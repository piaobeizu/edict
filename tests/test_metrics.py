"""Metrics 服务单测。"""

from app.services.metrics import MetricsCollector


class TestMetricsCollector:
    def test_counter_increment(self):
        m = MetricsCollector()
        m.inc("dispatch_total")
        snap = m.snapshot()
        assert snap["counters"]["dispatch_total"] == 1

    def test_counter_with_labels(self):
        m = MetricsCollector()
        m.inc("dispatch_total", labels={"agent": "taizi"})
        m.inc("dispatch_total", labels={"agent": "zhongshu"})
        m.inc("dispatch_total", labels={"agent": "taizi"})
        snap = m.snapshot()
        assert snap["counters"]["dispatch_total|agent=taizi"] == 2
        assert snap["counters"]["dispatch_total|agent=zhongshu"] == 1

    def test_observe_latency(self):
        m = MetricsCollector()
        m.observe("dispatch_latency", 1.2)
        m.observe("dispatch_latency", 0.8)
        hist = m.snapshot()["histograms"]["dispatch_latency"]
        assert hist["count"] == 2
        assert hist["sum"] == 2.0

    def test_snapshot_structure(self):
        m = MetricsCollector()
        m.inc("a")
        m.observe("b", 1.0)
        m.set_gauge("c", 3)
        snap = m.snapshot()
        assert set(snap.keys()) == {"counters", "histograms", "gauges"}
        assert isinstance(snap["counters"], dict)
        assert isinstance(snap["histograms"], dict)
        assert isinstance(snap["gauges"], dict)

    def test_reset(self):
        m = MetricsCollector()
        m.inc("a")
        m.observe("b", 2.0)
        m.set_gauge("c", 1)
        m.reset()
        snap = m.snapshot()
        assert snap["counters"] == {}
        assert snap["histograms"] == {}
        assert snap["gauges"] == {}

    def test_gauge_set(self):
        m = MetricsCollector()
        m.set_gauge("queue_depth", 7)
        m.set_gauge("queue_depth", 9)
        snap = m.snapshot()
        assert snap["gauges"]["queue_depth"] == 9
