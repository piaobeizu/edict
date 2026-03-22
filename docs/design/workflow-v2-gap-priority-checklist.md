# Workflow V2 差距补齐优先级清单

> 状态：P0 已完成，进入 P1
>
> 最后更新：2026-03-20
>
> 适用范围：`kernel/`、`backend/app/`、`flutter_app/`
>
> 关联文档：
> - `docs/design/generalized-reviewable-workflow-v2.md`
> - `docs/design/frontend-dashboard-app-workflow-v2.md`
> - `docs/design/frontend-workflow-v2-runtime-protocol.md`

---

## 0. 当前进度（2026-03-20）

### 已完成（P0）

- P0-1：写路径统一为 command（Flutter/API/worker 主链路已统一）
- P0-2：关键语义收敛到 policy -> action -> engine（select/assembly/reject/rollback 主路径已收口）
- P0-3：supersede 级联与 current revision 守卫已落地
- P0-4：resource-action 权限矩阵已接入 command 与直调入口

### 已处理的评审收口项

- 修复 `reject_assembly` 直调绕 engine
- 修复 `complete_assembly(done)` 非原子两步提交
- rollback 增加显式允许集合与校验逻辑
- 终态（`done`/`cancelled`）下 rollback/reject 关键路径拒绝测试已补齐
- 去除审批默认高权限 actor 回退
- 清理 dead code：`RollbackTargetAction`
- P1-4 第一阶段完成：pending mutation 增强确认映射（plan/review/node/candidate/assembly）
- P1-4 第一阶段完成：pending 状态机补齐 `pending -> timed_out -> failed`，超时不再永久阻塞按钮
- P1-4 第一阶段完成：projection sync hint TTL 与 pending 窗口对齐（10s -> 30s）
- P1-4 第一阶段完成：避免将 `workflow.v2.command.*` 入队事件误判为“已确认完成”
- P1-4 阶段二推进：后端 Pub/Sub 事件透传 `stream_entry_id`，前端按 entryId 标记“已入队待执行”
- P1-3 持续收口：Web 面板卡片操作接入 pending mutation 注册与禁用规则（与移动端语义对齐）
- P1-3 收口完成（workflow 主交互面）：Web 卡片新增 `可重试` 失败态提示，并区分 pending/timed_out 的禁用原因
- P1-3 收口完成（workflow 主交互面）：Web 重试前清理同目标 failed mutation，避免失败提示长时间残留

### 待完成（P1/P2）

- P1-1：fan-out / fan-in 并行执行与汇总门禁
- P1-2：前端动作矩阵与 runtime protocol 全量对齐
- P1-3：Web/App 交互一致性（非 workflow 主链路页面仍需逐页比对）
- P1-4：pending mutation 确认规则增强（阶段二：结合后端 `entryId` 与错误回流的精确失败归因）
- P2-1：`graphVersion` / `timelineVersion` / `eventSequence`
- P2-2：projection 补偿与重放工具化
- P2-3：policy 模板化扩展（generic -> coding/report/video）

### 当前发布结论（本轮）

- 仍偏离 SoT：无

Residual Risks：

1. info：command 端点为异步 fire-and-forget，前端依赖 pending mutation 覆盖（P1-4 阶段二补精确失败归因）
2. low：rollback 不级联 supersede 当前 node/candidate（P1-1 fan-out 场景可能需补充）

本轮已消减风险：

- worker 消费 -> `submit_command` 链路已补充 `start()->consume()->ack` 集成测试（`tests/test_workflow_workers.py`）
- command pending 已具备 entryId 级“入队可观测性”（`stream_entry_id` -> 前端 mutation 关联）
- 权限拒绝路径已补“副作用无损”断言（拒绝后不触发 engine.apply_event / db.commit）
- 汇总驳回后重选链路已补：reject 后再次选优会创建新 assembly，不污染已 rejected 版本
- outbox pending 可观测链路已补：发布 worker 启动前保持 pending，启动后转 published
- rollback M-2 已补：新增 `blocked -> planning` 与 `3 revision + target_revision_id` 精确回滚测试

---

## 1. 目标

本清单用于把当前 Workflow V2 从“最小可跑通”补齐到“架构一致、策略可治理、前后端可稳定协作”的状态。

优先级原则：

1. 先解决架构偏差（P0）
2. 再解决能力缺口与一致性（P1）
3. 最后解决增量性能与可演进性（P2）

---

## 2. P0（必须先做）

### P0-1 统一写路径为 command

- 目标：前端 V2 写操作统一走 `POST /api/workflows/{id}/commands`
- 当前问题：仍有资源式写接口与 command 并存，语义分散
- 主要改动：
  - 后端在 `workflow_constants` 补齐命令常量
  - API 层统一做 command 映射，保留资源式入口仅作兼容
  - Flutter `ApiClient` 所有语义写方法统一映射 command
- 影响文件：
  - `backend/app/services/workflow_constants.py`
  - `backend/app/api/workflows.py`
  - `flutter_app/lib/services/api_client.dart`
  - `flutter_app/lib/widgets/mobile/workflow_detail_screen.dart`
- 完成标准：
  - V2 UI 写操作不再直接依赖资源式写接口
  - command `eventType` 与文档协议一致

### P0-2 收敛到 engine + action 单入口

- 目标：状态语义由 policy 规划 action，再由 engine 执行；service 不再直写语义状态
- 当前问题：`WorkflowService` 存在绕过 policy 的直接状态更新
- 主要改动：
  - 把 `select/assembly/reject/rollback` 关键路径下沉为 action handler
  - service 仅保留事务边界、输入校验、组装调用
- 影响文件：
  - `backend/app/services/workflow_service.py`
  - `backend/app/services/workflow_policy.py`
  - `kernel/src/workflow_actions.py`
  - `kernel/src/graph_workflow.py`
- 完成标准：
  - 不再出现“policy 暂无动作，service 直改状态”的核心语义分叉

### P0-3 固化 supersede 规则

- 目标：revision 驳回后，旧 node/candidate 明确 supersede，避免混入当前视图
- 当前问题：规则在文档中明确，但代码执行不完整
- 主要改动：
  - 新增/完善 revision reject 级联策略
  - projection 只展示 active revision 视图，历史折叠
- 影响文件：
  - `kernel/src/graph_workflow.py`
  - `backend/app/repos/workflow_repo.py`
  - `backend/app/services/task_projection_service.py`
  - `tests/test_workflow_route_a.py`
  - `kernel/tests/test_graph_workflow.py`
- 完成标准：
  - reject 后旧节点不再参与当前 assembly 计算
  - 相关测试覆盖级联行为

### P0-4 三省六部权限矩阵 V2 化

- 目标：从硬编码审批角色升级为可配置 role-action-policy
- 当前问题：`ensure_review_actor` 仅允许少数角色，无法表达完整制度矩阵
- 主要改动：
  - 定义 V2 动作权限矩阵（workflow/revision/node/candidate/assembly）
  - 权限失败返回统一错误语义
- 影响文件：
  - `backend/app/services/workflow_policy_v2.py`
  - `backend/app/services/workflow_policy.py`
  - `tests/test_workflow_route_a.py`
- 完成标准：
  - 所有审批/回滚/选优动作均受矩阵治理
  - 测试覆盖允许与拒绝路径

---

## 3. P1（第二批）

### P1-1 fan-out / fan-in 真正落地

- 目标：方案批准后可并行生成多个 node，满足条件后自动汇总
- 影响文件：
  - `backend/app/services/workflow_policy.py`
  - `kernel/src/workflow_actions.py`
  - `backend/app/workers/node_dispatch_worker.py`
  - `backend/app/workers/assembly_worker.py`

### P1-2 前端动作矩阵与协议对齐

- 目标：动作可见性/禁用条件严格对齐 runtime protocol
- 影响文件：
  - `flutter_app/lib/widgets/mobile/workflow_detail_screen.dart`
  - `flutter_app/lib/providers/workflow_events_provider.dart`
  - `docs/design/frontend-workflow-v2-runtime-protocol.md`（必要时同步）

### P1-3 Web/App 交互一致性补齐

- 目标：Web Modal 与 Mobile Detail 在 V2 操作语义一致
- 影响文件：
  - `flutter_app/lib/widgets/panels/workflow_modal.dart`
  - `flutter_app/lib/widgets/panels/edict_board.dart`
  - `flutter_app/lib/widgets/mobile/workflow_detail_screen.dart`
- 完成标准：
  - 同一动作在两端一致的可见性、确认流程、错误提示

### P1-4 pending mutation 确认规则增强

- 目标：减少“同步中”误判与状态滞留
- 影响文件：
  - `flutter_app/lib/providers/workflow_events_provider.dart`
  - `flutter_app/lib/providers/workflow_projection_sync_provider.dart`

---

## 4. P2（第三批）

### P2-1 版本化增量协议

- 目标：后端补齐 `graphVersion` / `timelineVersion` / `eventSequence`
- 效果：前端可从 invalidate+refetch 升级为可证明 patch merge
- 影响文件：
  - `backend/app/api/workflows.py`
  - `backend/app/services/outbox_event_bus.py`
  - `flutter_app/lib/providers/workflow_events_provider.dart`

### P2-2 projection 补偿与重放工具化

- 目标：降低“workflow 数据待同步”窗口期
- 影响文件：
  - `backend/app/services/task_projection_service.py`
  - `backend/app/workers/projection_worker.py`
  - `backend/migration/recompute_workflow_projections.py`

### P2-3 policy 模板化扩展

- 目标：从 `generic` 平滑扩展到 `coding/report/video`，避免单 policy 膨胀
- 影响文件：
  - `backend/app/services/workflow_policy.py`
  - `backend/app/services/workflow_policy_v2.py`
  - `kernel/src/workflow_policy.py`

---

## 5. 建议排期

- 第 1 周：P0-1 + P0-2
- 第 2 周：P0-3 + P0-4
- 第 3 周：P1-1 + P1-2 + P1-3
- 第 4 周：P1-4 + P2-1 预埋字段

---

## 6. Review Prompt（可直接复用）

将下面 prompt 发给代码评审 Agent / Reviewer：

```text
请对 Workflow V2 改动做“架构一致性 + 行为回归”评审，重点不是代码风格，而是制度语义与实现是否一致。

评审范围：
1) 写路径是否统一为 /api/workflows/{id}/commands（前端与后端一致）
2) 关键状态推进是否全部通过 policy -> action -> engine 执行（避免 service 直写语义）
3) revision reject 后是否严格执行 supersede 级联，旧 node/candidate 不混入当前 assembly
4) 权限矩阵是否覆盖 workflow/revision/node/candidate/assembly 的关键动作
5) Web 与 App 在动作可见性、禁用条件、确认流程是否一致
6) pending mutation 的确认规则是否会造成误确认或长期“同步中”
7) 测试是否覆盖：成功路径、拒绝路径、并发边界、回滚路径

输出格式要求：
- 按严重级别列出问题：critical / major / minor
- 每条问题必须包含：触发条件、风险、复现场景、建议修复
- 明确指出“已满足设计目标”的部分和“仍偏离 SoT”的部分
- 若无问题，请明确写“未发现阻塞发布问题”，并给出剩余风险清单
```

