"""Server酱 (ServerChan) 推送渠道 — 推送到个人微信"""

from __future__ import annotations
import json
import logging
from typing import Any
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage

log = logging.getLogger("notify.serverchan")


class ServerChanChannel(NotifyChannel):
    channel_id = "serverchan"
    display_name = "Server酱 (微信)"
    icon = "📡"
    config_schema = [
        {
            "key": "send_key",
            "label": "SendKey",
            "type": "password",
            "placeholder": "SCT... (在 sct.ftqq.com 获取)",
            "required": True,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        send_key = (params.get("send_key") or "").strip()
        if not send_key:
            return False, "Server酱 SendKey 未配置"

        url = f"https://sctapi.ftqq.com/{send_key}.send"

        desp = message.body or message.body_plain or ""
        if message.url:
            desp += f"\n\n[🔗 查看详情]({message.url})"

        data = urlencode(
            {"title": message.title[:256], "desp": desp[:32768]}
        ).encode("utf-8")

        req = Request(
            url,
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"},
        )
        try:
            resp = urlopen(req, timeout=15)
            body = json.loads(resp.read().decode())
            if body.get("code") == 0:
                log.info("[Server酱] 推送成功")
                return True, "推送成功"
            else:
                msg = body.get("message", "未知错误")
                log.warning(f"[Server酱] 推送失败: {msg}")
                return False, f"Server酱返回错误: {msg}"
        except URLError as e:
            log.error(f"[Server酱] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[Server酱] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        key = (params.get("send_key") or "").strip()
        if not key:
            return False, "请填写 Server酱 SendKey"
        if not key.startswith("SCT"):
            return False, "SendKey 格式不正确，应以 SCT 开头"
        return True, ""


channel = ServerChanChannel()
