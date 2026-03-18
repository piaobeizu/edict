"""kernel — 与框架/存储无关的工作流引擎核心。

核心层零外部依赖（纯 stdlib），adapters 按需导入。

Quick start:
    from kernel import StateMachine, TaskEntity, WorkflowEngine
    from kernel.ports import TaskRepo, EventBusPort, AgentExecutor, RoutingPolicy

    # 三省六部业务层:
    from kernel.adapters.edict_routing import create_edict_state_machine, EdictRoutingPolicy
"""

try:  # installed/package mode
    from .state_machine import StateMachine, Transition, InvalidTransitionError, StateMachineError
    from .task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
    from .workflow import WorkflowEngine
    from .ports import ExecutionResult
except ImportError:  # source-path test mode
    from state_machine import StateMachine, Transition, InvalidTransitionError, StateMachineError
    from task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
    from workflow import WorkflowEngine
    from ports import ExecutionResult

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
    "WorkflowEngine",
    "ExecutionResult",
    "__version__",
]
