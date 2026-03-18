"""输出归一化服务。

将 agent stdout/stderr 归一化为统一结构：
- summary: 一句话摘要
- todo_detail: 步骤级明细（用于 todo.detail 回填）
- output: 可展示正文（截断）
- artifacts: 产出文件路径列表
- retry: 重试统计
"""

from __future__ import annotations

import re
from typing import Any


_PATH_RE = re.compile(r"(?:/[^\s`'\"]+)+")

_RETRY_EXHAUST_LIMITS = {
    "rate_limit": 4,
    "timeout": 3,
    "network": 3,
    "business_error": 1,
    "ok": 1,
}


def _looks_like_file_path(path: str) -> bool:
    """过滤误识别（如中文句子里的斜杠分隔词）。"""
    if not path or not path.startswith("/"):
        return False
    if path.startswith("/api/") or path.startswith("//"):
        return False
    # 避免把“地址/仓库位置”这类自然语言误判为文件路径
    if re.search(r"[\u4e00-\u9fff]", path):
        return False
    # 至少有两段路径，且包含常见路径字符
    if path.count("/") < 1:
        return False
    if not re.search(r"[A-Za-z0-9_.~-]", path):
        return False
    # 限制为更像“文件系统路径”的模式，避免把 /openai/gpt-5.4 这类标识当文件
    likely_roots = ("/root/", "/app/", "/tmp/", "/data/", "/var/", "/home/")
    likely_ext = (
        ".md", ".txt", ".json", ".log", ".csv", ".yaml", ".yml", ".pdf",
        ".py", ".ts", ".tsx", ".js", ".sh",
    )
    if not (path.startswith(likely_roots) or path.endswith(likely_ext)):
        return False
    return True


def _extract_artifacts(text: str, limit: int = 10) -> list[dict[str, str]]:
    """从文本中提取看起来像文件路径的片段。"""
    if not text:
        return []
    found = []
    seen = set()
    for m in _PATH_RE.finditer(text):
        path = m.group(0)
        if path in seen:
            continue
        if not _looks_like_file_path(path):
            continue
        seen.add(path)
        kind = "file"
        if path.endswith(".md"):
            kind = "markdown"
        elif path.endswith(".json"):
            kind = "json"
        elif path.endswith(".log"):
            kind = "log"
        found.append({"path": path, "kind": kind})
        if len(found) >= limit:
            break
    return found


def _pick_summary(stdout: str, stderr: str) -> str:
    """提取第一条可读摘要。"""
    for source in (stdout, stderr):
        for raw in source.splitlines():
            line = raw.strip()
            if not line:
                continue
            if len(line) > 200:
                line = line[:200] + "..."
            return line
    return "无输出"


def normalize_agent_output(
    *,
    task_id: str,
    agent: str,
    returncode: int,
    stdout: str,
    stderr: str,
    attempts: int = 1,
    error_type: str = "ok",
) -> dict[str, Any]:
    """生成统一输出合同。"""
    summary = _pick_summary(stdout, stderr)
    artifacts = _extract_artifacts("\n".join([stdout or "", stderr or ""]))
    ok = returncode == 0
    max_attempts = _RETRY_EXHAUST_LIMITS.get(error_type, 1)

    body = (stdout or "").strip()
    if not body and stderr:
        body = stderr.strip()
    if len(body) > 8000:
        body = body[:8000] + "\n...(truncated)"

    return {
        "task_id": task_id,
        "agent": agent,
        "ok": ok,
        "summary": summary,
        "todo_detail": summary,
        "output": body,
        "artifacts": artifacts,
        "retry": {
            "attempts": attempts,
            "error_type": error_type,
            "exhausted": (not ok and attempts >= max_attempts),
        },
        "return_code": returncode,
    }
