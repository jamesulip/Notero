"""The A/B runner's bookkeeping (eval/run_diarization_ab.py), without running any build."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import run_diarization_ab as ab  # noqa: E402


def test_an_arm_names_a_binary_an_engine_and_optionally_its_own_models():
    arm = ab.parse_arm("v18=/tmp/x/diarbench:chunk-slots:/tmp/models")
    assert arm == {"label": "v18", "binary": "/tmp/x/diarbench",
                   "engine": "chunk-slots", "models": "/tmp/models"}
    assert ab.parse_arm("base=/b:turn")["models"] is None


@pytest.mark.parametrize("bad", ["nolabel", "=/b:turn", "x=/only-a-binary"])
def test_a_malformed_arm_is_refused(bad):
    with pytest.raises(argparse.ArgumentTypeError):
        ab.parse_arm(bad)


def test_median_and_range_are_reported_together_and_scaled():
    assert ab.med_range([0.1, 0.3, 0.2], scale=100, digits=0) == "20 [10-30]"
    assert ab.med_range([], 1) == "-"


def test_a_fingerprint_is_the_label_for_label_output_at_ten_milliseconds():
    a = [{"start": 1.0004, "end": 2.0, "speaker": "S1"}]
    b = [{"start": 1.0001, "end": 2.0, "speaker": "S1"}]
    c = [{"start": 1.0, "end": 2.0, "speaker": "S2"}]
    assert ab.fingerprint(a) == ab.fingerprint(b)
    assert ab.fingerprint(a) != ab.fingerprint(c)


def _row(arm, fixture, repeat, der, speakers, ms, spans="x"):
    return {"arm": arm, "fixture": fixture, "repeat": repeat, "diarize_ms": ms,
            "first_pass_ms": ms / 2, "second_pass_ms": ms / 2, "peak_footprint_mb": 150.0,
            "speakers": speakers, "ref_speakers": 3, "der": der, "missed": 0.1,
            "false_alarm": 0.0, "confusion": der - 0.1, "fingerprint": ((0.0, 1.0, spans),)}


def test_the_report_counts_distinct_outputs_and_wrong_speaker_counts(capsys):
    rows = [_row("A", "f", r, 0.2, 3, 1000) for r in range(3)]
    rows += [_row("B", "f", 0, 0.2, 2, 700, spans="p"), _row("B", "f", 1, 0.2, 3, 710, spans="q"),
             _row("B", "f", 2, 0.2, 3, 720, spans="q")]
    arms = [{"label": "A"}, {"label": "B"}]
    ab.report(rows, arms, [Path("f.wav")], runs=3)
    out = capsys.readouterr().out
    assert "SYNTHETIC" in out
    line_a = next(l for l in out.splitlines() if l.startswith("| A |"))
    line_b = next(l for l in out.splitlines() if l.startswith("| B |"))
    assert line_a.rstrip().endswith("1 of 3 |")
    assert line_b.rstrip().endswith("2 of 3 |")
    assert "2/3 (3)" in line_b
