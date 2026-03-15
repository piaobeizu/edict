"""Kernel 单元测试 — 纯逻辑，不需要 DB/Redis/外部依赖。"""



import pytest
from datetime import datetime, timezone

# 确保 kernel 可导入

from edict_kernel.state_machine import StateMachine, InvalidTransitionError, Transition
from edict_kernel.task_entity import TaskEntity, FlowEntry, ProgressEntry, TodoItem
from edict_kernel.workflow import WorkflowEngine, EVENT_TASK_CREATED, EVENT_TASK_STATE_CHANGED, EVENT_TASK_COMPLETED, EVENT_TASK_DISPATCH
from edict_kernel.ports import ExecutionResult


# ══════════════════════════════════════
# StateMachine Tests
# ══════════════════════════════════════

@pytest.fixture
def simple_sm():
    """最小状态机：draft → review → done/cancelled。"""
    return StateMachine(
        transitions={
            "draft": {"review", "cancelled"},
            "review": {"done", "draft"},
        },
        terminal_states={"done", "cancelled"},
        initial_state="draft",
    )


@pytest.fixture
def edict_sm():
    """三省六部状态机。"""
    from edict_kernel.adapters.edict_routing import create_edict_state_machine
    return create_edict_state_machine()


class TestStateMachine:
    def test_initial_state(self, simple_sm):
        assert simple_sm.initial_state == "draft"

    def test_all_states(self, simple_sm):
        assert simple_sm.all_states == frozenset({"draft", "review", "done", "cancelled"})

    def test_terminal(self, simple_sm):
        assert simple_sm.is_terminal("done")
        assert simple_sm.is_terminal("cancelled")
        assert not simple_sm.is_terminal("draft")

    def test_allowed_transitions(self, simple_sm):
        assert simple_sm.allowed_transitions("draft") == frozenset({"review", "cancelled"})
        assert simple_sm.allowed_transitions("review") == frozenset({"done", "draft"})
        assert simple_sm.allowed_transitions("done") == frozenset()

    def test_validate_ok(self, simple_sm):
        simple_sm.validate("draft", "review")  # should not raise

    def test_validate_bad(self, simple_sm):
        with pytest.raises(InvalidTransitionError) as exc_info:
            simple_sm.validate("draft", "done")
        assert exc_info.value.current == "draft"
        assert exc_info.value.target == "done"
        assert "review" in exc_info.value.allowed

    def test_validate_from_terminal(self, simple_sm):
        with pytest.raises(InvalidTransitionError):
            simple_sm.validate("done", "draft")

    def test_transition_returns_record(self, simple_sm):
        t = simple_sm.transition("draft", "review", agent="user", reason="ready")
        assert isinstance(t, Transition)
        assert t.from_state == "draft"
        assert t.to_state == "review"
        assert t.agent == "user"

    def test_edict_full_happy_path(self, edict_sm):
        """三省六部完整流转路径。"""
        path = ["Taizi", "Zhongshu", "Menxia", "YuLan", "Assigned", "Doing", "Review", "Done"]
        state = edict_sm.initial_state
        assert state == "Taizi"
        for target in path[1:]:
            edict_sm.validate(state, target)
            state = target
        assert edict_sm.is_terminal(state)

    def test_edict_reject_path(self, edict_sm):
        """门下省封驳退回中书省。"""
        edict_sm.validate("Menxia", "Zhongshu")

    def test_edict_blocked_recovery(self, edict_sm):
        """Blocked 可恢复到多个状态。"""
        allowed = edict_sm.allowed_transitions("Blocked")
        assert "Taizi" in allowed
        assert "Doing" in allowed

    def test_edict_invalid_skip(self, edict_sm):
        """不能跳过中书直接到门下。"""
        with pytest.raises(InvalidTransitionError):
            edict_sm.validate("Taizi", "Menxia")


# ══════════════════════════════════════
# TaskEntity Tests
# ══════════════════════════════════════

class TestTaskEntity:
    def test_create(self):
        t = TaskEntity(id="T-001", title="Test", state="draft")
        assert t.id == "T-001"
        assert t.flow_log == []
        assert t.todos == []

    def test_append_flow(self):
        t = TaskEntity(id="T-001", title="Test", state="draft")
        e = FlowEntry(from_state="draft", to_state="review", agent="user", reason="ready")
        t.append_flow(e)
        assert len(t.flow_log) == 1
        assert t.flow_log[0].to_state == "review"

    def test_to_dict(self):
        t = TaskEntity(id="T-001", title="Test", state="draft", priority="high")
        d = t.to_dict()
        assert d["id"] == "T-001"
        assert d["state"] == "draft"
        assert d["priority"] == "high"
        assert isinstance(d["flow_log"], list)

    def test_todo_item(self):
        td = TodoItem(id=1, title="Step 1", status="in-progress")
        assert td.to_dict() == {"id": 1, "title": "Step 1", "status": "in-progress", "detail": ""}


# ══════════════════════════════════════
# WorkflowEngine Tests (with in-memory mocks)
# ══════════════════════════════════════

class InMemoryRepo:
    """内存版 TaskRepo，用于测试。"""
    def __init__(self):
        self._store: dict[str, TaskEntity] = {}

    async def create(self, entity: TaskEntity) -> TaskEntity:
        self._store[entity.id] = entity
        return entity

    async def get(self, task_id: str) -> TaskEntity | None:
        return self._store.get(task_id)

    async def save(self, entity: TaskEntity) -> TaskEntity:
        self._store[entity.id] = entity
        return entity

    async def list_by_state(self, state=None, assignee=None, limit=50, offset=0):
        results = list(self._store.values())
        if state:
            results = [t for t in results if t.state == state]
        if assignee:
            results = [t for t in results if t.assignee == assignee]
        return results[offset:offset+limit]

    async def count(self, state=None):
        if state:
            return sum(1 for t in self._store.values() if t.state == state)
        return len(self._store)


class InMemoryBus:
    """内存版 EventBusPort，记录所有发布的事件。"""
    def __init__(self):
        self.events: list[dict] = []

    async def publish(self, topic, trace_id, event_type, producer, payload=None):
        self.events.append({
            "topic": topic, "trace_id": trace_id,
            "event_type": event_type, "producer": producer,
            "payload": payload or {},
        })
        return f"evt-{len(self.events)}"

    async def consume(self, topic, group, consumer, count=10, block_ms=5000):
        return []

    async def ack(self, topic, group, entry_id):
        pass

    async def claim_stale(self, topic, group, consumer, min_idle_ms=60000, count=10):
        return []


@pytest.fixture
def engine():
    sm = StateMachine(
        transitions={
            "open": {"in_progress", "cancelled"},
            "in_progress": {"review", "cancelled"},
            "review": {"done", "in_progress"},
        },
        terminal_states={"done", "cancelled"},
        initial_state="open",
    )
    repo = InMemoryRepo()
    bus = InMemoryBus()
    return WorkflowEngine(state_machine=sm, repo=repo, bus=bus), repo, bus


@pytest.fixture
def edict_engine():
    from edict_kernel.adapters.edict_routing import create_edict_state_machine, EdictRoutingPolicy
    sm = create_edict_state_machine()
    repo = InMemoryRepo()
    bus = InMemoryBus()
    routing = EdictRoutingPolicy()
    return WorkflowEngine(state_machine=sm, repo=repo, bus=bus, routing=routing), repo, bus


class TestWorkflowEngine:
    @pytest.mark.asyncio
    async def test_create_task(self, engine):
        eng, repo, bus = engine
        task = await eng.create_task("Write tests", priority="high", creator="dev")
        assert task.state == "open"
        assert task.title == "Write tests"
        assert len(task.flow_log) == 1
        assert await repo.count() == 1
        assert len(bus.events) == 1
        assert bus.events[0]["topic"] == EVENT_TASK_CREATED

    @pytest.mark.asyncio
    async def test_transition(self, engine):
        eng, repo, bus = engine
        task = await eng.create_task("Task A")
        task = await eng.transition(task.id, "in_progress", agent="bot", reason="started")
        assert task.state == "in_progress"
        assert len(task.flow_log) == 2
        assert bus.events[-1]["topic"] == EVENT_TASK_STATE_CHANGED

    @pytest.mark.asyncio
    async def test_transition_to_terminal(self, engine):
        eng, repo, bus = engine
        task = await eng.create_task("Task B")
        task = await eng.transition(task.id, "in_progress")
        task = await eng.transition(task.id, "review")
        task = await eng.transition(task.id, "done", reason="completed")
        assert task.state == "done"
        assert bus.events[-1]["topic"] == EVENT_TASK_COMPLETED

    @pytest.mark.asyncio
    async def test_invalid_transition(self, engine):
        eng, _, _ = engine
        task = await eng.create_task("Task C")
        with pytest.raises(InvalidTransitionError):
            await eng.transition(task.id, "done")  # can't skip

    @pytest.mark.asyncio
    async def test_dispatch(self, engine):
        eng, _, bus = engine
        task = await eng.create_task("Task D")
        await eng.dispatch(task.id, target_agent="worker-1", message="go")
        dispatch_evt = [e for e in bus.events if e["topic"] == EVENT_TASK_DISPATCH]
        assert len(dispatch_evt) == 1
        assert dispatch_evt[0]["payload"]["agent"] == "worker-1"

    @pytest.mark.asyncio
    async def test_add_progress(self, engine):
        eng, _, _ = engine
        task = await eng.create_task("Task E")
        task = await eng.add_progress(task.id, "bot", "50% done")
        assert len(task.progress_log) == 1
        assert task.progress_log[0].content == "50% done"

    @pytest.mark.asyncio
    async def test_update_todos(self, engine):
        eng, _, _ = engine
        task = await eng.create_task("Task F")
        task = await eng.update_todos(task.id, [
            {"id": 1, "title": "Step 1", "status": "completed"},
            {"id": 2, "title": "Step 2", "status": "in-progress"},
        ])
        assert len(task.todos) == 2
        assert task.todos[0].status == "completed"

    @pytest.mark.asyncio
    async def test_edict_full_flow(self, edict_engine):
        """三省六部完整流转 + 自动路由。"""
        eng, repo, bus = edict_engine
        task = await eng.create_task("写周报", assignee="太子", creator="皇上")
        assert task.state == "Taizi"

        # 自动派发（RoutingPolicy 决定 agent）
        await eng.dispatch(task.id)
        dispatch_evts = [e for e in bus.events if e["topic"] == EVENT_TASK_DISPATCH]
        assert dispatch_evts[-1]["payload"]["agent"] == "taizi"

        # 完整流转
        task = await eng.transition(task.id, "Zhongshu", agent="taizi", reason="已分拣")
        task = await eng.transition(task.id, "Menxia", agent="zhongshu", reason="起草完成")
        task = await eng.transition(task.id, "YuLan", agent="menxia", reason="审议通过")
        task = await eng.transition(task.id, "Assigned", agent="emperor", reason="御批")
        task = await eng.transition(task.id, "Doing", agent="shangshu", reason="派发户部")
        task = await eng.transition(task.id, "Review", agent="hubu", reason="执行完成")
        task = await eng.transition(task.id, "Done", agent="shangshu", reason="审查通过")

        assert task.state == "Done"
        assert len(task.flow_log) == 8  # 1 create + 7 transitions
        completed_evts = [e for e in bus.events if e["topic"] == EVENT_TASK_COMPLETED]
        assert len(completed_evts) == 1


# ══════════════════════════════════════
# ExecutionResult Tests
# ══════════════════════════════════════

class TestExecutionResult:
    def test_success(self):
        r = ExecutionResult(success=True, output="done", duration_ms=1500)
        assert r.success
        d = r.to_dict()
        assert d["output"] == "done"

    def test_failure(self):
        r = ExecutionResult(success=False, error="timeout")
        assert not r.success
        assert r.error == "timeout"


# ══════════════════════════════════════
# EdictRoutingPolicy Tests
# ══════════════════════════════════════

class TestEdictRouting:
    def test_next_agent_taizi(self):
        from edict_kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Taizi")
        assert policy.next_agent(task) == "taizi"

    def test_next_agent_doing(self):
        from edict_kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Doing", assignee="户部")
        assert policy.next_agent(task) == "hubu"

    def test_next_agent_doing_unknown_dept(self):
        from edict_kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Doing", assignee="未知部")
        assert policy.next_agent(task) is None

    def test_next_state_after_completion(self):
        from edict_kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Zhongshu")
        assert policy.next_state_after_completion(task) == "Menxia"

    def test_no_next_for_done(self):
        from edict_kernel.adapters.edict_routing import EdictRoutingPolicy
        policy = EdictRoutingPolicy()
        task = TaskEntity(id="T-1", title="Test", state="Done")
        assert policy.next_state_after_completion(task) is None
