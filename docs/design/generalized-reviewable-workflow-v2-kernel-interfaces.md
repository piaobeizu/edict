# 通用可审议工作流内核 V2 · Kernel 类与接口草案

> 状态：设计中
>
> 最后更新：2026-03-18
>
> 上游设计：`docs/design/generalized-reviewable-workflow-v2.md`

## 1. 文档目标

本文档将通用可审议工作流 V2 的内核设计收敛为可实现的 Python 抽象草案，覆盖：

- 核心实体
- 状态机分层
- Ports / Protocol
- Workflow actions
- Policy 接口
- Engine 执行骨架
- 与当前 `kernel v1` 的兼容关系

本文档不要求一次性实现全部细节，重点是先把 V2 的内核对象和交互边界定义清楚。

---

## 2. 设计原则

1. 保持 `kernel` 零业务语义，不直接出现“三省六部”“视频”“代码”等概念。
2. 保持 `kernel` 零框架依赖，继续使用 dataclass + protocol 风格。
3. 保持 `kernel v1` 可继续运行，不破坏现有 `WorkflowEngine`。
4. 将复杂工作流的核心能力收敛到“图节点 + 决策 + 动作规划”。
5. 让后续 `backend` 只是实现 ports，而不是重新定义模型。

补充约束：

6. `workflow_instance` 是 aggregate root，`task` 不在 kernel 中承担聚合语义。
7. action 必须是强类型对象，不使用 `kind: str + payload: dict[str, Any]` 作为主表达。
8. 状态合法性由 kernel 级状态机保障，不能完全依赖 policy 自觉。

---

## 3. 目录建议

建议在 `kernel/src/` 下新增以下文件：

```text
kernel/src/
  graph_entities.py
  workflow_actions.py
  workflow_events.py
  workflow_policy.py
  graph_workflow.py
  workflow_ports.py
```

保留现有文件：

- `state_machine.py`
- `task_entity.py`
- `workflow.py`
- `ports.py`

---

## 4. 核心实体草案

## 4.1 WorkflowState

```python
from enum import StrEnum


class WorkflowState(StrEnum):
    DRAFT = "draft"
    PLANNING = "planning"
    AWAITING_PLAN_REVIEW = "awaiting_plan_review"
    EXECUTING = "executing"
    AWAITING_SELECTION = "awaiting_selection"
    ASSEMBLING = "assembling"
    AWAITING_FINAL_REVIEW = "awaiting_final_review"
    DONE = "done"
    BLOCKED = "blocked"
    CANCELLED = "cancelled"
```

```python
WORKFLOW_TRANSITIONS: dict[str, set[str]] = {
    "draft": {"planning", "cancelled"},
    "planning": {"awaiting_plan_review", "blocked", "cancelled"},
    "awaiting_plan_review": {"planning", "executing", "blocked", "cancelled"},
    "executing": {"awaiting_selection", "assembling", "blocked", "cancelled"},
    "awaiting_selection": {"executing", "assembling", "blocked", "cancelled"},
    "assembling": {"awaiting_final_review", "blocked", "cancelled"},
    "awaiting_final_review": {"executing", "done", "blocked", "cancelled"},
    "blocked": {"planning", "executing", "assembling", "cancelled"},
}

WORKFLOW_TERMINAL = {"done", "cancelled"}
```

## 4.2 NodeState

```python
class NodeState(StrEnum):
    PENDING = "pending"
    READY = "ready"
    RUNNING = "running"
    PRODUCED = "produced"
    AWAITING_REVIEW = "awaiting_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    SUPERSEDED = "superseded"
    FAILED = "failed"
    CANCELLED = "cancelled"
```

```python
NODE_TRANSITIONS: dict[str, set[str]] = {
    "pending": {"ready", "cancelled"},
    "ready": {"running", "cancelled"},
    "running": {"produced", "failed", "cancelled"},
    "produced": {"awaiting_review", "approved", "rejected", "superseded"},
    "awaiting_review": {"approved", "rejected", "superseded"},
    "rejected": {"ready", "superseded", "cancelled"},
    "failed": {"ready", "superseded", "cancelled"},
    "approved": {"superseded"},
}

NODE_TERMINAL = {"cancelled", "superseded"}
```

## 4.3 CandidateState

```python
class CandidateState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    APPROVED = "approved"
    REJECTED = "rejected"
    SUPERSEDED = "superseded"
```

```python
CANDIDATE_TRANSITIONS: dict[str, set[str]] = {
    "queued": {"running", "cancelled"},
    "running": {"succeeded", "failed", "cancelled"},
    "succeeded": {"approved", "rejected", "superseded"},
    "failed": {"queued", "superseded", "cancelled"},
    "approved": {"superseded"},
    "rejected": {"queued", "superseded", "cancelled"},
}

CANDIDATE_TERMINAL = {"cancelled", "superseded"}
```

## 4.4 DecisionAction

```python
class DecisionAction(StrEnum):
    APPROVE = "approve"
    REJECT = "reject"
    SELECT = "select"
    ROLLBACK = "rollback"
    REGENERATE = "regenerate"
    CANCEL = "cancel"
```

## 4.5 NodeKind

```python
class NodeKind(StrEnum):
    PLAN = "plan"
    WORK_ITEM = "work_item"
    REVIEW_GATE = "review_gate"
    CANDIDATE_GROUP = "candidate_group"
    ASSEMBLY = "assembly"
```

## 4.6 ArtifactRef

```python
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ArtifactRef:
    kind: str
    path: str
    mime: str = ""
    preview_url: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)
```

说明：

- `kind` 建议支持 `text / image / video / audio / archive / json / link`
- `path` 可以是本地绝对路径，也可以是远端 URL
- `preview_url` 主要服务前端直接预览

## 4.7 WorkflowEntity

```python
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


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
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def touch(self) -> None:
        self.updated_at = datetime.now(timezone.utc)
```

## 4.8 RevisionEntity

```python
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
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
```

## 4.9 NodeEntity

```python
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
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def touch(self) -> None:
        self.updated_at = datetime.now(timezone.utc)
```

## 4.10 CandidateEntity

```python
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
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
```

## 4.11 DecisionEntity

```python
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
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
```

## 4.12 AssemblyEntity

```python
@dataclass
class AssemblyItemRef:
    order: int
    node_id: str
    candidate_id: str
    role: str = "primary"
    meta: dict[str, Any] = field(default_factory=dict)


@dataclass
class AssemblyEntity:
    id: str
    workflow_id: str
    status: str
    items: list[AssemblyItemRef] = field(default_factory=list)
    summary: str = ""
    artifacts: list[ArtifactRef] = field(default_factory=list)
    meta: dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
```

---

## 5. Snapshot 对象

为了方便 policy 做决策，建议提供一个只读快照对象，而不是让 policy 自己查 repo。

```python
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
```

### Snapshot 语义

需要明确区分两个概念：

- `WorkflowSnapshot`
  repo 读取出的只读输入快照，只提供给 policy 做决策

- `WorkingSnapshot`
  engine 在单次 `apply_event()` 内部维护的工作副本，会在 action 应用成功后逐步更新

这样可以解决：

- action1 创建 node，action2 立刻 dispatch 新 node
- policy 输入保持只读
- engine 内部状态可顺序演进

---

## 6. WorkflowAction 草案

## 6.1 为什么需要 Action

当前 `RoutingPolicy` 只能返回“下一步 agent / 下一步状态”。V2 需要表达更复杂的结果：

- 创建 revision
- 批量创建 nodes
- 派发 node
- 创建候选任务
- 选择候选
- 触发 assembly
- 回滚某个对象

因此建议统一为动作对象。

## 6.2 Action 基类

```python
from dataclasses import dataclass, field


@dataclass
class WorkflowAction:
    pass
```

## 6.3 建议动作子类

```python
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
    spec: dict[str, Any] = field(default_factory=dict)


@dataclass
class TransitionWorkflowAction(WorkflowAction):
    workflow_id: str
    to_state: str
    reason: str = ""


@dataclass
class TransitionNodeAction(WorkflowAction):
    node_id: str
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
class BuildAssemblyAction(WorkflowAction):
    workflow_id: str
    item_refs: list[AssemblyItemRef] = field(default_factory=list)


@dataclass
class RollbackTargetAction(WorkflowAction):
    workflow_id: str
    target_type: str
    target_id: str
    reason: str = ""


@dataclass
class RefreshProjectionAction(WorkflowAction):
    workflow_id: str
```

---

## 7. 事件对象草案

建议让 graph engine 内部也有一层结构化事件，而不是只拼 dict。

```python
@dataclass
class WorkflowEvent:
    topic: str
    event_type: str
    trace_id: str
    producer: str
    payload: dict[str, Any] = field(default_factory=dict)
```

建议的内核 topic 常量：

```python
TOPIC_WORKFLOW_CREATED = "workflow.v2.created"
TOPIC_WORKFLOW_STATE_CHANGED = "workflow.v2.state.changed"
TOPIC_WORKFLOW_REVISION_CREATED = "workflow.v2.revision.created"
TOPIC_WORKFLOW_NODE_CREATED = "workflow.v2.node.created"
TOPIC_WORKFLOW_NODE_PROGRESS = "workflow.v2.node.progress"
TOPIC_WORKFLOW_CANDIDATE_COMPLETED = "workflow.v2.candidate.completed"
TOPIC_WORKFLOW_ASSEMBLY_COMPLETED = "workflow.v2.assembly.completed"
TOPIC_WORKFLOW_DECISION = "workflow.v2.decision"
TOPIC_WORKFLOW_ROLLBACK = "workflow.v2.rollback"
```

---

## 8. Ports 草案

## 8.1 为什么不直接复用 `TaskRepo`

因为 V2 不是只有一个 `TaskEntity`，而是多个实体的聚合。

因此建议新增 `WorkflowRepoPort`，而不是把一切都塞回 `TaskRepo`。

但为了避免 God Interface，repo 需要按职责拆分。

## 8.2 WorkflowRepoPort

```python
from typing import Protocol, runtime_checkable


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
```

## 8.3 ProjectionPort

当前系统还依赖 `task` 投影，因此建议单独定义 projection port。

```python
@runtime_checkable
class ProjectionPort(Protocol):
    async def refresh_task_projection(self, workflow_id: str) -> None: ...
```

## 8.4 NodeExecutorPort

V2 中最小执行单元不再是 task，而是 node。

```python
@runtime_checkable
class NodeExecutorPort(Protocol):
    async def execute_node(
        self,
        workflow: WorkflowEntity,
        node: NodeEntity,
        snapshot: WorkflowSnapshot,
    ) -> dict[str, Any]:
        ...
```

说明：

- 可由 OpenClaw CLI、HTTP provider、FFmpeg assembly worker 等实现
- 返回值可后续再收敛为标准结果对象

---

## 9. Policy 接口草案

## 9.1 核心接口

```python
@runtime_checkable
class WorkflowPolicy(Protocol):
    def plan_actions(
        self,
        snapshot: WorkflowSnapshot,
        event: WorkflowEvent,
    ) -> list[WorkflowAction]:
        ...
```

## 9.2 为什么只要一个入口

只保留 `plan_actions()` 的好处：

- 所有状态变化最终都统一成事件驱动
- policy 不再散落多个 hook
- 业务推理集中在一个地方

## 9.3 Policy 的职责边界

Policy 负责：

- 判断该创建哪些节点
- 判断何时进入审批
- 判断何时触发 assembly
- 判断何时允许 rollback

Policy 不负责：

- 持久化
- 真正执行 node
- 推送 WebSocket
- 刷新 task projection

---

## 10. GraphWorkflowEngine 草案

## 10.1 核心职责

1. 读取 snapshot
2. 调用 policy 产出 actions
3. 顺序执行 actions
4. 写回 repo
5. 发布 bus events
6. 刷新 projection

## 10.2 构造函数

```python
class GraphWorkflowEngine:
    def __init__(
        self,
        repo: WorkflowMutationRepoPort | WorkflowQueryRepoPort | WorkflowSnapshotRepoPort,
        bus: EventBusPort,
        policy: WorkflowPolicy,
        projection: ProjectionPort | None = None,
    ):
        self.repo = repo
        self.bus = bus
        self.policy = policy
        self.projection = projection
```

## 10.3 建议公开方法

```python
class GraphWorkflowEngine:
    async def create_workflow(...): ...
    async def apply_event(self, event: WorkflowEvent) -> list[WorkflowAction]: ...
    async def submit_decision(...): ...
    async def add_node_progress(...): ...
    async def complete_candidate(...): ...
    async def complete_assembly(...): ...
    async def rollback(...): ...
    async def get_snapshot(self, workflow_id: str) -> WorkflowSnapshot: ...
```

## 10.4 `apply_event()` 伪代码

```python
async def apply_event(self, event: WorkflowEvent) -> list[WorkflowAction]:
    workflow_id = event.payload["workflow_id"]
    snapshot = await self.repo.load_snapshot(workflow_id)
    actions = self.policy.plan_actions(snapshot, event)

    # 真实实现必须在单个 DB transaction 中对事实表和 outbox 一起提交
    working = snapshot_to_working_copy(snapshot)
    for action in actions:
        await self._apply_action(working, event, action)

    if self.projection:
        await self.projection.refresh_task_projection(workflow_id)

    return actions
```

## 10.5 `_apply_action()` 伪代码

```python
async def _apply_action(self, snapshot, event, action):
    if isinstance(action, CreateRevisionAction):
        ...
    elif isinstance(action, SpawnNodeAction):
        ...
    elif isinstance(action, TransitionWorkflowAction):
        ...
    elif isinstance(action, TransitionNodeAction):
        ...
    elif isinstance(action, CreateCandidateAction):
        ...
    elif isinstance(action, BuildAssemblyAction):
        ...
    else:
        raise NotImplementedError(type(action).__name__)
```

---

## 11. 与当前 Kernel V1 的兼容方案

## 11.1 不改 `WorkflowEngine`

现有：

- `kernel/src/workflow.py`
- `kernel/src/task_entity.py`
- `kernel/src/ports.py`

都不做破坏性修改。

## 11.2 新增导出

建议在 `kernel/src/__init__.py` 中新增：

```python
from .graph_entities import (
    WorkflowEntity,
    RevisionEntity,
    NodeEntity,
    CandidateEntity,
    DecisionEntity,
    AssemblyEntity,
    ArtifactRef,
    WorkflowSnapshot,
)
from .workflow_actions import WorkflowAction
from .workflow_policy import WorkflowPolicy
from .graph_workflow import GraphWorkflowEngine
```

## 11.3 使用策略

- 简单线性任务：继续使用 `WorkflowEngine`
- 复杂可审议任务：使用 `GraphWorkflowEngine`

这样能避免一次性把现有代码全迁走。

---

## 12. In-Memory 测试基座建议

为了快速推进 V2，建议像当前 `kernel/tests/test_kernel.py` 一样，先做纯内存测试。

建议新增：

- `InMemoryWorkflowRepo`
- `InMemoryProjectionPort`
- `FakeWorkflowPolicy`

先验证：

1. workflow 创建
2. revision 创建
3. revision 审批后生成 nodes
4. node 完成后生成 candidates
5. candidate 选中后触发 assembly
6. assembly 完成后进入最终审批
7. rollback 正确生成 superseded 状态

---

## 13. 第一批建议落地范围

如果只做最小可用版本，建议第一批内核实现只包含：

- `WorkflowEntity`
- `RevisionEntity`
- `NodeEntity`
- `CandidateEntity`
- `DecisionEntity`
- `WorkflowSnapshot`
- `WorkflowMutationRepoPort`
- `WorkflowQueryRepoPort`
- `WorkflowSnapshotRepoPort`
- `WorkflowPolicy`
- `GraphWorkflowEngine`
- `WorkflowAction`

暂时可以不实现：

- `AssemblyEntity`
- 复杂 rollback
- 嵌套 node graph

原因是：

- 先跑通“方案审批 -> 步骤执行 -> 候选选择”即可覆盖大多数复杂任务的骨架
- assembly 可以作为第二阶段加入

---

## 14. 最终结论

V2 内核的关键不是把现有 `TaskEntity` 变得更大，而是把复杂工作流拆成：

- 顶层 workflow
- revision
- node
- candidate
- decision
- action

并用 `GraphWorkflowEngine + WorkflowPolicy` 统一驱动。

这套抽象既能兼容当前 Edict 的制度化架构，也能支撑未来的视频、代码、文档、调研等通用复杂任务。
