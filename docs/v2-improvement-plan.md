# Edict v2 完善工作细化方案

> 目标：把 v2 从“可运行”提升到“可稳定上线、可观测、可回放、可扩展”。
>
> 适用范围：`/root/code/python/edict/edict`（FastAPI + Redis EventBus + Worker + React 前端）。

---

## 1. 当前问题摘要

基于现状运行与日志，v2 主要短板集中在以下 5 类：

1. 事件链路不够“抗故障”：派发/回执在限流和超时下会出现重试风暴、重复派发、状态与展示不一致。
2. 产出回填不稳定：`todo/detail` 与 `done/output` 经常缺失，UI 看不到每步结果。
3. 可观测性不足：缺少统一 trace id、关键指标（失败率/重试数/队列积压）和告警阈值。
4. 回放与运维能力不足：失败任务缺少标准死信池与一键重放机制。
5. 测试覆盖不足：状态机、事件重试、并发冲突、端到端链路缺少稳定回归。

---

## 2. 目标定义（Definition of Done）

当满足以下条件，视为 v2 完善完成：

- 稳定性：连续 7 天运行，任务成功率 >= 98%，无“卡状态 > 10 分钟”任务。
- 一致性：任务 `state`、`todos`、`progress`、`output` 四者一致，UI 与数据库一致率 100%。
- 可观测：可实时看到派发时延、重试次数、失败原因 TopN、队列积压。
- 可运维：失败任务可一键重放；可按 task_id 完整回放全链路。
- 可回归：CI 每次变更执行单测 + 集成 + E2E 全通过。

---

## 3. 分阶段实施计划

建议按 4 个 Sprint（每个 1 周）推进。

### Sprint 1（P0）核心稳定性与幂等

#### 3.1 状态机与幂等

- 工作项
  - 在 Orchestrator 增加状态跳转白名单校验（非法跳转直接拒绝并记录审计日志）。
  - 增加“事件去重键”（`task_id + stage + source + nonce`）。
  - Dispatch Worker 增加幂等防重：同一 `task_id + target_agent + dispatch_round` 只执行一次。
- 涉及模块
  - `edict/backend/app/workers/orchestrator_worker.py`
  - `edict/backend/app/workers/dispatch_worker.py`
  - `edict/backend/app/models/`（新增去重字段/索引）
- 验收标准
  - 压测下不出现重复派发。
  - 非法状态流转被拒绝并可追溯。
- 预估工时：2.5 人天

#### 3.2 重试策略分级

- 工作项
  - 区分错误类型：`rate_limit / timeout / network / business_error`。
  - 对 `rate_limit` 使用指数退避 + 随机抖动 + 最大等待上限。
  - 对 `business_error` 禁止盲重试，直接进失败池。
- 涉及模块
  - `edict/backend/app/workers/dispatch_worker.py`
  - `edict/backend/app/services/event_bus.py`
- 验收标准
  - 不再出现高频重试打满 API 的情况。
  - 失败原因分类准确可查询。
- 预估工时：2 人天

#### 3.3 死信队列（DLQ）+ 手动重放

- 工作项
  - 新增 `task.dispatch.dead_letter` 事件流。
  - 提供 API：查询失败任务、按 task_id 重放。
- 涉及模块
  - `edict/backend/app/api/`
  - `edict/backend/app/services/event_bus.py`
- 验收标准
  - 任一失败任务可在后台页面或 API 一键重放。
- 预估工时：1.5 人天

---

### Sprint 2（P0）产出可见性与前后端一致性

#### 3.4 统一“产出回填协议”

- 工作项
  - 统一定义每步产出结构：`todo.detail`、`output`、`summary`、`artifacts[]`。
  - 在 Worker 侧做兜底：若 agent 未主动写 `done`，系统自动回填最小摘要。
- 涉及模块
  - `edict/backend/app/workers/orchestrator_worker.py`
  - `edict/backend/app/services/`（新建 output_normalizer）
  - `edict/frontend/src/`（展示 artifacts）
- 验收标准
  - 每个任务在 UI 都能看到“每步输出 + 最终输出”。
- 预估工时：2 人天

#### 3.5 任务详情页增强

- 工作项
  - 增加“步骤产出”时间线（按 taizi -> zhongshu -> menxia -> shangshu -> 六部）。
  - 增加“失败重试记录”面板（错误码、重试次数、最后一次错误）。
  - 增加“产出文件链接”面板（宿主目录/容器路径）。
- 涉及模块
  - `edict/frontend/src/pages/TaskDetail*`
  - `edict/frontend/src/components/*`
- 验收标准
  - 不依赖飞书即可在 UI 查看完整执行过程。
- 预估工时：2.5 人天

#### 3.6 审批节点一致性修复

- 工作项
  - 修复“流程已结束但太子回奏仍进行中”的 UI 状态漂移。
  - 用后端状态机单一真相驱动前端（不再由前端推断）。
- 验收标准
  - `Done` 任务的 todo 状态全部收敛为最终一致状态。
- 预估工时：1 人天

---

### Sprint 3（P1）可观测性与运维

#### 3.7 指标体系（Metrics）

- 工作项
  - 暴露指标：任务成功率、平均时延、重试次数、队列积压、限流次数。
  - 增加按 agent 维度统计（taizi/zhongshu/...）。
- 涉及模块
  - `edict/backend/app/main.py`（metrics endpoint）
  - worker 日志与统计中间件
- 验收标准
  - 可通过 `/metrics` 拉取关键指标并画图。
- 预估工时：2 人天

#### 3.8 结构化日志 + Trace

- 工作项
  - 全链路统一 `trace_id = task_id`，所有日志可 grep 回放。
  - 日志统一 JSON 格式，字段固定（time, level, task_id, stage, error_code）。
- 验收标准
  - 任一异常可以 3 分钟内定位到具体阶段。
- 预估工时：1.5 人天

#### 3.9 运维工具

- 工作项
  - 增加命令：`replay-task`, `mark-done`, `requeue-dead-letter`。
  - 增加“限流保护模式”（临时降并发）。
- 验收标准
  - 运维无需改数据库，靠命令即可处理 80% 线上问题。
- 预估工时：1.5 人天

---

### Sprint 4（P1）测试与发布质量

#### 3.10 测试矩阵补齐

- 工作项
  - 单测：状态机、重试分类、幂等去重。
  - 集成：Redis Stream + Worker + DB + openclaw mock。
  - E2E：创建任务到回奏全链路。
- 验收标准
  - 关键链路覆盖率 >= 80%。
- 预估工时：3 人天

#### 3.11 CI/CD 门禁

- 工作项
  - CI 固定流水线：lint -> typecheck -> tests -> migration check。
  - PR 必须通过门禁才能合并。
- 验收标准
  - main 分支无红灯构建。
- 预估工时：1 人天

#### 3.12 回归基线与演练

- 工作项
  - 编写故障演练脚本（429、网关超时、Redis 断连）。
  - 每周一次回归演练并输出报告。
- 验收标准
  - 故障场景均有明确处置 SOP。
- 预估工时：1 人天

---

## 4. 总工时与优先级

- P0（Sprint 1 + Sprint 2）：约 11.5 人天
- P1（Sprint 3 + Sprint 4）：约 10 人天
- 总计：约 21.5 人天（1 人约 4-5 周，2 人约 2-3 周）

建议先做 P0，再做 P1。

---

## 5. 任务拆解清单（可直接建 Issue）

1. `v2-p0-state-machine-idempotency`
2. `v2-p0-dispatch-retry-policy`
3. `v2-p0-dead-letter-and-replay`
4. `v2-p0-output-contract-and-backfill`
5. `v2-p0-task-detail-activity-ui`
6. `v2-p0-approval-state-consistency`
7. `v2-p1-metrics-observability`
8. `v2-p1-structured-logging-trace`
9. `v2-p1-ops-tooling`
10. `v2-p1-test-matrix-ci-gate`

---

## 6. 风险与对策

- 风险：第三方 API rate limit 频繁触发，导致链路抖动。
  - 对策：并发阈值 + 退避 + 多 key 轮转 + 降级模型。

- 风险：Agent 行为不可控，导致 `todo/output` 漏写。
  - 对策：后端回填兜底，不依赖 Agent 自觉。

- 风险：状态机与 UI 双方各自推断状态，造成漂移。
  - 对策：以后端状态机为唯一真相，前端只展示。

---

## 7. 立即可执行的下一步（本周）

1. 先落地 P0-1（幂等 + 状态机校验）。
2. 同步落地 P0-2（重试策略分级，先止血限流风暴）。
3. 并行做 P0-4（产出回填协议），让 UI 先可见每步结果。

完成以上三项后，v2 的“可用性体感”会明显提升。
