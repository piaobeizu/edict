"""kernel package facade for source-tree usage.

让仓库根目录直接 `import kernel` 时，也能解析到 `kernel/src/` 下的实际源码。
安装成 wheel/editable 后，则由打包后的 `kernel` 包接管。
"""

from pathlib import Path

_src = Path(__file__).resolve().parent / "src"
if _src.exists():
    __path__.append(str(_src))  # type: ignore[name-defined]

from .state_machine import StateMachine, Transition, InvalidTransitionError, StateMachineError
from .task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
from .ports import ExecutionResult
from .graph_entities import (
    ArtifactRef,
    AssemblyEntity,
    AssemblyItemRef,
    CandidateEntity,
    DecisionEntity,
    NodeEntity,
    RevisionEntity,
    WorkflowEntity,
    WorkflowSnapshot,
    WorkingSnapshot,
)
from .workflow_actions import WorkflowAction
from .workflow_events import WorkflowEvent
from .workflow_types import (
    CandidateState,
    DecisionAction,
    NodeKind,
    NodeState,
    WorkflowState,
)
from .workflow_ports import (
    NodeExecutorPort,
    ProjectionPort,
    WorkflowPolicy,
    WorkflowMutationRepoPort,
    WorkflowQueryRepoPort,
    WorkflowRepoPort,
    WorkflowSnapshotRepoPort,
)
from .graph_workflow import GraphWorkflowEngine

__version__ = "0.1.0"

__all__ = [
    "StateMachine",
    "Transition",
    "InvalidTransitionError",
    "StateMachineError",
    "TaskEntity",
    "FlowEntry",
    "ProgressEntry",
    "TodoItem",
    "ExecutionResult",
    "ArtifactRef",
    "AssemblyEntity",
    "AssemblyItemRef",
    "CandidateEntity",
    "DecisionEntity",
    "NodeEntity",
    "RevisionEntity",
    "WorkflowEntity",
    "WorkflowSnapshot",
    "WorkingSnapshot",
    "WorkflowAction",
    "WorkflowEvent",
    "WorkflowPolicy",
    "WorkflowState",
    "NodeState",
    "CandidateState",
    "DecisionAction",
    "NodeKind",
    "WorkflowMutationRepoPort",
    "WorkflowQueryRepoPort",
    "WorkflowSnapshotRepoPort",
    "WorkflowRepoPort",
    "ProjectionPort",
    "NodeExecutorPort",
    "GraphWorkflowEngine",
    "__version__",
]
