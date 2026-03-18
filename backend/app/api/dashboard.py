"""Dashboard 兼容 API（v2）。"""

from __future__ import annotations

import asyncio
import datetime
import json
import os
import re
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, cast
from urllib.request import urlopen

from fastapi import APIRouter
from pydantic import BaseModel

from ..services.openclaw_runtime import (
    add_remote_skill as runtime_add_remote_skill,
    add_skill as runtime_add_skill,
    build_agent_config_payload,
    get_last_model_change_result as load_last_model_change_result,
    get_model_change_log as load_model_change_log,
    list_remote_skills,
    read_skill_content as runtime_read_skill_content,
    remove_remote_skill as runtime_remove_remote_skill,
    resolve_data_dir,
    set_agent_model,
    update_remote_skill as runtime_update_remote_skill,
)

router = APIRouter()
health_router = APIRouter()

_io_pool = ThreadPoolExecutor(max_workers=4)

_SAFE_NAME_RE = re.compile(r"^[a-zA-Z0-9_\-\u4e00-\u9fff]+$")
OCLAW_HOME = Path.home() / ".openclaw"

_AGENT_DEPTS = [
    {"id": "taizi", "label": "太子", "emoji": "👑", "role": "总分拣"},
    {"id": "zhongshu", "label": "中书省", "emoji": "📜", "role": "规划拆解"},
    {"id": "menxia", "label": "门下省", "emoji": "🔍", "role": "审核校验"},
    {"id": "shangshu", "label": "尚书省", "emoji": "📋", "role": "调度协调"},
    {"id": "libu", "label": "礼部", "emoji": "📖", "role": "内容创作"},
    {"id": "hubu", "label": "户部", "emoji": "📊", "role": "数据分析"},
    {"id": "bingbu", "label": "兵部", "emoji": "⚔️", "role": "代码工程"},
    {"id": "xingbu", "label": "刑部", "emoji": "⚖️", "role": "质量审查"},
    {"id": "gongbu", "label": "工部", "emoji": "🔧", "role": "部署运维"},
    {"id": "zaochao", "label": "钦天监", "emoji": "🌅", "role": "早朝简报"},
    {"id": "yushi", "label": "御史台", "emoji": "👁️", "role": "监察复盘"},
]


# ── helpers ──

def _now_iso() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

def _data_dir() -> Path:
    return resolve_data_dir()

def _read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default if default is not None else {}

# ══════════════════════════════════════
# 1. GET /healthz
# ══════════════════════════════════════

@health_router.get("/healthz")
async def healthz():
    data = _data_dir()
    checks = {
        "dataDir": data.is_dir(),
        "artifactsDir": (data / "artifacts").exists() or data.is_dir(),
        "openclawConfig": (OCLAW_HOME / "openclaw.json").exists(),
        "dataWritable": os.access(str(data), os.W_OK),
    }
    return {"status": "ok" if all(checks.values()) else "degraded", "ts": _now_iso(), "checks": checks}


# ══════════════════════════════════════
# 2-4. Simple JSON reads
# ══════════════════════════════════════

@router.get("/agent-config")
async def get_agent_config():
    return build_agent_config_payload()

@router.get("/model-change-log")
async def get_model_change_log():
    return load_model_change_log()

@router.get("/last-result")
async def get_last_result():
    return load_last_model_change_result()


# ══════════════════════════════════════
# 5. GET /agents-status
# ══════════════════════════════════════

def _check_gateway_probe() -> bool:
    try:
        resp = urlopen("http://127.0.0.1:18789/health", timeout=2)
        return resp.status == 200
    except Exception:
        return False

def _check_gateway_alive() -> bool:
    try:
        r = subprocess.run(["pgrep", "-f", "openclaw.*gateway"], capture_output=True, timeout=3)
        return r.returncode == 0
    except Exception:
        return False

def _check_agent_workspace(agent_id: str) -> bool:
    return (OCLAW_HOME / f"workspace-{agent_id}").is_dir()

def _check_agent_process(agent_id: str) -> bool:
    try:
        r = subprocess.run(["pgrep", "-f", f"openclaw.*--agent {agent_id}"], capture_output=True, timeout=3)
        return r.returncode == 0
    except Exception:
        return False

def _get_agent_session_status(agent_id: str) -> tuple[int, int, bool]:
    """Returns (last_ts_ms, session_count, is_busy)."""
    sessions_json = OCLAW_HOME / "agents" / agent_id / "sessions" / "sessions.json"
    if not sessions_json.exists():
        return 0, 0, False
    try:
        data = json.loads(sessions_json.read_text())
        sessions = data if isinstance(data, list) else data.get("sessions", [])
        count = len(sessions)
        last_ts = 0
        is_busy = False
        for s in sessions:
            ts = s.get("lastActiveTs", s.get("createdAt", 0))
            if isinstance(ts, (int, float)) and ts > last_ts:
                last_ts = int(ts)
            if s.get("status") == "busy":
                is_busy = True
        return last_ts, count, is_busy
    except Exception:
        return 0, 0, False

@router.get("/agents-status")
async def agents_status():
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_io_pool, _build_agents_status)

def _build_agents_status():
    gw_probe = _check_gateway_probe()
    gw_alive = _check_gateway_alive() or gw_probe
    agents = []
    seen = set()
    for dept in _AGENT_DEPTS:
        aid = dept["id"]
        if aid in seen:
            continue
        seen.add(aid)
        has_ws = _check_agent_workspace(aid)
        last_ts, sess_count, is_busy = _get_agent_session_status(aid)
        proc_alive = _check_agent_process(aid)
        if not has_ws:
            status, label = "unconfigured", "❌ 未配置"
        elif not gw_alive:
            status, label = "offline", "🔴 Gateway 离线"
        elif proc_alive or is_busy:
            status, label = "running", "🟢 运行中"
        elif last_ts > 0:
            age_ms = int(datetime.datetime.now().timestamp() * 1000) - last_ts
            if age_ms <= 600_000:
                status, label = "idle", "🟡 待命"
            elif age_ms <= 3_600_000:
                status, label = "idle", "⚪ 空闲"
            else:
                status, label = "idle", "⚪ 休眠"
        else:
            status, label = "idle", "⚪ 无记录"
        last_str = None
        if last_ts > 0:
            try:
                last_str = datetime.datetime.fromtimestamp(last_ts / 1000).strftime("%m-%d %H:%M")
            except Exception:
                pass
        agents.append({
            "id": aid, "label": dept["label"], "emoji": dept["emoji"], "role": dept["role"],
            "status": status, "statusLabel": label, "lastActive": last_str,
            "lastActiveTs": last_ts, "sessions": sess_count,
            "hasWorkspace": has_ws, "processAlive": proc_alive,
        })
    return {
        "ok": True,
        "gateway": {
            "alive": gw_alive, "probe": gw_probe,
            "status": "🟢 运行中" if gw_probe else ("🟡 进程在但无响应" if gw_alive else "🔴 未启动"),
        },
        "agents": agents, "checkedAt": _now_iso(),
    }


# ══════════════════════════════════════
# 6. GET /agent-activity/{agent_id}
# ══════════════════════════════════════

def _collect_message_text(msg: dict) -> str:
    parts = []
    for c in msg.get("content", []) or []:
        if c.get("type") == "text" and c.get("text"):
            parts.append(str(c["text"]))
        elif c.get("type") == "thinking" and c.get("thinking"):
            parts.append(str(c["thinking"]))
        elif c.get("type") == "tool_use":
            parts.append(json.dumps(c.get("input", {}), ensure_ascii=False))
    for key in ("output", "stdout", "stderr", "message"):
        val = (msg.get("details") or {}).get(key)
        if isinstance(val, str) and val:
            parts.append(val)
    return "".join(parts)

def _parse_activity_entry(item: dict) -> dict | None:
    msg = item.get("message") or {}
    role = str(msg.get("role", "")).strip().lower()
    ts = item.get("timestamp", "")
    if role == "assistant":
        text = thinking = ""
        tool_calls = []
        for c in msg.get("content", []) or []:
            if c.get("type") == "text" and c.get("text") and not text:
                text = str(c["text"]).strip()
            elif c.get("type") == "thinking" and c.get("thinking") and not thinking:
                thinking = str(c["thinking"]).strip()[:200]
            elif c.get("type") == "tool_use":
                tool_calls.append({"name": c.get("name", ""), "input_preview": json.dumps(c.get("input", {}), ensure_ascii=False)[:100]})
        if not (text or thinking or tool_calls):
            return None
        entry: dict[str, Any] = {"at": ts, "kind": "assistant"}
        if text:
            entry["text"] = text[:300]
        if thinking:
            entry["thinking"] = thinking
        if tool_calls:
            entry["tools"] = tool_calls
        return entry
    if role in ("toolresult", "tool_result"):
        details = msg.get("details") or {}
        code = details.get("exitCode", details.get("code", details.get("status")))
        output = ""
        for c in msg.get("content", []) or []:
            if c.get("type") == "text" and c.get("text"):
                output = str(c["text"]).strip()[:200]
                break
        if not output:
            for key in ("output", "stdout", "stderr", "message"):
                val = details.get(key)
                if isinstance(val, str) and val.strip():
                    output = val.strip()[:200]
                    break
        entry = {"at": ts, "kind": "tool_result", "tool": msg.get("toolName", msg.get("name", "")), "exitCode": code, "output": output}
        dur = details.get("durationMs")
        if isinstance(dur, (int, float)):
            entry["durationMs"] = int(dur)
        return entry
    if role == "user":
        text = ""
        for c in msg.get("content", []) or []:
            if c.get("type") == "text" and c.get("text"):
                text = str(c["text"]).strip()
                break
        return {"at": ts, "kind": "user", "text": text[:200]} if text else None
    return None

@router.get("/agent-activity/{agent_id}")
async def agent_activity(agent_id: str):
    if not _SAFE_NAME_RE.match(agent_id):
        return {"ok": False, "error": "invalid agent_id"}
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_io_pool, _collect_agent_activity, agent_id)

def _collect_agent_activity(agent_id: str):
    sessions_dir = OCLAW_HOME / "agents" / agent_id / "sessions"
    if not sessions_dir.exists():
        return {"ok": True, "agentId": agent_id, "activity": []}
    jsonl_files = sorted(sessions_dir.glob("*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)[:1]
    entries = []
    for sf in jsonl_files:
        try:
            lines = sf.read_text(errors="ignore").splitlines()
        except Exception:
            continue
        for ln in lines:
            try:
                item = json.loads(ln)
            except Exception:
                continue
            entry = _parse_activity_entry(item)
            if entry:
                entries.append(entry)
            if len(entries) >= 30:
                break
    return {"ok": True, "agentId": agent_id, "activity": entries[-30:]}


# ══════════════════════════════════════
# 7. POST /agent-wake
# ══════════════════════════════════════

class AgentWakeBody(BaseModel):
    agentId: str
    message: str = ""

@router.post("/agent-wake")
async def agent_wake(body: AgentWakeBody):
    agent_id = body.agentId.strip()
    if not agent_id or not _SAFE_NAME_RE.match(agent_id):
        return {"ok": False, "error": "agentId required"}
    if not _check_agent_workspace(agent_id):
        return {"ok": False, "error": f"{agent_id} 工作空间不存在"}
    if not _check_gateway_alive():
        return {"ok": False, "error": "Gateway 未启动"}
    msg = body.message.strip() or f"🔔 系统心跳检测 — 请回复 OK 确认在线。当前时间: {_now_iso()}"
    def do_wake():
        cmd = ["openclaw", "agent", "--agent", agent_id, "-m", msg, "--timeout", "120"]
        for attempt in range(1, 3):
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=130)
                if r.returncode == 0:
                    break
            except Exception:
                pass
    threading.Thread(target=do_wake, daemon=True).start()
    return {"ok": True, "message": f"已发送唤醒消息给 {agent_id}"}


# ══════════════════════════════════════
# 8. GET /remote-skills-list
# ══════════════════════════════════════

@router.get("/remote-skills-list")
@router.post("/remote-skills-list")
async def remote_skills_list():
    return list_remote_skills()


# ══════════════════════════════════════
# 9. GET /skill-content/{agent_id}/{skill_name}
# ══════════════════════════════════════

@router.get("/skill-content/{agent_id}/{skill_name}")
async def skill_content(agent_id: str, skill_name: str):
    return runtime_read_skill_content(agent_id, skill_name)


# ══════════════════════════════════════
# 10. POST /add-skill
# ══════════════════════════════════════

class AddSkillBody(BaseModel):
    agentId: str
    skillName: str = ""
    name: str = ""
    description: str = ""
    trigger: str = ""

@router.post("/add-skill")
async def add_skill(body: AddSkillBody):
    skill_name = (body.skillName or body.name).strip()
    if not body.agentId.strip() or not skill_name:
        return {"ok": False, "error": "agentId and skillName required"}
    return runtime_add_skill(body.agentId.strip(), skill_name, body.description.strip() or skill_name, body.trigger.strip())


# ══════════════════════════════════════
# 11. POST /add-remote-skill
# ══════════════════════════════════════

class AddRemoteSkillBody(BaseModel):
    agentId: str
    skillName: str
    sourceUrl: str
    description: str = ""

@router.post("/add-remote-skill")
async def add_remote_skill(body: AddRemoteSkillBody):
    return runtime_add_remote_skill(body.agentId.strip(), body.skillName.strip(), body.sourceUrl.strip(), body.description)


# ══════════════════════════════════════
# 12. POST /update-remote-skill
# ══════════════════════════════════════

class SkillRefBody(BaseModel):
    agentId: str
    skillName: str

@router.post("/update-remote-skill")
async def update_remote_skill(body: SkillRefBody):
    return runtime_update_remote_skill(body.agentId.strip(), body.skillName.strip())


# ══════════════════════════════════════
# 13. POST /remove-remote-skill
# ══════════════════════════════════════

@router.post("/remove-remote-skill")
async def remove_remote_skill(body: SkillRefBody):
    return runtime_remove_remote_skill(body.agentId.strip(), body.skillName.strip())


# ══════════════════════════════════════
# 14. POST /set-model
# ══════════════════════════════════════

class SetModelBody(BaseModel):
    agentId: str
    model: str

@router.post("/set-model")
async def set_model(body: SetModelBody):
    return set_agent_model(body.agentId.strip(), body.model.strip())


# ══════════════════════════════════════
# 15. POST /repair-flow-order
# ══════════════════════════════════════

@router.post("/repair-flow-order")
async def repair_flow_order():
    """修复历史任务首条流转错序 — 从 Postgres DB 读写。"""
    from app.db import async_session
    from app.models.task import Task
    from sqlalchemy import select

    fixed, fixed_ids = 0, []
    async with async_session() as db:
        result = await db.execute(select(Task))
        tasks = list(result.scalars().all())
        for task in tasks:
            tid = str(task.id)
            if not tid.startswith("JJC-"):
                continue
            flow_log_raw = cast(Any, task).flow_log
            flow_log = list(flow_log_raw) if isinstance(flow_log_raw, list) else []
            if not flow_log:
                continue
            first = flow_log[0]
            if first.get("from") != "皇上" or first.get("to") != "中书省":
                continue
            first["to"] = "太子"
            if str(cast(Any, task).state) == "Zhongshu" and str(cast(Any, task).org) == "中书省" and len(flow_log) == 1:
                cast(Any, task).state = "Taizi"
                cast(Any, task).org = "太子"
                cast(Any, task).now = "等待太子接旨分拣"
            cast(Any, task).flow_log = flow_log
            from datetime import datetime, timezone
            cast(Any, task).updated_at = datetime.now(timezone.utc)
            fixed += 1
            fixed_ids.append(tid)
        if fixed:
            await db.commit()
    return {"ok": True, "count": fixed, "taskIds": fixed_ids[:80], "more": max(0, fixed - 80), "checkedAt": _now_iso()}


# ══════════════════════════════════════
# 16. POST /task-todos
# ══════════════════════════════════════

class TaskTodosBody(BaseModel):
    taskId: str
    todos: list[dict[str, Any]] = []

@router.post("/task-todos")
async def task_todos(body: TaskTodosBody):
    """更新任务 todos — 从 Postgres DB 读写。"""
    task_id = body.taskId.strip()
    todos = body.todos
    if not task_id:
        return {"ok": False, "error": "taskId required"}
    if not isinstance(todos, list) or len(todos) > 200:
        return {"ok": False, "error": "todos must be a list (max 200)"}
    valid_statuses = {"not-started", "in-progress", "completed"}
    for td in todos:
        if not isinstance(td, dict) or "id" not in td or "title" not in td:
            return {"ok": False, "error": "each todo must have id and title"}
        if td.get("status", "not-started") not in valid_statuses:
            td["status"] = "not-started"

    from app.db import async_session
    from app.models.task import Task

    async with async_session() as db:
        task = await db.get(Task, task_id)
        if task is None:
            return {"ok": False, "error": f"任务 {task_id} 不存在"}
        cast(Any, task).todos = todos
        from datetime import datetime, timezone
        cast(Any, task).updated_at = datetime.now(timezone.utc)
        await db.commit()
    return {"ok": True, "message": f"{task_id} todos 已更新"}
