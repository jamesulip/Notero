"""Ring buffer timeline arithmetic.

If `window_start_ms` drifts, every downstream timestamp drifts with it: segment
boundaries, SRT cues, and the overlap merge Phase 6 uses to attach speakers.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from server.session import RingBuffer, Session, ms_to_bytes  # noqa: E402


def audio(ms: int) -> bytes:
    return b"\x01\x00" * (ms_to_bytes(ms) // 2)


def test_buffer_holds_only_the_context_window():
    ring = RingBuffer(context_ms=15_000)
    ring.push(audio(20_000))
    assert ring.duration_ms == 15_000
    assert ring.total_ms == 20_000


def test_window_start_tracks_discarded_audio():
    ring = RingBuffer(context_ms=15_000)
    ring.push(audio(10_000))
    assert ring.window_start_ms == 0          # nothing dropped yet

    ring.push(audio(10_000))                  # now 20s seen, 15s held
    assert ring.window_start_ms == 5_000
    assert ring.window_start_ms + ring.duration_ms == ring.total_ms


def test_timeline_stays_exact_over_many_small_pushes():
    """Frames arrive every 100 ms; rounding must not accumulate."""
    ring = RingBuffer(context_ms=15_000)
    for _ in range(600):                      # 60 s in 100 ms frames
        ring.push(audio(100))
    assert ring.total_ms == 60_000
    assert ring.duration_ms == 15_000
    assert ring.window_start_ms == 45_000


def test_hops_fire_once_per_hop_interval():
    s = Session(session_id="t", hop_ms=1_000)
    for _ in range(9):
        s.push_audio(audio(100))
    assert not s.due_for_hop()
    s.push_audio(audio(100))
    assert s.due_for_hop()
    s.mark_hop()
    assert not s.due_for_hop()


def test_window_returns_its_own_start():
    ring = RingBuffer(context_ms=5_000)
    ring.push(audio(8_000))
    pcm, start = ring.window()
    assert start == 3_000
    assert len(pcm) == ms_to_bytes(5_000)


def test_trim_to_anchors_the_window_at_a_commit():
    ring = RingBuffer(context_ms=15_000)
    ring.push(audio(10_000))
    ring.trim_to(4_000)
    assert ring.window_start_ms == 4_000
    assert ring.duration_ms == 6_000
    assert ring.total_ms == 10_000


def test_trim_to_is_monotonic_and_ignores_the_past():
    ring = RingBuffer(context_ms=15_000)
    ring.push(audio(10_000))
    ring.trim_to(6_000)
    ring.trim_to(2_000)          # older than what we already dropped
    assert ring.window_start_ms == 6_000


def test_context_cap_still_applies_when_nothing_commits():
    """A long stretch without agreement must not grow the buffer forever."""
    ring = RingBuffer(context_ms=15_000)
    ring.push(audio(60_000))
    assert ring.duration_ms == 15_000
    assert ring.window_start_ms == 45_000
