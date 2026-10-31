#!/usr/bin/env python3
"""One-off: turn the ephemeral P6 baseline in /tmp into the small committed files.

The P6 benchmark agent measured on 2026-10-31/11-01 and left its evidence in
/tmp/notero-team/baseline (per-run JSON, summaries, stderr) and
/tmp/notero-team/lead-ab. /tmp is not evidence: it is gone after a reboot. This
script reads those directories and writes, next to itself,

    p6-f022c6e-synthetic-taglish.json   every arm of the P6 sessions, run by run
    p6-lead-ab-main-vs-p6-branch.json   pre-P6 main against the P6 branch, 6 runs each

Only numbers are kept: per-run WER, word count, RTF, decodeMs, the load average
at launch, a flag for an invented-filler phrase, and the live counters. No audio,
no transcript text. It invents nothing and cannot regenerate a run: it is kept so
the provenance of the committed files is reproducible while /tmp still exists.

    python3 eval/baselines/import_p6.py [--src /tmp/notero-team/baseline] [--lead-ab /tmp/notero-team/lead-ab]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import benchstats as bs  # noqa: E402
from score import normalize  # noqa: E402

LIVE_KEYS = ("dropped_hops", "forced_commits", "unagreed_tail_words", "mean_decode_rtf",
             "infer_ms_per_hop", "commit_latency_median_ms")

ARMS = {
    # id: (summary path under --src, series id, short build name, session description)
    "offline-pure": ("offline/A", "offline-synthetic", "f022c6e pure build",
                     "offline, interleaved ABBA with the instrumented build, n = 12"),
    "offline-instrumented": ("offline/B", "offline-synthetic", "f022c6e + CLI instrumentation",
                             "offline, interleaved ABBA with the pure build, n = 12"),
    "live-pure": ("live/A", "live-synthetic", "f022c6e pure build",
                  "live replay, every decode awaited, interleaved ABBA, n = 8"),
    "live-instrumented": ("live/B", "live-synthetic", "f022c6e + CLI instrumentation",
                          "live replay, every decode awaited, interleaved ABBA, n = 8"),
    "recheck-live-pure": ("recheck/live/A", "live-synthetic", "f022c6e pure build",
                          "live recheck on a quiet machine, ABBA, n = 8"),
    "recheck-live-instrumented": ("recheck/live/B", "live-synthetic", "f022c6e + CLI instrumentation",
                                  "live recheck on a quiet machine, ABBA, n = 8"),
    "aa-live-path1": ("aa/live/A", "live-synthetic", "f022c6e pure build (path 1)",
                      "A/A: one binary against a byte-identical copy, live, ABBA, n = 8"),
    "aa-live-path2": ("aa/live/B", "live-synthetic", "f022c6e pure build (path 2, copy)",
                      "A/A: one binary against a byte-identical copy, live, ABBA, n = 8"),
    "realtime-instrumented": ("live-realtime", "live-realtime-synthetic",
                              "f022c6e + CLI instrumentation",
                              "live replay at wall-clock speed, one arm only, n = 8"),
}


def rows_of(summary: dict) -> list[dict]:
    per_run = summary["per_run"]
    rows = []
    for i, p in enumerate(per_run):
        row = {"index": p["index"], "wer": round(p["wer"], 6), "hyp_words": p["hyp_words"],
               "rtf": None if p.get("rtf") is None else round(p["rtf"], 5),
               "decode_ms": p.get("decode_ms"), "filler": bool(p.get("filler_markers")),
               "load": p.get("loadavg_1m")}
        for key in LIVE_KEYS:
            series = (summary.get("live_series") or {}).get(key) or []
            if len(series) == len(per_run):   # aligned only when no run lacked the value
                row[f"live.{key}"] = round(series[i], 5)
        rows.append({k: v for k, v in row.items() if v is not None})
    return rows


def old_rule_collapsed(rows: list[dict], ref_words: int) -> list[int]:
    """The P6 rule: WER > 2x the median of the arm's best half, or < 75% of the words."""
    wers = [r["wer"] for r in rows]
    threshold = 2.0 * bs.best_half_median(wers)
    return [r["index"] for r in rows
            if r["wer"] > threshold + 1e-12 or r["hyp_words"] < 0.75 * ref_words - 1e-12]


def new_rule_collapsed(rows: list[dict], ref_words: int) -> list[int]:
    flags, _ = bs.classify_collapsed([r["wer"] for r in rows], [r["hyp_words"] for r in rows],
                                     ref_words, filler=[r.get("filler", False) for r in rows])
    return [r["index"] for r, f in zip(rows, flags) if f]


def stats_of(rows: list[dict]) -> dict:
    return {key: bs.describe([r[key] for r in rows if r.get(key) is not None])
            for key in ("wer", "hyp_words", "rtf", "decode_ms", "load")
            if any(r.get(key) is not None for r in rows)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--src", type=Path, default=Path("/tmp/notero-team/baseline"))
    parser.add_argument("--lead-ab", type=Path, default=Path("/tmp/notero-team/lead-ab"))
    parser.add_argument("--out", type=Path, default=HERE)
    parser.add_argument("--repo-ref", type=Path, default=HERE.parent / "synthetic-taglish.txt")
    args = parser.parse_args()

    ref_text = args.repo_ref.read_text()
    ref_words = len(normalize(ref_text))
    first = json.loads((args.src / "offline/A/summary.json").read_text())
    summary_json = json.loads((args.src / "baseline-summary.json").read_text())

    arms = {}
    for arm_id, (path, series_id, build, session) in ARMS.items():
        summary = json.loads((args.src / path / "summary.json").read_text()) \
            if arm_id != "realtime-instrumented" else json.loads((args.src / path / "summary.json").read_text())
        rows = rows_of(summary)
        arms[arm_id] = {
            "series": series_id, "build": build, "session": session,
            "binary_sha256": summary["binary"]["sha256"],
            "measured_utc": summary["environment"]["date_utc"],
            "harness_commit": summary["environment"]["harness_commit"],
            "harness_eval_dir_dirty": summary["environment"]["harness_eval_dir_dirty"],
            "interleave": summary.get("interleave"), "bench_lock": summary.get("lock_used"),
            "n": len(rows), "rows": rows, "stats": stats_of(rows),
            "collapsed_by_p6_rule": old_rule_collapsed(rows, ref_words),
            "collapsed_by_current_rule": new_rule_collapsed(rows, ref_words),
        }

    baseline = {
        "schema": 2, "kind": "notero-baseline",
        "name": "p6-f022c6e-synthetic-taglish",
        "what": ("Baseline of the 2026-10-31/11-01 engineering cycle: `transcribe` built from f022c6e, "
                 "synthetic Taglish clip, Balanced tier (large-v3-turbo), forced tl, --no-diarize. "
                 "SYNTHETIC: supports A/B comparison only, never a claim about real Taglish."),
        "base_commit": summary_json["base_commit"],
        "environment": {k: first["environment"][k] for k in
                        ("hardware_model", "cpu", "memory_gb", "macos", "swift", "python", "date_utc")},
        "model": first["model"],
        "fixtures": {"synthetic-taglish": {"sha256": first["audio"]["sha256"],
                                           "reference_sha256": first["reference"]["sha256"],
                                           "ref_words": ref_words}},
        "provenance": {
            "measured_by": "the P6 benchmark agent (eval/bench_runs.py), then re-imported by import_p6.py",
            "harness_commits": sorted({a["harness_commit"] for a in arms.values()}),
            "note": ("Early sessions ran harness d01f895 with uncommitted changes in eval/ "
                     "(harness_eval_dir_dirty); the harness that produced the later ones is 1a8ab42, "
                     "and the final form is 62780a8. The collapse flags here are recomputed from the "
                     "per-run numbers under both rules."),
            "source_dir": str(args.src),
        },
        "series": {
            "offline-synthetic": {"base_arm": "offline-pure", "mode": "offline",
                                  "stats": arms["offline-pure"]["stats"]},
            "live-synthetic": {"base_arm": "live-pure", "mode": "live",
                               "stats": arms["live-pure"]["stats"]},
        },
        "arms": arms,
    }
    (args.out / "p6-f022c6e-synthetic-taglish.json").write_text(
        json.dumps(baseline, indent=1, sort_keys=True) + "\n")

    # --- the lead's pre-P6 against P6 branch comparison -------------------
    lead = {}
    for arm, build in (("A", "main at addf5f8 (pre-P6)"), ("B", "P6 branch (greedy-first + lead-in retry)")):
        rows = []
        for i in range(1, 7):
            report = json.loads((args.lead_ab / f"{arm}-{i}.json").read_text())
            hyp = normalize(report["transcript"])
            rows.append({"index": i, "wer": round(report["wer"], 6), "hyp_words": len(hyp),
                         "rtf": round(report["rtf"], 5), "decode_ms": report["decodeMs"]})
        lead[arm] = {"build": build, "n": len(rows), "rows": rows,
                     "collapsed_by_p6_rule": old_rule_collapsed(rows, ref_words)}
    pooled = bs.reference_level([r["wer"] for r in lead["A"]["rows"]], [r["wer"] for r in lead["B"]["rows"]])
    for arm in "AB":
        flags, _ = bs.classify_collapsed([r["wer"] for r in lead[arm]["rows"]],
                                         [r["hyp_words"] for r in lead[arm]["rows"]],
                                         ref_words, level=pooled)
        lead[arm]["collapsed_by_current_rule"] = [r["index"] for r, f in zip(lead[arm]["rows"], flags) if f]
    comparison = {
        "schema": 2, "kind": "notero-baseline", "name": "p6-lead-ab-main-vs-p6-branch",
        "what": ("The lead's A/B of pre-P6 main (addf5f8) against the P6 branch on the synthetic clip, "
                 "offline, 6 runs each, interleaved. Evidence that the first-window collapse was fixed: "
                 "main collapsed 4 of 6, the P6 branch gave the same 24.2% WER six times. "
                 "The P6 rule counted 1 of main's 6 runs as collapsed (its best-half median is 35.2%, so "
                 "the WER threshold was 70.4%; that one run was caught by the word floor); the current "
                 "rule counts 4."),
        "environment": {k: first["environment"][k] for k in
                        ("hardware_model", "cpu", "memory_gb", "macos")},
        "model": first["model"], "fixtures": baseline["fixtures"],
        "provenance": {"source_dir": str(args.lead_ab), "script": "run.sh in that directory",
                       "lock": "taken once for the whole 12-run loop",
                       "caveat": "n = 6 per arm: below the 8 the harness needs for a verdict. "
                                 "Context for the collapse rule, not a test."},
        "arms": lead,
    }
    (args.out / "p6-lead-ab-main-vs-p6-branch.json").write_text(
        json.dumps(comparison, indent=1, sort_keys=True) + "\n")
    for name in ("p6-f022c6e-synthetic-taglish.json", "p6-lead-ab-main-vs-p6-branch.json"):
        print(name, (args.out / name).stat().st_size, "bytes")
    for arm_id, a in arms.items():
        print(f"{arm_id:28s} n={a['n']:2d} collapsed p6={a['collapsed_by_p6_rule']} now={a['collapsed_by_current_rule']}")
    for arm in "AB":
        print("lead", arm, "p6", lead[arm]["collapsed_by_p6_rule"], "now", lead[arm]["collapsed_by_current_rule"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
