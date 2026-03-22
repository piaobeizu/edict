"""Kernel 单元测试 — 纯逻辑，不需要 DB/Redis/外部依赖。"""

import pytest
from datetime import datetime, timezone

from kernel.state_machine import StateMachine, InvalidTransitionError, Transition
from kernel.task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
from kernel.ports import ExecutionResult


# ══════════════════════════════════════
# StateMachine Tests
# ══════════════════════════════════════

@pytest.fixture
def simple_sm():
    """最小状态机：draft → review → done/cancelled。"""
    return StateMachine(
        transitions={
            "draft": {"review", "cancelled"},
            "review": {"done", "draft"},
        },
        terminal_states={"done", "cancelled"},
        initial_state="draft",
    )


@pytest.fixture
def edict_sm():
    """三省六部状态机。"""
    from kernel.adapters.edict_routing import create_edict_state_machine
    return create_edict_state_machine()


class TestStateMachine:
    def test_initial_state(self, simple_sm):
        assert simple_sm.initial_state == "draft"

    def test_all_states(self, simple_sm):
        assert simple_sm.all_states == frozenset({"draft", "review", "done", "cancelled"})

    def test_terminal(self, simple_sm):
        assert simple_sm.is_terminal("done")
        assert simple_sm.is_terminal("cancelled")
        assert not simple_sm.is_terminal("draft")

    def test_allowed_transitions(self, simple_sm):
        assert simple_sm.allowed_transitions("draft") == frozenset({"review", "cancelled"})
        assert simple_sm.allowed_transitions("review") == frozenset({"done", "draft"})
        assert simple_sm.allowed_transitions("done") == frozenset()

    def test_validate_ok(self, simple_sm):
        simple_sm.validate("draft", "review")  # should not raise

    def test_validate_bad(self, simple_sm):
        with pytest.raises(InvalidTransitionError) as exc_info:
            simple_sm.validate("draft", "done")
        assert exc_info.value.current == "draft"
        assert exc_info.value.target == "done"
        assert "review" in exc_info.value.allowed

    def test_validate_from_terminal(self, simple_sm):
        with pytest.raises(InvalidTransitionError):
            simple_sm.validate("done", "draft")

    def test_transition_returns_record(self, simple_sm):
        t = simple_sm.transition("draft", "review", agent="user", reason="ready")
        assert isinstance(t, Transition)
        assert t.from_state == "draft"
        assert t.to_state == "review"
        assert t.agent == "user"

    def test_edict_full_happy_path(self, edict_sm):
        """三省六部完整流转路径。"""
        path = ["Taizi", "Zhongshu", "Menxia", "YuLan", "Assigned", "Doing", "Review", "Done"]
        state = edict_sm.initial_state
        assert state == "Taizi"
        for target in path[1:]:
            edict_sm.validate(state, target)
            state = target
        assert edict_sm.is_terminal(state)

    def test_edict_reject_path(self, edict_sm):
        """门下省封驳退回中书省。"""
        edict_sm.validate("Menxia", "Zhongshu")

    def test_edict_blocked_recovery(self, edict_sm):
        """Blocked 可恢复到多个状态。"""
        allowed = edict_sm.allowed_transitions("Blocked")
        assert "Taizi" in allowed
        assert "Doing" in allowed

    def test_edict_invalid_skip(self, edict_sm):
        """不能跳过中书直接到门下。"""
        with pytest.raises(InvalidTransitionError):
            edict_sm.validate("Taizi", "Menxia")


# ══════════════════════════════════════
# TaskEntity Tests
# ══════════════════════════════════════

class TestTaskEntity:
    def test_create(self):
        t = TaskEntity(id="T-001", title="Test", state="draft")
        assert t.id == "T-001"
        assert t.flow_log == []
        assert t.todos == []

    def test_append_flow(self):
        t = TaskEntity(id="T-001", title="Test", state="draft")
        e = FlowEntry(from_state="draft", to_state="review", agent="user", reason="ready")
        t.append_flow(e)
        assert len(t.flow_log) == 1
        assert t.flow_log[0].to_state == "review"

    def test_to_dict(self):
        t = TaskEntity(id="T-001", title="Test", state="draft", priority="high")
        d = t.to_dict()
        assert d["id"] == "T-001"
        assert d["state"] == "draft"
        assert d["priority"] == "high"
        assert isinstance(d["flow_log"], list)

    def test_todo_item(self):
        td = TodoItem(id=1, title="Step 1", status="in-progress")
        assert td.to_dict() == {"id": 1, "title": "Step 1", "status": "in-progress", "detail": ""}


# ══════════════════════════════════════
# ExecutionResult Tests
# ══════════════════════════════════════

class TestExecutionResult:
    def test_success(self):
        r = ExecutionResult(success=True, output="done", duration_ms=1500)
        assert r.success
        d = r.to_dict()
        assert d["output"] == "done"

    def test_failure(self):
        r = ExecutionResult(success=False, error="timeout")
        assert not r.success
        assert r.error == "timeout"


# ══════════════════════════════════════
# EdictRoutingPolicy Tests
# ══════════════════════════════════════

class TestEdictRouting:
    def test_next_agent_taizi(self):
        from kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Taizi")
        assert policy.next_agent(task) == "taizi"

    def test_next_agent_doing(self):
        from kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Doing", assignee="户部")
        assert policy.next_agent(task) == "hubu"

    def test_next_agent_doing_unknown_dept(self):
        from kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Doing", assignee="未知部")
        assert policy.next_agent(task) is None

    def test_next_state_after_completion(self):
        from kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Zhongshu")
        assert policy.next_state_after_completion(task) == "Menxia"

    def test_no_next_for_done(self):
        from kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Done")
        assert policy.next_state_after_completion(task) is None
