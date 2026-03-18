"""Slack Webhook 推送渠道"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.slack")


class SlackChannel(NotifyChannel):
    channel_id = "slack"
    display_name = "Slack"
    icon = "💼"
    config_schema = [
        {
            "key": "webhook_url",
            "label": "Webhook URL",
            "type": "text",
            "placeholder": "https://hooks.slack.com/services/T.../B.../...",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "Slack Webhook URL 未配置"

        text = f"*{message.title}*\n\n{message.body or message.body_plain}"
        if message.url:
            text += f"\n\n<{message.url}|🔗 查看详情>"

        payload = json.dumps({"text": text}).encode()

        req = Request(
            webhook, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=10)
            body = resp.read().decode().strip()
            if resp.status == 200 and body == "ok":
                log.info("[Slack] 推送成功")
                return True, "推送成功"
            else:
                log.warning(f"[Slack] 推送失败: {body}")
                return False, f"Slack 返回: {body}"
        except URLError as e:
            log.error(f"[Slack] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[Slack] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "请填写 Slack Webhook URL"
        return validate_https_url(
            webhook,
            allowed_hosts=("hooks.slack.com",),
            path_prefixes=("/services/",),
        )


channel = SlackChannel()
