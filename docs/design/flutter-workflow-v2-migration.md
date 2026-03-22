# Flutter 端工作流 V2 迁移方案

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 上游设计：
> - `docs/design/generalized-reviewable-workflow-v2.md`
> - `docs/design/generalized-reviewable-workflow-v2-backend-schema-api.md`
> - `docs/design/frontend-dashboard-app-workflow-v2.md`
> - `docs/design/frontend-workflow-v2-runtime-protocol.md`

## 1. 文档目标

本文档专门回答 Flutter 端如何从当前的扁平 `task` 模型，迁移到“`task projection + workflow graph`”双层模型。

其中更高层的页面职责、Dashboard 分工、交互规范与迁移节奏，统一以 `docs/design/frontend-dashboard-app-workflow-v2.md` 为准。

其中 API 主路径、增量同步、overlay、动作矩阵、路由与降级规则，统一以 `docs/design/frontend-workflow-v2-runtime-protocol.md` 为准。

本文档重点落在 Flutter provider、模型与页面实现拆分。

重点覆盖：

- 当前实现依赖点
- 迁移难点
- provider 改造路径
- 详情页分层方案
- projection 延迟下的交互策略

---

## 2. 当前 Flutter 架构现状

当前移动端和面板端主要依赖：

- `liveStatusProvider`
  轮询 `/api/tasks/live-status`

- `taskActivityProvider`
  轮询 `/api/task-activity/{task_id}`

- `schedulerStateProvider`
  轮询 `/api/scheduler-state/{task_id}`

- `taskByIdProvider`
  从 `liveStatusProvider` 派生任务详情摘要

- `WebSocketService`
  已存在，但尚未成为当前主更新机制

也就是说，当前 UI 默认假设：

1. 首页只看一个扁平 task 列表
2. 详情页的主要事实来源仍是扁平 task
3. activity 是对 task 的补充，而不是 workflow graph 的主视图

---

## 3. 迁移目标

Flutter 迁移后应形成两层数据视图：

### 第一层：Projection 视图

继续服务：

- 首页
- 列表
- 搜索
- 快速状态概览

数据源：

- `/api/tasks/live-status`

### 第二层：Workflow Graph 视图

服务：

- 方案版本浏览
- 节点列表
- 候选比选
- 装配结果查看
- 回滚与审批操作

数据源：

- `/api/workflows/{id}`
- `/api/workflows/{id}/graph`
- `/api/workflows/{id}/timeline`
- `workflow.v2.*` WebSocket 事件

---

## 4. 迁移难点

## 4.1 `liveStatusProvider` 牵引范围大

当前：

- `liveStatusProvider` 每 5 秒轮询一次
- 多个 derived provider 都依赖它
- `taskByIdProvider` 直接把它当详情页主数据源

这意味着：

- 不能直接把首页和详情页同时切到 workflow graph
- 必须保留 `task projection` 作为首页和列表主数据源

## 4.2 详情页信息密度会显著上升

V2 后详情页不再只是：

- 状态
- output
- flow_log
- progress_log
- todos

还会新增：

- revisions
- nodes
- candidates
- assemblies
- decisions

因此详情页需要显式分层，而不能继续全部堆在一个 `TaskActivityData` 里。

## 4.3 Projection 延迟带来的体验问题

后端采用：

- outbox publisher
- projection worker

之后，用户触发 approve/reject/select 这类动作时：

- workflow 事实表会先更新
- task projection 稍后更新

因此 Flutter 必须处理短暂不一致窗口。

---

## 5. 模型设计建议

## 5.1 保留现有 task 模型

继续保留：

- `flutter_app/lib/models/task.dart`

原因：

- 首页与列表继续依赖 `task projection`
- 兼容 `live-status` 与必要的辅助字段解析

## 5.2 新增 workflow 模型

建议新增：

- `flutter_app/lib/models/workflow.dart`
- `flutter_app/lib/models/workflow_revision.dart`
- `flutter_app/lib/models/workflow_node.dart`
- `flutter_app/lib/models/workflow_candidate.dart`
- `flutter_app/lib/models/workflow_assembly.dart`
- `flutter_app/lib/models/workflow_decision.dart`

## 5.3 顶层映射关系

建议约定：

- `Task.id`
  始终是外部业务编号

- `Task.sourceMeta["workflowId"]`
  或新增明确字段承载真实 workflow id

这样详情页进入 workflow graph 时不需要重新猜测映射关系。

---

## 6. Provider 设计建议

## 6.1 保持 `liveStatusProvider`

不建议在第一阶段删除或替换。

建议继续：

- 服务首页/列表
- 提供 `taskByIdProvider`
- 作为 fallback 摘要来源

## 6.2 新增 workflow providers

建议新增：

- `workflowSummaryProvider(workflowId)`
- `workflowGraphProvider(workflowId)`
- `workflowTimelineProvider(workflowId)`
- `workflowSocketProvider(workflowId)`

### `workflowSummaryProvider`

职责：

- 获取 `/api/workflows/{id}`
- 提供顶层 workflow 摘要

### `workflowGraphProvider`

职责：

- 获取 `/api/workflows/{id}/graph`
- 提供 revisions/nodes/candidates/assemblies

### `workflowTimelineProvider`

职责：

- 获取 `/api/workflows/{id}/timeline`
- 提供决策与过程事件流

### `workflowSocketProvider`

职责：

- 订阅 `workflow.v2.*`
- 过滤当前 workflow 相关事件
- 记录最近事件 key
- 标记当前详情页 dirty
- 触发 debounce refetch / reconcile
- 更新 pending mutation 的确认状态

当前阶段不负责：

- 直接 patch graph 真值
- 直接 append timeline 真值
- 在本地重建服务端状态机

## 6.3 详情入口单轨化

当前策略：

- `taskActivityProvider` 继续服务辅助信息，不再作为详情主入口分流依据
- 详情统一进入 `workflow_detail_screen.dart`
- 若 `workflowId` 缺失，显示“工作流数据待同步”并允许重试

---

## 7. 详情页改造建议

## 7.1 统一详情页入口

当前实现目标是单一路径：

- `workflow_detail_screen.dart` 作为唯一详情入口
- 不再在移动端路由中跳转 `task_detail_screen.dart`

## 7.2 V2 详情页结构建议

建议分为 5 个标签页：

1. `概览`
   显示 workflow 摘要、当前阶段、待审批数量、进行中节点数量

2. `方案`
   显示 revisions 列表、diff 摘要、审批状态

3. `执行`
   显示 nodes 与 candidates，支持选优与重生成

4. `汇总`
   显示 assemblies 与最终产物

5. `动态`
   显示 workflow timeline 与 decisions

## 7.3 旧详情代码清理策略

`task_detail_screen.dart` 不再参与运行时路由，直接进入清理删除范围。

---

## 8. WebSocket 接入策略

## 8.1 首页

首页可继续依赖：

- 轮询 `live-status`

暂时不强制要求首页做全量 WebSocket 增量更新。

## 8.2 详情页

V2 详情页建议优先接 WebSocket。

原因：

- revisions/nodes/candidates 变化更频繁
- 轮询会导致结构化数据闪烁与重复拉取

## 8.3 事件归并策略

建议：

- 首次进入详情页先 HTTP 拉全量 graph
- 后续通过 WebSocket 接收事件协调信号
- 定时做轻量 reconcile，避免漏事件

---

## 9. Projection 延迟下的 UI 策略

## 9.1 首页/列表页

首页继续依赖 projection，因此会有轻微延迟。

建议体验策略：

- 用户触发审批后，弹出“已提交，正在同步”提示
- 允许列表页在 1-3 秒内异步更新

## 9.2 详情页

详情页若已切到 workflow graph，则应优先以 workflow 事实状态为准。

也就是说：

- 详情页动作成功后，可立即局部乐观更新
- 不必等待 `task projection` 刷新

## 9.3 一致性规则

建议：

- 列表页信任 `task projection`
- 详情页信任 `workflow graph`

这是双层模型下最清晰的职责划分。

---

## 10. API 客户端改造建议

建议在 `api_client.dart` 中新增：

- `workflowSummary()`
- `workflowGraph()`
- `workflowTimeline()`
- `submitWorkflowDecision()`
- `rollbackWorkflow()`

而不是在现有 `taskActivity()` 上不断堆字段。

---

## 11. 推荐迁移顺序

### Phase 1：模型与 API client

- 新增 workflow models
- 新增 workflow API client 方法

### Phase 2：新增 V2 详情页

- 新增 `workflow_detail_screen.dart`
- 统一入口跳转到 `workflow_detail_screen.dart`

### Phase 3：接 WebSocket

- 为 V2 详情页接入 `workflow.v2.*`
- 局部做增量归并

### Phase 4：首页增强

- 视需要让首页也消费 `workflow.v2.projection.updated`
- 但仍以 projection 为主

---

## 12. 第一批建议落地范围

若只做最小可验证版本，Flutter 第一批建议只做：

1. 新增 workflow models
2. 新增 workflow API client
3. 新增 `workflow_detail_screen.dart`
4. 入口统一跳转 Workflow V2 详情，缺失 `workflowId` 显示同步提示

暂时不做：

- 首页全量 WebSocket 化
- 所有 provider 重构
- 统一详情页代码路径

---

## 13. 最终结论

Flutter 迁移的关键不是“把现有 task UI 改复杂”，而是：

1. 保留 `task projection` 服务首页和列表
2. 新增 `workflow graph` 服务复杂详情
3. 用 `workflowId` 做唯一详情路由主键，不再维护 legacy 分流
4. 在详情页优先信任 workflow 事实状态，在列表页继续信任 projection

这样能用最小风险完成从扁平 task 视图到复杂 workflow 视图的过渡。
