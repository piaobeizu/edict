"""Telegram Bot 推送渠道"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import escape_html

log = logging.getLogger("notify.telegram")


class TelegramChannel(NotifyChannel):
    channel_id = "telegram"
    display_name = "Telegram"
    icon = "✈️"
    config_schema = [
        {
            "key": "bot_token",
            "label": "Bot Token",
            "type": "password",
            "placeholder": "123456:ABC-DEF1234ghIkl-zyx57W2v...",
            "required": True,
        },
        {
            "key": "chat_id",
            "label": "Chat ID",
            "type": "text",
            "placeholder": "-1001234567890 (群组) 或 123456789 (个人)",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        bot_token = (params.get("bot_token") or "").strip()
        chat_id = (params.get("chat_id") or "").strip()
        if not bot_token or not chat_id:
            return False, "Telegram Bot Token 或 Chat ID 未配置"

        text = f"<b>{escape_html(message.title)}</b>\n\n{escape_html(message.body or message.body_plain)}"
        if message.url:
            text += f'\n\n<a href="{escape_html(message.url)}">🔗 查看详情</a>'

        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        payload = json.dumps(
            {
                "chat_id": chat_id,
                "text": text,
                "parse_mode": "HTML",
                "disable_web_page_preview": False,
            }
        ).encode()

        req = Request(
            url, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=15)
            body = json.loads(resp.read().decode())
            if body.get("ok"):
                log.info("[Telegram] 推送成功")
                return True, "推送成功"
            else:
                desc = body.get("description", "未知错误")
                log.warning(f"[Telegram] 推送失败: {desc}")
                return False, f"Telegram 返回错误: {desc}"
        except URLError as e:
            log.error(f"[Telegram] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[Telegram] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        bot_token = (params.get("bot_token") or "").strip()
        chat_id = (params.get("chat_id") or "").strip()
        if not bot_token:
            return False, "请填写 Telegram Bot Token"
        if ":" not in bot_token:
            return False, "Bot Token 格式不正确"
        if not chat_id:
            return False, "请填写 Chat ID"
        return True, ""


channel = TelegramChannel()
