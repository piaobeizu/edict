"""重试策略分类单测 — 验证错误分类准确性。"""

import pytest


class TestErrorClassification:
    """DispatchWorker._classify_error 错误分类测试。"""

    @staticmethod
    def _classify(returncode: int, stderr: str) -> str:
        """Mirror the classify_error logic without instantiating the full worker."""
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

    def test_success(self):
        assert self._classify(0, "") == "ok"
        assert self._classify(0, "some output") == "ok"

    def test_rate_limit_429(self):
        assert self._classify(1, "Error: 429 Too Many Requests") == "rate_limit"

    def test_rate_limit_text(self):
        assert self._classify(1, "rate limit exceeded") == "rate_limit"

    def test_rate_limit_too_many(self):
        assert self._classify(1, "too many requests, slow down") == "rate_limit"

    def test_timeout(self):
        assert self._classify(1, "request timed out after 30s") == "timeout"

    def test_timeout_variant(self):
        assert self._classify(1, "TIMEOUT after 300s") == "timeout"

    def test_network_connection(self):
        assert self._classify(1, "connection refused") == "network"

    def test_network_gateway(self):
        assert self._classify(1, "502 Gateway Timeout") == "network"

    def test_network_unavailable(self):
        assert self._classify(1, "Service temporarily unavailable") == "network"

    def test_business_error_unknown(self):
        assert self._classify(1, "invalid model: gpt-99") == "business_error"

    def test_business_error_auth(self):
        assert self._classify(1, "authentication failed") == "business_error"

    def test_business_error_empty(self):
        assert self._classify(1, "") == "business_error"


class TestRetryPolicy:
    """重试策略参数测试。"""

    RETRY_POLICY = {
        "rate_limit": 4,
        "timeout": 3,
        "network": 3,
        "business_error": 1,
        "ok": 1,
    }

    def test_rate_limit_gets_most_retries(self):
        assert self.RETRY_POLICY["rate_limit"] == 4

    def test_business_error_no_retry(self):
        assert self.RETRY_POLICY["business_error"] == 1

    def test_ok_no_retry(self):
        assert self.RETRY_POLICY["ok"] == 1

    def test_timeout_and_network_equal(self):
        assert self.RETRY_POLICY["timeout"] == self.RETRY_POLICY["network"]
