"""Adapters — edict_kernel 接口的具体实现。

每个 adapter 实现 edict_kernel.ports 中的一个 Protocol：
  - edict_routing.py   → RoutingPolicy  (三省六部业务路由)
  - pg_task_repo.py    → TaskRepo       (Postgres, 需安装 edict-kernel[postgres])
  - redis_event_bus.py → EventBusPort   (Redis Streams, 需安装 edict-kernel[redis])
  - openclaw_executor.py → AgentExecutor (OpenClaw CLI, 零额外依赖)
"""
