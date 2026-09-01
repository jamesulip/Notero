"""Shared inference scheduler.

There is one model instance, so hops from every session contend for it. Section
5 sets the policy: per-session backpressure, and if a hop cannot be served
before the next arrives, **drop the older request** rather than queueing --
a stale partial is worse than a missing one.

Two things this adds over letting each session call the adapter directly:

  * Fairness. A FIFO queue lets a busy session starve a quiet one, because the
    busy session enqueues faster. Serving sessions round-robin bounds the wait
    by the number of *active* sessions rather than by queue depth.
  * A real drop. A request that has not started yet is replaced in place when a
    newer one arrives for the same session, so the model never spends time on
    audio that has already been superseded.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field

from .adapters.base import ASRAdapter, Result

log = logging.getLogger("asr.scheduler")


class SessionLimitReached(RuntimeError):
    pass


@dataclass
class _Request:
    session_id: str
    pcm: bytes
    language: str
    prompt: str | None
    future: asyncio.Future
    queued_at: float = field(default_factory=time.monotonic)


@dataclass
class SchedulerStats:
    served: int = 0
    dropped_superseded: int = 0
    rejected_sessions: int = 0
    max_wait_ms: int = 0


class InferenceScheduler:
    def __init__(self, adapter: ASRAdapter, max_sessions: int = 3) -> None:
        self.adapter = adapter
        self.max_sessions = max_sessions
        self.stats = SchedulerStats()
        self._pending: dict[str, _Request] = {}
        self._inflight: dict[str, _Request] = {}
        self._order: list[str] = []          # round-robin cursor over session ids
        self._registered: set[str] = set()
        self._wake = asyncio.Event()
        self._worker: asyncio.Task | None = None
        self._running = False

    # -- lifecycle ---------------------------------------------------------

    async def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._worker = asyncio.create_task(self._run())

    async def stop(self) -> None:
        self._running = False
        self._wake.set()
        if self._worker is not None:
            await asyncio.gather(self._worker, return_exceptions=True)
            self._worker = None
        for store in (self._pending, self._inflight):
            for request in store.values():
                if not request.future.done():
                    request.future.set_result(None)
            store.clear()

    # -- admission ---------------------------------------------------------

    def register(self, session_id: str) -> None:
        if session_id in self._registered:
            return
        if len(self._registered) >= self.max_sessions:
            self.stats.rejected_sessions += 1
            raise SessionLimitReached(
                f"at capacity ({self.max_sessions} concurrent sessions)"
            )
        self._registered.add(session_id)
        self._order.append(session_id)

    def unregister(self, session_id: str) -> None:
        self._registered.discard(session_id)
        if session_id in self._order:
            self._order.remove(session_id)
        # Release both the queued hop and any hop already running. The running
        # one cannot be un-run -- the model is mid-inference -- but the caller
        # is gone, so leaving its future unresolved would hang the coroutine
        # awaiting it for the lifetime of the process.
        for store in (self._pending, self._inflight):
            request = store.pop(session_id, None)
            if request is not None and not request.future.done():
                request.future.set_result(None)

    @property
    def active_sessions(self) -> int:
        return len(self._registered)

    # -- submission --------------------------------------------------------

    async def submit(
        self,
        session_id: str,
        pcm: bytes,
        language: str,
        prompt: str | None = None,
    ) -> Result | None:
        """Queues a hop. Returns None if it was superseded before it ran."""
        if session_id not in self._registered:
            raise SessionLimitReached(f"session {session_id} is not registered")

        superseded = self._pending.get(session_id)
        if superseded is not None and not superseded.future.done():
            superseded.future.set_result(None)
            self.stats.dropped_superseded += 1

        future: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[session_id] = _Request(
            session_id=session_id, pcm=pcm, language=language,
            prompt=prompt, future=future,
        )
        self._wake.set()
        return await future

    # -- worker ------------------------------------------------------------

    async def _run(self) -> None:
        while self._running:
            request = self._next_request()
            if request is None:
                self._wake.clear()
                try:
                    await asyncio.wait_for(self._wake.wait(), timeout=0.5)
                except asyncio.TimeoutError:
                    pass
                continue

            waited_ms = int((time.monotonic() - request.queued_at) * 1000)
            self.stats.max_wait_ms = max(self.stats.max_wait_ms, waited_ms)
            self._inflight[request.session_id] = request
            try:
                result = await self.adapter.transcribe(
                    request.pcm, request.language, request.prompt
                )
                self.stats.served += 1
                if not request.future.done():
                    request.future.set_result(result)
            except Exception as exc:
                if not request.future.done():
                    request.future.set_exception(exc)
            finally:
                self._inflight.pop(request.session_id, None)

    def _next_request(self) -> _Request | None:
        """Round-robin over sessions that have something waiting."""
        for _ in range(len(self._order)):
            session_id = self._order[0]
            self._order.append(self._order.pop(0))   # rotate
            request = self._pending.pop(session_id, None)
            if request is not None and not request.future.done():
                return request
        return None
