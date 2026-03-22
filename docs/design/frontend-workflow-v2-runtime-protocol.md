# 前端 Workflow V2 实现协议

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 适用范围：`flutter_app/`、`backend/app/api/`、`backend/app/services/`
>
> 上游文档：
> - `docs/design/generalized-reviewable-workflow-v2.md`
> - `docs/design/frontend-dashboard-app-workflow-v2.md`
> - `docs/design/flutter-workflow-v2-migration.md`

## 1. 文档目标

本文档补足前端升级方案中缺失的“运行时实现协议”。

它不重复解释页面为什么这样分层，而是直接冻结以下实现合同：

- 前端读写 API 的主路径
- WebSocket、HTTP、reconcile 的协作规则
- optimistic overlay 的生命周期
- timeline / graph 的去重与刷新策略
- 动作可见性矩阵
- 路由、深链与入口解析规则
- projection 降级展示规则

本文档的目标是让多人并行开发时，Dashboard、panel、mobile、provider、API client 可以遵循同一套稳定约束。

---

## 2. 文档职责划分

为避免设计文档继续漂移，约定如下：

### `frontend-dashboard-app-workflow-v2.md`

定位：

- 前端交互与页面架构 SoT
- 定义哪些页面读 projection，哪些页面读 graph
- 定义单一 V2 详情页入口与路由规则

### `flutter-workflow-v2-migration.md`

定位：

- Flutter 实现与迁移 SoT
- 定义 models、providers、screen/widget 的拆分方式

### `frontend-workflow-v2-runtime-protocol.md`

定位：

- 前端运行时协议 SoT
- 定义 API 主路径、增量同步、overlay、动作矩阵、路由与降级规则

如三者冲突，以本协议约束具体实现行为，以交互文档约束页面职责。

---

## 2.1 术语约定

为避免不同文档对同一个词使用不同含义，统一约定：

- `invalidate`
  标记本地 snapshot 可能过期

- `refetch`
  重新请求单个或多个 HTTP snapshot

- `reconcile`
  一次包含 `summary + graph + timeline` 的对账式刷新

- `confirm`
  pending mutation 被服务端结果间接确认

- `patch`
  直接修改 graph / timeline 真值

- `overlay`
  只覆盖展示层的本地派生状态

---

## 3. 当前后端能力与冻结决策

## 3.1 当前已存在能力

当前后端已提供：

- `GET /api/workflows/{workflow_id}`
- `GET /api/workflows/{workflow_id}/graph`
- `GET /api/workflows/{workflow_id}/timeline`
- `POST /api/workflows/{workflow_id}/commands`

当前仍存在 compat 转发 workflow command 的兼容路径，但前端新页面不再依赖该路径。

## 3.2 当前缺失能力

当前后端尚未提供前端可稳定依赖的：

- `graphVersion`
- `timelineVersion`
- 全局单调递增 `eventSequence`
- 可证明有序的 entity patch 事件

这意味着：

- WebSocket 现在还不能被前端当成“可直接字段级 merge 的事实流”
- 在补齐版本/序号前，WebSocket 应被视为“刷新信号 + 局部确认信号”

## 3.3 Phase 1-3 冻结决策

在后端补齐版本与序号前，前端统一采用以下主路径：

### 读路径

- `summary` -> `GET /api/workflows/{id}`
- `graph` -> `GET /api/workflows/{id}/graph`
- `timeline` -> `GET /api/workflows/{id}/timeline`

### 写路径

- 所有 V2 写操作统一走 `POST /api/workflows/{id}/commands`

### 客户端抽象

前端仍可暴露语义方法，例如：

- `approveWorkflowRevision()`
- `rejectWorkflowRevision()`
- `selectWorkflowCandidate()`
- `approveWorkflowAssembly()`
- `rollbackWorkflow()`

但这些方法在 client 层内部必须映射到统一 command API，而不是各自绑定不同后端 action endpoint。

换句话说：

- UI 层看见的是语义动作
- 传输层冻结为 command API

这样可以避免前端 client 在命令式 API 和资源动作式 API 之间反复返工。

---

## 4. 数据标识与前端主键规则

## 4.1 顶层对象标识

- `Task.id`
  外部业务编号，用于列表与跨端追踪

- `Workflow.id`
  V2 详情页唯一事实主键

## 4.2 子对象标识

以下对象都必须以服务端稳定 ID 作为主键：

- `revision.id`
- `node.id`
- `candidate.id`
- `assembly.id`
- `decision.id`

禁止用列表索引、时间戳位置或本地生成短 key 作为主合并键。

## 4.3 timeline item key

timeline 去重 key 统一定义为：

- `timelineKey = "{kind}:{id}"`

例如：

- `revision:wf_rev_001`
- `decision:wf_dec_123`
- `assembly:wf_asm_009`

若服务端临时返回无 `id` 的事件，则前端不得对其做持久 merge，只能当作瞬时提示项。

---

## 5. API 主路径与命令映射

## 5.1 统一写入入口

V2 前端统一调用：

- `POST /api/workflows/{workflow_id}/commands`

请求体结构：

```json
{
  "eventType": "workflow.v2.command.approve_plan",
  "producer": "flutter",
  "payload": {
    "revision_id": "wf_rev_001",
    "comment": "looks good"
  }
}
```

当前接口返回：

- `ok`
- `accepted`
- `entryId`

前端必须把 `entryId` 当作“命令已入队”的确认，而不是“状态已落地”的确认。

## 5.2 语义动作到 command 的映射

在 API client 层冻结以下映射：

| 前端语义动作 | command `eventType` | 备注 |
|---|---|---|
| `startPlanning` | `workflow.v2.command.start_planning` | 已有 |
| `submitPlan` | `workflow.v2.command.submit_plan` | 已有 |
| `approveWorkflowRevision` | `workflow.v2.command.approve_plan` | Phase 1-2 统一映射 |
| `rejectWorkflowRevision` | `workflow.v2.command.reject_plan` | Phase 1-2 统一映射 |
| `stopWorkflow` | `workflow.v2.command.stop` | 已有 |
| `cancelWorkflow` | `workflow.v2.command.cancel` | 已有 |
| `resumeWorkflow` | `workflow.v2.command.resume` | 已有 |
| `selectWorkflowCandidate` | 预留 command | Phase 3 后端补齐 |
| `regenerateWorkflowNode` | 预留 command | Phase 3 后端补齐 |
| `approveWorkflowAssembly` | 预留 command | Phase 3 后端补齐 |
| `rejectWorkflowAssembly` | 预留 command | Phase 3 后端补齐 |
| `rollbackWorkflow` | 预留 command | Phase 3 后端补齐 |

约束：

- 未有后端 command 常量的动作，不允许前端擅自发明 REST action endpoint
- 文档中写到但后端尚未补齐的动作，前端以“保留能力”处理，不进入默认 UI

## 5.3 compat 的定位

compat 仅作为后端兼容层保留。  
前端 V2 页面、新 provider、新 client 不直接调用 compat。

---

## 6. 同步协议：HTTP、WebSocket、Reconcile

## 6.1 总原则

在后端未提供 `graphVersion` / `eventSequence` 之前，前端不得把 WebSocket 事件直接当作 graph 真值 patch。

当前稳定协议如下：

1. HTTP snapshot 是唯一事实快照
2. WebSocket 事件是刷新信号与确认信号
3. reconcile 用于补偿漏事件、重连、跨端并发修改

## 6.2 首次进入详情页

进入 V2 详情页时按以下顺序执行：

1. 解析入口得到 `workflowId`
2. 并发请求 `summary + graph + timeline`
3. 组装本地 `WorkflowDetailState`
4. 再建立 WebSocket 订阅

禁止：

- 先连 WebSocket 再等事件拼装页面
- 只依赖 graph，不拉 timeline

## 6.3 当前阶段的 WebSocket 处理规则

当收到与当前 `workflowId` 相关的 WebSocket 事件时：

1. 先记录该事件到 `recentEventKeys`
2. 标记当前详情页为 `dirty`
3. 如果该事件与 pending mutation 有关，先尝试更新本地 overlay 状态
4. 触发一次 debounce refetch：
   - `summary + graph`
   - 如事件疑似影响动态区，再追加 `timeline`

当前阶段不做：

- 对 node / revision / assembly 做字段级原地 patch
- 依赖事件到达顺序更新 graph
- 依赖事件内容完整性更新 timeline

也就是说：

### 当前阶段 WebSocket 的角色

- `invalidate`
- `confirm`
- `wake up reconcile`

而不是：

- `authoritative incremental patch stream`

因此前端中的 `workflowEventsProvider`、`workflowSocketProvider` 或同类对象，统一被视为“事件协调器”，职责限定为：

- 订阅并过滤当前 workflow 相关 socket 事件
- 记录最近事件 key
- 标记 dirty
- 触发 debounce refetch / reconcile
- 更新 pending mutation 的确认状态

不负责：

- 直接 patch graph 真值
- 直接 append timeline 真值
- 在本地重建服务端状态机

## 6.4 Reconcile 规则

V2 详情页在以下时机触发 reconcile：

- 页面首次进入后 30 秒轮询一次
- WebSocket 重连成功后立即一次
- 某个 pending mutation 超时后一次
- App 从后台恢复前台后一次
- 用户手动下拉刷新时一次

reconcile 内容：

- `summary`
- `graph`
- `timeline`

若仅顶部摘要疑似过期，可只拉 `summary + graph`，但手动刷新必须拉全量三者。

---

## 7. 未来可升级的真正增量 merge 条件

当前协议是“WebSocket 触发 refetch”。  
未来若后端补齐以下字段，前端才允许升级到真正的事件级 merge：

- `graphVersion`
- `timelineVersion`
- 单调递增 `eventSequence`
- 每个事件明确声明影响对象、对象版本与变更后状态

只有在这些能力到位后，前端才可以：

- 丢弃旧事件
- 对 graph 做字段级 patch
- 对 timeline 做增量 append
- 在不 refetch 的情况下稳定维持一致性

在此之前，一律不做“看起来更快、但顺序不可靠”的局部 merge。

---

## 8. Optimistic Overlay 协议

## 8.1 适用范围

允许 optimistic overlay 的动作：

- `approveWorkflowRevision`
- `rejectWorkflowRevision`
- `selectWorkflowCandidate`

暂不允许 optimistic overlay 的动作：

- `regenerateWorkflowNode`
- `rollbackWorkflow`
- `approveWorkflowAssembly`
- `rejectWorkflowAssembly`
- 任何会触发大范围 graph 重建的动作

## 8.2 overlay 结构

每次允许 optimistic 的动作，都应生成本地 mutation：

```text
PendingMutation {
  mutationId,
  workflowId,
  targetType,
  targetId,
  action,
  startedAt,
  status,      // pending | confirmed | failed | timed_out
  expectedEffect
}
```

## 8.3 overlay 生效规则

命令 accepted 后：

1. 按钮进入 loading
2. 本地写入 `PendingMutation`
3. 由 view model 派生 overlay 显示“待确认状态”
4. 不直接改写原始 graph snapshot

约束：

- overlay 只覆盖 UI 派生层
- server snapshot 永远保留原始值

## 8.4 overlay 失效规则

overlay 在以下任一条件满足时失效：

1. refetch 后 snapshot 已体现预期效果
2. 收到明确失败响应
3. 30 秒内仍未确认，标记 `timed_out`
4. 用户离开详情页

`timed_out` 后：

- UI 保留“同步中”或“状态待确认”提示
- 立即触发一次 reconcile
- reconcile 后若仍未体现预期效果，则清空 overlay 并显示“同步未完成，请刷新重试”

## 8.5 3 秒提示规则

提交动作后 3 秒未确认：

- 不判失败
- 只显示“同步中...”

这条规则用于区分：

- `accepted but not yet projected`
- 真正失败

---

## 9. timeline 去重与刷新策略

## 9.1 当前阶段 timeline 来源

timeline 的事实来源是：

- `GET /api/workflows/{id}/timeline`

当前 WebSocket 不直接向 timeline append。

## 9.2 去重规则

每次 refetch timeline 后：

1. 以 `timelineKey = "{kind}:{id}"` 构建 map
2. 后到数据覆盖先到数据
3. 最终按 `at` 排序

## 9.3 为什么当前不直接 append socket event

因为当前后端未提供：

- 全局 sequence
- timeline 专用版本号
- 可证明完整的 timeline event payload

若直接 append，很容易出现：

- 重复 decision
- 晚到旧事件插入尾部
- graph 已更新但 timeline 仍旧缺项

因此当前协议冻结为：

- WebSocket 告知“可能有变化”
- timeline 一律通过 HTTP 重取

---

## 10. 动作可见性矩阵

## 10.1 总原则

同一 workflow 的 panel modal 与 mobile detail 必须使用同一套动作矩阵。

动作矩阵输出值只有三种：

- `visible`
- `disabled`
- `hidden`

禁止两端各自手写散落的 if/else。

## 10.2 Phase 1-2 动作矩阵

| 对象 | 状态 | 动作 | 可见性 | optimistic |
|---|---|---|---|---|
| workflow | `draft` | `startPlanning` | `visible` | 否 |
| revision | `submitted` / `awaiting_review` | `approve` | `visible` | 是 |
| revision | `submitted` / `awaiting_review` | `reject` | `visible` | 是 |
| workflow | `blocked` | `resume` | `visible` | 否 |
| workflow | 非终态 | `stop` | `visible` | 否 |
| workflow | 非终态 | `cancel` | `visible` | 否 |
| candidate | 任意 | `select` | `hidden` | 否 |
| candidate | 任意 | `regenerate` | `hidden` | 否 |
| assembly | 任意 | `approve` / `reject` | `hidden` | 否 |
| workflow | 任意 | `rollback` | `hidden` | 否 |

说明：

- Phase 1-2 只开放后端已收敛的 plan 级命令
- 还没冻结 command 的动作，一律隐藏，不做半成品按钮

## 10.3 Phase 3 预留矩阵

待后端补齐对应 commands 后，再开放：

- `candidate.select`
- `candidate.regenerate`
- `assembly.approve`
- `assembly.reject`
- `workflow.rollback`

开放前必须先补：

- command 常量
- client 映射
- overlay 策略
- server 确认条件

---

## 10.4 动作矩阵到页面落位的映射

同一动作在 panel modal 与 mobile detail 上必须遵循同一套落位规则：

| 动作类型 | 默认落位 | 说明 |
|---|---|---|
| workflow 级动作 | 概览页头部 / 首屏操作区 | `startPlanning`、`stop`、`cancel`、`resume` |
| revision 级动作 | 方案 tab | `approve`、`reject` |
| candidate / node 级动作 | 执行 tab | `select`、`regenerate` |
| assembly 级动作 | 汇总 tab | `approve`、`reject`、`reopen` |
| 历史 / 纠偏动作 | 动态 tab 工具区 | `rollback` |

约束：

- 同一动作不得同时在概览区与对象 tab 里都作为主按钮出现
- “动态” tab 默认展示历史，不承担常规审批入口
- hidden 动作在本阶段完全不展示，不用“即将支持”占位

---

## 11. 路由、深链与入口解析规则

## 11.1 统一入口模型

所有前端入口先归一为：

```text
WorkflowEntryRef {
  taskId,
  workflowId?,
  source,      // dashboard | notification | deeplink | push
  preferredSurface  // modal | page
}
```

入口来源包括：

- Dashboard 卡片点击
- 列表项点击
- Toast / 通知跳转
- 推送点击
- 深链恢复

## 11.2 解析规则

解析顺序固定为：

1. 若显式带 `workflowId`，优先按 V2 打开
2. 否则根据 `taskId` 查 `task projection`
3. 若 `workflowId != ""`，走 V2
4. 否则进入 resolver loading / 数据待同步提示态

## 11.3 `taskId` 深链的 resolver 策略

当入口只提供 `taskId`，且前端暂时拿不到 `workflowId` 时，统一进入 resolver loading 态。

处理顺序：

1. 用 `taskId` 请求 projection / 任务摘要
2. 若解析出 `workflowId != ""`，进入 V2
3. 若 projection 不完整且 `workflowId` 为空，展示“工作流数据待同步”并允许重试
4. 若请求失败，进入错误态，不做 silent fallback

约束：

- 不允许因为临时拿不到 `workflowId` 就误开旧详情
- resolver loading 态是允许的、且应被视为正常入口状态

## 11.4 Surface 规则

建议冻结为：

- Dashboard / 桌面大屏内点击：优先 modal
- Mobile App / 窄屏：优先 full page
- 通知 / 推送进入：优先 full page
- Web 刷新恢复：只能恢复 full page route，不恢复 modal 态

## 11.5 route 参数规则

V2 route 必须显式携带 `workflowId`。

推荐：

- `.../workflow/:workflowId`

任务详情统一收敛到携带 `workflowId` 的 V2 路由。  
仅在 resolver 阶段允许 `taskId` 输入，解析后必须跳转到 V2 route。

---

## 12. Projection 降级展示规则

## 12.1 V2 卡片字段优先级

Dashboard / 列表中，V2 任务卡片按以下优先级展示：

1. `title`
2. `state`
3. `now`
4. `pendingReviewCount`
5. `runningNodeCount`
6. `updatedAt`

若字段缺失，降级如下：

- `pendingReviewCount` 缺失 -> 不显示待审批 badge
- `runningNodeCount` 缺失 -> 不显示执行中 badge
- `now` 为空 -> 使用通用文案“工作流同步中”
- `workflowId` 为空 -> 视为不完整 projection，卡片显示“工作流数据待同步”

## 12.1.1 后端旧数据收敛（必须执行）

当系统切到 workflow v2 单轨后，后端必须保证 `tasks.workflow_id` 可解析到
`workflow_instances.id`，否则前端只能进入“数据待同步”态，无法打开详情。

执行要求：

1. 先 dry-run：  
   `python backend/migration/backfill_legacy_tasks_to_workflow_v2.py`
2. 观察输出中的候选数量与映射状态，确认无异常后再 apply：  
   `python backend/migration/backfill_legacy_tasks_to_workflow_v2.py --apply`
3. apply 后抽样校验：
   - `tasks.workflow_id` 非空
   - `tasks.workflow_type = generic`
   - `workflow_instances.task_id` 与 `tasks.task_id` 一一对应

## 12.2 列表页“同步中”规则

当用户在 V2 详情页提交动作后返回列表，如果 projection 还没追上：

- 当前 task 卡片可显示临时 badge：`同步中`
- 最长保留 10 秒
- 期间若 `projectionVersion` 或 `updatedAt` 前进，则立即清除

## 12.3 不允许的列表补偿方式

禁止：

- 直接把详情页 graph 状态写回列表 task
- 在列表页本地伪造完整 V2 状态推进

原因：

- 列表页的事实来源仍是 projection
- 可以做 UI hint，但不能伪造 projection 真值

---

## 13. 前端状态层次

为避免 provider 状态互相污染，前端统一区分 5 层状态：

### 1. Server Snapshot

- `summary`
- `graph`
- `timeline`

### 2. Socket Invalidations

- 最近收到的 workflow 相关事件
- 仅用于触发 refresh / reconcile

### 3. Pending Mutations

- 本地已提交但未确认的动作

### 4. Optimistic Overlay

- 基于 pending mutations 派生出的显示层状态

### 5. Derived View Model

- 供 widget 使用的最终数据

约束：

- widget 不直接读 socket 原始事件拼 UI
- overlay 不反写 snapshot
- snapshot 刷新后重新派生 view model

---

## 13.1 `decision` 在 graph 与 timeline 中的边界

为避免相同 decision 在数据层和展示层职责混乱，统一约定：

- `graph.decisions`
  用于结构上下文与对象当前状态判断

- `timeline.decision items`
  用于时间顺序回放与操作历史展示

实现约束：

- provider 可以同时保留两份数据，但用途必须区分
- widget 不应在多个 tab 中完整重复渲染同一批 decision
- “方案” / “汇总” tab 只显示当前对象关联的 decision 摘要
- “动态” tab 展示完整 decision 时间线

---

## 14. 推荐落地顺序

## Phase 1

- 前置条件 checklist：
  - `Task` 已解析 `workflowId`
  - command API 已冻结为唯一写入口
  - summary / graph 读取接口可用

- 冻结 command API 为唯一写入口
- `Task` 解析 V2 顶层字段
- 完成 V2 入口 resolver

## Phase 2

- 前置条件 checklist：
  - Phase 1 完成
  - `workflowSummaryProvider` / `workflowGraphProvider` 可用
  - 统一 V2 入口规则已落地

- 落地 `workflowSummaryProvider`
- 落地 `workflowGraphProvider`
- 落地 V2 详情页壳层
- 动作矩阵按 Phase 1-2 范围执行

## Phase 3

- 前置条件 checklist：
  - Phase 2 完成
  - timeline API 可用
  - socket invalidation 可用
  - pending mutation store 可用

- 落地 `workflowTimelineProvider`
- 接入 WebSocket invalidation
- 落地 pending mutation + overlay
- 落地 projection “同步中”提示

## Phase 4

- 前置条件 checklist：
  - Phase 3 完成
  - V2 详情闭环稳定
  - 创建入口切换后不会进入旧详情路径

- 等后端补齐 version / sequence
- 再评估是否升级为真实事件级 merge

---

## 15. 最终结论

当前最稳妥的前端实现协议不是“直接拿 WebSocket 事件 patch graph”，而是：

1. 读路径冻结为 `summary + graph + timeline`
2. 写路径冻结为 `commands`
3. WebSocket 当前只做 invalidation / confirm
4. graph 与 timeline 的真值都来自 HTTP snapshot
5. optimistic update 只存在于 overlay 层，不污染原始 snapshot

这套协议虽然比真正的实时 patch 更保守，但在后端尚未提供 `graphVersion / eventSequence` 之前，是最稳定、最不容易返工的实现方式。
