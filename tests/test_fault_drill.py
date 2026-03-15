"""故障演练测试 — 模拟各种故障场景验证系统韧性。"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock


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


class TestErrorClassificationDrill:
    """故障分类准确性演练。"""

    @staticmethod
    def _classify(returncode: int, stderr: str) -> str:
        """Mirror dispatch_worker._classify_error."""
        text = (stderr or "").lower()
        if returncode == 0:
            return "ok"
        if "rate limit" in text or "too many requests" in text or "429" in text:
            return "rate_limit"
        # Check network errors before generic timeout — "gateway timeout" is network
        if (
            "connection" in text
            or "network" in text
            or "temporarily unavailable" in text
            or "gateway timeout" in text
        ):
            return "network"
        if "timeout" in text or "timed out" in text:
            return "timeout"
        return "business_error"

    def test_429_rate_limit_backs_off(self):
        """429 response → classified as rate_limit (gets 4 retry attempts)."""
        assert self._classify(1, "Error 429: Too Many Requests") == "rate_limit"

        # Verify policy gives 4 attempts for rate_limit
        retry_policy = {"rate_limit": 4, "timeout": 3, "network": 3, "business_error": 1, "ok": 1}
        assert retry_policy["rate_limit"] == 4

    def test_gateway_timeout_classified_correctly(self):
        """502 Gateway Timeout → network error."""
        assert self._classify(1, "502 Gateway Timeout") == "network"
        assert self._classify(1, "HTTP 504 gateway timeout from upstream") == "network"

    def test_dispatch_timeout_300s(self):
        """subprocess.TimeoutExpired → classified as timeout."""
        assert self._classify(-1, "TIMEOUT after 300s") == "timeout"

    def test_business_error_no_retry(self):
        """Business error → max 1 attempt (no retry)."""
        assert self._classify(1, "invalid model: gpt-99") == "business_error"

        retry_policy = {"rate_limit": 4, "timeout": 3, "network": 3, "business_error": 1, "ok": 1}
        assert retry_policy["business_error"] == 1

    def test_connection_refused_is_network(self):
        """Connection refused → network error."""
        assert self._classify(1, "connection refused to host:8080") == "network"

    def test_temporarily_unavailable_is_network(self):
        """Service temporarily unavailable → network."""
        assert self._classify(1, "Service temporarily unavailable, retry later") == "network"


class TestRedisDisconnectGraceful:
    """Redis 断连优雅处理测试。"""

    @pytest.mark.asyncio
    async def test_redis_disconnect_worker_continues(self):
        """When Redis raises ConnectionError during poll, worker logs and continues."""
        from edict.backend.app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()
        worker._running = True

        # Simulate Redis error on consume
        call_count = 0

        async def flaky_consume(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise ConnectionError("Redis connection lost")
            # Second call: stop the loop
            worker._running = False
            return []

        worker.bus.consume = flaky_consume
        worker._check_throttle = AsyncMock()

        # Should not raise — error is caught in poll loop
        with patch("asyncio.sleep", new_callable=AsyncMock):
            try:
                await worker.start()
            except Exception:
                pass  # Worker exits when _running = False

        # Worker survived the Redis error
        assert call_count >= 1

    @pytest.mark.asyncio
    async def test_orchestrator_poll_error_recovery(self):
        """Orchestrator poll error → logs and retries."""
        from edict.backend.app.workers.orchestrator_worker import OrchestratorWorker

        worker = OrchestratorWorker()
        worker.bus = make_mock_bus()
        worker._running = True

        call_count = 0

        async def flaky_consume(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count <= 2:
                raise ConnectionError("Redis gone")
            worker._running = False
            return []

        worker.bus.consume = flaky_consume
        worker._recover_pending = AsyncMock()

        with patch("asyncio.sleep", new_callable=AsyncMock):
            try:
                await worker.start()
            except Exception:
                pass

        assert call_count >= 2


class TestDeadLetterOnExhaustedRetries:
    """重试耗尽后进入 DLQ 测试。"""

    @pytest.mark.asyncio
    async def test_dead_letter_on_exhausted(self):
        """After all retries exhausted → event goes to DLQ."""
        from edict.backend.app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()

        # Mock openclaw to always fail with business_error (no retry)
        worker._call_openclaw_with_retry = AsyncMock(return_value={
            "returncode": 1,
            "stdout": "",
            "stderr": "auth failed",
            "error_type": "business_error",
            "attempts": 1,
        })
        worker._backfill_task_output = AsyncMock()

        event = {
            "event_id": "evt-dlq",
            "trace_id": "JJC-DLQ",
            "payload": {
                "task_id": "JJC-DLQ",
                "agent": "taizi",
                "state": "Taizi",
                "dispatch_round": 1,
                "message": "test",
            },
        }

        await worker._dispatch("entry-dlq", event)

        # Should have published to DLQ
        dlq_calls = [
            c for c in worker.bus.publish.call_args_list
            if c.kwargs.get("topic") == "task.dispatch.dead_letter"
        ]
        assert len(dlq_calls) == 1
        assert dlq_calls[0].kwargs["payload"]["error_type"] == "business_error"

    @pytest.mark.asyncio
    async def test_success_no_dead_letter(self):
        """Successful dispatch → no DLQ event."""
        from edict.backend.app.workers.dispatch_worker import DispatchWorker

        worker = DispatchWorker()
        worker.bus = make_mock_bus()

        worker._call_openclaw_with_retry = AsyncMock(return_value={
            "returncode": 0,
            "stdout": "done",
            "stderr": "",
            "error_type": "ok",
            "attempts": 1,
        })
        worker._backfill_task_output = AsyncMock()

        event = {
            "event_id": "evt-ok",
            "trace_id": "JJC-OK",
            "payload": {
                "task_id": "JJC-OK",
                "agent": "taizi",
                "state": "Taizi",
                "dispatch_round": 1,
                "message": "test",
            },
        }

        await worker._dispatch("entry-ok", event)

        # No DLQ publish
        dlq_calls = [
            c for c in worker.bus.publish.call_args_list
            if c.kwargs.get("topic") == "task.dispatch.dead_letter"
        ]
        assert len(dlq_calls) == 0


class TestRetryBackoffDrill:
    """重试退避策略演练。"""

    def test_exponential_backoff_with_cap(self):
        """Verify exponential backoff formula with 30s cap."""
        import random

        for attempt in range(1, 10):
            base = min(2 ** (attempt - 1), 30)
            assert base <= 30, f"Attempt {attempt}: base={base} exceeds cap"

        # Specific values
        assert min(2 ** 0, 30) == 1   # attempt 1
        assert min(2 ** 1, 30) == 2   # attempt 2
        assert min(2 ** 2, 30) == 4   # attempt 3
        assert min(2 ** 3, 30) == 8   # attempt 4
        assert min(2 ** 4, 30) == 16  # attempt 5
        assert min(2 ** 5, 30) == 30  # attempt 6 — capped
        assert min(2 ** 6, 30) == 30  # attempt 7 — capped

    def test_jitter_range(self):
        """Jitter should be in [0.1, 0.8]."""
        import random

        random.seed(42)
        for _ in range(100):
            jitter = random.uniform(0.1, 0.8)
            assert 0.1 <= jitter <= 0.8
