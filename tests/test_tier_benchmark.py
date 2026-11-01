"""eval/tier_benchmark.py: the schedule, the Liva transcript parser and the decision gate.

The gate is the part that must not be wrong in the generous direction: a tier may replace
the default only when every condition in the plan holds. These tests build the files that
`transcribe --score` and the decodes would leave, and check `decide` against them.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "eval"))

import tier_benchmark as tb  # noqa: E402


def available(v):
    return {"status": "available", "value": v}


def unavailable(reason="not measured"):
    return {"status": "unavailable", "reason": reason}


def counts(s, d, i, n):
    return {"hits": n - s - d, "substitutions": s, "deletions": d, "insertions": i,
            "referenceLength": n, "hypothesisLength": n - d + i, "errors": s + d + i}


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


ITEMS = ["i0", "i1"]


def make_run(tmp: Path, *, wer: dict, diff: dict, rtf: dict, residency: dict, failed: dict | None = None,
             live: dict | None = None, repeats_differ: bool = False, scored: int = 2) -> Path:
    tiers = list(wer)
    schedule = [{"item": i, "tier": t, "repeat": r} for r in (0, 1) for i in ITEMS for t in tiers]
    plan = {
        "manifest": {"corpusId": "c", "items": len(ITEMS)}, "commit": "abc", "binary": {"sha256": "0" * 64},
        "tiers": {t: {"modelId": f"m-{t}", "revision": None,
                      "liveCapable": (live or tb.LIVE_CAPABLE)[t]} for t in tiers},
        "repeatItems": list(ITEMS), "schedule": schedule, "gate": dict(tb.DEFAULT_GATE),
    }
    write(tmp / "plan.json", plan)
    log = []
    for t in tiers:
        for n, item in enumerate(ITEMS):
            write(tmp / "hyp-repeat1" / t / f"{item}.json",
                  {"transcript": f"{item} {t}" + (" again" if repeats_differ else "")})
            log.append({"item": item, "tier": t, "repeat": 1, "exit": 0})
        write(tmp / "reports" / t / "report.json", {"corpus": {
            "itemsScored": scored, "itemsInManifest": 2, "wer": available(wer[t]),
            "werInterval": available({"interval": available({"lower": wer[t] - 0.01, "upper": wer[t] + 0.01})}),
            "cer": available(wer[t] / 3), "words": counts(1, 1, 1, 100), "characters": counts(1, 1, 1, 400),
            "deletionBursts": available([])}})
        for n in range(2):
            write(tmp / "hyp" / t / f"i{n}.json", {
                "transcript": f"i{n} {t}",
                "loadMs": 2000, "durationMs": 10000, "decodeMs": int(rtf[t] * 10000), "wordCount": 10,
                "performance": {"processPeakFootprintMB": available(150.0),
                                "modelResidencyMB": available(float(residency[t]))}})
            exit_code = 1 if (failed or {}).get(t, 0) > n else 0
            log.append({"item": f"i{n}", "tier": t, "repeat": 0, "exit": exit_code})
        if t != "balanced":
            d = diff[t]
            write(tmp / "reports" / f"balanced-vs-{t}" / "comparison.json", {"wer": available({
                "difference": available(d["point"]),
                "differenceInterval": available({"lower": d["lower"], "upper": d["upper"], "level": 0.95}),
                "shareCandidateLower": available(0.9)})})
    (tmp / "decode-log.jsonl").write_text("".join(json.dumps(e) + "\n" for e in log))
    return tmp / "plan.json"


def decide(plan: Path) -> dict:
    assert tb.main(["decide", "--plan", str(plan)]) == 0
    return json.loads((plan.parent / "reports" / "decision.json").read_text())


BASE = dict(wer={"fast": 0.12, "balanced": 0.10, "best": 0.08},
            rtf={"fast": 0.06, "balanced": 0.07, "best": 0.25},
            residency={"fast": 600, "balanced": 1580, "best": 3000})


def test_a_clear_win_by_a_live_capable_tier_changes_the_default(tmp_path):
    # Pretend fast is 20% better, with an interval below zero, and cheap.
    plan = make_run(tmp_path, wer={"fast": 0.08, "balanced": 0.10, "best": 0.09},
                    diff={"fast": {"point": -0.02, "lower": -0.03, "upper": -0.01},
                          "best": {"point": -0.01, "lower": -0.02, "upper": 0.005}},
                    rtf=BASE["rtf"], residency=BASE["residency"])
    d = decide(plan)
    assert d["verdicts"]["fast"]["meetsGate"] is True
    assert d["verdicts"]["best"]["meetsGate"] is False
    assert d["decision"].startswith("change the default to fast")


def test_best_cannot_become_the_default_because_it_cannot_run_live(tmp_path):
    plan = make_run(tmp_path, wer=BASE["wer"],
                    diff={"fast": {"point": 0.02, "lower": 0.01, "upper": 0.03},
                          "best": {"point": -0.02, "lower": -0.03, "upper": -0.01}},
                    rtf=BASE["rtf"], residency=BASE["residency"])
    d = decide(plan)
    checks = d["verdicts"]["best"]["checks"]
    assert checks["relativeWerImprovement"]["pass"] and checks["differenceIntervalBelowZero"]["pass"]
    assert checks["liveCapable"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_an_improvement_whose_interval_touches_zero_is_not_enough(tmp_path):
    plan = make_run(tmp_path, wer={"fast": 0.085, "balanced": 0.10, "best": 0.11},
                    diff={"fast": {"point": -0.015, "lower": -0.03, "upper": 0.001},
                          "best": {"point": 0.01, "lower": 0.0, "upper": 0.02}},
                    rtf=BASE["rtf"], residency=BASE["residency"])
    d = decide(plan)
    assert d["verdicts"]["fast"]["checks"]["relativeWerImprovement"]["pass"] is True
    assert d["verdicts"]["fast"]["checks"]["differenceIntervalBelowZero"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_a_significant_but_small_improvement_is_not_enough(tmp_path):
    plan = make_run(tmp_path, wer={"fast": 0.095, "balanced": 0.10, "best": 0.10},
                    diff={"fast": {"point": -0.005, "lower": -0.008, "upper": -0.002},
                          "best": {"point": 0.0, "lower": -0.001, "upper": 0.001}},
                    rtf=BASE["rtf"], residency=BASE["residency"])
    d = decide(plan)
    assert abs(d["verdicts"]["fast"]["checks"]["relativeWerImprovement"]["value"] - 0.05) < 1e-9
    assert d["decision"] == "keep balanced"


def test_more_failed_decodes_than_the_baseline_blocks_a_change(tmp_path):
    plan = make_run(tmp_path, wer={"fast": 0.08, "balanced": 0.10, "best": 0.10},
                    diff={"fast": {"point": -0.02, "lower": -0.03, "upper": -0.01},
                          "best": {"point": 0.0, "lower": -0.01, "upper": 0.01}},
                    rtf=BASE["rtf"], residency=BASE["residency"], failed={"fast": 1})
    d = decide(plan)
    assert d["verdicts"]["fast"]["checks"]["failedDecodes"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_a_slow_or_large_model_is_blocked(tmp_path):
    plan = make_run(tmp_path, wer={"fast": 0.08, "balanced": 0.10, "best": 0.10},
                    diff={"fast": {"point": -0.02, "lower": -0.03, "upper": -0.01},
                          "best": {"point": 0.0, "lower": -0.01, "upper": 0.01}},
                    rtf={"fast": 0.7, "balanced": 0.07, "best": 0.25},
                    residency={"fast": 5000, "balanced": 1580, "best": 3000})
    checks = decide(plan)["verdicts"]["fast"]["checks"]
    assert checks["medianWholeFileRTF"]["pass"] is False
    assert checks["modelResidencyMB"]["pass"] is False


def test_the_markdown_states_the_decision_and_every_check(tmp_path):
    plan = make_run(tmp_path, wer=BASE["wer"],
                    diff={"fast": {"point": 0.02, "lower": 0.01, "upper": 0.03},
                          "best": {"point": -0.02, "lower": -0.03, "upper": -0.01}},
                    rtf=BASE["rtf"], residency=BASE["residency"])
    decide(plan)
    md = (plan.parent / "reports" / "decision.md").read_text()
    assert "**Decision: keep balanced.**" in md
    assert md.count("| liveCapable |") == 2


def test_the_rotation_is_stable_and_covers_every_tier():
    tiers = ["fast", "balanced", "best"]
    orders = {tb.seeded_rotation(f"item{n}", 7, tiers)[0] for n in range(30)}
    assert orders == set(tiers), "every tier goes first for some items"
    assert tb.seeded_rotation("x", 7, tiers) == tb.seeded_rotation("x", 7, tiers)
    assert sorted(tb.seeded_rotation("x", 7, tiers)) == sorted(tiers)


def test_the_liva_parser_drops_tags_and_keeps_times_and_speakers():
    text = (
        "Speaker 1 [00:00:00.000 - 00:00:00.070]: [thudding]\n\n"
        "Speaker 5 [00:00:02.470 - 00:00:02.730]: Pwede.\n\n"
        "Speaker 1 [00:01:05.680 - 00:01:09.660]: Ang daming mushroom [laughing] jan. Wait lang, may-\n"
        "not a transcript line\n"
    )
    utts = tb.parse_liva_transcript(text)
    assert [u["text"] for u in utts] == ["Pwede.", "Ang daming mushroom jan. Wait lang, may-"]
    assert utts[0] == {"id": "line-3", "speaker": "Speaker 5", "startMs": 2470, "endMs": 2730,
                       "text": "Pwede.", "language": "mixed"}
    assert (utts[1]["startMs"], utts[1]["endMs"]) == (65680, 69660)


# ---- the holes the independent verification found: the gate must fail closed

WIN = dict(wer={"fast": 0.08, "balanced": 0.10, "best": 0.10},
           diff={"fast": {"point": -0.02, "lower": -0.03, "upper": -0.01},
                 "best": {"point": 0.0, "lower": -0.01, "upper": 0.01}},
           rtf=BASE["rtf"], residency=BASE["residency"])


def test_the_winning_fixture_passes_so_the_tests_below_test_one_thing_each(tmp_path):
    assert decide(make_run(tmp_path, **WIN))["verdicts"]["fast"]["meetsGate"] is True


def test_an_incomplete_scoring_blocks_a_change(tmp_path):
    d = decide(make_run(tmp_path, **WIN, scored=1))
    assert d["verdicts"]["fast"]["checks"]["allItemsScored"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_a_missing_decode_log_stops_the_decision(tmp_path):
    plan = make_run(tmp_path, **WIN)
    (tmp_path / "decode-log.jsonl").unlink()
    # Every tier would count as fully failed, which a "no more failures than the baseline"
    # check would pass. So decide refuses instead.
    assert tb.main(["decide", "--plan", str(plan)]) == 2
    assert not (tmp_path / "reports" / "decision.json").exists()


def test_a_logged_error_with_exit_zero_counts_as_failed(tmp_path):
    plan = make_run(tmp_path, **WIN)
    log = tmp_path / "decode-log.jsonl"
    lines = [json.loads(x) for x in log.read_text().splitlines()]
    for e in lines:
        if e["tier"] == "fast" and e["repeat"] == 0 and e["item"] == "i0":
            e["error"] = "model mismatch"
    log.write_text("".join(json.dumps(e) + "\n" for e in lines))
    d = decide(plan)
    assert d["verdicts"]["fast"]["checks"]["failedDecodes"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_residency_missing_on_one_item_blocks_a_change(tmp_path):
    plan = make_run(tmp_path, **WIN)
    path = tmp_path / "hyp" / "fast" / "i1.json"
    r = json.loads(path.read_text())
    r["performance"]["modelResidencyMB"] = unavailable()
    path.write_text(json.dumps(r))
    d = decide(plan)
    assert d["verdicts"]["fast"]["checks"]["residencyMeasuredOnEveryItem"]["pass"] is False


def test_a_gain_from_one_pass_of_a_nondeterministic_corpus_is_not_enough(tmp_path):
    d = decide(make_run(tmp_path, **WIN, repeats_differ=True))
    assert d["verdicts"]["fast"]["checks"]["stableAcrossDecodes"]["pass"] is False
    assert d["decision"] == "keep balanced"


def test_a_second_pass_that_agrees_makes_a_nondeterministic_gain_count(tmp_path):
    plan = make_run(tmp_path, **WIN, repeats_differ=True)
    write(tmp_path / "reports" / "repeat1" / "balanced-vs-fast" / "comparison.json", {"wer": available({
        "baseline": available(0.10), "difference": available(-0.015)})})
    check = decide(plan)["verdicts"]["fast"]["checks"]["stableAcrossDecodes"]
    assert check["pass"] is True


def test_a_second_pass_that_does_not_agree_blocks_it(tmp_path):
    plan = make_run(tmp_path, **WIN, repeats_differ=True)
    write(tmp_path / "reports" / "repeat1" / "balanced-vs-fast" / "comparison.json", {"wer": available({
        "baseline": available(0.10), "difference": available(0.006)})})
    assert decide(plan)["decision"] == "keep balanced"
