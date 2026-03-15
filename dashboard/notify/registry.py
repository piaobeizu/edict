"""渠道注册中心 — 自动发现并注册所有推送渠道"""

from __future__ import annotations
import importlib
import logging
import pkgutil
from typing import Optional

from .base import NotifyChannel

log = logging.getLogger("notify.registry")

_CHANNELS: dict[str, NotifyChannel] = {}


def register(ch: NotifyChannel) -> None:
    """注册一个渠道"""
    _CHANNELS[ch.channel_id] = ch
    log.debug(f"注册推送渠道: {ch.channel_id} ({ch.display_name})")


def get_channel(channel_id: str) -> Optional[NotifyChannel]:
    """根据 ID 获取渠道"""
    _ensure_loaded()
    return _CHANNELS.get(channel_id)


def all_channels() -> list[NotifyChannel]:
    """返回所有已注册的渠道"""
    _ensure_loaded()
    return list(_CHANNELS.values())


_loaded = False


def _ensure_loaded() -> None:
    """懒加载：首次调用时扫描 channels 包下的所有模块并注册"""
    global _loaded
    if _loaded:
        return

    from . import channels as channels_pkg

    loaded_any = False
    for _importer, mod_name, _is_pkg in pkgutil.iter_modules(channels_pkg.__path__):
        try:
            mod = importlib.import_module(f".channels.{mod_name}", package="notify")
        except ImportError:
            # 尝试用完整路径导入（兼容不同运行方式）
            try:
                mod = importlib.import_module(
                    f"notify.channels.{mod_name}"
                )
            except ImportError:
                # 最后尝试相对于 dashboard 包
                try:
                    mod = importlib.import_module(
                        f"dashboard.notify.channels.{mod_name}"
                    )
                except ImportError:
                    log.warning(f"无法加载渠道模块: {mod_name}")
                    continue

        ch = getattr(mod, "channel", None)
        if isinstance(ch, NotifyChannel):
            register(ch)
            loaded_any = True
        else:
            log.debug(f"模块 {mod_name} 未导出 channel 对象，跳过")

    _loaded = loaded_any or bool(_CHANNELS)
