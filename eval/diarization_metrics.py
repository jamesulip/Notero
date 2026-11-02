"""Diarization metrics with explicit rules, standard library only.

`eval/der.py` gives DER and its three parts. This module adds what a reader of a
transcript notices: overlapped speech, people merged into one speaker, one person
split into several, the speaker count, and spans that are not valid on the
recording's timeline. Every rule is a field of `Rules`, and `Rules.describe()`
prints them into each report.

Frame scoring (shared with `der.py`): the timeline is cut into `frame`-second
frames; a frame belongs to a segment when its centre falls inside it. Speech is
counted per speaker per frame, so two people talking at once count twice.

DER = (missed + false alarm + confusion) / reference speech, after the one-to-one
mapping of reference to hypothesis speakers that maximises shared time.

Collar: frames within `collar` seconds of any reference segment boundary are not
scored (NIST convention; 0.25 s here unless the plan says otherwise).

Overlap: by default overlapped reference speech IS scored (a diarizer that names
one of two simultaneous speakers is charged "missed" for the other). With
`skip_overlap`, frames with two or more reference speakers are not scored.

Merge: two reference speakers with at least `min_speaker_s` of scored speech each
whose largest share of time goes to the same hypothesis speaker. "Two people
became one".

Fragment: a hypothesis speaker is a piece of reference speaker R when R is the
reference speaker it shares the most time with, and it holds at least
`fragment_share` of R's scored speech. R is fragmented when it has two or more
pieces. "One person became several".

Speaker count: hypothesis speakers with at least `min_hyp_s` of output (scored or
not), against reference speakers in the reference.

Overlap detection: among scored frames with two or more reference speakers, the
share where the hypothesis also has two or more (recall), and the reverse
(precision).
"""

from __future__ import annotations

import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import der  # noqa: E402

Segment = der.Segment


@dataclass(frozen=True)
class Rules:
    collar: float = 0.25
    frame: float = 0.01
    skip_overlap: bool = False
    min_speaker_s: float = 5.0
    fragment_share: float = 0.10
    min_hyp_s: float = 1.0

    def describe(self) -> str:
        overlap = "not scored" if self.skip_overlap else "scored"
        return (f"collar {self.collar} s around every reference boundary; frame {self.frame} s; "
                f"overlapped speech {overlap}; merge/fragment judged on reference speakers with "
                f">= {self.min_speaker_s} s; a fragment holds >= {self.fragment_share:.0%} of its "
                f"speaker; hypothesis speakers under {self.min_hyp_s} s are not counted")

    def as_dict(self) -> dict:
        return asdict(self)


def optimal_mapping(co: list[list[int]]) -> dict[int, int | None]:
    """One-to-one reference -> hypothesis mapping that maximises total shared frames.

    Exact dynamic programme over subsets of reference speakers (2^R states), so it
    gives the same total as `der._best_mapping`'s exhaustive search, fast enough
    for a hypothesis with dozens of speakers. Ties go to the lower hypothesis index.
    """
    n_ref = len(co)
    if n_ref == 0:
        return {}
    if n_ref > 16:
        raise ValueError("more than 16 reference speakers")
    n_hyp = len(co[0]) if co else 0
    size = 1 << n_ref
    # best[mask] after processing hypotheses 0..j-1; choice tracks assignments.
    best = [-1] * size
    best[0] = 0
    choices: list[list[int]] = []   # per hyp: for each mask, the ref chosen (-1 none) to reach it
    for h in range(n_hyp):
        nxt = best[:]
        pick = [-1] * size
        for mask in range(size):
            if best[mask] < 0:
                continue
            for r in range(n_ref):
                if mask >> r & 1:
                    continue
                target = mask | (1 << r)
                value = best[mask] + co[r][h]
                if value > nxt[target]:
                    nxt[target] = value
                    pick[target] = r
        choices.append(pick)
        best = nxt
    # Recover: the best final mask, walking hypotheses backwards.
    mask = max(range(size), key=lambda m: (best[m], -bin(m).count("1")))
    mapping: dict[int, int | None] = {r: None for r in range(n_ref)}
    for h in range(n_hyp - 1, -1, -1):
        r = choices[h][mask]
        if r >= 0:
            mapping[r] = h
            mask &= ~(1 << r)
    return mapping


def _popcount(mask: int) -> int:
    return bin(mask).count("1")


def evaluate(ref: list[Segment], hyp: list[Segment], rules: Rules = Rules()) -> dict:
    """All metrics for one file. Times are seconds; shares are fractions."""
    ref_ids, hyp_ids = der._speakers(ref), der._speakers(hyp)
    ref_index = {s: i for i, s in enumerate(ref_ids)}
    hyp_index = {s: i for i, s in enumerate(hyp_ids)}
    horizon = max([s.end for s in ref] + [s.end for s in hyp] + [0.0])
    n = int(horizon / rules.frame) + 1
    f = rules.frame

    ref_mask = der._labels(ref, f, n, ref_index)
    hyp_mask = der._labels(hyp, f, n, hyp_index)
    keep = der._scored_frames(ref, n, f, rules.collar)
    if rules.skip_overlap:
        keep = [k and _popcount(m) <= 1 for k, m in zip(keep, ref_mask)]

    R, H = len(ref_ids), len(hyp_ids)
    co = [[0] * H for _ in range(R)]
    ref_time = [0] * R
    bits: dict[int, list[int]] = {}

    def members(mask: int) -> list[int]:
        got = bits.get(mask)
        if got is None:
            got = bits[mask] = [i for i in range(mask.bit_length()) if mask >> i & 1]
        return got

    for i in range(n):
        if not keep[i]:
            continue
        rm, hm = ref_mask[i], hyp_mask[i]
        for r in members(rm):
            ref_time[r] += 1
            for h in members(hm):
                co[r][h] += 1

    mapping = optimal_mapping(co)
    mapped = {r: h for r, h in mapping.items() if h is not None}

    # name -> [ref speech, missed, false alarm, confusion] in frames
    parts = {"all": [0, 0, 0, 0], "single": [0, 0, 0, 0], "overlap": [0, 0, 0, 0]}
    ov_ref = ov_hit = hyp_ov = hyp_ov_hit = 0
    for i in range(n):
        if not keep[i]:
            continue
        rm, hm = ref_mask[i], hyp_mask[i]
        n_ref, n_hyp = _popcount(rm), _popcount(hm)
        correct = sum(1 for r, h in mapped.items() if rm >> r & 1 and hm >> h & 1)
        row = (n_ref, max(0, n_ref - n_hyp), max(0, n_hyp - n_ref), min(n_ref, n_hyp) - correct)
        region = "overlap" if n_ref >= 2 else "single"
        for name in ("all", region):
            for k in range(4):
                parts[name][k] += row[k]
        if n_ref >= 2:
            ov_ref += 1
            ov_hit += n_hyp >= 2
        if n_hyp >= 2:
            hyp_ov += 1
            hyp_ov_hit += n_ref >= 2

    def summary(p: list[int]) -> dict:
        total = p[0]
        return {
            "speech_s": round(total * f, 3),
            "der": _ratio(sum(p[1:]), total),
            "missed": _ratio(p[1], total),
            "false_alarm": _ratio(p[2], total),
            "confusion": _ratio(p[3], total),
            "errors_s": round(sum(p[1:]) * f, 3),
            "missed_s": round(p[1] * f, 3),
            "false_alarm_s": round(p[2] * f, 3),
            "confusion_s": round(p[3] * f, 3),
        }

    # Merges and fragments.
    judged = [r for r in range(R) if ref_time[r] * f >= rules.min_speaker_s]
    dominant_hyp = {r: max(range(H), key=lambda h: (co[r][h], -h)) for r in judged if H and max(co[r]) > 0}
    by_hyp: dict[int, list[int]] = {}
    for r, h in dominant_hyp.items():
        by_hyp.setdefault(h, []).append(r)
    merges = [{"hyp": hyp_ids[h], "ref": sorted(ref_ids[r] for r in rs)}
              for h, rs in sorted(by_hyp.items()) if len(rs) >= 2]
    owner = {h: max(range(R), key=lambda r: (co[r][h], -r)) for h in range(H) if R and any(co[r][h] for r in range(R))}
    pieces = {}
    for r in judged:
        pieces[ref_ids[r]] = sum(1 for h, o in owner.items()
                                 if o == r and co[r][h] >= rules.fragment_share * ref_time[r])
    fragmented = sorted(name for name, k in pieces.items() if k >= 2)

    hyp_total = {s: 0.0 for s in hyp_ids}
    for seg in hyp:
        hyp_total[seg.speaker] += seg.end - seg.start
    counted = sorted(s for s, t in hyp_total.items() if t >= rules.min_hyp_s)

    return {
        **summary(parts["all"]),
        "single": summary(parts["single"]),
        "overlap": {
            **summary(parts["overlap"]),
            "share_of_speech": _ratio(parts["overlap"][0], parts["all"][0]),
            "detection_recall": _ratio(ov_hit, ov_ref),
            "detection_precision": _ratio(hyp_ov_hit, hyp_ov),
            "hyp_overlap_s": round(hyp_ov * f, 3),
        },
        "speakers": {
            "ref": R,
            "hyp": len(counted),
            "count_error": len(counted) - R,
            "judged_ref": len(judged),
        },
        "merges": merges,
        "merged_ref_speakers": sum(len(m["ref"]) for m in merges),
        "pieces": pieces,
        "fragmented_ref_speakers": fragmented,
        "mapping": {ref_ids[r]: (hyp_ids[h] if h is not None else None) for r, h in mapping.items()},
    }


def _ratio(num: float, den: float) -> float | None:
    return round(num / den, 6) if den else None


def timestamp_problems(spans: list[dict], duration_s: float, tolerance_s: float = 0.02) -> list[str]:
    """Spans that are not valid on the recording: not finite, negative, inverted,
    empty, or past the end. Order is not required (overlapping speakers)."""
    problems = []
    for k, s in enumerate(spans):
        start, end = s.get("start"), s.get("end")
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in (start, end)):
            problems.append(f"span {k}: not a finite time")
        elif start < 0:
            problems.append(f"span {k}: starts before 0 ({start})")
        elif end <= start:
            problems.append(f"span {k}: ends at or before its start ({start}..{end})")
        elif end > duration_s + tolerance_s:
            problems.append(f"span {k}: ends after the recording ({end} > {duration_s})")
    return problems


def pooled(results: list[dict]) -> dict:
    """Time-weighted totals over files: the corpus DER is total errors over total
    reference speech, not the mean of file DERs."""
    def pool(key: str | None) -> dict:
        rows = [r if key is None else r[key] for r in results]
        speech = sum(x["speech_s"] for x in rows)
        out = {"speech_s": round(speech, 3)}
        for part in ("errors", "missed", "false_alarm", "confusion"):
            seconds = sum(x[f"{part}_s"] for x in rows)
            out[f"{part}_s"] = round(seconds, 3)
            out["der" if part == "errors" else part] = _ratio(seconds, speech)
        return out
    return {
        **pool(None),
        "single": pool("single"),
        "overlap": pool("overlap"),
        "files": len(results),
        "merged_ref_speakers": sum(r["merged_ref_speakers"] for r in results),
        "fragmented_ref_speakers": sum(len(r["fragmented_ref_speakers"]) for r in results),
        "count_errors": sum(1 for r in results if r["speakers"]["count_error"] != 0),
        "abs_count_error": sum(abs(r["speakers"]["count_error"]) for r in results),
    }


if __name__ == "__main__":  # one pair, for inspection
    import argparse
    p = argparse.ArgumentParser(description="Score one hypothesis against one reference.")
    p.add_argument("--ref", type=Path, required=True)
    p.add_argument("--hyp", type=Path, required=True)
    p.add_argument("--collar", type=float, default=0.25)
    p.add_argument("--skip-overlap", action="store_true")
    a = p.parse_args()
    rules = Rules(collar=a.collar, skip_overlap=a.skip_overlap)
    print(json.dumps(evaluate(der.read_segments(a.ref), der.read_segments(a.hyp), rules),
                     indent=1, sort_keys=True))
