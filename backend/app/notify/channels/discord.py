"""Discord Webhook 推送渠道"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.discord")


class DiscordChannel(NotifyChannel):
    channel_id = "discord"
    display_name = "Discord"
    icon = "🎮"
    config_schema = [
        {
            "key": "webhook_url",
            "label": "Webhook URL",
            "type": "text",
            "placeholder": "https://discord.com/api/webhooks/...",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "Discord Webhook URL 未配置"

        description = (message.body or message.body_plain or "")[:4096]
        if message.url:
            description += f"\n\n[🔗 查看详情]({message.url})"

        payload = json.dumps(
            {
                "embeds": [
                    {
                        "title": message.title[:256],
                        "description": description,
                        "color": 4886754,  # 蓝色
                    }
                ]
            }
        ).encode()

        req = Request(
            webhook, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=10)
            # Discord 成功时返回 204 No Content
            if resp.status in (200, 204):
                log.info("[Discord] 推送成功")
                return True, "推送成功"
            else:
                log.warning(f"[Discord] 推送失败: HTTP {resp.status}")
                return False, f"HTTP {resp.status}"
        except URLError as e:
            log.error(f"[Discord] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[Discord] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "请填写 Discord Webhook URL"
        return validate_https_url(
            webhook,
            allowed_hosts=("discord.com", "canary.discord.com", "ptb.discord.com"),
            path_prefixes=("/api/webhooks/",),
        )


channel = DiscordChannel()
