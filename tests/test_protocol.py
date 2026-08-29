"""WebSocket protocol, Phase 2 semantics, driven by stubs so no model is needed.

The contract under test is section 8's: `partial` may be replaced at any time,
`final` never is. Everything else here supports checking that.
"""

from __future__ import annotations

import contextlib
import functools
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

import server.main as main_module  # noqa: E402
from server.adapters.base import ASRAdapter, Result, Token  # noqa: E402
from server.session import Session as _Session  # noqa: E402

SECOND = 16_000 * 2
SCRIPT = "kumusta kayong lahat welcome sa meeting natin ngayong umaga".split()


def second_of(index: int) -> bytes:
    """One second of PCM whose every sample equals `index`.

    The stub reads the position back out of the audio, so it transcribes
    whatever slice it is actually handed. A stub that keyed off window *length*
    would silently re-emit the script from the start once the window became
    anchored to a commit, and would not model a sliding window at all.
    """
    return struct.pack("<h", index) * (SECOND // 2)


class StubAdapter(ASRAdapter):
    """Maps each distinct sample value back to its script word."""

    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    async def transcribe(self, pcm, language, prompt=None):
        values = struct.unpack(f"<{len(pcm) // 2}h", pcm)
        tokens, run_start, first = [], 0, True
        for i in range(1, len(values) + 1):
            if i < len(values) and values[i] == values[run_start]:
                continue
            index = values[run_start]
            if 0 <= index < len(SCRIPT):
                start_ms = run_start * 1000 // (SECOND // 2)
                end_ms = i * 1000 // (SECOND // 2)
                tokens.append(Token(text=("" if first else " ") + SCRIPT[index],
                                    start_ms=start_ms, end_ms=end_ms))
                first = False
            run_start = i
        return Result(tokens, audio_ms=len(pcm) // 32, infer_ms=50)


@dataclass
class FakeVadState:
    trailing_silence_ms: int = 0
    speech_ms: int = 1_000
    last_prob: float = 0.9
    frames: int = 1

    @property
    def has_speech(self) -> bool:
        return self.speech_ms > 0


class FakeVAD:
    """Reports speech until `go_silent()` is called."""

    def __init__(self) -> None:
        self.silence_ms = 0

    def push(self, pcm) -> FakeVadState:
        return FakeVadState(trailing_silence_ms=self.silence_ms)

    def clear_speech_counter(self) -> None: ...

    def go_silent(self, ms: int = 1_000) -> None:
        self.silence_ms = ms


@contextlib.asynccontextmanager
async def _no_lifespan(app):
    yield


def make_client(vad=None) -> TestClient:
    main_module.adapter = StubAdapter()
    # These tests feed one second at a time and expect a hop per second. Pin the
    # hop rather than inheriting the tuned 1.5 s default, so retuning for real
    # audio never silently deadlocks the suite.
    main_module.Session = functools.partial(_Session, hop_ms=1_000)
    main_module.SileroVAD = (lambda: vad) if vad is not None else FakeVAD
    main_module.app.router.lifespan_context = _no_lifespan
    return TestClient(main_module.app)


def drain(ws, count):
    return [ws.receive_json() for _ in range(count)]


def test_audio_before_start_is_rejected():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_bytes(b"\x00" * 100)
        assert ws.receive_json()["code"] == "no_session"


def test_malformed_control_frame():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text("{not json")
        assert ws.receive_json()["code"] == "bad_json"


def test_static_assets_are_served():
    client = make_client()
    assert client.get("/").status_code == 200
    assert client.get("/static/pcm-worklet.js").status_code == 200


def test_partials_appear_before_any_final():
    """First hop can never commit: agreement needs two passes."""
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        assert ws.receive_json()["state"] == "listening"

        ws.send_bytes(second_of(0))
        kinds = [m["type"] for m in drain(ws, 3)]
        assert kinds == ["status", "status", "partial"]  # processing, listening, partial


def test_finals_accumulate_and_are_never_rewritten():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        ws.receive_json()

        finals, partials = [], []
        for n in range(6):
            ws.send_bytes(second_of(n))
            for _ in range(4):
                m = ws.receive_json()
                if m["type"] == "final":
                    finals.append(m["segment"])
                elif m["type"] == "partial":
                    partials.append(m["text"])
                    break

        assert finals, "expected some committed text"
        # Segment ids are monotonic and the timeline never goes backwards.
        assert [s["id"] for s in finals] == sorted(s["id"] for s in finals)
        for earlier, later in zip(finals, finals[1:]):
            assert later["start_ms"] >= earlier["end_ms"]
        # Committed words follow the script, in order, without repeats.
        words = " ".join(s["text"] for s in finals).split()
        assert words == SCRIPT[:len(words)]


def test_trailing_silence_flushes_the_tail_to_final():
    vad = FakeVAD()
    with make_client(vad).websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        ws.receive_json()

        ws.send_bytes(second_of(0))          # one hop, nothing committable yet
        drain(ws, 3)

        vad.go_silent(1_000)                 # exceeds the 700 ms boundary
        ws.send_bytes(second_of(1))
        kinds = []
        for _ in range(4):
            m = ws.receive_json()
            kinds.append(m["type"])
            if m["type"] == "final":
                assert m["segment"]["text"] == "kumusta"
                break
        assert "final" in kinds, "silence should flush the provisional tail"


def test_stop_flushes_whatever_is_pending():
    with make_client().websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        ws.receive_json()
        ws.send_bytes(second_of(0))
        drain(ws, 3)

        ws.send_text(json.dumps({"type": "stop"}))
        seen = []
        for _ in range(4):
            m = ws.receive_json()
            seen.append(m)
            if m.get("state") == "idle":
                break
        assert any(m["type"] == "final" for m in seen)
