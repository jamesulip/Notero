"""The acceptance rule in eval/tuning_verdict.py, on hand-built rows."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import tuning_verdict as tv  # noqa: E402


def row(arm, fixture, der, *, missed=0.05, ms=1000.0, speakers=2, ref=2, repeat=0, finger="a"):
    return {"arm": arm, "fixture": fixture, "repeat": repeat, "der": der / 100,
            "missed": missed / 100, "diarize_ms": ms, "speakers": speakers,
            "ref_speakers": ref, "fingerprint": [[0.0, 1.0, finger]]}


def runs(arm, fixture, der, n=3, **kw):
    return [row(arm, fixture, der, repeat=i, **kw) for i in range(n)]


def rows(base_der: dict, cand_der: dict, base: dict | None = None, cand: dict | None = None):
    out = []
    for f, d in base_der.items():
        out += runs("base", f, d, **(base or {}))
    for f, d in cand_der.items():
        out += runs("cand", f, d, **(cand or {}))
    return out


def test_two_points_of_mean_gain_with_nothing_worse_passes():
    v = tv.judge(rows({"a": 10, "b": 20}, {"a": 8, "b": 17}), "base", "cand")
    assert v.passed and round(v.mean_der_delta, 2) == -2.5


def test_under_two_points_without_a_fixed_count_fails():
    v = tv.judge(rows({"a": 10, "b": 20}, {"a": 9, "b": 19}), "base", "cand")
    assert not v.passed and any(r.startswith("gain") for r in v.reasons)


def test_a_fixed_speaker_count_passes_without_two_points():
    data = rows({"a": 10}, {"a": 9.5},
                base={"speakers": 1, "ref": 2}, cand={"speakers": 2, "ref": 2})
    v = tv.judge(data, "base", "cand")
    assert v.passed and any("count fixed" in n for n in v.notes)


def test_a_fixed_count_does_not_excuse_a_worse_mean():
    data = rows({"a": 10}, {"a": 11},
                base={"speakers": 1, "ref": 2}, cand={"speakers": 2, "ref": 2})
    assert not tv.judge(data, "base", "cand").passed


def test_a_new_merge_fails_however_large_the_gain():
    data = rows({"a": 30}, {"a": 5}, base={"speakers": 2, "ref": 2}, cand={"speakers": 1, "ref": 2})
    v = tv.judge(data, "base", "cand")
    assert not v.passed and any("merge" in r for r in v.reasons)


def test_a_merge_the_baseline_already_had_is_not_new():
    data = rows({"a": 30}, {"a": 20}, base={"speakers": 1, "ref": 2}, cand={"speakers": 1, "ref": 2})
    assert tv.judge(data, "base", "cand").passed


def test_a_phantom_speaker_fails():
    data = rows({"a": 30}, {"a": 5}, base={"speakers": 2, "ref": 2}, cand={"speakers": 3, "ref": 2})
    v = tv.judge(data, "base", "cand")
    assert not v.passed and any("phantom" in r for r in v.reasons)


def test_more_missed_speech_fails_even_when_der_improves():
    data = rows({"a": 30}, {"a": 20}, base={"missed": 5}, cand={"missed": 6})
    v = tv.judge(data, "base", "cand")
    assert not v.passed and any("missed" in r for r in v.reasons)


def test_an_unstable_candidate_fails():
    base = runs("base", "a", 30)
    cand = [row("cand", "a", 10, repeat=i, finger="xy"[i % 2]) for i in range(4)]
    v = tv.judge(base + cand, "base", "cand")
    assert not v.passed and any("unstable" in r for r in v.reasons)


def test_one_fixture_getting_three_points_worse_fails_a_good_mean():
    v = tv.judge(rows({"a": 10, "b": 10, "c": 10}, {"a": 0, "b": 0, "c": 14}), "base", "cand")
    assert not v.passed and any("regression" in r for r in v.reasons)


def test_ten_percent_more_time_is_the_limit():
    ok = tv.judge(rows({"a": 10}, {"a": 5}, base={"ms": 1000}, cand={"ms": 1100}), "base", "cand")
    slow = tv.judge(rows({"a": 10}, {"a": 5}, base={"ms": 1000}, cand={"ms": 1101}), "base", "cand")
    assert ok.passed and not slow.passed


def test_the_median_not_the_worst_run_decides():
    base = runs("base", "a", 30)
    cand = [row("cand", "a", d, repeat=i) for i, d in enumerate([5, 5, 5, 5, 90])]
    assert tv.judge(base + cand, "base", "cand").passed


def test_overfit_is_a_pass_on_tuning_and_a_fail_on_holdout():
    good = tv.Verdict(True, -3.0)
    bad = tv.Verdict(False, 1.0, ["gain: ..."])
    assert tv.decide(good, good) == "ACCEPT"
    assert tv.decide(good, bad).startswith("REJECT (overfit")
    assert tv.decide(bad, good).startswith("REJECT (fails on the tuning set")
    assert tv.decide(good, None).startswith("UNVALIDATED")


def test_no_shared_fixture_is_not_a_pass():
    data = runs("base", "a", 10) + runs("cand", "b", 5)
    assert not tv.judge(data, "base", "cand").passed


def test_the_time_condition_can_come_from_a_separate_locked_run():
    accuracy = rows({"a": 10}, {"a": 5}, base={"ms": 1000}, cand={"ms": 5000})      # noisy: parallel
    locked_ok = rows({"a": 10}, {"a": 5}, base={"ms": 1000}, cand={"ms": 1050})
    locked_slow = rows({"a": 10}, {"a": 5}, base={"ms": 1000}, cand={"ms": 1300})
    assert not tv.judge(accuracy, "base", "cand").passed
    assert tv.judge(accuracy, "base", "cand", time_rows=locked_ok).passed
    assert not tv.judge(accuracy, "base", "cand", time_rows=locked_slow).passed


def test_timing_rows_that_lack_an_arm_fail_rather_than_pass_quietly():
    accuracy = rows({"a": 10}, {"a": 5})
    only_base = runs("base", "a", 10)
    v = tv.judge(accuracy, "base", "cand", time_rows=only_base)
    assert not v.passed and any(r.startswith("time") for r in v.reasons)

