"""Orchestrator Worker — 消费事件总线，驱动任务状态机。

监听 topic:
- task.created → 自动派发给太子 agent
- task.planning.complete → 中书审议完成 → 流转门下
- task.review.result → 门下审核 → 通过则 Assigned，退回则 Replan
- task.status → 处理各种状态变更
- task.stalled → 处理停滞任务

这是系统的核心编排器，取代旧架构中 daemon 线程 + 定时扫描的角色。
得益于 Redis Streams ACK 机制：即使 worker 崩溃，未 ACK 的事件
会被其他消费者自动认领，永不丢失。
"""

import asyncio
import logging
import signal
from datetime import datetime, timezone

from ..config import get_settings
from ..db import async_session
from ..models.task import (
    Task,
    TaskState,
    STATE_AGENT_MAP,
    ORG_AGENT_MAP,
    STATE_TRANSITIONS,
)
from ..services.event_bus import (
    EventBus,
    TOPIC_TASK_CREATED,
    TOPIC_TASK_STATUS,
    TOPIC_TASK_DISPATCH,
    TOPIC_TASK_COMPLETED,
    TOPIC_TASK_STALLED,
    TOPIC_TASK_ESCALATED,
)
from ..services.task_service import TaskService
from ..services.metrics import get_metrics
from ..services.structured_log import (
    setup_structured_logging,
    set_trace_context,
    clear_trace_context,
)
from ..services.task_notifier import (
    notify_task_created,
    notify_task_state_changed,
    notify_task_stalled,
)

log = logging.getLogger("edict.orchestrator")

GROUP = "orchestrator"
CONSUMER = "orch-1"

# 需要监听的 topics
WATCHED_TOPICS = [
    TOPIC_TASK_CREATED,
    TOPIC_TASK_STATUS,
    TOPIC_TASK_COMPLETED,
    TOPIC_TASK_STALLED,
]


class OrchestratorWorker:
    """事件驱动的编排器 Worker。"""

    def __init__(self):
        self.bus = EventBus()
        self._running = False

    async def _mark_event_once(self, event: dict) -> bool:
        """事件幂等：同一 event_id 仅处理一次（防重复派发）。"""
        event_id = event.get("event_id")
        if not event_id:
            return True

        key = f"edict:orch:event:{event_id}"
        # SETNX + 7 天过期
        ok = await self.bus.redis.set(key, "1", ex=7 * 24 * 3600, nx=True)
        return bool(ok)

    async def start(self):
        """启动 worker 主循环。"""
        await self.bus.connect()

        # 确保所有消费者组
        for topic in WATCHED_TOPICS:
            await self.bus.ensure_consumer_group(topic, GROUP)

        self._running = True
        log.info("🏛️ Orchestrator worker started")

        # 先处理崩溃遗留的 pending 事件
        await self._recover_pending()

        while self._running:
            try:
                await self._poll_cycle()
            except Exception as e:
                log.error(f"Orchestrator poll error: {e}", exc_info=True)
                await asyncio.sleep(2)

    async def stop(self):
        self._running = False
        await self.bus.close()
        log.info("Orchestrator worker stopped")

    async def _recover_pending(self):
        """恢复崩溃前未 ACK 的事件。"""
        for topic in WATCHED_TOPICS:
            events = await self.bus.claim_stale(
                topic, GROUP, CONSUMER, min_idle_ms=30000, count=50
            )
            if events:
                log.info(f"Recovering {len(events)} stale events from {topic}")
                for entry_id, event in events:
                    await self._handle_event(topic, entry_id, event)

    async def _poll_cycle(self):
        """一次轮询周期：从所有 topic 消费事件。"""
        for topic in WATCHED_TOPICS:
            events = await self.bus.consume(
                topic, GROUP, CONSUMER, count=5, block_ms=1000
            )
            for entry_id, event in events:
                try:
                    await self._handle_event(topic, entry_id, event)
                    await self.bus.ack(topic, GROUP, entry_id)
                except Exception as e:
                    log.error(
                        f"Error handling event {entry_id} from {topic}: {e}",
                        exc_info=True,
                    )
                    # 不 ACK → 事件会被重新投递

    async def _handle_event(self, topic: str, entry_id: str, event: dict):
        """根据 topic 和 event_type 分发处理。"""
        if not await self._mark_event_once(event):
            log.info("⏭️ Skip duplicate event: %s", event.get("event_id", entry_id))
            return

        event_type = event.get("event_type", "")
        trace_id = event.get("trace_id", "")
        payload = event.get("payload", {})
        get_metrics().inc(
            "events_processed_total",
            labels={"topic": topic, "worker": "orchestrator"},
        )

        set_trace_context(
            task_id=payload.get("task_id", ""),
            trace_id=trace_id,
            stage=topic,
        )
        try:
            log.info(f"📨 {topic}/{event_type} trace={trace_id}")

            if topic == TOPIC_TASK_CREATED:
                await self._on_task_created(payload, trace_id)
            elif topic == TOPIC_TASK_STATUS:
                await self._on_task_status(event_type, payload, trace_id)
            elif topic == TOPIC_TASK_COMPLETED:
                await self._on_task_completed(payload, trace_id)
            elif topic == TOPIC_TASK_STALLED:
                await self._on_task_stalled(payload, trace_id)
        finally:
            clear_trace_context()

    async def _on_task_created(self, payload: dict, trace_id: str):
        """任务创建 → 派发给太子 agent 起草。"""
        task_id = str(payload.get("task_id") or "")
        if not task_id:
            return
        state = payload.get("state", "taizi")
        agent = STATE_AGENT_MAP.get(TaskState(state), "taizi")
        dispatch_round = await self._next_dispatch_round(task_id)

        # 推送通知
        notify_task_created(task_id=task_id, title=payload.get("title", ""))

        await self.bus.publish(
            topic=TOPIC_TASK_DISPATCH,
            trace_id=trace_id,
            event_type="task.dispatch.request",
            producer="orchestrator",
            payload={
                "task_id": task_id,
                "agent": agent,
                "state": state,
                "message": f"新任务已创建: {payload.get('title', '')}",
                "assignee_org": payload.get("assignee_org", ""),
                "dispatch_round": dispatch_round,
            },
        )

    async def _on_task_status(self, event_type: str, payload: dict, trace_id: str):
        """状态变更 → 自动派发下一个 agent。"""
        task_id = str(payload.get("task_id") or "")
        if not task_id:
            return
        old_state_str = payload.get("from", "")
        new_state_str = payload.get("to", "")

        try:
            new_state = TaskState(new_state_str)
        except ValueError:
            log.warning(f"Unknown state: {new_state_str}")
            return

        # 状态机白名单校验：非法流转拒绝并写审计事件
        if old_state_str:
            try:
                old_state = TaskState(old_state_str)
                allowed = STATE_TRANSITIONS.get(old_state, set())
                if new_state not in allowed:
                    reason = (
                        f"Illegal state transition: {old_state.value} -> {new_state.value}; "
                        f"allowed={[s.value for s in allowed]}"
                    )
                    set_trace_context(error_code="illegal_transition")
                    log.warning("🚫 %s task=%s trace=%s", reason, task_id, trace_id)
                    await self.bus.publish(
                        topic=TOPIC_TASK_ESCALATED,
                        trace_id=trace_id,
                        event_type="task.state.illegal_transition",
                        producer="orchestrator",
                        payload={
                            "task_id": task_id,
                            "from": old_state.value,
                            "to": new_state.value,
                            "reason": reason,
                            "ts": datetime.now(timezone.utc).isoformat(),
                        },
                    )
                    return
            except ValueError:
                log.warning("Unknown old state: %s", old_state_str)
                return

        ctx = await self._get_task_context(task_id)
        org = (payload.get("assignee_org") or ctx.get("org") or "").strip()
        title = ctx.get("title") or payload.get("title") or task_id
        scheduler = ctx.get("scheduler") or {}
        target_dept = str(scheduler.get("target_dept") or "").strip()

        # 推送通知（只推关键节点，内部过滤）
        notify_task_state_changed(
            task_id=task_id, title=title,
            from_state=old_state_str, to_state=new_state_str,
            reason=payload.get("reason", ""),
        )

        # 默认状态映射
        agent = STATE_AGENT_MAP.get(new_state)

        # Assigned/Doing 阶段按六部优先派发（target_dept > org）
        if new_state in (TaskState.Assigned, TaskState.Doing):
            exec_org = target_dept or org
            agent = ORG_AGENT_MAP.get(exec_org, agent)

        if agent:
            dispatch_round = await self._next_dispatch_round(task_id)
            await self.bus.publish(
                topic=TOPIC_TASK_DISPATCH,
                trace_id=trace_id,
                event_type="task.dispatch.request",
                producer="orchestrator",
                payload={
                    "task_id": task_id,
                    "agent": agent,
                    "state": new_state_str,
                    "message": f"任务已流转到 {new_state_str}",
                    "assignee_org": org,
                    "dispatch_round": dispatch_round,
                },
            )

    async def _get_task_context(self, task_id: str) -> dict:
        if not task_id:
            return {}
        try:
            async with async_session() as db:
                task = await db.get(Task, task_id)
                if not task:
                    return {}
                return {
                    "org": task.org,
                    "title": task.title,
                    "scheduler": dict(task.scheduler or {}),
                }
        except Exception:
            # 测试环境或 DB 临时不可用时，降级为仅使用事件 payload
            return {}

    async def _next_dispatch_round(self, task_id: str) -> int:
        ctx = await self._get_task_context(task_id)
        scheduler = ctx.get("scheduler") or {}
        return int(scheduler.get("lastDispatchRound", 0) or 0) + 1

    async def _on_task_completed(self, payload: dict, trace_id: str):
        """任务完成 → 记录日志 + 推送通知。"""
        task_id = payload.get("task_id")
        ctx = await self._get_task_context(str(task_id or ""))
        title = ctx.get("title") or str(task_id)
        notify_task_state_changed(
            task_id=str(task_id), title=title,
            from_state=payload.get("from", ""), to_state="Done",
            reason=payload.get("reason", ""),
        )
        log.info(f"🎉 Task {task_id} completed. trace={trace_id}")

    async def _on_task_stalled(self, payload: dict, trace_id: str):
        """任务停滞 → 自动恢复策略。

        策略：
        1. 如果 stall_count < 3：重新派发当前 agent
        2. 如果 stall_count >= 3：升级通知（发布 escalated 事件）
        3. 如果 stall_count >= 5：自动标记 Blocked
        """
        task_id = payload.get("task_id")
        stall_count = int(payload.get("stall_count", 1))

        log.warning(
            "⏸️ Task %s stalled (count=%s). trace=%s",
            task_id, stall_count, trace_id,
        )

        # 推送通知（内部过滤 stall_count < 3 不推）
        notify_task_stalled(task_id=str(task_id or ""), stall_count=stall_count)

        if stall_count >= 5:
            # 超过阈值，标记 Blocked
            log.error(
                "🚨 Task %s stalled %s times, marking Blocked. trace=%s",
                task_id, stall_count, trace_id,
            )
            async with async_session() as db:
                from ..models.task import Task, TaskState as TS, TERMINAL_STATES
                task = await db.get(Task, task_id)
                if task:
                    st = task.state if isinstance(task.state, TS) else TS(task.state)
                    if st not in TERMINAL_STATES and st != TS.Blocked:
                        task.state = TS.Blocked.value
                        task.block = f"自动阻塞：连续停滞 {stall_count} 次"
                        flow_entry = {
                            "from": st.value,
                            "to": TS.Blocked.value,
                            "agent": "orchestrator",
                            "reason": f"stalled {stall_count} times",
                            "ts": datetime.now(timezone.utc).isoformat(),
                        }
                        task.flow_log = [*(task.flow_log or []), flow_entry]
                        await db.commit()
            return

        if stall_count >= 3:
            # 发布升级事件
            await self.bus.publish(
                topic=TOPIC_TASK_ESCALATED,
                trace_id=trace_id,
                event_type="task.stalled.escalated",
                producer="orchestrator",
                payload={
                    "task_id": task_id,
                    "stall_count": stall_count,
                    "reason": f"Task stalled {stall_count} times, needs manual attention",
                    "ts": datetime.now(timezone.utc).isoformat(),
                },
            )
            # Still try to re-dispatch

        # 尝试重新派发
        async with async_session() as db:
            from ..models.task import Task, TaskState as TS, STATE_AGENT_MAP, ORG_AGENT_MAP, TERMINAL_STATES
            task = await db.get(Task, task_id)
            if not task:
                return

            st = task.state if isinstance(task.state, TS) else TS(task.state)
            if st in TERMINAL_STATES:
                return

            agent = STATE_AGENT_MAP.get(st)
            if st == TS.Assigned:
                agent = ORG_AGENT_MAP.get(task.org, agent)

            if agent:
                # Clear previous idempotency to allow re-dispatch
                idem_pattern = f"edict:dispatch:idem:{task_id}:{agent}:*"
                keys = []
                async for key in self.bus.redis.scan_iter(idem_pattern):
                    keys.append(key)
                if keys:
                    await self.bus.redis.delete(*keys)

                dispatch_round = stall_count + 100  # Use high round number to avoid collision
                await self.bus.publish(
                    topic=TOPIC_TASK_DISPATCH,
                    trace_id=trace_id,
                    event_type="task.dispatch.stall_recovery",
                    producer="orchestrator",
                    payload={
                        "task_id": task_id,
                        "agent": agent,
                        "state": st.value,
                        "message": f"stall recovery attempt {stall_count}",
                        "dispatch_round": dispatch_round,
                    },
                )
                log.info(
                    "🔄 Stall recovery: task=%s agent=%s round=%s",
                    task_id, agent, dispatch_round,
                )


async def run_orchestrator():
    """入口函数 — 用于直接运行 worker。"""
    setup_structured_logging()
    worker = OrchestratorWorker()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(worker.stop()))

    await worker.start()


if __name__ == "__main__":
    asyncio.run(run_orchestrator())
