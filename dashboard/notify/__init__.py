"""
三省六部 · 通用消息推送系统
支持飞书、企业微信、钉钉、Server酱、PushPlus、Telegram、邮件、Bark、Discord、Slack 等渠道。

用法:
    from notify.service import NotifyService
    from notify.message import NotifyMessage
    from notify.registry import get_channel, all_channels
"""

__all__ = ["NotifyService", "NotifyMessage", "get_channel", "all_channels"]
