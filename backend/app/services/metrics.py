"""轻量级内存 Metrics 收集器。"""

from __future__ import annotations

from collections import defaultdict


class MetricsCollector:
    """提供 counter / histogram / gauge 的简单聚合。"""

    def __init__(self):
        self._counters: dict[str, float] = defaultdict(float)
        self._hist_count: dict[str, int] = defaultdict(int)
        self._hist_sum: dict[str, float] = defaultdict(float)
        self._gauges: dict[str, float] = {}

    @staticmethod
    def _key(name: str, labels: dict | None = None) -> str:
        if not labels:
            return name
        parts = [f"{k}={labels[k]}" for k in sorted(labels.keys())]
        return f"{name}|" + ",".join(parts)

    def inc(self, name: str, value: float = 1, labels: dict | None = None):
        key = self._key(name, labels)
        self._counters[key] += value

    def observe(self, name: str, value: float, labels: dict | None = None):
        key = self._key(name, labels)
        self._hist_count[key] += 1
        self._hist_sum[key] += value

    def set_gauge(self, name: str, value: float, labels: dict | None = None):
        key = self._key(name, labels)
        self._gauges[key] = value

    def snapshot(self) -> dict:
        return {
            "counters": dict(self._counters),
            "histograms": {
                key: {
                    "count": self._hist_count[key],
                    "sum": self._hist_sum[key],
                }
                for key in set(self._hist_count.keys()) | set(self._hist_sum.keys())
            },
            "gauges": dict(self._gauges),
        }

    def reset(self):
        self._counters.clear()
        self._hist_count.clear()
        self._hist_sum.clear()
        self._gauges.clear()


# ── 全局单例 ──
_metrics: MetricsCollector | None = None


def get_metrics() -> MetricsCollector:
    global _metrics
    if _metrics is None:
        _metrics = MetricsCollector()
    return _metrics
