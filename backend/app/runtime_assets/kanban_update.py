#!/usr/bin/env python3
"""Edict v2 kanban CLI.

保持 `scripts/kanban_update.py` 接口不变，内部调用 Edict REST API。
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys
from urllib.request import Request, urlopen

EDICT_API_URL = os.environ.get("EDICT_API_URL", "http://localhost:8000")

_MIN_TITLE_LEN = 6
_JUNK_TITLES = {
    "?", "？", "好", "好的", "是", "否", "不", "不是", "对", "了解", "收到",
    "嗯", "哦", "知道了", "开启了么", "可以", "不行", "行", "ok", "yes", "no",
    "你去开启", "测试", "试试", "看看",
}

_STATE_TO_EDICT = {
    "Taizi": "Taizi", "Zhongshu": "Zhongshu", "Menxia": "Menxia", "YuLan": "YuLan",
    "Assigned": "Assigned", "Next": "Next", "Doing": "Doing", "Review": "Review",
    "Done": "Done", "Blocked": "Blocked", "Cancelled": "Cancelled", "Pending": "Pending",
}


def _sanitize_text(raw: str, max_len: int = 80) -> str:
    text = (raw or "").strip()
    text = re.split(r"\n*Conversation\b", text, maxsplit=1)[0].strip()
    text = re.split(r"\n*```", text, maxsplit=1)[0].strip()
    text = re.sub(r"[/\\.~][A-Za-z0-9_\-./]+(?:\.(?:py|js|ts|json|md|sh|yaml|yml|txt|csv|html|css|log))?", "", text)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"^(传旨|下旨)([（(][^)）]*[)）])?[：:\uff1a]\s*", "", text)
    text = re.sub(r"(message_id|session_id|chat_id|open_id|user_id|tenant_key)\s*[:=]\s*\S+", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > max_len:
        text = text[:max_len] + "…"
    return text


def _sanitize_title(raw: str) -> str:
    return _sanitize_text(raw, 80)


def _sanitize_remark(raw: str) -> str:
    return _sanitize_text(raw, 120)


def _is_valid_task_title(title: str):
    text = (title or "").strip()
    if len(text) < _MIN_TITLE_LEN:
        return False, f"标题过短（{len(text)}<{_MIN_TITLE_LEN}字），疑似非旨意"
    if text.lower() in _JUNK_TITLES:
        return False, f'标题 "{text}" 不是有效旨意'
    if re.fullmatch(r"[\s?？!！.。,，…·\-—~]+", text):
        return False, "标题只有标点符号"
    if re.match(r"^[/\\~.]", text) or re.search(r"/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+", text):
        return False, "标题看起来像文件路径，请用中文概括任务"
    if re.fullmatch(r"[\s\W]*", text):
        return False, "标题清洗后为空"
    return True, ""


def _infer_agent_id() -> str:
    for key in ("OPENCLAW_AGENT_ID", "OPENCLAW_AGENT", "AGENT_ID"):
        value = (os.environ.get(key) or "").strip()
        if value:
            return value
    match = re.search(r"workspace-([a-zA-Z0-9_\-]+)", str(pathlib.Path.cwd()))
    return match.group(1) if match else "system"


def _request(method: str, path: str, data: dict | None = None):
    body = json.dumps(data, ensure_ascii=False).encode("utf-8") if data is not None else None
    request = Request(
        f"{EDICT_API_URL}{path}",
        data=body,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urlopen(request, timeout=10) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


def cmd_create(task_id, title, _state, org, official, remark=None):
    title = _sanitize_title(title)
    valid, reason = _is_valid_task_title(title)
    if not valid:
        print(f"[看板] 拒绝创建：{reason}", flush=True)
        return
    _request("POST", "/api/tasks", {
        "title": title,
        "description": remark or f"下旨：{title}",
        "priority": "中",
        "assignee_org": org,
        "creator": official,
        "tags": [task_id],
        "meta": {"legacy_id": task_id},
    })


def cmd_state(task_id, new_state, now_text=None):
    _request("POST", f"/api/tasks/by-legacy/{task_id}/transition", {
        "new_state": _STATE_TO_EDICT.get(new_state, new_state),
        "agent": _infer_agent_id(),
        "reason": now_text or f"状态更新为 {new_state}",
    })


def cmd_flow(task_id, from_dept, to_dept, remark):
    _request("POST", f"/api/tasks/by-legacy/{task_id}/progress", {
        "agent": _infer_agent_id(),
        "content": f"流转: {from_dept} → {to_dept} | {_sanitize_remark(remark)}",
    })


def cmd_done(task_id, _output_path="", summary=""):
    _request("POST", f"/api/tasks/by-legacy/{task_id}/transition", {
        "new_state": "Done",
        "agent": _infer_agent_id(),
        "reason": summary or "任务已完成",
    })


def cmd_block(task_id, reason):
    _request("POST", f"/api/tasks/by-legacy/{task_id}/transition", {
        "new_state": "Blocked",
        "agent": _infer_agent_id(),
        "reason": reason,
    })


def cmd_progress(task_id, now_text, todos_pipe="", tokens=0, cost=0.0, elapsed=0):
    del tokens, cost, elapsed
    clean = _sanitize_remark(now_text)
    _request("POST", f"/api/tasks/by-legacy/{task_id}/progress", {
        "agent": _infer_agent_id(),
        "content": clean,
    })
    if todos_pipe:
        todos = []
        for index, item in enumerate(todos_pipe.split("|"), start=1):
            item = item.strip()
            if not item:
                continue
            if item.endswith("✅"):
                status, title = "completed", item[:-1].strip()
            elif item.endswith("🔄"):
                status, title = "in-progress", item[:-1].strip()
            else:
                status, title = "not-started", item
            todos.append({"id": str(index), "title": title, "status": status})
        if todos:
            _request("PUT", f"/api/tasks/by-legacy/{task_id}/todos", {"todos": todos})


def cmd_todo(task_id, todo_id, title, status="not-started", detail=""):
    status = status if status in {"not-started", "in-progress", "completed"} else "not-started"
    remark = f"Todo #{todo_id}: {title} → {status}"
    if detail:
        remark += f"\n{detail}"
    _request("POST", f"/api/tasks/by-legacy/{task_id}/progress", {
        "agent": _infer_agent_id(),
        "content": remark,
    })


_CMD_MIN_ARGS = {"create": 6, "state": 3, "flow": 5, "done": 2, "block": 3, "todo": 4, "progress": 3}


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        raise SystemExit(0)
    command = args[0]
    if command in _CMD_MIN_ARGS and len(args) < _CMD_MIN_ARGS[command]:
        raise SystemExit(1)
    if command == "create":
        cmd_create(args[1], args[2], args[3], args[4], args[5], args[6] if len(args) > 6 else None)
    elif command == "state":
        cmd_state(args[1], args[2], args[3] if len(args) > 3 else None)
    elif command == "flow":
        cmd_flow(args[1], args[2], args[3], args[4])
    elif command == "done":
        cmd_done(args[1], args[2] if len(args) > 2 else "", args[3] if len(args) > 3 else "")
    elif command == "block":
        cmd_block(args[1], args[2])
    elif command == "todo":
        todo_pos, todo_detail, idx = [], "", 1
        while idx < len(args):
            if args[idx] == "--detail" and idx + 1 < len(args):
                todo_detail = args[idx + 1]
                idx += 2
            else:
                todo_pos.append(args[idx])
                idx += 1
        cmd_todo(
            todo_pos[0] if len(todo_pos) > 0 else "",
            todo_pos[1] if len(todo_pos) > 1 else "",
            todo_pos[2] if len(todo_pos) > 2 else "",
            todo_pos[3] if len(todo_pos) > 3 else "not-started",
            detail=todo_detail,
        )
    elif command == "progress":
        positional, kwargs, idx = [], {}, 1
        while idx < len(args):
            if args[idx] in {"--tokens", "--cost", "--elapsed"} and idx + 1 < len(args):
                kwargs[args[idx][2:]] = args[idx + 1]
                idx += 2
            else:
                positional.append(args[idx])
                idx += 1
        cmd_progress(
            positional[0] if len(positional) > 0 else "",
            positional[1] if len(positional) > 1 else "",
            positional[2] if len(positional) > 2 else "",
            tokens=kwargs.get("tokens", 0),
            cost=kwargs.get("cost", 0.0),
            elapsed=kwargs.get("elapsed", 0),
        )
    else:
        raise SystemExit(1)
