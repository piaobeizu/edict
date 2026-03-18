# Edict Agent 架构重设计文档

> ⚠️ **文档状态说明（重要）**：本文件是早期架构设计草案，**不代表当前实现现状**。请优先参考：
> - [`../../architecture/task-dispatch-architecture.md`](../../architecture/task-dispatch-architecture.md)（任务分发与流转实现）
> - [`../../architecture/code-structure.md`](../../architecture/code-structure.md)（当前代码结构与分层）

## 1. 设计目标
- **可观测性**：Dashboard 能实时显示每个 agent 的思考流（thoughts）和 todo 变更。
- **可重放 & 审计**：所有事件和状态变更持久化，可回溯。
- **可控流程**：保留三省六部逻辑，事件驱动，支持人工干预。
- **实时与可扩展**：低延迟交互，支持水平扩展。
- **结构化任务与可插拔 skill**：todo 与思考结构化，便于 UI 渲染和再利用。

## 2. 总体组件
1. **API Gateway / Control Plane**（REST + WebSocket）
2. **Orchestrator（调度核心）**
3. **Event Bus / Stream Layer**（Redis Streams / NATS / Kafka）
4. **Agent Runtime Pool**
5. **Model / LLM Pool**
6. **Task Store / Audit DB**（Postgres + JSONB）
7. **Realtime Dashboard**（WebSocket 客户端）
8. **Observability / Tracing**（Prometheus + Grafana + OpenTelemetry）

## 3. 通信模式
- **Event-Driven**: 所有 agent 间通信通过 Event Bus
- **主题示例**: `task.created`, `task.planning`, `task.review.request`, `task.review.result`, `task.dispatch`, `agent.thoughts`, `agent.todo.update`, `task.status`, `heartbeat`

## 4. 技术栈建议
| 层 | 技术 |
|----|------|
| Event Bus | Redis Streams |
| API | FastAPI |
| WS | FastAPI WebSocket |
| DB | Postgres |
| Agent Runtime | Python asyncio worker |
| Frontend | React + Zustand |

---
**备注**：此文档为早期架构设计草案，包含事件规范、WebSocket 协议、时序图和 JSON Schema。当前实现已演进，请以正式架构文档为准。
