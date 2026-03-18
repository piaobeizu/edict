"""Redis Streams EventBusPort 实现 — 桥接 kernel 接口 ↔ 现有 EventBus。"""

from __future__ import annotations

from typing import Any

from app.services.event_bus import EventBus as RedisEventBus


class RedisEventBusAdapter:
    """实现 kernel.ports.EventBusPort，委托给现有 RedisEventBus。

    这是一个薄适配层，让现有 Redis 实现满足 kernel 接口约束。
    """

    def __init__(self, bus: RedisEventBus):
        self._bus = bus

    async def publish(
        self,
        topic: str,
        trace_id: str,
        event_type: str,
        producer: str,
        payload: dict[str, Any] | None = None,
    ) -> str:
        return await self._bus.publish(
            topic=topic,
            trace_id=trace_id,
            event_type=event_type,
            producer=producer,
            payload=payload,
        )

    async def consume(
        self,
        topic: str,
        group: str,
        consumer: str,
        count: int = 10,
        block_ms: int = 5000,
    ) -> list[tuple[str, dict[str, Any]]]:
        return await self._bus.consume(topic, group, consumer, count, block_ms)

    async def ack(self, topic: str, group: str, entry_id: str) -> None:
        await self._bus.ack(topic, group, entry_id)

    async def claim_stale(
        self,
        topic: str,
        group: str,
        consumer: str,
        min_idle_ms: int = 60000,
        count: int = 10,
    ) -> list[tuple[str, dict[str, Any]]]:
        return await self._bus.claim_stale(topic, group, consumer, min_idle_ms, count)
