"""并发冲突测试 — 验证幂等和状态机在并发下的正确性。"""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, PropertyMock


def make_mock_bus():
    bus = MagicMock()
    bus.connect = AsyncMock()
    bus.close = AsyncMock()
    bus.publish = AsyncMock(return_value="entry-001")
    bus.consume = AsyncMock(return_value=[])
    bus.ack = AsyncMock()
    bus.ensure_consumer_group = AsyncMock()
    bus.claim_stale = AsyncMock(return_value=[])
    mock_redis = AsyncMock()
    mock_redis.set = AsyncMock(return_value=True)
    mock_redis.ping = AsyncMock(return_value=True)
    type(bus).redis = PropertyMock(return_value=mock_redis)
    return bus


class TestConcurrentDispatchIdempotency:
    """并发派发幂等测试。"""

    @pytest.mark.asyncio
    async def test_concurrent_dispatch_only_one_runs(self):
        """5 concurrent dispatches for same task+agent+round → only 1 executes openclaw."""
        from app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()

        # Track how many times _call_openclaw_with_retry is called
        call_count = 0

        async def mock_openclaw(**kwargs):
            nonlocal call_count
            call_count += 1
            await asyncio.sleep(0.01)  # Simulate brief work
            return {"returncode": 0, "stdout": "ok", "stderr": "", "error_type": "ok", "attempts": 1}

        worker._call_openclaw_with_retry = mock_openclaw
        worker._backfill_task_output = AsyncMock()

        # First call succeeds SETNX, rest fail
        call_idx = 0

        async def mock_setnx(key, value, ex=None, nx=None):
            nonlocal call_idx
            call_idx += 1
            if call_idx == 1:
                return True  # First one wins
            return None  # Others lose

        worker.bus.redis.set = mock_setnx

        event = {
            "event_id": "evt-concurrent",
            "trace_id": "JJC-CONC",
            "payload": {
                "task_id": "JJC-CONC",
                "agent": "taizi",
                "state": "Taizi",
                "dispatch_round": 1,
                "message": "test",
            },
        }

        # Run 5 concurrent dispatches
        tasks = [worker._dispatch(f"entry-{i}", event) for i in range(5)]
        await asyncio.gather(*tasks)

        # Only 1 should have actually called openclaw
        assert call_count == 1


class TestConcurrentEventDedup:
    """并发事件去重测试。"""

    @pytest.mark.asyncio
    async def test_event_dedup_concurrent(self):
        """Multiple identical events → mark_event_once returns True only for the first."""
        from app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()

        # Track how many times _on_task_created is actually called
        call_count = 0
        original_on_created = worker._on_task_created

        async def tracked_on_created(payload, trace_id):
            nonlocal call_count
            call_count += 1

        worker._on_task_created = tracked_on_created

        # Simulate SETNX: only first call returns True
        setnx_count = 0

        async def mock_setnx(key, value, ex=None, nx=None):
            nonlocal setnx_count
            setnx_count += 1
            return True if setnx_count == 1 else None

        worker.bus.redis.set = mock_setnx

        event = {
            "event_id": "evt-dedup-001",
            "trace_id": "JJC-DEDUP",
            "topic": "task.created",
            "event_type": "task.created",
            "payload": {"task_id": "JJC-DEDUP", "state": "Taizi", "title": "Test"},
        }

        # Process the same event 3 times
        for i in range(3):
            await worker._handle_event("task.created", f"entry-{i}", event)

        # Only 1 should have reached _on_task_created
        assert call_count == 1


class TestConcurrentStateTransitions:
    """并发状态流转竞争测试。"""

    @pytest.mark.asyncio
    async def test_concurrent_transitions_only_one_succeeds(self):
        """Two concurrent transitions from same state → at most one succeeds."""
        from app.services.task_service import TaskService
        from app.models.task import TaskState

        # Create a mock task
        mock_task = MagicMock()
        mock_task.state = TaskState.Taizi
        mock_task.trace_id = "JJC-RACE"
        mock_task.flow_log = []
        mock_task.updated_at = None
        mock_task.workflow_type = "legacy"

        call_count = 0

        mock_db = AsyncMock()

        def make_mock_result(task_obj):
            mock_scalars = MagicMock()
            mock_scalars.first = MagicMock(return_value=task_obj)
            mock_result = MagicMock()
            mock_result.scalars = MagicMock(return_value=mock_scalars)
            return mock_result

        call_count = 0

        async def mock_execute(stmt):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return make_mock_result(mock_task)
            # Second call: state already changed
            mock_task2 = MagicMock()
            mock_task2.state = TaskState.Zhongshu  # Already transitioned
            mock_task2.trace_id = "JJC-RACE"
            mock_task2.flow_log = []
            mock_task2.workflow_type = "legacy"
            return make_mock_result(mock_task2)

        mock_db.execute = mock_execute
        mock_db.commit = AsyncMock()

        mock_bus = make_mock_bus()

        svc = TaskService(db=mock_db, event_bus=mock_bus)

        # First transition should succeed
        result = await svc.transition_state("JJC-RACE", TaskState.Zhongshu)
        assert result.state == TaskState.Zhongshu.value

        # Second transition from Zhongshu→Zhongshu (same target) should fail
        # because Zhongshu→Zhongshu is not allowed
        with pytest.raises(ValueError, match="Invalid transition"):
            await svc.transition_state("JJC-RACE", TaskState.Zhongshu)
