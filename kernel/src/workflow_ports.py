"""Ports for kernel v2 graph workflow."""

from __future__ import annotations

from typing import Any, Protocol, runtime_checkable

from .workflow_actions import WorkflowAction
from .workflow_events import WorkflowEvent
from .graph_entities import (
    WorkflowEntity,
    RevisionEntity,
    NodeEntity,
    CandidateEntity,
    DecisionEntity,
    AssemblyEntity,
    WorkflowSnapshot,
)


@runtime_checkable
class WorkflowMutationRepoPort(Protocol):
    async def create_workflow(self, entity: WorkflowEntity) -> WorkflowEntity: ...
    async def save_workflow(self, entity: WorkflowEntity) -> WorkflowEntity: ...
    async def create_revision(self, entity: RevisionEntity) -> RevisionEntity: ...
    async def save_revision(self, entity: RevisionEntity) -> RevisionEntity: ...
    async def create_node(self, entity: NodeEntity) -> NodeEntity: ...
    async def save_node(self, entity: NodeEntity) -> NodeEntity: ...
    async def create_candidate(self, entity: CandidateEntity) -> CandidateEntity: ...
    async def save_candidate(self, entity: CandidateEntity) -> CandidateEntity: ...
    async def create_decision(self, entity: DecisionEntity) -> DecisionEntity: ...
    async def create_assembly(self, entity: AssemblyEntity) -> AssemblyEntity: ...
    async def save_assembly(self, entity: AssemblyEntity) -> AssemblyEntity: ...


@runtime_checkable
class WorkflowQueryRepoPort(Protocol):
    async def get_workflow(self, workflow_id: str) -> WorkflowEntity | None: ...
    async def get_revision(self, revision_id: str) -> RevisionEntity | None: ...
    async def list_revisions(self, workflow_id: str) -> list[RevisionEntity]: ...
    async def get_node(self, node_id: str) -> NodeEntity | None: ...
    async def list_nodes(self, workflow_id: str) -> list[NodeEntity]: ...
    async def get_candidate(self, candidate_id: str) -> CandidateEntity | None: ...
    async def list_candidates(self, workflow_id: str) -> list[CandidateEntity]: ...
    async def list_candidates_for_node(self, node_id: str) -> list[CandidateEntity]: ...
    async def list_decisions(self, workflow_id: str) -> list[DecisionEntity]: ...
    async def get_assembly(self, assembly_id: str) -> AssemblyEntity | None: ...
    async def list_assemblies(self, workflow_id: str) -> list[AssemblyEntity]: ...


@runtime_checkable
class WorkflowSnapshotRepoPort(Protocol):
    async def load_snapshot(
        self,
        workflow_id: str,
        *,
        include_revisions: bool = True,
        include_nodes: bool = True,
        include_candidates: bool = True,
        include_decisions: bool = False,
        include_assemblies: bool = True,
    ) -> WorkflowSnapshot: ...


@runtime_checkable
class WorkflowRepoPort(
    WorkflowMutationRepoPort,
    WorkflowQueryRepoPort,
    WorkflowSnapshotRepoPort,
    Protocol,
):
    """Convenience aggregate port for implementations."""


@runtime_checkable
class ProjectionPort(Protocol):
    async def refresh_task_projection(self, workflow_id: str) -> None: ...


@runtime_checkable
class NodeExecutorPort(Protocol):
    async def execute_node(
        self,
        *,
        workflow_id: str,
        node_id: str,
        executor_id: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Run node and return execution metadata/output."""
        ...


@runtime_checkable
class WorkflowPolicy(Protocol):
    def plan_actions(
        self,
        snapshot: WorkflowSnapshot,
        event: WorkflowEvent,
    ) -> list[WorkflowAction]:
        """Plan follow-up actions for a workflow event."""
        ...
