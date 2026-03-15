"""Sprint2 合同与状态机回归测试（轻量单测）。"""

from edict.backend.app.models.task import STATE_TRANSITIONS, TaskState
from edict.backend.app.services.output_normalizer import normalize_agent_output


def test_output_contract_contains_sprint2_fields():
    out = normalize_agent_output(
        task_id="JJC-TEST-001",
        agent="taizi",
        returncode=0,
        stdout="已完成分析，产出见 /tmp/result.md",
        stderr="",
        attempts=1,
        error_type="ok",
    )

    assert out["ok"] is True
    assert "summary" in out
    assert "output" in out
    assert "todo_detail" in out
    assert out["todo_detail"] == out["summary"]
    assert isinstance(out.get("artifacts"), list)
    assert isinstance(out.get("retry"), dict)
    assert out["retry"].get("attempts") == 1


def test_state_machine_contains_yulan_stage():
    assert TaskState.YuLan.value == "YuLan"
    assert TaskState.YuLan in STATE_TRANSITIONS[TaskState.Menxia]
    assert TaskState.Assigned in STATE_TRANSITIONS[TaskState.YuLan]
