"""Bark 推送渠道 — iOS 推送通知"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import validate_https_url

log = logging.getLogger("notify.bark")


class BarkChannel(NotifyChannel):
    channel_id = "bark"
    display_name = "Bark (iOS)"
    icon = "🍎"
    config_schema = [
        {
            "key": "server_url",
            "label": "Bark 服务地址",
            "type": "text",
            "placeholder": "https://api.day.app/your-key",
            "required": True,
        },
        {
            "key": "sound",
            "label": "提示音 (可选)",
            "type": "text",
            "placeholder": "默认留空，可选: birdsong, alarm, ...",
            "required": False,
        },
        {
            "key": "group",
            "label": "分组 (可选)",
            "type": "text",
            "placeholder": "三省六部",
            "default": "三省六部",
            "required": False,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        server_url = (params.get("server_url") or "").strip().rstrip("/")
        if not server_url:
            return False, "Bark 服务地址未配置"

        payload: dict[str, Any] = {
            "title": message.title,
            "body": message.body_plain or message.body or message.title,
        }
        if message.url:
            payload["url"] = message.url
        sound = (params.get("sound") or "").strip()
        if sound:
            payload["sound"] = sound
        group = (params.get("group") or "").strip()
        if group:
            payload["group"] = group

        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = Request(
            server_url,
            data=data,
            headers={"Content-Type": "application/json; charset=utf-8"},
        )
        try:
            resp = urlopen(req, timeout=10)
            body = json.loads(resp.read().decode())
            if body.get("code") == 200:
                log.info("[Bark] 推送成功")
                return True, "推送成功"
            else:
                msg = body.get("message", "未知错误")
                log.warning(f"[Bark] 推送失败: {msg}")
                return False, f"Bark 返回错误: {msg}"
        except URLError as e:
            log.error(f"[Bark] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[Bark] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        url = (params.get("server_url") or "").strip()
        if not url:
            return False, "请填写 Bark 服务地址"
        return validate_https_url(url, allow_any_public_host=True)


channel = BarkChannel()
