"""集成测试 — 用 mock 验证 worker + service 协作逻辑。"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock
from datetime import datetime, timezone


# ── Helper: build a mock EventBus ──

def make_mock_bus():
    """Create a mock EventBus with all needed async methods."""
    bus = MagicMock()
    bus.connect = AsyncMock()
    bus.close = AsyncMock()
    bus.publish = AsyncMock(return_value="entry-001")
    bus.consume = AsyncMock(return_value=[])
    bus.ack = AsyncMock()
    bus.ensure_consumer_group = AsyncMock()
    bus.claim_stale = AsyncMock(return_value=[])

    # Mock Redis for idempotency
    mock_redis = AsyncMock()
    mock_redis.set = AsyncMock(return_value=True)  # SETNX succeeds by default
    mock_redis.ping = AsyncMock(return_value=True)
    type(bus).redis = PropertyMock(return_value=mock_redis)

    return bus


def make_event(topic, event_type, task_id, payload_extra=None, trace_id=None):
    """Create a mock event dict."""
    payload = {"task_id": task_id, **(payload_extra or {})}
    return {
        "event_id": f"evt-{task_id}-{event_type}",
        "trace_id": trace_id or task_id,
        "topic": topic,
        "event_type": event_type,
        "producer": "test",
        "payload": payload,
        "meta": {},
    }


# ── Orchestrator Tests ──

class TestOrchestratorDispatches:
    """Orchestrator 事件驱动派发测试。"""

    @pytest.mark.asyncio
    async def test_dispatches_on_task_created(self):
        """task.created → should publish task.dispatch."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        event = make_event("task.created", "task.created", "JJC-001", {
            "title": "测试任务",
            "state": "Taizi",
        })

        await worker._handle_event("task.created", "entry-1", event)

        # Should have published a dispatch event
        worker.bus.publish.assert_called()
        call_args = worker.bus.publish.call_args
        assert call_args.kwargs["topic"] == "task.dispatch"
        assert call_args.kwargs["payload"]["agent"] == "taizi"
        assert call_args.kwargs["payload"]["task_id"] == "JJC-001"

    @pytest.mark.asyncio
    async def test_rejects_illegal_transition(self):
        """Illegal state transition → publishes escalated event, no dispatch."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        event = make_event("task.status", "task.state.Done", "JJC-002", {
            "from": "Taizi",
            "to": "Done",  # Illegal: Taizi → Done
        })

        await worker._handle_event("task.status", "entry-2", event)

        # Should have published an escalated event for illegal transition
        calls = worker.bus.publish.call_args_list
        assert len(calls) >= 1
        escalated_call = calls[0]
        assert escalated_call.kwargs["topic"] == "task.escalated"
        assert escalated_call.kwargs["event_type"] == "task.state.illegal_transition"

    @pytest.mark.asyncio
    async def test_status_dispatches_next_agent(self):
        """Valid transition to Zhongshu → dispatches zhongshu agent."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        event = make_event("task.status", "task.state.Zhongshu", "JJC-003", {
            "from": "Taizi",
            "to": "Zhongshu",
        })

        await worker._handle_event("task.status", "entry-3", event)

        worker.bus.publish.assert_called()
        call_args = worker.bus.publish.call_args
        assert call_args.kwargs["topic"] == "task.dispatch"
        assert call_args.kwargs["payload"]["agent"] == "zhongshu"

    @pytest.mark.asyncio
    async def test_event_dedup_skips_duplicate(self):
        """Duplicate event_id → _mark_event_once returns False, event skipped."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        # First call: SETNX succeeds
        worker.bus.redis.set = AsyncMock(return_value=True)
        event = make_event("task.created", "task.created", "JJC-004", {"state": "Taizi", "title": "Test"})
        await worker._handle_event("task.created", "entry-4a", event)
        assert worker.bus.publish.called

        # Reset and second call: SETNX fails (duplicate)
        worker.bus.publish.reset_mock()
        worker.bus.redis.set = AsyncMock(return_value=None)
        await worker._handle_event("task.created", "entry-4b", event)

        # Should NOT have published (event was deduplicated)
        worker.bus.publish.assert_not_called()


class TestOrchestratorStallRecovery:
    """Orchestrator 停滞恢复逻辑测试。"""

    @pytest.mark.asyncio
    async def test_stall_recovery_under_threshold(self):
        """stall_count < 3 → re-dispatch with cleared idem keys."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        # Mock scan_iter for idem key cleanup
        async def mock_scan_iter(pattern):
            for key in ["edict:dispatch:idem:JJC-005:taizi:1"]:
                yield key

        worker.bus.redis.scan_iter = mock_scan_iter
        worker.bus.redis.delete = AsyncMock()

        # Mock DB to return a task in Taizi state
        mock_task = MagicMock()
        mock_task.state = "Taizi"
        mock_task.org = "太子"

        mock_db = AsyncMock()
        mock_db.get = AsyncMock(return_value=mock_task)
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=False)

        with patch("app.workers.orchestrator_worker.async_session", return_value=mock_db):
            event = make_event("task.stalled", "task.stalled", "JJC-005", {
                "stall_count": 1,
            })
            await worker._handle_event("task.stalled", "entry-5", event)

        # Should have published a dispatch for stall recovery
        dispatch_calls = [
            c for c in worker.bus.publish.call_args_list
            if c.kwargs.get("topic") == "task.dispatch"
        ]
        assert len(dispatch_calls) >= 1

    @pytest.mark.asyncio
    async def test_stall_auto_blocks_at_5(self):
        """stall_count >= 5 → marks task Blocked in DB."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        mock_task = MagicMock()
        mock_task.state = "Taizi"
        mock_task.flow_log = []

        mock_db = AsyncMock()
        mock_db.get = AsyncMock(return_value=mock_task)
        mock_db.commit = AsyncMock()
        mock_db.__aenter__ = AsyncMock(return_value=mock_db)
        mock_db.__aexit__ = AsyncMock(return_value=False)

        with patch("app.workers.orchestrator_worker.async_session", return_value=mock_db):
            event = make_event("task.stalled", "task.stalled", "JJC-006", {
                "stall_count": 5,
            })
            await worker._handle_event("task.stalled", "entry-6", event)

        # Task should be marked Blocked
        assert mock_task.state == "Blocked"
        assert mock_db.commit.called


# ── Dispatch Worker Tests ──

class TestDispatchWorkerIdempotency:
    """Dispatch Worker 幂等与去重测试。"""

    @pytest.mark.asyncio
    async def test_duplicate_dispatch_skipped(self):
        """Second dispatch with same task+agent+round is skipped."""
        from app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()

        # SETNX fails (already dispatched)
        worker.bus.redis.set = AsyncMock(return_value=None)

        event = make_event("task.dispatch", "task.dispatch.request", "JJC-007", {
            "agent": "taizi",
            "state": "Taizi",
            "dispatch_round": 1,
            "message": "test",
        })

        await worker._dispatch("entry-7", event)

        # Should have ACKed (duplicate) but not published anything except the skip
        worker.bus.ack.assert_called_once()

    @pytest.mark.asyncio
    async def test_publishes_dead_letter_on_failure(self):
        """Non-zero returncode → DLQ event published."""
        from app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()

        # Mock _call_openclaw_with_retry to return failure
        worker._call_openclaw_with_retry = AsyncMock(return_value={
            "returncode": 1,
            "stdout": "",
            "stderr": "authentication failed",
            "error_type": "business_error",
            "attempts": 1,
        })

        # Mock _backfill_task_output
        worker._backfill_task_output = AsyncMock()

        event = make_event("task.dispatch", "task.dispatch.request", "JJC-008", {
            "agent": "zhongshu",
            "state": "Zhongshu",
            "dispatch_round": 1,
            "message": "test",
        })

        await worker._dispatch("entry-8", event)

        # Find the DLQ publish call
        dlq_calls = [
            c for c in worker.bus.publish.call_args_list
            if c.kwargs.get("topic") == "task.dispatch.dead_letter"
        ]
        assert len(dlq_calls) == 1
        assert dlq_calls[0].kwargs["payload"]["task_id"] == "JJC-008"
        assert dlq_calls[0].kwargs["payload"]["error_type"] == "business_error"


class TestTaskServiceTransition:
    """TaskService 状态流转校验测试。"""

    @staticmethod
    def _mock_db_for_transition(mock_task):
        """Create a mock db that supports both .get() and .execute() with scalars().first()."""
        mock_scalars = MagicMock()
        mock_scalars.first = MagicMock(return_value=mock_task)
        mock_result = MagicMock()
        mock_result.scalars = MagicMock(return_value=mock_scalars)
        mock_db = AsyncMock()
        mock_db.execute = AsyncMock(return_value=mock_result)
        mock_db.get = AsyncMock(return_value=mock_task)
        mock_db.commit = AsyncMock()
        return mock_db

    @pytest.mark.asyncio
    async def test_rejects_invalid_transition(self):
        """Invalid state transition → raises ValueError."""
        from app.services.task_service import TaskService
        from app.models.task import TaskState

        mock_task = MagicMock()
        mock_task.state = TaskState.Taizi
        mock_task.trace_id = "JJC-009"
        mock_task.flow_log = []
        mock_task.workflow_type = "legacy"

        mock_db = self._mock_db_for_transition(mock_task)

        mock_bus = make_mock_bus()
        svc = TaskService(db=mock_db, event_bus=mock_bus)

        with pytest.raises(ValueError, match="Invalid transition"):
            await svc.transition_state("JJC-009", TaskState.Done)

    @pytest.mark.asyncio
    async def test_allows_valid_transition(self):
        """Valid state transition → succeeds, publishes event."""
        from app.services.task_service import TaskService
        from app.models.task import TaskState

        mock_task = MagicMock()
        mock_task.state = TaskState.Taizi
        mock_task.trace_id = "JJC-010"
        mock_task.flow_log = []
        mock_task.updated_at = None
        mock_task.workflow_type = "legacy"

        mock_db = self._mock_db_for_transition(mock_task)

        mock_bus = make_mock_bus()
        svc = TaskService(db=mock_db, event_bus=mock_bus)

        result = await svc.transition_state("JJC-010", TaskState.Zhongshu, agent="taizi")
        assert result.state == TaskState.Zhongshu.value
        mock_bus.publish.assert_called_once()
