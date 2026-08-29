"""WebSocket protocol test, run against a stub adapter so no model is needed.

Covers the things that are easy to get subtly wrong and hard to notice live:
chunk boundaries, the trailing flush on stop, and timestamp contiguity across
the two. A gap or overlap here shows up much later as desynced SRT exports.
"""

from __future__ import annotations

import contextlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

import server.main as main_module  # noqa: E402
from server.adapters.base import ASRAdapter, Result, Token  # noqa: E402

SECOND = 16_000 * 2  # bytes of PCM16 mono 16 kHz


class StubAdapter(ASRAdapter):
    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    async def transcribe(self, pcm, language, prompt=None):
        audio_ms = len(pcm) // 32
        return Result([Token(f"chunk{len(pcm) // SECOND}", 0, audio_ms)],
                      audio_ms=audio_ms, infer_ms=100)


@contextlib.asynccontextmanager
async def _no_lifespan(app):
    yield


def make_client() -> TestClient:
    main_module.adapter = StubAdapter()
    main_module.app.router.lifespan_context = _no_lifespan
    return TestClient(main_module.app)


def test_audio_before_start_is_rejected():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_bytes(b"\x00" * 100)
        assert ws.receive_json()["code"] == "no_session"


def test_chunking_and_flush_timestamps_are_contiguous():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start", "language": "tl"}))
        assert ws.receive_json() == {"type": "status", "state": "listening"}

        ws.send_bytes(b"\x00" * (SECOND * 4))   # under the 5 s threshold
        ws.send_bytes(b"\x00" * (SECOND * 2))   # crosses it, 1 s left over

        assert ws.receive_json()["state"] == "processing"
        first = ws.receive_json()["segment"]
        assert (first["start_ms"], first["end_ms"]) == (0, 5000)
        assert ws.receive_json()["state"] == "listening"

        ws.send_text(json.dumps({"type": "stop"}))
        assert ws.receive_json()["state"] == "processing"
        tail = ws.receive_json()["segment"]
        # The flushed tail must start exactly where the last chunk ended.
        assert (tail["start_ms"], tail["end_ms"]) == (5000, 6000)
        assert ws.receive_json()["state"] == "listening"
        assert ws.receive_json()["state"] == "idle"


def test_malformed_control_frame():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text("{not json")
        assert ws.receive_json()["code"] == "bad_json"


def test_static_assets_are_served():
    client = make_client()
    assert client.get("/").status_code == 200
    assert client.get("/static/pcm-worklet.js").status_code == 200
