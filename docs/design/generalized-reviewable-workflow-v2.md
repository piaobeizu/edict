# 通用可审议工作流内核 V2 设计方案

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 适用范围：`kernel/`、`backend/app/`、`flutter_app/`

## 关联文档

- [三省六部架构总览](../architecture/overview.md)
- [三省六部任务分发流转体系](../architecture/task-dispatch-architecture.md)
- [文生图 / 文生视频升级方案](media-generation-upgrade.md)
- [Kernel 类与接口草案](generalized-reviewable-workflow-v2-kernel-interfaces.md)
- [Backend 表结构与 API 草案](generalized-reviewable-workflow-v2-backend-schema-api.md)
- [前端 Dashboard / App 变更方案](frontend-dashboard-app-workflow-v2.md)
- [前端实现协议](frontend-workflow-v2-runtime-protocol.md)
- [Flutter 迁移方案](flutter-workflow-v2-migration.md)

---

## 1. 背景

当前 Edict 已具备以下能力：

- 基于 `kernel/src/state_machine.py` 的通用有限状态机
- 基于 `kernel/src/workflow.py` 的线性工作流引擎
- 基于 `kernel/src/ports.py` 的 Repo / Bus / Routing / Executor 解耦
- 基于 `backend/app/workers/orchestrator_worker.py` 与 `dispatch_worker.py` 的事件驱动执行链
- 基于 `backend/app/api/compat.py` 的审批、叫停、恢复、回滚入口
- 基于 `backend/app/api/websocket.py` 的实时事件推送基础设施

这套实现可以很好地支撑“单任务、单状态链、单次派发”的流程，例如：

- 皇上下旨
- 太子分拣
- 中书起草
- 门下审议
- 尚书派发
- 六部执行
- 汇总回奏

但它不适合承载下面这类更通用的复杂任务：

- 一个任务先生成方案，再经过多轮审批修订
- 一个方案拆解为多个可独立执行的步骤
- 每个步骤可并行产生多个候选结果
- 用户可逐步挑选最佳候选，或只对局部步骤要求重做
- 所有步骤合格后再生成最终汇总结果
- 最终结果被驳回时，可回滚到局部步骤或历史版本
- 任一步骤完成都需要主动推送到 App

这类模式并不局限于视频任务，也适用于：

- 文档写作
- 调研报告
- 代码交付
- 测试执行
- 设计稿生成
- 发布流程
- 多系统运维变更

因此，需要在保留当前内核优点的前提下，设计一套更通用的“可审议、可分支、可回滚、可汇总”的工作流内核 V2。

---

## 2. 设计目标

### 2.1 总目标

将 Edict 从“线性任务流转系统”演进为“通用可审议工作流系统”。

### 2.2 具体目标

1. 保留当前 `kernel` 的分层思想，不推翻已有 StateMachine / Ports / EventBus 抽象。
2. 保留 `task` 作为现有前后端的兼容投影和稳定业务锚点。
3. 新增“方案 revision、步骤节点、候选结果、审批记录、最终装配物”等一等公民。
4. 支持 fan-out / fan-in，即拆解、并行执行、聚合汇总。
5. 支持局部重做，而不是一旦不满意就整任务重来。
6. 支持逐级审批和最终审批。
7. 支持基于事件的实时更新与移动端展示。
8. 支持不同任务类型通过 policy 扩展，而不是把业务语义写死在 kernel 中。

### 2.3 非目标

本方案不直接规定：

- 某个具体第三方视频 API 的接入细节
- 某个具体 Agent 的 prompt / SOUL.md 写法
- 某种具体媒体存储产品的选型
- 某个 Flutter 页面像素级 UI 细节

这些应由业务层和后续专题设计文档解决。

---

## 3. 当前实现的核心问题

## 3.1 `TaskEntity` 过于单体

当前 `kernel/src/task_entity.py` 中的 `TaskEntity` 同时承担：

- 顶层任务定义
- 状态记录
- 进展记录
- 子任务快照
- 最终输出
- 调度元数据

这适合线性流程，不适合复杂工作流。

主要问题：

- 无法自然表达“一个任务的多轮方案版本”
- 无法自然表达“一个任务下的多个工作节点”
- 无法自然表达“一个节点下的多个候选结果”
- 无法自然表达“某次审批针对的是方案、步骤还是最终汇总物”
- 无法自然表达“局部回滚”

## 3.2 `WorkflowEngine` 仍然是单派发模型

当前 `kernel/src/workflow.py` 的 `dispatch()` 明确假设一次只派发一个目标 agent。

这会导致：

- 无法原生支持步骤并行
- 无法原生支持多 provider 竞争生成
- 无法原生支持汇总条件触发

## 3.3 `RoutingPolicy` 只支持线性决策

当前 `RoutingPolicy` 只有：

- `next_agent()`
- `next_state_after_completion()`
- `suggest_assignee()`

这个抽象只适用于“完成当前步骤后去哪一步”，不适用于：

- 生成多个子节点
- 创建审批门
- 选择候选
- 汇总装配
- 版本回滚

## 3.4 `task` 被当成唯一事实来源

当前后端 ORM `backend/app/models/task.py` 与前端 `flutter_app/lib/models/task.dart` 都默认：

- 一个任务就是全部
- 任务详情页就是这个任务的完整信息

这会导致后续复杂工作流只能不断往 JSON 字段里叠加结构，最终失控。

---

## 4. 总体设计思路

## 4.1 设计原则

1. `kernel v1` 继续保留，服务简单线性任务。
2. 新增 `kernel v2`，服务复杂可审议工作流。
3. `task` 继续保留，但降级为“根任务 + 摘要投影”。
4. 工作流细节拆成独立对象，由图结构表示。
5. `kernel` 只定义通用对象和通用动作，不引入三省六部、视频、代码等业务语义。
6. 业务类型通过 `Policy` 扩展。

## 4.2 总体分层

```text
┌──────────────────────────────────────────────────────────┐
│ Product Layer                                            │
│ 视频任务 / 文档任务 / 代码任务 / 调研任务 / 发布任务       │
└───────────────────────┬──────────────────────────────────┘
                        │ use
┌───────────────────────▼──────────────────────────────────┐
│ Business Policy Layer                                    │
│ EdictWorkflowPolicy / VideoPolicy / CodingPolicy ...     │
└───────────────────────┬──────────────────────────────────┘
                        │ use
┌───────────────────────▼──────────────────────────────────┐
│ Kernel V2                                                │
│ Workflow / Node / Candidate / Decision / Assembly        │
│ Graph Engine / State Machines / Workflow Actions         │
└───────────────────────┬──────────────────────────────────┘
                        │ via ports
┌───────────────────────▼──────────────────────────────────┐
│ Adapters                                                 │
│ Postgres Repo / Redis Bus / OpenClaw Executor / Files    │
└──────────────────────────────────────────────────────────┘
```

---

## 5. `task` 的定位

这是本设计的关键。

未来不取消 `task`，但要重新定义它的职责，并明确它不再是复杂工作流的事实来源。

## 5.1 `task` 是什么

`task` 在 V2 中不再是 aggregate root，而是：

- 一个稳定的外部业务编号
- 一个兼容当前前后端的展示对象
- 一个指向真实 workflow 的 projection/read model

示例：

- 制作一期磨豆腐视频
- 产出一份调研报告
- 完成一个需求开发
- 执行一次发布

`task` 负责表达：

- 这件事是什么
- 当前整体进行到哪
- 当前总负责人是谁
- 当前最关键的摘要信息
- 当前对用户显示的总状态

复杂工作流的真正事实来源是 `workflow_instance`。

## 5.2 `task` 不再是什么

`task` 不再直接承载：

- 全部步骤明细
- 全部候选结果
- 全部审批历史
- 全部版本历史
- 全部装配细节

这些信息应拆分给下层对象。

同时，V2 中应遵守一个强约束：

- 业务写入先落到 `workflow_*`
- `task` 只能由 projection worker 单向刷新
- 业务代码不允许对 `task.state / now / output / todos` 做语义性直写

## 5.3 `task` 与 `workflow_instance` 的关系

### `workflow_instance`

它是：

- aggregate root
- source of truth
- workflow graph 的根节点
- revisions / nodes / candidates / decisions / assemblies 的归属主体

### `task`

它是：

- workflow 的兼容外壳
- UI 和旧 API 的 projection/read model
- 对外稳定的业务编号

### 二者关系

- 一个 `task` 对应一个 `workflow_instance`
- `workflow_instance.task_id` 指向 `task.id`
- 下游复杂对象统一挂在 `workflow_instance` 下
- `task` 不挂接复杂子对象，只暴露汇总结果

`task` 继续支撑：

- `live-status`
- 任务列表
- 首页摘要卡片
- 兼容现有详情页的基础字段

---

## 6. Kernel V2 领域模型

## 6.1 核心对象总览

建议在 `kernel/src/` 中新增以下对象：

- `WorkflowEntity`
- `NodeEntity`
- `CandidateEntity`
- `DecisionEntity`
- `AssemblyEntity`
- `ArtifactRef`

## 6.2 `WorkflowEntity`

表示一个完整工作流实例，对应一个顶层任务。

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | workflow id，与 task id 对应或映射 |
| `task_id` | 顶层任务 id |
| `type` | 任务类型，如 `generic`, `video`, `coding`, `report` |
| `state` | 工作流整体状态 |
| `title` | 标题 |
| `goal` | 目标描述 |
| `current_revision_id` | 当前激活方案版本 |
| `current_assembly_id` | 当前最终装配版本 |
| `owner` | 当前总负责人 |
| `summary_output` | 当前对用户展示的摘要 |
| `meta` | 额外元数据 |

## 6.3 `Revision`

表示某一轮整体方案。

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | revision id |
| `workflow_id` | 所属 workflow |
| `number` | 第几版 |
| `status` | draft / awaiting_review / approved / rejected / superseded |
| `created_by` | 由谁创建 |
| `source` | 人工创建 / agent 生成 / 基于上一版修改 |
| `content` | 方案内容 |
| `change_summary` | 相对上一版的变化摘要 |

## 6.4 `NodeEntity`

表示工作流中的一个执行节点。

节点类型不带业务专用语义，建议支持：

- `plan`
- `work_item`
- `review_gate`
- `candidate_group`
- `assembly`

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | node id |
| `workflow_id` | 所属 workflow |
| `revision_id` | 来源 revision |
| `parent_node_id` | 父节点，可为空 |
| `kind` | 节点类型 |
| `title` | 节点标题 |
| `description` | 节点描述 |
| `state` | pending / ready / running / produced / awaiting_review / approved / rejected / superseded |
| `assignee` | 当前执行人 / 部门 |
| `sequence` | 顺序 |
| `spec` | 节点规格，JSON |
| `acceptance_criteria` | 验收标准 |
| `selected_candidate_id` | 当前选中的候选结果 |

## 6.5 `CandidateEntity`

表示某个节点下的候选结果。

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | candidate id |
| `node_id` | 所属 node |
| `workflow_id` | 所属 workflow |
| `provider` | 由哪个 provider / agent 生成 |
| `status` | queued / running / succeeded / failed / approved / rejected |
| `summary` | 候选摘要 |
| `artifact_refs` | 关联产物 |
| `metrics` | 耗时、成本、tokens、尺寸等 |
| `score` | 机器或人工评分 |
| `prompt_snapshot` | 生成时的参数快照 |

## 6.6 `DecisionEntity`

表示一次人工或系统决策。

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | decision id |
| `workflow_id` | 所属 workflow |
| `target_type` | workflow / revision / node / candidate / assembly |
| `target_id` | 被决策对象 id |
| `action` | approve / reject / select / rollback / regenerate / cancel |
| `comment` | 批注 |
| `actor` | 谁做的决定 |
| `payload` | 扩展数据 |

## 6.7 `AssemblyEntity`

表示最终汇总结果。

建议字段：

| 字段 | 含义 |
|---|---|
| `id` | assembly id |
| `workflow_id` | 所属 workflow |
| `status` | draft / building / ready / approved / rejected / superseded |
| `items` | 使用了哪些 node/candidate |
| `artifact_refs` | 最终产物 |
| `summary` | 汇总摘要 |
| `meta` | 装配参数 |

## 6.8 `ArtifactRef`

统一引用产物，不限媒体。

建议字段：

| 字段 | 含义 |
|---|---|
| `kind` | text / image / video / audio / json / archive / link |
| `path` | 本地路径或 URL |
| `mime` | MIME 类型 |
| `preview_url` | 预览地址 |
| `metadata` | 时长、分辨率、大小等 |

---

## 7. 工作流状态模型

## 7.1 Workflow 级状态

建议采用比当前更抽象的整体状态：

| 状态 | 含义 |
|---|---|
| `draft` | 已创建但未进入正式流程 |
| `planning` | 正在生成或修改整体方案 |
| `awaiting_plan_review` | 等待审批方案 |
| `executing` | 已批准方案，节点执行中 |
| `awaiting_selection` | 节点候选已出，等待挑选 |
| `assembling` | 正在生成最终汇总结果 |
| `awaiting_final_review` | 等待最终审批 |
| `done` | 最终完成 |
| `blocked` | 阻塞 |
| `cancelled` | 取消 |

### Workflow 合法迁移

```text
draft -> planning | cancelled
planning -> awaiting_plan_review | blocked | cancelled
awaiting_plan_review -> planning | executing | blocked | cancelled
executing -> awaiting_selection | assembling | blocked | cancelled
awaiting_selection -> executing | assembling | blocked | cancelled
assembling -> awaiting_final_review | blocked | cancelled
awaiting_final_review -> executing | done | blocked | cancelled
blocked -> planning | executing | assembling | cancelled
```

## 7.2 Node 级状态

节点建议采用独立状态机：

| 状态 | 含义 |
|---|---|
| `pending` | 尚未可执行 |
| `ready` | 已就绪，等待派发 |
| `running` | 正在执行 |
| `produced` | 已产出候选或结果 |
| `awaiting_review` | 等待节点审批 |
| `approved` | 节点通过 |
| `rejected` | 节点被驳回 |
| `superseded` | 已被更高版本替代 |
| `failed` | 执行失败 |
| `cancelled` | 已取消 |

### Node 合法迁移

```text
pending -> ready | cancelled
ready -> running | cancelled
running -> produced | failed | cancelled
produced -> awaiting_review | approved | rejected | superseded
awaiting_review -> approved | rejected | superseded
rejected -> ready | superseded | cancelled
failed -> ready | superseded | cancelled
approved -> superseded
```

## 7.3 Candidate 级状态

候选建议使用：

- `queued`
- `running`
- `succeeded`
- `failed`
- `approved`
- `rejected`
- `superseded`

### Candidate 合法迁移

```text
queued -> running | cancelled
running -> succeeded | failed | cancelled
succeeded -> approved | rejected | superseded
failed -> queued | superseded | cancelled
approved -> superseded
rejected -> queued | superseded | cancelled
```

---

## 8. Kernel V2 引擎设计

## 8.1 保留 `WorkflowEngine` V1

保留当前 `kernel/src/workflow.py`，继续用于：

- 简单线性任务
- 现有三省六部流程
- 兼容当前业务

## 8.2 新增 `GraphWorkflowEngine`

建议新增 `kernel/src/graph_workflow.py`，提供以下高层能力：

- 创建 workflow
- 创建 revision
- 基于 revision 生成 nodes
- 派发 node
- 上报 candidate
- 提交 decision
- 触发 assembly
- 执行 rollback
- 生成 task projection

## 8.3 新增强类型 `WorkflowAction`

当前 `RoutingPolicy` 不够表达复杂流程。

建议新增一个动作抽象，但不再采用 `kind: str + payload: dict[str, Any]` 作为主表达。

应采用：

- 强类型 dataclass 子类
- 每种 action 有明确字段
- engine 对 action 做穷举处理

例如：

- `CreateRevisionAction`
- `SpawnNodeAction`
- `TransitionWorkflowAction`
- `TransitionNodeAction`
- `DispatchNodeAction`
- `CreateCandidateAction`
- `SelectCandidateAction`
- `BuildAssemblyAction`
- `RollbackTargetAction`
- `RefreshProjectionAction`

这些强类型 action 可以覆盖如下通用动作语义：

| 动作 | 含义 |
|---|---|
| `spawn_node` | 创建节点 |
| `dispatch_node` | 派发节点 |
| `transition_node` | 节点状态迁移 |
| `create_revision` | 创建方案版本 |
| `request_review` | 发起审批 |
| `create_candidates` | 创建候选任务 |
| `select_candidate` | 选择候选 |
| `build_assembly` | 生成汇总结果 |
| `rollback_target` | 回滚到指定对象 |
| `publish_projection` | 更新 task 摘要 |

## 8.4 Policy 升级

保留 `RoutingPolicy`，但新增 `WorkflowPolicy`。

建议接口：

```python
class WorkflowPolicy(Protocol):
    def plan_actions(
        self,
        workflow: WorkflowEntity,
        event: WorkflowEvent,
        snapshot: WorkflowSnapshot,
    ) -> list[WorkflowAction]:
        ...
```

含义：

- kernel 提供状态、节点、事件
- policy 决定下一步动作
- 视频、代码、文档、调研都只是不同 policy

## 8.5 三省六部如何映射

三省六部不进入 kernel，保留在 policy 层：

- `EdictLinearPolicy`：兼容当前线性流程
- `EdictReviewableWorkflowPolicy`：支持 revision、节点、候选、汇总

其中：

- 太子：任务分类、建 workflow、提炼目标
- 中书：生成 revision、拆解 work items
- 门下：审批 revision / 节点方案
- 尚书：调度 node 到执行方
- 六部：实际执行 work items 或生成 candidates
- 皇帝：审批 revision、选择 candidate、审批 assembly

---

## 9. 持久化设计

## 9.1 保留 `tasks` 作为兼容投影

`backend/app/models/task.py` 保留，但职责调整：

- 不再作为复杂工作流的唯一事实来源
- 变成 workflow 的读模型 / 投影模型
- 继续服务 `live-status` 和基础详情

建议保留字段：

- `id`
- `title`
- `state`
- `org`
- `official`
- `now`
- `eta`
- `block`
- `output`
- `priority`
- `archived`
- `updated_at`

建议新增或重解释的字段：

- `source_workflow_id`
- `projection_version`
- `current_revision_id`
- `current_assembly_id`
- `pending_review_count`
- `running_node_count`

## 9.2 新增工作流表

建议新增：

- `workflow_instances`
- `workflow_revisions`
- `workflow_nodes`
- `workflow_candidates`
- `workflow_decisions`
- `workflow_assemblies`
- `workflow_artifacts`

## 9.3 `tasks` 与工作流表的关系

```text
tasks (projection)
  1 ── 1 workflow_instances
  1 ── N workflow_revisions
  1 ── N workflow_nodes
  1 ── N workflow_decisions
  1 ── N workflow_assemblies

workflow_nodes
  1 ── N workflow_candidates
```

---

## 10. 事件模型

## 10.1 继续保留当前事件总线

当前 `backend/app/services/event_bus.py` 的方向是正确的，应继续沿用 Redis Streams + Pub/Sub fanout。

但 V2 必须补上两个当前设计里没有被制度化的约束：

1. 同一业务事件产生的多条数据库写入必须包在同一个 DB transaction 中。
2. 事件发布必须与数据库提交解耦，使用 outbox pattern 或等价机制，避免半成功。

### 事务与 Outbox 原则

推荐流程：

1. worker 收到一条输入事件
2. engine 计算 actions
3. 在单个 DB transaction 内写入 workflow 事实表和 outbox 表
4. transaction commit 成功
5. outbox publisher 异步把待发布事件发到 Redis Streams / PubSub
6. projection worker、websocket、通知系统只消费已发布事件

这样可以避免：

- action 执行到一半失败留下半残状态
- 先 publish 后 DB rollback
- DB 成功但事件丢失

## 10.2 新增 V2 事件 topic

建议新增标准 topic：

- `workflow.v2.created`
- `workflow.v2.state.changed`
- `workflow.v2.revision.created`
- `workflow.v2.revision.review.requested`
- `workflow.v2.revision.approved`
- `workflow.v2.revision.rejected`
- `workflow.v2.node.created`
- `workflow.v2.node.ready`
- `workflow.v2.node.dispatched`
- `workflow.v2.node.progress`
- `workflow.v2.node.approved`
- `workflow.v2.node.rejected`
- `workflow.v2.candidate.created`
- `workflow.v2.candidate.completed`
- `workflow.v2.candidate.selected`
- `workflow.v2.assembly.requested`
- `workflow.v2.assembly.completed`
- `workflow.v2.rollback`
- `workflow.v2.projection.updated`

## 10.3 V1 / V2 事件隔离

迁移期必须显式隔离 V1 与 V2 事件，避免旧 worker 误消费新事件。

建议同时采用两层隔离：

### topic 前缀隔离

- V1 保持现有 `task.*`
- V2 使用 `workflow.v2.*`

### payload 版本字段

所有 V2 事件 payload 统一带：

```json
{
  "workflow_version": 2
}
```

worker 消费规则：

- `orchestrator_worker.py` 只处理 V1 topic
- `workflow_orchestrator_worker.py` 只处理 V2 topic
- projection worker 可同时消费两者，但分开映射

## 10.4 与现有 `task.*` 事件的关系

迁移期采用双写策略：

- V2 工作流事件驱动实际流程
- 同时投影生成现有 `task.*` 事件，兼容当前看板和移动端

示例：

- `workflow.node.progress` -> 更新 `task.progress_log`
- `workflow.revision.approved` -> 更新 `task.state`
- `workflow.assembly.completed` -> 更新 `task.output`

---

## 11. 执行模型

## 11.1 一个 node 对应一次执行单元

V2 中的最小执行粒度不再是整个 task，而是 node。

这意味着：

- 一个 workflow 可有多个 nodes
- 一个 node 可生成多个 candidates
- 一个 candidate 可由不同 provider 生成

## 11.2 fan-out 模型

示例：

1. revision 被批准
2. policy 生成多个 `work_item` nodes
3. 每个 node 进入 `ready`
4. orchestrator 按 policy fan-out 派发多个 node
5. 每个 node 可能再生成多个 candidate 子任务

## 11.3 fan-in 模型

示例：

1. 所有关键 nodes 至少有一个 approved candidate
2. policy 判定满足 assembly 条件
3. 生成 `assembly` node
4. assembly 完成后进入最终审批

## 11.4 局部重做

局部重做时：

- 不重建整个 task
- 不废弃整个 workflow
- 只对目标 node 或 candidate 生成新 revision / 新 candidate

## 11.5 Revision 与 Node 的 cascade 规则

这是 V2 领域模型必须在 Phase 0 冻结前明确的规则。

默认策略建议采用“保守 supersede，不隐式复用”：

### 规则一：revision 被 reject 后

- 该 revision 下所有未批准 nodes 统一标记为 `superseded`
- 该 revision 下所有未批准 candidates 统一标记为 `superseded`
- 已进入终态的 assembly 若来源于该 revision，也标记为 `superseded`

这样可以避免：

- 驳回后旧节点继续偷偷参与后续装配
- 新旧 revision 的节点混用而无审计痕迹

### 规则二：新 revision 创建时

- 默认不自动复用旧 revision 中的 nodes
- policy 如需复用，必须显式创建“复用节点”动作，而不是隐式沿用旧节点

### 规则三：复用 approved node 的方式

若某个旧 node 已被人工批准且确认可复用，建议：

- 创建一个新的 node 记录挂到新 revision
- 在 `meta.source_node_id` 中指向被复用的旧 node
- 新 node 的 `revision_id` 永远指向当前 revision，而不是旧 revision

这样可以保持：

- 当前 revision 的节点集合闭合
- 审计链完整
- rollback / diff / timeline 更容易计算

### 规则四：selected candidate 的处理

- 新 revision 默认不继承旧 node 的 `selected_candidate_id`
- 如确需继承，也通过显式“复用节点 + 复用 candidate 引用”实现

### 规则五：projection 视图

对用户展示时：

- 只展示当前 active revision 下的 nodes/candidates
- 历史 revision 的节点默认折叠到“历史版本”视图

这样主视图不会被过期节点污染。

## 11.6 回滚

支持三种回滚：

1. `revision rollback`
回到上一个已批准方案版本

2. `node rollback`
某个步骤回到历史已批准结果

3. `assembly rollback`
回到上一个最终汇总版本

---

## 12. API 设计

## 12.1 保留现有兼容 API

现有 API 保留：

- `/api/tasks/live-status`
- `/api/task-activity/{task_id}`
- `/api/scheduler-state/{task_id}`
- `/api/review-action`
- `/api/task-action`

## 12.2 新增 V2 API

建议新增：

### 顶层工作流

- `POST /api/workflows`
- `GET /api/workflows/{id}`
- `GET /api/workflows/{id}/graph`
- `GET /api/workflows/{id}/timeline`

### revision

- `POST /api/workflows/{id}/revisions`
- `GET /api/workflows/{id}/revisions`
- `POST /api/revisions/{id}/approve`
- `POST /api/revisions/{id}/reject`

### node

- `GET /api/workflows/{id}/nodes`
- `POST /api/nodes/{id}/dispatch`
- `POST /api/nodes/{id}/approve`
- `POST /api/nodes/{id}/reject`
- `POST /api/nodes/{id}/regenerate`

### candidate

- `GET /api/nodes/{id}/candidates`
- `POST /api/candidates/{id}/select`
- `POST /api/candidates/{id}/reject`

### assembly

- `POST /api/workflows/{id}/assemblies`
- `GET /api/workflows/{id}/assemblies`
- `POST /api/assemblies/{id}/approve`
- `POST /api/assemblies/{id}/reject`

### rollback

- `POST /api/workflows/{id}/rollback`

## 12.3 `task-activity` 的演进

当前 `task_activity` 建议在迁移期保持不变，但内部来源改为：

- 读取 workflow 事件
- 投影为当前移动端可消费的 activity 结构

也就是：

- API 可以先不变
- 数据来源逐步迁移到 V2

---

## 13. Flutter / 前端设计影响

## 13.1 首页和任务列表

继续基于 `task` projection 展示。

原因：

- 当前 UI 已经建立在任务卡片模型上
- 用户心智仍是“我下了一道旨意”

## 13.2 详情页从“单任务详情”升级为“工作流详情”

现有 `task_detail_screen.dart` 与 `task_modal.dart` 需要逐步升级为：

- 概览：顶层 task 摘要
- 方案：revision 列表
- 执行：nodes / candidates
- 审批：decision timeline
- 结果：assembly 列表与最终产物

## 13.3 WebSocket 接入

继续复用现有：

- `backend/app/api/websocket.py`
- `flutter_app/lib/services/websocket_service.dart`

但需要让 Flutter 真正消费：

- `workflow.*`
- `task.*`

并做本地状态归并。

## 13.4 推送策略

前台实时更新：

- 使用 WebSocket + provider 归并

后台系统通知：

- 后续增加设备推送通道

---

## 14. 迁移方案

## 14.1 Phase 0：文档与抽象冻结

- 冻结 V2 领域模型
- 冻结事件命名
- 冻结 task 新定位

## 14.2 Phase 1：Kernel V2 最小实现

- 新增 V2 核心实体
- 新增 graph workflow engine
- 新增 workflow repo port
- 新增 workflow policy 抽象

不改现有任务流。

## 14.3 Phase 2：后端双轨运行

- 线性任务继续走 V1
- 复杂任务可走 V2
- V2 生成 task projection
- 现有 API 继续读 projection

这一步的前提是先修复一个当前已存在的问题：

- backend 的主链路必须真正以 engine 为中心，而不是 ORM service 与 worker 各写一套状态机语义

若不先解决“kernel 与 backend 脱节”，则 V2 的 `GraphWorkflowEngine` 也会变成旁路实现，难以成为唯一业务编排入口。

## 14.4 Phase 3：详情页改造

- 新增 workflow graph API
- Flutter 详情页支持 revision / node / candidate / assembly
- 引入 WebSocket 实时增量更新

## 14.5 Phase 4：业务 policy 落地

优先落地：

1. `EdictReviewableWorkflowPolicy`
2. `VideoProductionPolicy`
3. `CodingDeliveryPolicy`

---

## 15. 与当前代码的映射建议

## 15.1 `kernel/`

新增：

- `kernel/src/graph_entities.py`
- `kernel/src/graph_workflow.py`
- `kernel/src/workflow_policy.py`

保留：

- `kernel/src/state_machine.py`
- `kernel/src/workflow.py`
- `kernel/src/ports.py`

## 15.2 `backend/app/models/`

保留：

- `task.py`

新增：

- `workflow_instance.py`
- `workflow_revision.py`
- `workflow_node.py`
- `workflow_candidate.py`
- `workflow_decision.py`
- `workflow_assembly.py`

## 15.3 `backend/app/workers/`

保留：

- `orchestrator_worker.py`
- `dispatch_worker.py`

新增：

- `workflow_orchestrator_worker.py`
- `assembly_worker.py`
- `projection_worker.py`

## 15.4 `backend/app/api/`

保留：

- `tasks.py`
- `compat.py`
- `insights.py`
- `websocket.py`

新增：

- `workflows.py`
- `revisions.py`
- `nodes.py`
- `candidates.py`
- `assemblies.py`

## 15.5 `flutter_app/`

建议新增模型：

- `workflow.dart`
- `workflow_revision.dart`
- `workflow_node.dart`
- `workflow_candidate.dart`
- `workflow_assembly.dart`

建议新增 provider：

- `workflow_detail_provider.dart`
- `workflow_graph_provider.dart`
- `workflow_socket_provider.dart`

---

## 16. 风险与取舍

## 16.1 复杂度上升

从单任务模型升级到图工作流，系统复杂度显著增加。

应对方式：

- 保留 V1
- 采用双轨迁移
- 优先把复杂度放到 V2 专用路径

## 16.2 数据双写一致性

迁移期 `workflow` 与 `task projection` 会存在双写。

应对方式：

- 以 workflow 表为事实来源
- task 表只做 projection
- projection 更新失败不影响主流程，但需补偿重放

## 16.3 前端演进周期长

移动端当前基于扁平 task 模型，升级到 graph 详情页需要时间。

应对方式：

- 列表页继续读 task projection
- 详情页先新增 V2 标签页，不一次性推翻

## 16.4 业务 policy 易膨胀

如果把大量业务分支直接写进单个 policy，会再次变得不可维护。

应对方式：

- policy 只负责动作规划
- 执行器、装配器、candidate 评分器继续拆分

---

## 17. 推荐实施顺序

### Milestone 1：抽象定型

- 完成 V2 领域对象定义
- 完成 workflow topic 设计
- 明确 task projection 字段

### Milestone 2：后端最小闭环

- 建 workflow 表
- 实现 GraphWorkflowEngine
- 实现 revision -> node -> candidate -> assembly 最小链路

### Milestone 3：兼容现有 UI

- 从 workflow 自动投影到 task
- 保持 `live-status` 和 `task-activity` 可用

### Milestone 4：详情页升级

- 支持 revision、nodes、candidates、assemblies
- 接入 WebSocket 增量更新

### Milestone 5：业务类型模板化

- 视频任务模板
- 代码任务模板
- 文档任务模板

---

## 18. 最终结论

本方案不建议继续在当前 `TaskEntity` 上叠加更多字段来硬撑复杂任务。

推荐方向是：

1. 保留当前 `kernel v1`，继续支撑线性任务。
2. 新增 `kernel v2`，引入 workflow graph、revision、node、candidate、decision、assembly。
3. 保留 `task`，但将其重新定位为“根任务 + 摘要投影”，而不是唯一事实来源。
4. 保持业务语义留在 policy 层，kernel 只提供通用工作流能力。

这样既能兼容当前 Edict 架构，也能把视频、代码、调研、文档等复杂任务统一收敛到一套通用逻辑里。
