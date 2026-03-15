"""推送渠道 API — 查询 / 保存配置 / 测试推送。

复用 dashboard/notify/ 模块（Docker 构建时复制到 /app/notify/）。
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from fastapi import APIRouter

router = APIRouter()

# ── 确保 notify 包可导入 ──
# Docker 容器中: /app/notify/  本地开发: dashboard/notify/
for _candidate in [
    Path("/app"),
    Path(__file__).resolve().parent.parent.parent.parent.parent / "dashboard",
]:
    if (_candidate / "notify").is_dir() and str(_candidate) not in sys.path:
        sys.path.insert(0, str(_candidate))
        break


def _data_dir() -> Path:
    """定位 data 目录。"""
    candidates = [
        Path("/app/data"),
        Path.cwd() / "data",
    ]
    for p in candidates:
        if p.exists() and p.is_dir():
            return p
    d = Path("/app/data")
    d.mkdir(parents=True, exist_ok=True)
    return d


def _get_svc():
    from notify.service import NotifyService  # type: ignore[import-untyped]

    svc = NotifyService(_data_dir() / "notify_config.json")
    svc.migrate_legacy(_data_dir() / "morning_brief_config.json")
    return svc


# ── GET /api/notify-channels ──

@router.get("/notify-channels")
async def get_notify_channels():
    try:
        svc = _get_svc()
        return {"ok": True, "channels": svc.get_channels_meta()}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ── POST /api/notify-config ──

@router.post("/notify-config")
async def save_notify_config(body: dict[str, Any]):
    if not isinstance(body, dict) or "channels" not in body:
        return {"ok": False, "error": "请求体必须包含 channels 字段"}
    try:
        svc = _get_svc()
        cfg = svc.validate_and_normalize_config(body)
        svc.save_config(cfg)
        return {"ok": True, "message": "推送配置已保存"}
    except ValueError as e:
        return {"ok": False, "error": str(e)}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ── POST /api/notify-test ──

@router.post("/notify-test")
async def test_notify_channel(body: dict[str, Any]):
    channel_id = (body.get("channel_id") or "").strip()
    params = body.get("params", {})
    if not channel_id:
        return {"ok": False, "error": "channel_id required"}
    if not isinstance(params, dict):
        return {"ok": False, "error": "params 必须是对象"}
    try:
        svc = _get_svc()
        return svc.send_test(channel_id, params)
    except Exception as e:
        return {"ok": False, "error": str(e)}
