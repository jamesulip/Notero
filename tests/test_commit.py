"""LocalAgreement-n behaviour.

The property that matters most is the negative one: committed text must never
change. Everything else is latency tuning.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

from server.adapters.base import Token  # noqa: E402
from server.commit import LocalAgreement  # noqa: E402


def toks(spec: str, start: int = 0, step: int = 300) -> list[Token]:
    """"a b c" -> three tokens 300 ms apart starting at `start`."""
    out = []
    for i, word in enumerate(spec.split()):
        t0 = start + i * step
        out.append(Token(text=(" " if i or start else "") + word, start_ms=t0, end_ms=t0 + step))
    return out


def test_nothing_commits_on_the_first_pass():
    la = LocalAgreement(agreement=2)
    assert la.insert(toks("kumusta ka na")) == []
    assert la.committed_text == ""
    assert la.partial == "kumusta ka na"


def test_agreeing_prefix_commits():
    la = LocalAgreement(agreement=2)
    la.insert(toks("kumusta ka na"))
    la.insert(toks("kumusta ka na kaibigan"))
    assert la.committed_text == "kumusta ka na"
    assert la.partial == "kaibigan"


def test_disagreement_blocks_the_commit():
    la = LocalAgreement(agreement=2)
    la.insert(toks("kumusta ka na"))
    la.insert(toks("kumusta ba na"))
    # Only "kumusta" is agreed; the rest stays provisional.
    assert la.committed_text == "kumusta"


def test_casing_and_punctuation_do_not_block_commits():
    """Whisper varies these between passes on identical audio."""
    la = LocalAgreement(agreement=2)
    la.insert(toks("kumusta ka na"))
    la.insert(toks("Kumusta, ka na!"))
    # Commits carry the newest pass's surface form, punctuation included.
    stripped = re.sub(r"[^\w ]", "", la.committed_text).lower()
    assert stripped == "kumusta ka na"


def test_three_pass_agreement_needs_three():
    la = LocalAgreement(agreement=3)
    la.insert(toks("magandang umaga"))
    la.insert(toks("magandang umaga"))
    assert la.committed_text == ""      # two passes is not enough now
    la.insert(toks("magandang umaga"))
    assert la.committed_text == "magandang umaga"


def test_committed_text_is_never_rewritten():
    """The section 8 contract, stated as a test."""
    la = LocalAgreement(agreement=2)
    passes = [
        "ang problema kasi",
        "ang problema kasi hindi",
        "ang problema kasi hindi pa",
        "ang PROBLEMA kasi hindi pa tapos",
        "ang problema kasi hindi pa tapos yung",
    ]
    seen = ""
    for p in passes:
        la.insert(toks(p))
        # committed may only ever grow, and only by appending
        assert la.committed_text.startswith(seen)
        seen = la.committed_text
    # Five passes at 2-pass agreement commit everything but the newest word.
    assert seen == "ang problema kasi hindi pa tapos"


def test_flush_commits_the_tail():
    la = LocalAgreement(agreement=2)
    la.insert(toks("sige next topic"))
    assert la.committed_text == ""
    la.flush()
    assert la.committed_text == "sige next topic"
    assert la.partial == ""


def test_already_committed_audio_is_not_recommitted():
    """A sliding window re-transcribes audio it has already seen."""
    la = LocalAgreement(agreement=2)
    la.insert(toks("una pangalawa", start=0))
    la.insert(toks("una pangalawa", start=0))
    assert la.committed_text == "una pangalawa"
    # next window overlaps: repeats both words, then adds one
    la.insert(toks("una pangalawa panghuli", start=0))
    la.insert(toks("una pangalawa panghuli", start=0))
    assert la.committed_text == "una pangalawa panghuli"


def test_agreement_below_two_is_rejected():
    with pytest.raises(ValueError):
        LocalAgreement(agreement=1)


def test_committed_timeline_never_goes_backwards():
    """Word timings drift between passes; SRT cues cannot.

    Reproduces the real failure seen in the Phase 2 end-to-end run, where a
    segment starting at 45.4 s was emitted after one ending at 45.9 s.
    """
    la = LocalAgreement(agreement=2)
    la.insert(toks("kailangan natin", start=44_000))
    la.insert(toks("kailangan natin", start=44_000))
    assert la.committed_text == "kailangan natin"
    end = la.committed[-1].end_ms

    # Next window re-times the following words slightly earlier than the
    # boundary the previous commit established.
    drifted = [Token(text=" priority", start_ms=end - 500, end_ms=end + 700)]
    la.insert(drifted)
    la.insert(drifted)

    starts_ends = [(t.start_ms, t.end_ms) for t in la.committed]
    for (_, prev_end), (start, _) in zip(starts_ends, starts_ends[1:]):
        assert start >= prev_end, f"timeline went backwards: {starts_ends}"


def test_force_commit_unsticks_a_permanent_stall():
    """A sliding window past the commit point must not stall forever."""
    la = LocalAgreement(agreement=2)
    # Two passes that never agree on their head -- nothing can commit.
    la.insert([Token(" kalo", 0, 900), Token(" ka", 900, 1800)])
    la.insert([Token(" kumusta", 0, 900), Token(" kayong", 900, 1800)])
    assert la.committed_text == ""

    # The window has moved to 900 ms; that audio is about to be discarded.
    forced = la.force_commit_before(900)
    assert forced and la.committed_text == "kumusta"
    assert la.committed_end_ms == 900


def test_force_commit_is_a_noop_when_nothing_is_old_enough():
    la = LocalAgreement(agreement=2)
    la.insert([Token(" mamaya", 5_000, 6_000)])
    assert la.force_commit_before(1_000) == []
    assert la.committed_text == ""


def test_nothing_is_timestamped_past_the_audio_received():
    """Reproduces a segment that ended at 71 s in a 57 s recording."""
    la = LocalAgreement(agreement=2)
    la.ceiling_ms = 57_000
    overlapping = [Token(f" w{i}", 56_000 + i * 10, 56_500 + i * 10) for i in range(40)]
    la.insert(overlapping)
    la.insert(overlapping)
    la.flush()
    assert la.committed, "expected the tail to commit"
    assert max(t.end_ms for t in la.committed) <= 57_000
