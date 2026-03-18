"""通用有限状态机 — 不绑定任何业务语义。

状态名、转换规则、终态集合全部由外部注入。
三省六部的具体状态图是业务层的事（见 adapters/edict_routing.py）。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


@dataclass(frozen=True)
class Transition:
    """一次状态转换的不可变记录。"""
    from_state: str
    to_state: str
    agent: str
    reason: str
    ts: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class StateMachineError(Exception):
    """状态机错误基类。"""


class InvalidTransitionError(StateMachineError):
    """非法转换。"""
    def __init__(self, current: str, target: str, allowed: set[str]):
        self.current = current
        self.target = target
        self.allowed = allowed
        super().__init__(
            f"Invalid transition: {current} → {target}. "
            f"Allowed: {sorted(allowed)}"
        )


class StateMachine:
    """通用有限状态机。

    不含任何业务语义——状态名和转换规则全部由构造参数注入。

    Args:
        transitions: {state: {allowed_next_states}}
        terminal_states: 终态集合（到达后不可再转换）
        initial_state: 默认初始状态

    Example:
        sm = StateMachine(
            transitions={"draft": {"review", "cancelled"}, "review": {"done", "draft"}},
            terminal_states={"done", "cancelled"},
            initial_state="draft",
        )
        sm.validate("draft", "review")  # OK
        sm.validate("done", "draft")    # raises InvalidTransitionError
    """

    def __init__(
        self,
        transitions: dict[str, set[str]],
        terminal_states: set[str],
        initial_state: str,
    ):
        self._transitions = {k: frozenset(v) for k, v in transitions.items()}
        self._terminal = frozenset(terminal_states)
        self._initial = initial_state

        # 健全性检查
        all_states = set(self._transitions.keys())
        for targets in self._transitions.values():
            all_states.update(targets)
        all_states.update(self._terminal)
        all_states.add(self._initial)
        self._all_states = frozenset(all_states)

    @property
    def initial_state(self) -> str:
        return self._initial

    @property
    def terminal_states(self) -> frozenset[str]:
        return self._terminal

    @property
    def all_states(self) -> frozenset[str]:
        return self._all_states

    def is_terminal(self, state: str) -> bool:
        return state in self._terminal

    def allowed_transitions(self, state: str) -> frozenset[str]:
        """返回从 state 可以转换到的合法目标集合。"""
        return self._transitions.get(state, frozenset())

    def validate(self, current: str, target: str) -> None:
        """校验转换是否合法。不合法则抛 InvalidTransitionError。"""
        if self.is_terminal(current):
            raise InvalidTransitionError(current, target, set())
        allowed = self.allowed_transitions(current)
        if target not in allowed:
            raise InvalidTransitionError(current, target, set(allowed))

    def transition(
        self,
        current: str,
        target: str,
        agent: str = "system",
        reason: str = "",
    ) -> Transition:
        """执行转换并返回 Transition 记录。非法则抛异常。"""
        self.validate(current, target)
        return Transition(
            from_state=current,
            to_state=target,
            agent=agent,
            reason=reason,
        )
