"""Workflow v2 events and topic constants."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

TOPIC_WORKFLOW_CREATED = "workflow.v2.created"
TOPIC_WORKFLOW_STATE_CHANGED = "workflow.v2.state.changed"
TOPIC_WORKFLOW_REVISION_CREATED = "workflow.v2.revision.created"
TOPIC_WORKFLOW_NODE_CREATED = "workflow.v2.node.created"
TOPIC_WORKFLOW_NODE_STATE_CHANGED = "workflow.v2.node.state.changed"
TOPIC_WORKFLOW_NODE_DISPATCHED = "workflow.v2.node.dispatched"
TOPIC_WORKFLOW_CANDIDATE_CREATED = "workflow.v2.candidate.created"
TOPIC_WORKFLOW_CANDIDATE_UPDATED = "workflow.v2.candidate.updated"
TOPIC_WORKFLOW_CANDIDATE_SELECTED = "workflow.v2.candidate.selected"
TOPIC_WORKFLOW_ASSEMBLY_CREATED = "workflow.v2.assembly.created"
TOPIC_WORKFLOW_DECISION = "workflow.v2.decision"
TOPIC_WORKFLOW_PROJECTION_REFRESH = "workflow.v2.projection.updated"


@dataclass
class WorkflowEvent:
    topic: str
    event_type: str
    trace_id: str
    producer: str
    payload: dict[str, Any] = field(default_factory=dict)

    def with_version(self) -> "WorkflowEvent":
        payload = dict(self.payload)
        payload.setdefault("workflow_version", 2)
        return WorkflowEvent(
            topic=self.topic,
            event_type=self.event_type,
            trace_id=self.trace_id,
            producer=self.producer,
            payload=payload,
        )
