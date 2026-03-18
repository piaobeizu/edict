"""PushPlus 推送渠道 — 通过微信公众号推送消息到个人微信"""

from __future__ import annotations
import json
import logging
import re
from typing import Any
from urllib.request import Request, urlopen
from urllib.error import URLError

from ..base import NotifyChannel
from ..message import NotifyMessage
from ..utils import escape_html

log = logging.getLogger("notify.pushplus")

PUSHPLUS_API = "https://www.pushplus.plus/send"


class PushPlusChannel(NotifyChannel):
    channel_id = "pushplus"
    display_name = "PushPlus (微信)"
    icon = "📲"
    config_schema = [
        {
            "key": "token",
            "label": "Token",
            "type": "password",
            "placeholder": "在 pushplus.plus 获取的 Token",
            "required": True,
        },
        {
            "key": "topic",
            "label": "群组编码 (可选)",
            "type": "text",
            "placeholder": "留空为单人推送，填写则群组推送",
            "required": False,
        },
        {
            "key": "template",
            "label": "消息模板",
            "type": "select",
            "options": ["html", "markdown", "txt"],
            "default": "html",
            "required": False,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        token = (params.get("token") or "").strip()
        if not token:
            return False, "PushPlus Token 未配置"

        topic = (params.get("topic") or "").strip()
        template = (params.get("template") or "html").strip()

        # 根据模板类型选择内容格式
        if template == "markdown":
            content = message.body or message.body_plain or message.title
        elif template == "html":
            content = self._to_html(message)
        else:
            content = message.body_plain or message.body or message.title

        payload = {
            "token": token,
            "title": message.title[:100],  # PushPlus 标题限制 100 字
            "content": content,
            "template": template,
        }
        if topic:
            payload["topic"] = topic

        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = Request(
            PUSHPLUS_API,
            data=data,
            headers={"Content-Type": "application/json; charset=utf-8"},
        )

        try:
            resp = urlopen(req, timeout=15)
            body = json.loads(resp.read().decode("utf-8"))
            if body.get("code") == 200:
                log.info(f"[PushPlus] 推送成功: {body.get('msg', '')}")
                return True, "推送成功"
            else:
                msg = body.get("msg", "未知错误")
                log.warning(f"[PushPlus] 推送失败: {msg}")
                return False, f"PushPlus 返回错误: {msg}"
        except URLError as e:
            log.error(f"[PushPlus] 网络错误: {e}")
            return False, f"网络错误: {e}"
        except Exception as e:
            log.error(f"[PushPlus] 推送异常: {e}")
            return False, f"推送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        token = (params.get("token") or "").strip()
        if not token:
            return False, "请填写 PushPlus Token"
        if len(token) < 10:
            return False, "Token 格式不正确"
        template = (params.get("template") or "html").strip()
        if template not in {"html", "markdown", "txt"}:
            return False, "template 仅支持 html / markdown / txt"
        return True, ""

    @staticmethod
    def _to_html(message: NotifyMessage) -> str:
        """将消息转为 HTML 格式"""
        lines = [f"<h3>{escape_html(message.title)}</h3>"]
        body = message.body or message.body_plain
        if body:
            html_body = escape_html(body)
            html_body = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", html_body)
            html_body = html_body.replace("\n", "<br>")
            lines.append(f"<p>{html_body}</p>")
        if message.url:
            safe_url = escape_html(message.url)
            lines.append(f'<p><a href="{safe_url}">🔗 查看详情</a></p>')
        return "\n".join(lines)


channel = PushPlusChannel()
