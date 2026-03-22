from __future__ import annotations

from copy import deepcopy

from kernel.graph_entities import WorkflowSnapshot


class InMemoryWorkflowRepo:
    def __init__(self):
        self.workflows = {}
        self.revisions = {}
        self.nodes = {}
        self.candidates = {}
        self.decisions = {}
        self.assemblies = {}

    async def create_workflow(self, entity):
        self.workflows[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def save_workflow(self, entity):
        self.workflows[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def create_revision(self, entity):
        self.revisions[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def save_revision(self, entity):
        self.revisions[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def create_node(self, entity):
        self.nodes[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def save_node(self, entity):
        self.nodes[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def create_candidate(self, entity):
        self.candidates[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def save_candidate(self, entity):
        self.candidates[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def create_decision(self, entity):
        self.decisions[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def create_assembly(self, entity):
        self.assemblies[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def save_assembly(self, entity):
        self.assemblies[entity.id] = deepcopy(entity)
        return deepcopy(entity)

    async def get_workflow(self, workflow_id):
        item = self.workflows.get(workflow_id)
        return deepcopy(item) if item else None

    async def get_revision(self, revision_id):
        item = self.revisions.get(revision_id)
        return deepcopy(item) if item else None

    async def list_revisions(self, workflow_id):
        return [deepcopy(v) for v in self.revisions.values() if v.workflow_id == workflow_id]

    async def get_node(self, node_id):
        item = self.nodes.get(node_id)
        return deepcopy(item) if item else None

    async def list_nodes(self, workflow_id):
        return [deepcopy(v) for v in self.nodes.values() if v.workflow_id == workflow_id]

    async def get_candidate(self, candidate_id):
        item = self.candidates.get(candidate_id)
        return deepcopy(item) if item else None

    async def list_candidates(self, workflow_id):
        return [deepcopy(v) for v in self.candidates.values() if v.workflow_id == workflow_id]

    async def list_candidates_for_node(self, node_id):
        return [deepcopy(v) for v in self.candidates.values() if v.node_id == node_id]

    async def list_decisions(self, workflow_id):
        return [deepcopy(v) for v in self.decisions.values() if v.workflow_id == workflow_id]

    async def get_assembly(self, assembly_id):
        item = self.assemblies.get(assembly_id)
        return deepcopy(item) if item else None

    async def list_assemblies(self, workflow_id):
        return [deepcopy(v) for v in self.assemblies.values() if v.workflow_id == workflow_id]

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
            raise ValueError(f"Unknown workflow: {workflow_id}")
        return WorkflowSnapshot(
            workflow=workflow,
            revisions=await self.list_revisions(workflow_id) if include_revisions else [],
            nodes=await self.list_nodes(workflow_id) if include_nodes else [],
            candidates=await self.list_candidates(workflow_id) if include_candidates else [],
            decisions=await self.list_decisions(workflow_id) if include_decisions else [],
            assemblies=await self.list_assemblies(workflow_id) if include_assemblies else [],
        )
