"""Diarization metrics and the comparison runner (eval/diarization_metrics.py,
eval/diarization_eval.py). No audio, models or binaries: segments built in code,
and the runner's decision logic fed synthetic score rows.
"""

from __future__ import annotations

import itertools
import json
import random
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import der  # noqa: E402
import diarization_eval as de  # noqa: E402
import diarization_metrics as dm  # noqa: E402

S = der.Segment
NO_COLLAR = dm.Rules(collar=0.0)


def ev(ref, hyp, **kw):
    return dm.evaluate(ref, hyp, dm.Rules(**{"collar": 0.0, **kw}))


# --- agreement with der.py ---------------------------------------------------

def random_segments(rng, speakers, n, horizon=60.0):
    out = []
    for _ in range(n):
        start = rng.uniform(0, horizon - 1)
        out.append(S(round(start, 2), round(start + rng.uniform(0.3, 6), 2), rng.choice(speakers)))
    return out


@pytest.mark.parametrize("seed", range(25))
def test_der_and_its_parts_equal_der_py_on_random_input(seed):
    rng = random.Random(seed)
    ref = random_segments(rng, ["a", "b", "c", "d"][: rng.randint(1, 4)], 12)
    hyp = random_segments(rng, ["x", "y", "z", "w", "v"][: rng.randint(1, 5)], 14)
    for collar in (0.0, 0.25):
        old = der.score(ref, hyp, collar=collar).as_dict()
        new = dm.evaluate(ref, hyp, dm.Rules(collar=collar))
        for key in ("der", "missed", "false_alarm", "confusion"):
            assert new[key] == pytest.approx(old[key], abs=1e-6), (seed, collar, key)


@pytest.mark.parametrize("seed", range(40))
def test_the_subset_programme_finds_the_same_total_as_exhaustive_search(seed):
    rng = random.Random(seed)
    n_ref, n_hyp = rng.randint(1, 5), rng.randint(0, 7)
    co = [[rng.randint(0, 9) for _ in range(n_hyp)] for _ in range(n_ref)]
    mapping = dm.optimal_mapping(co)
    got = sum(co[r][h] for r, h in mapping.items() if h is not None)
    best = 0
    pool = list(range(n_hyp)) + [None] * n_ref
    for choice in itertools.permutations(pool, n_ref):
        best = max(best, sum(co[r][h] for r, h in enumerate(choice) if h is not None))
    assert got == best
    used = [h for h in mapping.values() if h is not None]
    assert len(used) == len(set(used))


# --- overlap -----------------------------------------------------------------

def test_overlap_named_once_is_missed_and_counted_in_the_overlap_region():
    ref = [S(0, 10, "a"), S(5, 10, "b")]
    hyp = [S(0, 10, "x")]
    r = ev(ref, hyp)
    assert r["overlap"]["speech_s"] == pytest.approx(10)    # 5 s, two speakers
    assert r["overlap"]["missed_s"] == pytest.approx(5)
    assert r["single"]["der"] == 0
    assert r["overlap"]["detection_recall"] == 0
    assert r["overlap"]["share_of_speech"] == pytest.approx(10 / 15)


def test_overlap_marked_by_the_hypothesis_is_detected():
    ref = [S(0, 10, "a"), S(5, 10, "b")]
    hyp = [S(0, 10, "x"), S(5, 10, "y")]
    r = ev(ref, hyp)
    assert r["der"] == 0
    assert r["overlap"]["detection_recall"] == 1
    assert r["overlap"]["detection_precision"] == 1


def test_skip_overlap_removes_overlapped_frames_from_the_score():
    ref = [S(0, 10, "a"), S(5, 10, "b")]
    hyp = [S(0, 10, "x")]
    r = ev(ref, hyp, skip_overlap=True)
    assert r["speech_s"] == pytest.approx(5)
    assert r["der"] == 0


def test_the_collar_is_around_reference_boundaries_only():
    ref = [S(0, 10, "a")]
    hyp = [S(0.2, 10, "x"), S(4, 4.5, "y")]
    r = dm.evaluate(ref, hyp, dm.Rules(collar=0.25))
    # The late start is forgiven; the wrong half second in the middle is not.
    assert r["confusion_s"] + r["false_alarm_s"] == pytest.approx(0.5, abs=0.02)


# --- merges and fragments ----------------------------------------------------

def test_two_people_under_one_label_are_a_merge():
    ref = [S(0, 10, "a"), S(10, 20, "b"), S(20, 30, "c")]
    hyp = [S(0, 20, "x"), S(20, 30, "y")]
    r = ev(ref, hyp)
    assert r["merges"] == [{"hyp": "x", "ref": ["a", "b"]}]
    assert r["merged_ref_speakers"] == 2
    assert r["fragmented_ref_speakers"] == []
    assert r["speakers"]["count_error"] == -1


def test_a_short_speaker_is_not_judged_for_merges():
    ref = [S(0, 10, "a"), S(10, 12, "b")]
    hyp = [S(0, 12, "x")]
    r = ev(ref, hyp)
    assert r["merges"] == []
    assert r["speakers"]["judged_ref"] == 1


def test_one_person_under_two_labels_is_fragmented():
    ref = [S(0, 20, "a"), S(20, 30, "b")]
    hyp = [S(0, 12, "x"), S(12, 20, "z"), S(20, 30, "y")]
    r = ev(ref, hyp)
    assert r["pieces"]["a"] == 2
    assert r["fragmented_ref_speakers"] == ["a"]
    assert r["merges"] == []
    assert r["speakers"]["count_error"] == 1


def test_a_sliver_under_the_fragment_share_is_not_a_piece():
    ref = [S(0, 20, "a")]
    hyp = [S(0, 19, "x"), S(19, 20, "z")]
    r = ev(ref, hyp)
    assert r["pieces"]["a"] == 1
    assert r["fragmented_ref_speakers"] == []


def test_a_tiny_hypothesis_speaker_is_not_counted():
    ref = [S(0, 10, "a")]
    hyp = [S(0, 10, "x"), S(10, 10.5, "z")]
    assert ev(ref, hyp)["speakers"]["hyp"] == 1


# --- timestamps and pooling --------------------------------------------------

def test_timestamp_problems():
    spans = [{"start": 0, "end": 1}, {"start": 2, "end": 2}, {"start": -1, "end": 1},
             {"start": 5, "end": 10.5}, {"start": float("nan"), "end": 1}, {"start": 3, "end": 9.99}]
    problems = dm.timestamp_problems(spans, duration_s=10)
    assert [p.split(":")[0] for p in problems] == ["span 1", "span 2", "span 3", "span 4"]


def test_overlapping_spans_of_two_speakers_are_valid_timestamps():
    assert dm.timestamp_problems([{"start": 0, "end": 5}, {"start": 3, "end": 6}], 6) == []


def test_pooled_der_weights_by_speech_not_by_file():
    long = ev([S(0, 90, "a")], [S(0, 90, "x")])                 # 0 errors in 90 s
    short = ev([S(0, 10, "a")], [])                              # 10 s missed of 10
    p = dm.pooled([long, short])
    assert p["der"] == pytest.approx(10 / 100)
    assert p["missed"] == pytest.approx(10 / 100)


# --- Liva reference ----------------------------------------------------------

def test_liva_lines_with_only_event_tags_are_not_speech():
    text = ("Speaker 1 [00:00:00.000 - 00:00:00.070]: [thudding]\n\n"
            "Speaker 5 [00:00:02.470 - 00:00:02.730]: Pwede.\n"
            "Speaker 1 [00:01:05.680 - 00:01:09.660]: [laughing] Wait lang, sa harapan natin.\n"
            "Speaker 2 [00:00:03.000 - 00:00:03.000]: Empty.\n"
            "garbage line\n")
    segs = de.parse_liva_speech(text)
    assert segs == [S(2.47, 2.73, "Speaker5"), S(65.68, 69.66, "Speaker1")]


# --- decision ----------------------------------------------------------------

def row(arm, item, corpus, der_value, run=1, merged=0, rtf=0.01, peak=300.0, ts=None, fp="f"):
    speech = 100.0
    primary = {"der": der_value, "speech_s": speech, "errors_s": der_value * speech,
               "missed_s": 0.0, "false_alarm_s": 0.0, "confusion_s": der_value * speech,
               "single": {"speech_s": speech, "errors_s": 0.0, "missed_s": 0.0,
                          "false_alarm_s": 0.0, "confusion_s": 0.0},
               "overlap": {"speech_s": 0.0, "errors_s": 0.0, "missed_s": 0.0,
                           "false_alarm_s": 0.0, "confusion_s": 0.0},
               "merged_ref_speakers": merged, "fragmented_ref_speakers": [],
               "speakers": {"count_error": 0}}
    return {"arm": arm, "item": item, "corpus": corpus, "run": run, "primary": primary,
            "rtf": rtf, "peakFootprintMB": peak, "timestampProblems": ts or [], "fingerprint": fp}


def plan_for(items, runs=2):
    order = [{"arm": a, "item": i, "run": k} for k in range(1, runs + 1) for i, _ in items
             for a in ("base", "cand")]
    return {"baseline": "base", "candidates": ["cand"], "primaryCandidate": "cand",
            "gate": de.DEFAULT_GATE,
            "items": [{"id": i, "corpus": c} for i, c in items], "order": order}


ITEMS = [("ami-1", "ami"), ("liva-1", "liva"), ("syn-1", "synth")]


def ident(arm, wrong, seconds=100.0, variant="noise40"):
    return {"arm": arm, "item": "liva-1", "corpus": "liva", "variant": variant,
            "carry": {"right": 100 - wrong, "wrong": wrong, "default": 0.0, "seconds": seconds},
            "label": {"right": 100 - wrong, "wrong": wrong, "default": 0.0, "seconds": seconds}}


IDENT = [ident("base", 5.0), ident("cand", 5.5)]


def rows_for(cand_der, base_der=0.20, **cand_kw):
    out = []
    for run in (1, 2):
        for item, corpus in ITEMS:
            out.append(row("base", item, corpus, base_der, run=run))
            out.append(row("cand", item, corpus, cand_der, run=run, **cand_kw))
    return out


def test_a_candidate_fifteen_percent_better_everywhere_passes():
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.16), "failedRuns": []}, IDENT)
    assert result["candidates"]["cand"]["passesGate"], result
    assert result["recommendation"].startswith("cand passes")


def test_ten_percent_better_is_not_enough():
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.18), "failedRuns": []}, IDENT)
    checks = result["candidates"]["cand"]["checks"]
    assert not checks["relativeDerImprovement:ami"]["pass"]
    assert result["recommendation"].startswith("keep base")


def test_better_on_one_real_corpus_only_fails():
    rows = rows_for(0.10)
    for r in rows:
        if r["arm"] == "cand" and r["corpus"] == "liva":
            r["primary"]["der"] = 0.30
            r["primary"]["errors_s"] = 30.0
    result = de.decide(plan_for(ITEMS), {"rows": rows, "failedRuns": []}, IDENT)
    checks = result["candidates"]["cand"]["checks"]
    assert checks["relativeDerImprovement:ami"]["pass"]
    assert not checks["relativeDerImprovement:liva"]["pass"]
    assert not result["candidates"]["cand"]["passesGate"]


@pytest.mark.parametrize("kw,check", [
    ({"merged": 2}, "noNewMerges"),
    ({"ts": ["span 1: ends at or before its start"]}, "timestampsValid"),
    ({"peak": 4096.0}, "peakFootprint"),
    ({"rtf": 0.5}, "realTimeFactor"),
])
def test_each_guard_can_fail_a_much_better_candidate(kw, check):
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.05, **kw), "failedRuns": []}, IDENT)
    assert not result["candidates"]["cand"]["checks"][check]["pass"]
    assert not result["candidates"]["cand"]["passesGate"]


def test_an_unstable_candidate_fails():
    rows = rows_for(0.05)
    for r in rows:
        if r["arm"] == "cand" and r["run"] == 2 and r["item"] == "syn-1":
            r["primary"]["der"] = 0.09
    result = de.decide(plan_for(ITEMS), {"rows": rows, "failedRuns": []}, IDENT)
    assert not result["candidates"]["cand"]["checks"]["repeatStable"]["pass"]


def test_a_missing_or_failed_run_fails_closed():
    rows = [r for r in rows_for(0.05) if not (r["arm"] == "cand" and r["item"] == "syn-1" and r["run"] == 2)]
    result = de.decide(plan_for(ITEMS), {"rows": rows, "failedRuns": []}, IDENT)
    assert not result["candidates"]["cand"]["checks"]["allRunsScored"]["pass"]
    failed = [{"arm": "cand", "item": "ami-1", "run": 1, "ok": False}]
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.05), "failedRuns": failed}, IDENT)
    assert not result["candidates"]["cand"]["checks"]["allRunsScored"]["pass"]


def test_a_real_corpus_with_no_rows_fails():
    rows = [r for r in rows_for(0.05) if r["corpus"] != "liva"]
    result = de.decide(plan_for(ITEMS), {"rows": rows, "failedRuns": []}, IDENT)
    assert not result["candidates"]["cand"]["checks"]["relativeDerImprovement:liva"]["pass"]


def test_plan_order_interleaves_arms_and_is_seeded(tmp_path):
    manifest = tmp_path / "m.json"
    manifest.write_text(json.dumps({"items": [
        {"id": f"i{k}", "corpus": "c", "audio": "a.wav", "ref": "r.rttm", "refSpeakers": 2,
         "durationS": 1.0} for k in range(4)]}))
    plans = []
    for out in ("p1", "p2"):
        assert de.main(["plan", "--manifest", str(manifest),
                        "--arm", "a=/bin/echo {audio} {json}", "--arm", "b=/bin/echo {audio} {json}",
                        "--runs", "2", "--wrap", "--out", str(tmp_path / out)]) == 0
        plans.append(json.loads((tmp_path / out / "plan.json").read_text()))
    assert plans[0]["order"] == plans[1]["order"]
    assert len(plans[0]["order"]) == 16
    assert plans[0]["gate"] == de.DEFAULT_GATE
    assert plans[0]["wrap"] == []
    firsts = {tuple(o["arm"] for o in plans[0]["order"][k:k + 2]) for k in range(0, 16, 2)}
    assert firsts == {("a", "b"), ("b", "a")}


def test_an_arm_needs_audio_and_json_placeholders():
    with pytest.raises(Exception):
        de.parse_arm("a=/bin/echo {audio}")


def test_names_carried_wrongly_more_often_fail_the_gate():
    rows = [ident("base", 5.0), ident("cand", 6.5)]
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.05), "failedRuns": []}, rows)
    assert not result["candidates"]["cand"]["checks"]["speakerNamesCarry"]["pass"]


def test_no_identity_run_fails_closed():
    result = de.decide(plan_for(ITEMS), {"rows": rows_for(0.05), "failedRuns": []}, None)
    assert not result["candidates"]["cand"]["checks"]["speakerNamesCarry"]["pass"]
    assert not result["candidates"]["cand"]["passesGate"]


def test_identity_summary_pools_by_seconds():
    rows = [ident("a", 10.0, seconds=100.0), ident("a", 0.0, seconds=300.0, variant="aac64")]
    s = de.identity_summary(rows, "a")
    assert s["carry"]["wrong"] == pytest.approx(2.5)
    assert s["runs"] == 2


def test_rescore_reads_other_references_by_meeting_name(tmp_path):
    out = tmp_path / "run"
    (out / "runs" / "a").mkdir(parents=True)
    (out / "runs" / "a" / "ami-M1.r1.json").write_text(json.dumps(
        {"spans": [{"start": 0, "end": 10, "speaker": "S1"}]}))
    refs = tmp_path / "refs"
    refs.mkdir()
    der.write_rttm([S(0, 10, "x")], refs / "M1.rttm", "M1")
    plan = {"arms": [{"label": "a"}], "items": [{"id": "ami-M1", "corpus": "ami"}],
            "rules": {"primary": dm.Rules().as_dict(), "secondary": []}}
    (out / "plan.json").write_text(json.dumps(plan))
    assert de.main(["rescore", "--plan", str(out / "plan.json"), "--corpus", "ami",
                    "--refs", str(refs), "--label", "alt"]) == 0
    result = json.loads((out / "rescore-alt.json").read_text())
    assert result["pooled"]["a"][0]["der"] == 0
    assert result["references"][0]["item"] == "ami-M1"


def test_a_repeated_file_without_reference_speech_fails_closed_without_crashing():
    rows = rows_for(0.05)
    for r in rows:
        if r["arm"] == "cand" and r["item"] == "syn-1":
            r["primary"]["der"] = None
    result = de.decide(plan_for(ITEMS), {"rows": rows, "failedRuns": []}, IDENT)
    check = result["candidates"]["cand"]["checks"]["repeatStable"]
    assert not check["pass"] and check["unscorable"] == ["syn-1"]


def test_decide_refuses_scores_from_another_plan(tmp_path):
    out = tmp_path / "run"
    out.mkdir()
    (out / "plan.json").write_text(json.dumps(plan_for(ITEMS)))
    (out / "scores.json").write_text(json.dumps({"planSha256": "0" * 64, "rows": [], "failedRuns": []}))
    assert de.main(["decide", "--plan", str(out / "plan.json")]) == 2
