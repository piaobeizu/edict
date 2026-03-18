"""状态机全面单测 — 验证所有合法/非法流转路径。"""

import pytest
from app.models.task import (
    TaskState,
    STATE_TRANSITIONS,
    TERMINAL_STATES,
    STATE_AGENT_MAP,
    ORG_AGENT_MAP,
)


class TestStateTransitions:
    """状态流转白名单测试。"""

    def test_all_states_have_transitions_except_terminals(self):
        """所有非终态都应该有合法出口。"""
        for state in TaskState:
            if state in TERMINAL_STATES:
                continue
            assert state in STATE_TRANSITIONS, f"{state.value} missing from STATE_TRANSITIONS"
            assert len(STATE_TRANSITIONS[state]) > 0, f"{state.value} has empty transitions"

    def test_terminal_states_have_no_outgoing(self):
        """终态不应有出口。"""
        for state in TERMINAL_STATES:
            assert state not in STATE_TRANSITIONS or len(STATE_TRANSITIONS.get(state, set())) == 0

    def test_happy_path_forward(self):
        """正常路径：Pending → Taizi → Zhongshu → Menxia → YuLan → Assigned → Doing → Review → Done"""
        path = [
            TaskState.Pending, TaskState.Taizi, TaskState.Zhongshu,
            TaskState.Menxia, TaskState.YuLan, TaskState.Assigned,
            TaskState.Doing, TaskState.Review, TaskState.Done,
        ]
        for i in range(len(path) - 1):
            current, next_s = path[i], path[i + 1]
            assert next_s in STATE_TRANSITIONS.get(current, set()), \
                f"Transition {current.value} → {next_s.value} should be allowed"

    def test_menxia_reject_to_zhongshu(self):
        """门下封驳退回中书。"""
        assert TaskState.Zhongshu in STATE_TRANSITIONS[TaskState.Menxia]

    def test_review_reject_to_doing(self):
        """审查不通过退回执行。"""
        assert TaskState.Doing in STATE_TRANSITIONS[TaskState.Review]

    def test_blocked_can_resume_to_multiple_states(self):
        """Blocked 可以恢复到多个状态。"""
        blocked_targets = STATE_TRANSITIONS[TaskState.Blocked]
        assert TaskState.Taizi in blocked_targets
        assert TaskState.Doing in blocked_targets

    def test_cancellation_from_non_terminal(self):
        """所有非终态应都可取消（除 Blocked）。"""
        for state in TaskState:
            if state in TERMINAL_STATES or state == TaskState.Blocked:
                continue
            allowed = STATE_TRANSITIONS.get(state, set())
            assert TaskState.Cancelled in allowed, \
                f"{state.value} should allow cancellation"

    @pytest.mark.parametrize("illegal_transition", [
        (TaskState.Done, TaskState.Doing),
        (TaskState.Done, TaskState.Taizi),
        (TaskState.Cancelled, TaskState.Doing),
        (TaskState.Taizi, TaskState.Done),
        (TaskState.Taizi, TaskState.Doing),
        (TaskState.Pending, TaskState.Done),
        (TaskState.Zhongshu, TaskState.Doing),
        (TaskState.Review, TaskState.Taizi),
    ])
    def test_illegal_transitions_rejected(self, illegal_transition):
        """非法状态流转应被拒绝。"""
        from_state, to_state = illegal_transition
        allowed = STATE_TRANSITIONS.get(from_state, set())
        assert to_state not in allowed, \
            f"Transition {from_state.value} → {to_state.value} should NOT be allowed"


class TestStateAgentMap:
    """状态 → Agent 映射测试。"""

    def test_taizi_maps_to_taizi_agent(self):
        assert STATE_AGENT_MAP[TaskState.Taizi] == "taizi"

    def test_zhongshu_maps_to_zhongshu_agent(self):
        assert STATE_AGENT_MAP[TaskState.Zhongshu] == "zhongshu"

    def test_menxia_maps_to_menxia_agent(self):
        assert STATE_AGENT_MAP[TaskState.Menxia] == "menxia"

    def test_assigned_maps_to_shangshu_agent(self):
        assert STATE_AGENT_MAP[TaskState.Assigned] == "shangshu"

    def test_review_maps_to_shangshu_agent(self):
        assert STATE_AGENT_MAP[TaskState.Review] == "shangshu"

    def test_doing_defaults_to_shangshu(self):
        """Doing 默认由尚书省协调，可被 ORG_AGENT_MAP 覆盖。"""
        assert STATE_AGENT_MAP[TaskState.Doing] == "shangshu"

    def test_yulan_maps_to_shangshu(self):
        """YuLan 御览由尚书省汇总呈报。"""
        assert STATE_AGENT_MAP[TaskState.YuLan] == "shangshu"


class TestOrgAgentMap:
    """组织 → Agent 映射测试。"""

    def test_six_departments_all_mapped(self):
        expected = {"户部", "礼部", "兵部", "刑部", "工部", "吏部"}
        assert expected == set(ORG_AGENT_MAP.keys())

    def test_hubu_maps_correctly(self):
        assert ORG_AGENT_MAP["户部"] == "hubu"
