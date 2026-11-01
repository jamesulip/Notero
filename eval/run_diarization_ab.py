"""Interleaved A/B of diarization builds on the synthetic multi-speaker fixtures.

Runs `diarbench` once per (repeat, fixture, arm), arms interleaved and rotated
each repeat so no arm always runs first, scores every run with `eval/der.py`,
and prints median and range per arm and fixture.

    python3 eval/run_diarization_ab.py \\
        --arm base=/tmp/base/diarbench:turn \\
        --arm v18=/tmp/v18/diarbench:turn \\
        --arm v18-chunk=/tmp/v18/diarbench:chunk-slots \\
        --fixtures eval/audio/multispeaker --runs 5 --out /tmp/ab \\
        --wrap /tmp/notero-team/bench-lock.sh

An arm is `label=binary:engine[:models-dir]`. A models directory per arm keeps
a build that re-downloads or rewrites its model cache (FluidAudio 0.15.8 and
later re-fetch weights when the cached revision differs) from touching the one
every other build reads. `--wrap` is a command prefix for each run, for example
a lock that serializes the Neural Engine, or `sandbox-exec -p '(version 1)
(allow default)(deny network*)'` to prove a build works offline; it may be given
more than once and wraps outermost-first.

All numbers are SYNTHETIC: text-to-speech voices at exact boundaries. They
compare builds on the same audio and do not describe real meetings.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import der  # noqa: E402


def parse_arm(text: str) -> dict:
    label, _, rest = text.partition("=")
    parts = rest.split(":")
    if not label or len(parts) < 2:
        raise argparse.ArgumentTypeError("arm is label=binary:engine[:models-dir]")
    return {"label": label, "binary": parts[0], "engine": parts[1],
            "models": parts[2] if len(parts) > 2 else None}


def med_range(values: list[float], scale: float = 1.0, digits: int = 1) -> str:
    if not values:
        return "-"
    vs = [v * scale for v in values]
    return f"{statistics.median(vs):.{digits}f} [{min(vs):.{digits}f}-{max(vs):.{digits}f}]"


def fingerprint(spans: list[dict]) -> tuple:
    """What the user would see: who spoke when, at 10 ms resolution."""
    return tuple((round(s["start"], 2), round(s["end"], 2), s["speaker"]) for s in spans)


def run_one(arm: dict, fixture: Path, out: Path, wrap: list[list[str]], mode: str) -> dict | None:
    cmd = [arm["binary"], "--audio", str(fixture), "--engine", arm["engine"],
           "--mode", mode, "--label", arm["label"], "--json", str(out)]
    if arm["models"]:
        cmd += ["--models", arm["models"]]
    for prefix in reversed(wrap):
        cmd = prefix + cmd
    started = time.time()
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0 or not out.exists():
        print(f"FAILED {arm['label']} {fixture.name}: exit {done.returncode}\n"
              f"{done.stderr[-600:]}", file=sys.stderr)
        return None
    data = json.loads(out.read_text())
    data["wallclock_s"] = time.time() - started
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--arm", action="append", type=parse_arm, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--only", action="append", help="fixture name; repeatable")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--wrap", action="append", default=[], help="command prefix, shell-split")
    parser.add_argument("--mode", default="accurate", choices=["accurate", "fast"])
    parser.add_argument("--collar", type=float, default=0.25)
    parser.add_argument("--first-repeat", type=int, default=0,
                        help="index of the first repeat; run one repeat per call to hold a "
                             "lock for a single interleaved round instead of the whole batch")
    parser.add_argument("--report-only", action="store_true",
                        help="print the tables from rows.jsonl in --out and run nothing")
    args = parser.parse_args(argv)

    import shlex
    wrap = [shlex.split(w) for w in args.wrap]
    fixtures = sorted(p for p in args.fixtures.glob("*.wav") if p.stem != "survey"
                      and (not args.only or p.stem in args.only))
    args.out.mkdir(parents=True, exist_ok=True)
    arms = args.arm
    results: list[dict] = []

    rows_path = args.out / "rows.jsonl"
    if args.report_only:
        rows = [json.loads(line) for line in rows_path.read_text().splitlines() if line.strip()]
        for row in rows:
            row["fingerprint"] = tuple(tuple(x) for x in row["fingerprint"])
        report(rows, arms, fixtures, len({r["repeat"] for r in rows}))
        return 0

    for repeat in range(args.first_repeat, args.first_repeat + args.runs):
        # Rotate the arm order each repeat: A B C, B C A, C A B...
        order = arms[repeat % len(arms):] + arms[:repeat % len(arms)]
        for fixture in fixtures:
            ref = der.read_rttm(fixture.with_suffix(".rttm"))
            for arm in order:
                out = args.out / f"{fixture.stem}.{arm['label']}.{repeat}.json"
                data = run_one(arm, fixture, out, wrap, args.mode)
                if data is None:
                    continue
                hyp = der.read_spans_json(out)
                score = der.score(ref, hyp, collar=args.collar).as_dict()
                row = {
                    "arm": arm["label"], "fixture": fixture.stem, "repeat": repeat,
                    "diarize_ms": data["diarizeMs"], "first_pass_ms": data.get("firstPassMs"),
                    "second_pass_ms": data.get("secondPassMs"),
                    "peak_footprint_mb": data["peakFootprintBytes"] / 1e6,
                    "speakers": data["speakers"], "ref_speakers": score["ref_speakers"],
                    "der": score["der"], "missed": score["missed"],
                    "false_alarm": score["false_alarm"], "confusion": score["confusion"],
                    "fingerprint": fingerprint(data["spans"]),
                    "reused": data.get("reusedEmbeddings"), "reembedded": data.get("reembedded"),
                }
                results.append(row)
                with rows_path.open("a") as handle:
                    handle.write(json.dumps(row) + "\n")
        print(f"repeat {repeat} done", file=sys.stderr)

    if not args.first_repeat:
        report(results, arms, fixtures, args.runs)
    return 0


def report(results: list[dict], arms: list[dict], fixtures: list[Path], runs: int) -> None:
    print(f"\nSYNTHETIC multi-speaker fixtures; n={runs} per arm and fixture; "
          f"median [min-max]\n")
    for fixture in fixtures:
        print(f"## {fixture.stem}")
        print("| arm | DER % | missed % | confusion % | speakers (ref) | diarize ms | "
              "2nd-pass ms | peak footprint MB | distinct outputs |")
        print("|---|---|---|---|---|---|---|---|---|")
        for arm in arms:
            rows = [r for r in results if r["arm"] == arm["label"] and r["fixture"] == fixture.stem]
            if not rows:
                print(f"| {arm['label']} | (no successful run) |")
                continue
            speakers = sorted({r["speakers"] for r in rows})
            print(f"| {arm['label']} | {med_range([r['der'] for r in rows], 100)} "
                  f"| {med_range([r['missed'] for r in rows], 100)} "
                  f"| {med_range([r['confusion'] for r in rows], 100)} "
                  f"| {'/'.join(map(str, speakers))} ({rows[0]['ref_speakers']}) "
                  f"| {med_range([r['diarize_ms'] for r in rows], 1, 0)} "
                  f"| {med_range([r['second_pass_ms'] for r in rows if r['second_pass_ms'] is not None], 1, 0)} "
                  f"| {med_range([r['peak_footprint_mb'] for r in rows], 1, 0)} "
                  f"| {len({r['fingerprint'] for r in rows})} of {len(rows)} |")
        print()

    print("## all fixtures pooled (per-fixture medians averaged)")
    print("| arm | mean DER % | mean diarize ms | mean peak footprint MB | fixtures where speaker count != ref |")
    print("|---|---|---|---|---|")
    for arm in arms:
        ders, times, mems, wrong = [], [], [], 0
        for fixture in fixtures:
            rows = [r for r in results if r["arm"] == arm["label"] and r["fixture"] == fixture.stem]
            if not rows:
                continue
            ders.append(statistics.median(r["der"] for r in rows) * 100)
            times.append(statistics.median(r["diarize_ms"] for r in rows))
            mems.append(statistics.median(r["peak_footprint_mb"] for r in rows))
            if statistics.median(r["speakers"] for r in rows) != rows[0]["ref_speakers"]:
                wrong += 1
        if ders:
            print(f"| {arm['label']} | {statistics.mean(ders):.2f} | {statistics.mean(times):.0f} "
                  f"| {statistics.mean(mems):.0f} | {wrong} |")


if __name__ == "__main__":
    sys.exit(main())
