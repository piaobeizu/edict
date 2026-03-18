"""官员统计服务。"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.task import Task
from .openclaw_runtime import OCLAW_HOME, build_agent_config_payload, normalize_model

MODEL_PRICING = {
    "anthropic/claude-sonnet-4-6": {"in": 3.0, "out": 15.0, "cr": 0.30, "cw": 3.75},
    "anthropic/claude-opus-4-5": {"in": 15.0, "out": 75.0, "cr": 1.50, "cw": 18.75},
    "anthropic/claude-haiku-3-5": {"in": 0.8, "out": 4.0, "cr": 0.08, "cw": 1.0},
    "openai/gpt-4o": {"in": 2.5, "out": 10.0, "cr": 1.25, "cw": 0},
    "openai/gpt-4o-mini": {"in": 0.15, "out": 0.6, "cr": 0.075, "cw": 0},
    "google/gemini-2.0-flash": {"in": 0.075, "out": 0.3, "cr": 0, "cw": 0},
    "google/gemini-2.5-pro": {"in": 1.25, "out": 10.0, "cr": 0, "cw": 0},
}

OFFICIALS = [
    {"id": "taizi", "label": "太子", "role": "太子", "emoji": "🤴", "rank": "储君"},
    {"id": "zhongshu", "label": "中书省", "role": "中书令", "emoji": "📜", "rank": "正一品"},
    {"id": "menxia", "label": "门下省", "role": "侍中", "emoji": "🔍", "rank": "正一品"},
    {"id": "shangshu", "label": "尚书省", "role": "尚书令", "emoji": "📮", "rank": "正一品"},
    {"id": "libu", "label": "礼部", "role": "礼部尚书", "emoji": "📝", "rank": "正二品"},
    {"id": "hubu", "label": "户部", "role": "户部尚书", "emoji": "💰", "rank": "正二品"},
    {"id": "bingbu", "label": "兵部", "role": "兵部尚书", "emoji": "⚔️", "rank": "正二品"},
    {"id": "xingbu", "label": "刑部", "role": "刑部尚书", "emoji": "⚖️", "rank": "正二品"},
    {"id": "gongbu", "label": "工部", "role": "工部尚书", "emoji": "🔧", "rank": "正二品"},
    {"id": "libu_hr", "label": "吏部", "role": "吏部尚书", "emoji": "👔", "rank": "正二品"},
    {"id": "zaochao", "label": "钦天监", "role": "朝报官", "emoji": "📰", "rank": "正三品"},
]


def _read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _scan_agent(agent_id: str) -> dict:
    sessions_json = OCLAW_HOME / "agents" / agent_id / "sessions" / "sessions.json"
    if not sessions_json.exists() and agent_id == "taizi":
        sessions_json = OCLAW_HOME / "agents" / "main" / "sessions" / "sessions.json"
    if not sessions_json.exists():
        return {"tokens_in": 0, "tokens_out": 0, "cache_read": 0, "cache_write": 0, "sessions": 0, "last_active": None, "messages": 0}
    data = _read_json(sessions_json, {})
    if not isinstance(data, dict):
        return {"tokens_in": 0, "tokens_out": 0, "cache_read": 0, "cache_write": 0, "sessions": 0, "last_active": None, "messages": 0}
    tokens_in = tokens_out = cache_read = cache_write = messages = 0
    last_active_dt = None
    latest_session_file = None
    latest_updated = 0
    for session in data.values():
        if not isinstance(session, dict):
            continue
        tokens_in += int(session.get("inputTokens", 0) or 0)
        tokens_out += int(session.get("outputTokens", 0) or 0)
        cache_read += int(session.get("cacheRead", 0) or 0)
        cache_write += int(session.get("cacheWrite", 0) or 0)
        updated = session.get("updatedAt", 0) or 0
        try:
            current_dt = dt.datetime.fromtimestamp(updated / 1000, tz=dt.timezone.utc) if isinstance(updated, (int, float)) else dt.datetime.fromisoformat(str(updated).replace("Z", "+00:00"))
            if last_active_dt is None or current_dt > last_active_dt:
                last_active_dt = current_dt
        except Exception:
            pass
        if isinstance(updated, (int, float)) and updated > latest_updated:
            latest_updated = int(updated)
            latest_session_file = session.get("sessionFile")
    if latest_session_file:
        session_file = sessions_json.parent / Path(str(latest_session_file)).name
        try:
            for line in session_file.read_text(encoding="utf-8", errors="ignore").splitlines():
                entry = json.loads(line)
                if entry.get("type") == "message" and ((entry.get("message") or {}).get("role") == "assistant"):
                    messages += 1
        except Exception:
            pass
    return {
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "cache_read": cache_read,
        "cache_write": cache_write,
        "sessions": len(data),
        "last_active": last_active_dt,
        "messages": messages,
    }


def _calc_cost(stats: dict, model: str) -> float:
    pricing = MODEL_PRICING.get(model, MODEL_PRICING["anthropic/claude-sonnet-4-6"])
    usd = (
        stats["tokens_in"] / 1e6 * pricing["in"]
        + stats["tokens_out"] / 1e6 * pricing["out"]
        + stats["cache_read"] / 1e6 * pricing["cr"]
        + stats["cache_write"] / 1e6 * pricing["cw"]
    )
    return round(usd, 4)


def _heartbeat(last_active_dt: dt.datetime | None) -> dict:
    if last_active_dt is None:
        return {"status": "idle", "label": "⚪ 待命", "ageSec": None}
    now = dt.datetime.now(dt.timezone.utc)
    age_sec = max(0, int((now - last_active_dt).total_seconds()))
    if age_sec < 180:
        return {"status": "active", "label": f"🟢 活跃 {age_sec // 60}分钟前", "ageSec": age_sec}
    if age_sec < 600:
        return {"status": "warn", "label": f"🟡 可能停滞 {age_sec // 60}分钟前", "ageSec": age_sec}
    return {"status": "idle", "label": f"⚪ 空闲 {age_sec // 60}分钟前", "ageSec": age_sec}


def _task_stats(org_label: str, tasks: list[Task]) -> dict:
    done = [task for task in tasks if task.state == "Done" and task.org == org_label]
    active = [task for task in tasks if task.state in ("Doing", "Review", "Assigned") and task.org == org_label]
    flow_count = 0
    participated = []
    seen = set()
    for task in tasks:
        for flow in list(task.flow_log or []):
            if flow.get("from") == org_label or flow.get("to") == org_label:
                flow_count += 1
                if task.id not in seen and str(task.id).startswith("JJC"):
                    participated.append({"id": task.id, "title": task.title or "", "state": task.state or ""})
                    seen.add(task.id)
    return {
        "tasks_done": len(done),
        "tasks_active": len(active),
        "flow_participations": flow_count,
        "participated_edicts": participated,
    }


async def build_officials_stats(db: AsyncSession) -> dict:
    rows = await db.execute(select(Task))
    tasks = list(rows.scalars().all())
    agent_payload = build_agent_config_payload()
    model_map = {agent["id"]: normalize_model(agent.get("model"), "anthropic/claude-sonnet-4-6") for agent in agent_payload.get("agents", [])}
    result = []
    for official in OFFICIALS:
        model = model_map.get(official["id"], "anthropic/claude-sonnet-4-6")
        stats = _scan_agent(official["id"])
        task_stats = _task_stats(official["label"], tasks)
        cost_usd = _calc_cost(stats, model)
        merit_score = task_stats["tasks_done"] * 10 + task_stats["flow_participations"] * 2 + min(stats["sessions"], 20)
        result.append({
            **official,
            "model": model,
            "model_short": model.split("/")[-1] if "/" in model else model,
            "tokens_in": stats["tokens_in"],
            "tokens_out": stats["tokens_out"],
            "cache_read": stats["cache_read"],
            "cache_write": stats["cache_write"],
            "tokens_total": stats["tokens_in"] + stats["tokens_out"],
            "cost_usd": cost_usd,
            "cost_cny": round(cost_usd * 7.25, 2),
            "sessions": stats["sessions"],
            "messages": stats["messages"],
            "last_active": stats["last_active"].strftime("%Y-%m-%d %H:%M") if stats["last_active"] else None,
            "heartbeat": _heartbeat(stats["last_active"]),
            "tasks_done": task_stats["tasks_done"],
            "tasks_active": task_stats["tasks_active"],
            "flow_participations": task_stats["flow_participations"],
            "participated_edicts": task_stats["participated_edicts"],
            "merit_score": merit_score,
        })
    result.sort(key=lambda item: item["merit_score"], reverse=True)
    for idx, item in enumerate(result, start=1):
        item["merit_rank"] = idx
    totals = {
        "tokens_total": sum(item["tokens_total"] for item in result),
        "cache_total": sum(item["cache_read"] + item["cache_write"] for item in result),
        "cost_usd": round(sum(item["cost_usd"] for item in result), 2),
        "cost_cny": round(sum(item["cost_cny"] for item in result), 2),
        "tasks_done": sum(item["tasks_done"] for item in result),
    }
    top = max(result, key=lambda item: item["merit_score"], default={})
    return {
        "generatedAt": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "officials": result,
        "totals": totals,
        "top_official": top.get("label", ""),
    }
