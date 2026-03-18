"""OpenClaw 运行时配置服务。"""

from __future__ import annotations

import datetime as dt
import hashlib
import ipaddress
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import Request, urlopen

OCLAW_HOME = Path.home() / ".openclaw"
SAFE_NAME_RE = re.compile(r"^[a-zA-Z0-9_\-\u4e00-\u9fff]+$")

ID_LABEL = {
    "taizi": {"label": "太子", "role": "太子", "duty": "飞书消息分拣与回奏", "emoji": "🤴"},
    "main": {"label": "太子", "role": "太子", "duty": "飞书消息分拣与回奏", "emoji": "🤴"},
    "zhongshu": {"label": "中书省", "role": "中书令", "duty": "起草任务令与优先级", "emoji": "📜"},
    "menxia": {"label": "门下省", "role": "侍中", "duty": "审议与退回机制", "emoji": "🔍"},
    "shangshu": {"label": "尚书省", "role": "尚书令", "duty": "派单与升级裁决", "emoji": "📮"},
    "libu": {"label": "礼部", "role": "礼部尚书", "duty": "文档/汇报/规范", "emoji": "📝"},
    "hubu": {"label": "户部", "role": "户部尚书", "duty": "资源/预算/成本", "emoji": "💰"},
    "bingbu": {"label": "兵部", "role": "兵部尚书", "duty": "应急与巡检", "emoji": "⚔️"},
    "xingbu": {"label": "刑部", "role": "刑部尚书", "duty": "合规/审计/红线", "emoji": "⚖️"},
    "gongbu": {"label": "工部", "role": "工部尚书", "duty": "工程交付与自动化", "emoji": "🔧"},
    "libu_hr": {"label": "吏部", "role": "吏部尚书", "duty": "人事/培训/Agent管理", "emoji": "👔"},
    "zaochao": {"label": "钦天监", "role": "朝报官", "duty": "每日新闻采集与简报", "emoji": "📰"},
}

KNOWN_MODELS = [
    {"id": "anthropic/claude-sonnet-4-6", "label": "Claude Sonnet 4.6", "provider": "Anthropic"},
    {"id": "anthropic/claude-opus-4-5", "label": "Claude Opus 4.5", "provider": "Anthropic"},
    {"id": "anthropic/claude-haiku-3-5", "label": "Claude Haiku 3.5", "provider": "Anthropic"},
    {"id": "openai/gpt-4o", "label": "GPT-4o", "provider": "OpenAI"},
    {"id": "openai/gpt-4o-mini", "label": "GPT-4o Mini", "provider": "OpenAI"},
    {"id": "openai-codex/gpt-5.3-codex", "label": "GPT-5.3 Codex", "provider": "OpenAI Codex"},
    {"id": "google/gemini-2.0-flash", "label": "Gemini 2.0 Flash", "provider": "Google"},
    {"id": "google/gemini-2.5-pro", "label": "Gemini 2.5 Pro", "provider": "Google"},
    {"id": "copilot/claude-sonnet-4", "label": "Claude Sonnet 4", "provider": "Copilot"},
    {"id": "copilot/claude-opus-4.5", "label": "Claude Opus 4.5", "provider": "Copilot"},
    {"id": "github-copilot/claude-opus-4.6", "label": "Claude Opus 4.6", "provider": "GitHub Copilot"},
    {"id": "copilot/gpt-4o", "label": "GPT-4o", "provider": "Copilot"},
    {"id": "copilot/gemini-2.5-pro", "label": "Gemini 2.5 Pro", "provider": "Copilot"},
    {"id": "copilot/o3-mini", "label": "o3-mini", "provider": "Copilot"},
]

EXTRA_AGENTS = {
    "taizi": {"allowAgents": ["zhongshu"]},
    "main": {"allowAgents": ["zhongshu", "menxia", "shangshu", "hubu", "libu", "bingbu", "xingbu", "gongbu", "libu_hr"]},
    "zaochao": {"allowAgents": []},
    "libu_hr": {"allowAgents": ["shangshu"]},
}

SOUL_DEPLOY_MAP = {
    "taizi": "taizi",
    "zhongshu": "zhongshu",
    "menxia": "menxia",
    "shangshu": "shangshu",
    "libu": "libu",
    "hubu": "hubu",
    "bingbu": "bingbu",
    "xingbu": "xingbu",
    "gongbu": "gongbu",
    "libu_hr": "libu_hr",
    "zaochao": "zaochao",
}


def _project_root() -> Path:
    candidates: list[Path] = []
    env_root = (os.getenv("OPENCLAW_PROJECT_DIR") or "").strip()
    if env_root:
        candidates.append(Path(env_root))
    candidates.append(Path("/app"))
    resolved = Path(__file__).resolve()
    candidates.extend([resolved.parent, *resolved.parents])
    candidates.append(Path.cwd())

    seen: set[Path] = set()
    for candidate in candidates:
        try:
            candidate = candidate.resolve()
        except Exception:
            continue
        if candidate in seen:
            continue
        seen.add(candidate)
        if (candidate / "backend").exists() and (candidate / "agents").exists():
            return candidate
        if (candidate / "agents").exists() or (candidate / "data").exists():
            return candidate
    return Path("/app")


def resolve_data_dir() -> Path:
    for path in [Path("/app/data"), _project_root() / "data", Path.cwd() / "data"]:
        if path.exists() and path.is_dir():
            return path
    path = Path("/app/data")
    path.mkdir(parents=True, exist_ok=True)
    return path


def resolve_agents_dir() -> Path:
    for path in [Path("/app/agents"), _project_root() / "agents", Path.cwd() / "agents"]:
        if path.exists() and path.is_dir():
            return path
    return Path("/app/agents")


def resolve_kanban_asset_path() -> Path:
    candidates = [
        Path(__file__).resolve().parents[1] / "runtime_assets" / "kanban_update.py",
    ]
    for path in candidates:
        if path.exists() and path.is_file():
            return path
    return candidates[0]


def _read_json(path: Path, default: Any):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def _timestamp() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def normalize_model(model_value: Any, fallback: str = "unknown") -> str:
    if isinstance(model_value, str) and model_value:
        return model_value
    if isinstance(model_value, dict):
        return model_value.get("primary") or model_value.get("id") or fallback
    return fallback


def _validate_safe_name(value: str) -> bool:
    return bool(SAFE_NAME_RE.match(value))


def _is_path_under(child: Path, parent: Path) -> bool:
    """安全检查 child 是否在 parent 目录下（使用 resolve + relative_to）。"""
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _validate_url(url: str, allowed_schemes: tuple[str, ...] = ("https",), allowed_domains=None) -> bool:
    import socket
    try:
        parsed = urlparse(url)
        if parsed.scheme not in allowed_schemes or not parsed.hostname:
            return False
        if allowed_domains and parsed.hostname not in allowed_domains:
            return False
        # 检查直接 IP
        try:
            ip = ipaddress.ip_address(parsed.hostname)
            if ip.is_private or ip.is_loopback or ip.is_reserved:
                return False
        except ValueError:
            pass
        # DNS 解析后检查（防止 DNS rebinding 到内网 IP）
        try:
            for family, _, _, _, sockaddr in socket.getaddrinfo(parsed.hostname, None):
                ip = ipaddress.ip_address(sockaddr[0])
                if ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_link_local:
                    return False
        except (socket.gaierror, OSError):
            return False
        return True
    except Exception:
        return False


def _openclaw_cfg_path() -> Path:
    return OCLAW_HOME / "openclaw.json"


def load_openclaw_config() -> dict[str, Any]:
    return _read_json(_openclaw_cfg_path(), {})


def _workspace_path(agent_id: str) -> Path:
    return OCLAW_HOME / f"workspace-{agent_id}"


def _skill_path(agent_id: str, skill_name: str) -> Path:
    return _workspace_path(agent_id) / "skills" / skill_name / "SKILL.md"


def _list_skills(workspace: Path) -> list[dict[str, Any]]:
    skills_dir = workspace / "skills"
    skills = []
    if not skills_dir.exists():
        return skills
    for directory in sorted(skills_dir.iterdir()):
        if not directory.is_dir():
            continue
        md = directory / "SKILL.md"
        description = ""
        if md.exists():
            try:
                for line in md.read_text(encoding="utf-8", errors="ignore").splitlines():
                    stripped = line.strip()
                    if stripped and not stripped.startswith("#") and not stripped.startswith("---"):
                        description = stripped[:100]
                        break
            except Exception:
                description = "(读取失败)"
        skills.append({
            "name": directory.name,
            "path": str(md),
            "exists": md.exists(),
            "description": description,
        })
    return skills


_MEMORY_TEMPLATE = """\
# {agent_id} 记忆

> 本文件由 OpenClaw 运行时自动维护，记录 agent 跨会话的持久记忆。

## 偏好与约定

- 输出语言：中文
- 回复风格：结构化、简洁、可执行

## 历史经验

（暂无，将在任务执行中自动积累）
"""


def sync_workspace_support_files() -> dict[str, int]:
    agents_dir = resolve_agents_dir()
    kanban_asset = resolve_kanban_asset_path()
    soul_count = 0
    script_count = 0
    memory_count = 0
    skill_count = 0
    for project_name, runtime_id in SOUL_DEPLOY_MAP.items():
        workspace = _workspace_path(runtime_id)
        workspace.mkdir(parents=True, exist_ok=True)
        (OCLAW_HOME / "agents" / runtime_id / "sessions").mkdir(parents=True, exist_ok=True)
        source_soul = agents_dir / project_name / "SOUL.md"
        target_soul = workspace / "soul.md"
        if source_soul.exists():
            source_text = source_soul.read_text(encoding="utf-8", errors="ignore")
            current_text = target_soul.read_text(encoding="utf-8", errors="ignore") if target_soul.exists() else ""
            if source_text != current_text:
                target_soul.write_text(source_text, encoding="utf-8")
                soul_count += 1
            if runtime_id == "taizi":
                main_soul = OCLAW_HOME / "agents" / "main" / "SOUL.md"
                main_soul.parent.mkdir(parents=True, exist_ok=True)
                current_main = main_soul.read_text(encoding="utf-8", errors="ignore") if main_soul.exists() else ""
                if source_text != current_main:
                    main_soul.write_text(source_text, encoding="utf-8")
        # MEMORY.md — 仅在不存在时创建初始模板，不覆盖已有记忆
        memory_file = workspace / "MEMORY.md"
        if not memory_file.exists():
            memory_file.write_text(
                _MEMORY_TEMPLATE.format(agent_id=runtime_id), encoding="utf-8"
            )
            memory_count += 1
        # memory/ 目录 — OpenClaw 按日写入 memory/YYYY-MM-DD.md
        memory_dir = workspace / "memory"
        memory_dir.mkdir(parents=True, exist_ok=True)
        # skills/ 目录 — 从源码同步到 workspace（增量，不删除远程添加的）
        source_skills = agents_dir / project_name / "skills"
        if source_skills.is_dir():
            target_skills = workspace / "skills"
            target_skills.mkdir(parents=True, exist_ok=True)
            for skill_dir in source_skills.iterdir():
                if not skill_dir.is_dir():
                    continue
                target_skill_dir = target_skills / skill_dir.name
                target_skill_dir.mkdir(parents=True, exist_ok=True)
                for skill_file in skill_dir.iterdir():
                    if skill_file.is_file():
                        target_file = target_skill_dir / skill_file.name
                        source_bytes = skill_file.read_bytes()
                        target_bytes = target_file.read_bytes() if target_file.exists() else b""
                        if source_bytes != target_bytes:
                            target_file.write_bytes(source_bytes)
                            skill_count += 1
        if kanban_asset.exists():
            scripts_dir = workspace / "scripts"
            scripts_dir.mkdir(parents=True, exist_ok=True)
            target_script = scripts_dir / "kanban_update.py"
            source_bytes = kanban_asset.read_bytes()
            target_bytes = target_script.read_bytes() if target_script.exists() else b""
            if source_bytes != target_bytes:
                target_script.write_bytes(source_bytes)
                script_count += 1
    return {"soul": soul_count, "scripts": script_count, "memory": memory_count, "skills": skill_count}


def build_agent_config_payload() -> dict[str, Any]:
    cfg = load_openclaw_config()
    agents_cfg = cfg.get("agents", {})
    default_model = normalize_model(agents_cfg.get("defaults", {}).get("model", {}), "unknown")
    agents_list = agents_cfg.get("list", []) if isinstance(agents_cfg.get("list", []), list) else []
    result = []
    seen_ids: set[str] = set()
    for agent in agents_list:
        agent_id = str(agent.get("id", "")).strip()
        if agent_id not in ID_LABEL:
            continue
        meta = ID_LABEL[agent_id]
        workspace = Path(agent.get("workspace") or _workspace_path(agent_id))
        result.append({
            "id": agent_id,
            "label": meta["label"],
            "role": meta["role"],
            "duty": meta["duty"],
            "emoji": meta["emoji"],
            "model": normalize_model(agent.get("model"), default_model),
            "defaultModel": default_model,
            "workspace": str(workspace),
            "skills": _list_skills(workspace),
            "allowAgents": ((agent.get("subagents") or {}).get("allowAgents") or []),
        })
        seen_ids.add(agent_id)
    for agent_id, extra in EXTRA_AGENTS.items():
        if agent_id in seen_ids or agent_id not in ID_LABEL:
            continue
        meta = ID_LABEL[agent_id]
        workspace = _workspace_path(agent_id)
        result.append({
            "id": agent_id,
            "label": meta["label"],
            "role": meta["role"],
            "duty": meta["duty"],
            "emoji": meta["emoji"],
            "model": default_model,
            "defaultModel": default_model,
            "workspace": str(workspace),
            "skills": _list_skills(workspace),
            "allowAgents": extra["allowAgents"],
        })
    return {
        "generatedAt": _timestamp(),
        "defaultModel": default_model,
        "knownModels": KNOWN_MODELS,
        "agents": result,
    }


def get_agent_config_entry(agent_id: str) -> dict[str, Any]:
    payload = build_agent_config_payload()
    return next((agent for agent in payload.get("agents", []) if agent.get("id") == agent_id), {})


def read_skill_content(agent_id: str, skill_name: str) -> dict[str, Any]:
    if not _validate_safe_name(agent_id) or not _validate_safe_name(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    skill_path = _skill_path(agent_id, skill_name).resolve()
    allowed_roots = (OCLAW_HOME.resolve(), _project_root().resolve())
    if not any(_is_path_under(skill_path, root) for root in allowed_roots):
        return {"ok": False, "error": "路径不在允许的目录范围内"}
    if not skill_path.exists():
        return {
            "ok": True,
            "name": skill_name,
            "agent": agent_id,
            "content": "(SKILL.md 文件不存在)",
            "path": str(skill_path),
        }
    return {
        "ok": True,
        "name": skill_name,
        "agent": agent_id,
        "content": skill_path.read_text(encoding="utf-8", errors="ignore"),
        "path": str(skill_path),
    }


def add_skill(agent_id: str, skill_name: str, description: str, trigger: str = "") -> dict[str, Any]:
    if not _validate_safe_name(agent_id) or not _validate_safe_name(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    workspace = _workspace_path(agent_id) / "skills" / skill_name
    workspace.mkdir(parents=True, exist_ok=True)
    trigger_section = f"\n## 触发条件\n{trigger}\n" if trigger else ""
    template = (
        f"---\nname: {skill_name}\ndescription: {description or skill_name}\n---\n\n"
        f"# {skill_name}\n\n{description or skill_name}\n{trigger_section}\n"
        f"## 输入\n\n<!-- 说明此技能接收什么输入 -->\n\n"
        f"## 处理流程\n\n1. 步骤一\n2. 步骤二\n\n"
        f"## 输出规范\n\n<!-- 说明产出物格式与交付要求 -->\n\n"
        f"## 注意事项\n\n- (在此补充约束、限制或特殊规则)\n"
    )
    skill_file = workspace / "SKILL.md"
    skill_file.write_text(template, encoding="utf-8")
    return {"ok": True, "message": f"技能 {skill_name} 已添加", "path": str(skill_file)}


def _download_remote_text(source_url: str, *, allow_local: bool = False) -> str:
    """下载远程文本内容。默认仅允许 HTTPS，本地文件需显式启用。"""
    if source_url.startswith("https://"):
        if not _validate_url(source_url, allowed_schemes=("https",)):
            raise ValueError("URL 无效或不安全（仅支持 HTTPS）")
        req = Request(source_url, headers={"User-Agent": "Edict-RemoteSkill/1.0"})
        with urlopen(req, timeout=10) as resp:
            return resp.read(10 * 1024 * 1024).decode("utf-8")
    if not allow_local:
        raise ValueError("API 模式下仅支持 HTTPS 远程 URL，不允许本地文件访问")
    if source_url.startswith("file://"):
        local_path = Path(source_url[7:]).resolve()
    else:
        local_path = Path(source_url).resolve()
    allowed_roots = (OCLAW_HOME.resolve(), _project_root().resolve())
    if not any(_is_path_under(local_path, root) for root in allowed_roots):
        raise ValueError("路径不在允许的目录范围内")
    if not local_path.exists():
        raise ValueError(f"本地文件不存在: {local_path}")
    return local_path.read_text(encoding="utf-8")


def add_remote_skill(agent_id: str, skill_name: str, source_url: str, description: str = "") -> dict[str, Any]:
    if not _validate_safe_name(agent_id) or not _validate_safe_name(skill_name):
        return {"ok": False, "error": "参数含非法字符"}
    if not source_url.strip():
        return {"ok": False, "error": "sourceUrl required"}
    try:
        content = _download_remote_text(source_url.strip())
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    if not content.startswith("---"):
        return {"ok": False, "error": "文件格式无效（缺少 YAML frontmatter）"}
    workspace = _workspace_path(agent_id) / "skills" / skill_name
    workspace.mkdir(parents=True, exist_ok=True)
    skill_file = workspace / "SKILL.md"
    skill_file.write_text(content, encoding="utf-8")
    source_info = {
        "skillName": skill_name,
        "sourceUrl": source_url,
        "description": description,
        "addedAt": _timestamp(),
        "lastUpdated": _timestamp(),
        "checksum": hashlib.sha256(content.encode()).hexdigest()[:16],
        "status": "valid",
    }
    _write_json(workspace / ".source.json", source_info)
    return {
        "ok": True,
        "message": f"技能 {skill_name} 已从远程源添加",
        "skillName": skill_name,
        "agentId": agent_id,
        "source": source_url,
        "localPath": str(skill_file),
        "size": len(content),
        "addedAt": source_info["addedAt"],
    }


def list_remote_skills() -> dict[str, Any]:
    remote_skills = []
    for workspace_dir in OCLAW_HOME.glob("workspace-*"):
        agent_id = workspace_dir.name.replace("workspace-", "")
        skills_dir = workspace_dir / "skills"
        if not skills_dir.exists():
            continue
        for skill_dir in skills_dir.iterdir():
            if not skill_dir.is_dir():
                continue
            source_json = skill_dir / ".source.json"
            if not source_json.exists():
                continue
            info = _read_json(source_json, {})
            remote_skills.append({
                "skillName": skill_dir.name,
                "agentId": agent_id,
                "sourceUrl": info.get("sourceUrl", ""),
                "description": info.get("description", ""),
                "localPath": str(skill_dir / "SKILL.md"),
                "addedAt": info.get("addedAt", ""),
                "lastUpdated": info.get("lastUpdated", ""),
                "status": "valid" if (skill_dir / "SKILL.md").exists() else "not-found",
            })
    return {"ok": True, "remoteSkills": remote_skills, "count": len(remote_skills), "listedAt": _timestamp()}


def update_remote_skill(agent_id: str, skill_name: str) -> dict[str, Any]:
    source_json = _workspace_path(agent_id) / "skills" / skill_name / ".source.json"
    if not source_json.exists():
        return {"ok": False, "error": f"技能 {skill_name} 不是远程 skill"}
    info = _read_json(source_json, {})
    source_url = str(info.get("sourceUrl", "")).strip()
    if not source_url:
        return {"ok": False, "error": "源 URL 不存在"}
    result = add_remote_skill(agent_id, skill_name, source_url, str(info.get("description", "")))
    if result.get("ok"):
        result["message"] = "技能已更新"
    return result


def remove_remote_skill(agent_id: str, skill_name: str) -> dict[str, Any]:
    workspace = _workspace_path(agent_id) / "skills" / skill_name
    if not workspace.exists():
        return {"ok": False, "error": f"技能不存在: {skill_name}"}
    if not (workspace / ".source.json").exists():
        return {"ok": False, "error": f"技能 {skill_name} 不是远程 skill"}
    shutil.rmtree(workspace)
    return {"ok": True, "message": f"技能 {skill_name} 已从 {agent_id} 移除"}


def get_model_change_log() -> list[dict[str, Any]]:
    return _read_json(resolve_data_dir() / "model_change_log.json", [])


def get_last_model_change_result() -> dict[str, Any]:
    return _read_json(resolve_data_dir() / "last_model_change_result.json", {})


def set_agent_model(agent_id: str, model: str) -> dict[str, Any]:
    agent_id = agent_id.strip()
    model = model.strip()
    if not agent_id or not model:
        return {"ok": False, "error": "agentId and model required"}
    cfg_path = _openclaw_cfg_path()
    if not cfg_path.exists():
        return {"ok": False, "error": f"openclaw 配置不存在: {cfg_path}"}
    cfg = load_openclaw_config()
    agents_cfg = cfg.setdefault("agents", {})
    agents_list = agents_cfg.setdefault("list", [])
    default_model = normalize_model(agents_cfg.get("defaults", {}).get("model", {}), "unknown")
    current_agent = next((agent for agent in agents_list if agent.get("id") == agent_id), None)
    if current_agent is None:
        current_agent = {
            "id": agent_id,
            "workspace": str(_workspace_path(agent_id)),
            "subagents": {"allowAgents": EXTRA_AGENTS.get(agent_id, {}).get("allowAgents", [])},
        }
        agents_list.append(current_agent)
    old_model = normalize_model(current_agent.get("model"), default_model)
    if model == default_model:
        current_agent.pop("model", None)
    else:
        current_agent["model"] = model
    backup = cfg_path.parent / f"openclaw.json.bak.model-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(cfg_path, backup)
    _write_json(cfg_path, cfg)
    applied: list[dict[str, Any]] = [{
        "at": dt.datetime.now().isoformat(),
        "agentId": agent_id,
        "oldModel": old_model,
        "newModel": model,
    }]
    rollback = False
    restart_ok = False
    try:
        result = subprocess.run(["openclaw", "gateway", "restart"], capture_output=True, text=True, timeout=30)
        restart_ok = result.returncode == 0
        if not restart_ok:
            raise RuntimeError(result.stderr or result.stdout or f"gateway restart rc={result.returncode}")
    except Exception as exc:
        shutil.copy2(backup, cfg_path)
        rollback = True
        applied[0] = {**applied[0], "rolledBack": True}
        _write_json(resolve_data_dir() / "last_model_change_result.json", {
            "at": _timestamp(),
            "applied": applied,
            "errors": [{"agentId": agent_id, "error": str(exc)}],
            "gatewayRestarted": restart_ok,
            "rolledBack": rollback,
        })
        return {"ok": False, "error": f"模型切换失败，已回滚: {exc}"}
    log_path = resolve_data_dir() / "model_change_log.json"
    logs = _read_json(log_path, [])
    if not isinstance(logs, list):
        logs = []
    logs.extend(applied)
    if len(logs) > 200:
        logs = logs[-200:]
    _write_json(log_path, logs)
    _write_json(resolve_data_dir() / "last_model_change_result.json", {
        "at": _timestamp(),
        "applied": applied,
        "errors": [],
        "gatewayRestarted": restart_ok,
        "rolledBack": rollback,
    })
    return {"ok": True, "message": f"Applied: {agent_id} → {model}"}
