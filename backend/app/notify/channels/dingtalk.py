"""钉钉群机器人 Webhook 推送渠道"""

from __future__ import annotations
import hashlib
import hmac
import json
import logging
import time
import base64
from typing import Any
from urllib.parse import quote_plus
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.dingtalk")


class DingTalkChannel(NotifyChannel):
    channel_id = "dingtalk"
    display_name = "钉钉"
    icon = "🔔"
    config_schema = [
        {
            "key": "webhook_url",
            "label": "Webhook URL",
            "type": "text",
            "placeholder": "https://oapi.dingtalk.com/robot/send?access_token=...",
            "required": True,
        },
        {
            "key": "secret",
            "label": "加签密钥 (可选)",
            "type": "password",
            "placeholder": "SEC...",
            "required": False,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "钉钉 Webhook URL 未配置"

        secret = (params.get("secret") or "").strip()
        if secret:
            webhook = self._sign_url(webhook, secret)

        text = f"### {message.title}\n\n{message.body or message.body_plain}"
        if message.url:
            text += f"\n\n[🔗 查看详情]({message.url})"

        payload = json.dumps(
            {
                "msgtype": "markdown",
                "markdown": {"title": message.title, "text": text},
            }
        ).encode()

        req = Request(
            webhook, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=10)
            body = json.loads(resp.read().decode())
            if body.get("errcode") == 0:
                log.info("[钉钉] 推送成功")
                return True, "推送成功"
            else:
                msg = body.get("errmsg", "未知错误")
                log.warning(f"[钉钉] 推送失败: {msg}")
                return False, f"钉钉返回错误: {msg}"
        except URLError as e:
            log.error(f"[钉钉] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[钉钉] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "请填写钉钉 Webhook URL"
        return validate_https_url(
            webhook,
            allowed_hosts=("oapi.dingtalk.com",),
            path_prefixes=("/robot/send",),
        )

    @staticmethod
    def _sign_url(webhook: str, secret: str) -> str:
        """钉钉加签"""
        timestamp = str(round(time.time() * 1000))
        string_to_sign = f"{timestamp}\n{secret}"
        hmac_code = hmac.new(
            secret.encode("utf-8"),
            string_to_sign.encode("utf-8"),
            digestmod=hashlib.sha256,
        ).digest()
        sign = quote_plus(base64.b64encode(hmac_code))
        sep = "&" if "?" in webhook else "?"
        return f"{webhook}{sep}timestamp={timestamp}&sign={sign}"


channel = DingTalkChannel()
