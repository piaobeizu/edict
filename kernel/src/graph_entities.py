"""Graph workflow entities for kernel v2."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class ArtifactRef:
    kind: str
    path: str
    mime: str = ""
    preview_url: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class AssemblyItemRef:
    order: int
    node_id: str
    candidate_id: str
    role: str = "primary"
    meta: dict[str, Any] = field(default_factory=dict)


@dataclass
class WorkflowEntity:
    id: str
    task_id: str
    type: str
    title: str
    goal: str
    state: str
    owner: str = ""
    current_revision_id: str = ""
    current_assembly_id: str = ""
    summary_output: str = ""
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def touch(self) -> None:
        self.updated_at = utcnow()


@dataclass
class RevisionEntity:
    id: str
    workflow_id: str
    number: int
    status: str
    created_by: str
    source: str = ""
    content: str = ""
    change_summary: str = ""
    parent_revision_id: str = ""
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def touch(self) -> None:
        self.updated_at = utcnow()


@dataclass
class NodeEntity:
    id: str
    workflow_id: str
    revision_id: str
    kind: str
    state: str
    title: str
    description: str = ""
    parent_node_id: str = ""
    assignee: str = ""
    sequence: int = 0
    spec: dict[str, Any] = field(default_factory=dict)
    acceptance_criteria: str = ""
    selected_candidate_id: str = ""
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def touch(self) -> None:
        self.updated_at = utcnow()


@dataclass
class CandidateEntity:
    id: str
    workflow_id: str
    node_id: str
    status: str
    provider: str = ""
    summary: str = ""
    prompt_snapshot: dict[str, Any] = field(default_factory=dict)
    metrics: dict[str, Any] = field(default_factory=dict)
    score: float | None = None
    artifacts: list[ArtifactRef] = field(default_factory=list)
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def touch(self) -> None:
        self.updated_at = utcnow()


@dataclass
class DecisionEntity:
    id: str
    workflow_id: str
    target_type: str
    target_id: str
    action: str
    actor: str
    comment: str = ""
    payload: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)


@dataclass
class AssemblyEntity:
    id: str
    workflow_id: str
    status: str
    items: list[AssemblyItemRef] = field(default_factory=list)
    summary: str = ""
    artifacts: list[ArtifactRef] = field(default_factory=list)
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=utcnow)
    updated_at: datetime = field(default_factory=utcnow)

    def touch(self) -> None:
        self.updated_at = utcnow()


@dataclass
class WorkflowSnapshot:
    workflow: WorkflowEntity
    revisions: list[RevisionEntity] = field(default_factory=list)
    nodes: list[NodeEntity] = field(default_factory=list)
    candidates: list[CandidateEntity] = field(default_factory=list)
    decisions: list[DecisionEntity] = field(default_factory=list)
    assemblies: list[AssemblyEntity] = field(default_factory=list)

    def nodes_by_kind(self, kind: str) -> list[NodeEntity]:
        return [n for n in self.nodes if n.kind == kind]

    def candidates_for_node(self, node_id: str) -> list[CandidateEntity]:
        return [c for c in self.candidates if c.node_id == node_id]


@dataclass
class WorkingSnapshot:
    workflow: WorkflowEntity
    revisions: list[RevisionEntity] = field(default_factory=list)
    nodes: list[NodeEntity] = field(default_factory=list)
    candidates: list[CandidateEntity] = field(default_factory=list)
    decisions: list[DecisionEntity] = field(default_factory=list)
    assemblies: list[AssemblyEntity] = field(default_factory=list)

    def upsert_workflow(self, entity: WorkflowEntity) -> None:
        self.workflow = entity

    def upsert_revision(self, entity: RevisionEntity) -> None:
        for idx, item in enumerate(self.revisions):
            if item.id == entity.id:
                self.revisions[idx] = entity
                return
        self.revisions.append(entity)

    def upsert_node(self, entity: NodeEntity) -> None:
        for idx, item in enumerate(self.nodes):
            if item.id == entity.id:
                self.nodes[idx] = entity
                return
        self.nodes.append(entity)

    def upsert_candidate(self, entity: CandidateEntity) -> None:
        for idx, item in enumerate(self.candidates):
            if item.id == entity.id:
                self.candidates[idx] = entity
                return
        self.candidates.append(entity)

    def upsert_decision(self, entity: DecisionEntity) -> None:
        for idx, item in enumerate(self.decisions):
            if item.id == entity.id:
                self.decisions[idx] = entity
                return
        self.decisions.append(entity)

    def upsert_assembly(self, entity: AssemblyEntity) -> None:
        for idx, item in enumerate(self.assemblies):
            if item.id == entity.id:
                self.assemblies[idx] = entity
                return
        self.assemblies.append(entity)


def snapshot_to_working_copy(snapshot: WorkflowSnapshot) -> WorkingSnapshot:
    return WorkingSnapshot(
        workflow=deepcopy(snapshot.workflow),
        revisions=deepcopy(snapshot.revisions),
        nodes=deepcopy(snapshot.nodes),
        candidates=deepcopy(snapshot.candidates),
        decisions=deepcopy(snapshot.decisions),
        assemblies=deepcopy(snapshot.assemblies),
    )
