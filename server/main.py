"""FastAPI orchestrator -- Phase 1 vertical slice.

Goal is measurement, not quality: fixed 5 s chunks straight to WhisperKit, no
VAD, no overlap, no commit policy. Every chunk result is emitted as a `final`
because with no commit policy there is nothing provisional to revise. Phase 2
introduces the ring buffer, VAD and LocalAgreement-2, at which point partials
become real.
"""

from __future__ import annotations

import json
import logging
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .adapters.base import ASRAdapter
from .adapters.whisperkit import WhisperKitAdapter
from .session import Session, bytes_to_ms

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
    running = adapter is not None
    return {
        "ok": running,
        "model": getattr(adapter, "model", None),
        "load_ms": getattr(adapter, "load_ms", None),
    }


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    session: Session | None = None
    log.info("client connected")

    async def send(payload: dict) -> None:
        await ws.send_text(json.dumps(payload))

    try:
        while True:
            message = await ws.receive()

            if message["type"] == "websocket.disconnect":
                break

            # -- control ---------------------------------------------------
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
                    log.info("session %s started (language=%s)",
                             session.session_id, session.language)
                    await send({"type": "status", "state": "listening"})
                elif kind == "stop":
                    if session is not None:
                        await _flush(ws, send, session)
                        log.info(
                            "session %s ended: %d chunks, %.1f s audio, mean RTF %.3f",
                            session.session_id, session.chunks,
                            session.total_audio_ms / 1000, session.mean_rtf,
                        )
                        session = None
                    await send({"type": "status", "state": "idle"})
                else:
                    await send({"type": "error", "code": "unknown_control",
                                "message": f"unknown control type {kind!r}"})
                continue

            # -- audio -----------------------------------------------------
            pcm = message.get("bytes")
            if pcm is None:
                continue
            if session is None:
                await send({"type": "error", "code": "no_session",
                            "message": "send a start control frame first"})
                continue

            for chunk, start_ms in session.chunker.push(pcm):
                await _transcribe_chunk(ws, send, session, chunk, start_ms)

    except WebSocketDisconnect:
        log.info("client disconnected")
    finally:
        if session is not None:
            log.info("session %s dropped: %d chunks, mean RTF %.3f",
                     session.session_id, session.chunks, session.mean_rtf)


async def _flush(ws: WebSocket, send, session: Session) -> None:
    tail = session.chunker.flush()
    if tail is not None:
        chunk, start_ms = tail
        await _transcribe_chunk(ws, send, session, chunk, start_ms)


async def _transcribe_chunk(ws: WebSocket, send, session: Session,
                            chunk: bytes, start_ms: int) -> None:
    assert adapter is not None
    await send({"type": "status", "state": "processing"})
    started = time.perf_counter()
    try:
        result = await adapter.transcribe(chunk, session.language, session.prompt)
    except Exception as exc:  # sidecar died, timed out, or refused the audio
        log.exception("transcription failed")
        await send({"type": "error", "code": "transcribe_failed", "message": str(exc)})
        await send({"type": "status", "state": "listening"})
        return
    wall_ms = int((time.perf_counter() - started) * 1000)

    audio_ms = bytes_to_ms(len(chunk))
    session.chunks += 1
    session.total_audio_ms += audio_ms
    session.total_infer_ms += result.infer_ms

    # Phase 1's entire deliverable is this line.
    metrics.info(
        "chunk=%d audio_ms=%d infer_ms=%d wall_ms=%d rtf=%.3f mean_rtf=%.3f chars=%d",
        session.chunks, audio_ms, result.infer_ms, wall_ms,
        result.rtf, session.mean_rtf, len(result.text),
    )

    text = result.text
    if text:
        await send({
            "type": "final",
            "segment": {
                "id": session.allocate_segment_id(),
                "text": text,
                "start_ms": start_ms,
                "end_ms": start_ms + audio_ms,
            },
            "timing": {
                "audio_ms": audio_ms,
                "infer_ms": result.infer_ms,
                "rtf": round(result.rtf, 3),
            },
        })
    await send({"type": "status", "state": "listening"})


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    async def index() -> FileResponse:
        return FileResponse(CLIENT_DIR / "index.html")
