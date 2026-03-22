# 前端 Dashboard / App 工作流 V2 变更方案

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 适用范围：`flutter_app/`、`backend/app/api/`、`backend/app/services/`
>
> 关联文档：
> - `docs/design/generalized-reviewable-workflow-v2.md`
> - `docs/design/generalized-reviewable-workflow-v2-backend-schema-api.md`
> - `docs/design/flutter-workflow-v2-migration.md`
> - `docs/design/frontend-workflow-v2-runtime-protocol.md`

## 1. 文档目标

本文档定义 Workflow V2 在 Edict 前端的整体交互改造方案，覆盖：

- Dashboard 看板如何继续承载任务总览
- App 详情页如何从 `task projection` 升级为 `workflow graph`
- 单一 V2 详情页如何统一承载所有任务
- API / Provider / WebSocket 的前端接入边界
- 审批、回滚、选优等交互的一致规范
- 分阶段迁移路径

本文档是前端产品与交互层的总方案，重点回答“用户看到什么、页面读什么、操作写哪里”。

更细的 Flutter provider 和模型拆分细节，由 `docs/design/flutter-workflow-v2-migration.md` 承接。

更细的 API 主路径、增量同步、overlay、动作矩阵、路由与降级规则，由 `docs/design/frontend-workflow-v2-runtime-protocol.md` 承接。

---

## 2. 背景与当前问题

当前 Edict 前端默认把 `task` 当作唯一事实来源：

- 首页 / 列表 / Dashboard 读 `/api/tasks/live-status`
- 详情页头部读 `taskByIdProvider`
- 详情页动态区读 `/api/task-activity/{task_id}`
- 审批动作走 `/api/review-action`

随着前端改造推进，当前不再保留 legacy 详情分支，任务统一按 Workflow V2 渲染与操作。

### 2.1 当前已暴露的核心问题

1. 详情页事实来源错误
   V2 详情页仍读 `task projection`，审批或选优后会受到 projection 延迟与轮询周期影响，无法实时反映 workflow 真状态。

2. 线性流程条与 V2 状态机不兼容
   现有 `kPipe` / `kPipeStateIdx` 基于 legacy 固定状态链，无法表达 `draft -> planning -> executing -> assembling -> done`，也无法表达驳回后回到 planning 的循环。

3. 旧详情页已接近复杂度上限
   `task_modal.dart` 与 `task_detail_screen.dart` 都围绕扁平 task 组织，继续往里叠加 revision / node / candidate / assembly 会让维护成本失控。

4. 审批动作仍然绑定 compat 状态推进
   V2 审批本质上应针对 workflow 对象做 decision，而不是直接推进 `tasks.state`。

5. `task-activity` 只能表达 legacy 摘要流
   当前 activity 更适合作为 projection 摘要，而不是承载 V2 的 revision、candidate、assembly、decision 全量动态。

6. WebSocket 连接已存在，但还不是 V2 详情页主更新链路
   这会让前端继续停留在 HTTP 轮询思路，无法承接更高频、更结构化的 workflow 事件。

---

## 3. 总体设计原则

### 3.1 用户心智不暴露底层术语

首页与列表继续展示“旨意”或“任务”，不要求用户理解 workflow internals。

V2 详情页则升级为“管理一个工作流”，但界面上使用业务语言包装底层对象：

- `revision` -> 方案版本
- `node` -> 执行步骤
- `candidate` -> 候选结果
- `assembly` -> 最终汇总
- `decision` -> 审批记录 / 操作记录

### 3.2 保留双层读模型

前端维持两套视图层：

- Projection 视图：面向首页、列表、搜索、看板概览
- Workflow Graph 视图：面向 V2 详情、审批、选优、回滚

### 3.3 列表与详情职责分离

- 列表页追求稳定、轻量、可扫描，可接受最终一致
- 详情页追求结构完整、操作准确、实时更新，应以 workflow 事实源为准

### 3.4 单一路径：全量 Workflow V2

当前策略调整为单一路径：

- 所有任务统一走 `workflow_detail_screen.dart` / `workflow_modal.dart`
- 写操作统一走 workflow commands
- 不再新增或维护 legacy 详情入口

---

## 4. 信息架构与入口分流

## 4.1 页面分工

| 页面 | 主要职责 | 数据源 |
|---|---|---|
| 首页 / Dashboard / 列表 | 查看任务总览、筛选、搜索、进入详情 | `task projection` |
| Workflow V2 详情页 | 查看方案、执行步骤、汇总产物、审批决策 | `workflow summary` + `workflow graph` + `workflow timeline` |

## 4.2 入口分流规则

点击任务卡片或列表项时，统一按 Workflow V2 打开：

- `workflowId` 非空则直接进入 V2 详情
- `workflowId` 为空进入“工作流数据待同步”提示态

建议在前端封装统一 helper：

- `isWorkflowV2Task(task)`
- `taskWorkflowId(task)`

避免把判断逻辑散落在路由、弹窗、移动端详情、列表卡片多个位置。

## 4.3 创建入口分流

创建入口统一调用 `createWorkflow()`，默认产出 Workflow V2 任务，不再提供 legacy 创建路径。

---

## 5. 数据源职责划分

## 5.1 页面与数据源映射

| 页面区域 | 主数据源 | 说明 |
|---|---|---|
| 首页 / Dashboard 卡片 | `/api/tasks/live-status` | 保持低成本轮询 |
| 列表筛选 / 搜索 | `task projection` | 保持扁平结构 |
| V2 详情页头部摘要 | `workflow summary`，必要时回退 projection | 以 workflow 为准 |
| V2 详情页概览 | `workflow graph` 派生 | 不再依赖旧 pipe |
| V2 详情页方案 tab | `workflow graph` | revisions / decisions |
| V2 详情页执行 tab | `workflow graph` | nodes / candidates |
| V2 详情页汇总 tab | `workflow graph` | assemblies / artifacts |
| V2 详情页动态 tab | `workflow timeline` | 决策与过程事件流 |
| 顶部实时状态修正 | WebSocket 增量事件 | 仅用于 V2 详情 |

## 5.2 一致性原则

- 列表页信任 projection
- V2 详情页信任 workflow graph
- 列表与详情短时不一致是设计允许的
- 列表上的 1-3 秒延迟可接受，不为此引入复杂同步机制

## 5.3 不再推荐的模式

以下模式不应继续用于 V2：

- 用 `taskByIdProvider` 作为详情页主事实源
- 在 `task-activity` 里不断追加 V2 字段
- 继续复用 legacy pipeline 渲染 V2 状态
- 通过 compat 接口直写 `tasks.state`

---

## 6. Dashboard 变更方案

## 6.1 可保留不动的部分

以下能力可以继续沿用：

- `liveStatusProvider` 的 5 秒轮询机制
- 首页整体布局与任务卡片栅格
- 列表筛选、归档、排序框架
- 模板与创建入口的基础布局

## 6.2 Dashboard 需要调整的部分

### 6.2.1 卡片状态展示降级为“通用摘要”

对 V2 任务，Dashboard 卡片不再渲染 legacy 三省六部 pipe 语义，而应展示：

- 标题
- 顶层状态 label
- 当前摘要进展
- 待审批数
- 运行中节点数
- 更新时间

如需保留轻量流程感，可改为 4 段式动态阶段条：

1. 起草 / 规划
2. 审批方案
3. 执行步骤
4. 汇总完成

该阶段条仅作为摘要视图，不要求一一映射 graph 内所有状态。

### 6.2.2 卡片点击统一分流

`EdictCardItem`、列表项、通知跳转入口都应统一走 Workflow V2 详情入口：

- Dashboard / 面板：`workflow_modal.dart`
- Mobile：`workflow_detail_screen.dart`

### 6.2.3 排序与 badge 适配 V2

对于 V2 任务，排序不再依赖 legacy `kStateOrder` 语义，建议改为：

- 优先按是否待审批
- 再按是否执行中
- 再按更新时间倒序

Dashboard badge 建议补充：

- `待审批`
- `执行中`
- `已汇总`
- `已完成`

---

## 7. App 详情页变更方案

## 7.1 统一使用 V2 详情页

建议新增：

- `flutter_app/lib/widgets/panels/workflow_modal.dart`
- `flutter_app/lib/widgets/mobile/workflow_detail_screen.dart`

两端结构保持一致，但可以根据屏幕尺寸调整信息密度。

## 7.3 V2 详情页信息结构

建议使用 5 个 tab：

### 1. 概览

展示：

- workflow 标题与状态
- 动态阶段条
- 当前方案版本
- 当前汇总版本
- 待审批对象数
- 运行中节点数
- 快捷操作入口

动作落位：

- 顶层 workflow 动作放在概览页头部或首屏操作区
- 仅放与整个 workflow 相关的动作，例如 `startPlanning`、`stop`、`cancel`、`resume`
- 不在概览页放 candidate / assembly 级细粒度动作

### 2. 方案

展示：

- revision 列表
- revision 当前状态
- change summary
- 方案 diff 摘要
- approve / reject 操作

动作落位：

- revision 级动作只放在“方案” tab
- `approve / reject` 跟随当前待审 revision 卡片或详情区显示
- 不在“动态” tab 重复放审批按钮

### 3. 执行

展示：

- node 列表
- node 当前状态
- candidate 列表
- selected candidate
- regenerate / select 操作

动作落位：

- candidate / node 级动作只放在“执行” tab
- `select / regenerate` 跟随 candidate 列表或 node 详情区显示
- 若 Phase 1-2 后端命令尚未补齐，则该区域先展示状态，不展示动作入口

### 4. 汇总

展示：

- assembly 列表
- assembly 状态
- artifact 列表
- approve / reject / reopen 操作

动作落位：

- assembly 级动作只放在“汇总” tab
- `approve / reject / reopen` 跟随当前 assembly 卡片显示
- artifact 预览入口与 assembly 动作同区，但不与顶层 workflow 动作混排

### 5. 动态

展示：

- workflow timeline
- decision 记录
- 关键系统事件
- rollback 入口

动作落位：

- “动态” tab 以时间线回放为主，不承载主要审批入口
- `rollback` 若开放，放在动态页顶部工具区或时间线旁侧操作区
- 其他业务动作不在动态页重复展示

## 7.4 动态流程条设计

V2 详情页不再复用 `kPipe`。

建议定义独立的 V2 阶段摘要：

| 阶段 | 典型状态 |
|---|---|
| 草拟 | `draft` |
| 方案中 | `planning` / `awaiting_plan_review` |
| 执行中 | `executing` / `awaiting_selection` |
| 汇总中 | `assembling` / `awaiting_final_review` |
| 完成 | `done` / `cancelled` / `blocked` |

说明：

- 该阶段条是用户视角摘要，不是底层状态机的直接平铺
- 被驳回时阶段条可以回退到“方案中”或“执行中”
- 不强求每个节点都投影到阶段条上

## 7.5 `decision` 的展示边界

为避免同一批审批记录在多个 tab 重复堆叠，约定：

- `graph.decisions`
  用于结构上下文与当前对象状态判断，例如某个 revision 是否已被批准、某个 assembly 当前是否待审

- `timeline` 中的 `decision` 条目
  用于按时间顺序回放审批历史与操作历史

页面展示规则：

- “方案” / “汇总” tab 可以显示与当前对象直接相关的最近 decision 摘要
- “动态” tab 负责展示完整 decision 时间线
- 若同一条 decision 已在动态页完整展示，其他 tab 只显示摘要，不重复整段展开

---

## 8. 状态管理与 Provider 方案

## 8.1 保留现有 provider

以下 provider 保持不动：

- `liveStatusProvider`
- `taskByIdProvider`
- `filteredEdictsProvider`
- `taskActivityProvider`
- `schedulerStateProvider`

它们继续服务 Dashboard 与 V2 详情中的辅助信息区。

## 8.2 新增 workflow providers

建议新增：

- `workflowSummaryProvider(workflowId)`
- `workflowGraphProvider(workflowId)`
- `workflowTimelineProvider(workflowId)`
- `workflowEventsProvider(workflowId)`

职责如下：

### `workflowSummaryProvider`

- 拉取 `/api/workflows/{id}`
- 提供详情页头部与轻量摘要信息

### `workflowGraphProvider`

- 拉取 `/api/workflows/{id}/graph`
- 承载 revisions / nodes / candidates / assemblies
- 作为 V2 详情页主事实源

### `workflowTimelineProvider`

- 拉取 `/api/workflows/{id}/timeline`
- 承载 decisions 与动态事件流

### `workflowEventsProvider`

- 连接 `WebSocketService`
- 过滤当前 workflow 相关事件
- 记录最近事件 key
- 标记当前详情页 dirty
- 触发 debounce refetch / reconcile
- 更新 pending mutation 的确认状态

当前阶段不负责：

- 直接 patch graph 真值
- 直接 append timeline 真值

## 8.3 推荐同步策略

V2 详情页进入时：

1. HTTP 拉取 `summary + graph + timeline`
2. 进入页面后连接 WebSocket
3. 收到增量事件后标记 dirty，并触发 debounce refetch / reconcile
4. 每 30 秒做一次静默 reconcile

不建议：

- 仅依赖 WebSocket 不做初始全量加载
- 完全依赖轮询刷新 graph
- 每次事件都强制整页 reload

---

## 9. API Client 与模型变更

## 9.1 `Task` 模型最小增量

现有 `Task` 模型应先解析以下顶层字段：

- `workflowId`
- `projectionVersion`
- `currentRevisionId`
- `currentAssemblyId`
- `pendingReviewCount`
- `runningNodeCount`

目的：

- 支持统一入口解析与 `workflowId` 路由
- 支持列表展示 V2 badge
- 避免继续把关键字段塞进不透明 map

## 9.2 新增 workflow models

建议新增：

- `workflow.dart`
- `workflow_revision.dart`
- `workflow_node.dart`
- `workflow_candidate.dart`
- `workflow_assembly.dart`
- `workflow_decision.dart`
- `workflow_timeline_event.dart`

## 9.3 `ApiClient` 新增方法

建议新增：

- `createWorkflow()`
- `workflowSummary()`
- `workflowGraph()`
- `workflowTimeline()`
- `submitWorkflowCommand()`
- `approveWorkflowRevision()`
- `rejectWorkflowRevision()`
- `selectWorkflowCandidate()`
- `regenerateWorkflowNode()`
- `approveWorkflowAssembly()`
- `rejectWorkflowAssembly()`
- `rollbackWorkflow()`

旧方法处于历史兼容状态，不再作为前端默认动作主路径：

- `createTask()`
- `reviewAction()`
- `advanceState()`

---

## 10. WebSocket 与轮询策略

## 10.1 首页 / Dashboard

保持现状：

- 继续 5 秒轮询 `live-status`
- 不切到全量 WebSocket 架构

原因：

- 首页目标是稳定概览
- projection 结构轻，易缓存
- 没必要为列表态承担 graph 级别的事件复杂度

## 10.2 V2 详情页

采用：

- HTTP 全量
- WebSocket 增量
- 30 秒 reconcile

原因：

- graph 数据结构复杂
- 审批、选优、汇总、回滚需要更低延迟反馈
- 需要补偿漏事件和弱网场景

## 10.3 事件过滤建议

后端当前 `/ws` 是全量事件流，后续建议支持：

- workflow 维度 topic 过滤
- 或至少支持按 `workflow_id` / `task_id` 过滤

在服务端未完成过滤前，前端 `workflowEventsProvider` 需要本地过滤当前 workflow 相关事件。

---

## 11. 交互规范

## 11.1 审批 / 回滚统一约束

所有以下动作都必须二次确认：

- approve
- reject
- select
- rollback
- reopen

### 表单规则

- approve：备注可选
- reject：理由必填
- rollback：理由必填
- select：可选备注
- regenerate：不做乐观更新

## 11.2 按钮反馈规范

动作提交后统一遵循：

1. 按钮进入 loading
2. 局部界面进入 pending 状态
3. 收到确认事件后展示成功 toast
4. 3 秒内未收到确认事件时，显示“同步中...”

## 11.3 乐观更新边界

允许乐观更新：

- approve / reject
- select

不建议乐观更新：

- regenerate
- rollback
- 大范围重建 graph 的操作

建议通过 `optimistic overlay` 方式覆盖展示层，而不是直接改写 graph 真值。

---

## 12. 迁移阶段

## Phase 1：单轨基础改造

目标：

- 补齐 `Task` 的 V2 字段解析
- `ApiClient` 增加 workflow 读取与创建方法
- 统一入口 helper 改为仅解析 `workflowId`

交付结果：

- 首页能识别 V2 任务
- 前端具备请求 V2 API 的能力
- 详情入口默认进入 V2 页面

## Phase 2：V2 详情页落地

目标：

- 新增 `workflow_modal.dart`
- 新增 `workflow_detail_screen.dart`
- 接入 `workflowSummaryProvider` / `workflowGraphProvider`
- Dashboard 点击后可进入 V2 详情

交付结果：

- V2 详情页可展示概览、方案
- V2 详情页成为唯一默认详情入口

## Phase 3：实时交互闭环

目标：

- 接入 `workflowTimelineProvider`
- 接入 `workflowEventsProvider`
- 完成执行 / 汇总 / 动态 tab
- 完成审批、选优、回滚交互

交付结果：

- V2 详情具备完整可操作能力
- 详情页实现 HTTP + WS + reconcile 闭环

## Phase 4：创建入口与代码清理

目标：

- `create_screen.dart` 默认走 V2 创建
- 清理旧详情页与旧路由代码

交付结果：

- 新任务默认采用 Workflow V2
- 代码路径收敛为全量 Workflow V2

---

## 13. 可保持不动的部分

以下组件可继续复用，不必在本轮改造中重写：

- `liveStatusProvider` 与轮询机制
- `WebSocketService` 的连接管理能力
- Dashboard 主体布局
- `create_screen.dart` 的模板框架
- `constants.dart` 中的通用模板、部门与颜色常量
- `backend/app/api/websocket.py` 的基础转发框架
- `task-activity` API 仅作为辅助观测接口（非详情主链路）

---

## 14. 待确认问题

以下产品与交互问题需要在实施前明确：

1. 新建任务默认是否全部走 V2，还是保留用户可选开关
2. 三省六部标签在 V2 下是否继续用于 projection 展示
3. candidate 是自动选优还是必须人工确认
4. 多人同时审批同一 revision 时的冲突提示策略
5. assembly 是自动触发还是需要用户手动点击开始汇总
6. Artifact inline 预览是否纳入本期
7. Phase 2 是否同步建设移动端推送提醒

---

## 15. 最终结论

Workflow V2 的前端改造重点，不是把原有 `task` 详情页继续做大，而是建立清晰的双层架构：

1. Dashboard 继续使用 `task projection` 做总览
2. V2 详情页切到 `workflow graph` 做事实展示
3. 所有任务统一进入 V2 详情页，不再维护 legacy 详情分支
4. 审批与回滚统一走 workflow API，而不是 compat 状态推进
5. V2 详情页采用 HTTP 全量 + WebSocket 增量 + reconcile 的同步策略

这样可以减少双轨维护成本，保证交互与状态语义始终围绕同一套 Workflow V2 合同演进。
