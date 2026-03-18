"""notify 内部通用工具。"""

from __future__ import annotations

import html
import ipaddress
from urllib.parse import urlparse


def escape_html(text: str) -> str:
    return html.escape(text or "", quote=True)


def validate_https_url(
    url: str,
    *,
    allowed_hosts: tuple[str, ...] | None = None,
    path_prefixes: tuple[str, ...] | None = None,
    allow_any_public_host: bool = False,
) -> tuple[bool, str]:
    """统一 URL 校验。

    - 必须 https
    - hostname 必须存在
    - 拒绝 localhost / 私网 IP / loopback / reserved
    - 如提供 allowed_hosts，必须精确命中
    - 如提供 path_prefixes，路径必须匹配前缀之一
    """

    if not isinstance(url, str) or not url.strip():
        return False, "URL 不能为空"

    parsed = urlparse(url.strip())
    if parsed.scheme != "https":
        return False, "URL 必须以 https:// 开头"

    hostname = (parsed.hostname or "").strip().lower()
    if not hostname:
        return False, "URL 缺少 hostname"
    if hostname == "localhost" or hostname.endswith(".local"):
        return False, "不允许使用本地地址"

    try:
        ip = ipaddress.ip_address(hostname)
        if ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_link_local:
            return False, "不允许使用内网或保留地址"
    except ValueError:
        pass

    if allowed_hosts and hostname not in {h.lower() for h in allowed_hosts}:
        return False, f"仅支持: {', '.join(allowed_hosts)}"

    if not allow_any_public_host and not allowed_hosts:
        return False, "不允许任意外部地址"

    if path_prefixes and not any((parsed.path or "").startswith(p) for p in path_prefixes):
        return False, f"URL 路径必须匹配: {', '.join(path_prefixes)}"

    return True, ""


def mask_secret(value: str, *, show: int = 0) -> str:
    value = value or ""
    if not value:
        return ""
    if show <= 0:
        return "••••••••"
    if len(value) <= show * 2:
        return "•" * len(value)
    return f"{value[:show]}{'•' * max(4, len(value) - show * 2)}{value[-show:]}"
