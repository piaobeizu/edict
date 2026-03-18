# kernel

Framework-agnostic workflow engine kernel.

- **StateMachine** — Generic finite state machine with injectable transitions
- **TaskEntity** — Pure dataclass work item (no ORM binding)
- **WorkflowEngine** — Orchestrates create/transition/dispatch/progress
- **Ports** — Protocol interfaces (TaskRepo, EventBusPort, AgentExecutor, RoutingPolicy)
- **Adapters** — Concrete implementations (Postgres, Redis Streams, OpenClaw CLI, 三省六部 routing)

## Install

```bash
# From repo root
pip install -e ./kernel

# Or inside kernel/ directory
pip install -e .
```

## Quick usage

```python
from kernel import TaskEntity, WorkflowEngine

task = TaskEntity(id="JJC-demo-001", title="demo")
engine = WorkflowEngine(...)
engine.create(task)
```
