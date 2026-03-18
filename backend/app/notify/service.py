"""推送调度服务 — 读取配置，向所有已启用渠道分发消息"""

from __future__ import annotations
import json
import logging
import pathlib
from typing import Any

from .message import NotifyMessage
from .registry import get_channel, all_channels as _all_channels
from .utils import mask_secret

log = logging.getLogger("notify.service")


class NotifyService:
    """消息推送调度中心。

    读取 notify_config.json，遍历已启用渠道，逐一发送。
    """

    def __init__(self, config_path: pathlib.Path):
        self.config_path = config_path

    # ── 配置读写 ──

    def load_config(self) -> dict[str, Any]:
        """加载推送配置"""
        try:
            return json.loads(self.config_path.read_text())
        except Exception:
            return {"channels": {}}

    def save_config(self, cfg: dict[str, Any]) -> None:
        """保存推送配置"""
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = self.config_path.with_suffix(self.config_path.suffix + ".tmp")
        tmp_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
        tmp_path.replace(self.config_path)

    def validate_and_normalize_config(self, raw_cfg: dict[str, Any]) -> dict[str, Any]:
        """校验并标准化配置。

        - 仅允许已注册渠道
        - 仅允许 schema 中声明的字段
        - password 字段允许留空，此时沿用旧值
        - 启用中的渠道必须通过 validate_config
        """

        if not isinstance(raw_cfg, dict) or not isinstance(raw_cfg.get("channels"), dict):
            raise ValueError("请求体必须包含 channels 对象")

        existing = self.load_config().get("channels", {})
        normalized: dict[str, Any] = {"channels": {}}

        for channel_id, input_cfg in raw_cfg["channels"].items():
            if not isinstance(channel_id, str):
                raise ValueError("channel_id 必须是字符串")
            ch = get_channel(channel_id)
            if not ch:
                raise ValueError(f"未知渠道: {channel_id}")
            if not isinstance(input_cfg, dict):
                raise ValueError(f"渠道 {channel_id} 的配置必须是对象")

            allowed_keys = ch.allowed_keys()
            secret_keys = ch.secret_keys()
            unknown = set(input_cfg.keys()) - (allowed_keys | {"enabled"})
            if unknown:
                raise ValueError(
                    f"渠道 {channel_id} 存在未知字段: {', '.join(sorted(unknown))}"
                )

            current_cfg = existing.get(channel_id, {}) if isinstance(existing.get(channel_id), dict) else {}
            enabled = bool(input_cfg.get("enabled", False))
            params: dict[str, Any] = {}
            for key in allowed_keys:
                incoming = input_cfg.get(key, None)
                if key in secret_keys:
                    if isinstance(incoming, str) and incoming.strip():
                        params[key] = incoming.strip()
                    elif current_cfg.get(key):
                        params[key] = current_cfg.get(key)
                else:
                    if incoming is None:
                        if key in current_cfg:
                            params[key] = current_cfg.get(key)
                    elif isinstance(incoming, str):
                        params[key] = incoming.strip()
                    else:
                        params[key] = incoming

            if enabled:
                valid, err = ch.validate_config(params)
                if not valid:
                    raise ValueError(f"{ch.display_name}: {err}")

            normalized["channels"][channel_id] = {"enabled": enabled, **params}

        return normalized

    # ── 迁移兼容 ──

    def migrate_legacy(self, morning_config_path: pathlib.Path) -> None:
        """从旧版 morning_brief_config.json 迁移飞书 webhook 配置。

        只在 notify_config.json 不存在时执行一次。
        """
        if self.config_path.exists():
            return
        try:
            old = json.loads(morning_config_path.read_text())
        except Exception:
            return
        webhook = (old.get("feishu_webhook") or "").strip()
        if webhook:
            cfg = {
                "channels": {
                    "feishu": {
                        "enabled": True,
                        **{k: v for k, v in [("webhook_url", webhook)]},
                    }
                }
            }
            self.save_config(cfg)
            log.info(f"已从旧配置迁移飞书 Webhook → notify_config.json")

    # ── 发送 ──

    def send_all(self, message: NotifyMessage) -> dict[str, Any]:
        """向所有已启用的渠道发送消息。

        Returns:
            {channel_id: {"ok": bool, "msg": str}, ...}
        """
        cfg = self.load_config()
        results: dict[str, Any] = {}

        for channel_id, channel_cfg in cfg.get("channels", {}).items():
            if not channel_cfg.get("enabled"):
                continue

            ch = get_channel(channel_id)
            if not ch:
                results[channel_id] = {
                    "ok": False,
                    "msg": f"未知渠道: {channel_id}",
                }
                continue

            # 提取参数（排除 enabled 字段）
            params = {k: v for k, v in channel_cfg.items() if k != "enabled"}

            try:
                valid, err = ch.validate_config(params)
                if not valid:
                    results[channel_id] = {"ok": False, "msg": f"配置无效: {err}"}
                    continue
                ok, msg = ch.send(message, params)
                results[channel_id] = {"ok": ok, "msg": msg}
            except Exception as e:
                log.error(f"[{channel_id}] 发送异常: {e}")
                results[channel_id] = {"ok": False, "msg": f"异常: {e}"}

        return results

    def send_test(self, channel_id: str, params: dict[str, Any]) -> dict[str, Any]:
        """发送测试消息到指定渠道"""
        if not isinstance(params, dict):
            return {"ok": False, "msg": "params 必须是对象"}
        ch = get_channel(channel_id)
        if not ch:
            return {"ok": False, "msg": f"未知渠道: {channel_id}"}

        merged_params = dict(params)
        current_cfg = self.load_config().get("channels", {}).get(channel_id, {})
        for key in ch.secret_keys():
            if not (merged_params.get(key) or "") and current_cfg.get(key):
                merged_params[key] = current_cfg.get(key)

        # 先校验配置
        valid, err = ch.validate_config(merged_params)
        if not valid:
            return {"ok": False, "msg": err}

        test_msg = NotifyMessage(
            title="🧪 三省六部 · 推送测试",
            body="如果你看到这条消息，说明推送渠道配置成功！\n\n**渠道**: "
            + ch.display_name,
            body_plain="如果你看到这条消息，说明推送渠道配置成功！",
            url="",
            msg_type="test",
        )
        try:
            ok, msg = ch.send(test_msg, merged_params)
            return {"ok": ok, "msg": msg}
        except Exception as e:
            return {"ok": False, "msg": f"异常: {e}"}

    # ── 查询 ──

    def get_channels_meta(self) -> list[dict[str, Any]]:
        """返回所有渠道的元信息 + 当前配置状态"""
        cfg = self.load_config()
        channels_cfg = cfg.get("channels", {})
        result = []
        for ch in _all_channels():
            ch_cfg = channels_cfg.get(ch.channel_id, {})
            meta = ch.to_meta()
            meta["enabled"] = ch_cfg.get("enabled", False)
            secret_keys = ch.secret_keys()
            params = {}
            secret_state = {}
            for key, value in ch_cfg.items():
                if key == "enabled":
                    continue
                if key in secret_keys:
                    params[key] = ""
                    secret_state[key] = {
                        "has_value": bool(value),
                        "masked": mask_secret(str(value), show=2) if value else "",
                    }
                else:
                    params[key] = value
            meta["params"] = params
            meta["secret_state"] = secret_state
            result.append(meta)
        return result
