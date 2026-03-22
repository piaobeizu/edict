"""Strongly typed workflow actions for kernel v2."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

try:
    from .graph_entities import AssemblyItemRef
except ImportError:
    from graph_entities import AssemblyItemRef


@dataclass
class WorkflowAction:
    """Marker base class for workflow actions."""


@dataclass
class CreateRevisionAction(WorkflowAction):
    workflow_id: str
    created_by: str
    source: str = ""
    content: str = ""
    parent_revision_id: str = ""


@dataclass
class SpawnNodeAction(WorkflowAction):
    workflow_id: str
    revision_id: str
    kind: str
    title: str
    description: str = ""
    parent_node_id: str = ""
    assignee: str = ""
    sequence: int = 0
    state: str = "ready"
    spec: dict[str, Any] = field(default_factory=dict)


@dataclass
class TransitionWorkflowAction(WorkflowAction):
    workflow_id: str
    to_state: str
    reason: str = ""


@dataclass
class TransitionRevisionAction(WorkflowAction):
    workflow_id: str
    to_status: str
    revision_id: str = ""
    reason: str = ""


@dataclass
class TransitionNodeAction(WorkflowAction):
    node_id: str
    to_state: str
    reason: str = ""


@dataclass
class TransitionCandidateAction(WorkflowAction):
    candidate_id: str
    to_state: str
    reason: str = ""


@dataclass
class DispatchNodeAction(WorkflowAction):
    node_id: str
    executor_id: str
    message: str = ""


@dataclass
class CreateCandidateAction(WorkflowAction):
    workflow_id: str
    node_id: str
    provider: str
    prompt_snapshot: dict[str, Any] = field(default_factory=dict)


@dataclass
class SelectCandidateAction(WorkflowAction):
    node_id: str
    candidate_id: str


@dataclass
class UpsertAssemblyFromSelectionAction(WorkflowAction):
    workflow_id: str
    node_id: str
    candidate_id: str
    summary: str = ""


@dataclass
class CompleteAssemblyAction(WorkflowAction):
    workflow_id: str
    assembly_id: str = ""
    status: str = "done"
    summary: str = ""
    artifacts: list[Any] | None = None
    meta: dict[str, Any] | None = None


@dataclass
class RejectAssemblyAction(WorkflowAction):
    workflow_id: str
    assembly_id: str
    reason: str = ""


@dataclass
class RollbackWorkflowAction(WorkflowAction):
    workflow_id: str
    actor: str
    target_revision_id: str = ""
    reason: str = ""


@dataclass
class BuildAssemblyAction(WorkflowAction):
    workflow_id: str
    item_refs: list[AssemblyItemRef] = field(default_factory=list)


@dataclass
class RecordDecisionAction(WorkflowAction):
    workflow_id: str
    target_type: str
    target_id: str
    action: str
    actor: str
    comment: str = ""
    payload: dict[str, Any] = field(default_factory=dict)


@dataclass
class RefreshProjectionAction(WorkflowAction):
    workflow_id: str
