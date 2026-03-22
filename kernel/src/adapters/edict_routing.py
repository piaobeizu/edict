"""三省六部路由策略 — RoutingPolicy 的具体实现。

这是 Edict 业务层的核心：状态图 + Agent 映射。
换一套组织架构只需创建一个新的 RoutingPolicy 实现。
"""

from __future__ import annotations

from ..state_machine import StateMachine
from ..task_entity import TaskEntity

# ══════════════════════════════════════
# 状态定义
# ══════════════════════════════════════


class EdictState:
    """三省六部状态常量。"""

    TAIZI = "Taizi"  # 太子分拣
    ZHONGSHU = "Zhongshu"  # 中书省起草
    MENXIA = "Menxia"  # 门下省审议
    YULAN = "YuLan"  # 皇上御览
    ASSIGNED = "Assigned"  # 尚书省派发
    NEXT = "Next"  # 待执行
    DOING = "Doing"  # 六部执行
    REVIEW = "Review"  # 审查汇总
    DONE = "Done"  # 完成
    BLOCKED = "Blocked"  # 阻塞
    CANCELLED = "Cancelled"  # 取消
    PENDING = "Pending"  # 待处理


# ══════════════════════════════════════
# 状态机实例（注入 kernel）
# ══════════════════════════════════════

EDICT_TRANSITIONS: dict[str, set[str]] = {
    EdictState.PENDING: {EdictState.TAIZI, EdictState.CANCELLED},
    EdictState.TAIZI: {EdictState.ZHONGSHU, EdictState.CANCELLED},
    EdictState.ZHONGSHU: {EdictState.MENXIA, EdictState.CANCELLED, EdictState.BLOCKED},
    EdictState.MENXIA: {EdictState.YULAN, EdictState.ZHONGSHU, EdictState.CANCELLED},
    EdictState.YULAN: {
        EdictState.ASSIGNED,
        EdictState.ZHONGSHU,
        EdictState.CANCELLED,
        EdictState.BLOCKED,
    },
    EdictState.ASSIGNED: {
        EdictState.DOING,
        EdictState.NEXT,
        EdictState.CANCELLED,
        EdictState.BLOCKED,
    },
    EdictState.NEXT: {EdictState.DOING, EdictState.CANCELLED},
    EdictState.DOING: {
        EdictState.REVIEW,
        EdictState.DONE,
        EdictState.BLOCKED,
        EdictState.CANCELLED,
    },
    EdictState.REVIEW: {EdictState.DONE, EdictState.DOING, EdictState.CANCELLED},
    EdictState.BLOCKED: {
        EdictState.TAIZI,
        EdictState.ZHONGSHU,
        EdictState.MENXIA,
        EdictState.ASSIGNED,
        EdictState.DOING,
    },
}

EDICT_TERMINAL = {EdictState.DONE, EdictState.CANCELLED}


def create_edict_state_machine() -> StateMachine:
    """创建三省六部状态机实例。"""
    return StateMachine(
        transitions=EDICT_TRANSITIONS,
        terminal_states=EDICT_TERMINAL,
        initial_state=EdictState.TAIZI,
    )


# ══════════════════════════════════════
# Agent 映射
# ══════════════════════════════════════

# 状态 → Agent（流程阶段的固定映射）
STATE_AGENT_MAP: dict[str, str] = {
    EdictState.TAIZI: "taizi",
    EdictState.ZHONGSHU: "zhongshu",
    EdictState.MENXIA: "menxia",
    EdictState.ASSIGNED: "shangshu",
    EdictState.REVIEW: "shangshu",
}

# 部门 → Agent（六部执行阶段的映射）
ORG_AGENT_MAP: dict[str, str] = {
    "户部": "hubu",
    "礼部": "libu",
    "兵部": "bingbu",
    "刑部": "xingbu",
    "工部": "gongbu",
    "吏部": "libu_hr",
}

# 状态 → 完成后自动流转目标
STATE_COMPLETION_MAP: dict[str, str] = {
    EdictState.TAIZI: EdictState.ZHONGSHU,
    EdictState.ZHONGSHU: EdictState.MENXIA,
    EdictState.MENXIA: EdictState.YULAN,
    EdictState.YULAN: EdictState.ASSIGNED,
    EdictState.ASSIGNED: EdictState.DOING,
    EdictState.DOING: EdictState.REVIEW,
    EdictState.REVIEW: EdictState.DONE,
}


# ══════════════════════════════════════
# RoutingPolicy 实现
# ══════════════════════════════════════


class EdictRoutingPolicy:
    """三省六部路由策略。

    实现 kernel.ports.RoutingPolicy 接口。
    """

    def next_agent(self, task: TaskEntity) -> str | None:
        """根据当前状态决定下一个 agent。"""
        state = task.state

        # 流程阶段有固定 agent
        agent = STATE_AGENT_MAP.get(state)
        if agent:
            return agent

        # Doing 状态看 assignee（部门）
        if state == EdictState.DOING:
            return ORG_AGENT_MAP.get(task.assignee)

        return None

    def next_state_after_completion(self, task: TaskEntity) -> str | None:
        """Agent 完成后应该自动转到的状态。"""
        return STATE_COMPLETION_MAP.get(task.state)

    def suggest_assignee(self, task: TaskEntity) -> str:
        """建议的执行者。"""
        state = task.state
        if state == EdictState.TAIZI:
            return "太子"
        if state in (EdictState.ZHONGSHU, EdictState.MENXIA):
            return state
        if state == EdictState.ASSIGNED:
            return task.target_assignee or "尚书省"
        return task.assignee or ""
