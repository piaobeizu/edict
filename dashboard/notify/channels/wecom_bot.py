"""企业微信群机器人 Webhook 推送渠道"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.wecom_bot")


class WecomBotChannel(NotifyChannel):
    channel_id = "wecom_bot"
    display_name = "企业微信群机器人"
    icon = "💬"
    config_schema = [
        {
            "key": "webhook_url",
            "label": "Webhook URL",
            "type": "text",
            "placeholder": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=...",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "企业微信 Webhook URL 未配置"

        content = f"## {message.title}\n\n{message.body or message.body_plain}"
        if message.url:
            content += f"\n\n[🔗 查看详情]({message.url})"

        payload = json.dumps(
            {"msgtype": "markdown", "markdown": {"content": content}}
        ).encode()

        req = Request(
            webhook, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=10)
            body = json.loads(resp.read().decode())
            if body.get("errcode") == 0:
                log.info("[企业微信] 推送成功")
                return True, "推送成功"
            else:
                msg = body.get("errmsg", "未知错误")
                log.warning(f"[企业微信] 推送失败: {msg}")
                return False, f"企业微信返回错误: {msg}"
        except URLError as e:
            log.error(f"[企业微信] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[企业微信] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "请填写企业微信 Webhook URL"
        return validate_https_url(
            webhook,
            allowed_hosts=("qyapi.weixin.qq.com",),
            path_prefixes=("/cgi-bin/webhook/send",),
        )


channel = WecomBotChannel()
