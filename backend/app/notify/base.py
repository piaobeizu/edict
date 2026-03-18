"""推送渠道抽象基类"""

from __future__ import annotations
from abc import ABC, abstractmethod
from typing import Any

from .message import NotifyMessage


class NotifyChannel(ABC):
    """所有推送渠道的抽象基类。

    子类必须定义类属性并实现 send / validate_config 方法。
    """

    # ── 子类必须定义的元信息 ──
    channel_id: str = ""  # 唯一标识: "feishu", "wecom_bot" …
    display_name: str = ""  # 显示名: "飞书", "企业微信群机器人" …
    icon: str = ""  # emoji 图标
    config_schema: list[dict[str, Any]] = []  # 配置表单 schema（供前端动态渲染）

    @abstractmethod
    def send(self, message: NotifyMessage, params: dict[str, Any]) -> tuple[bool, str]:
        """发送消息。

        Args:
            message: 统一消息对象
            params: 渠道配置参数 (webhook_url, token 等)

        Returns:
            (是否成功, 结果描述)
        """
        ...

    @abstractmethod
    def validate_config(self, params: dict[str, Any]) -> tuple[bool, str]:
        """校验渠道配置是否合法。

        Returns:
            (是否合法, 错误信息)
        """
        ...

    def to_meta(self) -> dict[str, Any]:
        """返回渠道元信息（给前端用）"""
        return {
            "channel_id": self.channel_id,
            "display_name": self.display_name,
            "icon": self.icon,
            "config_schema": self.config_schema,
        }

    def secret_keys(self) -> set[str]:
        return {
            str(item.get("key"))
            for item in self.config_schema
            if item.get("type") == "password" and item.get("key")
        }

    def allowed_keys(self) -> set[str]:
        return {
            str(item.get("key"))
            for item in self.config_schema
            if item.get("key")
        }
