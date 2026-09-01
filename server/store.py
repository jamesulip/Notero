"""SQLite persistence. Committed segments are the single source of truth.

Schema follows section 10's Phase 4 spec, including the two diarization hooks
that cost nothing now and save a migration later: `speaker_id` is nullable and
always null until Phase 6, and `text_clean` holds the Phase 5 cleanup output so
raw ASR is never overwritten.
"""

from __future__ import annotations

import asyncio
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id           TEXT PRIMARY KEY,
    started_at   TEXT NOT NULL,
    ended_at     TEXT,
    language     TEXT NOT NULL,
    prompt       TEXT,
    audio_path   TEXT,
    duration_ms  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS segments (
    session_id   TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    id           INTEGER NOT NULL,
    start_ms     INTEGER NOT NULL,
    end_ms       INTEGER NOT NULL,
    text         TEXT NOT NULL,
    text_clean   TEXT,
    speaker_id   TEXT,
    committed_at TEXT NOT NULL,
    PRIMARY KEY (session_id, id)
);

CREATE INDEX IF NOT EXISTS segments_by_time
    ON segments (session_id, start_ms);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


@dataclass(frozen=True)
class SegmentRow:
    id: int
    start_ms: int
    end_ms: int
    text: str
    text_clean: str | None
    speaker_id: str | None

    @property
    def display_text(self) -> str:
        """Cleaned text when it exists, raw otherwise. Exports use this."""
        return self.text_clean or self.text


class Store:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.executescript(SCHEMA)
        self._conn.commit()
        self._lock = asyncio.Lock()

    def close(self) -> None:
        self._conn.close()

    # -- writes ------------------------------------------------------------

    async def create_session(self, session_id: str, language: str,
                             prompt: str | None, audio_path: str | None) -> None:
        async with self._lock:
            await asyncio.to_thread(self._create_session, session_id, language,
                                    prompt, audio_path)

    def _create_session(self, session_id, language, prompt, audio_path) -> None:
        self._conn.execute(
            "INSERT OR IGNORE INTO sessions (id, started_at, language, prompt, audio_path)"
            " VALUES (?,?,?,?,?)",
            (session_id, _now(), language, prompt, audio_path),
        )
        self._conn.commit()

    async def add_segment(self, session_id: str, segment_id: int, start_ms: int,
                          end_ms: int, text: str) -> None:
        async with self._lock:
            await asyncio.to_thread(self._add_segment, session_id, segment_id,
                                    start_ms, end_ms, text)

    def _add_segment(self, session_id, segment_id, start_ms, end_ms, text) -> None:
        self._conn.execute(
            "INSERT OR REPLACE INTO segments"
            " (session_id, id, start_ms, end_ms, text, committed_at)"
            " VALUES (?,?,?,?,?,?)",
            (session_id, segment_id, start_ms, end_ms, text, _now()),
        )
        self._conn.commit()

    async def finish_session(self, session_id: str, duration_ms: int) -> None:
        async with self._lock:
            await asyncio.to_thread(self._finish_session, session_id, duration_ms)

    def _finish_session(self, session_id, duration_ms) -> None:
        self._conn.execute(
            "UPDATE sessions SET ended_at=?, duration_ms=? WHERE id=?",
            (_now(), duration_ms, session_id),
        )
        self._conn.commit()

    async def set_clean_text(self, session_id: str, segment_id: int, clean: str) -> None:
        async with self._lock:
            await asyncio.to_thread(self._set_clean_text, session_id, segment_id, clean)

    def _set_clean_text(self, session_id, segment_id, clean) -> None:
        self._conn.execute(
            "UPDATE segments SET text_clean=? WHERE session_id=? AND id=?",
            (clean, session_id, segment_id),
        )
        self._conn.commit()

    async def set_speaker(self, session_id: str, segment_id: int, speaker: str) -> None:
        """Phase 6 hook. Unused until diarization lands."""
        async with self._lock:
            await asyncio.to_thread(self._set_speaker, session_id, segment_id, speaker)

    def _set_speaker(self, session_id, segment_id, speaker) -> None:
        self._conn.execute(
            "UPDATE segments SET speaker_id=? WHERE session_id=? AND id=?",
            (speaker, session_id, segment_id),
        )
        self._conn.commit()

    async def delete_session(self, session_id: str) -> str | None:
        """Removes a session and its segments. Returns its audio path, if any."""
        async with self._lock:
            return await asyncio.to_thread(self._delete_session, session_id)

    def _delete_session(self, session_id) -> str | None:
        row = self._conn.execute(
            "SELECT audio_path FROM sessions WHERE id=?", (session_id,)
        ).fetchone()
        self._conn.execute("DELETE FROM segments WHERE session_id=?", (session_id,))
        self._conn.execute("DELETE FROM sessions WHERE id=?", (session_id,))
        self._conn.commit()
        return row["audio_path"] if row else None

    # -- reads -------------------------------------------------------------

    def list_sessions(self) -> list[dict]:
        rows = self._conn.execute(
            "SELECT s.*, (SELECT COUNT(*) FROM segments g WHERE g.session_id=s.id)"
            " AS segment_count FROM sessions s ORDER BY s.started_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]

    def get_session(self, session_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT * FROM sessions WHERE id=?", (session_id,)
        ).fetchone()
        return dict(row) if row else None

    def get_segments(self, session_id: str) -> list[SegmentRow]:
        rows = self._conn.execute(
            "SELECT id, start_ms, end_ms, text, text_clean, speaker_id"
            " FROM segments WHERE session_id=? ORDER BY start_ms, id",
            (session_id,),
        ).fetchall()
        return [SegmentRow(**dict(r)) for r in rows]

    def sessions_older_than(self, days: int) -> list[dict]:
        cutoff = datetime.now(timezone.utc).timestamp() - days * 86400
        out = []
        for row in self.list_sessions():
            try:
                started = datetime.fromisoformat(row["started_at"]).timestamp()
            except (TypeError, ValueError):
                continue
            if started < cutoff:
                out.append(row)
        return out
