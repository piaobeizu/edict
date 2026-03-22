# 通用可审议工作流内核 V2 · Backend 表结构与 API 草案

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 上游设计：`docs/design/generalized-reviewable-workflow-v2.md`

## 1. 文档目标

本文档把 V2 工作流设计进一步收敛到 `backend` 可直接落地的层面，覆盖：

- Postgres 表结构建议
- 与现有 `tasks` 表的关系
- 事件到投影的写入逻辑
- API 路由建议
- 兼容现有 Flutter / 看板的迁移路径

---

## 2. 总体策略

## 2.1 保留 `tasks`

不删除现有 `tasks` 表。

原因：

- 当前 `live-status`、详情页、首页列表都依赖它
- 当前 worker 和 compat API 都围绕它构建
- 一次性切换风险太高

## 2.2 `tasks` 降级为 projection

V2 中：

- `workflow_*` 表是事实来源
- `tasks` 是兼容读模型

也就是：

- 复杂工作流的主写入落在 `workflow_*`
- `tasks` 通过 projection worker 更新

这意味着：

- `tasks` 不是 source of truth
- V2 业务代码不允许直接更新 `tasks.state / now / output / todos`
- 所有这类字段都只能由 projection worker 单向写入

## 2.3 双轨运行

迁移期支持两类任务：

1. `legacy task`
继续走当前 `TaskService + orchestrator_worker + dispatch_worker`

2. `workflow v2 task`
走新工作流引擎，但同步更新 `tasks`

双轨运行的前提是事件与 worker 隔离，避免 V1 worker 误消费 V2 事件。

---

## 3. 数据库表结构

## 3.1 继续保留 `tasks`

现有表见 `backend/app/models/task.py`。

建议只做增量扩展，不大改已有字段：

### 建议新增字段

| 字段 | 类型 | 含义 |
|---|---|---|
| `workflow_id` | `String(64)` | 对应 `workflow_instances.id` |
| `workflow_type` | `String(32)` | `legacy` / `generic` / `video` / `coding` / `report` |
| `projection_version` | `Integer` | 当前投影版本号 |
| `current_revision_id` | `String(64)` | 当前激活方案 |
| `current_assembly_id` | `String(64)` | 当前最终装配版本 |
| `pending_review_count` | `Integer` | 待审批对象数 |
| `running_node_count` | `Integer` | 执行中的节点数 |

### 字段职责重解释

| 旧字段 | 新含义 |
|---|---|
| `state` | 顶层 workflow 状态投影 |
| `org` | 当前总负责人 / 当前阶段负责人 |
| `now` | 当前摘要进展 |
| `output` | 当前最重要的摘要产出 |
| `todos` | 由 workflow nodes 聚合出的简化快照 |
| `flow_log` | 顶层关键状态流转投影 |
| `progress_log` | 关键事件摘要投影 |

### 写入约束

在 V2 模式下，以下字段视为 projection-only：

- `state`
- `org`
- `now`
- `output`
- `todos`
- `flow_log`
- `progress_log`

除 projection worker 外，任何 service / worker 都不应对这些字段做业务语义更新。

## 3.2 `workflow_instances`

表示顶层工作流实例。

建议字段：

```sql
CREATE TABLE workflow_instances (
  id VARCHAR(64) PRIMARY KEY,
  task_id VARCHAR(32) NOT NULL UNIQUE,
  workflow_type VARCHAR(32) NOT NULL DEFAULT 'generic',
  title TEXT NOT NULL,
  goal TEXT NOT NULL DEFAULT '',
  state VARCHAR(32) NOT NULL,
  owner VARCHAR(64) NOT NULL DEFAULT '',
  current_revision_id VARCHAR(64) NOT NULL DEFAULT '',
  current_assembly_id VARCHAR(64) NOT NULL DEFAULT '',
  summary_output TEXT NOT NULL DEFAULT '',
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_instances_state ON workflow_instances(state);
CREATE INDEX ix_workflow_instances_type ON workflow_instances(workflow_type);
CREATE INDEX ix_workflow_instances_updated_at ON workflow_instances(updated_at DESC);
```

## 3.3 `workflow_revisions`

表示整体方案版本。

```sql
CREATE TABLE workflow_revisions (
  id VARCHAR(64) PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL,
  status VARCHAR(32) NOT NULL,
  created_by VARCHAR(64) NOT NULL DEFAULT '',
  source VARCHAR(32) NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  change_summary TEXT NOT NULL DEFAULT '',
  parent_revision_id VARCHAR(64) NOT NULL DEFAULT '',
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(workflow_id, revision_number)
);

CREATE INDEX ix_workflow_revisions_workflow_id ON workflow_revisions(workflow_id);
CREATE INDEX ix_workflow_revisions_status ON workflow_revisions(status);
```

## 3.4 `workflow_nodes`

表示工作流执行节点。

```sql
CREATE TABLE workflow_nodes (
  id VARCHAR(64) PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  revision_id VARCHAR(64) NOT NULL REFERENCES workflow_revisions(id) ON DELETE CASCADE,
  parent_node_id VARCHAR(64) NOT NULL DEFAULT '',
  kind VARCHAR(32) NOT NULL,
  state VARCHAR(32) NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  assignee VARCHAR(64) NOT NULL DEFAULT '',
  sequence INTEGER NOT NULL DEFAULT 0,
  acceptance_criteria TEXT NOT NULL DEFAULT '',
  selected_candidate_id VARCHAR(64) NOT NULL DEFAULT '',
  spec JSONB NOT NULL DEFAULT '{}'::jsonb,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_nodes_workflow_id ON workflow_nodes(workflow_id);
CREATE INDEX ix_workflow_nodes_revision_id ON workflow_nodes(revision_id);
CREATE INDEX ix_workflow_nodes_parent_node_id ON workflow_nodes(parent_node_id);
CREATE INDEX ix_workflow_nodes_state ON workflow_nodes(state);
CREATE INDEX ix_workflow_nodes_kind ON workflow_nodes(kind);
CREATE INDEX ix_workflow_nodes_workflow_seq ON workflow_nodes(workflow_id, sequence);
```

## 3.5 `workflow_candidates`

表示节点下的候选结果。

```sql
CREATE TABLE workflow_candidates (
  id VARCHAR(64) PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  node_id VARCHAR(64) NOT NULL REFERENCES workflow_nodes(id) ON DELETE CASCADE,
  status VARCHAR(32) NOT NULL,
  provider VARCHAR(64) NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  score DOUBLE PRECISION,
  prompt_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_candidates_workflow_id ON workflow_candidates(workflow_id);
CREATE INDEX ix_workflow_candidates_node_id ON workflow_candidates(node_id);
CREATE INDEX ix_workflow_candidates_status ON workflow_candidates(status);
```

## 3.6 `workflow_artifacts`

统一存储 revision / node / candidate / assembly 产物。

```sql
CREATE TABLE workflow_artifacts (
  id BIGSERIAL PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  owner_type VARCHAR(32) NOT NULL,
  owner_id VARCHAR(64) NOT NULL,
  kind VARCHAR(32) NOT NULL,
  path TEXT NOT NULL,
  mime VARCHAR(128) NOT NULL DEFAULT '',
  preview_url TEXT NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_artifacts_owner ON workflow_artifacts(owner_type, owner_id);
CREATE INDEX ix_workflow_artifacts_workflow_id ON workflow_artifacts(workflow_id);
```

说明：

- `owner_type` 可取 `revision / node / candidate / assembly`
- 这样后续不需要为每类对象建独立 artifact 表

## 3.7 `workflow_decisions`

表示审批、选择、回滚等操作记录。

```sql
CREATE TABLE workflow_decisions (
  id VARCHAR(64) PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  target_type VARCHAR(32) NOT NULL,
  target_id VARCHAR(64) NOT NULL,
  action VARCHAR(32) NOT NULL,
  actor VARCHAR(64) NOT NULL,
  comment TEXT NOT NULL DEFAULT '',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_decisions_workflow_id ON workflow_decisions(workflow_id);
CREATE INDEX ix_workflow_decisions_target ON workflow_decisions(target_type, target_id);
CREATE INDEX ix_workflow_decisions_action ON workflow_decisions(action);
```

## 3.8 `workflow_assemblies`

表示最终汇总产物。

`items` 不建议长期保留为任意 JSON。

建议在 ORM / repo 层至少收敛为固定结构：

```json
[
  {
    "order": 1,
    "nodeId": "node_1",
    "candidateId": "cand_3",
    "role": "primary"
  }
]
```

后续若 assembly 复杂度提升，可进一步拆出 `workflow_assembly_items` 表。

```sql
CREATE TABLE workflow_assemblies (
  id VARCHAR(64) PRIMARY KEY,
  workflow_id VARCHAR(64) NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  status VARCHAR(32) NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_assemblies_workflow_id ON workflow_assemblies(workflow_id);
CREATE INDEX ix_workflow_assemblies_status ON workflow_assemblies(status);
```

`items` 不建议长期保留为任意 JSON。

建议在 ORM / repo 层至少收敛为固定结构：

```json
[
  {
    "order": 1,
    "nodeId": "node_1",
    "candidateId": "cand_3",
    "role": "primary"
  }
]
```

后续若 assembly 复杂度提升，可进一步拆出 `workflow_assembly_items` 表。

---

## 4. SQLAlchemy 模型建议

建议新增以下模型文件：

- `backend/app/models/workflow_instance.py`
- `backend/app/models/workflow_revision.py`
- `backend/app/models/workflow_node.py`
- `backend/app/models/workflow_candidate.py`
- `backend/app/models/workflow_artifact.py`
- `backend/app/models/workflow_decision.py`
- `backend/app/models/workflow_assembly.py`

并在 `backend/app/models/__init__.py` 统一导出。

注意：

- 先不要在 ORM 层建立复杂 relationship，避免异步查询时引发额外加载复杂度
- 优先用显式查询，由 repo 聚合成 snapshot

---

## 5. Projection 设计

## 5.1 为什么需要 projection worker

当前前端和通知系统都依赖扁平 task 结构，因此需要把 workflow 事实表投影回 `tasks`。

projection worker 只能消费已提交并发布成功的 workflow 事件，不能读取事务中间态。

## 5.1.1 Projection 延迟 SLA

为了保证用户在 App 端看到一致体验，建议定义迁移期 SLA：

- `DB commit -> event published`：P95 < 500ms
- `event published -> projection updated`：P95 < 1000ms
- `projection updated -> WebSocket/轮询前端可见`：P95 < 1500ms

整体目标：

- 审批或关键动作到列表页/详情页可见：P95 < 3s

若超过此目标，前端需考虑：

- optimistic hint
- “已提交，正在同步”提示
- 详情页局部乐观更新

## 5.2 投影规则建议

### `tasks.state`

从 `workflow_instances.state` 直接映射：

| workflow state | task state |
|---|---|
| `draft` | `Pending` |
| `planning` | `Zhongshu` |
| `awaiting_plan_review` | `YuLan` 或 `Menxia`，按业务策略映射 |
| `executing` | `Doing` |
| `awaiting_selection` | `Review` |
| `assembling` | `Review` |
| `awaiting_final_review` | `YuLan` |
| `done` | `Done` |
| `blocked` | `Blocked` |
| `cancelled` | `Cancelled` |

注：

- 这里不是一一对应，而是为了兼容现有 UI 心智做业务投影
- 具体映射应由 `EdictProjectionPolicy` 决定

### `tasks.org`

优先级建议：

1. 当前待审批对象的负责人
2. 当前运行中 node 的 assignee
3. workflow.owner

### `tasks.now`

取最近关键事件的摘要，比如：

- “第 2 版方案等待御览”
- “共 8 个步骤，已完成 5 个，2 个待挑选”
- “正在拼接最终汇总结果”

### `tasks.output`

仅保留当前最重要的摘要结果：

- 优先展示最新已批准 assembly 的 summary
- 否则展示当前已批准 revision 摘要
- 再否则展示 workflow.summary_output

### `tasks.todos`

从 `workflow_nodes` 聚合：

- `approved` -> `completed`
- `running` -> `in-progress`
- `pending/ready/produced/awaiting_review` -> `not-started` 或 `in-progress`

### `tasks.progress_log`

从关键 workflow 事件摘要生成简化 activity：

- revision 创建
- revision 审批
- node 完成
- candidate 完成
- assembly 完成

### `tasks.flow_log`

仅记录顶层状态投影变化，不再尝试还原所有 node 细节。

## 5.3 Projection 更新方式

建议新增：

- `projection_worker.py`

监听：

- `workflow.v2.*`

执行：

- 查询 snapshot
- 生成 task projection
- upsert 到 `tasks`

---

## 6. Repo 层建议

建议新增：

- `backend/app/repos/workflow_repo.py`
- `backend/app/services/task_projection_service.py`
- `backend/app/services/outbox_publisher.py`

### `WorkflowRepo`

职责：

- 从多张表聚合为 snapshot
- 保存 workflow/revision/node/candidate/decision/assembly
- 在 repo 层支持 selective load，避免每次全量查询

### `TaskProjectionService`

职责：

- 将 snapshot 映射为 `Task`
- 控制兼容字段的写法

### `OutboxPublisher`

职责：

- 轮询或订阅 outbox 表
- 将待发布事件发往 Redis Streams / PubSub
- 标记事件已发布

### `workflow_outbox` 表建议

```sql
CREATE TABLE workflow_outbox (
  id BIGSERIAL PRIMARY KEY,
  aggregate_type VARCHAR(32) NOT NULL DEFAULT 'workflow',
  aggregate_id VARCHAR(64) NOT NULL,
  topic VARCHAR(128) NOT NULL,
  event_type VARCHAR(128) NOT NULL,
  trace_id VARCHAR(64) NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  headers JSONB NOT NULL DEFAULT '{}'::jsonb,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  retry_count INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  last_error TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_workflow_outbox_status_available_at
  ON workflow_outbox(status, available_at);

CREATE INDEX ix_workflow_outbox_aggregate
  ON workflow_outbox(aggregate_type, aggregate_id);
```

建议状态：

- `pending`
- `publishing`
- `published`
- `dead_letter`

### publisher 配置建议

- poll interval：`200ms - 500ms`
- batch size：`50`
- max retries：`10`
- backoff：指数退避，上限 `30s`
- 超过最大重试进入 `dead_letter`

---

## 7. Worker 设计

## 7.1 `workflow_orchestrator_worker.py`

职责：

- 消费 `workflow.v2.*`
- 调用 `GraphWorkflowEngine.apply_event()`
- 执行 policy 规划
- 触发后续 actions

## 7.2 `node_dispatch_worker.py`

职责：

- 消费 `workflow.node.dispatched`
- 调用 node executor
- 写入 candidate / progress / node state

它类似当前 `dispatch_worker.py`，但粒度从 task 变成 node。

## 7.3 `assembly_worker.py`

职责：

- 消费 `workflow.assembly.requested`
- 读取选中的 candidates
- 组装最终结果
- 写入 `workflow_assemblies` 与 artifacts

## 7.4 `projection_worker.py`

职责：

- 可同时消费 `task.*` 与 `workflow.v2.*`，但映射逻辑分离
- 刷新 `tasks` projection
- 保持旧 API 兼容

## 7.5 `outbox_publisher_worker.py`

职责：

- 消费数据库 outbox
- 发布 Redis Stream / PubSub 事件
- 保证“DB commit 成功”与“事件最终可见”之间的桥接

建议运行参数：

- 常驻轮询，默认 250ms
- 单批最多发布 50 条
- 连续失败时退避但不阻塞主业务事务

---

## 8. API 设计

## 8.1 保留现有任务 API

现有保留：

- `GET /api/tasks/live-status`
- `GET /api/task-activity/{task_id}`
- `GET /api/scheduler-state/{task_id}`
- `POST /api/task-action`
- `POST /api/review-action`

这些接口继续服务现有移动端和面板。

但 V2 任务不应再通过这些接口直接修改 `tasks` 主字段；这些接口如要兼容 V2，应转发成 workflow decision / command。

### `TaskService` / `compat.py` guard 建议

为避免迁移期出现同表双写，建议加入代码层防护：

1. `tasks.workflow_type = 'legacy'`
   才允许现有 `TaskService` 继续直接更新 `tasks.state / now / output / todos`

2. 若 `tasks.workflow_type != 'legacy'`
   则以下路径应拒绝直接写 projection-only 字段，并返回明确错误：

- `TaskService.transition_state()`
- `TaskService.add_progress()`
- `TaskService.update_todos()`
- `dispatch_worker._backfill_task_output()`
- `compat.py` 中直接基于 `TaskState` 的状态推进逻辑

3. 对 V2 任务，`compat.py` 的兼容动作应改为：

- 识别 `workflow_type != 'legacy'`
- 转发到 workflow decision / command service
- 由 V2 engine 更新事实表，再由 projection worker 刷新 `tasks`

这样可以把“文档约束”变成“代码层硬约束”。

## 8.2 新增工作流 API

建议新增以下路由文件：

- `backend/app/api/workflows.py`
- `backend/app/api/workflow_revisions.py`
- `backend/app/api/workflow_nodes.py`
- `backend/app/api/workflow_candidates.py`
- `backend/app/api/workflow_assemblies.py`
- `backend/app/api/workflow_decisions.py`

## 8.3 顶层 API

### 创建工作流

`POST /api/workflows`

请求体：

```json
{
  "title": "制作一期磨豆腐视频",
  "goal": "拆解、生成、审批并最终输出完整视频",
  "workflowType": "video",
  "priority": "high",
  "meta": {
    "channel": "mobile"
  }
}
```

返回：

```json
{
  "ok": true,
  "workflowId": "wf_xxx",
  "taskId": "JJC-20260318-001"
}
```

### 工作流详情

`GET /api/workflows/{workflow_id}`

返回顶层摘要：

```json
{
  "ok": true,
  "workflow": {
    "id": "wf_xxx",
    "taskId": "JJC-20260318-001",
    "type": "video",
    "title": "制作一期磨豆腐视频",
    "state": "executing",
    "owner": "shangshu",
    "currentRevisionId": "rev_2",
    "currentAssemblyId": "",
    "summaryOutput": "共 8 个步骤，已完成 5 个，2 个待挑选"
  }
}
```

### 工作流图

`GET /api/workflows/{workflow_id}/graph`

返回：

- workflow
- revisions
- nodes
- candidates
- current assembly

供新版详情页直接使用。

## 8.4 Revision API

### 创建 revision

`POST /api/workflows/{workflow_id}/revisions`

### revision 列表

`GET /api/workflows/{workflow_id}/revisions`

### revision 审批

`POST /api/revisions/{revision_id}/approve`

### revision 驳回

`POST /api/revisions/{revision_id}/reject`

请求体：

```json
{
  "comment": "第 3 步还不够具体，请补充分镜头脚本"
}
```

## 8.5 Node API

### 节点列表

`GET /api/workflows/{workflow_id}/nodes`

### 手动派发节点

`POST /api/nodes/{node_id}/dispatch`

### 节点审批

`POST /api/nodes/{node_id}/approve`

### 节点驳回

`POST /api/nodes/{node_id}/reject`

### 节点重生成

`POST /api/nodes/{node_id}/regenerate`

## 8.6 Candidate API

### 候选列表

`GET /api/nodes/{node_id}/candidates`

### 选择候选

`POST /api/candidates/{candidate_id}/select`

### 驳回候选

`POST /api/candidates/{candidate_id}/reject`

## 8.7 Assembly API

### 创建汇总结果

`POST /api/workflows/{workflow_id}/assemblies`

### assembly 列表

`GET /api/workflows/{workflow_id}/assemblies`

### assembly 审批

`POST /api/assemblies/{assembly_id}/approve`

### assembly 驳回

`POST /api/assemblies/{assembly_id}/reject`

## 8.8 Rollback API

建议统一为：

`POST /api/workflows/{workflow_id}/rollback`

请求体：

```json
{
  "targetType": "revision",
  "targetId": "rev_1",
  "comment": "回到第一版整体方案"
}
```

或：

```json
{
  "targetType": "node",
  "targetId": "node_3",
  "comment": "只回滚第三步"
}
```

## 8.9 决策 API 收敛建议

虽然本文档保留了 `approve/reject/select` 形式的显式端点，便于前端直观调用，但后端语义层建议统一收敛为 decision command。

也就是说，内部最终都可以归一到：

- `POST /api/workflow-decisions`

请求体：

```json
{
  "workflowId": "wf_xxx",
  "targetType": "candidate",
  "targetId": "cand_1",
  "action": "select",
  "comment": "这一版最佳"
}
```

显式端点可以作为兼容包装层，内部调用统一 decision service。

---

## 9. `task-activity` API 演进方案

现有：

- `GET /api/task-activity/{task_id}`

不建议立即废弃。

## 9.1 迁移期实现

内部改为：

1. 根据 `task.workflow_id` 查 workflow snapshot
2. 将 revisions / nodes / candidates / decisions / assemblies 映射成扁平 activity
3. 继续返回当前前端能消费的字段

## 9.2 活动映射建议

| workflow 事件 | task activity kind |
|---|---|
| revision 创建 | `progress` |
| revision 审批 | `flow` |
| node 进入 running | `progress` |
| candidate 完成 | `progress` 或新增 `candidate` |
| candidate 被选中 | `progress` |
| assembly 完成 | `progress` |
| rollback | `flow` |

迁移完成后，可再给新版详情页单独提供：

- `GET /api/workflows/{id}/timeline`

---

## 10. WebSocket 设计

## 10.1 继续复用现有 `/ws`

当前 `backend/app/api/websocket.py` 已能转发 Redis Pub/Sub。

V2 可直接新增 topic，无需重写 WebSocket 服务。

但必须确保 topic namespace 隔离。

## 10.2 建议前端消费的重点事件

- `workflow.v2.state.changed`
- `workflow.v2.revision.created`
- `workflow.v2.revision.approved`
- `workflow.v2.revision.rejected`
- `workflow.v2.node.progress`
- `workflow.v2.candidate.completed`
- `workflow.v2.candidate.selected`
- `workflow.v2.assembly.completed`
- `workflow.v2.rollback`
- `workflow.v2.projection.updated`

## 10.3 与 `tasks` 事件的关系

迁移期建议同时推：

- `workflow.v2.*`
- `task.*`

这样：

- 新页面可用 `workflow.v2.*`
- 旧页面继续靠 `task.*`

同时要求：

- V2 payload 带 `workflow_version = 2`
- V1 worker 不订阅 `workflow.v2.*`
- V2 worker 不订阅 `task.*`

---

## 11. 文件与媒体接口建议

V2 会让产物明显增多，因此建议在现有 `files.py` 基础上进一步增强。

## 11.1 下载接口

保留：

- `GET /api/files/download?path=...`

建议增强：

- 正确 MIME
- 支持 inline preview
- 允许通过 artifact id 访问，而不是只暴露绝对路径

## 11.2 新增 artifact 访问接口

建议新增：

- `GET /api/artifacts/{artifact_id}`
- `GET /api/artifacts/{artifact_id}/meta`

这样能减少前端对绝对路径的依赖。

---

## 12. Alembic 迁移建议

建议按以下顺序建表：

1. `workflow_instances`
2. `workflow_revisions`
3. `workflow_nodes`
4. `workflow_candidates`
5. `workflow_artifacts`
6. `workflow_decisions`
7. `workflow_assemblies`
8. `tasks` 增量字段
9. `workflow_outbox`

理由：

- 先建事实表
- 后建引用表
- 最后扩 projection 表

---

## 13. 第一批建议落地范围

若只做最小闭环，建议后端第一批先实现：

1. `workflow_instances`
2. `workflow_revisions`
3. `workflow_nodes`
4. `workflow_candidates`
5. `workflow_decisions`
6. `workflow_repo`
7. `workflow_orchestrator_worker`
8. `projection_worker`
9. `workflows/revisions/nodes/candidates` API
10. `workflow_outbox + outbox_publisher_worker`

暂缓：

- `workflow_assemblies`
- `artifact id` 访问体系
- 复杂 rollback

原因：

- 先跑通“方案审批 + 步骤执行 + 候选选优”就能覆盖大多数复杂工作流
- assembly 可以作为第二阶段补上

---

## 14. 与现有代码目录的具体映射

### 模型

- `backend/app/models/task.py` 保留并扩字段
- `backend/app/models/workflow_instance.py` 新增
- `backend/app/models/workflow_revision.py` 新增
- `backend/app/models/workflow_node.py` 新增
- `backend/app/models/workflow_candidate.py` 新增
- `backend/app/models/workflow_artifact.py` 新增
- `backend/app/models/workflow_decision.py` 新增
- `backend/app/models/workflow_assembly.py` 新增

### repo / service

- `backend/app/repos/workflow_repo.py` 新增
- `backend/app/services/task_projection_service.py` 新增

### worker

- `backend/app/workers/workflow_orchestrator_worker.py` 新增
- `backend/app/workers/node_dispatch_worker.py` 新增
- `backend/app/workers/projection_worker.py` 新增
- `backend/app/workers/assembly_worker.py` 新增

### api

- `backend/app/api/workflows.py` 新增
- `backend/app/api/workflow_revisions.py` 新增
- `backend/app/api/workflow_nodes.py` 新增
- `backend/app/api/workflow_candidates.py` 新增
- `backend/app/api/workflow_assemblies.py` 新增

---

## 15. 最终结论

Backend 层的关键不是直接废弃 `tasks`，而是：

1. 保留 `tasks` 作为 projection。
2. 新建 `workflow_*` 表作为事实来源。
3. 用 projection worker 把复杂 workflow 摘要同步到 `tasks`。
4. 用新的 workflow API 逐步替代旧详情 API。

如果没有“单向 projection + 事务 + outbox + V1/V2 事件隔离”这四个约束，V2 的 backend 很容易重新落回双写失控和 worker 串线的问题。

这样既能兼容当前 App 和看板，又能为复杂任务提供真正可演进的后端数据结构。
