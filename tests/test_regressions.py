"""关键回归测试。"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest
from fastapi import WebSocketDisconnect

from app.api.websocket import _handle_client_messages, _relay_events
from app.models.task import Task, TaskState
from app.services.task_service import generate_task_id
from app.workers.dispatch_worker import DispatchWorker


class _DummyPubSub:
    def __init__(self, messages):
        self._messages = list(messages)

    async def listen(self):
        for message in self._messages:
            yield message


class _DummyWebSocket:
    def __init__(self, receive_events=None):
        self.receive_events = list(receive_events or [])
        self.sent = []

    async def send_json(self, data):
        self.sent.append(data)

    async def receive_json(self):
        if not self.receive_events:
            raise WebSocketDisconnect()
        event = self.receive_events.pop(0)
        if isinstance(event, Exception):
            raise event
        return event


def test_generate_task_id_has_longer_suffix_and_fits_column():
    now = datetime(2026, 3, 16, 12, 0, 0, tzinfo=timezone.utc)
    task_id = generate_task_id(now)
    assert task_id.startswith("JJC-20260316-120000-")
    assert len(task_id) <= 32
    assert len(task_id.rsplit("-", 1)[-1]) == 8


def test_generate_task_id_differs_with_same_timestamp():
    now = datetime(2026, 3, 16, 12, 0, 0, tzinfo=timezone.utc)
    assert generate_task_id(now) != generate_task_id(now)


def test_task_to_dict_does_not_inject_fake_todos():
    task = Task(id="JJC-1", title="t", state=TaskState.Done.value, todos=[])
    payload = task.to_dict()
    assert payload["todos"] == []


def test_dispatch_worker_next_state_map_supports_blocked_resume():
    assert DispatchWorker._NEXT_STATE_MAP[TaskState.Blocked] == TaskState.Taizi


@pytest.mark.asyncio
async def test_relay_events_continues_after_bad_message():
    pubsub = _DummyPubSub([
        {"type": "pmessage", "channel": "edict:pubsub:task.status", "data": "not-json"},
        {
            "type": "pmessage",
            "channel": "edict:pubsub:task.status",
            "data": '{"payload": {"task_id": "JJC-1"}}',
        },
    ])
    ws = _DummyWebSocket()

    await _relay_events(pubsub, ws)

    assert len(ws.sent) == 1
    assert ws.sent[0]["topic"] == "task.status"
    assert ws.sent[0]["data"]["payload"]["task_id"] == "JJC-1"


@pytest.mark.asyncio
async def test_handle_client_messages_recovers_after_bad_payload():
    ws = _DummyWebSocket(receive_events=[ValueError("bad payload"), {"type": "ping"}])

    with pytest.raises(WebSocketDisconnect):
        await _handle_client_messages(ws)

    assert ws.sent == [{"type": "pong"}]
