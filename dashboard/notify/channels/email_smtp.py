"""邮件 SMTP 推送渠道"""

from __future__ import annotations
import logging
import smtplib
from html import escape
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Any

from ..base import NotifyChannel
from ..message import NotifyMessage

log = logging.getLogger("notify.email")


class EmailChannel(NotifyChannel):
    channel_id = "email"
    display_name = "邮件"
    icon = "📧"
    config_schema = [
        {
            "key": "smtp_host",
            "label": "SMTP 服务器",
            "type": "text",
            "placeholder": "smtp.qq.com / smtp.gmail.com / ...",
            "required": True,
        },
        {
            "key": "smtp_port",
            "label": "端口",
            "type": "text",
            "placeholder": "465 (SSL) 或 587 (TLS)",
            "default": "465",
            "required": True,
        },
        {
            "key": "username",
            "label": "发件邮箱",
            "type": "text",
            "placeholder": "your@email.com",
            "required": True,
        },
        {
            "key": "password",
            "label": "密码/授权码",
            "type": "password",
            "placeholder": "邮箱密码或 SMTP 授权码",
            "required": True,
        },
        {
            "key": "to_addr",
            "label": "收件邮箱",
            "type": "text",
            "placeholder": "receiver@email.com (多个用逗号分隔)",
            "required": True,
        },
        {
            "key": "use_ssl",
            "label": "使用 SSL",
            "type": "select",
            "options": ["true", "false"],
            "default": "true",
            "required": False,
        },
    ]

    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        smtp_host = (params.get("smtp_host") or "").strip()
        smtp_port = int(params.get("smtp_port") or 465)
        username = (params.get("username") or "").strip()
        password = (params.get("password") or "").strip()
        to_addr = (params.get("to_addr") or "").strip()
        use_ssl = str(params.get("use_ssl", "true")).lower() == "true"

        if not all([smtp_host, username, password, to_addr]):
            return False, "邮件配置不完整"

        recipients = [a.strip() for a in to_addr.split(",") if a.strip()]

        msg = MIMEMultipart("alternative")
        msg["Subject"] = message.title
        msg["From"] = username
        msg["To"] = ", ".join(recipients)

        # 纯文本
        plain = message.body_plain or message.body or message.title
        if message.url:
            plain += f"\n\n查看详情: {message.url}"
        msg.attach(MIMEText(plain, "plain", "utf-8"))

        # HTML
        html = self._to_html(message)
        msg.attach(MIMEText(html, "html", "utf-8"))

        try:
            if use_ssl:
                server = smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=15)
            else:
                server = smtplib.SMTP(smtp_host, smtp_port, timeout=15)
                server.starttls()

            server.login(username, password)
            server.sendmail(username, recipients, msg.as_string())
            server.quit()
            log.info(f"[邮件] 发送成功 → {to_addr}")
            return True, "发送成功"
        except smtplib.SMTPAuthenticationError:
            return False, "SMTP 认证失败，请检查用户名和密码"
        except smtplib.SMTPException as e:
            log.error(f"[邮件] SMTP 错误: {e}")
            return False, f"SMTP 错误: {e}"
        except Exception as e:
            log.error(f"[邮件] 发送异常: {e}")
            return False, f"发送异常: {e}"

    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        for key in ("smtp_host", "username", "password", "to_addr"):
            if not (params.get(key) or "").strip():
                return False, f"请填写 {key}"
        port = params.get("smtp_port", "465")
        try:
            int(port)
        except (ValueError, TypeError):
            return False, "端口号必须是数字"
        return True, ""

    @staticmethod
    def _to_html(message: NotifyMessage) -> str:
        body = message.body or message.body_plain or ""
        body_html = escape(body).replace("\n", "<br>")
        link = (
            f'<p><a href="{escape(message.url, quote=True)}" style="color:#4a9eff;">🔗 查看详情</a></p>'
            if message.url
            else ""
        )
        return f"""
        <div style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:20px;">
            <h2 style="color:#333;">{escape(message.title)}</h2>
            <div style="color:#555;line-height:1.6;">{body_html}</div>
            {link}
            <hr style="border:none;border-top:1px solid #eee;margin:20px 0;">
            <p style="color:#999;font-size:12px;">由三省六部 · Edict 自动发送</p>
        </div>
        """


channel = EmailChannel()
