# Workflow V2 E2E Test Cases（基于当前 Edict 实现）

> 目标：覆盖当前 Workflow V2 在「命令入队 -> worker 执行 -> 投影刷新 -> Web/App 可见」的端到端主链路。
>
> 适用版本：当前 `v2` 分支（含 command 单入口、policy/action/engine 收口、pending mutation 机制）。

---

## 1) 范围与约束

- 覆盖对象：`backend`、`orchestrator/dispatcher/assembly/projection worker`、`flutter_app`（Web/App UI）。
- 关注重点：
  - 三省六部角色权限矩阵
  - command 异步语义（accepted + entryId）
  - FSM 合法迁移与终态拒绝
  - 投影一致性与 Web/App 交互一致性
- 不在本轮覆盖：
  - 压测/容量上限
  - P2 的增量版本协议（`graphVersion/timelineVersion/eventSequence`）

---

## 2) 测试数据建议

- 角色：
  - 审批角色：`zhongshu`、`emperor`
  - 执行角色：`libu`、`hubu`、`bingbu`、`xingbu`、`gongbu`、`api`、`flutter`
- 任务类型：`workflow_v2` / `generic`
- 环境：
  - Docker Compose：`backend + frontend + redis + postgres + workers`
  - WebSocket 开启

---

## 3) E2E 用例清单（推荐首批）

| ID | 优先级 | 场景 |
|---|---|---|
| E2E-001 | P0 | 正常主流程：草稿 -> 规划 -> 审批 -> 执行 -> 汇总通过 -> Done |
| E2E-002 | P0 | 方案驳回：revision 驳回后 node/candidate supersede 不污染当前视图 |
| E2E-003 | P0 | 汇总驳回：assembly reject 回到 executing，且后续可继续选优 |
| E2E-004 | P0 | 回滚：允许状态回滚成功，终态（done/cancelled）拒绝 |
| E2E-005 | P0 | 权限矩阵：非法 actor 提交 review 命令返回拒绝 |
| E2E-006 | P0 | command 异步语义：返回 accepted+entryId，前端 pending 正确展示 |
| E2E-007 | P1 | pending 超时与失败：pending -> timed_out -> failed -> 重试可恢复 |
| E2E-008 | P1 | worker 消费链路：consume -> submit_command -> ack 完整闭环 |
| E2E-009 | P1 | projection 一致性：关键状态变更后任务列表/详情一致 |
| E2E-010 | P1 | Web/App 一致性：同动作的可见性、禁用条件、提示一致 |
| E2E-011 | P1 | 兼容接口：compat 路由触发后仍走 command 链路且语义一致 |
| E2E-012 | P2 | 故障恢复：worker 重启后 pending 消费继续，系统最终一致 |

---

## 4) 详细步骤（可直接转自动化）

### E2E-001 正常主流程闭环

- **前置**：创建一个 workflow v2 任务，状态为 `draft/pending`。
- **步骤**：
  1. 发送 `start_planning` 命令。
  2. 提交方案 `submit_plan`。
  3. 审批角色执行 `approve_plan`。
  4. 推进 node 到 `ready/running`，完成 candidate。
  5. 选定 candidate，生成/更新 assembly。
  6. 审批 assembly（`approve_assembly`）。
- **预期**：
  - workflow 最终 `done`
  - timeline 有完整关键事件
  - task projection 状态与 workflow 一致
  - Web/App 均展示完成态

### E2E-002 方案驳回 supersede

- **步骤**：
  1. 完成 `submit_plan` 后执行 `reject_plan`。
  2. 重新进入 planning 并生成新 revision。
- **预期**：
  - 被驳回 revision 的 node/candidate 标记 superseded
  - 当前视图只展示 active revision 数据
  - 旧 candidate 不可用于当前 assembly

### E2E-003 汇总驳回回流

- **步骤**：
  1. 进入 awaiting final review（已有 assembly）。
  2. 执行 `reject_assembly`。
- **预期**：
  - workflow 回到 `executing`
  - assembly 状态更新为 rejected
  - 后续可重新选 candidate 并再次汇总

### E2E-004 回滚边界

- **步骤**：
  1. 在 `executing/assembling/awaiting_final_review` 分别发起 rollback。
  2. 在 `done/cancelled` 发起 rollback。
- **预期**：
  - 非终态：按策略允许时回到 planning
  - 终态：统一拒绝（错误语义一致）

### E2E-005 权限拒绝

- **步骤**：用非审批角色执行 `approve_plan/reject_plan/approve_assembly/reject_assembly/rollback`。
- **预期**：
  - API 返回权限错误（403/PolicyViolation）
  - 状态无副作用
  - Web/App 错误提示一致、可理解

### E2E-006 command accepted + entryId

- **步骤**：
  1. 提交任意命令（如 `start_planning`）。
  2. 记录返回 `entryId`。
  3. 监听 websocket/pending 状态。
- **预期**：
  - 接口返回 accepted + entryId
  - 前端 pending mutation 创建成功
  - 入队事件可与 entryId 对上（已入队可观测）

### E2E-007 pending 超时/失败与恢复

- **步骤**：
  1. 注入消费延迟或临时停 worker，观察 pending 超时。
  2. 验证 timed_out -> failed 迁移。
  3. 恢复 worker 后重试同动作。
- **预期**：
  - UI 显示“超时待确认/可重试”
  - 重试后 failed 标记可清理，不永久阻塞

### E2E-008 worker 消费闭环

- **步骤**：发送 command 后检查 orchestrator 消费与 ack。
- **预期**：
  - event 被消费且 ack
  - submit_command 被调用
  - 数据最终落库并可投影

### E2E-009 projection 一致性

- **步骤**：执行关键状态迁移（plan approve、candidate select、assembly approve/reject）。
- **预期**：
  - tasks live-status、workflow summary、graph/timeline 三者一致
  - 列表与详情不存在长期分叉

### E2E-010 Web/App 一致性

- **步骤**：在 Web 和 App 对同一 workflow 执行相同步骤。
- **预期**：
  - 动作按钮可见性一致
  - 禁用条件一致（pending/timed_out）
  - 错误提示与恢复路径一致

### E2E-011 compat 兼容入口

- **步骤**：通过旧兼容 API（stop/cancel/resume/review）触发动作。
- **预期**：
  - 最终进入 command 统一链路
  - 状态迁移和新入口一致

### E2E-012 故障恢复

- **步骤**：
  1. 命令入队后重启单个 worker。
  2. 观察系统是否继续消费并完成流程。
- **预期**：
  - 无永久卡死
  - 最终一致性成立

---

## 5) 自动化落地建议

- **API/服务层（pytest + async）**：
  - 先自动化 E2E-001 ~ E2E-006、E2E-008、E2E-009、E2E-011。
- **UI 层（Web/App 冒烟）**：
  - 优先 E2E-006、E2E-007、E2E-010（可用 Playwright + Flutter integration test）。
- **故障演练**：
  - E2E-012 作为 nightly 或发布前手动回归。

---

## 6) 发布前最小通过门槛（建议）

- 必过：E2E-001/002/003/004/005/006/008/009（8 条）
- 可延后但需记录：E2E-010/012
- 若 E2E-007 失败：禁止发布（会导致前端长期“同步中”或误判）

