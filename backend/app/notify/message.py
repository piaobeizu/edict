"""统一消息格式定义"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any


@dataclass
class NotifyMessage:
    """渠道无关的统一消息格式。

    所有推送渠道都接收此对象，自行适配为各自的消息体。
    """

    title: str  # 消息标题
    body: str  # 正文 (Markdown)
    body_plain: str = ""  # 纯文本备选（给不支持 MD 的渠道）
    url: str = ""  # 可选跳转链接
    msg_type: str = "brief"  # 消息类型: brief / alert / task_done / approval
    extra: dict[str, Any] = field(default_factory=dict)  # 渠道特有附加数据
