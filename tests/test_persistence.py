"""Store, exports and retention."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

from server.archive import WavArchiver, repair  # noqa: E402
from server.exports import RENDERERS  # noqa: E402
from server.store import SegmentRow, Store  # noqa: E402


@pytest.fixture
def db(tmp_path):
    store = Store(tmp_path / "t.db")
    yield store
    store.close()


async def test_segments_round_trip(db):
    await db.create_session("s1", "tl", None, "/tmp/s1.wav")
    await db.add_segment("s1", 1, 0, 1500, "kumusta kayong lahat")
    await db.add_segment("s1", 2, 1500, 3000, "welcome sa meeting")
    await db.finish_session("s1", 3000)

    segments = db.get_segments("s1")
    assert [s.text for s in segments] == ["kumusta kayong lahat", "welcome sa meeting"]
    assert db.get_session("s1")["duration_ms"] == 3000
    assert db.list_sessions()[0]["segment_count"] == 2


async def test_clean_text_never_overwrites_raw(db):
    """Section 10: store as text_clean, never overwrite raw ASR output."""
    await db.create_session("s1", "tl", None, None)
    await db.add_segment("s1", 1, 0, 1000, "gusto kolang i confirm")
    await db.set_clean_text("s1", 1, "Gusto ko lang i-confirm.")

    segment = db.get_segments("s1")[0]
    assert segment.text == "gusto kolang i confirm"
    assert segment.text_clean == "Gusto ko lang i-confirm."
    assert segment.display_text == "Gusto ko lang i-confirm."


async def test_speaker_hook_is_writable_and_null_by_default(db):
    """Phase 6 hook: the column exists now so Phase 6 is not a migration."""
    await db.create_session("s1", "tl", None, None)
    await db.add_segment("s1", 1, 0, 1000, "sino ba yan")
    assert db.get_segments("s1")[0].speaker_id is None
    await db.set_speaker("s1", 1, "SPEAKER_01")
    assert db.get_segments("s1")[0].speaker_id == "SPEAKER_01"


async def test_delete_removes_segments_too(db):
    await db.create_session("s1", "tl", None, "/tmp/s1.wav")
    await db.add_segment("s1", 1, 0, 1000, "text")
    assert await db.delete_session("s1") == "/tmp/s1.wav"
    assert db.get_session("s1") is None
    assert db.get_segments("s1") == []


SESSION = {"id": "s1", "language": "tl", "started_at": "2026-08-29T10:00:00+00:00",
           "ended_at": "2026-08-29T10:01:00+00:00", "duration_ms": 5000}


def test_all_four_formats_render():
    segments = [SegmentRow(1, 0, 2500, "kumusta", None, None),
                SegmentRow(2, 2500, 5000, "salamat", "Salamat.", None)]
    for name, (render, _) in RENDERERS.items():
        assert render(SESSION, segments).strip(), f"{name} rendered empty"


def test_srt_cues_are_ordered_numbered_and_nonzero():
    segments = [SegmentRow(1, 0, 2500, "una", None, None),
                SegmentRow(2, 2500, 2500, "pangalawa", None, None)]  # zero-length
    out = RENDERERS["srt"][0](SESSION, segments)
    assert out.startswith("1\n")
    assert "\n2\n" in out
    assert "00:00:02,500 --> 00:00:02,501" in out    # widened so it is visible


def test_exports_carry_speaker_labels_when_present():
    segments = [SegmentRow(1, 0, 1000, "una", None, "SPEAKER_01"),
                SegmentRow(2, 1000, 2000, "pangalawa", None, "SPEAKER_02")]
    assert "[SPEAKER_01]" in RENDERERS["srt"][0](SESSION, segments)
    assert "<v SPEAKER_02>" in RENDERERS["vtt"][0](SESSION, segments)
    assert "SPEAKER_01:" in RENDERERS["txt"][0](SESSION, segments)
    assert json.loads(RENDERERS["json"][0](SESSION, segments))["segments"][0][
        "speaker_id"] == "SPEAKER_01"


def test_json_export_keeps_raw_and_cleaned_side_by_side():
    segments = [SegmentRow(1, 0, 1000, "raw text", "Raw text.", None)]
    payload = json.loads(RENDERERS["json"][0](SESSION, segments))
    assert payload["segments"][0]["text"] == "raw text"
    assert payload["segments"][0]["text_clean"] == "Raw text."


async def test_archiver_writes_a_readable_wav(tmp_path):
    import wave

    archiver = WavArchiver(tmp_path / "a.wav")
    await archiver.write(b"\x01\x00" * 16000)     # 1 s
    await archiver.write(b"\x02\x00" * 16000)     # 1 s
    assert archiver.duration_ms == 2000
    await archiver.close()

    with wave.open(str(tmp_path / "a.wav")) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
        assert w.getnframes() == 32000


def test_repair_fixes_a_header_left_by_a_crash(tmp_path):
    """A crashed session should leave a recoverable file, not a lost one."""
    import wave

    path = tmp_path / "crashed.wav"
    archiver = WavArchiver(path)
    archiver._write(b"\x01\x00" * 16000)          # written, never closed
    archiver._file.flush()

    assert repair(path) == 32000
    with wave.open(str(path)) as w:
        assert w.getnframes() == 16000
