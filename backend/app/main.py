"""Edict Backend — FastAPI 应用入口。

Lifespan 管理：
- startup: 连接 Redis Event Bus, 初始化数据库
- shutdown: 关闭连接

路由：
- /api/tasks — 任务 CRUD
- /api/agents — Agent 信息
- /api/events — 事件查询
- /api/admin — 管理操作
- /ws — WebSocket 实时推送
"""

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .services.event_bus import get_event_bus
from .services.openclaw_runtime import sync_workspace_support_files
from .services.structured_log import setup_structured_logging
from .workers.inprocess_workflow_workers import InProcessWorkflowWorkers
from .api import tasks, agents, events, admin, websocket, insights, metrics, compat, files, notify, dashboard, workflows
from .services.task_service import TaskService
from .api import legacy

setup_structured_logging()
log = logging.getLogger("edict")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理。"""
    settings = get_settings()
    log.info(f"🏛️ Edict Backend starting on port {settings.port}...")

    # 连接 Event Bus
    bus = await get_event_bus()
    log.info("✅ Event Bus connected")
    workflow_workers = None
    if settings.workflow_workers_inprocess:
        workflow_workers = InProcessWorkflowWorkers()
        await workflow_workers.start()
        log.info("✅ In-process workflow workers started")

    try:
        synced = sync_workspace_support_files()
        log.info(f"✅ Workspace assets synced: soul={synced['soul']} scripts={synced['scripts']} memory={synced.get('memory', 0)} skills={synced.get('skills', 0)}")
    except Exception as e:
        log.warning(f"Workspace asset sync skipped: {e}")

    yield

    # 清理
    if workflow_workers is not None:
        await workflow_workers.stop()
    await bus.close()
    log.info("Edict Backend shutdown complete")


app = FastAPI(
    title="Edict 三省六部",
    description="事件驱动的 AI Agent 协作平台",
    version="2.0.0",
    lifespan=lifespan,
)

# CORS — 生产环境应配置具体 origins
_cors_origins = get_settings().cors_origins if hasattr(get_settings(), "cors_origins") else []
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins or ["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(tasks.router, prefix="/api/tasks", tags=["tasks"])
app.include_router(workflows.router, prefix="/api/workflows", tags=["workflows"])
app.include_router(agents.router, prefix="/api/agents", tags=["agents"])
app.include_router(events.router, prefix="/api/events", tags=["events"])
app.include_router(admin.router, prefix="/api/admin", tags=["admin"])
app.include_router(metrics.router, prefix="/api/admin", tags=["metrics"])
app.include_router(insights.router, prefix="/api", tags=["insights"])
app.include_router(compat.router, prefix="/api", tags=["compat"])
app.include_router(dashboard.router, prefix="/api", tags=["dashboard"])
app.include_router(dashboard.health_router, tags=["health"])
app.include_router(files.router, prefix="/api/files", tags=["files"])
app.include_router(websocket.router, tags=["websocket"])
app.include_router(legacy.router, prefix="/api/tasks", tags=["legacy"])
app.include_router(notify.router, prefix="/api", tags=["notify"])


@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.0.0", "engine": "edict"}


@app.get("/api")
async def api_root():
    return {
        "name": "Edict 三省六部 API",
        "version": "2.0.0",
        "endpoints": {
            "tasks": "/api/tasks",
            "agents": "/api/agents",
            "events": "/api/events",
            "admin": "/api/admin",
            "websocket": "/ws",
            "health": "/health",
        },
    }


@app.get("/api/live-status")
async def live_status_compat(svc: TaskService = Depends(tasks.get_task_service)):
    """兼容旧前端：/api/live-status -> /api/tasks/live-status。"""
    return await svc.get_live_status()
