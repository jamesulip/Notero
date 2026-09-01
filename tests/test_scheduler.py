"""Scheduler fairness, drop policy and admission control."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

from server.adapters.base import ASRAdapter, Result, Token  # noqa: E402
from server.scheduler import InferenceScheduler, SessionLimitReached  # noqa: E402


class SlowAdapter(ASRAdapter):
    def __init__(self, delay: float = 0.05) -> None:
        self.delay = delay
        self.seen: list[bytes] = []

    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    async def transcribe(self, pcm, language, prompt=None):
        await asyncio.sleep(self.delay)
        self.seen.append(pcm)
        return Result([Token(pcm.decode(), 0, 100)], audio_ms=100, infer_ms=1)


@pytest.mark.asyncio
async def test_superseded_hop_is_dropped_not_queued():
    """Section 5: a stale partial is worse than a missing one."""
    adapter = SlowAdapter(delay=0.01)
    sched = InferenceScheduler(adapter)
    sched.register("s1")

    # Queue both before the worker runs. Supersession applies to hops that have
    # not started; a hop already inside the model cannot be un-run.
    first = asyncio.create_task(sched.submit("s1", b"old", "tl"))
    second = asyncio.create_task(sched.submit("s1", b"new", "tl"))
    await asyncio.sleep(0)
    await sched.start()

    results = await asyncio.gather(first, second)
    await sched.stop()

    # Exactly one of them ran, and it was the newer audio.
    assert sched.stats.dropped_superseded == 1
    assert b"old" not in adapter.seen
    assert b"new" in adapter.seen
    assert None in results


@pytest.mark.asyncio
async def test_sessions_are_served_round_robin():
    """A busy session must not starve a quiet one."""
    adapter = SlowAdapter(delay=0.01)
    sched = InferenceScheduler(adapter)
    await sched.start()
    for sid in ("a", "b", "c"):
        sched.register(sid)

    await asyncio.gather(
        sched.submit("a", b"a", "tl"),
        sched.submit("b", b"b", "tl"),
        sched.submit("c", b"c", "tl"),
    )
    await sched.stop()
    assert sorted(x.decode() for x in adapter.seen) == ["a", "b", "c"]


@pytest.mark.asyncio
async def test_capacity_is_enforced():
    sched = InferenceScheduler(SlowAdapter(), max_sessions=2)
    sched.register("a")
    sched.register("b")
    with pytest.raises(SessionLimitReached):
        sched.register("c")
    assert sched.stats.rejected_sessions == 1

    sched.unregister("a")
    sched.register("c")            # a slot freed up
    assert sched.active_sessions == 2


@pytest.mark.asyncio
async def test_unregister_releases_a_waiting_hop():
    """A client that disconnects mid-hop must not leave the caller hanging."""
    sched = InferenceScheduler(SlowAdapter(delay=0.3))
    await sched.start()
    sched.register("s1")
    pending = asyncio.create_task(sched.submit("s1", b"x", "tl"))
    await asyncio.sleep(0.01)
    sched.unregister("s1")
    assert await asyncio.wait_for(pending, timeout=1) is None
    await sched.stop()
