"""WebSocket protocol, Phase 2 semantics, driven by stubs so no model is needed.

The contract under test is section 8's: `partial` may be replaced at any time,
`final` never is. Everything else here supports checking that.
"""

from __future__ import annotations

import asyncio
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
from server.registry import SessionRegistry  # noqa: E402
from server.scheduler import InferenceScheduler  # noqa: E402
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

    def __init__(self) -> None:
        self.languages_seen: list[str] = []

    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    async def transcribe(self, pcm, language, prompt=None):
        if language not in self.languages_seen:
            self.languages_seen.append(language)
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


class FakeVAD:
    """Reports speech until `go_silent()` is called."""

    def __init__(self) -> None:
        self.silence_ms = 0

    def push(self, pcm) -> FakeVadState:
        return FakeVadState(trailing_silence_ms=self.silence_ms)

    def clear_speech_counter(self) -> None: ...

    def go_silent(self, ms: int = 1_000) -> None:
        self.silence_ms = ms


def make_client(vad=None, max_sessions: int = 3) -> TestClient:
    """Installs a lifespan that wires stubs instead of the real model.

    The scheduler owns a worker task, so it has to be created on the loop the
    app actually runs on -- building it out here would attach it to the wrong
    one and every hop would hang.
    """
    adapter = StubAdapter()

    @contextlib.asynccontextmanager
    async def test_lifespan(app):
        main_module.adapter = adapter
        main_module.store = None                  # persistence covered elsewhere
        main_module.scheduler = InferenceScheduler(adapter, max_sessions=max_sessions)
        await main_module.scheduler.start()
        main_module.registry = SessionRegistry(grace_seconds=60)
        yield
        await main_module.scheduler.stop()

    # These tests feed one second at a time and expect a hop per second. Pin the
    # hop rather than inheriting the tuned 1.5 s default, so retuning for real
    # audio never silently deadlocks the suite.
    main_module.Session = functools.partial(_Session, hop_ms=1_000)
    main_module.SileroVAD = (lambda: vad) if vad is not None else FakeVAD
    main_module.WavArchiver = lambda path: None   # no files from the test suite
    main_module.app.router.lifespan_context = test_lifespan
    return TestClient(main_module.app)


def drain(ws, count):
    return [ws.receive_json() for _ in range(count)]


def test_audio_before_start_is_rejected():
    with make_client() as client, client.websocket_connect("/ws") as ws:
        ws.send_bytes(b"\x00" * 100)
        assert ws.receive_json()["code"] == "no_session"


def test_malformed_control_frame():
    with make_client() as client, client.websocket_connect("/ws") as ws:
        ws.send_text("{not json")
        assert ws.receive_json()["code"] == "bad_json"


def test_static_assets_are_served():
    with make_client() as client:
        assert client.get("/").status_code == 200
        assert client.get("/static/pcm-worklet.js").status_code == 200


def test_partials_appear_before_any_final():
    """First hop can never commit: agreement needs two passes."""
    with make_client() as client, client.websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        assert ws.receive_json()["state"] == "listening"

        ws.send_bytes(second_of(0))
        kinds = [m["type"] for m in drain(ws, 3)]
        assert kinds == ["status", "status", "partial"]  # processing, listening, partial


def test_finals_accumulate_and_are_never_rewritten():
    with make_client() as client, client.websocket_connect("/ws") as ws:
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
    with make_client(vad) as client, client.websocket_connect("/ws") as ws:
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
    with make_client() as client, client.websocket_connect("/ws") as ws:
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


def test_second_start_on_the_same_socket_is_rejected():
    """A silently replaced session leaks its scheduler slot, archiver handle
    and ring buffer forever -- three starts used to wedge the whole server."""
    with make_client(max_sessions=1) as client, client.websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start"}))
        assert ws.receive_json()["state"] == "listening"

        ws.send_text(json.dumps({"type": "start"}))
        error = ws.receive_json()
        assert error["type"] == "error"
        assert error["code"] == "already_started"

        # The original session is untouched and still transcribes.
        ws.send_bytes(second_of(0))
        kinds = [m["type"] for m in drain(ws, 3)]
        assert kinds == ["status", "status", "partial"]

        # And stop/start still works: the refusal is per-live-session,
        # not per-socket.
        ws.send_text(json.dumps({"type": "stop"}))
        while ws.receive_json().get("state") != "idle":
            pass
        ws.send_text(json.dumps({"type": "start"}))
        assert ws.receive_json()["state"] == "listening"


def test_session_id_that_escapes_the_audio_dir_is_rejected():
    """The id becomes a filename under data/audio/; '../' must not."""
    for evil in ("../../../../tmp/pwned", "a/b", "x" * 65, 7):
        with make_client() as client, client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "start", "session_id": evil}))
            error = ws.receive_json()
            assert error["type"] == "error"
            assert error["code"] == "bad_session_id"


async def test_reaping_an_abandoned_session_flushes_its_provisional_tail(tmp_path):
    """Phones drop connections constantly; the words still in the partial when
    that happens must reach the store, not evaporate with the socket."""
    from server.store import Store

    adapter = StubAdapter()
    scheduler = InferenceScheduler(adapter, max_sessions=1)
    await scheduler.start()
    store = Store(tmp_path / "reap.db")
    main_module.scheduler = scheduler
    main_module.store = store
    try:
        scheduler.register("reapme")
        await store.create_session("reapme", "tl", None, None)
        session = _Session(session_id="reapme", language="tl", hop_ms=1_000)
        pipeline = main_module.Pipeline(session, lambda p: None, vad=FakeVAD())

        async def send(payload: dict) -> None: ...
        pipeline.send = send

        for n in range(2):                     # two passes: one commits, one is tail
            await pipeline.feed(second_of(n))
            for _ in range(200):
                if not pipeline._tasks:
                    break
                await asyncio.sleep(0.005)

        assert pipeline.commit.partial.strip(), "test needs a provisional tail"
        tail = pipeline.commit.partial.strip()

        await pipeline.on_reap()

        stored = " ".join(s.text for s in store.get_segments("reapme"))
        assert tail in stored, f"tail {tail!r} missing from store: {stored!r}"
        assert scheduler.active_sessions == 0, "reap must free the scheduler slot"
    finally:
        await scheduler.stop()
        store.close()
        main_module.scheduler = None
        main_module.store = None


def test_session_survives_a_dropped_connection_and_replays_the_tail():
    """Section 8: the client buffers while disconnected and dedupes by id, so
    the server must still have the session -- and must replay what was missed."""
    client = make_client()
    with client:
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "start", "session_id": "keep-me"}))
            ws.receive_json()

            finals = []
            for n in range(4):
                ws.send_bytes(second_of(n))
                for _ in range(4):
                    m = ws.receive_json()
                    if m["type"] == "final":
                        finals.append(m["segment"])
                    elif m["type"] == "partial":
                        break
            assert finals, "need some committed text before disconnecting"
            # drop the connection without sending stop

        # Reconnect claiming to have seen nothing.
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({
                "type": "start", "session_id": "keep-me", "last_segment_id": 0,
            }))
            assert ws.receive_json()["state"] == "listening"
            replayed = [ws.receive_json()["segment"] for _ in range(len(finals))]

        assert [s["id"] for s in replayed] == [s["id"] for s in finals]
        assert [s["text"] for s in replayed] == [s["text"] for s in finals]


def test_resume_replays_only_what_the_client_missed():
    client = make_client()
    with client:
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "start", "session_id": "partial-seen"}))
            ws.receive_json()
            finals = []
            for n in range(5):
                ws.send_bytes(second_of(n))
                for _ in range(4):
                    m = ws.receive_json()
                    if m["type"] == "final":
                        finals.append(m["segment"])
                    elif m["type"] == "partial":
                        break
            assert len(finals) >= 2

        seen_through = finals[0]["id"]
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({
                "type": "start", "session_id": "partial-seen",
                "last_segment_id": seen_through,
            }))
            ws.receive_json()
            expected = [s for s in finals if s["id"] > seen_through]
            replayed = [ws.receive_json()["segment"] for _ in expected]

        assert [s["id"] for s in replayed] == [s["id"] for s in expected]


def test_capacity_is_refused_rather_than_queued():
    client = make_client(max_sessions=1)
    with client:
        with client.websocket_connect("/ws") as first:
            first.send_text(json.dumps({"type": "start", "session_id": "a"}))
            assert first.receive_json()["state"] == "listening"

            with client.websocket_connect("/ws") as second:
                second.send_text(json.dumps({"type": "start", "session_id": "b"}))
                error = second.receive_json()
                assert error["type"] == "error"
                assert error["code"] == "at_capacity"


def test_model_listing_reports_what_is_downloaded():
    with make_client() as client:
        payload = client.get("/models").json()
        ids = [m["id"] for m in payload["models"]]
        assert "openai_whisper-large-v3-v20240930_turbo" in ids
        assert all({"label", "detail", "downloaded", "multilingual"} <= m.keys()
                   for m in payload["models"])


def test_unknown_model_is_rejected():
    with make_client() as client:
        assert client.post("/models/select", params={"model": "nope"}).status_code == 404


def test_english_only_model_needs_an_explicit_override():
    """Selecting it for Tagalog would translate rather than transcribe."""
    with make_client() as client:
        response = client.post("/models/select", params={
            "model": "distil-whisper_distil-large-v3_turbo"})
        assert response.status_code == 400
        assert "English-only" in response.json()["detail"]


def test_model_cannot_be_swapped_while_a_session_is_live():
    """The model is shared; swapping mid-session would splice two models'
    output into one transcript with no record of the seam."""
    client = make_client()
    with client:
        with client.websocket_connect("/ws") as ws:
            ws.send_text(json.dumps({"type": "start", "session_id": "busy"}))
            ws.receive_json()

            response = client.post("/models/select", params={
                "model": "openai_whisper-small"})
            assert response.status_code == 409
            assert "still live" in response.json()["detail"]


def test_language_listing_puts_tagalog_first_and_flags_auto_detect():
    with make_client() as client:
        payload = client.get("/languages").json()
        assert payload["default"] == "tl"
        assert payload["languages"][0]["code"] == "tl"
        assert payload["languages"][0]["recommended"]

        auto = [l for l in payload["languages"] if l["auto_detect"]]
        assert len(auto) == 1
        # Section 2's warning has to reach whoever is choosing.
        assert "translate" in auto[0]["note"]
        assert auto[0] is payload["languages"][-1], "auto-detect should be last"


def test_unsupported_language_is_rejected():
    with make_client() as client, client.websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start", "language": "klingon"}))
        error = ws.receive_json()
        assert error["type"] == "error"
        assert error["code"] == "unknown_language"


def test_session_language_reaches_the_adapter():
    """A dropdown that does not change what the model decodes is worse than none."""
    client = make_client()
    with client, client.websocket_connect("/ws") as ws:
        ws.send_text(json.dumps({"type": "start", "language": "es"}))
        assert ws.receive_json()["state"] == "listening"
        ws.send_bytes(second_of(0))
        for _ in range(4):
            if ws.receive_json()["type"] == "partial":
                break
    assert main_module.adapter.languages_seen == ["es"], \
        f"adapter saw {main_module.adapter.languages_seen}"
