"""What does the stated head-count (`expectedSpeakers`) do to the result?

For every fixture, runs `diarbench` with no count, the true count, one too many and one
too few, under each consolidation distance, and scores the output with `eval/der.py`.

    python3 eval/run_headcount.py --diarbench BIN --models DIR --out OUT \\
        --fixtures eval/audio/multispeaker --fixtures /tmp/pairs [--wrap PREFIX]

The head-count is a TARGET, never a cap: while there are more clusters than the count,
the two closest are merged, but only if their centroids are within the consolidation
distance. The shipping distance is 0.85. The question this answers is what a count that
is one too low does to two real people (it merges them when they are closer than the
distance), and whether a tighter distance stops that. What it cannot answer is whether a
tighter distance still merges the FRAGMENTS of one person that the count exists to fix:
the fixtures have no fragmented voice, because text-to-speech does not drift.

All audio is SYNTHETIC. A run is deterministic, so one run per cell is enough here.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import der  # noqa: E402

ARMS = {"ship-0.85": None, "cons-0.78": "consolidationDistance=0.78",
        "cons-0.75": "consolidationDistance=0.75"}
# stated count relative to the true one; None is "Any"
STATED = {"any": None, "true": 0, "one-too-many": +1, "one-too-few": -1}


def run(binary: Path, models: Path, wav: Path, out: Path, stated: int | None,
        tune: str | None, wrap: list[str]) -> dict:
    command = wrap + [str(binary), "--audio", str(wav), "--models", str(models), "--json", str(out)]
    if stated is not None:
        command += ["--expected", str(stated)]
    if tune:
        command += ["--tune", tune]
    subprocess.run(command, check=True, capture_output=True)
    return json.loads(out.read_text())


def summarize(rows: list[dict]) -> list[dict]:
    """One line per (arm, stated): mean DER, fixtures with a wrong speaker count, and the
    fixtures where real speakers were merged (fewer speakers than there are)."""
    out = []
    for arm in sorted({r["arm"] for r in rows}):
        for stated in STATED:
            cell = [r for r in rows if r["arm"] == arm and r["stated"] == stated]
            if not cell:
                continue
            out.append({
                "arm": arm, "stated": stated, "fixtures": len(cell),
                "mean_der": statistics.mean(r["der"] for r in cell) * 100,
                "wrong_count": sum(r["speakers"] != r["ref"] for r in cell),
                "merged": sum(r["speakers"] < r["ref"] for r in cell),
                "split": sum(r["speakers"] > r["ref"] for r in cell),
            })
    return out


def render(summary: list[dict]) -> str:
    lines = ["| arm | stated count | fixtures | mean DER % | wrong speaker count | merged real speakers | phantom |",
             "|---|---|---|---|---|---|---|"]
    for s in summary:
        lines.append(f"| {s['arm']} | {s['stated']} | {s['fixtures']} | {s['mean_der']:.2f} "
                     f"| {s['wrong_count']} | {s['merged']} | {s['split']} |")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--diarbench", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, action="append", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--wrap", nargs="*", default=[])
    parser.add_argument("--arms", nargs="*", choices=list(ARMS), default=list(ARMS),
                        help="consolidation arms to run (default all)")
    parser.add_argument("--stated", nargs="*", choices=list(STATED), default=list(STATED),
                        help="stated counts to run (default all)")
    args = parser.parse_args(argv)

    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for directory in args.fixtures:
        for wav in sorted(directory.glob("*.wav")):
            if wav.stem == "survey" or "." in wav.stem:
                continue
            ref = der.read_rttm(wav.with_suffix(".rttm"))
            n_ref = len({t.speaker for t in ref})
            for arm, tune in ARMS.items():
                if arm not in args.arms:
                    continue
                for stated, delta in STATED.items():
                    if stated not in args.stated:
                        continue
                    count = None if delta is None else max(1, n_ref + delta)
                    if count == 1:
                        continue          # the app short-circuits a count of one; nothing runs
                    path = args.out / f"{wav.stem}.{arm}.{stated}.json"
                    run(args.diarbench, args.models, wav, path, count, tune, args.wrap)
                    score = der.score(ref, der.read_spans_json(path))
                    rows.append({"fixture": wav.stem, "arm": arm, "stated": stated,
                                 "ref": n_ref, "speakers": score.hyp_speakers, "der": score.der})
    (args.out / "rows.json").write_text(json.dumps(rows, indent=2))
    print(render(summarize(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
