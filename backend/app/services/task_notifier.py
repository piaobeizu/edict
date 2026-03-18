"""任务状态推送 — 关键节点通知到微信/飞书等渠道。

复用 app.notify 推送系统，在 Worker 中以 best-effort 方式调用。
推送失败不影响主流程。
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

log = logging.getLogger("edict.task_notifier")

# 状态中文映射
_STATE_LABELS = {
    "Taizi": "📋 太子分拣",
    "Zhongshu": "📜 中书省起草",
    "Menxia": "🔍 门下省审议",
    "YuLan": "⏳ 等待御览",
    "Assigned": "🚀 尚书省派发",
    "Doing": "⚙️ 六部执行中",
    "Review": "🔎 审查汇总",
    "Done": "✅ 完成",
    "Blocked": "⚠️ 阻塞",
    "Cancelled": "❌ 取消",
}

# 需要推送的关键节点（不是所有状态变更都推）
_NOTIFY_STATES = {"YuLan", "Assigned", "Done", "Blocked", "Cancelled"}


def _get_notify_service():
    """懒加载 NotifyService。"""
    try:
        from ..notify.service import NotifyService
        data_dir = Path("/app/data")
        if not data_dir.exists():
            data_dir = Path(__file__).resolve().parents[4] / "data"
        return NotifyService(data_dir / "notify_config.json")
    except Exception as e:
        log.debug(f"NotifyService 不可用: {e}")
        return None


def notify_task_created(task_id: str, title: str, **kwargs: Any) -> None:
    """任务创建通知。"""
    _send(
        title=f"📋 新旨意: {title}",
        body=f"任务 **{task_id}** 已创建\n{title}",
        body_plain=f"任务 {task_id} 已创建: {title}",
        msg_type="task_created",
    )


def notify_task_state_changed(
    task_id: str,
    title: str,
    from_state: str,
    to_state: str,
    reason: str = "",
    **kwargs: Any,
) -> None:
    """任务状态变更通知（只推关键节点）。"""
    if to_state not in _NOTIFY_STATES:
        return

    label = _STATE_LABELS.get(to_state, to_state)

    if to_state == "YuLan":
        msg_title = f"⏳ {task_id} 等待御批"
        body = f"任务 **{title}** 已通过门下省审议\n方案呈送御览，请在看板操作「准奏」或「封驳」"
    elif to_state == "Done":
        msg_title = f"✅ {task_id} 已完成"
        body = f"任务 **{title}** 已完成\n{reason}" if reason else f"任务 **{title}** 已完成"
    elif to_state == "Blocked":
        msg_title = f"⚠️ {task_id} 阻塞"
        body = f"任务 **{title}** 已阻塞\n原因: {reason}" if reason else f"任务 **{title}** 已阻塞"
    elif to_state == "Assigned":
        msg_title = f"🚀 {task_id} 御批派发"
        body = f"任务 **{title}** 已御批准奏，派发六部执行"
    elif to_state == "Cancelled":
        msg_title = f"❌ {task_id} 已取消"
        body = f"任务 **{title}** 已取消\n{reason}" if reason else f"任务 **{title}** 已取消"
    else:
        msg_title = f"{label}: {task_id}"
        body = f"任务 **{title}** 状态变更为 {label}"

    _send(title=msg_title, body=body, body_plain=body.replace("**", ""), msg_type="task_status")


def notify_task_stalled(task_id: str, stall_count: int, **kwargs: Any) -> None:
    """任务停滞通知。"""
    if stall_count < 3:
        return  # 前几次不推，避免噪音
    _send(
        title=f"⏸️ {task_id} 停滞 ({stall_count}次)",
        body=f"任务 **{task_id}** 已连续停滞 {stall_count} 次，可能需要人工干预",
        body_plain=f"任务 {task_id} 已连续停滞 {stall_count} 次",
        msg_type="task_stalled",
    )


def _send(title: str, body: str, body_plain: str = "", msg_type: str = "task_status") -> None:
    """Best-effort 推送 — 失败不影响主流程。"""
    try:
        svc = _get_notify_service()
        if svc is None:
            return
        from ..notify.message import NotifyMessage
        msg = NotifyMessage(
            title=title,
            body=body,
            body_plain=body_plain or body.replace("**", ""),
            msg_type=msg_type,
        )
        results = svc.send_all(msg)
        for ch_id, r in results.items():
            if r["ok"]:
                log.debug(f"[{ch_id}] 任务通知推送成功")
            else:
                log.warning(f"[{ch_id}] 任务通知推送失败: {r['msg']}")
    except Exception as e:
        log.warning(f"任务通知推送异常（不影响主流程）: {e}")
