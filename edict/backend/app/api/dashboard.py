"""Dashboard 兼容 API — 补全 dashboard/server.py 中 FastAPI 缺失的 16 个端点。"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()
health_router = APIRouter()

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
    for p in [Path("/app/data"), Path.cwd() / "data"]:
        if p.exists() and p.is_dir():
            return p
    return Path("/app/data")

def _scripts_dir() -> Path:
    for p in [Path("/app/scripts"), Path.cwd() / "scripts"]:
        if p.exists() and p.is_dir():
            return p
    return Path("/app/scripts")

def _read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default if default is not None else {}

def _write_json(path: Path, data: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def _compute_checksum(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:12]

def _run_script_async(*args: str) -> None:
    def _run():
        try:
            subprocess.run(list(args), timeout=30, capture_output=True)
        except Exception:
            pass
    threading.Thread(target=_run, daemon=True).start()


# ══════════════════════════════════════
# 1. GET /healthz
# ══════════════════════════════════════

@health_router.get("/healthz")
async def healthz():
    data = _data_dir()
    checks = {
        "dataDir": data.is_dir(),
        "tasksReadable": (data / "tasks_source.json").exists(),
        "dataWritable": os.access(str(data), os.W_OK),
    }
    return {"status": "ok" if all(checks.values()) else "degraded", "ts": _now_iso(), "checks": checks}


# ══════════════════════════════════════
# 2-4. Simple JSON reads
# ══════════════════════════════════════

@router.get("/agent-config")
async def get_agent_config():
    return _read_json(_data_dir() / "agent_config.json", {})

@router.get("/model-change-log")
async def get_model_change_log():
    return _read_json(_data_dir() / "model_change_log.json", [])

@router.get("/last-result")
async def get_last_result():
    return _read_json(_data_dir() / "last_model_change_result.json", {})


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
    remote_skills = []
    for ws_dir in OCLAW_HOME.glob("workspace-*"):
        agent_id = ws_dir.name.replace("workspace-", "")
        skills_dir = ws_dir / "skills"
        if not skills_dir.exists():
            continue
        for skill_dir in skills_dir.iterdir():
            if not skill_dir.is_dir():
                continue
            source_json = skill_dir / ".source.json"
            if not source_json.exists():
                continue
            try:
                info = json.loads(source_json.read_text())
                remote_skills.append({
                    "skillName": skill_dir.name, "agentId": agent_id,
                    "sourceUrl": info.get("sourceUrl", ""), "description": info.get("description", ""),
                    "localPath": str(skill_dir / "SKILL.md"),
                    "addedAt": info.get("addedAt", ""), "lastUpdated": info.get("lastUpdated", ""),
                    "status": "valid" if (skill_dir / "SKILL.md").exists() else "not-found",
                })
            except Exception:
                pass
    return {"ok": True, "remoteSkills": remote_skills, "count": len(remote_skills), "listedAt": _now_iso()}


# ══════════════════════════════════════
# 9. GET /skill-content/{agent_id}/{skill_name}
# ══════════════════════════════════════

@router.get("/skill-content/{agent_id}/{skill_name}")
async def skill_content(agent_id: str, skill_name: str):
    if not _SAFE_NAME_RE.match(agent_id) or not _SAFE_NAME_RE.match(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    cfg = _read_json(_data_dir() / "agent_config.json", {})
    agents = cfg.get("agents", [])
    ag = next((a for a in agents if a.get("id") == agent_id), None)
    if not ag:
        return {"ok": False, "error": f"Agent {agent_id} 不存在"}
    sk = next((s for s in ag.get("skills", []) if s.get("name") == skill_name), None)
    if not sk:
        return {"ok": False, "error": f"技能 {skill_name} 不存在"}
    skill_path = Path(sk.get("path", "")).resolve()
    allowed = (OCLAW_HOME.resolve(), _data_dir().parent.resolve())
    if not any(str(skill_path).startswith(str(r)) for r in allowed):
        return {"ok": False, "error": "路径不在允许的目录范围内"}
    if not skill_path.exists():
        return {"ok": True, "name": skill_name, "agent": agent_id, "content": "(SKILL.md 文件不存在)", "path": str(skill_path)}
    try:
        return {"ok": True, "name": skill_name, "agent": agent_id, "content": skill_path.read_text(), "path": str(skill_path)}
    except Exception as e:
        return {"ok": False, "error": str(e)}


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
    agent_id = body.agentId.strip()
    skill_name = (body.skillName or body.name).strip()
    if not agent_id or not skill_name:
        return {"ok": False, "error": "agentId and skillName required"}
    if not _SAFE_NAME_RE.match(agent_id) or not _SAFE_NAME_RE.match(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    desc = body.description.strip() or skill_name
    trigger = body.trigger.strip()
    workspace = OCLAW_HOME / f"workspace-{agent_id}" / "skills" / skill_name
    workspace.mkdir(parents=True, exist_ok=True)
    trigger_section = f"\n## 触发条件\n{trigger}\n" if trigger else ""
    template = (
        f"---\nname: {skill_name}\ndescription: {desc}\n---\n\n"
        f"# {skill_name}\n\n{desc}\n{trigger_section}\n"
        f"## 输入\n\n<!-- 说明此技能接收什么输入 -->\n\n"
        f"## 处理流程\n\n1. 步骤一\n2. 步骤二\n\n"
        f"## 输出规范\n\n<!-- 说明产出物格式与交付要求 -->\n\n"
        f"## 注意事项\n\n- (在此补充约束、限制或特殊规则)\n"
    )
    (workspace / "SKILL.md").write_text(template)
    scripts = _scripts_dir()
    _run_script_async("python3", str(scripts / "sync_agent_config.py"))
    return {"ok": True, "message": f"技能 {skill_name} 已添加", "path": str(workspace / "SKILL.md")}


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
    agent_id, skill_name, source_url = body.agentId.strip(), body.skillName.strip(), body.sourceUrl.strip()
    if not agent_id or not skill_name or not source_url:
        return {"ok": False, "error": "agentId, skillName, and sourceUrl required"}
    if not _SAFE_NAME_RE.match(agent_id) or not _SAFE_NAME_RE.match(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    # Download
    try:
        if source_url.startswith("https://"):
            req = Request(source_url, headers={"User-Agent": "OpenClaw-SkillManager/1.0"})
            resp = urlopen(req, timeout=10)
            content = resp.read(10 * 1024 * 1024).decode("utf-8")
        elif source_url.startswith("/") or source_url.startswith("."):
            lp = Path(source_url).resolve()
            if not lp.exists():
                return {"ok": False, "error": f"本地文件不存在: {lp}"}
            content = lp.read_text()
        else:
            return {"ok": False, "error": "仅支持 https:// 或本地路径"}
    except Exception as e:
        return {"ok": False, "error": f"文件读取失败: {str(e)[:100]}"}
    if not content.startswith("---"):
        return {"ok": False, "error": "文件格式无效（缺少 YAML frontmatter）"}
    workspace = OCLAW_HOME / f"workspace-{agent_id}" / "skills" / skill_name
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "SKILL.md").write_text(content)
    source_info = {"skillName": skill_name, "sourceUrl": source_url, "description": body.description,
                   "addedAt": _now_iso(), "lastUpdated": _now_iso(), "checksum": _compute_checksum(content), "status": "valid"}
    (workspace / ".source.json").write_text(json.dumps(source_info, ensure_ascii=False, indent=2))
    _run_script_async("python3", str(_scripts_dir() / "sync_agent_config.py"))
    return {"ok": True, "message": f"技能 {skill_name} 已从远程源添加", "skillName": skill_name, "agentId": agent_id,
            "source": source_url, "localPath": str(workspace / "SKILL.md"), "size": len(content), "addedAt": _now_iso()}


# ══════════════════════════════════════
# 12. POST /update-remote-skill
# ══════════════════════════════════════

class SkillRefBody(BaseModel):
    agentId: str
    skillName: str

@router.post("/update-remote-skill")
async def update_remote_skill(body: SkillRefBody):
    agent_id, skill_name = body.agentId.strip(), body.skillName.strip()
    if not _SAFE_NAME_RE.match(agent_id) or not _SAFE_NAME_RE.match(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    source_json = OCLAW_HOME / f"workspace-{agent_id}" / "skills" / skill_name / ".source.json"
    if not source_json.exists():
        return {"ok": False, "error": f"技能 {skill_name} 不是远程 skill"}
    info = json.loads(source_json.read_text())
    url = info.get("sourceUrl", "")
    if not url:
        return {"ok": False, "error": "源 URL 不存在"}
    result = await add_remote_skill(AddRemoteSkillBody(agentId=agent_id, skillName=skill_name, sourceUrl=url, description=info.get("description", "")))
    if isinstance(result, dict) and result.get("ok"):
        result["message"] = "技能已更新"
    return result


# ══════════════════════════════════════
# 13. POST /remove-remote-skill
# ══════════════════════════════════════

@router.post("/remove-remote-skill")
async def remove_remote_skill(body: SkillRefBody):
    agent_id, skill_name = body.agentId.strip(), body.skillName.strip()
    if not _SAFE_NAME_RE.match(agent_id) or not _SAFE_NAME_RE.match(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    workspace = OCLAW_HOME / f"workspace-{agent_id}" / "skills" / skill_name
    if not workspace.exists():
        return {"ok": False, "error": f"技能不存在: {skill_name}"}
    if not (workspace / ".source.json").exists():
        return {"ok": False, "error": f"技能 {skill_name} 不是远程 skill"}
    try:
        shutil.rmtree(workspace)
        _run_script_async("python3", str(_scripts_dir() / "sync_agent_config.py"))
        return {"ok": True, "message": f"技能 {skill_name} 已从 {agent_id} 移除"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ══════════════════════════════════════
# 14. POST /set-model
# ══════════════════════════════════════

class SetModelBody(BaseModel):
    agentId: str
    model: str

@router.post("/set-model")
async def set_model(body: SetModelBody):
    agent_id, model = body.agentId.strip(), body.model.strip()
    if not agent_id or not model:
        return {"ok": False, "error": "agentId and model required"}
    data = _data_dir()
    pending_path = data / "pending_model_changes.json"
    current = _read_json(pending_path, [])
    if not isinstance(current, list):
        current = []
    current = [x for x in current if x.get("agentId") != agent_id]
    current.append({"agentId": agent_id, "model": model})
    _write_json(pending_path, current)
    scripts = _scripts_dir()
    def apply_async():
        try:
            subprocess.run(["python3", str(scripts / "apply_model_changes.py")], timeout=30)
            subprocess.run(["python3", str(scripts / "sync_agent_config.py")], timeout=10)
        except Exception:
            pass
    threading.Thread(target=apply_async, daemon=True).start()
    return {"ok": True, "message": f"Queued: {agent_id} → {model}"}


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
            flow_log = list(task.flow_log or [])
            if not flow_log:
                continue
            first = flow_log[0]
            if first.get("from") != "皇上" or first.get("to") != "中书省":
                continue
            first["to"] = "太子"
            if task.state == "Zhongshu" and task.org == "中书省" and len(flow_log) == 1:
                task.state = "Taizi"
                task.org = "太子"
                task.now = "等待太子接旨分拣"
            task.flow_log = flow_log
            from datetime import datetime, timezone
            task.updated_at = datetime.now(timezone.utc)
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
        if not task:
            return {"ok": False, "error": f"任务 {task_id} 不存在"}
        task.todos = todos
        from datetime import datetime, timezone
        task.updated_at = datetime.now(timezone.utc)
        await db.commit()
    return {"ok": True, "message": f"{task_id} todos 已更新"}
