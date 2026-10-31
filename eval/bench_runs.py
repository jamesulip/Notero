"""Repeated, interleaved benchmark runs of a `transcribe` binary, and an A/B compare.

One run of `transcribe` proves nothing: the offline pass is not deterministic, and
eight identical runs of the synthetic clip spanned 25% to 57% WER (FINDINGS 15).
This harness runs a binary N times, records every run, summarizes with order
statistics, and compares two summaries with tests that make no distributional
assumption. Standard library only; it drives the existing `transcribe` CLI and
reuses `score.py` and `langscore.py` for scoring.

    # N runs of one binary
    bench_runs.py run --bin app/.build/release/transcribe \\
        --audio /path/synthetic-taglish.wav --ref eval/synthetic-taglish.txt \\
        --mode offline --runs 12 --out-dir /tmp/notero-team/baseline/offline

    # Baseline against candidate, alternating A B A B ..., one summary each
    bench_runs.py run --interleave BASE_BIN CAND_BIN \\
        --audio ... --ref ... --mode live --runs 8 --out-dir /tmp/ab-live

    # Re-summarize a directory of runs, or compare two summaries
    bench_runs.py summarize /tmp/ab-live/A
    bench_runs.py compare /tmp/ab-live/A/summary.json /tmp/ab-live/B/summary.json

Every measured run goes through /tmp/notero-team/bench-lock.sh when that file
exists (one Neural Engine; two concurrent runs corrupt each other's RTF), taking
the lock for that run only. `--no-lock` turns it off.

What the numbers are, and are not:

  * WER is scored by `score.py` (the pooled scorer, which splits intra-word
    hyphens as the CLI does). The CLI's own WER is kept beside it as `cli_wer`.
  * "RTF" is the CLI's `rtf` = decodeMs / audio duration. Offline, that is the
    whole-file RTF (VAD, windows and retries included; model load excluded).
    Live, it is the REPLAY RTF: with every decode awaited it measures how fast the
    machine replays the file, and under `--realtime` it is about 1.0 by
    construction. Neither is a per-hop cost; that is `mean_decode_rtf` and
    `infer_ms_per_hop`.
  * Memory figures are the footprint of one process. They are not model residency.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(EVAL_DIR))

import benchstats as bs  # noqa: E402
from langscore import score as lang_score  # noqa: E402
from score import levenshtein, normalize  # noqa: E402

REPO = EVAL_DIR.parent
LOCK_SCRIPT = Path("/tmp/notero-team/bench-lock.sh")
TIME_BINARY = Path("/usr/bin/time")
SCHEMA = 1

#: Phrases Whisper invents out of silence or a hostile window. Informational:
#: it explains a collapse, and the collapse rule does not depend on it.
FILLER_MARKERS = (
    "thank you so much for watching",
    "thanks for watching",
    "thank you for watching",
    "please subscribe",
    "like and subscribe",
    "welcome to meeting",
    "thank goodness",
)


# --------------------------------------------------------------------------
# Parsing and scoring one run (pure; tested)
# --------------------------------------------------------------------------

def parse_stderr(text: str) -> dict:
    """What `transcribe` and `/usr/bin/time -l` say on stderr that the JSON
    report does not. Missing lines give missing keys; nothing is guessed."""
    out: dict = {}

    def grab(pattern: str, key: str, cast=int) -> None:
        match = re.search(pattern, text, re.MULTILINE)
        if match:
            out[key] = cast(match.group(1))

    grab(r"^speech: (\d+) regions", "regions")
    grab(r"regions, \S+ in (\d+) windows", "windows")
    grab(r"^\s+(\d+) window\(s\) needed a (?:warmer )?retry", "retried_windows")
    grab(r"WARNING (\d+) window\(s\) never decoded", "dropped_windows")
    grab(r"^model load (\d+) ms", "load_ms")
    # Old binaries print "peak memory N MB" (phys_footprint read once at exit).
    grab(r"^peak memory (\d+) MB", "cli_footprint_at_exit_mb")
    # New binaries say what it is.
    grab(r"footprint at exit (\d+) MB", "cli_footprint_at_exit_mb")
    grab(r"lifetime peak footprint (\d+) MB", "cli_lifetime_peak_footprint_mb")
    grab(r"NOT in the footprint: (\d+) MB now", "cli_neural_at_exit_mb")
    grab(r"NOT in the footprint: \d+ MB now, (\d+) MB peak", "cli_neural_peak_mb")
    # `/usr/bin/time -l`, which reports bytes.
    grab(r"^\s*(\d+)\s+maximum resident set size", "time_max_rss_bytes")
    grab(r"^\s*(\d+)\s+peak memory footprint", "time_peak_footprint_bytes")
    return out


def filler_markers(reference: str, hypothesis: str) -> list[str]:
    """Invented-filler phrases present in the hypothesis and absent from the
    reference, matched on normalized words."""
    ref = " ".join(normalize(reference))
    hyp = " ".join(normalize(hypothesis))
    return [m for m in FILLER_MARKERS if m in hyp and m not in ref]


def score_run(reference: str, report: dict) -> dict:
    """WER by `score.py`, the per-language errors by `langscore.py`, and the
    CLI's own WER beside them so a scorer mismatch is visible, not silent."""
    transcript = report.get("transcript", "")
    ref_words = normalize(reference)
    hyp_words = normalize(transcript)
    subs, dels, ins = levenshtein(ref_words, hyp_words)
    wer = (subs + dels + ins) / len(ref_words) if ref_words else None
    result = {
        "wer": wer,
        "sub": subs,
        "del": dels,
        "ins": ins,
        "ref_words": len(ref_words),
        "hyp_words": len(hyp_words),
        "cli_wer": report.get("wer"),
        "filler_markers": filler_markers(reference, transcript),
    }
    try:
        lang = lang_score(reference, transcript)
        result["langscore_wer"] = lang["wer"]
        result["tl_error_rate"] = lang["by_class"]["tl"]["error_rate"]
        result["en_error_rate"] = lang["by_class"]["en"]["error_rate"]
        result["code_switch_error_rate"] = lang["code_switch"]["error_rate"]
    except Exception as error:  # a scorer problem must not lose the run
        result["langscore_error"] = str(error)
    return result


def live_metrics(report: dict) -> dict:
    """The live counters, plus per-hop figures derived from them."""
    stats = report.get("live") or {}
    if not stats:
        return {}
    hops = stats.get("hops", 0)
    infer_ms = stats.get("totalInferMs", 0)
    audio_ms = stats.get("totalAudioMs", 0)
    out = {
        "hops": hops,
        "dropped_hops": stats.get("droppedHops", 0),
        "forced_commits": stats.get("forcedCommits", 0),
        "unagreed_tail_words": stats.get("unagreedTailCommits", 0),
        "duplicates_dropped": stats.get("duplicatesDropped", 0),
        "skipped_silent": stats.get("skippedSilent", 0),
        "failed_hops": stats.get("failedHops", 0),
        "empty_results": stats.get("emptyResults", 0),
        "boundaries": stats.get("boundaries", 0),
        "finalizations": stats.get("finalizations", 0),
        "mean_decode_rtf": (infer_ms / audio_ms) if audio_ms else None,
        "infer_ms_per_hop": (infer_ms / hops) if hops else None,
        "sampled_peak_footprint_mb": stats.get("peakMemoryMB"),
    }
    timing = report.get("decodeTiming")
    if timing:
        out["decode_median_infer_ms"] = timing.get("medianInferMs")
        out["decode_p95_infer_ms"] = timing.get("p95InferMs")
        out["decode_max_infer_ms"] = timing.get("maxInferMs")
        out["decode_wall_rtf"] = timing.get("wallRtf")
    latency = report.get("commitLatency")
    if latency:
        out["commit_latency_median_ms"] = latency.get("medianMs")
        out["commit_latency_p95_ms"] = latency.get("p95Ms")
        out["commit_latency_max_ms"] = latency.get("maxMs")
    wall = report.get("commitLatencyWall")
    if wall:
        out["commit_latency_wall_median_ms"] = wall.get("medianMs")
        out["commit_latency_wall_p95_ms"] = wall.get("p95Ms")
    return out


def memory_stages(report: dict) -> dict:
    """Footprint by stage, from a binary that reports them. Empty for older ones."""
    stages = {}
    for snapshot in report.get("memory") or []:
        stages[snapshot["stage"]] = {
            "phys_footprint_mb": snapshot.get("physFootprintMB"),
            "resident_mb": snapshot.get("residentMB"),
            "internal_mb": snapshot.get("internalMB"),
            "external_mb": snapshot.get("externalMB"),
            "lifetime_peak_footprint_mb": snapshot.get("lifetimePeakFootprintMB"),
            "neural_mb": snapshot.get("neuralMB"),
            "neural_peak_mb": snapshot.get("neuralPeakMB"),
        }
    return stages


# --------------------------------------------------------------------------
# Summarizing a set of runs (pure; tested)
# --------------------------------------------------------------------------

def _values(records: list[dict], getter) -> list[float]:
    out = []
    for record in records:
        value = getter(record)
        if value is not None:
            out.append(value)
    return out


def summarize_records(records: list[dict], *, meta: dict) -> dict:
    """One summary from per-run records. `meta` carries what the records do not
    repeat (label, mode, binary, audio, reference, environment, interleave)."""
    ok = [r for r in records if r.get("ok")]
    failed = [r for r in records if not r.get("ok")]
    mode = meta.get("mode", "offline")
    ref_words = ok[0]["score"]["ref_words"] if ok else None

    wers = [r["score"]["wer"] for r in ok]
    hyp_words = [r["score"]["hyp_words"] for r in ok]
    flags, threshold = (bs.classify_collapsed(wers, hyp_words, ref_words)
                        if ok else ([], float("nan")))

    per_run = []
    for record, flag in zip(ok, flags):
        report = record["report"]
        per_run.append({
            "index": record["index"],
            "wer": record["score"]["wer"],
            "cli_wer": record["score"]["cli_wer"],
            "hyp_words": record["score"]["hyp_words"],
            "rtf": report.get("rtf"),
            "decode_ms": report.get("decodeMs"),
            "collapsed": flag,
            "filler_markers": record["score"]["filler_markers"],
            "loadavg_1m": record.get("loadavg_1m_at_launch"),
            "retried_windows": record["stderr_info"].get("retried_windows"),
            "dropped_windows": record["stderr_info"].get("dropped_windows"),
        })

    summary = {
        "schema": SCHEMA,
        **meta,
        "runs_attempted": len(records),
        "runs_ok": len(ok),
        "runs_failed": len(failed),
        "failures": [{"index": r["index"], "returncode": r.get("returncode"),
                      "error": r.get("error"), "stderr_tail": r.get("stderr_tail")}
                     for r in failed],
        "collapse": {
            "rule": bs.COLLAPSE_RULE,
            "ref_words": ref_words,
            "wer_threshold": None if not ok else threshold,
            "word_floor": None if ref_words is None else bs.COLLAPSE_MIN_WORD_FRACTION * ref_words,
            "collapsed_runs": sum(flags),
            "collapsed_indices": [p["index"] for p in per_run if p["collapsed"]],
            "runs_with_filler_markers": sum(1 for p in per_run if p["filler_markers"]),
            "runs_with_retried_window": sum(1 for p in per_run if p["retried_windows"]),
            "windows_retried_total": sum(p["retried_windows"] or 0 for p in per_run),
            "windows_never_decoded_total": sum(p["dropped_windows"] or 0 for p in per_run),
        },
        "wer": bs.describe(wers),
        "cli_wer": bs.describe(_values(ok, lambda r: r["score"]["cli_wer"])),
        "hyp_words": bs.describe([float(w) for w in hyp_words]),
        "rtf": bs.describe(_values(ok, lambda r: r["report"].get("rtf"))),
        "rtf_meaning": ("whole-file RTF: decodeMs / audio duration, VAD and retries included, "
                        "model load excluded" if mode == "offline" else
                        "REPLAY RTF: wall time of the replay / audio duration. Awaited decodes: "
                        "machine throughput on this schedule. --realtime: about 1.0 by construction. "
                        "Not a per-hop cost; see live.mean_decode_rtf"),
        "decode_ms": bs.describe(_values(ok, lambda r: r["report"].get("decodeMs"))),
        "load_ms": bs.describe(_values(ok, lambda r: r["report"].get("loadMs"))),
        "loadavg_1m_at_launch": bs.describe(_values(ok, lambda r: r.get("loadavg_1m_at_launch"))),
        "tl_error_rate": bs.describe(_values(ok, lambda r: r["score"].get("tl_error_rate"))),
        "en_error_rate": bs.describe(_values(ok, lambda r: r["score"].get("en_error_rate"))),
        "per_run": per_run,
    }

    if mode.startswith("live"):
        live_keys = ["hops", "dropped_hops", "forced_commits", "unagreed_tail_words",
                     "duplicates_dropped", "failed_hops", "mean_decode_rtf", "infer_ms_per_hop",
                     "decode_p95_infer_ms", "decode_max_infer_ms", "commit_latency_median_ms",
                     "commit_latency_p95_ms", "commit_latency_wall_median_ms"]
        summary["live"] = {
            key: bs.describe(_values(ok, lambda r, k=key: r["live"].get(k)))
            for key in live_keys
        }
        summary["live_series"] = {
            key: _values(ok, lambda r, k=key: r["live"].get(k)) for key in live_keys}
        summary["live"]["meaning"] = {
            "mean_decode_rtf": "sum of model inference time / sum of audio decoded, over all hops "
                               "(audio includes context and pre-roll). A per-decode cost.",
            "infer_ms_per_hop": "mean model-reported inference time of one decode, in ms",
            "commit_latency": "clock at commit minus the word's end time. Median/p95 are over words "
                              "within one run; the figure here is the median across runs. The "
                              "clock is audio fed so far (mechanism), or wall time (…_wall_…, "
                              "--realtime only).",
        }

    memory_keys = {
        "cli_footprint_at_exit_mb": lambda r: r["stderr_info"].get("cli_footprint_at_exit_mb"),
        "cli_lifetime_peak_footprint_mb":
            lambda r: r["stderr_info"].get("cli_lifetime_peak_footprint_mb"),
        "cli_neural_peak_mb": lambda r: r["stderr_info"].get("cli_neural_peak_mb"),
        "time_max_rss_mb": lambda r: _mb(r["stderr_info"].get("time_max_rss_bytes")),
        "time_peak_footprint_mb": lambda r: _mb(r["stderr_info"].get("time_peak_footprint_bytes")),
    }
    memory = {key: bs.describe(_values(ok, getter)) for key, getter in memory_keys.items()}
    stage_names = sorted({s for r in ok for s in r["memory"]})
    memory["stages_phys_footprint_mb"] = {
        stage: bs.describe(_values(ok, lambda r, s=stage:
                                   (r["memory"].get(s) or {}).get("phys_footprint_mb")))
        for stage in stage_names
    }
    memory["stages_resident_mb"] = {
        stage: bs.describe(_values(ok, lambda r, s=stage:
                                   (r["memory"].get(s) or {}).get("resident_mb")))
        for stage in stage_names
    }
    memory["stages_neural_mb"] = {
        stage: bs.describe(_values(ok, lambda r, s=stage:
                                   (r["memory"].get(s) or {}).get("neural_mb")))
        for stage in stage_names
    }
    memory["meaning"] = (
        "PROCESS FOOTPRINT, not model residency. phys_footprint counts dirty and compressed "
        "pages of this process only; it does NOT include the Neural Engine memory that CoreML "
        "owns for the loaded model. That is reported apart as neural_mb ('neural, nofootprint' "
        "in footprint(1)). 'cli_footprint_at_exit_mb' is the CLI's old 'peak memory' line: one "
        "reading at exit, not a peak. time_* come from /usr/bin/time -l (true lifetime peak "
        "footprint of this process)."
    )
    summary["memory"] = memory
    return summary


def _mb(value) -> float | None:
    return None if value is None else value / (1024 * 1024)


# --------------------------------------------------------------------------
# Comparing two summaries (pure; tested)
# --------------------------------------------------------------------------

def _metric_rows(mode: str) -> list[tuple[str, str, float, str]]:
    """(label, dotted path into the summary, display scale, unit)."""
    rows = [
        ("WER", "wer", 100.0, "%"),
        ("words (normalized)", "hyp_words", 1.0, ""),
        ("whole-file RTF" if mode == "offline" else "replay RTF", "rtf", 1.0, ""),
        ("decodeMs", "decode_ms", 1.0, " ms"),
    ]
    if mode.startswith("live"):
        rows += [
            ("dropped hops", "live.dropped_hops", 1.0, ""),
            ("forced commits", "live.forced_commits", 1.0, ""),
            ("unagreed tail words", "live.unagreed_tail_words", 1.0, ""),
            ("mean per-decode RTF", "live.mean_decode_rtf", 1.0, ""),
            ("infer ms per hop", "live.infer_ms_per_hop", 1.0, " ms"),
            ("commit latency median", "live.commit_latency_median_ms", 1.0, " ms"),
        ]
    return rows


def _dig(summary: dict, path: str):
    node = summary
    for part in path.split("."):
        if not isinstance(node, dict) or node.get(part) is None:
            return None
        node = node[part]
    return node


def compare_summaries(base: dict, cand: dict, *, allow_non_interleaved: bool = False,
                      seed: int = bs.DEFAULT_SEED) -> dict:
    """Everything `compare` prints, as data. Raises ValueError for arms that
    are not comparable (different audio, reference or mode)."""
    for key in ("mode",):
        if base.get(key) != cand.get(key):
            raise ValueError(f"arms differ in {key}: {base.get(key)!r} vs {cand.get(key)!r}")
    for key in ("audio", "reference"):
        a = (base.get(key) or {}).get("sha256")
        b = (cand.get(key) or {}).get("sha256")
        if a != b:
            raise ValueError(f"arms differ in {key} (sha256 {str(a)[:12]} vs {str(b)[:12]}); "
                             f"comparing them would compare the inputs, not the builds")
    mode = base["mode"]

    base_inter, cand_inter = base.get("interleave"), cand.get("interleave")
    interleaved = bool(base_inter and cand_inter and base_inter.get("id")
                       and base_inter.get("id") == cand_inter.get("id")
                       and {base_inter.get("arm"), cand_inter.get("arm")} == {"A", "B"})

    wer_a = [p["wer"] for p in base["per_run"]]
    wer_b = [p["wer"] for p in cand["per_run"]]
    n_a, n_b = len(wer_a), len(wer_b)

    result: dict = {
        "mode": mode,
        "baseline": {"label": base.get("label"), "n": n_a},
        "candidate": {"label": cand.get("label"), "n": n_b},
        "interleaved": interleaved,
        "interleave_id": (base_inter or {}).get("id"),
        "collapse_rule": bs.COLLAPSE_RULE,
        "min_runs_for_verdict": bs.MIN_RUNS_FOR_VERDICT,
        "rows": [],
    }

    for label, path, scale, unit in _metric_rows(mode):
        a_values, b_values = _series_for(base, path), _series_for(cand, path)
        row = {"metric": label, "path": path, "scale": scale, "unit": unit,
               "baseline": bs.describe(a_values), "candidate": bs.describe(b_values),
               "diff": None, "p": None, "p_method": None}
        if a_values and b_values:
            row["diff"] = bs.median_difference(a_values, b_values)
            row["p"], row["p_method"] = bs.permutation_p_value(a_values, b_values, seed=seed)
        result["rows"].append(row)

    wer_row = result["rows"][0]
    wer_ci = bs.bootstrap_ci(wer_a, wer_b, seed=seed) if wer_a and wer_b else None
    result["wer"] = {"diff": wer_row["diff"], "p": wer_row["p"], "p_method": wer_row["p_method"],
                     "ci95": wer_ci, "ci_method": f"percentile bootstrap, B={bs.BOOTSTRAP_RESAMPLES}, "
                                                  f"seed {seed}"}

    col_a = sum(1 for p in base["per_run"] if p["collapsed"])
    col_b = sum(1 for p in cand["per_run"] if p["collapsed"])
    fisher_p = bs.fisher_exact(col_a, n_a - col_a, col_b, n_b - col_b) if n_a and n_b else None
    result["collapsed"] = {"baseline": col_a, "candidate": col_b, "fisher_p": fisher_p}

    # The candidate judged against the BASELINE's level. Judged only against
    # itself, an arm that collapses every run has no collapsed runs.
    if n_a and n_b and base["collapse"]["wer_threshold"] is not None:
        ref_words = base["collapse"]["ref_words"]
        shared_flags, shared_threshold = bs.classify_collapsed(
            wer_b, [p["hyp_words"] for p in cand["per_run"]], ref_words,
            wer_threshold=base["collapse"]["wer_threshold"])
        shared = sum(shared_flags)
        result["collapsed_vs_baseline_threshold"] = {
            "threshold": shared_threshold, "candidate": shared,
            "fisher_p": bs.fisher_exact(col_a, n_a - col_a, shared, n_b - shared)}

    result["verdict"] = bs.verdict(
        n_a=n_a, n_b=n_b, wer_diff=wer_row["diff"], wer_p=wer_row["p"], wer_ci=wer_ci,
        collapsed_a=col_a, collapsed_b=col_b, fisher_p=fisher_p,
        interleaved=interleaved, allow_non_interleaved=allow_non_interleaved)
    return result


def _series_for(summary: dict, path: str) -> list[float]:
    """Per-run values for a metric path, in run order."""
    per_run = summary.get("per_run") or []
    direct = {"wer": "wer", "hyp_words": "hyp_words", "rtf": "rtf", "decode_ms": "decode_ms"}
    if path in direct:
        return [float(p[direct[path]]) for p in per_run if p.get(direct[path]) is not None]
    if path.startswith("live."):
        return [float(v) for v in (summary.get("live_series", {}).get(path.split(".", 1)[1]) or [])]
    return []


def _fmt(value, scale: float, unit: str) -> str:
    if value is None:
        return "—"
    shown = value * scale
    if unit == "%":
        return f"{shown:.1f}%"
    if unit == " ms":
        return f"{shown:.0f} ms"
    if abs(shown) >= 100 or shown == int(shown):
        return f"{shown:.0f}"
    return f"{shown:.3f}"


def _p(p) -> str:
    return "—" if p is None else ("<0.001" if p < 0.001 else f"{p:.3f}")


def format_comparison(result: dict) -> str:
    lines = []
    base, cand = result["baseline"], result["candidate"]
    lines.append(f"Baseline : {base['label']}  (n = {base['n']})")
    lines.append(f"Candidate: {cand['label']}  (n = {cand['n']})")
    lines.append(f"Mode: {result['mode']}.  Interleaved A/B: "
                 + (f"yes (session {result['interleave_id']})" if result["interleaved"]
                    else "NO (the arms were not run in one interleaved session)"))
    lines.append(f"Collapse rule: {result['collapse_rule']}.")
    lines.append("")
    header = (f"| {'metric':<24} | {'baseline median [min..max] (IQR)':<38} "
              f"| {'candidate median [min..max] (IQR)':<38} | {'cand − base':>12} | {'perm p':>7} |")
    lines.append(header)
    lines.append("|" + "|".join("-" * (len(c)) for c in header.split("|")[1:-1]) + "|")

    def cell(d, scale, unit):
        if not d:
            return "—"
        return (f"{_fmt(d['median'], scale, unit)} [{_fmt(d['min'], scale, unit)}.."
                f"{_fmt(d['max'], scale, unit)}] ({_fmt(d['iqr'], scale, unit)})")

    for row in result["rows"]:
        if row["diff"] is None:
            diff = "—"
        elif row["unit"] == "%":
            diff = f"{row['diff'] * row['scale']:+.1f} pt"
        elif row["unit"] == " ms":
            diff = f"{row['diff']:+.0f} ms"
        else:
            diff = f"{row['diff']:+.3g}"
        lines.append(f"| {row['metric']:<24} | {cell(row['baseline'], row['scale'], row['unit']):<38} "
                     f"| {cell(row['candidate'], row['scale'], row['unit']):<38} "
                     f"| {diff:>12} | {_p(row['p']):>7} |")
    c = result["collapsed"]
    lines.append(f"| {'collapsed runs':<24} | {c['baseline']}/{base['n']:<36} "
                 f"| {c['candidate']}/{cand['n']:<36} | {'':>12} | {_p(c['fisher_p']):>7} |")
    lines.append("")
    lines.append("perm p: two-sided permutation test on the difference of medians; the WER row is the "
                 "primary test, every other row is secondary and not corrected for multiple comparisons. "
                 "The collapsed-runs row is Fisher's exact test (two-sided).")
    wer = result["wer"]
    if wer["diff"] is not None:
        lines.append(f"WER median difference (candidate − baseline): {wer['diff'] * 100:+.1f} points; "
                     f"permutation p = {_p(wer['p'])} ({wer['p_method']}); "
                     f"95% CI {wer['ci95'][0] * 100:+.1f} to {wer['ci95'][1] * 100:+.1f} "
                     f"({wer['ci_method']}).")
    shared = result.get("collapsed_vs_baseline_threshold")
    if shared:
        lines.append(f"Check against the baseline's own level: {shared['candidate']}/{cand['n']} candidate "
                     f"runs have WER above {shared['threshold'] * 100:.1f}% (2x the baseline's best-half "
                     f"median); Fisher p = {_p(shared['fisher_p'])}. This catches a candidate that is "
                     f"uniformly bad, which its own best half would not.")
    lines.append("")
    lines.append(result["verdict"])
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Running binaries (not unit-tested: needs a model)
# --------------------------------------------------------------------------

def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def file_identity(path: Path) -> dict:
    stat = path.stat()
    return {"path": str(path), "sha256": sha256_of(path), "bytes": stat.st_size,
            "mtime": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat()}


def _capture(cmd: list[str]) -> str | None:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def capture_environment() -> dict:
    commit = _capture(["git", "-C", str(REPO), "rev-parse", "HEAD"])
    dirty = _capture(["git", "-C", str(REPO), "status", "--porcelain", "--", "eval"])
    swift = _capture(["swift", "--version"])
    return {
        "date_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "hardware_model": _capture(["sysctl", "-n", "hw.model"]),
        "cpu": _capture(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "memory_gb": (int(_capture(["sysctl", "-n", "hw.memsize"]) or 0) // 2**30) or None,
        "macos": _capture(["sw_vers", "-productVersion"]),
        "swift": swift.splitlines()[0] if swift else None,
        "python": platform.python_version(),
        "harness_commit": commit,
        "harness_eval_dir_dirty": bool(dirty),
    }


def build_command(binary: Path, audio: Path, ref: Path, json_path: Path, *, mode: str,
                  extra: list[str], use_lock: bool, use_time: bool) -> list[str]:
    cmd: list[str] = []
    if use_lock:
        cmd.append(str(LOCK_SCRIPT))
    if use_time:
        cmd += [str(TIME_BINARY), "-l"]
    cmd += [str(binary), "--audio", str(audio), "--reference", str(ref), "--no-diarize",
            "--json", str(json_path)]
    if mode in ("live", "live-realtime"):
        cmd.append("--live")
    if mode == "live-realtime":
        cmd.append("--realtime")
    return cmd + extra


def run_once(*, binary: Path, audio: Path, ref: Path, reference_text: str, out_dir: Path,
             index: int, mode: str, extra: list[str], use_lock: bool, timeout: float,
             arm: str | None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"run-{index:02d}"
    json_path = out_dir / f"{stem}.report.json"
    stderr_path = out_dir / f"{stem}.stderr.txt"
    use_time = TIME_BINARY.exists()
    cmd = build_command(binary, audio, ref, json_path, mode=mode, extra=extra,
                        use_lock=use_lock, use_time=use_time)
    record: dict = {"schema": SCHEMA, "index": index, "arm": arm, "mode": mode,
                    "cmd": cmd, "lock": use_lock, "started_utc":
                        datetime.now(timezone.utc).isoformat(timespec="seconds")}
    # The lock serializes measured runs only. Builds and tests by other people
    # do not take it, and they move RTF, so record how busy the machine was.
    record["loadavg_1m_at_launch"] = round(os.getloadavg()[0], 2)
    began = time.monotonic()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                            start_new_session=True)
    try:
        _, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            _, stderr = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            _, stderr = proc.communicate()
        record.update(ok=False, error=f"timed out after {timeout:.0f} s (lock wait included)")
    else:
        record["returncode"] = proc.returncode
    # Includes any wait for the bench lock, so it is NOT a measurement.
    record["wall_s_including_lock_wait"] = round(time.monotonic() - began, 2)
    stderr_path.write_text(stderr)
    record["stderr_file"] = stderr_path.name
    record["stderr_info"] = parse_stderr(stderr)
    # The tail is for diagnosing a failure, so leave out the /usr/bin/time table
    # that follows the program's own output.
    own_output = re.split(r"^\s+[\d.]+ real\s", stderr, maxsplit=1, flags=re.MULTILINE)[0]
    record["stderr_tail"] = "\n".join(own_output.strip().splitlines()[-6:])

    if "error" not in record:
        if record["returncode"] != 0:
            record.update(ok=False, error=f"exit code {record['returncode']}")
        elif not json_path.exists():
            record.update(ok=False, error="no JSON report was written")
        else:
            try:
                report = json.loads(json_path.read_text())
            except json.JSONDecodeError as error:
                record.update(ok=False, error=f"unreadable JSON report: {error}")
            else:
                record.update(ok=True, report=report,
                              score=score_run(reference_text, report),
                              live=live_metrics(report), memory=memory_stages(report))
    record.setdefault("ok", False)
    record["report_file"] = json_path.name if json_path.exists() else None
    (out_dir / f"{stem}.json").write_text(json.dumps(record, indent=2, sort_keys=True))
    return record


def load_records(directory: Path) -> list[dict]:
    records = [json.loads(p.read_text()) for p in sorted(directory.glob("run-[0-9][0-9]*.json"))
               if not p.name.endswith(".report.json")]
    return sorted(records, key=lambda r: r["index"])


def write_summary(directory: Path, records: list[dict], meta: dict) -> dict:
    summary = summarize_records(records, meta=meta)
    (directory / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def format_summary(summary: dict) -> str:
    def cell(d, scale=1.0, unit=""):
        return "—" if not d else (f"{_fmt(d['median'], scale, unit)} "
                                  f"[{_fmt(d['min'], scale, unit)}..{_fmt(d['max'], scale, unit)}] "
                                  f"IQR {_fmt(d['iqr'], scale, unit)}")
    c = summary["collapse"]
    lines = [f"{summary.get('label')}  mode={summary['mode']}  runs ok {summary['runs_ok']}/"
             f"{summary['runs_attempted']}" + (f"  FAILED {summary['runs_failed']}"
                                              if summary["runs_failed"] else ""),
             f"  WER (score.py)       median [min..max]: {cell(summary['wer'], 100, '%')}",
             f"  words (normalized)   {cell(summary['hyp_words'])}   reference {c['ref_words']}",
             f"  {'whole-file RTF' if summary['mode'] == 'offline' else 'replay RTF':<20} {cell(summary['rtf'])}",
             f"  decodeMs             {cell(summary['decode_ms'], 1.0, ' ms')}",
             f"  collapsed runs       {c['collapsed_runs']}/{summary['runs_ok']} "
             f"(threshold WER > {c['wer_threshold'] * 100:.1f}% or words < {c['word_floor']:.0f}) "
             f"indices {c['collapsed_indices']}" if summary["runs_ok"] else "  no successful runs",
             f"  rule: {c['rule']}",
             f"  runs with invented-filler phrases: {c['runs_with_filler_markers']}; "
             f"runs with a window that needed the retry ladder: {c['runs_with_retried_window']}; "
             f"windows never decoded: {c['windows_never_decoded_total']}"]
    if "live" in summary:
        live = summary["live"]
        for key, scale, unit in (("dropped_hops", 1, ""), ("forced_commits", 1, ""),
                                 ("unagreed_tail_words", 1, ""), ("mean_decode_rtf", 1, ""),
                                 ("infer_ms_per_hop", 1, " ms"),
                                 ("commit_latency_median_ms", 1, " ms")):
            lines.append(f"  live {key:<22} {cell(live.get(key), scale, unit)}")
    mem = summary["memory"]
    lines.append(f"  memory (process footprint, NOT model residency): CLI footprint at exit "
                 f"{cell(mem['cli_footprint_at_exit_mb'], 1, ' MB')}; /usr/bin/time peak footprint "
                 f"{cell(mem['time_peak_footprint_mb'], 1, ' MB')}")
    if mem.get("cli_neural_peak_mb"):
        lines.append(f"  neural-engine memory owned by the process (NOT in the footprint), peak: "
                     f"{cell(mem['cli_neural_peak_mb'], 1, ' MB')}")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def command_run(args: argparse.Namespace) -> int:
    audio, ref = Path(args.audio).resolve(), Path(args.ref).resolve()
    for path, what in ((audio, "--audio"), (ref, "--ref")):
        if not path.is_file():
            print(f"error: {what} {path} does not exist", file=sys.stderr)
            return 2
    reference_text = ref.read_text()
    mode = args.mode
    if mode == "live" and args.realtime:
        mode = "live-realtime"

    if args.interleave:
        binaries = {"A": Path(args.interleave[0]).resolve(), "B": Path(args.interleave[1]).resolve()}
        labels = {"A": args.labels[0] if args.labels else "baseline",
                  "B": args.labels[1] if args.labels else "candidate"}
    else:
        if not args.bin:
            print("error: give --bin, or --interleave BASE CAND", file=sys.stderr)
            return 2
        binaries = {"A": Path(args.bin).resolve()}
        labels = {"A": args.label}
    for binary in binaries.values():
        if not binary.is_file() or not os.access(binary, os.X_OK):
            print(f"error: {binary} is not an executable file", file=sys.stderr)
            return 2
    if labels["A"] is None:
        labels["A"] = f"transcribe@{sha256_of(binaries['A'])[:8]}"

    out_dir = Path(args.out_dir).resolve()
    arm_dirs = {arm: (out_dir / arm if args.interleave else out_dir) for arm in binaries}
    for directory in arm_dirs.values():
        if directory.exists() and any(directory.glob("run-*.json")):
            print(f"error: {directory} already holds runs; refusing to mix or overwrite. "
                  f"Use a new --out-dir.", file=sys.stderr)
            return 2
        directory.mkdir(parents=True, exist_ok=True)

    extra = list(args.extra or [])
    if args.models:
        extra += ["--models", args.models]
    use_lock = LOCK_SCRIPT.exists() and not args.no_lock
    if not use_lock:
        print("note: running WITHOUT /tmp/notero-team/bench-lock.sh "
              + ("(--no-lock)" if args.no_lock else "(file not found)")
              + "; timings are only valid if nothing else uses this Mac", file=sys.stderr)

    schedule = (bs.interleave_schedule(args.runs, args.order) if args.interleave
                else ["A"] * args.runs)
    session = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    counters = {arm: 0 for arm in binaries}
    records: dict[str, list[dict]] = {arm: [] for arm in binaries}
    timeline = []
    for step, arm in enumerate(schedule, 1):
        counters[arm] += 1
        index = counters[arm]
        print(f"[{step}/{len(schedule)}] {arm} ({labels[arm]}) run {index}/{args.runs} ...",
              file=sys.stderr, flush=True)
        record = run_once(binary=binaries[arm], audio=audio, ref=ref, reference_text=reference_text,
                          out_dir=arm_dirs[arm], index=index, mode=mode, extra=extra,
                          use_lock=use_lock, timeout=args.timeout, arm=arm)
        records[arm].append(record)
        timeline.append({"step": step, "arm": arm, "index": index, "ok": record["ok"],
                         "started_utc": record["started_utc"]})
        if record["ok"]:
            s = record["score"]
            print(f"    WER {s['wer'] * 100:.1f}%  words {s['hyp_words']}  "
                  f"rtf {record['report'].get('rtf', 0):.3f}"
                  + (f"  fillers {s['filler_markers']}" if s["filler_markers"] else ""),
                  file=sys.stderr, flush=True)
        else:
            print(f"    FAILED: {record.get('error')}", file=sys.stderr, flush=True)

    env = capture_environment()
    audio_id, ref_id = file_identity(audio), file_identity(ref)
    ref_id["words"] = len(normalize(reference_text))
    summaries = {}
    for arm, binary in binaries.items():
        meta = {
            "label": labels[arm], "mode": mode, "runs_requested": args.runs,
            "binary": file_identity(binary), "audio": audio_id, "reference": ref_id,
            "cli_args_extra": extra, "lock_used": use_lock, "environment": env,
            "model": next((r["report"].get("model") for r in records[arm] if r["ok"]), None),
            "interleave": ({"id": session, "arm": arm, "scheme": args.order,
                            "schedule": "".join(schedule)} if args.interleave else None),
        }
        summaries[arm] = write_summary(arm_dirs[arm], records[arm], meta)
        print("\n" + format_summary(summaries[arm]))
    if args.interleave:
        (out_dir / "interleave.json").write_text(json.dumps(
            {"id": session, "scheme": args.order, "timeline": timeline, "labels": labels}, indent=2))
        print("\n" + format_comparison(compare_summaries(summaries["A"], summaries["B"])))
    return 0 if all(s["runs_ok"] for s in summaries.values()) else 1


def command_summarize(args: argparse.Namespace) -> int:
    directory = Path(args.directory).resolve()
    records = load_records(directory)
    if not records:
        print(f"error: no run-NN.json files in {directory}", file=sys.stderr)
        return 2
    previous = directory / "summary.json"
    meta = {k: v for k, v in json.loads(previous.read_text()).items()
            if k in ("label", "mode", "runs_requested", "binary", "audio", "reference",
                     "cli_args_extra", "lock_used", "environment", "model", "interleave")} \
        if previous.exists() else {"label": directory.name, "mode": records[0]["mode"]}
    summary = write_summary(directory, records, meta)
    print(format_summary(summary))
    return 0


def command_compare(args: argparse.Namespace) -> int:
    base = json.loads(Path(args.baseline).read_text())
    cand = json.loads(Path(args.candidate).read_text())
    try:
        result = compare_summaries(base, cand, allow_non_interleaved=args.allow_non_interleaved)
    except ValueError as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        return 2
    print(format_comparison(result))
    if args.json:
        Path(args.json).write_text(json.dumps(result, indent=2, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="run a transcribe binary N times (or two, interleaved)")
    run.add_argument("--bin", help="the transcribe binary")
    run.add_argument("--interleave", nargs=2, metavar=("BASE_BIN", "CAND_BIN"),
                     help="alternate two binaries A B A B ...; A is the baseline")
    run.add_argument("--labels", nargs=2, metavar=("BASE", "CAND"), help="names for --interleave")
    run.add_argument("--label", help="name of the single arm")
    run.add_argument("--order", choices=("abab", "abba"), default="abab",
                     help="abab: strict alternation; abba: alternate who goes first (cancels drift)")
    run.add_argument("--audio", required=True)
    run.add_argument("--ref", required=True, help="reference transcript")
    run.add_argument("--runs", type=int, default=8, help="runs per arm (default 8; the verdict needs >= 8)")
    run.add_argument("--mode", choices=("offline", "live"), default="offline")
    run.add_argument("--realtime", action="store_true", help="with --mode live: pace at wall-clock speed")
    run.add_argument("--out-dir", required=True)
    run.add_argument("--models", help="passed to transcribe --models")
    run.add_argument("--timeout", type=float, default=1800.0, help="seconds per run, lock wait included")
    run.add_argument("--no-lock", action="store_true", help="do not use bench-lock.sh")
    run.add_argument("--extra", nargs=argparse.REMAINDER, default=[],
                     help="everything after is passed to transcribe (e.g. --extra --hop 1000)")
    run.set_defaults(func=command_run)

    summarize = sub.add_parser("summarize", help="re-summarize a directory of runs")
    summarize.add_argument("directory")
    summarize.set_defaults(func=command_summarize)

    compare = sub.add_parser("compare", help="compare a baseline and a candidate summary")
    compare.add_argument("baseline")
    compare.add_argument("candidate")
    compare.add_argument("--json", help="also write the comparison as JSON")
    compare.add_argument("--allow-non-interleaved", action="store_true",
                         help="print a verdict even if the arms were not interleaved (marked as such)")
    compare.set_defaults(func=command_compare)

    args = parser.parse_args(argv)
    if getattr(args, "runs", 1) < 1:
        parser.error("--runs must be at least 1")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
