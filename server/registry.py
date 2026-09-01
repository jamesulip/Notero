"""Keeps sessions alive across a dropped connection.

Section 8: the client buffers ~30 s of audio while disconnected and dedupes by
segment id, so the server can safely replay its segment tail. That only works
if the server still has the session -- its committed text, its ring buffer and
its place on the timeline -- when the client comes back.

Sessions are held for `grace_seconds` after a disconnect and then reaped. The
reaper matters: a WAV archiver and a 15 s ring buffer per session is real
memory, and phones drop connections constantly without ever coming back.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field

log = logging.getLogger("asr.registry")


@dataclass
class Entry:
    pipeline: object
    detached_at: float | None = None
    segments: list[dict] = field(default_factory=list)


class SessionRegistry:
    def __init__(self, grace_seconds: float = 120.0) -> None:
        self.grace_seconds = grace_seconds
        self._entries: dict[str, Entry] = {}
        self._reaper: asyncio.Task | None = None

    def start_reaper(self) -> None:
        if self._reaper is None:
            self._reaper = asyncio.create_task(self._reap_loop())

    async def stop_reaper(self) -> None:
        if self._reaper is not None:
            self._reaper.cancel()
            await asyncio.gather(self._reaper, return_exceptions=True)
            self._reaper = None

    def get(self, session_id: str) -> Entry | None:
        return self._entries.get(session_id)

    def put(self, session_id: str, pipeline) -> Entry:
        entry = Entry(pipeline=pipeline)
        self._entries[session_id] = entry
        return entry

    def attach(self, session_id: str) -> None:
        entry = self._entries.get(session_id)
        if entry is not None:
            entry.detached_at = None

    def detach(self, session_id: str) -> None:
        entry = self._entries.get(session_id)
        if entry is not None:
            entry.detached_at = time.monotonic()

    def drop(self, session_id: str) -> Entry | None:
        return self._entries.pop(session_id, None)

    def expired(self) -> list[str]:
        now = time.monotonic()
        return [
            sid for sid, e in self._entries.items()
            if e.detached_at is not None and now - e.detached_at > self.grace_seconds
        ]

    async def _reap_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(5)
                for session_id in self.expired():
                    log.info("reaping abandoned session %s", session_id)
                    entry = self._entries.pop(session_id, None)
                    on_reap = getattr(entry.pipeline, "on_reap", None) if entry else None
                    if on_reap is not None:
                        try:
                            await on_reap()
                        except Exception:
                            log.exception("reaping %s failed", session_id)
        except asyncio.CancelledError:
            pass
