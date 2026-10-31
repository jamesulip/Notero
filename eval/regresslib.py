"""Pure logic of the regression harness: no subprocess, no clock, no machine.

`bench_runs.py` runs one binary and summarizes it; `regress.py` runs a whole
SUITE of two binaries, interleaved, and reports. Both decide with the same rule
(`benchstats.decide`) and call the functions here, so there is one collapse rule
and one decision rule and a test can exercise them without a model:

  * `arm_from_rows` / `arm_from_summary`  per-run numbers -> an "arm"
  * `compare_series`                      two arms -> tests, collapse, load
  * `evaluate`                            every series -> one decision
  * `format_report`                       the markdown report
  * `analyze_determinism`                 N runs of one binary: identical? where not?
  * `drift_warnings`                      a committed baseline against this machine

Everything a run produces is SYNTHETIC unless a series says otherwise: the
fixtures are text-to-speech. A verdict supports a statement about two builds on
the same audio; it says nothing about real meetings or real Taglish.
"""

from __future__ import annotations

import hashlib
import json
import math
from typing import Sequence

import benchstats as bs

SCHEMA = 2

#: The live counters a live series tests besides WER, words and RTF.
LIVE_KEYS = ("dropped_hops", "forced_commits", "unagreed_tail_words", "mean_decode_rtf",
             "infer_ms_per_hop", "commit_latency_median_ms")


# --------------------------------------------------------------------------
# Arms: the numbers of one binary in one series
# --------------------------------------------------------------------------

def row_from_record(record: dict) -> dict:
    """The flat per-run numbers of a successful `bench_runs.run_once` record.
    A transcript is kept only as a hash: the determinism check needs equality,
    and a report should not carry text."""
    score, report = record["score"], record["report"]
    row = {
        "index": record["index"],
        "wer": score["wer"],
        "hyp_words": score["hyp_words"],
        "rtf": report.get("rtf"),
        "decode_ms": report.get("decodeMs"),
        "filler": bool(score["filler_markers"]),
        "load": record.get("loadavg_1m_at_launch"),
        "retried_windows": (record.get("stderr_info") or {}).get("retried_windows"),
        "dropped_windows": (record.get("stderr_info") or {}).get("dropped_windows"),
        "transcript_sha256": hashlib.sha256(
            report.get("transcript", "").encode("utf-8")).hexdigest(),
        "started_utc": record.get("started_utc"),
    }
    for key in LIVE_KEYS:
        value = (record.get("live") or {}).get(key)
        if value is not None:
            row[f"live.{key}"] = value
    return row


def arm_from_rows(rows: Sequence[dict], *, label: str, ref_words: int,
                  extra: dict | None = None) -> dict:
    """An arm: per-metric value lists plus what the collapse rule and the load
    assessment need. Rows with a missing metric are skipped for that metric only."""
    metrics: dict[str, list[float]] = {}
    for key in ("wer", "hyp_words", "rtf", "decode_ms",
                *[f"live.{k}" for k in LIVE_KEYS]):
        values = [float(r[key]) for r in rows if r.get(key) is not None]
        if values:
            metrics[key] = values
    arm = {"label": label, "n": len(rows), "ref_words": ref_words, "metrics": metrics,
           "wer": [float(r["wer"]) for r in rows],
           "hyp_words": [int(r["hyp_words"]) for r in rows],
           "filler": [bool(r.get("filler")) for r in rows],
           "load": [r.get("load") for r in rows],
           "index": [r.get("index") for r in rows]}
    arm.update(extra or {})
    return arm


def arm_from_summary(summary: dict) -> dict:
    """An arm from a `bench_runs.py` summary.json (its per_run and live_series)."""
    per_run = summary.get("per_run") or []
    rows = [{"index": p["index"], "wer": p["wer"], "hyp_words": p["hyp_words"],
             "rtf": p.get("rtf"), "decode_ms": p.get("decode_ms"),
             "filler": bool(p.get("filler_markers")), "load": p.get("loadavg_1m")}
            for p in per_run]
    arm = arm_from_rows(rows, label=summary.get("label") or "?",
                        ref_words=(summary.get("collapse") or {}).get("ref_words") or 0)
    for key, values in (summary.get("live_series") or {}).items():
        if values and key in LIVE_KEYS:
            arm["metrics"][f"live.{key}"] = [float(v) for v in values]
    return arm


# --------------------------------------------------------------------------
# One series: two arms of the same clip and mode
# --------------------------------------------------------------------------

def collapse_info(arm_a: dict, arm_b: dict, *, level: float | None = None) -> dict:
    """Judge both arms against ONE reference level, pooled over both (or `level`
    if the caller has an external one, e.g. a committed baseline's)."""
    if not arm_a["wer"] or not arm_b["wer"]:
        return {"level": None, "threshold": None, "A": None, "B": None}
    used = bs.reference_level(arm_a["wer"], arm_b["wer"]) if level is None else level
    out = {"level": used, "level_source": "pooled best half" if level is None else "given",
           "rule": bs.COLLAPSE_RULE}
    for name, arm in (("A", arm_a), ("B", arm_b)):
        reasons, threshold = bs.collapse_reasons(
            arm["wer"], arm["hyp_words"], arm["ref_words"], level=used, filler=arm["filler"])
        out["threshold"] = threshold
        out[name] = {"count": sum(1 for r in reasons if r),
                     "indices": [arm["index"][i] for i, r in enumerate(reasons) if r],
                     "reasons": {str(arm["index"][i]): r for i, r in enumerate(reasons) if r}}
    out["word_floor"] = bs.COLLAPSE_MIN_WORD_FRACTION * arm_a["ref_words"]
    return out


def collapse_test(series: str, arm_a: dict, arm_b: dict, collapse: dict) -> dict:
    """The collapsed-runs test (Fisher's exact on the 2x2 table) as a `decide` input."""
    spec = bs.METRICS["collapsed"]
    n_a, n_b = arm_a["n"], arm_b["n"]
    test = {"series": series, "key": "collapsed", "label": spec["label"], "kind": spec["kind"],
            "better": spec["better"], "n_a": n_a, "n_b": n_b,
            "floor_abs": spec["floor_abs"], "floor_rel": spec["floor_rel"],
            "diff": None, "rel_diff": None, "floor_met": False, "p": None, "p_method": None,
            "a": None, "b": None}
    if collapse.get("A") is None or not n_a or not n_b:
        return test
    count_a, count_b = collapse["A"]["count"], collapse["B"]["count"]
    test["a"] = {"n": n_a, "median": float(count_a), "min": float(count_a), "max": float(count_a),
                 "iqr": 0.0, "count": count_a}
    test["b"] = {"n": n_b, "median": float(count_b), "min": float(count_b), "max": float(count_b),
                 "iqr": 0.0, "count": count_b}
    test["diff"] = float(count_b - count_a)
    test["floor_met"] = abs(test["diff"]) >= spec["floor_abs"]
    test["p"] = bs.fisher_exact(count_a, n_a - count_a, count_b, n_b - count_b)
    test["p_method"] = "fisher"
    return test


def compare_series(series_id: str, mode: str, arm_a: dict, arm_b: dict, *,
                   seed: int = bs.DEFAULT_SEED, level: float | None = None) -> dict:
    """Everything one clip-and-mode comparison reports, as data: the per-metric
    tests (not yet corrected: `evaluate` does that across ALL series), the
    collapse counts under the one rule, and the load record. Raises ValueError for
    arms that are not comparable."""
    if arm_a["ref_words"] != arm_b["ref_words"]:
        raise ValueError(f"series {series_id}: the arms were scored against references of "
                         f"different length ({arm_a['ref_words']} vs {arm_b['ref_words']} words)")
    keys = ["wer", "hyp_words", "rtf", "decode_ms"]
    if mode.startswith("live"):
        keys += [f"live.{k}" for k in LIVE_KEYS]
    tests = []
    skipped = []
    for key in keys:
        a, b = arm_a["metrics"].get(key, []), arm_b["metrics"].get(key, [])
        if a and b:
            tests.append(bs.metric_test(key, a, b, series=series_id, seed=seed))
        elif a or b:
            # One build reports it and the other does not (an older binary lacks the field):
            # untestable, and said so, never silently dropped from the table.
            skipped.append({"key": key, "label": bs.METRICS[key]["label"],
                            "missing_in": "candidate" if a else "base"})
    collapse = collapse_info(arm_a, arm_b, level=level)
    tests.append(collapse_test(series_id, arm_a, arm_b, collapse))
    return {"id": series_id, "mode": mode, "ref_words": arm_a["ref_words"],
            "arms": {"A": {"label": arm_a["label"], "n": arm_a["n"]},
                     "B": {"label": arm_b["label"], "n": arm_b["n"]}},
            "tests": tests, "collapse": collapse, "skipped_metrics": skipped,
            "load": bs.assess_load(arm_a["load"], arm_b["load"]),
            "per_arm_values": {"A": {k: arm_a["metrics"].get(k, []) for k in keys},
                               "B": {k: arm_b["metrics"].get(k, []) for k in keys}}}


def evaluate(series: Sequence[dict], *, interleaved: bool = True,
             confirm_with: dict | None = None) -> dict:
    """The decision over ALL series together (Holm over every tested metric)."""
    tests = [t for s in series for t in s["tests"]]
    load = {s["id"]: s["load"] for s in series}
    decision = bs.decide(tests, load=load, interleaved=interleaved)
    by_series: dict[str, list[dict]] = {}
    for t in decision["tests"]:
        by_series.setdefault(t["series"], []).append(t)
    for s in series:
        s["tests"] = by_series.get(s["id"], [])
    result = {"decision": {k: v for k, v in decision.items() if k != "tests"}}
    if confirm_with is not None:
        result["confirmation"] = bs.confirm(confirm_with.get("decision", {}), decision["tests"], load=load)
    return result


# --------------------------------------------------------------------------
# Printing
# --------------------------------------------------------------------------

def fmt_value(value, scale: float, unit: str) -> str:
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


def fmt_p(p) -> str:
    return "—" if p is None else ("<0.001" if p < 0.001 else f"{p:.3f}")


def _cell(d: dict | None, scale: float, unit: str) -> str:
    if not d:
        return "—"
    if "count" in d:
        return f"{d['count']}/{d['n']}"
    return (f"{fmt_value(d['median'], scale, unit)} "
            f"[{fmt_value(d['min'], scale, unit)}..{fmt_value(d['max'], scale, unit)}]")


def _delta(t: dict) -> str:
    if t["diff"] is None:
        return "—"
    spec = bs.METRICS[t["key"]]
    if spec["unit"] == "%":
        text = f"{t['diff'] * spec['scale']:+.1f} pt"
    elif t["key"] == "collapsed":
        text = f"{t['diff']:+.0f} runs"
    elif spec["unit"] == " ms":
        text = f"{t['diff']:+.0f} ms"
    else:
        text = f"{t['diff']:+.3g}"
    if t["rel_diff"] is not None and spec["unit"] != "%" and t["key"] != "collapsed":
        text += f" ({t['rel_diff'] * 100:+.0f}%)"
    return text


STATUS_TEXT = {
    "regression": "**REGRESSION (suspected)**", "improvement": "**IMPROVEMENT (suspected)**",
    "changed": "**CHANGED (suspected)**", "indicative": "indicative only (load)",
    "below-floor": "significant, below floor", "not-significant": "not significant",
    "no-verdict": "no verdict (n)", "untested": "not tested",
}


def series_table(series: dict) -> list[str]:
    lines = ["| metric | base median [min..max] | cand median [min..max] | cand − base | p (rank sum) | p (Holm) | status |",
             "| --- | --- | --- | ---: | ---: | ---: | --- |"]
    for t in series["tests"]:
        spec = bs.METRICS[t["key"]]
        status = STATUS_TEXT.get(t.get("status", ""), t.get("status", ""))
        if t.get("status") == "indicative":
            status += f" ({t.get('would_be')}; {t.get('load_reason')})"
        lines.append(f"| {t['label']} | {_cell(t['a'], spec['scale'], spec['unit'])} "
                     f"| {_cell(t['b'], spec['scale'], spec['unit'])} | {_delta(t)} "
                     f"| {fmt_p(t['p'])} | {fmt_p(t.get('p_holm'))} | {status} |")
    return lines


def load_lines(series: dict) -> list[str]:
    load = series["load"]
    if not load["recorded"]:
        return ["- load average at launch: **not recorded for every run**; timing is not believed."]
    verdict = "quiet and balanced" if load["reliable"] else f"NOT reliable: {load['reason']}"
    return [f"- load average (1 min) at launch, median / max: base {load['median_a']:.2f} / "
            f"{load['max_a']:.2f}, cand {load['median_b']:.2f} / {load['max_b']:.2f} — {verdict}"]


def system_lines(system: dict | None) -> list[str]:
    if not system:
        return []
    lines = []
    for when in ("before", "after"):
        snap = (system or {}).get(when)
        if not snap:
            continue
        mem = snap.get("memory") or {}
        parts = [f"uptime load {snap.get('loadavg')}"]
        if mem.get("free_percentage") is not None:
            parts.append(f"memory free {mem['free_percentage']}%")
        if mem.get("pageouts") is not None:
            parts.append(f"pageouts {mem['pageouts']}")
        if mem.get("compressed_pages") is not None:
            parts.append(f"compressor pages {mem['compressed_pages']}")
        lines.append(f"- {when}: " + ", ".join(parts))
    if system.get("pageouts_delta") is not None:
        lines.append(f"- pageouts during the series: {system['pageouts_delta']}")
    return lines


def format_series(series: dict) -> str:
    c = series["collapse"]
    lines = [f"### {series['id']} ({series['mode']})", "",
             f"Base `{series['arms']['A']['label']}` n = {series['arms']['A']['n']}; "
             f"candidate `{series['arms']['B']['label']}` n = {series['arms']['B']['n']}."]
    if series.get("fixture"):
        f = series["fixture"]
        lines.append(f"Audio `{f.get('id')}` sha256 `{(f.get('sha256') or '?')[:12]}`, "
                     f"reference {series['ref_words']} words"
                     + (" (SYNTHETIC)" if f.get("synthetic") else "") + ".")
    lines += [""] + series_table(series) + [""]
    if c.get("A") is not None:
        lines.append(f"Collapsed runs (level {c['level'] * 100:.1f}% WER, threshold "
                     f"{c['threshold'] * 100:.1f}%, word floor {c['word_floor']:.0f}): "
                     f"base {c['A']['count']} {c['A']['indices']}, "
                     f"cand {c['B']['count']} {c['B']['indices']}.")
        why = {**{f"A#{k}": v for k, v in c["A"]["reasons"].items()},
               **{f"B#{k}": v for k, v in c["B"]["reasons"].items()}}
        if why:
            lines.append("Why: " + "; ".join(f"{k} {'+'.join(v)}" for k, v in why.items()) + ".")
    if series.get("skipped_metrics"):
        lines.append("Not tested, reported by only one build: " + ", ".join(
            f"{m['label']} (missing in the {m['missing_in']})" for m in series["skipped_metrics"]) + ".")
    lines += load_lines(series) + system_lines(series.get("system"))
    return "\n".join(lines)


def format_der(der: dict | None) -> str:
    if not der:
        return ""
    lines = ["### Diarization (DER, synthetic fixtures)", "",
             f"{der['note']}", "",
             "| fixture | base DER per round | cand DER per round | cand − base (median) | deterministic | status |",
             "| --- | --- | --- | ---: | --- | --- |"]
    for row in der["fixtures"]:
        a = ", ".join(f"{x * 100:.1f}" for x in row["base"])
        b = ", ".join(f"{x * 100:.1f}" for x in row["cand"])
        lines.append(f"| {row['id']} | {a} | {b} | "
                     f"{row['diff'] * 100:+.1f} pt | {'yes' if row['deterministic'] else 'NO'} | "
                     f"{row['status']} |")
    return "\n".join(lines)


def format_determinism(report: dict | list | None) -> str:
    if not report:
        return ""
    if isinstance(report, list):
        return "\n\n".join(format_determinism(one) for one in report)
    lines = [f"### Determinism of `{report.get('label', 'binary')}`", "",
             f"{report['n']} runs of one binary on one file: "
             + ("**byte-identical**" if report["identical"] else
                f"**NOT identical: {report['distinct']} distinct transcripts**")
             + f" (groups of {report['group_sizes']})."]
    first = report.get("first_divergence")
    if first:
        window = (f"window {first['window_index']} ({first['window_start_ms']}–"
                  f"{first['window_end_ms']} ms)" if first.get("window_index") is not None
                  else "window unknown (this binary's report lists no windows)")
        lines.append(f"First divergence: run {first['run_a']} vs run {first['run_b']} at word "
                     f"{first['word_index']} (≈ {first['time_ms']} ms), {window}: "
                     f"`{first['a_context']}` vs `{first['b_context']}`.")
    return "\n".join(lines)


def format_report(result: dict) -> str:
    """The whole markdown report from `result` (the same dict written as JSON)."""
    env = result.get("environment", {})
    ident = result.get("identity", {})
    lines = ["# Regression report", "",
             f"- Suite: `{result.get('suite')}`; base `{ident.get('base')}`, candidate "
             f"`{ident.get('cand')}`; interleave `{result.get('interleave', {}).get('scheme')}` "
             f"({result.get('interleave', {}).get('id')}).",
             f"- Machine: {env.get('hardware_model')} / {env.get('cpu')} / {env.get('memory_gb')} GB / "
             f"macOS {env.get('macos')}; model `{result.get('model')}`; date {env.get('date_utc')}.",
             f"- Bench lock: {'used' if result.get('lock_used') else '**NOT USED: timings are valid only if nothing else ran**'}.",
             f"- Collapse rule: {bs.COLLAPSE_RULE}.",
             f"- Decision rule: n ≥ {bs.MIN_RUNS_FOR_VERDICT} per arm interleaved; rank-sum permutation "
             f"test per metric; Holm over all {result['decision']['family_size']} tested metrics "
             f"(α = {bs.ALPHA}); effect-size floors; timing believed only on a quiet, balanced machine "
             f"(median load ≤ {bs.LOAD_QUIET_MEDIAN:g}, arms within {bs.LOAD_BALANCE_MAX:g}); one session "
             f"only SUSPECTS, a reproduced second session CONFIRMS.",
             "", "## Verdict", "", result["decision"]["headline"], ""]
    conf = result.get("confirmation")
    if conf and conf.get("refused"):
        lines += ["### Second-session confirmation", "",
                  f"**REFUSED: {conf['refused']}** Nothing is confirmed.", ""]
    elif conf:
        lines += ["### Second-session confirmation", ""]
        for r in conf["results"]:
            lines.append(f"- {r['series']}:{r['label']}: "
                         + ("**CONFIRMED (reproduced)**" if r["reproduced"]
                            else f"not reproduced ({r.get('why_not')})")
                         + f" (first Δ {r['first_diff']:+.4g}, second Δ "
                         + (f"{r['second_diff']:+.4g}, p_Holm {r['second_p_holm']:.3f}"
                            if r["second_diff"] is not None else "n/a") + ")")
        lines.append("")
    for warning in result.get("warnings", []):
        lines.append(f"> WARNING: {warning}")
    if result.get("warnings"):
        lines.append("")
    lines.append("## Series")
    lines.append("")
    for series in result["series"]:
        lines += [format_series(series), ""]
    for block in (format_der(result.get("der")), format_determinism(result.get("determinism"))):
        if block:
            lines += [block, ""]
    base = result.get("baseline_check")
    if base:
        lines += ["## Committed baseline", "", *base, ""]
    for note in result.get("skipped", []):
        lines.append(f"- skipped: {note}")
    lines += ["", "Everything above was measured on SYNTHETIC audio unless a series says otherwise; "
                  "it supports an A/B statement about two builds, not a claim about real meetings "
                  "or real Taglish. \"Not significant\" is never \"equivalent\"."]
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# Determinism
# --------------------------------------------------------------------------

def _words_of(report: dict) -> list[str]:
    return [w.get("text", "").strip() for w in report.get("words") or []]


def first_difference(report_a: dict, report_b: dict) -> dict | None:
    """Where two reports of the same file first differ: the word index, its time,
    the window it is in (when the report lists windows) and a few words of context."""
    words_a, words_b = _words_of(report_a), _words_of(report_b)
    limit = min(len(words_a), len(words_b))
    index = next((i for i in range(limit) if words_a[i] != words_b[i]), None)
    if index is None:
        if len(words_a) == len(words_b):
            if report_a.get("transcript") == report_b.get("transcript"):
                return None
            index = limit
        else:
            index = limit
    source = report_a if index < len(words_a) else report_b
    entries = source.get("words") or []
    if index < len(entries):
        time_ms = entries[index].get("startMs")
    elif entries:
        time_ms = entries[-1].get("endMs")
    else:
        time_ms = None
    window = None
    for position, span in enumerate(report_a.get("windows") or report_b.get("windows") or []):
        if time_ms is not None and span["startMs"] <= time_ms < span["endMs"]:
            window = {"window_index": position, "window_start_ms": span["startMs"],
                      "window_end_ms": span["endMs"]}
            break
    lo = max(0, index - 3)
    return {"word_index": index, "time_ms": time_ms,
            "a_context": " ".join(words_a[lo:index + 3]), "b_context": " ".join(words_b[lo:index + 3]),
            "window_index": None, "window_start_ms": None, "window_end_ms": None,
            **(window or {})}


def analyze_determinism(reports: Sequence[dict], *, label: str = "binary") -> dict:
    """Are N runs of one binary on one file byte-identical, how many distinct
    transcripts are there, and where is the first divergence from the first run?"""
    if not reports:
        raise ValueError("no runs to compare")
    texts = [r.get("transcript", "") for r in reports]
    groups: dict[str, list[int]] = {}
    for i, text in enumerate(texts, 1):
        groups.setdefault(hashlib.sha256(text.encode("utf-8")).hexdigest(), []).append(i)
    ordered = sorted(groups.values(), key=lambda g: (-len(g), g[0]))
    out = {"label": label, "n": len(reports), "identical": len(groups) == 1,
           "distinct": len(groups), "group_sizes": [len(g) for g in ordered],
           "groups": ordered, "first_divergence": None}
    if len(groups) > 1:
        reference = reports[0]
        for i, text in enumerate(texts[1:], 2):
            if text != texts[0]:
                diff = first_difference(reference, reports[i - 1])
                if diff:
                    out["first_divergence"] = {"run_a": 1, "run_b": i, **diff}
                break
    return out


# --------------------------------------------------------------------------
# Baselines
# --------------------------------------------------------------------------

def _major_minor(version: str | None) -> str | None:
    return None if not version else ".".join(version.split(".")[:2])


def drift_warnings(baseline: dict, environment: dict, *, model: str | None,
                   fixture_hashes: dict[str, str] | None = None) -> list[str]:
    """What differs between the machine a committed baseline was measured on and
    this one. A baseline is evidence about THAT machine, OS and model."""
    warnings = []
    saved = baseline.get("environment") or {}
    for key, label in (("hardware_model", "hardware model"), ("cpu", "CPU"),
                       ("memory_gb", "memory (GB)")):
        if saved.get(key) and environment.get(key) and saved[key] != environment[key]:
            warnings.append(f"baseline drift: {label} is {environment[key]!r} here but "
                            f"{saved[key]!r} in the baseline")
    if (saved.get("macos") and environment.get("macos")
            and _major_minor(saved["macos"]) != _major_minor(environment["macos"])):
        warnings.append(f"baseline drift: macOS {environment['macos']} here, {saved['macos']} in the "
                        f"baseline (a different OS release can change Core ML and Neural Engine behaviour)")
    elif (saved.get("macos") and environment.get("macos") and saved["macos"] != environment["macos"]):
        warnings.append(f"baseline drift (minor): macOS {environment['macos']} here, "
                        f"{saved['macos']} in the baseline")
    if baseline.get("model") and model and baseline["model"] != model:
        warnings.append(f"baseline drift: model id {model!r} here, {baseline['model']!r} in the baseline")
    for fixture_id, sha in (fixture_hashes or {}).items():
        saved_sha = ((baseline.get("fixtures") or {}).get(fixture_id) or {}).get("sha256")
        if saved_sha and sha and saved_sha != sha:
            warnings.append(f"baseline drift: fixture {fixture_id} has sha256 {sha[:12]} here, "
                            f"{saved_sha[:12]} in the baseline")
    return warnings


def baseline_check(baseline: dict, series: Sequence[dict]) -> list[str]:
    """Today's BASE arm beside the committed baseline's numbers for the same
    series. Not a test (the committed runs were not interleaved with today's):
    a way to see whether today's session looks like the one the baseline came from."""
    lines = [f"Baseline `{baseline.get('name')}` — {baseline.get('what', '')}",
             f"Measured {baseline.get('environment', {}).get('date_utc')} at "
             f"`{(baseline.get('base_commit') or '?')[:10]}`; **not interleaved with this session, so "
             f"it is context, never a test** (docs/BENCHMARKS.md)."]
    saved_series = baseline.get("series") or {}
    for s in series:
        saved = saved_series.get(s["id"])
        if not saved:
            continue
        for key in ("wer", "rtf"):
            t = next((t for t in s["tests"] if t["key"] == key), None)
            reference = (saved.get("stats") or {}).get(key)
            if not t or not t["a"] or not reference:
                continue
            spec = bs.METRICS[key]
            today = t["a"]["median"]
            inside = reference["min"] <= today <= reference["max"]
            lines.append(
                f"- {s['id']} {spec['label']}: base arm today median "
                f"{fmt_value(today, spec['scale'], spec['unit'])}; committed baseline median "
                f"{fmt_value(reference['median'], spec['scale'], spec['unit'])} "
                f"[{fmt_value(reference['min'], spec['scale'], spec['unit'])}.."
                f"{fmt_value(reference['max'], spec['scale'], spec['unit'])}] n={reference['n']} — "
                + ("inside the committed range" if inside else
                   "**OUTSIDE the committed range: this session or this machine differs from the baseline's**"))
    return lines


def json_safe(value):
    """NaN and infinity are not JSON; report them as null."""
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    if isinstance(value, dict):
        return {k: json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(v) for v in value]
    return value


def dumps(result: dict, *, sort_keys: bool = False) -> str:
    """JSON text. Key order is kept by default: a plan reloaded by `--reanalyze` must
    list its series in the order the suite ran them, or the report reads differently."""
    return json.dumps(json_safe(result), indent=2, sort_keys=sort_keys)
