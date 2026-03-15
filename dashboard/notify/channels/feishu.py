"""飞书 Webhook 推送渠道"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.feishu")


class FeishuChannel(NotifyChannel):
    channel_id = "feishu"
    display_name = "飞书"
    icon = "🐦"
    config_schema = [
        {
            "key": "webhook_url",
            "label": "Webhook URL",
            "type": "text",
            "placeholder": "https://open.feishu.cn/open-apis/bot/v2/hook/...",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "飞书 Webhook URL 未配置"

        payload = json.dumps(
            {
                "msg_type": "interactive",
                "card": {
                    "header": {
                        "title": {"tag": "plain_text", "content": message.title},
                        "template": "blue",
                    },
                    "elements": [
                        {
                            "tag": "div",
                            "text": {
                                "tag": "lark_md",
                                "content": message.body or message.body_plain,
                            },
                        },
                        *(
                            [
                                {
                                    "tag": "action",
                                    "actions": [
                                        {
                                            "tag": "button",
                                            "text": {
                                                "tag": "plain_text",
                                                "content": "🔗 查看详情",
                                            },
                                            "url": message.url,
                                            "type": "primary",
                                        }
                                    ],
                                }
                            ]
                            if message.url
                            else []
                        ),
                    ],
                },
            }
        ).encode()

        req = Request(
            webhook, data=payload, headers={"Content-Type": "application/json"}
        )
        try:
            resp = urlopen(req, timeout=10)
            body_raw = resp.read().decode("utf-8")
            body = json.loads(body_raw) if body_raw else {}
            if body.get("code") in (None, 0) and body.get("StatusCode", 0) == 0:
                log.info(f"[飞书] 推送成功 ({resp.status})")
                return True, "推送成功"
            msg = body.get("msg") or body.get("StatusMessage") or body_raw or "未知错误"
            log.warning(f"[飞书] 推送失败: {msg}")
            return False, f"飞书返回错误: {msg}"
        except URLError as e:
            log.error(f"[飞书] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[飞书] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        webhook = (params.get("webhook_url") or "").strip()
        if not webhook:
            return False, "请填写飞书 Webhook URL"
        return validate_https_url(
            webhook,
            allowed_hosts=("open.feishu.cn", "open.larksuite.com"),
            path_prefixes=("/open-apis/bot/v2/hook/",),
        )


channel = FeishuChannel()
