"""The A/A calibration tool: the interval it reports, how it draws and deals runs, and
that it can SEE a difference when there is one (a calibration that cannot fail proves
nothing). The committed numbers are checked in test_baselines.py."""

import json
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import benchstats as bs  # noqa: E402
import calibrate_aa as ca  # noqa: E402


def test_wilson_interval_matches_hand_values():
    # k = 0 of 20: the upper bound is z^2 / (n + z^2) = 3.8416 / 23.8416.
    low, high = ca.wilson(0, 20)
    assert low == 0.0 and high == pytest.approx(3.8416 / 23.8416, abs=1e-4)
    low, high = ca.wilson(50, 1000)
    assert low < 0.05 < high and high - low < 0.03
    assert ca.wilson(0, 0) == (0.0, 1.0)
    assert ca.rate(3, 100)["rate"] == 0.03 and ca.rate(3, 100)["ci95"][0] < 0.03 < ca.rate(3, 100)["ci95"][1]


def rows(count, wer=0.25, jitter=0.001, **extra):
    rng = random.Random(1)
    return [{"index": i + 1, "wer": wer + rng.random() * jitter, "hyp_words": 120, "rtf": 0.1 + rng.random() * 0.005,
             "decode_ms": 6000, "filler": False, "load": 0.5, **extra} for i in range(count)]


def test_draw_splits_without_replacement_when_the_pool_allows_and_bootstraps_otherwise():
    pool = rows(20)
    a, b = ca.draw(pool, 8, random.Random(3))
    assert len(a) == len(b) == 8
    assert len({r["index"] for r in a} | {r["index"] for r in b}) == 16        # disjoint: no run twice
    small = rows(5)
    a, b = ca.draw(small, 8, random.Random(3))
    assert len(a) == len(b) == 8 and {r["index"] for r in a + b} <= {1, 2, 3, 4, 5}   # with replacement


def test_evaluate_session_on_two_draws_of_one_distribution_flags_nothing():
    pool = rows(40, jitter=0.02)
    rng = random.Random(5)
    flagged = 0
    for k in range(30):
        a, b = ca.draw(pool, 8, rng)
        flagged += bool(ca.evaluate_session(a, b, "offline", 128, seed=k)["shipped_ignoring_load"])
    assert flagged <= 3                                                          # nominal 5%, not 50%


def test_evaluate_session_sees_a_real_difference():
    a = rows(8, wer=0.25)
    b = rows(8, wer=0.40)
    session = ca.evaluate_session(a, b, "offline", 128, seed=1, with_old_rule=True)
    assert "wer" in session["holm"] and "wer" in session["shipped"] and "wer" in session["p6_rule"]
    assert session["family"] == 4


def test_naive_rule_flags_more_often_than_holm_on_the_same_null_sessions():
    pool = rows(60, jitter=0.03, **{"live.forced_commits": 2.0})
    for r in pool:                      # give the live metrics some spread
        r["live.forced_commits"] = float(random.Random(r["index"]).randint(0, 6))
        r["live.dropped_hops"] = float(random.Random(r["index"] + 99).randint(0, 3))
        r["live.unagreed_tail_words"] = float(random.Random(r["index"] + 7).randint(0, 9))
        r["live.mean_decode_rtf"] = 0.06 + random.Random(r["index"] + 3).random() * 0.01
        r["live.infer_ms_per_hop"] = 900 + random.Random(r["index"] + 4).random() * 50
        r["live.commit_latency_median_ms"] = 2000 + random.Random(r["index"] + 5).random() * 300
    rng = random.Random(11)
    naive = holm = 0
    for k in range(120):
        a, b = ca.draw(pool, 8, rng)
        s = ca.evaluate_session(a, b, "live", 128, seed=k)
        naive += bool(s["naive"])
        holm += bool(s["holm"])
    assert s["family"] == 10 and naive > holm                                    # the multiple-testing gap
    assert naive >= 0.15 * 120 and holm <= 0.10 * 120


def test_simulate_returns_rates_power_and_the_family_size(tmp_path):
    baseline = {"name": "t", "fixtures": {"synthetic-taglish": {"ref_words": 128}},
                "arms": {"offline-pure": {"rows": rows(16, jitter=0.01)}}}
    results = ca.simulate(baseline, n=8, reps=24, jobs=1, seed=3, pools=["offline-pure"], power=True)
    pool = results["offline-pure"]
    assert pool["replicates"] == 24 and pool["family_size"] == 4 and pool["pool_runs"] == 16
    assert set(pool["any_metric_flagged"]) == {"naive", "p6_rule", "holm", "shipped_ignoring_load", "confirmed"}
    assert all(0 <= v["rate"] <= 1 for v in pool["any_metric_flagged"].values())
    power = pool["power_of_shipped_rule"]
    assert power["WER +10 points"]["rate"] == 1.0          # a 10-point shift on tight data is always seen
    assert power["WER +5 points"]["rate"] >= 0.9
    assert pool["any_metric_flagged"]["shipped_ignoring_load"]["rate"] <= 0.1


def test_stream_blocks_are_dealt_in_abba_order_and_counted(monkeypatch):
    seen = []
    real = ca.evaluate_session

    def spy(a, b, mode, ref_words, **kwargs):
        seen.append(([r["index"] for r in a], [r["index"] for r in b]))
        return real(a, b, mode, ref_words, **kwargs)

    monkeypatch.setattr(ca, "evaluate_session", spy)
    analysis = ca.analyze_stream(rows(64), n=8, stride=16, ref_words=128)
    assert analysis["blocks"] == 4 and analysis["disjoint_blocks"] == 4        # 64 runs / 16
    assert seen[0] == ([1, 4, 5, 8, 9, 12, 13, 16], [2, 3, 6, 7, 10, 11, 14, 15])   # A B B A A B B A ...
    monkeypatch.setattr(ca, "evaluate_session", real)
    overlapping = ca.analyze_stream(rows(64), n=8, stride=4, ref_words=128)
    assert overlapping["blocks"] == 13 and overlapping["disjoint_blocks"] == 4        # (64 - 16) / 4 + 1


def test_stream_analysis_can_fail_when_the_arms_really_differ():
    # Runs at the A positions of every block are good, at the B positions bad: the
    # systematic A/B difference a drifting or order-dependent machine would create.
    schedule = bs.interleave_schedule(8, "abba")
    stream = []
    for i in range(64):
        arm = schedule[i % 16]
        stream.append({"index": i + 1, "wer": 0.25 if arm == "A" else 0.45, "hyp_words": 120,
                       "rtf": 0.1, "decode_ms": 6000, "filler": False, "load": 0.5})
    analysis = ca.analyze_stream(stream, n=8, stride=16, ref_words=128)
    flagged = analysis["any_metric_flagged_disjoint_blocks"]["shipped"]
    assert flagged["flagged"] == 4 and flagged["sessions"] == 4


def test_p6_rule_reproduces_the_rule_it_replaced():
    from regresslib import arm_from_rows
    a = arm_from_rows(rows(8, wer=0.25), label="a", ref_words=128)
    b = arm_from_rows(rows(8, wer=0.40), label="b", ref_words=128)
    assert "wer" in ca.p6_rule_flags(a, b, seed=1)
    same = arm_from_rows(rows(8, wer=0.25), label="c", ref_words=128)
    assert ca.p6_rule_flags(a, same, seed=1) == []


def test_export_and_load_stream_round_trip(tmp_path):
    source = tmp_path / "stream.json"
    payload = {"schema": 2, "kind": "notero-aa-stream", "label": "x", "ref_words": 128, "rows": rows(5)}
    source.write_text(json.dumps(payload))
    loaded, info = ca.load_stream(source)
    assert len(loaded) == 5 and info["ref_words"] == 128


def test_merge_output_keeps_earlier_sections(tmp_path):
    out = tmp_path / "cal.json"
    ca.merge_output(out, {"simulation": {"a": 1}})
    ca.merge_output(out, {"stream:x": {"b": float("nan")}})
    data = json.loads(out.read_text())
    assert data["simulation"] == {"a": 1} and data["stream:x"] == {"b": None}   # NaN is not JSON
