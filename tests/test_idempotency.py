"""幂等去重逻辑单测。"""

import pytest


class TestEventDeduplication:
    """事件去重逻辑测试（不依赖 Redis，测试去重键的生成逻辑）。"""

    def test_event_dedup_key_format(self):
        """事件去重键格式：edict:orch:event:{event_id}"""
        event_id = "550e8400-e29b-41d4-a716-446655440000"
        key = f"edict:orch:event:{event_id}"
        assert key == "edict:orch:event:550e8400-e29b-41d4-a716-446655440000"

    def test_dispatch_idem_key_format(self):
        """派发幂等键格式：edict:dispatch:idem:{task_id}:{agent}:{round}"""
        task_id = "JJC-20260313-001"
        agent = "taizi"
        dispatch_round = 1
        key = f"edict:dispatch:idem:{task_id}:{agent}:{dispatch_round}"
        assert key == "edict:dispatch:idem:JJC-20260313-001:taizi:1"

    def test_different_rounds_produce_different_keys(self):
        """不同 round 应该产生不同的幂等键。"""
        base = "edict:dispatch:idem:JJC-001:taizi"
        assert f"{base}:1" != f"{base}:2"

    def test_different_agents_produce_different_keys(self):
        """不同 agent 应该产生不同的幂等键。"""
        base = "edict:dispatch:idem:JJC-001"
        assert f"{base}:taizi:1" != f"{base}:zhongshu:1"


class TestDispatchRoundLogic:
    """派发轮次逻辑测试。"""

    def test_default_round_is_1(self):
        payload = {}
        dispatch_round = int(payload.get("dispatch_round") or 1)
        assert dispatch_round == 1

    def test_round_from_payload(self):
        payload = {"dispatch_round": 3}
        dispatch_round = int(payload.get("dispatch_round") or 1)
        assert dispatch_round == 3

    def test_round_none_defaults_to_1(self):
        payload = {"dispatch_round": None}
        dispatch_round = int(payload.get("dispatch_round") or 1)
        assert dispatch_round == 1

    def test_round_string_conversion(self):
        payload = {"dispatch_round": "5"}
        dispatch_round = int(payload.get("dispatch_round") or 1)
        assert dispatch_round == 5
