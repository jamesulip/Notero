"""The acceptance rule for a speaker-pipeline threshold, written before it was used.

A candidate arm is compared with the baseline arm on one set of fixtures, from the
`rows.jsonl` that `eval/run_diarization_ab.py` writes (n runs per arm and fixture,
interleaved). Everything is judged on per-fixture MEDIANS, so one noisy run cannot decide.

A candidate PASSES a set when ALL of these hold:

  gain        the mean DER across fixtures falls by at least 2.0 points (absolute),
              OR at least one fixture's speaker count goes from wrong to right and the
              mean DER does not rise
  no merges   no fixture ends with fewer speakers than there are, where the baseline
              did not (a new merge is worse than any DER)
  no phantoms no fixture ends with more speakers than there are, where the baseline did
              not
  no missing  no fixture's missed speech rises by more than 0.5 points
  no drift    no fixture gives more distinct outputs across its runs than the baseline
              does (and never fewer than one): the same input must give the same answer
  no regress  no fixture's DER rises by more than 3.0 points
  time        the mean of the per-fixture median speaker-processing time is at most
              10% above the baseline's

A threshold is ACCEPTED only if it passes BOTH the set it was chosen on (TUNING) and a
second set built from voices and seeds it was never tuned on (HOLD-OUT). Passing the
first and failing the second is REJECTED as overfit. Failing the first is REJECTED.

The candidates are fixed here, before any result, so the grid cannot be fitted to the data.
One knob at a time, from the shipping value: mergeGapMs 120 and 0 (shipping 250);
firstPassMinSpeechSeconds 0.6 and 0.4 (1.0); foundingTurnMs 1500, 1000 and 3000 (2000);
sameSpeakerDistance 0.65, 0.60 and 0.75 (0.70). Only knobs that pass alone are combined.
The head-count (`expectedSpeakers`) is judged by its own runs, not by this grid.

Every number comes from SYNTHETIC audio (text-to-speech voices, exact boundaries, a clean
noise floor). Passing here is necessary and not sufficient for a real meeting.

    python3 eval/tuning_verdict.py --base base --candidate gap120 \\
        --tuning /tmp/sweep-T --holdout /tmp/sweep-H
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

GAIN_POINTS = 2.0
MISSED_POINTS = 0.5
REGRESSION_POINTS = 3.0
TIME_FACTOR = 1.10


@dataclass
class Verdict:
    passed: bool
    mean_der_delta: float                       # points, candidate minus baseline
    reasons: list[str] = field(default_factory=list)   # why not, one per failed condition
    notes: list[str] = field(default_factory=list)     # what held, for the record


def load_rows(directory: Path) -> list[dict]:
    path = directory / "rows.jsonl" if directory.is_dir() else directory
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def _per_fixture(rows: list[dict], arm: str) -> dict[str, dict]:
    """Median DER, missed, time and speaker count, and the number of distinct outputs."""
    out: dict[str, dict] = {}
    for fixture in sorted({r["fixture"] for r in rows if r["arm"] == arm}):
        mine = [r for r in rows if r["arm"] == arm and r["fixture"] == fixture]
        out[fixture] = {
            "der": statistics.median(r["der"] for r in mine) * 100,
            "missed": statistics.median(r["missed"] for r in mine) * 100,
            "ms": statistics.median(r["diarize_ms"] for r in mine),
            "speakers": statistics.median(r["speakers"] for r in mine),
            "ref": mine[0]["ref_speakers"],
            "distinct": len({tuple(map(tuple, r["fingerprint"])) for r in mine}),
            "runs": len(mine),
        }
    return out


def judge(rows: list[dict], base: str, candidate: str) -> Verdict:
    b, c = _per_fixture(rows, base), _per_fixture(rows, candidate)
    fixtures = sorted(set(b) & set(c))
    if not fixtures:
        return Verdict(False, 0.0, ["no fixture has both arms"])
    delta = statistics.mean(c[f]["der"] - b[f]["der"] for f in fixtures)
    verdict = Verdict(True, delta)

    def fail(text: str) -> None:
        verdict.passed = False
        verdict.reasons.append(text)

    fixed = [f for f in fixtures if b[f]["speakers"] != b[f]["ref"] and c[f]["speakers"] == c[f]["ref"]]
    broke = [f for f in fixtures if b[f]["speakers"] == b[f]["ref"] and c[f]["speakers"] != c[f]["ref"]]
    if delta <= -GAIN_POINTS:
        verdict.notes.append(f"gain: mean DER {delta:+.2f} points")
    elif fixed and delta <= 0:
        verdict.notes.append(f"gain: speaker count fixed on {', '.join(fixed)}")
    else:
        fail(f"gain: mean DER {delta:+.2f} points (needs <= -{GAIN_POINTS}) and no count fixed")

    merges = [f for f in fixtures
              if c[f]["speakers"] < c[f]["ref"] and c[f]["speakers"] < b[f]["speakers"]]
    if merges:
        fail(f"new merge on {', '.join(merges)}")
    phantoms = [f for f in fixtures
                if c[f]["speakers"] > c[f]["ref"] and c[f]["speakers"] > b[f]["speakers"]]
    if phantoms:
        fail(f"phantom speaker on {', '.join(phantoms)}")
    missing = [f for f in fixtures if c[f]["missed"] - b[f]["missed"] > MISSED_POINTS]
    if missing:
        fail("more missed speech on " + ", ".join(
            f"{f} ({c[f]['missed'] - b[f]['missed']:+.1f})" for f in missing))
    drift = [f for f in fixtures if c[f]["distinct"] > max(1, b[f]["distinct"])]
    if drift:
        fail(f"unstable across runs on {', '.join(drift)}")
    regress = [f for f in fixtures if c[f]["der"] - b[f]["der"] > REGRESSION_POINTS]
    if regress:
        fail("DER regression on " + ", ".join(
            f"{f} ({c[f]['der'] - b[f]['der']:+.1f})" for f in regress))
    base_ms = statistics.mean(b[f]["ms"] for f in fixtures)
    cand_ms = statistics.mean(c[f]["ms"] for f in fixtures)
    if cand_ms > TIME_FACTOR * base_ms:
        fail(f"time {cand_ms:.0f} ms against {base_ms:.0f} ms (limit {TIME_FACTOR:.2f}x)")
    else:
        verdict.notes.append(f"time {cand_ms:.0f} ms against {base_ms:.0f} ms")
    return verdict


def decide(tuning: Verdict, holdout: Verdict | None) -> str:
    if not tuning.passed:
        return "REJECT (fails on the tuning set)"
    if holdout is None:
        return "UNVALIDATED (passes tuning; no hold-out run, so not accepted)"
    if not holdout.passed:
        return "REJECT (overfit: passes tuning, fails hold-out)"
    return "ACCEPT"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--base", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--tuning", type=Path, required=True)
    parser.add_argument("--holdout", type=Path)
    args = parser.parse_args(argv)

    t = judge(load_rows(args.tuning), args.base, args.candidate)
    h = judge(load_rows(args.holdout), args.base, args.candidate) if args.holdout else None
    for name, v in (("tuning", t), ("hold-out", h)):
        if v is None:
            continue
        print(f"{name}: {'PASS' if v.passed else 'FAIL'}  mean DER {v.mean_der_delta:+.2f} points")
        for line in v.notes:
            print(f"    ok    {line}")
        for line in v.reasons:
            print(f"    FAIL  {line}")
    print(decide(t, h))
    return 0 if decide(t, h) == "ACCEPT" else 1


if __name__ == "__main__":
    sys.exit(main())
