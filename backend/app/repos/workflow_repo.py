"""Workflow v2 repository backed by SQLAlchemy models."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from kernel.graph_entities import (
    ArtifactRef,
    AssemblyEntity,
    AssemblyItemRef,
    CandidateEntity,
    DecisionEntity,
    NodeEntity,
    RevisionEntity,
    WorkflowEntity,
    WorkflowSnapshot,
)
from ..models.workflow_models import (
    WorkflowAssembly,
    WorkflowArtifact,
    WorkflowCandidate,
    WorkflowDecision,
    WorkflowInstance,
    WorkflowNode,
    WorkflowRevision,
)


class WorkflowRepo:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_workflow(self, entity: WorkflowEntity) -> WorkflowEntity:
        model = WorkflowInstance(
            id=entity.id,
            task_id=entity.task_id,
            workflow_type=entity.type,
            title=entity.title,
            goal=entity.goal,
            state=entity.state,
            owner=entity.owner,
            current_revision_id=entity.current_revision_id,
            current_assembly_id=entity.current_assembly_id,
            summary_output=entity.summary_output,
            meta=entity.meta,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.db.add(model)
        await self.db.flush()
        return _workflow_from_model(model)

    async def save_workflow(self, entity: WorkflowEntity) -> WorkflowEntity:
        model = await self.db.get(WorkflowInstance, entity.id)
        if model is None:
            raise ValueError(f"Workflow not found: {entity.id}")
        model.task_id = entity.task_id
        model.workflow_type = entity.type
        model.title = entity.title
        model.goal = entity.goal
        model.state = entity.state
        model.owner = entity.owner
        model.current_revision_id = entity.current_revision_id
        model.current_assembly_id = entity.current_assembly_id
        model.summary_output = entity.summary_output
        model.meta = entity.meta
        model.created_at = entity.created_at
        model.updated_at = entity.updated_at
        await self.db.flush()
        return _workflow_from_model(model)

    async def get_workflow(self, workflow_id: str) -> WorkflowEntity | None:
        model = await self.db.get(WorkflowInstance, workflow_id)
        return _workflow_from_model(model) if model else None

    async def create_revision(self, entity: RevisionEntity) -> RevisionEntity:
        model = WorkflowRevision(
            id=entity.id,
            workflow_id=entity.workflow_id,
            revision_number=entity.number,
            status=entity.status,
            created_by=entity.created_by,
            source=entity.source,
            content=entity.content,
            change_summary=entity.change_summary,
            parent_revision_id=entity.parent_revision_id,
            meta=entity.meta,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.db.add(model)
        await self.db.flush()
        return _revision_from_model(model)

    async def save_revision(self, entity: RevisionEntity) -> RevisionEntity:
        model = await self.db.get(WorkflowRevision, entity.id)
        if model is None:
            raise ValueError(f"Revision not found: {entity.id}")
        model.status = entity.status
        model.created_by = entity.created_by
        model.source = entity.source
        model.content = entity.content
        model.change_summary = entity.change_summary
        model.parent_revision_id = entity.parent_revision_id
        model.meta = entity.meta
        model.created_at = entity.created_at
        model.updated_at = entity.updated_at
        await self.db.flush()
        return _revision_from_model(model)

    async def get_revision(self, revision_id: str) -> RevisionEntity | None:
        model = await self.db.get(WorkflowRevision, revision_id)
        return _revision_from_model(model) if model else None

    async def list_revisions(self, workflow_id: str) -> list[RevisionEntity]:
        rows = await self.db.execute(
            select(WorkflowRevision)
            .where(WorkflowRevision.workflow_id == workflow_id)
            .order_by(WorkflowRevision.revision_number.asc())
        )
        return [_revision_from_model(item) for item in rows.scalars().all()]

    async def create_node(self, entity: NodeEntity) -> NodeEntity:
        model = WorkflowNode(
            id=entity.id,
            workflow_id=entity.workflow_id,
            revision_id=entity.revision_id,
            kind=entity.kind,
            state=entity.state,
            title=entity.title,
            description=entity.description,
            parent_node_id=entity.parent_node_id,
            assignee=entity.assignee,
            sequence=entity.sequence,
            acceptance_criteria=entity.acceptance_criteria,
            selected_candidate_id=entity.selected_candidate_id,
            spec=entity.spec,
            meta=entity.meta,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.db.add(model)
        await self.db.flush()
        return _node_from_model(model)

    async def save_node(self, entity: NodeEntity) -> NodeEntity:
        model = await self.db.get(WorkflowNode, entity.id)
        if model is None:
            raise ValueError(f"Node not found: {entity.id}")
        model.state = entity.state
        model.title = entity.title
        model.description = entity.description
        model.parent_node_id = entity.parent_node_id
        model.assignee = entity.assignee
        model.sequence = entity.sequence
        model.acceptance_criteria = entity.acceptance_criteria
        model.selected_candidate_id = entity.selected_candidate_id
        model.spec = entity.spec
        model.meta = entity.meta
        model.created_at = entity.created_at
        model.updated_at = entity.updated_at
        await self.db.flush()
        return _node_from_model(model)

    async def get_node(self, node_id: str) -> NodeEntity | None:
        model = await self.db.get(WorkflowNode, node_id)
        return _node_from_model(model) if model else None

    async def list_nodes(self, workflow_id: str) -> list[NodeEntity]:
        rows = await self.db.execute(
            select(WorkflowNode)
            .where(WorkflowNode.workflow_id == workflow_id)
            .order_by(WorkflowNode.sequence.asc(), WorkflowNode.created_at.asc())
        )
        return [_node_from_model(item) for item in rows.scalars().all()]

    async def create_candidate(self, entity: CandidateEntity) -> CandidateEntity:
        model = WorkflowCandidate(
            id=entity.id,
            workflow_id=entity.workflow_id,
            node_id=entity.node_id,
            status=entity.status,
            provider=entity.provider,
            summary=entity.summary,
            score=entity.score,
            prompt_snapshot=entity.prompt_snapshot,
            metrics=entity.metrics,
            meta=entity.meta,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.db.add(model)
        await self.db.flush()
        await self._replace_artifacts("candidate", entity.id, entity.workflow_id, entity.artifacts)
        return _candidate_from_model(model)

    async def save_candidate(self, entity: CandidateEntity) -> CandidateEntity:
        model = await self.db.get(WorkflowCandidate, entity.id)
        if model is None:
            raise ValueError(f"Candidate not found: {entity.id}")
        model.status = entity.status
        model.provider = entity.provider
        model.summary = entity.summary
        model.score = entity.score
        model.prompt_snapshot = entity.prompt_snapshot
        model.metrics = entity.metrics
        model.meta = entity.meta
        model.created_at = entity.created_at
        model.updated_at = entity.updated_at
        await self.db.flush()
        await self._replace_artifacts("candidate", entity.id, entity.workflow_id, entity.artifacts)
        return _candidate_from_model(model)

    async def get_candidate(self, candidate_id: str) -> CandidateEntity | None:
        model = await self.db.get(WorkflowCandidate, candidate_id)
        return _candidate_from_model(model) if model else None

    async def list_candidates(self, workflow_id: str) -> list[CandidateEntity]:
        rows = await self.db.execute(
            select(WorkflowCandidate)
            .where(WorkflowCandidate.workflow_id == workflow_id)
            .order_by(WorkflowCandidate.created_at.asc())
        )
        return [_candidate_from_model(item) for item in rows.scalars().all()]

    async def list_candidates_for_node(self, node_id: str) -> list[CandidateEntity]:
        rows = await self.db.execute(
            select(WorkflowCandidate)
            .where(WorkflowCandidate.node_id == node_id)
            .order_by(WorkflowCandidate.created_at.asc())
        )
        return [_candidate_from_model(item) for item in rows.scalars().all()]

    async def create_decision(self, entity: DecisionEntity) -> DecisionEntity:
        model = WorkflowDecision(
            id=entity.id,
            workflow_id=entity.workflow_id,
            target_type=entity.target_type,
            target_id=entity.target_id,
            action=entity.action,
            actor=entity.actor,
            comment=entity.comment,
            payload=entity.payload,
            created_at=entity.created_at,
        )
        self.db.add(model)
        await self.db.flush()
        return _decision_from_model(model)

    async def list_decisions(self, workflow_id: str) -> list[DecisionEntity]:
        rows = await self.db.execute(
            select(WorkflowDecision)
            .where(WorkflowDecision.workflow_id == workflow_id)
            .order_by(WorkflowDecision.created_at.asc())
        )
        return [_decision_from_model(item) for item in rows.scalars().all()]

    async def create_assembly(self, entity: AssemblyEntity) -> AssemblyEntity:
        model = WorkflowAssembly(
            id=entity.id,
            workflow_id=entity.workflow_id,
            status=entity.status,
            summary=entity.summary,
            items=[_assembly_item_to_dict(item) for item in entity.items],
            meta=entity.meta,
            created_at=entity.created_at,
            updated_at=entity.updated_at,
        )
        self.db.add(model)
        await self.db.flush()
        await self._replace_artifacts("assembly", entity.id, entity.workflow_id, entity.artifacts)
        return _assembly_from_model(model)

    async def save_assembly(self, entity: AssemblyEntity) -> AssemblyEntity:
        model = await self.db.get(WorkflowAssembly, entity.id)
        if model is None:
            raise ValueError(f"Assembly not found: {entity.id}")
        model.status = entity.status
        model.summary = entity.summary
        model.items = [_assembly_item_to_dict(item) for item in entity.items]
        model.meta = entity.meta
        model.created_at = entity.created_at
        model.updated_at = entity.updated_at
        await self.db.flush()
        await self._replace_artifacts("assembly", entity.id, entity.workflow_id, entity.artifacts)
        return _assembly_from_model(model)

    async def get_assembly(self, assembly_id: str) -> AssemblyEntity | None:
        model = await self.db.get(WorkflowAssembly, assembly_id)
        return _assembly_from_model(model) if model else None

    async def list_assemblies(self, workflow_id: str) -> list[AssemblyEntity]:
        rows = await self.db.execute(
            select(WorkflowAssembly)
            .where(WorkflowAssembly.workflow_id == workflow_id)
            .order_by(WorkflowAssembly.created_at.asc())
        )
        return [_assembly_from_model(item) for item in rows.scalars().all()]

    async def list_artifacts(self, owner_type: str, owner_id: str) -> list[ArtifactRef]:
        rows = await self.db.execute(
            select(WorkflowArtifact)
            .where(WorkflowArtifact.owner_type == owner_type, WorkflowArtifact.owner_id == owner_id)
            .order_by(WorkflowArtifact.created_at.asc())
        )
        return [
            ArtifactRef(
                kind=item.kind,
                path=item.path,
                mime=item.mime,
                preview_url=item.preview_url,
                metadata=dict(item.metadata_ or {}),
            )
            for item in rows.scalars().all()
        ]

    async def load_snapshot(
        self,
        workflow_id: str,
        *,
        include_revisions: bool = True,
        include_nodes: bool = True,
        include_candidates: bool = True,
        include_decisions: bool = False,
        include_assemblies: bool = True,
    ) -> WorkflowSnapshot:
        workflow = await self.get_workflow(workflow_id)
        if workflow is None:
            raise ValueError(f"Workflow not found: {workflow_id}")
        snapshot = WorkflowSnapshot(
            workflow=workflow,
            revisions=await self.list_revisions(workflow_id) if include_revisions else [],
            nodes=await self.list_nodes(workflow_id) if include_nodes else [],
            candidates=await self.list_candidates(workflow_id) if include_candidates else [],
            decisions=await self.list_decisions(workflow_id) if include_decisions else [],
            assemblies=await self.list_assemblies(workflow_id) if include_assemblies else [],
        )
        if include_candidates:
            for candidate in snapshot.candidates:
                candidate.artifacts = await self.list_artifacts("candidate", candidate.id)
        if include_assemblies:
            for assembly in snapshot.assemblies:
                assembly.artifacts = await self.list_artifacts("assembly", assembly.id)
        return snapshot

    async def _replace_artifacts(
        self,
        owner_type: str,
        owner_id: str,
        workflow_id: str,
        artifacts: list[ArtifactRef],
    ) -> None:
        rows = await self.db.execute(
            select(WorkflowArtifact).where(
                WorkflowArtifact.owner_type == owner_type,
                WorkflowArtifact.owner_id == owner_id,
            )
        )
        for item in rows.scalars().all():
            await self.db.delete(item)
        for index, artifact in enumerate(artifacts or [], start=1):
            self.db.add(
                WorkflowArtifact(
                    id=f"{owner_type}-{owner_id}-{index}",
                    workflow_id=workflow_id,
                    owner_type=owner_type,
                    owner_id=owner_id,
                    kind=artifact.kind,
                    path=artifact.path,
                    mime=artifact.mime,
                    preview_url=artifact.preview_url,
                    metadata_=dict(artifact.metadata or {}),
                )
            )


def _workflow_from_model(model: WorkflowInstance) -> WorkflowEntity:
    return WorkflowEntity(
        id=model.id,
        task_id=model.task_id,
        type=model.workflow_type,
        title=model.title,
        goal=model.goal,
        state=model.state,
        owner=model.owner,
        current_revision_id=model.current_revision_id,
        current_assembly_id=model.current_assembly_id,
        summary_output=model.summary_output,
        meta=dict(model.meta or {}),
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _revision_from_model(model: WorkflowRevision) -> RevisionEntity:
    return RevisionEntity(
        id=model.id,
        workflow_id=model.workflow_id,
        number=model.revision_number,
        status=model.status,
        created_by=model.created_by,
        source=model.source,
        content=model.content,
        change_summary=model.change_summary,
        parent_revision_id=model.parent_revision_id,
        meta=dict(model.meta or {}),
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _node_from_model(model: WorkflowNode) -> NodeEntity:
    return NodeEntity(
        id=model.id,
        workflow_id=model.workflow_id,
        revision_id=model.revision_id,
        kind=model.kind,
        state=model.state,
        title=model.title,
        description=model.description,
        parent_node_id=model.parent_node_id,
        assignee=model.assignee,
        sequence=model.sequence,
        spec=dict(model.spec or {}),
        acceptance_criteria=model.acceptance_criteria,
        selected_candidate_id=model.selected_candidate_id,
        meta=dict(model.meta or {}),
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _candidate_from_model(model: WorkflowCandidate) -> CandidateEntity:
    return CandidateEntity(
        id=model.id,
        workflow_id=model.workflow_id,
        node_id=model.node_id,
        status=model.status,
        provider=model.provider,
        summary=model.summary,
        prompt_snapshot=dict(model.prompt_snapshot or {}),
        metrics=dict(model.metrics or {}),
        score=model.score,
        artifacts=[],
        meta=dict(model.meta or {}),
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _decision_from_model(model: WorkflowDecision) -> DecisionEntity:
    return DecisionEntity(
        id=model.id,
        workflow_id=model.workflow_id,
        target_type=model.target_type,
        target_id=model.target_id,
        action=model.action,
        actor=model.actor,
        comment=model.comment,
        payload=dict(model.payload or {}),
        created_at=model.created_at,
    )


def _assembly_item_to_dict(item: AssemblyItemRef) -> dict:
    return {
        "order": item.order,
        "node_id": item.node_id,
        "candidate_id": item.candidate_id,
        "role": item.role,
        "meta": dict(item.meta or {}),
    }


def _assembly_from_model(model: WorkflowAssembly) -> AssemblyEntity:
    items = [
        AssemblyItemRef(
            order=int(item.get("order", 0)),
            node_id=str(item.get("node_id", "")),
            candidate_id=str(item.get("candidate_id", "")),
            role=str(item.get("role", "primary")),
            meta=dict(item.get("meta", {}) or {}),
        )
        for item in list(model.items or [])
    ]
    return AssemblyEntity(
        id=model.id,
        workflow_id=model.workflow_id,
        status=model.status,
        items=items,
        summary=model.summary,
        artifacts=[],
        meta=dict(model.meta or {}),
        created_at=model.created_at,
        updated_at=model.updated_at,
    )
