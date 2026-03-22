"""kernel — 与框架/存储无关的工作流引擎核心。

核心层零外部依赖（纯 stdlib），adapters 按需导入。

Quick start:
    from kernel import StateMachine, TaskEntity, GraphWorkflowEngine
    from kernel.ports import TaskRepo, EventBusPort

    # 三省六部业务层:
    from kernel.adapters.edict_routing import create_edict_state_machine, EdictRoutingPolicy
"""
