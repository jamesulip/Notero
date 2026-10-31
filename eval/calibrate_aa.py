#!/usr/bin/env python3
"""How often does this harness call a difference between IDENTICAL builds real?

An A/A comparison (one binary against itself) has no true difference, so every
flag it raises is a false positive. This measures the false-positive rate of the
shipped decision rule (`benchstats.decide`) and, for contrast, of the rules it
replaces, in two ways that fail differently:

  simulate   Resampling. Takes the raw per-run numbers of the P6 baseline
             sessions (`eval/baselines/p6-*.json`, same binary within each pool),
             draws two arms of n runs at random, runs the whole decision rule on
             them, repeats. Fast, thousands of replicates, and the null is exactly
             "identical builds". What it cannot show: slow drift of the machine
             between runs (the draws are iid).
  stream     Real runs. Takes a long stream of runs of ONE binary taken one after
             another on the real machine (`bench_runs.py run --bin X --runs 320`,
             through the bench lock, other agents building next door), cuts it into
             consecutive blocks of 2n runs, deals them to arms A and B in the
             interleaved ABBA order, and applies the same rule to each block. This
             includes drift and load, and it is the check on the resampling.

    python3 eval/calibrate_aa.py simulate --reps 2000 --n 8 --out eval/baselines/aa-calibration.json
    python3 eval/calibrate_aa.py stream --dir /tmp/.../aa-stream --n 8 --out eval/baselines/aa-calibration.json
    python3 eval/calibrate_aa.py export-stream --dir /tmp/.../aa-stream --out eval/baselines/aa-stream.json

A rate is reported with its Wilson 95% interval and the number of replicates. The
requirement the shipped rule is chosen to meet: the rate at which an A/A session
flags ANY metric (all reported metrics together) is at most 5%.
"""

from __future__ import annotations

import argparse
import json
import math
import multiprocessing
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import benchstats as bs  # noqa: E402
import regresslib as rl  # noqa: E402

DEFAULT_BASELINE = HERE / "baselines" / "p6-f022c6e-synthetic-taglish.json"
FLAGGED = ("regression", "improvement", "changed")

#: Pools of runs of ONE binary. (mode, arms of the baseline file that are the same binary)
POOLS = {
    "offline-pure": ("offline", ["offline-pure"]),
    "offline-instrumented": ("offline", ["offline-instrumented"]),
    "live-pure": ("live", ["live-pure", "recheck-live-pure", "aa-live-path1", "aa-live-path2"]),
    "live-instrumented": ("live", ["live-instrumented", "recheck-live-instrumented"]),
}


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson score interval for a proportion k/n."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def rate(k: int, n: int) -> dict:
    low, high = wilson(k, n)
    return {"flagged": k, "sessions": n, "rate": k / n if n else None,
            "ci95": [low, high]}


# --------------------------------------------------------------------------
# One session
# --------------------------------------------------------------------------

def session_arms(rows_a: list[dict], rows_b: list[dict], mode: str, ref_words: int) -> tuple[dict, dict]:
    return (rl.arm_from_rows(rows_a, label="A", ref_words=ref_words),
            rl.arm_from_rows(rows_b, label="B", ref_words=ref_words))


def evaluate_session(rows_a: list[dict], rows_b: list[dict], mode: str, ref_words: int,
                     *, seed: int, with_old_rule: bool = False) -> dict:
    """Run the full decision rule on two arms and report which rules would flag."""
    arm_a, arm_b = session_arms(rows_a, rows_b, mode, ref_words)
    series = rl.compare_series("s", mode, arm_a, arm_b, seed=seed)
    result = rl.evaluate([series], interleaved=True)
    tests = series["tests"]
    decision = result["decision"]
    family = [t for t in tests if t.get("status") not in ("untested", "no-verdict")]
    out = {
        "family": len(family),
        "naive": [t["key"] for t in family if t["p"] is not None and t["p"] < bs.ALPHA],
        "holm": [t["key"] for t in family if t.get("p_holm") is not None and t["p_holm"] < bs.ALPHA],
        "shipped_ignoring_load": [t["key"] for t in family
                                  if t["status"] in FLAGGED or t["status"] == "indicative"],
        "shipped": [t["key"] for t in family if t["status"] in FLAGGED],
        "flagged_tests": decision["flagged"],
        "_tests": tests,
    }
    if with_old_rule:
        out["p6_rule"] = p6_rule_flags(arm_a, arm_b, seed)
    return out


def p6_rule_flags(arm_a: dict, arm_b: dict, seed: int) -> list[str]:
    """The P6 verdict: WER significant (permutation p < 0.05 on the difference of
    medians AND a bootstrap interval excluding zero), or collapsed runs significant
    (Fisher) under the P6 collapse rule (WER > 2x the best-half median)."""
    flags = []
    a, b = arm_a["wer"], arm_b["wer"]
    p, _ = bs.permutation_p_value(a, b, seed=seed)
    lo, hi = bs.bootstrap_ci(a, b, seed=seed)
    if p < bs.ALPHA and (lo > 0 or hi < 0):
        flags.append("wer")

    def old_flags(arm):
        threshold = 2.0 * bs.best_half_median(arm["wer"])
        floor = 0.75 * arm["ref_words"]
        return sum(1 for w, n in zip(arm["wer"], arm["hyp_words"]) if w > threshold + 1e-12 or n < floor - 1e-12)

    ca, cb = old_flags(arm_a), old_flags(arm_b)
    if bs.fisher_exact(ca, arm_a["n"] - ca, cb, arm_b["n"] - cb) < bs.ALPHA:
        flags.append("collapsed")
    return flags


def draw(pool: list[dict], n: int, rng: random.Random) -> tuple[list[dict], list[dict]]:
    """Two arms of n runs. Without replacement (a random split of real runs) when
    the pool has at least 2n of them, otherwise with replacement (a bootstrap draw
    from the empirical distribution)."""
    if len(pool) >= 2 * n:
        picked = rng.sample(pool, 2 * n)
        return picked[:n], picked[n:]
    return [rng.choice(pool) for _ in range(n)], [rng.choice(pool) for _ in range(n)]


def _replicate(args: tuple) -> dict:
    pool_name, pool, n, mode, ref_words, seed, shifts = args
    rng = random.Random(seed)
    first = draw(pool, n, rng)
    session = evaluate_session(first[0], first[1], mode, ref_words, seed=seed, with_old_rule=True)
    second = draw(pool, n, rng)
    session2 = evaluate_session(second[0], second[1], mode, ref_words, seed=seed + 1)
    # The second session is treated as quiet, so a timing flag COULD be confirmed: the rate is
    # an upper bound on what the load gate lets through.
    confirmation = bs.confirm({"flagged": session["flagged_tests"]}, session2["_tests"],
                              load={"s": {"reliable": True}})
    out = {"family": session["family"],
           **{k: session[k] for k in ("naive", "holm", "shipped_ignoring_load", "shipped", "p6_rule")},
           "confirmed": [r["key"] for r in confirmation["confirmed"]]}
    out["power"] = {}
    for label, spec in shifts.items():
        key = spec[0]
        shifted = [apply_shift(r, spec) for r in first[1]]
        s = evaluate_session(first[0], shifted, mode, ref_words, seed=seed)
        out["power"][label] = key in s["shipped_ignoring_load"]
    return out


# power cases: label -> (metric key, "add" | "mul", amount), applied to every run of arm B.
# Plain tuples, not lambdas: multiprocessing has to pickle them.
SHIFTS_OFFLINE = {
    "WER +5 points": ("wer", "add", 0.05),
    "WER +10 points": ("wer", "add", 0.10),
    "RTF +10%": ("rtf", "mul", 1.10),
    "RTF +20%": ("rtf", "mul", 1.20),
}
SHIFTS_LIVE = {**SHIFTS_OFFLINE,
               "mean per-decode RTF +20%": ("live.mean_decode_rtf", "mul", 1.20)}


def apply_shift(row: dict, spec: tuple) -> dict:
    key, how, amount = spec
    if row.get(key) is None:
        return row
    return {**row, key: row[key] + amount if how == "add" else row[key] * amount}


def simulate(baseline: dict, *, n: int, reps: int, jobs: int, seed: int,
             pools: list[str], power: bool) -> dict:
    ref_words = baseline["fixtures"]["synthetic-taglish"]["ref_words"]
    results = {}
    with multiprocessing.Pool(processes=jobs) as workers:
        for name in pools:
            mode, arm_ids = POOLS[name]
            pool = [r for arm_id in arm_ids for r in baseline["arms"][arm_id]["rows"]]
            shifts = (SHIFTS_LIVE if mode == "live" else SHIFTS_OFFLINE) if power else {}
            jobs_args = [(name, pool, n, mode, ref_words, seed + 1000 * i, shifts) for i in range(reps)]
            outcomes = workers.map(_replicate, jobs_args, chunksize=max(1, reps // (jobs * 8)))
            by_rule = {}
            for rule in ("naive", "p6_rule", "holm", "shipped_ignoring_load", "confirmed"):
                k = sum(1 for o in outcomes if o[rule])
                by_rule[rule] = rate(k, reps)
            per_metric: dict[str, int] = {}
            for o in outcomes:
                for key in set(o["naive"]):
                    per_metric[key] = per_metric.get(key, 0) + 1
            # Which replicates each rule flagged: lets a test recompute the first few
            # replicates from the seed and compare them exactly with the committed ones.
            flagged_replicates = {rule: [i for i, o in enumerate(outcomes) if o[rule]]
                                  for rule in by_rule}
            entry = {"mode": mode, "flagged_replicates": flagged_replicates, "pool_runs": len(pool), "arms_used": arm_ids, "n_per_arm": n,
                     "replicates": reps, "family_size": outcomes[0]["family"],
                     "draw": "without replacement" if len(pool) >= 2 * n else "with replacement (bootstrap)",
                     "any_metric_flagged": by_rule,
                     "naive_flags_by_metric": {k: v / reps for k, v in sorted(per_metric.items())}}
            if power:
                entry["power_of_shipped_rule"] = {
                    label: rate(sum(1 for o in outcomes if o["power"][label]), reps)
                    for label in shifts}
            results[name] = entry
            print(f"{name}: pool {len(pool)} runs, family {entry['family_size']}, {reps} replicates", file=sys.stderr)
            for rule, r in by_rule.items():
                print(f"    {rule:24s} {r['rate'] * 100:5.1f}%  CI {r['ci95'][0] * 100:.1f}-{r['ci95'][1] * 100:.1f}%",
                      file=sys.stderr)
    return results


# --------------------------------------------------------------------------
# A real stream of runs of one binary
# --------------------------------------------------------------------------

def load_stream(path: Path) -> tuple[list[dict], dict]:
    """Per-run rows from a bench_runs directory (run-NN.json) or an exported JSON."""
    if path.is_file():
        data = json.loads(path.read_text())
        return data["rows"], data
    sys.path.insert(0, str(HERE))
    import bench_runs
    records = [r for r in bench_runs.load_records(path) if r.get("ok")]
    rows = [rl.row_from_record(r) for r in records]
    summary = path / "summary.json"
    info = {}
    if summary.exists():
        s = json.loads(summary.read_text())
        info = {k: s.get(k) for k in ("label", "binary", "environment", "model", "audio", "reference")}
    ref_words = records[0]["score"]["ref_words"] if records else None
    return rows, {**info, "ref_words": ref_words}


def export_stream(directory: Path, out: Path, label: str) -> None:
    rows, info = load_stream(directory)
    keep = ("index", "wer", "hyp_words", "rtf", "decode_ms", "filler", "load", "started_utc",
            "retried_windows", "dropped_windows")
    payload = {"schema": 2, "kind": "notero-aa-stream", "label": label,
               "binary_sha256": ((info.get("binary") or {}).get("sha256")),
               "model": info.get("model"), "ref_words": info.get("ref_words"),
               "environment": {k: (info.get("environment") or {}).get(k)
                               for k in ("hardware_model", "cpu", "memory_gb", "macos", "date_utc")},
               "runs": len(rows),
               "rows": [{k: r[k] for k in keep if r.get(k) is not None} for r in rows]}
    out.write_text(json.dumps(payload, indent=1, sort_keys=True) + "\n")
    print(f"wrote {out} ({len(rows)} runs, {out.stat().st_size} bytes)")


def analyze_stream(rows: list[dict], *, n: int, stride: int, ref_words: int, mode: str = "offline") -> dict:
    """Cut a single-binary stream into blocks of 2n consecutive runs, deal them out
    A B B A A B B A ... and run the decision rule on each block."""
    rows = sorted(rows, key=lambda r: r["index"])
    schedule = bs.interleave_schedule(n, "abba")
    blocks = []
    for start in range(0, len(rows) - 2 * n + 1, stride):
        window = rows[start:start + 2 * n]
        a = [r for r, arm in zip(window, schedule) if arm == "A"]
        b = [r for r, arm in zip(window, schedule) if arm == "B"]
        s = evaluate_session(a, b, mode, ref_words, seed=bs.DEFAULT_SEED + start, with_old_rule=True)
        loads = [r.get("load") for r in window if r.get("load") is not None]
        blocks.append({"start_index": window[0]["index"],
                       "median_load": bs.median(loads) if loads else None, **{
                           k: s[k] for k in ("naive", "holm", "shipped_ignoring_load", "shipped", "p6_rule")}})
    def rate_of(rule, subset=None):
        chosen = blocks if subset is None else subset
        return rate(sum(1 for b in chosen if b[rule]), len(chosen))
    disjoint = [b for i, b in enumerate(blocks) if (i * stride) % (2 * n) == 0]
    by_rule = {rule: rate_of(rule) for rule in ("naive", "p6_rule", "holm", "shipped_ignoring_load", "shipped")}
    by_rule_disjoint = {rule: rate_of(rule, disjoint)
                        for rule in ("naive", "p6_rule", "holm", "shipped_ignoring_load", "shipped")}
    per_metric: dict[str, int] = {}
    for b in blocks:
        for key in set(b["naive"]):
            per_metric[key] = per_metric.get(key, 0) + 1
    return {"mode": mode, "n_per_arm": n, "runs": len(rows), "stride": stride, "blocks": len(blocks),
            "disjoint_blocks": len(disjoint),
            "median_load_over_blocks": bs.median([b["median_load"] for b in blocks if b["median_load"] is not None])
            if any(b["median_load"] is not None for b in blocks) else None,
            "any_metric_flagged_overlapping_blocks": by_rule,
            "any_metric_flagged_disjoint_blocks": by_rule_disjoint,
            "naive_flags_by_metric": {k: v / len(blocks) for k, v in sorted(per_metric.items())},
            "note": ("Overlapping blocks share runs and are not independent: their rate is a smoother estimate, "
                     "their interval too narrow. The disjoint blocks are independent sessions but few.")}


def merge_output(out: Path, update: dict) -> None:
    current = json.loads(out.read_text()) if out.exists() else {}
    current.update(update)
    out.write_text(json.dumps(rl.json_safe(current), indent=1, sort_keys=True) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sim = sub.add_parser("simulate", help="resample A/A sessions from the committed P6 runs")
    sim.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    sim.add_argument("--n", type=int, default=8)
    sim.add_argument("--reps", type=int, default=2000)
    sim.add_argument("--jobs", type=int, default=max(1, min(6, (multiprocessing.cpu_count() or 2) - 2)))
    sim.add_argument("--seed", type=int, default=20261101)
    sim.add_argument("--pools", nargs="+", choices=sorted(POOLS), default=sorted(POOLS))
    sim.add_argument("--no-power", action="store_true")
    sim.add_argument("--out", type=Path)
    st = sub.add_parser("stream", help="A/A blocks from a real stream of runs of one binary")
    st.add_argument("--dir", type=Path, required=True, help="a bench_runs directory or an exported JSON")
    st.add_argument("--n", type=int, default=8)
    st.add_argument("--stride", type=int, help="blocks start every STRIDE runs (default 2n: disjoint)")
    st.add_argument("--label", default="stream")
    st.add_argument("--out", type=Path)
    ex = sub.add_parser("export-stream", help="write a stream's per-run numbers as one small JSON")
    ex.add_argument("--dir", type=Path, required=True)
    ex.add_argument("--out", type=Path, required=True)
    ex.add_argument("--label", default="stream")
    args = parser.parse_args(argv)

    if args.command == "simulate":
        baseline = json.loads(args.baseline.read_text())
        results = simulate(baseline, n=args.n, reps=args.reps, jobs=args.jobs, seed=args.seed,
                           pools=args.pools, power=not args.no_power)
        update = {"simulation": {
            "n_per_arm": args.n, "replicates": args.reps, "seed": args.seed,
            "source": baseline["name"],
            "rules": {
                "naive": "any tested metric with an uncorrected rank-sum p < 0.05 (reading the table)",
                "p6_rule": "the P6 verdict: WER permutation p < 0.05 with the bootstrap CI excluding 0, "
                           "or Fisher p < 0.05 on collapsed counts under the P6 collapse rule",
                "holm": "any metric with Holm-adjusted p < 0.05 (no floors)",
                "shipped_ignoring_load": "Holm p < 0.05 AND the effect-size floor met, timing included "
                                         "regardless of machine load (an upper bound: the load gate only removes flags)",
                "confirmed": "flagged by the shipped rule in one session AND reproduced in a second independent session"},
            "pools": results}}
        print(json.dumps(rl.json_safe(update), indent=1)[:2000] if not args.out else "")
        if args.out:
            merge_output(args.out, update)
            print(f"wrote {args.out}", file=sys.stderr)
    elif args.command == "stream":
        rows, info = load_stream(args.dir)
        ref_words = info.get("ref_words") or 0
        analysis = analyze_stream(rows, n=args.n, stride=args.stride or 2 * args.n, ref_words=ref_words)
        analysis["label"] = args.label
        for key in ("any_metric_flagged_overlapping_blocks", "any_metric_flagged_disjoint_blocks"):
            print(key)
            for rule, r in analysis[key].items():
                print(f"    {rule:24s} {r['flagged']}/{r['sessions']} = "
                      f"{(r['rate'] or 0) * 100:.1f}%  CI {r['ci95'][0] * 100:.1f}-{r['ci95'][1] * 100:.1f}%")
        if args.out:
            merge_output(args.out, {f"stream:{args.label}": analysis})
    else:
        export_stream(args.dir, args.out, args.label)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
