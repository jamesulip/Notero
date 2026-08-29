"""FastAPI orchestrator -- Phase 2.

Rolling 15 s context on a 1 s hop, Silero VAD gating and boundary detection,
and LocalAgreement-2 deciding what is safe to freeze. Every hop re-transcribes
the whole trailing window; the commit policy turns that stream of overlapping,
disagreeing hypotheses into text that only ever grows.

The partial/final split is the protocol half of section 8's design contract:
`partial` may be replaced at any time, `final` never is.
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .adapters.base import ASRAdapter, Token
from .adapters.whisperkit import WhisperKitAdapter
from .commit import LocalAgreement
from .session import Session, bytes_to_ms
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

adapter: ASRAdapter | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global adapter
    adapter = WhisperKitAdapter()
    log.info("loading ASR model (first run also downloads it)")
    await adapter.start()
    log.info("ASR model ready")
    yield
    await adapter.stop()


app = FastAPI(title="Live Tagalog Transcriber", lifespan=lifespan)


@app.get("/health")
async def health() -> dict:
    return {
        "ok": adapter is not None,
        "model": getattr(adapter, "model", None),
        "load_ms": getattr(adapter, "load_ms", None),
    }


class Pipeline:
    """One session's live path: ring buffer -> VAD -> ASR -> commit -> events."""

    def __init__(self, session: Session, send, agreement: int = 2, vad=None) -> None:
        self.session = session
        self.send = send
        self.vad = vad if vad is not None else SileroVAD()
        self.commit = LocalAgreement(agreement=agreement)
        self._inflight = False
        self._last_partial = ""
        self._tasks: set[asyncio.Task] = set()

    async def feed(self, pcm: bytes) -> None:
        self.session.push_audio(pcm)
        state = self.vad.push(pcm)

        if not self.session.due_for_hop():
            return
        self.session.mark_hop()

        # Section 5: one model instance, and a stale partial is worse than a
        # missing one. If the previous hop is still running, drop this one
        # rather than queueing behind it.
        if self._inflight:
            self.session.stats.dropped_hops += 1
            log.debug("hop dropped: previous still in flight")
            return

        if state.trailing_silence_ms >= self.session.silence_boundary_ms:
            await self._boundary()
            return

        # Run the hop off the receive path. Awaiting it here would stall the
        # socket read loop for the duration of inference, so audio would queue
        # up in the transport and latency would grow without bound -- the drop
        # policy can only work if hops and audio intake are concurrent.
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
        """Trailing silence ends a segment: flush the tail, then stop decoding."""
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
        # Nothing pending and nobody talking -- skip inference entirely.
        # Turbo hallucinates confidently on silence.
        self.session.stats.skipped_silent += 1

    async def _hop(self) -> None:
        assert adapter is not None
        window, window_start_ms = self.session.ring.window()
        if not window:
            return
        self.commit.ceiling_ms = self.session.ring.total_ms

        # The window has slid past the last commit, so the audio at its head is
        # about to be dropped without ever having been agreed. Commit it now --
        # otherwise the next hypothesis starts at a different word than this
        # one, prefixes stop aligning, and the stall becomes permanent.
        if window_start_ms > self.commit.committed_end_ms:
            forced = self.commit.force_commit_before(window_start_ms)
            if forced:
                self.session.stats.forced_commits += 1
                await self._emit_final(forced)

        await self.send({"type": "status", "state": "processing"})
        try:
            result = await adapter.transcribe(
                window, self.session.language, self.session.prompt
            )
        except Exception as exc:
            log.exception("transcription failed")
            await self.send({"type": "error", "code": "transcribe_failed",
                             "message": str(exc)})
            return
        finally:
            await self.send({"type": "status", "state": "listening"})

        stats = self.session.stats
        stats.hops += 1
        stats.total_audio_ms += result.audio_ms
        stats.total_infer_ms += result.infer_ms

        if not result.tokens:
            stats.empty_results += 1
            log.warning(
                "hop %d returned no text (%d ms window, %d ms inference) -- "
                "decode threshold likely tripped",
                stats.hops, result.audio_ms, result.infer_ms,
            )
            return

        # Window-relative timings become absolute so segments, exports and
        # Phase 6's overlap merge all share one timeline.
        absolute = [
            Token(text=t.text,
                  start_ms=window_start_ms + t.start_ms,
                  end_ms=window_start_ms + t.end_ms)
            for t in result.tokens
        ]
        log.debug("HYP win=[%d-%d] head=%s",
                  window_start_ms, window_start_ms + result.audio_ms,
                  [t.text for t in absolute[:4]])
        newly = self.commit.insert(absolute)
        if newly:
            # Re-anchor the window to the new commit point so the next pass
            # starts where this one stopped agreeing.
            self.session.ring.trim_to(self.commit.committed_end_ms)

        metrics.info(
            "hop=%d window_ms=%d infer_ms=%d rtf=%.3f tokens=%d committed=+%d "
            "pending=%d",
            stats.hops, result.audio_ms, result.infer_ms, result.rtf,
            len(absolute), len(newly), len(self.commit.partial),
        )

        if newly:
            await self._emit_final(newly)
        await self._emit_partial(self.commit.partial)

    async def _emit_final(self, tokens: list[Token]) -> None:
        text = "".join(t.text for t in tokens).strip()
        if not text:
            return
        await self.send({
            "type": "final",
            "segment": {
                "id": self.session.allocate_segment_id(),
                "text": text,
                "start_ms": tokens[0].start_ms,
                "end_ms": tokens[-1].end_ms,
            },
        })

    async def _emit_partial(self, text: str) -> None:
        if text == self._last_partial:
            return
        self._last_partial = text
        await self.send({"type": "partial", "text": text,
                         "since_ms": self.commit.committed_end_ms})

    async def finish(self) -> None:
        """Session end: nothing more is coming, so the tail is as final as it gets."""
        self.commit.ceiling_ms = self.session.ring.total_ms
        if self._tasks:
            await asyncio.gather(*list(self._tasks), return_exceptions=True)
        tail = self.commit.flush()
        if tail:
            await self._emit_final(tail)
        await self._emit_partial("")


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    pipeline: Pipeline | None = None
    log.info("client connected")

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
                    session = Session(
                        session_id=control.get("session_id") or uuid.uuid4().hex[:12],
                        language=control.get("language") or "tl",
                        prompt=control.get("prompt"),
                    )
                    pipeline = Pipeline(session, send)
                    log.info("session %s started (language=%s, %d ms context, "
                             "%d ms hop)", session.session_id, session.language,
                             session.context_ms, session.hop_ms)
                    await send({"type": "status", "state": "listening"})
                elif kind == "stop":
                    if pipeline is not None:
                        await pipeline.finish()
                        _log_summary(pipeline)
                        pipeline = None
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
        log.info("client disconnected")
    finally:
        if pipeline is not None:
            _log_summary(pipeline)


def _log_summary(pipeline: Pipeline) -> None:
    s = pipeline.session.stats
    log.info(
        "session %s ended: %d hops, %d silent skips, %d dropped, %d empty, "
        "%d boundaries, %d forced, mean RTF %.3f, %d committed tokens",
        pipeline.session.session_id, s.hops, s.skipped_silent, s.dropped_hops,
        s.empty_results, s.boundaries, s.forced_commits, s.mean_rtf,
        len(pipeline.commit.committed),
    )


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    async def index() -> FileResponse:
        return FileResponse(CLIENT_DIR / "index.html")
