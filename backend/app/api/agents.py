"""Agents API — Agent 配置和状态查询。"""

import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException

from ..services.openclaw_runtime import get_agent_config_entry

log = logging.getLogger("edict.api.agents")
router = APIRouter()

# Agent 元信息（对应 agents/ 目录下的 SOUL.md）
AGENT_META = {
    "zaochao": {"name": "早朝（朝会主持）", "role": "朝会召集与议程管理", "icon": "🏛️"},
    "shangshu": {"name": "尚书令", "role": "总协调与任务监督", "icon": "📜"},
    "zhongshu": {"name": "中书省", "role": "起草诏令与方案规划", "icon": "✍️"},
    "menxia": {"name": "门下省", "role": "审核与封驳", "icon": "🔍"},
    "libu": {"name": "吏部", "role": "人事与组织管理", "icon": "👤"},
    "hubu": {"name": "户部", "role": "财务与资源管理", "icon": "💰"},
    "gongbu": {"name": "工部", "role": "工程与技术实施", "icon": "🔧"},
    "xingbu": {"name": "刑部", "role": "规范与质量审查", "icon": "⚖️"},
    "bingbu": {"name": "兵部", "role": "安全与应急响应", "icon": "🛡️"},
}


@router.get("")
async def list_agents():
    """列出所有可用 Agent。"""
    agents = []
    for agent_id, meta in AGENT_META.items():
        agents.append({
            "id": agent_id,
            **meta,
        })
    return {"agents": agents}


@router.get("/{agent_id}")
async def get_agent(agent_id: str):
    """获取 Agent 详情。"""
    meta = AGENT_META.get(agent_id)
    if not meta:
        raise HTTPException(status_code=404, detail=f"Agent '{agent_id}' not found")

    # 尝试读取 SOUL.md
    from ..services.openclaw_runtime import resolve_agents_dir
    soul_path = resolve_agents_dir() / agent_id / "SOUL.md"
    soul_content = ""
    if soul_path.exists():
        soul_content = soul_path.read_text(encoding="utf-8")[:2000]

    return {
        "id": agent_id,
        **meta,
        "soul_preview": soul_content,
    }


@router.get("/{agent_id}/config")
async def get_agent_config(agent_id: str):
    """获取 Agent 运行时配置。"""
    return {"agent_id": agent_id, "config": get_agent_config_entry(agent_id)}
