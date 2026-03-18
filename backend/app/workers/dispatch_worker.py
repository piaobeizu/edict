"""Dispatch Worker — 消费 task.dispatch 事件，执行 OpenClaw agent 调用。

核心解决旧架构痛点：
- 旧: daemon 线程 + subprocess.run → kill -9 丢失一切
- 新: Redis Streams ACK 保证 → 崩溃后自动重新投递

流程:
1. 从 task.dispatch stream 消费事件
2. 调用 OpenClaw CLI: `openclaw agent --agent xxx -m "..."`
3. 解析 agent 输出（kanban_update.py 调用结果）
4. ACK 事件
"""

import asyncio
import json
import logging
import os
import random
import signal
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any
from datetime import datetime, timezone

from ..config import get_settings
from ..db import async_session
from ..models.task import Task, TaskState
from ..services.task_service import TaskService
from ..services.event_bus import (
    EventBus,
    TOPIC_TASK_DISPATCH,
    TOPIC_TASK_DISPATCH_DEAD_LETTER,
    TOPIC_AGENT_THOUGHTS,
    TOPIC_AGENT_HEARTBEAT,
)
from ..services.output_normalizer import normalize_agent_output
from ..services.metrics import get_metrics
from ..services.structured_log import (
    setup_structured_logging,
    set_trace_context,
    clear_trace_context,
)

log = logging.getLogger("edict.dispatcher")

GROUP = "dispatcher"
CONSUMER = f"disp-{os.getpid()}-{uuid.uuid4().hex[:6]}"


class DispatchWorker:
    """Agent 派发 Worker — 调用 OpenClaw CLI 执行 agent 任务。"""

    def __init__(self, max_concurrent: int = 3):
        self.bus = EventBus()
        self._running = False
        self._semaphore = asyncio.Semaphore(max_concurrent)
        self._active_tasks: dict[str, asyncio.Task] = {}
        self._throttle_key = "edict:config:dispatch_concurrency"

    async def _mark_dispatch_once(self, payload: dict) -> bool:
        """派发幂等：同 task+agent+round 只执行一次。"""
        task_id = payload.get("task_id", "")
        agent = payload.get("agent", "")
        dispatch_round = int(payload.get("dispatch_round") or 1)
        if not task_id or not agent:
            return True

        key = f"edict:dispatch:idem:{task_id}:{agent}:{dispatch_round}"
        ok = await self.bus.redis.set(key, "1", ex=7 * 24 * 3600, nx=True)
        return bool(ok)

    async def _clear_dispatch_dedup(self, payload: dict):
        """回滚去重标记，允许事件被重新处理。"""
        task_id = payload.get("task_id", "")
        agent = payload.get("agent", "")
        dispatch_round = int(payload.get("dispatch_round") or 1)
        if task_id and agent:
            key = f"edict:dispatch:idem:{task_id}:{agent}:{dispatch_round}"
            await self.bus.redis.delete(key)

    async def start(self):
        await self.bus.connect()
        await self.bus.ensure_consumer_group(TOPIC_TASK_DISPATCH, GROUP)
        self._running = True
        log.info("🚀 Dispatch worker started")

        # 恢复崩溃遗留
        await self._recover_pending()

        while self._running:
            try:
                await self._poll_cycle()
            except Exception as e:
                log.error(f"Dispatch poll error: {e}", exc_info=True)
                await asyncio.sleep(2)

    async def stop(self):
        self._running = False
        # 等待进行中的 agent 调用完成
        if self._active_tasks:
            log.info(f"Waiting for {len(self._active_tasks)} active dispatches...")
            await asyncio.gather(*self._active_tasks.values(), return_exceptions=True)
        await self.bus.close()
        log.info("Dispatch worker stopped")

    async def _recover_pending(self):
        events = await self.bus.claim_stale(
            TOPIC_TASK_DISPATCH, GROUP, CONSUMER, min_idle_ms=60000, count=20
        )
        if events:
            log.info(f"Recovering {len(events)} stale dispatch events")
            for entry_id, event in events:
                await self._dispatch(entry_id, event, is_recovery=True)

    async def _check_throttle(self):
        """检查 Redis 中的动态并发配置，更新信号量。

        注意：仅在无活跃任务时才替换 semaphore，避免并发不一致。
        """
        try:
            val = await self.bus.redis.get(self._throttle_key)
            if val:
                new_limit = max(1, int(val))
                current_limit = self._semaphore._value + len(self._active_tasks)
                if new_limit != current_limit and not self._active_tasks:
                    self._semaphore = asyncio.Semaphore(new_limit)
                    log.info("🔧 Dispatch concurrency updated to %s", new_limit)
        except Exception:
            pass  # Use existing semaphore on error

    async def _poll_cycle(self):
        await self._check_throttle()
        events = await self.bus.consume(
            TOPIC_TASK_DISPATCH, GROUP, CONSUMER, count=3, block_ms=2000
        )
        for entry_id, event in events:
            # 每个派发在独立任务中执行，带并发控制
            # 用 entry_id 作为 key，避免同 task_id 并发 dispatch 覆盖
            task = asyncio.create_task(self._dispatch(entry_id, event))
            self._active_tasks[entry_id] = task
            task.add_done_callback(lambda t, eid=entry_id: self._active_tasks.pop(eid, None))

    async def _dispatch(self, entry_id: str, event: dict, is_recovery: bool = False):
        """执行一次 agent 派发。"""
        async with self._semaphore:
            payload = event.get("payload", {})
            task_id = payload.get("task_id", "")
            agent = payload.get("agent", "")
            message = payload.get("message", "")
            trace_id = event.get("trace_id", "")
            state = payload.get("state", "")
            dispatch_round = int(payload.get("dispatch_round") or 1)

            set_trace_context(
                task_id=task_id,
                trace_id=trace_id,
                stage=f"dispatch.{agent}",
            )

            try:
                if not await self._mark_dispatch_once(payload):
                    await self._update_scheduler_status(
                        task_id=task_id,
                        status="skipped",
                        agent=agent,
                        dispatch_round=dispatch_round,
                        extra={"reason": "duplicate_dispatch"},
                    )
                    log.info(
                        "⏭️ Skip duplicate dispatch: task=%s agent=%s round=%s",
                        task_id,
                        agent,
                        dispatch_round,
                    )
                    await self.bus.ack(TOPIC_TASK_DISPATCH, GROUP, entry_id)
                    return

                log.info(f"🔄 Dispatching task {task_id} → agent '{agent}' state={state}")
                await self._update_scheduler_status(
                    task_id=task_id,
                    status="running",
                    agent=agent,
                    dispatch_round=dispatch_round,
                )

                # 发布心跳
                await self.bus.publish(
                    topic=TOPIC_AGENT_HEARTBEAT,
                    trace_id=trace_id,
                    event_type="agent.dispatch.start",
                    producer="dispatcher",
                    payload={"task_id": task_id, "agent": agent},
                )

                dispatch_started = time.monotonic()
                task_context = await self._load_task_context(task_id)
                dispatch_message = self._compose_dispatch_message(
                    task_id=task_id,
                    state=state,
                    agent=agent,
                    original_message=message,
                    task_context=task_context,
                )
                result = await self._call_openclaw_with_retry(
                    agent=agent,
                    message=dispatch_message,
                    task_id=task_id,
                    trace_id=trace_id,
                    dispatch_round=dispatch_round,
                )
                metrics = get_metrics()
                metrics.inc(
                    "dispatch_total",
                    labels={"agent": agent or "unknown", "result": result.get("error_type", "unknown")},
                )
                metrics.observe(
                    "dispatch_latency_seconds",
                    value=time.monotonic() - dispatch_started,
                    labels={"agent": agent or "unknown"},
                )
                if result.get("error_type") == "rate_limit":
                    metrics.inc("rate_limit_total")

                # 发布 agent 输出
                normalized = normalize_agent_output(
                    task_id=task_id,
                    agent=agent,
                    returncode=result.get("returncode", -1),
                    stdout=result.get("stdout", ""),
                    stderr=result.get("stderr", ""),
                    attempts=int(result.get("attempts", 1)),
                    error_type=result.get("error_type", "unknown"),
                )

                await self.bus.publish(
                    topic=TOPIC_AGENT_THOUGHTS,
                    trace_id=trace_id,
                    event_type="agent.output",
                    producer=f"agent.{agent}",
                    payload={
                        "task_id": task_id,
                        "agent": agent,
                        "output": normalized.get("output", ""),
                        "summary": normalized.get("summary", ""),
                        "artifacts": normalized.get("artifacts", []),
                        "retry": normalized.get("retry", {}),
                        "return_code": result.get("returncode", -1),
                    },
                )

                # 输出兜底回填：即使 agent 没主动 done，也写最小可见产出
                await self._backfill_task_output(
                    task_id=task_id,
                    agent=agent,
                    normalized=normalized,
                )

                if result.get("returncode") == 0:
                    await self._update_scheduler_status(
                        task_id=task_id,
                        status="ok",
                        agent=agent,
                        dispatch_round=dispatch_round,
                        attempts=int(result.get("attempts", 1)),
                        extra={"errorType": result.get("error_type", "ok")},
                    )
                    log.info(f"✅ Agent '{agent}' completed task {task_id}")
                    # Agent 完成后自动推进状态（如果 agent 没自己推进）
                    await self._auto_advance_if_needed(task_id, state, agent)
                else:
                    await self._update_scheduler_status(
                        task_id=task_id,
                        status="failed",
                        agent=agent,
                        dispatch_round=dispatch_round,
                        attempts=int(result.get("attempts", 1)),
                        extra={"errorType": result.get("error_type", "unknown")},
                    )
                    log.warning(
                        f"⚠️ Agent '{agent}' returned non-zero for task {task_id}: "
                        f"rc={result.get('returncode')} type={result.get('error_type')}"
                    )
                    # 失败写入 DLQ，避免无限重投
                    await self.bus.publish(
                        topic=TOPIC_TASK_DISPATCH_DEAD_LETTER,
                        trace_id=trace_id,
                        event_type="task.dispatch.dead_letter",
                        producer="dispatcher",
                        payload={
                            "task_id": task_id,
                            "agent": agent,
                            "state": state,
                            "dispatch_round": dispatch_round,
                            "message": message,
                            "return_code": result.get("returncode"),
                            "error_type": result.get("error_type", "unknown"),
                            "stderr": result.get("stderr", "")[:1000],
                            "attempts": result.get("attempts", 1),
                        },
                    )

                # ACK — 事件处理完毕
                await self.bus.ack(TOPIC_TASK_DISPATCH, GROUP, entry_id)

            except Exception as e:
                # 处理失败 → 回滚去重标记，允许重新投递时再次处理
                await self._clear_dispatch_dedup(payload)
                await self._update_scheduler_status(
                    task_id=task_id,
                    status="failed",
                    agent=agent,
                    dispatch_round=dispatch_round,
                    extra={"errorType": "worker_exception", "error": str(e)[:300]},
                )
                log.error(f"❌ Dispatch failed: task {task_id} → {agent}: {e}", exc_info=True)
                # 不 ACK → Redis 会重新投递给其他消费者
            finally:
                clear_trace_context()

    # ── 自动状态推进 ──

    # Agent 完成后的默认下一步
    # 注意：YuLan 不在此表中 — 需要皇上手动准奏/封驳，不自动推进
    _NEXT_STATE_MAP = {
        TaskState.Pending: TaskState.Taizi,
        TaskState.Taizi: TaskState.Zhongshu,
        TaskState.Zhongshu: TaskState.Menxia,
        TaskState.Menxia: TaskState.YuLan,
        # YuLan → 需皇上御批，不自动推进
        TaskState.Assigned: TaskState.Doing,
        TaskState.Next: TaskState.Doing,
        TaskState.Doing: TaskState.Review,
        TaskState.Review: TaskState.Done,
        # 与兼容层 advance-state 保持一致：Blocked 恢复时默认回到 Taizi 重新分拣
        TaskState.Blocked: TaskState.Taizi,
    }

    async def _auto_advance_if_needed(self, task_id: str, dispatch_state: str, agent: str):
        """Agent 完成后，如果任务状态仍停在派发时的状态，自动推进到下一步。

        如果 agent 自己通过 kanban_update 推进了状态，这里会发现当前状态已不同，跳过。
        """
        try:
            async with async_session() as db:
                task = await db.get(Task, task_id)
                if not task:
                    return
                current_state = task.state if isinstance(task.state, TaskState) else TaskState(task.state)
                dispatch_enum = TaskState(dispatch_state) if isinstance(dispatch_state, str) else dispatch_state

                # Agent 已经自己推进了状态 → 不重复推进
                if current_state != dispatch_enum:
                    log.debug(f"Auto-advance skip: {task_id} state already changed {dispatch_state} → {current_state.value}")
                    return

                next_state = self._NEXT_STATE_MAP.get(current_state)
                if not next_state:
                    log.debug(f"Auto-advance skip: {task_id} no next state for {current_state.value}")
                    return

            # 用 TaskService 执行状态转换（会发布事件、记录 flow_log）
            async with async_session() as db:
                svc = TaskService(db=db, event_bus=self.bus)
                await svc.transition_state(
                    task_id=task_id,
                    new_state=next_state,
                    agent=f"auto:{agent}",
                    reason=f"Agent {agent} 执行完成，自动推进",
                )
                log.info(f"⏩ Auto-advance: {task_id} {current_state.value} → {next_state.value}")
        except Exception as e:
            log.warning(f"Auto-advance failed for {task_id}: {e}")

    # ── Scheduler ──

    async def _update_scheduler_status(
        self,
        task_id: str,
        status: str,
        agent: str,
        dispatch_round: int,
        attempts: int | None = None,
        extra: dict | None = None,
    ):
        """回写 scheduler 状态，供 /api/scheduler-state 与前端展示。"""
        if not task_id:
            return
        try:
            async with async_session() as db:
                task = await db.get(Task, task_id)
                if not task:
                    return
                raw_scheduler = task.scheduler
                scheduler: dict[str, Any] = dict(raw_scheduler) if isinstance(raw_scheduler, dict) else {}
                scheduler["lastDispatchStatus"] = status
                scheduler["lastDispatchAt"] = datetime.now(timezone.utc).isoformat()
                scheduler["lastDispatchAgent"] = agent
                scheduler["lastDispatchRound"] = int(dispatch_round or 1)
                if status != "skipped":
                    scheduler.pop("reason", None)
                if attempts is not None:
                    scheduler["lastDispatchAttempts"] = int(attempts)
                if status in ("failed", "timeout", "rate_limit", "network"):
                    scheduler["retryCount"] = int(scheduler.get("retryCount", 0) or 0) + 1
                if extra:
                    scheduler.update(extra)
                task.scheduler = scheduler
                await db.commit()
        except Exception as e:
            # 观测写入失败不阻断主派发链路
            log.debug("scheduler status update skipped: %s", e)

    def _classify_error(self, returncode: int, stderr: str) -> str:
        text = (stderr or "").lower()
        if returncode == 0:
            return "ok"
        if "rate limit" in text or "too many requests" in text or "429" in text:
            return "rate_limit"
        # Check network errors before generic timeout — "gateway timeout" is network
        if (
            "connection" in text
            or "network" in text
            or "temporarily unavailable" in text
            or "gateway timeout" in text
        ):
            return "network"
        if "timeout" in text or "timed out" in text:
            return "timeout"
        if "empty agent reply" in text or "no reply from agent" in text:
            return "business_error"
        # 参数错误、未知模型、认证错误等都视为业务错误，不做盲重试
        return "business_error"

    async def _load_task_context(self, task_id: str) -> dict:
        """从 DB 加载任务的完整上下文，供 prompt 拼装。"""
        try:
            async with async_session() as db:
                task = await db.get(Task, task_id)
                if task:
                    # 提取前序 agent 产出摘要（最近 5 条 progress_log）
                    progress_log = list(getattr(task, "progress_log", None) or [])
                    prior_outputs = []
                    for p in progress_log[-5:]:
                        agent = p.get("agent", "")
                        content = p.get("content", "")
                        details = p.get("details", {})
                        todo_detail = details.get("todo_detail", "")
                        text = todo_detail or content
                        if text:
                            prior_outputs.append(f"[{agent}] {text[:500]}")

                    return {
                        "title": str(getattr(task, "title", "") or ""),
                        "description": str(getattr(task, "now", "") or ""),
                        "priority": str(getattr(task, "priority", "") or ""),
                        "prior_outputs": prior_outputs,
                    }
        except Exception as e:
            log.warning("Failed to load task context for %s: %s", task_id, e)
        return {}

    def _compose_dispatch_message(
        self,
        *,
        task_id: str,
        state: str,
        agent: str,
        original_message: str,
        task_context: dict | None = None,
    ) -> str:
        """统一派发提示词，包含完整任务上下文和前序产出。"""
        ctx = task_context or {}
        title = ctx.get("title", "")
        description = ctx.get("description", "")
        priority = ctx.get("priority", "")
        prior_outputs = ctx.get("prior_outputs", [])

        core = (original_message or "").strip() or "请处理当前任务。"

        parts = [
            f"任务ID: {task_id}",
            f"当前状态: {state}",
            f"执行官: {agent}",
        ]
        if title:
            parts.append(f"任务标题: {title}")
        if priority:
            parts.append(f"优先级: {priority}")
        parts.append(f"派发说明: {core}")
        if description:
            parts.append(f"\n## 任务详情/补充材料\n\n{description}")

        # 注入前序 agent 产出，让当前 agent 知道前面做了什么
        if prior_outputs:
            parts.append("\n## 前序处理记录\n")
            for output in prior_outputs:
                parts.append(f"- {output}")

        parts.append(
            "\n---\n请根据你的 SOUL.md 中对当前状态的职责定义执行。以中文直接回复，至少包含：\n"
            "1) 已接旨\n"
            "2) 任务理解（基于当前状态你应该做什么）\n"
            "3) 具体产出\n"
            "若信息不足，请明确列出缺失信息；禁止空回复。"
        )
        return "\n".join(parts)

    async def _backfill_task_output(self, task_id: str, agent: str, normalized: dict):
        """Sprint2 兜底：回填 output/progress，保证 UI 可见每步产出。"""
        async with async_session() as db:
            task = await db.get(Task, task_id)
            if not task:
                return

            summary = normalized.get("summary", "")
            output = normalized.get("output", "")
            ok = bool(normalized.get("ok", False))
            todo_detail = normalized.get("todo_detail", "") or summary

            # 产物兜底：将本轮文本输出固化为可下载文件（长期可追溯）
            artifacts = list(normalized.get("artifacts", []) or [])
            text_for_file = (output or summary or "").strip()
            if text_for_file:
                p = self._persist_text_artifact(task_id=task_id, agent=agent, text=text_for_file)
                if p:
                    artifacts.append({"kind": "markdown", "path": p})

            # progress_log 追加一条结构化记录
            progress_log = list(task.progress_log or [])
            progress_log.append(
                {
                    "agent": agent,
                    "content": summary,
                    "ts": datetime.now(timezone.utc).isoformat(),
                    "details": {
                        "ok": ok,
                        "todo_detail": todo_detail,
                        "artifacts": artifacts,
                        "retry": normalized.get("retry", {}),
                    },
                }
            )
            task.progress_log = progress_log

            # 将本轮摘要回填到一个可编辑 todo.detail（优先 in-progress，其次 not-started）
            if todo_detail:
                todos = list(task.todos or [])
                target_idx = None
                for i, td in enumerate(todos):
                    if td.get("status") in ("in-progress", "in_progress"):
                        target_idx = i
                        break
                if target_idx is None:
                    for i, td in enumerate(todos):
                        if td.get("status") in ("not-started", "not_started", "pending", "todo"):
                            target_idx = i
                            break
                if target_idx is not None:
                    cur = dict(todos[target_idx])
                    if cur.get("detail") != todo_detail:
                        cur["detail"] = todo_detail
                        todos[target_idx] = cur
                        task.todos = todos

            # output 空时填最小可见正文
            if not (task.output or "").strip() and output:
                task.output = output[:4000]

            # Done/Cancelled 一致性收敛：todos 全部置 completed
            st = task.state if isinstance(task.state, TaskState) else TaskState(task.state)
            if st in (TaskState.Done, TaskState.Cancelled):
                fixed = []
                changed = False
                for td in list(task.todos or []):
                    status = td.get("status")
                    if status != "completed":
                        td = {**td, "status": "completed"}
                        changed = True
                    fixed.append(td)
                if changed:
                    task.todos = fixed

            await db.commit()

    def _persist_text_artifact(self, task_id: str, agent: str, text: str) -> str | None:
        """将输出文本持久化到 /app/data/artifacts/<task_id>/ 下。"""
        try:
            base = Path("/app/data/artifacts") / task_id
            base.mkdir(parents=True, exist_ok=True)
            ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
            fn = f"{ts}-{agent}.md"
            fp = base / fn
            fp.write_text(text, encoding="utf-8")
            return str(fp)
        except Exception as e:
            log.debug("persist artifact skipped: %s", e)
            return None

    async def _call_openclaw_with_retry(
        self,
        agent: str,
        message: str,
        task_id: str,
        trace_id: str,
        dispatch_round: int,
    ) -> dict:
        """分级重试策略：rate_limit/timeout/network 重试，business_error 直接失败。"""
        retry_policy = {
            "rate_limit": 4,
            "timeout": 3,
            "network": 3,
            "business_error": 1,
            "ok": 1,
        }

        attempt = 0
        last_result: dict = {
            "returncode": -1,
            "stdout": "",
            "stderr": "UNKNOWN",
            "error_type": "business_error",
        }

        while True:
            attempt += 1
            result = await self._call_openclaw_once(agent, message, task_id, trace_id)
            err_type = self._classify_error(result.get("returncode", -1), result.get("stderr", ""))
            result["error_type"] = err_type
            if err_type != "ok": set_trace_context(error_code=err_type)
            result["attempts"] = attempt
            last_result = result

            if err_type == "ok":
                return result

            max_attempts = retry_policy.get(err_type, 1)
            if attempt >= max_attempts:
                return result

            # 指数退避 + 抖动（上限 30s）
            base = min(2 ** (attempt - 1), 30)
            jitter = random.uniform(0.1, 0.8)
            delay = base + jitter
            log.warning(
                "🔁 dispatch retry task=%s agent=%s round=%s attempt=%s/%s type=%s delay=%.2fs",
                task_id,
                agent,
                dispatch_round,
                attempt,
                max_attempts,
                err_type,
                delay,
            )
            metrics = get_metrics()
            metrics.inc("dispatch_retry_total", labels={"error_type": err_type})
            if err_type == "rate_limit":
                metrics.inc("rate_limit_total")
            await asyncio.sleep(delay)

    async def _call_openclaw_once(
        self,
        agent: str,
        message: str,
        task_id: str,
        trace_id: str,
    ) -> dict:
        """单次调用 OpenClaw CLI — 在线程池中执行。"""
        settings = get_settings()
        cmd = [
            "openclaw", "agent",
            "--local",
            "--agent", agent,
            "-m", message,
            "--json",
        ]

        env = os.environ.copy()
        env["EDICT_TASK_ID"] = task_id
        env["EDICT_TRACE_ID"] = trace_id
        env["EDICT_API_URL"] = f"http://localhost:{settings.port}"

        log.debug(f"Executing: {' '.join(cmd)}")

        def _run():
            try:
                proc = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=300,
                    env=env,
                    cwd=settings.openclaw_project_dir or None,
                )
                stdout = proc.stdout or ""
                stderr = proc.stderr or ""

                # 优先解析 --json 输出中的 payload text
                parsed_text = ""
                try:
                    payload = json.loads(stdout) if stdout.strip().startswith("{") else None
                    if isinstance(payload, dict):
                        texts = []
                        for item in payload.get("payloads", []) or []:
                            if isinstance(item, dict) and item.get("text"):
                                texts.append(str(item.get("text")))
                        parsed_text = "\n".join(t.strip() for t in texts if t and t.strip())
                except Exception:
                    parsed_text = ""

                if proc.returncode == 0 and not parsed_text.strip():
                    # 明确空回复为失败，避免假成功
                    return {
                        "returncode": 2,
                        "stdout": "",
                        "stderr": (stderr + "\nEMPTY_AGENT_REPLY").strip(),
                    }

                return {
                    "returncode": proc.returncode,
                    "stdout": (parsed_text or stdout)[-5000:] if (parsed_text or stdout) else "",
                    "stderr": stderr[-2000:] if stderr else "",
                }
            except subprocess.TimeoutExpired:
                return {"returncode": -1, "stdout": "", "stderr": "TIMEOUT after 300s"}
            except FileNotFoundError:
                return {"returncode": -1, "stdout": "", "stderr": "openclaw command not found"}

        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, _run)


async def run_dispatcher():
    """入口函数 — 用于直接运行 worker。"""
    setup_structured_logging()
    worker = DispatchWorker()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(worker.stop()))

    await worker.start()


if __name__ == "__main__":
    asyncio.run(run_dispatcher())
