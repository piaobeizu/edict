"""Workflow v2 command constants, permission guards, and policy violations."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from kernel.graph_entities import NodeEntity, WorkflowSnapshot

# ══════════════════════════════════════
# Topic & command event-type constants
# ══════════════════════════════════════

TOPIC_WORKFLOW_COMMAND = "workflow.v2.command"

EVENT_START_PLANNING = "workflow.v2.command.start_planning"
EVENT_SUBMIT_PLAN = "workflow.v2.command.submit_plan"
EVENT_APPROVE_PLAN = "workflow.v2.command.approve_plan"
EVENT_REJECT_PLAN = "workflow.v2.command.reject_plan"
EVENT_STOP_WORKFLOW = "workflow.v2.command.stop"
EVENT_CANCEL_WORKFLOW = "workflow.v2.command.cancel"
EVENT_RESUME_WORKFLOW = "workflow.v2.command.resume"
EVENT_NODE_PROGRESS = "workflow.v2.command.node_progress"
EVENT_COMPLETE_CANDIDATE = "workflow.v2.command.complete_candidate"
EVENT_SELECT_CANDIDATE = "workflow.v2.command.select_candidate"
EVENT_REGENERATE_NODE = "workflow.v2.command.regenerate_node"
EVENT_APPROVE_ASSEMBLY = "workflow.v2.command.approve_assembly"
EVENT_REJECT_ASSEMBLY = "workflow.v2.command.reject_assembly"
EVENT_ROLLBACK_WORKFLOW = "workflow.v2.command.rollback"

# ══════════════════════════════════════
# Permission tables
# ══════════════════════════════════════

ALLOWED_REVIEW_ACTORS = {"zhongshu", "emperor"}
ACTION_PERMISSIONS: dict[tuple[str, str], set[str]] = {
    ("workflow", "start_planning"): {"taizi", "zhongshu", "emperor", "api", "flutter"},
    ("workflow", "submit_plan"): {"taizi", "zhongshu", "emperor", "api", "flutter"},
    ("workflow", "approve_plan"): {"zhongshu", "emperor"},
    ("workflow", "reject_plan"): {"zhongshu", "emperor"},
    ("workflow", "stop"): {"taizi", "zhongshu", "emperor", "api", "flutter"},
    ("workflow", "cancel"): {"taizi", "zhongshu", "emperor", "api", "flutter"},
    ("workflow", "resume"): {"taizi", "zhongshu", "emperor", "api", "flutter"},
    ("workflow", "rollback"): {"zhongshu", "emperor"},
    ("node", "progress"): {"libu", "hubu", "bingbu", "xingbu", "gongbu", "api", "flutter"},
    ("node", "regenerate"): {"zhongshu", "emperor"},
    ("candidate", "complete"): {"libu", "hubu", "bingbu", "xingbu", "gongbu", "api", "flutter"},
    ("candidate", "select"): {"zhongshu", "emperor"},
    ("assembly", "approve"): {"zhongshu", "emperor"},
    ("assembly", "reject"): {"zhongshu", "emperor"},
    ("revision", "approve"): {"zhongshu", "emperor"},
    ("revision", "reject"): {"zhongshu", "emperor"},
}
COMMAND_TO_ACTION: dict[str, tuple[str, str]] = {
    EVENT_START_PLANNING: ("workflow", "start_planning"),
    EVENT_SUBMIT_PLAN: ("workflow", "submit_plan"),
    EVENT_APPROVE_PLAN: ("workflow", "approve_plan"),
    EVENT_REJECT_PLAN: ("workflow", "reject_plan"),
    EVENT_STOP_WORKFLOW: ("workflow", "stop"),
    EVENT_CANCEL_WORKFLOW: ("workflow", "cancel"),
    EVENT_RESUME_WORKFLOW: ("workflow", "resume"),
    EVENT_NODE_PROGRESS: ("node", "progress"),
    EVENT_COMPLETE_CANDIDATE: ("candidate", "complete"),
    EVENT_SELECT_CANDIDATE: ("candidate", "select"),
    EVENT_REGENERATE_NODE: ("node", "regenerate"),
    EVENT_APPROVE_ASSEMBLY: ("assembly", "approve"),
    EVENT_REJECT_ASSEMBLY: ("assembly", "reject"),
    EVENT_ROLLBACK_WORKFLOW: ("workflow", "rollback"),
}
MAX_CANDIDATES_PER_NODE = 5
MAX_REGENERATE_TIMES = 2

# ══════════════════════════════════════
# Guard functions
# ══════════════════════════════════════


@dataclass(frozen=True)
class PolicyViolation(Exception):
    message: str

    def __str__(self) -> str:
        return self.message


def normalize_actor(actor: str) -> str:
    return (actor or "").strip().lower()


def ensure_review_actor(actor: str) -> None:
    if normalize_actor(actor) not in ALLOWED_REVIEW_ACTORS:
        raise PolicyViolation("当前角色不允许执行审批操作")


def ensure_action_actor(resource: str, action: str, actor: str) -> None:
    allowed = ACTION_PERMISSIONS.get((resource, action))
    if not allowed:
        return
    normalized = normalize_actor(actor)
    if normalized not in allowed:
        raise PolicyViolation(f"当前角色不允许执行该动作: {resource}.{action}")


def ensure_command_actor(event_type: str, actor: str) -> None:
    resource_action = COMMAND_TO_ACTION.get(event_type)
    if not resource_action:
        return
    ensure_action_actor(resource_action[0], resource_action[1], actor)


def ensure_not_done(snapshot: "WorkflowSnapshot") -> None:
    if snapshot.workflow.state in {"done", "cancelled"}:
        raise PolicyViolation("终态流程不可回滚")


def ensure_candidate_limit(snapshot: "WorkflowSnapshot", node_id: str) -> None:
    count = sum(1 for item in snapshot.candidates if item.node_id == node_id)
    if count >= MAX_CANDIDATES_PER_NODE:
        raise PolicyViolation(f"该节点候选数已达上限（{MAX_CANDIDATES_PER_NODE}）")


def ensure_regenerate_allowed(node: "NodeEntity") -> int:
    current = int((node.meta or {}).get("regenerate_count") or 0)
    if current >= MAX_REGENERATE_TIMES:
        raise PolicyViolation(f"该节点重新生成次数已达上限（{MAX_REGENERATE_TIMES}）")
    return current + 1
