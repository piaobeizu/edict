"""
三省六部 · 通用消息推送系统
支持飞书、企业微信、钉钉、Server酱、PushPlus、Telegram、邮件、Bark、Discord、Slack 等渠道。

用法:
    from app.notify.service import NotifyService
    from app.notify.message import NotifyMessage
    from app.notify.registry import get_channel, all_channels
"""

__all__ = ["NotifyService", "NotifyMessage", "get_channel", "all_channels"]
