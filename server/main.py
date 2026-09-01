"""FastAPI orchestrator -- Phases 1 through 5.

Live path:  ring buffer -> VAD -> scheduler -> ASR -> LocalAgreement -> events
Persistence: committed segments to SQLite, session audio to WAV
Offline:     export renderers, and an LLM cleanup pass over finalized text

The partial/final split is the protocol half of section 8's design contract:
`partial` may be replaced at any time, `final` never is.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles

from .adapters.base import ASRAdapter, Token
from .adapters.whisperkit import DEFAULT_MODEL, MODELS_DIR, WhisperKitAdapter
from .archive import WavArchiver
from .cleanup import CleanupEngine
from .commit import LocalAgreement
from .exports import RENDERERS
from .languages import BY_CODE as LANGUAGES_BY_CODE, DEFAULT as DEFAULT_LANGUAGE
from .languages import catalogue as language_catalogue
from .models import BY_ID, catalogue
from .registry import SessionRegistry
from .scheduler import InferenceScheduler, SessionLimitReached
from .session import Session
from .store import Store
from .vad import SileroVAD

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-5s %(name)s: %(message)s",
)
log = logging.getLogger("asr.server")
metrics = logging.getLogger("asr.metrics")

ROOT = Path(__file__).resolve().parents[1]
CLIENT_DIR = ROOT / "client"
STATIC_DIR = CLIENT_DIR / "public"
DATA_DIR = ROOT / "data"
AUDIO_DIR = DATA_DIR / "audio"

# A session id becomes a filename under AUDIO_DIR, a SQLite key and a
# Content-Disposition header. Anything outside this alphabet is an attack,
# not a client bug: "../../x" writes and deletes WAVs outside the archive.
SESSION_ID_RE = re.compile(r"[A-Za-z0-9_-]{1,64}")

adapter: ASRAdapter | None = None
scheduler: InferenceScheduler | None = None
store: Store | None = None
registry = SessionRegistry(grace_seconds=120)
cleanup_engine = CleanupEngine()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global adapter, scheduler, store
    store = Store(DATA_DIR / "sessions.db")
    adapter = WhisperKitAdapter(model=os.environ.get("ASR_MODEL", DEFAULT_MODEL))
    log.info("loading ASR model %s (first run also downloads it)", adapter.model)
    await adapter.start()
    # Section 7 caps at 3, but Phase 1 measured a 15 s window at ~0.9 s, so one
    # session already uses most of one model instance. Override to explore the
    # degradation curve; see docs/FINDINGS.md.
    scheduler = InferenceScheduler(
        adapter, max_sessions=int(os.environ.get("ASR_MAX_SESSIONS", "3"))
    )
    await scheduler.start()
    registry.start_reaper()
    log.info("ready")
    yield
    await registry.stop_reaper()
    await scheduler.stop()
    await adapter.stop()
    store.close()


app = FastAPI(title="Live Tagalog Transcriber", lifespan=lifespan)


@app.get("/health")
async def health() -> dict:
    return {
        "ok": adapter is not None,
        "model": getattr(adapter, "model", None),
        "load_ms": getattr(adapter, "load_ms", None),
        "active_sessions": scheduler.active_sessions if scheduler else 0,
        "max_sessions": scheduler.max_sessions if scheduler else 0,
        "scheduler": vars(scheduler.stats) if scheduler else {},
    }


class Pipeline:
    """One session's live path."""

    def __init__(self, session: Session, send, agreement: int = 2, vad=None,
                 archiver: WavArchiver | None = None) -> None:
        self.session = session
        self.send = send
        self.vad = vad if vad is not None else SileroVAD()
        self.commit = LocalAgreement(agreement=agreement)
        self.archiver = archiver
        self.segments: list[dict] = []      # emitted finals, for replay on resume
        self._inflight = False
        self._last_partial = ""
        self._tasks: set[asyncio.Task] = set()

    # -- live path ---------------------------------------------------------

    async def feed(self, pcm: bytes) -> None:
        self.session.push_audio(pcm)
        if self.archiver is not None:
            await self.archiver.write(pcm)
        state = self.vad.push(pcm)

        if not self.session.due_for_hop():
            return
        self.session.mark_hop()

        if self._inflight:
            self.session.stats.dropped_hops += 1
            return

        if state.trailing_silence_ms >= self.session.silence_boundary_ms:
            await self._boundary()
            return

        # Off the receive path: awaiting inference here would stall the socket
        # read loop and audio would queue in the transport instead of being
        # dropped, so latency would grow without bound.
        self._inflight = True
        task = asyncio.create_task(self._hop())
        task.add_done_callback(self._hop_finished)
        self._tasks.add(task)

    def _hop_finished(self, task: asyncio.Task) -> None:
        self._inflight = False
        self._tasks.discard(task)
        if not task.cancelled() and task.exception() is not None:
            log.error("hop failed", exc_info=task.exception())

    async def _boundary(self) -> None:
        self.commit.ceiling_ms = self.session.ring.total_ms
        tail = self.commit.flush()
        if tail:
            self.session.stats.boundaries += 1
            self.session.ring.trim_to(self.commit.committed_end_ms)
            self.vad.clear_speech_counter()
            await self._emit_final(tail)
            await self._emit_partial("")
            await self.send({"type": "status", "state": "listening"})
            return
        self.session.stats.skipped_silent += 1

    async def _hop(self) -> None:
        window, window_start_ms = self.session.ring.window()
        if not window:
            return
        self.commit.ceiling_ms = self.session.ring.total_ms

        # The window has slid past the last commit, so audio at its head is
        # about to be discarded unagreed. Commit it now, or the next hypothesis
        # starts at a different word and prefixes stop aligning for good.
        if window_start_ms > self.commit.committed_end_ms:
            forced = self.commit.force_commit_before(window_start_ms)
            if forced:
                self.session.stats.forced_commits += 1
                await self._emit_final(forced)

        await self.send({"type": "status", "state": "processing"})
        try:
            assert scheduler is not None
            result = await scheduler.submit(
                self.session.session_id, window, self.session.language,
                self.session.prompt,
            )
        except Exception as exc:
            log.exception("transcription failed")
            await self.send({"type": "error", "code": "transcribe_failed",
                             "message": str(exc)})
            return
        finally:
            await self.send({"type": "status", "state": "listening"})

        if result is None:          # superseded by a newer hop
            self.session.stats.dropped_hops += 1
            return

        stats = self.session.stats
        stats.hops += 1
        stats.total_audio_ms += result.audio_ms
        stats.total_infer_ms += result.infer_ms

        if not result.tokens:
            stats.empty_results += 1
            log.warning("hop %d returned no text (%d ms window, %d ms inference)"
                        " -- decode threshold likely tripped",
                        stats.hops, result.audio_ms, result.infer_ms)
            return

        absolute = [
            Token(text=t.text,
                  start_ms=window_start_ms + t.start_ms,
                  end_ms=window_start_ms + t.end_ms)
            for t in result.tokens
        ]
        newly = self.commit.insert(absolute)
        if newly:
            self.session.ring.trim_to(self.commit.committed_end_ms)

        metrics.info("hop=%d window_ms=%d infer_ms=%d rtf=%.3f committed=+%d",
                     stats.hops, result.audio_ms, result.infer_ms,
                     result.rtf, len(newly))

        if newly:
            await self._emit_final(newly)
        await self._emit_partial(self.commit.partial)

    # -- events ------------------------------------------------------------

    async def _emit_final(self, tokens: list[Token]) -> None:
        text = "".join(t.text for t in tokens).strip()
        if not text:
            return
        segment = {
            "id": self.session.allocate_segment_id(),
            "text": text,
            "start_ms": tokens[0].start_ms,
            "end_ms": tokens[-1].end_ms,
        }
        self.segments.append(segment)
        if store is not None:
            await store.add_segment(self.session.session_id, segment["id"],
                                    segment["start_ms"], segment["end_ms"], text)
        await self.send({"type": "final", "segment": segment})

    async def _emit_partial(self, text: str) -> None:
        if text == self._last_partial:
            return
        self._last_partial = text
        await self.send({"type": "partial", "text": text,
                         "since_ms": self.commit.committed_end_ms})

    async def replay(self, after_id: int) -> None:
        """Resends finals the client may have missed while disconnected."""
        missed = [s for s in self.segments if s["id"] > after_id]
        for segment in missed:
            await self.send({"type": "final", "segment": segment})
        log.info("session %s resumed: replayed %d segments after id %d",
                 self.session.session_id, len(missed), after_id)

    # -- teardown ----------------------------------------------------------

    async def finish(self) -> None:
        self.commit.ceiling_ms = self.session.ring.total_ms
        if self._tasks:
            await asyncio.gather(*list(self._tasks), return_exceptions=True)
        tail = self.commit.flush()
        if tail:
            await self._emit_final(tail)
        await self._emit_partial("")
        await self.close()

    async def close(self) -> None:
        if self.archiver is not None:
            await self.archiver.close()
        if scheduler is not None:
            scheduler.unregister(self.session.session_id)
        if store is not None:
            await store.finish_session(self.session.session_id,
                                       self.session.ring.total_ms)

    async def on_reap(self) -> None:
        """Called by the registry when the grace period expires.

        The socket is long gone, but the provisional tail is not: whatever
        never reached agreement still has to be flushed to the store, or the
        last utterance of every abandoned session is silently lost. Swap in a
        sink for the transport and run the normal finish path.
        """
        log.info("finalizing abandoned session %s", self.session.session_id)

        async def discard(payload: dict) -> None:
            return None

        self.send = discard
        await self.finish()


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    pipeline: Pipeline | None = None
    session_id: str | None = None

    async def send(payload: dict) -> None:
        await ws.send_text(json.dumps(payload))

    try:
        while True:
            message = await ws.receive()
            if message["type"] == "websocket.disconnect":
                break

            if (text := message.get("text")) is not None:
                try:
                    control = json.loads(text)
                except json.JSONDecodeError:
                    await send({"type": "error", "code": "bad_json",
                                "message": "control frame was not JSON"})
                    continue

                kind = control.get("type")
                if kind == "start":
                    if pipeline is not None:
                        # Silently replacing the session would orphan the old
                        # one: its scheduler slot, archiver handle and ring
                        # buffer are never reaped because it was never detached.
                        await send({"type": "error", "code": "already_started",
                                    "message": "stop the current session before"
                                               " starting another"})
                        continue
                    requested = control.get("session_id")
                    if requested is not None and (
                        not isinstance(requested, str)
                        or SESSION_ID_RE.fullmatch(requested) is None
                    ):
                        await send({"type": "error", "code": "bad_session_id",
                                    "message": "session_id must be 1-64 chars"
                                               " of [A-Za-z0-9_-]"})
                        continue
                    existing = registry.get(requested) if requested else None

                    if existing is not None:
                        # Section 8: resume, and replay the segment tail the
                        # client may have missed. It dedupes by id.
                        pipeline = existing.pipeline
                        session_id = requested
                        pipeline.send = send
                        registry.attach(session_id)
                        await send({"type": "status", "state": "listening"})
                        await pipeline.replay(int(control.get("last_segment_id") or 0))
                        continue

                    if _model_switch.locked():
                        await send({"type": "error", "code": "model_switching",
                                    "message": "a model switch is in progress;"
                                               " retry shortly"})
                        continue

                    session_id = requested or uuid.uuid4().hex[:12]
                    try:
                        assert scheduler is not None
                        scheduler.register(session_id)
                    except SessionLimitReached as exc:
                        await send({"type": "error", "code": "at_capacity",
                                    "message": str(exc)})
                        session_id = None
                        continue

                    requested_language = control.get("language") or DEFAULT_LANGUAGE
                    if requested_language not in LANGUAGES_BY_CODE:
                        await send({"type": "error", "code": "unknown_language",
                                    "message": f"unsupported language "
                                               f"{requested_language!r}"})
                        scheduler.unregister(session_id)
                        session_id = None
                        continue
                    session = Session(
                        session_id=session_id,
                        language=requested_language,
                        prompt=control.get("prompt"),
                    )
                    audio_path = AUDIO_DIR / f"{session_id}.wav"
                    pipeline = Pipeline(session, send,
                                        archiver=WavArchiver(audio_path))
                    registry.put(session_id, pipeline)
                    if store is not None:
                        await store.create_session(session_id, session.language,
                                                   session.prompt, str(audio_path))
                    log.info("session %s started (language=%s, %d ms context, "
                             "%d ms hop)", session_id, session.language,
                             session.context_ms, session.hop_ms)
                    await send({"type": "status", "state": "listening"})

                elif kind == "stop":
                    if pipeline is not None:
                        await pipeline.finish()
                        _log_summary(pipeline)
                        registry.drop(pipeline.session.session_id)
                        pipeline = None
                        session_id = None
                    await send({"type": "status", "state": "idle"})
                else:
                    await send({"type": "error", "code": "unknown_control",
                                "message": f"unknown control type {kind!r}"})
                continue

            pcm = message.get("bytes")
            if pcm is None:
                continue
            if pipeline is None:
                await send({"type": "error", "code": "no_session",
                            "message": "send a start control frame first"})
                continue
            await pipeline.feed(pcm)

    except WebSocketDisconnect:
        pass
    finally:
        # Keep the session alive for the grace period so a reconnect can resume.
        if session_id is not None:
            registry.detach(session_id)
            log.info("session %s detached; resumable for %.0fs",
                     session_id, registry.grace_seconds)


def _log_summary(pipeline: Pipeline) -> None:
    s = pipeline.session.stats
    log.info("session %s ended: %d hops, %d silent, %d dropped, %d empty, "
             "%d boundaries, %d forced, mean RTF %.3f",
             pipeline.session.session_id, s.hops, s.skipped_silent,
             s.dropped_hops, s.empty_results, s.boundaries, s.forced_commits,
             s.mean_rtf)


# -- session browsing, exports, cleanup, retention -------------------------

def _require_store() -> Store:
    if store is None:
        raise HTTPException(503, "store not ready")
    return store


_model_switch = asyncio.Lock()


@app.get("/models")
async def list_models() -> dict:
    return {
        "current": getattr(adapter, "model", None),
        "models": catalogue(MODELS_DIR, getattr(adapter, "model", None)),
    }


@app.get("/languages")
async def list_languages() -> dict:
    return {"default": DEFAULT_LANGUAGE,
            "languages": language_catalogue(DEFAULT_LANGUAGE)}


@app.post("/models/select")
async def select_model(model: str, allow_english_only: bool = False) -> dict:
    """Swaps the ASR model. Blocks until the new one is loaded.

    Refused while any session is live: the model is shared, and swapping it
    underneath a session would splice two different models' output into one
    transcript with no record of where the seam is.
    """
    global adapter

    if model not in BY_ID:
        raise HTTPException(404, f"unknown model {model!r}")
    info = BY_ID[model]
    if not info.multilingual and not allow_english_only:
        raise HTTPException(
            400,
            f"{info.label} is English-only and will translate Tagalog rather "
            f"than transcribe it. Pass allow_english_only=true to override.",
        )
    if scheduler is None:
        raise HTTPException(503, "scheduler not ready")
    if _model_switch.locked():
        raise HTTPException(409, "a model switch is already in progress")

    async with _model_switch:
        # Checked *inside* the lock, and the websocket start handler refuses
        # new sessions while the lock is held. Checking before acquiring left
        # a window the length of a 1.6 GB model load in which a session could
        # start and then have the model swapped underneath it.
        if scheduler.active_sessions:
            raise HTTPException(
                409,
                f"{scheduler.active_sessions} session(s) still live; "
                f"stop them first",
            )
        if getattr(adapter, "model", None) == model:
            return {"current": model, "changed": False}

        previous = adapter
        log.info("switching ASR model to %s", model)
        replacement = WhisperKitAdapter(model=model)
        try:
            await replacement.start()
        except Exception as exc:
            log.exception("failed to load %s; keeping %s", model,
                          getattr(previous, "model", None))
            raise HTTPException(500, f"could not load {model}: {exc}") from exc

        # Only tear the old one down once the new one is actually up, so a
        # failed switch leaves a working server rather than no model at all.
        adapter = replacement
        scheduler.adapter = replacement
        if previous is not None:
            await previous.stop()

    return {"current": model, "changed": True,
            "load_ms": getattr(adapter, "load_ms", None)}


@app.get("/sessions")
async def list_sessions() -> list[dict]:
    return _require_store().list_sessions()


@app.get("/sessions/{session_id}")
async def get_session(session_id: str) -> dict:
    db = _require_store()
    session = db.get_session(session_id)
    if session is None:
        raise HTTPException(404, "no such session")
    segments = db.get_segments(session_id)
    return {"session": session, "segments": [vars(s) for s in segments]}


@app.get("/sessions/{session_id}/export/{fmt}")
async def export_session(session_id: str, fmt: str) -> Response:
    if fmt not in RENDERERS:
        raise HTTPException(404, f"unknown format {fmt!r}")
    db = _require_store()
    session = db.get_session(session_id)
    if session is None:
        raise HTTPException(404, "no such session")
    render, media_type = RENDERERS[fmt]
    body = render(session, db.get_segments(session_id))
    return Response(
        content=body, media_type=media_type,
        headers={"Content-Disposition":
                 f'attachment; filename="{session_id}.{fmt}"'},
    )


@app.get("/sessions/{session_id}/audio")
async def download_audio(session_id: str) -> FileResponse:
    session = _require_store().get_session(session_id)
    if session is None or not session.get("audio_path"):
        raise HTTPException(404, "no audio for this session")
    path = Path(session["audio_path"])
    if not path.exists():
        raise HTTPException(404, "audio file is missing")
    return FileResponse(path, media_type="audio/wav",
                        filename=f"{session_id}.wav")


@app.post("/sessions/{session_id}/cleanup")
async def run_cleanup(session_id: str, vocabulary: str | None = None) -> dict:
    """Phase 5: LLM pass over finalized segments only, never the live tail."""
    db = _require_store()
    if db.get_session(session_id) is None:
        raise HTTPException(404, "no such session")
    segments = db.get_segments(session_id)
    if not segments:
        return {"cleaned": 0, "attempted": 0}

    updates, stats = await asyncio.to_thread(
        cleanup_engine.clean_segments, segments, vocabulary
    )
    cleared = 0
    for segment_id, text in updates.items():
        await db.set_clean_text(session_id, segment_id, text)
        cleared += text is None

    return {
        "attempted": stats.attempted,
        "accepted": stats.accepted,
        "rejected_drift": stats.rejected_drift,
        "rejected_length": stats.rejected_length,
        "rejected_dropped_words": stats.rejected_dropped,
        "changed": len(updates) - cleared,
        "cleared_stale": cleared,
    }


@app.delete("/sessions/{session_id}")
async def delete_session(session_id: str) -> dict:
    audio_path = await _require_store().delete_session(session_id)
    removed_audio = False
    if audio_path:
        path = Path(audio_path)
        if path.exists():
            path.unlink()
            removed_audio = True
    return {"deleted": session_id, "audio_removed": removed_audio}


@app.post("/maintenance/retention")
async def apply_retention(days: int = Query(30, ge=1)) -> dict:
    """Section 13: archived audio is ~115 MB per session-hour."""
    db = _require_store()
    removed = []
    for row in db.sessions_older_than(days):
        await delete_session(row["id"])
        removed.append(row["id"])
    return {"days": days, "removed": removed}


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    async def index() -> FileResponse:
        return FileResponse(CLIENT_DIR / "index.html")
