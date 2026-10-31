"""Diarization scorer and fixture helpers (eval/der.py, eval/make_multispeaker.py).

Neither needs `say`, models or audio: the scorer is arithmetic over segments,
and the generator's pure helpers (trim, level, schedule) take plain lists.
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import der  # noqa: E402
import make_multispeaker as mm  # noqa: E402

S = der.Segment


def run(ref, hyp, **kw):
    return der.score(ref, hyp, **{"collar": 0.0, **kw})


# --- scorer ------------------------------------------------------------------

def test_a_perfect_hypothesis_scores_zero_whatever_it_calls_the_speakers():
    ref = [S(0, 5, "alice"), S(5, 10, "bob"), S(10, 12, "alice")]
    hyp = [S(0, 5, "S2"), S(5, 10, "S1"), S(10, 12, "S2")]
    result = run(ref, hyp)
    assert result.der == pytest.approx(0, abs=1e-9)
    assert result.mapping == {"alice": "S2", "bob": "S1"}


def test_speech_the_hypothesis_leaves_out_is_missed():
    result = run([S(0, 10, "a")], [S(0, 5, "x")])
    assert result.missed / result.total == pytest.approx(0.5, abs=0.01)
    assert result.false_alarm == 0 and result.confusion == 0


def test_speech_where_the_reference_has_none_is_a_false_alarm():
    result = run([S(0, 5, "a")], [S(0, 10, "x")])
    assert result.false_alarm / result.total == pytest.approx(1.0, abs=0.01)
    assert result.missed == 0 and result.confusion == 0


def test_two_people_fused_into_one_label_cost_one_of_them_as_confusion():
    result = run([S(0, 5, "a"), S(5, 10, "b")], [S(0, 10, "x")])
    assert result.confusion / result.total == pytest.approx(0.5, abs=0.01)
    assert result.hyp_speakers == 1 and result.ref_speakers == 2
    assert None in result.mapping.values()


def test_one_person_split_into_two_labels_costs_the_smaller_half():
    result = run([S(0, 10, "a")], [S(0, 6, "x"), S(6, 10, "y")])
    assert result.confusion / result.total == pytest.approx(0.4, abs=0.01)


def test_overlap_the_hypothesis_does_not_mark_is_missed_per_speaker():
    ref = [S(0, 10, "a"), S(4, 6, "b")]
    result = run(ref, [S(0, 10, "x")])
    # 12 speaker-seconds of reference speech; b's two seconds are unaccounted for.
    assert result.total == pytest.approx(12, abs=0.05)
    assert result.missed / result.total == pytest.approx(2 / 12, abs=0.01)


def test_the_collar_forgives_a_boundary_that_is_a_little_late():
    ref = [S(0, 5, "a"), S(5, 10, "b")]
    hyp = [S(0, 5.2, "x"), S(5.2, 10, "y")]
    assert run(ref, hyp, collar=0.0).der > 0.015
    assert run(ref, hyp, collar=0.25).der == pytest.approx(0, abs=1e-9)


def test_the_collar_does_not_forgive_a_turn_that_is_simply_wrong():
    ref = [S(0, 5, "a"), S(5, 10, "b"), S(10, 15, "a")]
    hyp = [S(0, 15, "x")]
    assert run(ref, hyp, collar=0.25).confusion > 4.0


def test_mapping_is_the_best_one_to_one_assignment_not_a_greedy_one():
    # x overlaps a slightly more than y does, but y is the only fit for b.
    ref = [S(0, 6, "a"), S(6, 10, "b")]
    hyp = [S(0, 7, "x"), S(7, 10, "y")]
    result = run(ref, hyp)
    assert result.mapping == {"a": "x", "b": "y"}


def test_an_empty_hypothesis_is_all_missed():
    result = run([S(0, 10, "a")], [])
    assert result.der == pytest.approx(1.0, abs=0.01)
    assert result.missed == pytest.approx(result.total)


def test_an_empty_reference_does_not_divide_by_zero():
    assert run([], []).der == 0.0


def test_rttm_round_trip_and_json_input(tmp_path):
    segments = [S(0.5, 2.25, "spk1"), S(3.0, 4.5, "spk2")]
    rttm = tmp_path / "x.rttm"
    der.write_rttm(segments, rttm, "x")
    assert der.read_rttm(rttm) == segments

    hyp = tmp_path / "hyp.json"
    hyp.write_text(json.dumps({"spans": [{"start": 0.5, "end": 2.25, "speaker": "S1"}]}))
    assert der.read_segments(hyp) == [S(0.5, 2.25, "S1")]
    assert der.read_segments(rttm) == segments


def test_command_line_prints_one_json_object(tmp_path, capsys):
    ref = tmp_path / "r.rttm"
    der.write_rttm([S(0, 4, "a"), S(4, 8, "b")], ref, "r")
    hyp = tmp_path / "h.rttm"
    der.write_rttm([S(0, 4, "p"), S(4, 8, "q")], hyp, "h")
    assert der.main(["--ref", str(ref), "--hyp", str(hyp), "--json"]) == 0
    out = json.loads(capsys.readouterr().out)
    assert out["der"] == 0 and out["ref_speakers"] == 2 and out["hyp_speakers"] == 2


# --- generator helpers -------------------------------------------------------

def test_trim_cuts_silence_but_keeps_the_speech():
    quiet = [0.0] * 4800
    speech = [0.2 * math.sin(i / 7) for i in range(8000)]
    trimmed = mm.trim(quiet + speech + quiet)
    assert len(trimmed) < len(quiet) * 2 + len(speech)
    assert len(trimmed) >= len(speech)
    assert max(abs(x) for x in trimmed) == pytest.approx(0.2, abs=0.01)


def test_level_brings_every_clip_to_the_same_rms():
    soft = [0.01 * math.sin(i / 5) for i in range(4000)]
    loud = [0.6 * math.sin(i / 5) for i in range(4000)]
    for clip in (soft, loud):
        out = mm.level(clip)
        rms = math.sqrt(sum(x * x for x in out) / len(out))
        assert rms == pytest.approx(mm.TARGET_RMS, rel=1e-6)


def test_the_schedule_is_reproducible_and_never_repeats_a_text_within_a_pool():
    fixture = mm.FIXTURES[0]
    first = [mm.choose(random.Random(fixture.seed), fixture, set()) for _ in range(3)]
    second = [mm.choose(random.Random(fixture.seed), fixture, set()) for _ in range(3)]
    assert first == second

    rng, used = random.Random(1), set()
    picks = [mm.choose(rng, fixture, used)[1] for _ in range(12)]
    assert len(set(picks)) == len(picks)


def test_fixtures_name_enough_voices_and_gains_for_their_speakers():
    for fixture in mm.FIXTURES:
        assert 2 <= len(fixture.voices) <= len(fixture.gains)
        assert len(set(fixture.voices)) == len(fixture.voices)
        assert sum(fixture.weights) == pytest.approx(1.0)
