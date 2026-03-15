# edict-kernel

Framework-agnostic workflow engine kernel.

- **StateMachine** — Generic finite state machine with injectable transitions
- **TaskEntity** — Pure dataclass work item (no ORM binding)
- **WorkflowEngine** — Orchestrates create/transition/dispatch/progress
- **Ports** — Protocol interfaces (TaskRepo, EventBusPort, AgentExecutor, RoutingPolicy)
- **Adapters** — Concrete implementations (Postgres, Redis Streams, OpenClaw CLI, 三省六部 routing)

## Install

```bash
pip install edict-kernel              # core only (zero deps)
pip install edict-kernel[postgres]    # + SQLAlchemy/asyncpg
pip install edict-kernel[redis]       # + Redis
pip install edict-kernel[all]         # everything
```
