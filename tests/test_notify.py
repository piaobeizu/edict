"""tests for dashboard/notify — 通用消息推送系统"""

import json
import pathlib
import sys
from unittest.mock import patch, MagicMock

# Add project paths
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "dashboard"))
sys.path.insert(0, str(ROOT / "scripts"))


def test_all_channels_registered():
    """All 10 channels should be auto-discovered and registered."""
    from notify.registry import all_channels

    channels = all_channels()
    ids = {ch.channel_id for ch in channels}
    expected = {
        "feishu", "wecom_bot", "dingtalk", "serverchan", "pushplus",
        "telegram", "email", "bark", "discord", "slack",
    }
    assert ids == expected, f"Missing: {expected - ids}, Extra: {ids - expected}"


def test_channel_meta():
    """Each channel should return valid meta with config_schema."""
    from notify.registry import all_channels

    for ch in all_channels():
        meta = ch.to_meta()
        assert meta["channel_id"] == ch.channel_id
        assert meta["display_name"]
        assert meta["icon"]
        assert isinstance(meta["config_schema"], list)
        assert len(meta["config_schema"]) > 0, f"{ch.channel_id} has empty config_schema"


def test_all_channels_reject_empty_config():
    """Every channel should reject empty params."""
    from notify.registry import all_channels

    for ch in all_channels():
        ok, err = ch.validate_config({})
        assert not ok, f"{ch.channel_id} should reject empty config"
        assert err, f"{ch.channel_id} should return error message"


def test_pushplus_validate():
    """PushPlus validation rules."""
    from notify.registry import get_channel

    pp = get_channel("pushplus")
    assert pp is not None

    ok, _ = pp.validate_config({"token": ""})
    assert not ok

    ok, _ = pp.validate_config({"token": "abc"})
    assert not ok  # too short

    ok, _ = pp.validate_config({"token": "abcdefghijklmnop"})
    assert ok


def test_feishu_validate():
    """Feishu validation: only https and feishu/lark domains."""
    from notify.registry import get_channel

    fs = get_channel("feishu")
    assert fs is not None

    ok, _ = fs.validate_config({"webhook_url": ""})
    assert not ok

    ok, _ = fs.validate_config({"webhook_url": "http://evil.com"})
    assert not ok

    ok, _ = fs.validate_config({"webhook_url": "https://evil.com/hook"})
    assert not ok

    ok, _ = fs.validate_config(
        {"webhook_url": "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"}
    )
    assert ok

    ok, _ = fs.validate_config(
        {"webhook_url": "https://open.larksuite.com/open-apis/bot/v2/hook/xxx"}
    )
    assert ok

    ok, _ = fs.validate_config(
        {"webhook_url": "https://evil.com/?target=https://open.feishu.cn/open-apis/bot/v2/hook/xxx"}
    )
    assert not ok


def test_wecom_bot_validate():
    from notify.registry import get_channel

    ch = get_channel("wecom_bot")
    ok, _ = ch.validate_config({"webhook_url": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"})
    assert ok
    ok, _ = ch.validate_config({"webhook_url": "https://evil.com"})
    assert not ok


def test_dingtalk_validate():
    from notify.registry import get_channel

    ch = get_channel("dingtalk")
    ok, _ = ch.validate_config({"webhook_url": "https://oapi.dingtalk.com/robot/send?access_token=xxx"})
    assert ok
    ok, _ = ch.validate_config({"webhook_url": "https://evil.com"})
    assert not ok
    ok, _ = ch.validate_config({"webhook_url": "https://evil.com/?next=oapi.dingtalk.com/robot/send"})
    assert not ok


def test_serverchan_validate():
    from notify.registry import get_channel

    ch = get_channel("serverchan")
    ok, _ = ch.validate_config({"send_key": "SCTabcdef"})
    assert ok
    ok, _ = ch.validate_config({"send_key": "abc"})
    assert not ok


def test_telegram_validate():
    from notify.registry import get_channel

    ch = get_channel("telegram")
    ok, _ = ch.validate_config({"bot_token": "123:ABC", "chat_id": "-100123"})
    assert ok
    ok, _ = ch.validate_config({"bot_token": "nocolon", "chat_id": "123"})
    assert not ok


def test_notify_service_save_load(tmp_path):
    """NotifyService can save and load config."""
    from notify.service import NotifyService

    cfg_path = tmp_path / "notify_config.json"
    svc = NotifyService(cfg_path)

    # Initial load returns empty
    assert svc.load_config() == {"channels": {}}

    # Save and reload
    svc.save_config({"channels": {"pushplus": {"enabled": True, "token": "test123"}}})
    cfg = svc.load_config()
    assert cfg["channels"]["pushplus"]["enabled"] is True
    assert cfg["channels"]["pushplus"]["token"] == "test123"


def test_notify_service_migrate_legacy(tmp_path):
    """Legacy feishu_webhook should be migrated to new format."""
    from notify.service import NotifyService

    cfg_path = tmp_path / "notify_config.json"
    old_path = tmp_path / "morning_brief_config.json"
    old_path.write_text(json.dumps({"feishu_webhook": "https://open.feishu.cn/hook/xxx"}))

    svc = NotifyService(cfg_path)
    svc.migrate_legacy(old_path)

    cfg = svc.load_config()
    assert cfg["channels"]["feishu"]["enabled"] is True
    assert cfg["channels"]["feishu"]["webhook_url"] == "https://open.feishu.cn/hook/xxx"


def test_notify_service_no_double_migrate(tmp_path):
    """If notify_config.json already exists, migration should be skipped."""
    from notify.service import NotifyService

    cfg_path = tmp_path / "notify_config.json"
    cfg_path.write_text(json.dumps({"channels": {"slack": {"enabled": True}}}))

    old_path = tmp_path / "morning_brief_config.json"
    old_path.write_text(json.dumps({"feishu_webhook": "https://open.feishu.cn/hook/xxx"}))

    svc = NotifyService(cfg_path)
    svc.migrate_legacy(old_path)

    # Should NOT have feishu, because existing config takes precedence
    cfg = svc.load_config()
    assert "feishu" not in cfg["channels"]
    assert cfg["channels"]["slack"]["enabled"] is True


def test_notify_service_get_channels_meta(tmp_path):
    """get_channels_meta returns all channels with merged config."""
    from notify.service import NotifyService

    cfg_path = tmp_path / "notify_config.json"
    cfg_path.write_text(json.dumps({
        "channels": {
            "pushplus": {"enabled": True, "token": "mytoken"},
            "feishu": {"enabled": False, "webhook_url": "https://open.feishu.cn/hook/xxx"},
        }
    }))

    svc = NotifyService(cfg_path)
    metas = svc.get_channels_meta()

    assert len(metas) == 10  # All channels should appear

    pp = next(m for m in metas if m["channel_id"] == "pushplus")
    assert pp["enabled"] is True
    assert pp["params"]["token"] == ""
    assert pp["secret_state"]["token"]["has_value"] is True

    fs = next(m for m in metas if m["channel_id"] == "feishu")
    assert fs["enabled"] is False
    assert fs["params"]["webhook_url"] == "https://open.feishu.cn/hook/xxx"

    # Non-configured channels should have enabled=False
    tg = next(m for m in metas if m["channel_id"] == "telegram")
    assert tg["enabled"] is False
    assert tg["params"] == {}


def test_notify_service_send_all_no_channels(tmp_path):
    """send_all with no enabled channels returns empty results."""
    from notify.service import NotifyService
    from notify.message import NotifyMessage

    svc = NotifyService(tmp_path / "notify_config.json")
    msg = NotifyMessage(title="Test", body="Hello")
    results = svc.send_all(msg)
    assert results == {}


def test_notify_service_send_test_unknown_channel(tmp_path):
    """send_test with unknown channel returns error."""
    from notify.service import NotifyService

    svc = NotifyService(tmp_path / "notify_config.json")
    r = svc.send_test("nonexistent", {})
    assert r["ok"] is False
    assert "未知渠道" in r["msg"]


def test_notify_service_send_test_invalid_config(tmp_path):
    """send_test with invalid config returns validation error."""
    from notify.service import NotifyService

    svc = NotifyService(tmp_path / "notify_config.json")
    r = svc.send_test("pushplus", {})
    assert r["ok"] is False
    assert "Token" in r["msg"]


def test_notify_service_validate_and_normalize_config_preserves_secret(tmp_path):
    from notify.service import NotifyService

    cfg_path = tmp_path / "notify_config.json"
    cfg_path.write_text(json.dumps({
        "channels": {
            "pushplus": {"enabled": True, "token": "old_secret", "template": "html"}
        }
    }))
    svc = NotifyService(cfg_path)
    normalized = svc.validate_and_normalize_config({
        "channels": {
            "pushplus": {"enabled": True, "token": "", "template": "markdown"}
        }
    })
    assert normalized["channels"]["pushplus"]["token"] == "old_secret"
    assert normalized["channels"]["pushplus"]["template"] == "markdown"


def test_notify_service_validate_and_normalize_rejects_unknown_channel(tmp_path):
    from notify.service import NotifyService

    svc = NotifyService(tmp_path / "notify_config.json")
    try:
        svc.validate_and_normalize_config({"channels": {"bad": {"enabled": True}}})
        assert False, "should raise"
    except ValueError as e:
        assert "未知渠道" in str(e)


def test_notify_service_validate_and_normalize_rejects_unknown_field(tmp_path):
    from notify.service import NotifyService

    svc = NotifyService(tmp_path / "notify_config.json")
    try:
        svc.validate_and_normalize_config({
            "channels": {"pushplus": {"enabled": True, "token": "abcdeabcde", "oops": "x"}}
        })
        assert False, "should raise"
    except ValueError as e:
        assert "未知字段" in str(e)


def test_notify_service_validate_and_normalize_rejects_invalid_url(tmp_path):
    from notify.service import NotifyService

    svc = NotifyService(tmp_path / "notify_config.json")
    try:
        svc.validate_and_normalize_config({
            "channels": {"slack": {"enabled": True, "webhook_url": "https://evil.com/abc"}}
        })
        assert False, "should raise"
    except ValueError as e:
        assert "Slack" in str(e)


@patch("notify.channels.pushplus.urlopen")
def test_notify_service_send_test_preserves_existing_secret(mock_urlopen, tmp_path):
    from notify.service import NotifyService

    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps({"code": 200, "msg": "ok"}).encode()
    mock_urlopen.return_value = mock_resp

    cfg_path = tmp_path / "notify_config.json"
    cfg_path.write_text(json.dumps({
        "channels": {"pushplus": {"enabled": True, "token": "saved_token_12345"}}
    }))
    svc = NotifyService(cfg_path)
    r = svc.send_test("pushplus", {"token": ""})
    assert r["ok"] is True


@patch("notify.channels.pushplus.urlopen")
def test_pushplus_send_success(mock_urlopen, tmp_path):
    """PushPlus send succeeds when API returns code 200."""
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps({"code": 200, "msg": "ok"}).encode()
    mock_urlopen.return_value = mock_resp

    pp = get_channel("pushplus")
    msg = NotifyMessage(title="Test", body="Hello **world**", url="http://example.com")
    ok, result_msg = pp.send(msg, {"token": "valid_token_12345"})
    assert ok
    assert "成功" in result_msg
    mock_urlopen.assert_called_once()


def test_pushplus_html_escapes_content():
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    pp = get_channel("pushplus")
    html = pp._to_html(NotifyMessage(
        title="<title>",
        body="Hello **world** <script>",
        url='https://example.com/?q=<x>'
    ))
    assert "<script>" not in html
    assert "&lt;script&gt;" in html
    assert "<b>world</b>" in html


@patch("notify.channels.pushplus.urlopen")
def test_pushplus_send_failure(mock_urlopen):
    """PushPlus send fails when API returns non-200 code."""
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    mock_resp = MagicMock()
    mock_resp.read.return_value = json.dumps({"code": 400, "msg": "token invalid"}).encode()
    mock_urlopen.return_value = mock_resp

    pp = get_channel("pushplus")
    msg = NotifyMessage(title="Test", body="Hello")
    ok, result_msg = pp.send(msg, {"token": "bad_token_12345"})
    assert not ok
    assert "token invalid" in result_msg


@patch("notify.channels.feishu.urlopen")
def test_feishu_send_success(mock_urlopen):
    """Feishu send succeeds."""
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.read.return_value = json.dumps({"StatusCode": 0, "StatusMessage": "success"}).encode()
    mock_urlopen.return_value = mock_resp

    fs = get_channel("feishu")
    msg = NotifyMessage(title="Test", body="Hello", url="http://example.com")
    ok, _ = fs.send(msg, {"webhook_url": "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"})
    assert ok


@patch("notify.channels.feishu.urlopen")
def test_feishu_send_failure_when_body_reports_error(mock_urlopen):
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.read.return_value = json.dumps({"StatusCode": 9499, "StatusMessage": "bad token"}).encode()
    mock_urlopen.return_value = mock_resp

    fs = get_channel("feishu")
    ok, msg = fs.send(NotifyMessage(title="T", body="B"), {"webhook_url": "https://open.feishu.cn/open-apis/bot/v2/hook/xxx"})
    assert not ok
    assert "bad token" in msg


@patch("notify.channels.slack.urlopen")
def test_slack_send_failure_on_non_ok_body(mock_urlopen):
    from notify.registry import get_channel
    from notify.message import NotifyMessage

    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.read.return_value = b"invalid_payload"
    mock_urlopen.return_value = mock_resp

    slack = get_channel("slack")
    ok, msg = slack.send(NotifyMessage(title="T", body="B"), {"webhook_url": "https://hooks.slack.com/services/T/B/X"})
    assert not ok
    assert "invalid_payload" in msg


def test_dingtalk_sign():
    """DingTalk signing generates valid URL with timestamp and sign."""
    from notify.channels.dingtalk import DingTalkChannel

    url = DingTalkChannel._sign_url(
        "https://oapi.dingtalk.com/robot/send?access_token=xxx",
        "SECtest123"
    )
    assert "timestamp=" in url
    assert "sign=" in url
