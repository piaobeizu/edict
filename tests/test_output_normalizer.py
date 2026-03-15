"""输出归一化器全面单测。"""

import pytest
from edict.backend.app.services.output_normalizer import normalize_agent_output


class TestNormalizeAgentOutput:
    """normalize_agent_output 测试。"""

    def test_success_output(self):
        out = normalize_agent_output(
            task_id="JJC-001",
            agent="taizi",
            returncode=0,
            stdout="分析完成，结果已写入 /tmp/result.md",
            stderr="",
        )
        assert out["ok"] is True
        assert out["task_id"] == "JJC-001"
        assert out["agent"] == "taizi"
        assert out["return_code"] == 0
        assert "summary" in out
        assert len(out["summary"]) > 0

    def test_failure_output(self):
        out = normalize_agent_output(
            task_id="JJC-002",
            agent="zhongshu",
            returncode=1,
            stdout="",
            stderr="rate limit exceeded",
            attempts=3,
            error_type="rate_limit",
        )
        assert out["ok"] is False
        assert out["retry"]["attempts"] == 3
        assert out["retry"]["error_type"] == "rate_limit"
        assert out["retry"]["exhausted"] is True

    def test_artifacts_extraction(self):
        out = normalize_agent_output(
            task_id="JJC-003",
            agent="gongbu",
            returncode=0,
            stdout="已生成报告 /data/reports/weekly.md 和 /data/exports/data.json",
            stderr="",
        )
        paths = [a["path"] for a in out["artifacts"]]
        assert "/data/reports/weekly.md" in paths
        assert "/data/exports/data.json" in paths

    def test_artifact_kind_detection(self):
        out = normalize_agent_output(
            task_id="JJC-004",
            agent="hubu",
            returncode=0,
            stdout="Files: /a.md /b.json /c.log /d.txt",
            stderr="",
        )
        kinds = {a["path"]: a["kind"] for a in out["artifacts"]}
        assert kinds.get("/a.md") == "markdown"
        assert kinds.get("/b.json") == "json"
        assert kinds.get("/c.log") == "log"
        assert kinds.get("/d.txt") == "file"

    def test_api_paths_excluded_from_artifacts(self):
        out = normalize_agent_output(
            task_id="JJC-005",
            agent="taizi",
            returncode=0,
            stdout="Calling /api/tasks/list and /api/events",
            stderr="",
        )
        paths = [a["path"] for a in out["artifacts"]]
        assert not any(p.startswith("/api/") for p in paths)

    def test_empty_output_fallback(self):
        out = normalize_agent_output(
            task_id="JJC-006",
            agent="taizi",
            returncode=0,
            stdout="",
            stderr="",
        )
        assert out["summary"] == "无输出"
        assert out["output"] == ""

    def test_long_output_truncated(self):
        long_text = "A" * 20000
        out = normalize_agent_output(
            task_id="JJC-007",
            agent="taizi",
            returncode=0,
            stdout=long_text,
            stderr="",
        )
        assert len(out["output"]) < 10000
        assert "truncated" in out["output"]

    def test_stderr_as_body_when_no_stdout(self):
        out = normalize_agent_output(
            task_id="JJC-008",
            agent="taizi",
            returncode=1,
            stdout="",
            stderr="Error: something went wrong",
        )
        assert "something went wrong" in out["output"]

    def test_single_retry_not_exhausted(self):
        out = normalize_agent_output(
            task_id="JJC-009",
            agent="taizi",
            returncode=1,
            stdout="",
            stderr="failed",
            attempts=1,
            error_type="network",
        )
        assert out["retry"]["exhausted"] is False

    def test_todo_detail_equals_summary(self):
        out = normalize_agent_output(
            task_id="JJC-010",
            agent="taizi",
            returncode=0,
            stdout="分析完成",
            stderr="",
        )
        assert out["todo_detail"] == out["summary"]
