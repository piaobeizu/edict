"""Edict 运维命令行工具。

用法:
    python -m edict.backend.app.cli.ops replay-task <task_id>
    python -m edict.backend.app.cli.ops mark-done <task_id> [--reason "手动完结"]
    python -m edict.backend.app.cli.ops requeue-dead-letter [--all] [--entry-id <id>]
    python -m edict.backend.app.cli.ops throttle --concurrency 1
    python -m edict.backend.app.cli.ops list-stalled [--threshold 300]
    python -m edict.backend.app.cli.ops task-info <task_id>
"""

import argparse
import asyncio
import json
import sys
import logging
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")


async def cmd_replay_task(args):
    """重新派发指定任务到 dispatch 队列。"""
    from ..services.event_bus import EventBus, TOPIC_TASK_DISPATCH
    from ..db import async_session
    from ..models.task import Task, STATE_AGENT_MAP, ORG_AGENT_MAP, TaskState

    bus = EventBus()
    await bus.connect()

    async with async_session() as db:
        task = await db.get(Task, args.task_id)
        if not task:
            print(f"❌ Task not found: {args.task_id}")
            return

        state = task.state if isinstance(task.state, TaskState) else TaskState(task.state)
        agent = STATE_AGENT_MAP.get(state)
        if state == TaskState.Assigned:
            agent = ORG_AGENT_MAP.get(task.org, agent)

        if not agent:
            agent = args.agent or "taizi"
            print(f"⚠️  No agent mapped for state {state.value}, using: {agent}")

        # Clear idempotency key to allow re-dispatch
        idem_pattern = f"edict:dispatch:idem:{args.task_id}:*"
        keys = []
        async for key in bus.redis.scan_iter(idem_pattern):
            keys.append(key)
        if keys:
            await bus.redis.delete(*keys)
            print(f"🔑 Cleared {len(keys)} idempotency key(s)")

        dispatch_round = int(args.round or 1)
        entry_id = await bus.publish(
            topic=TOPIC_TASK_DISPATCH,
            trace_id=args.task_id,
            event_type="task.dispatch.replay",
            producer="ops-cli",
            payload={
                "task_id": args.task_id,
                "agent": agent,
                "state": state.value,
                "message": f"ops replay: {args.reason or 'manual replay'}",
                "dispatch_round": dispatch_round,
            },
        )
        print(f"✅ Replayed task {args.task_id} → agent={agent} round={dispatch_round} entry={entry_id}")

    await bus.close()


async def cmd_mark_done(args):
    """手动将任务标记为 Done。"""
    from ..db import async_session
    from ..models.task import Task, TaskState
    from ..services.event_bus import EventBus, TOPIC_TASK_COMPLETED

    bus = EventBus()
    await bus.connect()

    async with async_session() as db:
        task = await db.get(Task, args.task_id)
        if not task:
            print(f"❌ Task not found: {args.task_id}")
            return

        old_state = task.state if isinstance(task.state, TaskState) else TaskState(task.state)
        task.state = TaskState.Done.value
        task.updated_at = datetime.now(timezone.utc)

        flow_entry = {
            "from": old_state.value,
            "to": TaskState.Done.value,
            "agent": "ops-cli",
            "reason": args.reason or "manual mark-done via CLI",
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        task.flow_log = [*(task.flow_log or []), flow_entry]

        # Converge all todos to completed
        if task.todos:
            task.todos = [{**td, "status": "completed"} for td in task.todos]

        await db.commit()

        await bus.publish(
            topic=TOPIC_TASK_COMPLETED,
            trace_id=args.task_id,
            event_type="task.state.Done",
            producer="ops-cli",
            payload={
                "task_id": args.task_id,
                "from": old_state.value,
                "to": "Done",
                "reason": args.reason or "manual",
            },
        )

        print(f"✅ Task {args.task_id}: {old_state.value} → Done")

    await bus.close()


async def cmd_requeue_dead_letter(args):
    """将死信队列中的事件重新入队。"""
    from ..services.event_bus import EventBus, TOPIC_TASK_DISPATCH, TOPIC_TASK_DISPATCH_DEAD_LETTER

    bus = EventBus()
    await bus.connect()

    dlq_key = bus._stream_key(TOPIC_TASK_DISPATCH_DEAD_LETTER)

    if args.entry_id:
        # Replay specific entry
        rows = await bus.redis.xrange(dlq_key, min=args.entry_id, max=args.entry_id, count=1)
        if not rows:
            print(f"❌ DLQ entry not found: {args.entry_id}")
            await bus.close()
            return
        entries = rows
    elif args.all:
        entries = await bus.redis.xrange(dlq_key, count=100)
    else:
        # Default: show DLQ contents
        entries = await bus.redis.xrevrange(dlq_key, count=20)
        if not entries:
            print("📭 DLQ is empty")
        else:
            print(f"📋 DLQ has {len(entries)} entries (showing newest 20):")
            for eid, data in entries:
                payload = json.loads(data.get("payload", "{}"))
                print(f"  {eid} | task={payload.get('task_id','')} agent={payload.get('agent','')} "
                      f"err={payload.get('error_type','')} attempts={payload.get('attempts','')}")
            print(f"\nUse --entry-id <id> or --all to replay")
        await bus.close()
        return

    replayed = 0
    for entry_id, data in entries:
        payload = json.loads(data.get("payload", "{}"))
        task_id = payload.get("task_id")
        agent = payload.get("agent")
        if not task_id or not agent:
            continue

        # Clear idempotency key
        idem_pattern = f"edict:dispatch:idem:{task_id}:{agent}:*"
        async for key in bus.redis.scan_iter(idem_pattern):
            await bus.redis.delete(key)

        dispatch_round = int(payload.get("dispatch_round", 1)) + 1
        await bus.publish(
            topic=TOPIC_TASK_DISPATCH,
            trace_id=data.get("trace_id", task_id),
            event_type="task.dispatch.replay",
            producer="ops-cli",
            payload={
                "task_id": task_id,
                "agent": agent,
                "state": payload.get("state", ""),
                "message": payload.get("message", ""),
                "dispatch_round": dispatch_round,
                "replay_of": entry_id,
            },
        )
        replayed += 1
        print(f"  ✅ Replayed {entry_id} → task={task_id} agent={agent} round={dispatch_round}")

    print(f"\n🔁 Replayed {replayed} DLQ entries")
    await bus.close()


async def cmd_throttle(args):
    """设置限流保护模式：通过 Redis 控制 dispatch 并发上限。"""
    from ..services.event_bus import EventBus

    bus = EventBus()
    await bus.connect()

    key = "edict:config:dispatch_concurrency"

    if args.concurrency is not None:
        await bus.redis.set(key, str(args.concurrency))
        print(f"🔧 Dispatch concurrency set to {args.concurrency}")
        if args.concurrency <= 1:
            print("⚠️  限流保护模式已开启 (concurrency=1)")
    else:
        val = await bus.redis.get(key)
        print(f"📊 Current dispatch concurrency: {val or 'default (3)'}")

    await bus.close()


async def cmd_list_stalled(args):
    """列出停滞任务。"""
    from ..db import async_session
    from ..models.task import Task, TERMINAL_STATES
    from sqlalchemy import select  # type: ignore[reportMissingImports]

    threshold = int(args.threshold or 300)
    now = datetime.now(timezone.utc)

    async with async_session() as db:
        result = await db.execute(select(Task).where(Task.state.notin_([s.value for s in TERMINAL_STATES])))
        tasks = list(result.scalars().all())

    stalled = []
    for t in tasks:
        ref = t.updated_at or t.created_at
        if ref:
            elapsed = (now - ref.replace(tzinfo=timezone.utc if ref.tzinfo is None else ref.tzinfo)).total_seconds()
            if elapsed >= threshold:
                stalled.append((t, elapsed))

    stalled.sort(key=lambda x: -x[1])

    if not stalled:
        print(f"✅ No stalled tasks (threshold={threshold}s)")
    else:
        print(f"⏸️  {len(stalled)} stalled tasks (threshold={threshold}s):")
        for t, elapsed in stalled:
            mins = int(elapsed // 60)
            print(f"  {t.id} | state={t.state} | org={t.org} | stalled={mins}m | title={t.title[:50]}")


async def cmd_task_info(args):
    """显示任务详细信息。"""
    from ..db import async_session
    from ..models.task import Task

    async with async_session() as db:
        task = await db.get(Task, args.task_id)
        if not task:
            print(f"❌ Task not found: {args.task_id}")
            return

    d = task.to_dict()
    print(json.dumps(d, indent=2, ensure_ascii=False, default=str))


async def cmd_drain_queue(args):
    """清空指定 Redis Stream（读取并删除前 N 条）。"""
    from ..services.event_bus import EventBus, STREAM_PREFIX

    bus = EventBus()
    await bus.connect()

    topic = args.topic
    count = max(1, int(args.count or 100))
    stream_key = topic if topic.startswith(STREAM_PREFIX) else bus._stream_key(topic)

    try:
        rows = await bus.redis.xrange(stream_key, count=count)
        if not rows:
            print(f"📭 Queue empty: {stream_key}")
            return

        entry_ids = [entry_id for entry_id, _ in rows]
        deleted = await bus.redis.xdel(stream_key, *entry_ids)
        print(f"🧹 Drained {deleted} event(s) from {stream_key}")
    finally:
        await bus.close()


async def cmd_event_trace(args):
    """按 task_id 聚合所有 stream 事件轨迹。"""
    from ..services.event_bus import EventBus, STREAM_PREFIX

    bus = EventBus()
    await bus.connect()

    task_id = args.task_id
    limit = max(1, int(args.limit or 50))
    matches = []

    try:
        keys = [k async for k in bus.redis.scan_iter(f"{STREAM_PREFIX}*")]
        for key in keys:
            rows = await bus.redis.xrevrange(key, count=max(limit, 200))
            for entry_id, data in rows:
                payload_raw = data.get("payload", "{}")
                try:
                    payload = json.loads(payload_raw) if isinstance(payload_raw, str) else (payload_raw or {})
                except Exception:
                    payload = {}

                if payload.get("task_id") != task_id and data.get("trace_id", "") != task_id:
                    continue

                topic = key[len(STREAM_PREFIX):] if key.startswith(STREAM_PREFIX) else key
                matches.append(
                    {
                        "topic": topic,
                        "entry_id": entry_id,
                        "timestamp": data.get("timestamp", ""),
                        "event_type": data.get("event_type", ""),
                        "producer": data.get("producer", ""),
                        "trace_id": data.get("trace_id", ""),
                        "payload": payload,
                    }
                )

        matches.sort(key=lambda x: (x.get("timestamp", ""), x.get("entry_id", "")))
        matches = matches[-limit:]

        if not matches:
            print(f"🔍 No events found for task_id={task_id}")
            return

        print(f"📚 Event trace for {task_id} (showing {len(matches)}):")
        for item in matches:
            print(
                f"  {item['timestamp']} | {item['topic']} | {item['event_type']} | "
                f"producer={item['producer']} | entry={item['entry_id']}"
            )
            print(f"    payload={json.dumps(item['payload'], ensure_ascii=False, default=str)}")
    finally:
        await bus.close()


async def cmd_health_report(_args):
    """输出系统健康报告：Redis/DB/队列/停滞任务/DLQ。"""
    from sqlalchemy import select, text  # type: ignore[reportMissingImports]
    from ..db import async_session
    from ..models.task import Task, TERMINAL_STATES
    from ..services.event_bus import (
        EventBus,
        TOPIC_TASK_CREATED,
        TOPIC_TASK_PLANNING_REQUEST,
        TOPIC_TASK_PLANNING_COMPLETE,
        TOPIC_TASK_REVIEW_REQUEST,
        TOPIC_TASK_REVIEW_RESULT,
        TOPIC_TASK_DISPATCH,
        TOPIC_TASK_DISPATCH_DEAD_LETTER,
        TOPIC_TASK_STATUS,
        TOPIC_TASK_COMPLETED,
        TOPIC_TASK_CLOSED,
        TOPIC_TASK_REPLAN,
        TOPIC_TASK_STALLED,
        TOPIC_TASK_ESCALATED,
        TOPIC_AGENT_THOUGHTS,
        TOPIC_AGENT_TODO_UPDATE,
        TOPIC_AGENT_HEARTBEAT,
    )

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "redis": {"ok": False, "error": ""},
        "database": {"ok": False, "error": ""},
        "queues": {},
        "stalled_task_count": 0,
        "dlq_size": 0,
    }

    bus = EventBus()
    await bus.connect()

    try:
        try:
            pong = await bus.redis.ping()
            report["redis"]["ok"] = bool(pong)
        except Exception as e:
            report["redis"]["error"] = str(e)

        try:
            async with async_session() as db:
                await db.execute(text("SELECT 1"))
                report["database"]["ok"] = True

                threshold = 300
                now = datetime.now(timezone.utc)
                result = await db.execute(
                    select(Task).where(Task.state.notin_([s.value for s in TERMINAL_STATES]))
                )
                tasks = list(result.scalars().all())
                stalled_count = 0
                for task in tasks:
                    ref = task.updated_at or task.created_at
                    if not ref:
                        continue
                    base = ref.replace(tzinfo=timezone.utc if ref.tzinfo is None else ref.tzinfo)
                    if (now - base).total_seconds() >= threshold:
                        stalled_count += 1
                report["stalled_task_count"] = stalled_count
        except Exception as e:
            report["database"]["error"] = str(e)

        topics = [
            TOPIC_TASK_CREATED,
            TOPIC_TASK_PLANNING_REQUEST,
            TOPIC_TASK_PLANNING_COMPLETE,
            TOPIC_TASK_REVIEW_REQUEST,
            TOPIC_TASK_REVIEW_RESULT,
            TOPIC_TASK_DISPATCH,
            TOPIC_TASK_DISPATCH_DEAD_LETTER,
            TOPIC_TASK_STATUS,
            TOPIC_TASK_COMPLETED,
            TOPIC_TASK_CLOSED,
            TOPIC_TASK_REPLAN,
            TOPIC_TASK_STALLED,
            TOPIC_TASK_ESCALATED,
            TOPIC_AGENT_THOUGHTS,
            TOPIC_AGENT_TODO_UPDATE,
            TOPIC_AGENT_HEARTBEAT,
        ]

        for topic in topics:
            key = bus._stream_key(topic)
            try:
                report["queues"][topic] = await bus.redis.xlen(key)
            except Exception:
                report["queues"][topic] = 0

        report["dlq_size"] = int(report["queues"].get(TOPIC_TASK_DISPATCH_DEAD_LETTER, 0))
    finally:
        await bus.close()

    print(json.dumps(report, indent=2, ensure_ascii=False, default=str))


def main():
    parser = argparse.ArgumentParser(description="Edict 运维工具")
    sub = parser.add_subparsers(dest="command")

    # replay-task
    p = sub.add_parser("replay-task", help="重新派发任务")
    p.add_argument("task_id")
    p.add_argument("--agent", default=None, help="指定 agent（默认根据状态自动选择）")
    p.add_argument("--round", default=None, help="指定 dispatch_round")
    p.add_argument("--reason", default="", help="原因")

    # mark-done
    p = sub.add_parser("mark-done", help="手动标记任务完成")
    p.add_argument("task_id")
    p.add_argument("--reason", default="", help="原因")

    # requeue-dead-letter
    p = sub.add_parser("requeue-dead-letter", help="重放死信队列")
    p.add_argument("--entry-id", default=None, help="指定 entry ID")
    p.add_argument("--all", action="store_true", help="重放所有")

    # throttle
    p = sub.add_parser("throttle", help="限流保护模式")
    p.add_argument("--concurrency", type=int, default=None, help="设置并发上限")

    # list-stalled
    p = sub.add_parser("list-stalled", help="列出停滞任务")
    p.add_argument("--threshold", default="300", help="停滞阈值(秒)")

    # task-info
    p = sub.add_parser("task-info", help="查看任务详情")
    p.add_argument("task_id")

    # drain-queue
    p = sub.add_parser("drain-queue", help="清空指定事件队列")
    p.add_argument("--topic", required=True, help="topic 名称，如 task.dispatch")
    p.add_argument("--count", type=int, default=100, help="最多清理多少条")

    # event-trace
    p = sub.add_parser("event-trace", help="查看任务事件轨迹")
    p.add_argument("task_id")
    p.add_argument("--limit", type=int, default=50, help="最多显示多少条")

    # health-report
    sub.add_parser("health-report", help="系统健康报告")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmd_map = {
        "replay-task": cmd_replay_task,
        "mark-done": cmd_mark_done,
        "requeue-dead-letter": cmd_requeue_dead_letter,
        "throttle": cmd_throttle,
        "list-stalled": cmd_list_stalled,
        "task-info": cmd_task_info,
        "drain-queue": cmd_drain_queue,
        "event-trace": cmd_event_trace,
        "health-report": cmd_health_report,
    }

    asyncio.run(cmd_map[args.command](args))


if __name__ == "__main__":
    main()
