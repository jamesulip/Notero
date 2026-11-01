"""Tests for eval/speaker_stability.py: audio variants and the name-follows-voice score.

Pure Python on tiny hand-built timelines: no `say`, no models, runs on Linux.
"""

import array
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "eval"))

import der  # noqa: E402
import speaker_stability as ss  # noqa: E402

S = der.Segment


def turns(*speakers: str, length: float = 10.0) -> list[der.Segment]:
    return [S(i * length, (i + 1) * length, who) for i, who in enumerate(speakers)]


def renumbered(ref: list[der.Segment], mapping: dict[str, str]) -> list[der.Segment]:
    return [S(t.start, t.end, mapping[t.speaker]) for t in ref]


# --- audio -----------------------------------------------------------------------

def test_mute_silences_only_the_range_and_keeps_the_length():
    audio = array.array("h", [100] * 160)
    out = ss.mute(audio, 16, 2 / 16, 6 / 16)  # samples 2..6
    assert len(out) == len(audio)
    assert list(out[:2]) == [100, 100] and list(out[2:6]) == [0, 0, 0, 0] and out[6] == 100


def test_trim_head_moves_everything_earlier():
    audio = array.array("h", range(100))
    out = ss.trim_head(audio, 10, 2.0)
    assert out[0] == 20 and len(out) == 80


def test_shifted_turns_drop_those_that_ended_before_the_cut_and_move_the_rest():
    ref = turns("a", "b", "c", "d")
    moved = ss.shifted(ref, 15.0)
    assert [t.speaker for t in moved] == ["b", "c", "d"]
    assert moved[0].start == -5.0 and moved[1].start == 5.0


def test_room_noise_is_reproducible_and_changes_the_audio():
    audio = array.array("h", [0] * 2000)
    a = ss.add_room_noise(audio, -40.0, seed=1)
    b = ss.add_room_noise(audio, -40.0, seed=1)
    assert a == b and a != audio and max(abs(x) for x in a) > 0


# --- the score ----------------------------------------------------------------------

def run(ref, mapping, drop=()):
    return [t for t in renumbered(ref, mapping) if t.start not in drop]


def test_an_unchanged_run_gives_every_name_to_the_right_voice_under_both_policies():
    ref = turns("a", "b", "a", "b")
    old = renumbered(ref, {"a": "S1", "b": "S2"})
    result = ss.stability(ref, old, ref, old, {"labels": {}, "inherited": {"S1": "S1", "S2": "S2"}})
    assert result["voices_renumbered"] == 0
    assert result["label"]["right"] == 100.0 and result["carry"]["right"] == 100.0


def test_a_renumbered_run_puts_the_names_on_the_wrong_voices_unless_they_are_carried():
    ref = turns("a", "b", "a", "b")
    old = renumbered(ref, {"a": "S1", "b": "S2"})
    new = renumbered(ref, {"a": "S2", "b": "S1"})
    carry = {"labels": {"S1": "S2", "S2": "S1"}, "inherited": {"S1": "S2", "S2": "S1"}, "kept": []}
    result = ss.stability(ref, old, ref, new, carry)
    assert result["voices_renumbered"] == 2
    assert result["label"]["wrong"] == 100.0, "the name stays on the number, so it moves to the other voice"
    assert result["carry"]["right"] == 100.0 and result["carry"]["wrong"] == 0.0


def test_a_speaker_that_could_not_be_matched_gets_no_name_and_not_a_wrong_one():
    ref = turns("a", "b", "a", "b")
    old = renumbered(ref, {"a": "S1", "b": "S2"})
    new = renumbered(ref, {"a": "S1", "b": "S1"})          # the new run fuses both
    carry = {"labels": {"S1": "S3"}, "inherited": {}, "kept": ["S1", "S2"]}
    result = ss.stability(ref, old, ref, new, carry)
    assert result["carry"]["wrong"] == 0.0 and result["carry"]["default"] == 100.0
    assert result["label"]["wrong"] > 0.0, "label policy hands S1's name to the fused speaker"


def test_a_voice_the_new_run_does_not_hear_is_not_counted():
    ref = turns("a", "b", "a")
    old = renumbered(ref, {"a": "S1", "b": "S2"})
    new = [t for t in old if t.speaker == "S1"]
    result = ss.stability(ref, old, ref, new, {"labels": {}, "inherited": {"S1": "S1"}})
    assert result["label"]["seconds"] == 20.0 and result["label"]["right"] == 100.0


def test_the_score_uses_the_reference_of_the_new_audio_when_the_audio_was_trimmed():
    ref = turns("a", "b", "a", "b")
    old = renumbered(ref, {"a": "S1", "b": "S2"})
    cut = 10.0
    new_ref = ss.shifted(ref, cut)
    new = renumbered(new_ref, {"b": "S1", "a": "S2"})       # b opens the trimmed audio
    # Nothing inherits, so each new speaker is moved to a label no old name is on.
    carry = {"labels": {"S1": "S3", "S2": "S4"}, "inherited": {}, "kept": ["S1", "S2"]}
    result = ss.stability(ref, old, new_ref, new, carry)
    assert result["label"]["wrong"] == 100.0
    assert result["carry"]["default"] == 100.0, "no inherited label, so no name is invented"


@pytest.mark.parametrize("numbering", [{"a": "S1", "b": "S2"}, {"a": "S2", "b": "S1"}])
def test_label_names_follow_the_voice_not_the_number(numbering):
    ref = turns("a", "b", "a", "b")
    names = ss.label_names(ref, renumbered(ref, numbering))
    assert names == {numbering["a"]: "a", numbering["b"]: "b"}
