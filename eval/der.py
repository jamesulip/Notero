"""Frame-level diarization error rate, standard library only.

Scores a hypothesis (who spoke when) against a reference with the usual three
error classes, after the best one-to-one speaker mapping:

    missed     reference speech the hypothesis left without a speaker
    false      hypothesis speech where the reference has no speech
    confusion  speech given to a speaker that does not map to the true one

    DER = (missed + false + confusion) / total reference speech

Speech is counted per speaker per frame, so two people talking at once count
twice and a hypothesis that names only one of them is charged for the other as
"missed". A collar (default 0.25 s, the NIST convention) removes a band around
every reference turn boundary from the score, because nobody can mark a
boundary more precisely than that.

Inputs are RTTM or the JSON written by `diarbench`. Labels never have to match:
the mapping is chosen to maximise agreement, which is also what makes the
number honest about a diarizer that splits one person in two (the second half
is confusion) or fuses two people into one (one of them is confusion).

    python3 eval/der.py --ref fixtures/two-distinct.rttm --hyp run1.json
    python3 eval/der.py --ref REF.rttm --hyp HYP.rttm --collar 0 --json

Every number this produces on `make_multispeaker.py` fixtures is SYNTHETIC:
concatenated text-to-speech voices with exact boundaries. It supports A/B
comparison between two implementations on the same file. It says nothing
about real meetings, which have overlap, crosstalk, room acoustics and
voices that are not machine-generated.
"""

from __future__ import annotations

import argparse
import itertools
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class Segment:
    start: float
    end: float
    speaker: str


@dataclass
class Score:
    total: float          # reference speech scored, in speaker-seconds
    missed: float
    false_alarm: float
    confusion: float
    ref_speakers: int
    hyp_speakers: int
    mapping: dict[str, str | None] = field(default_factory=dict)  # ref -> hyp

    @property
    def der(self) -> float:
        return (self.missed + self.false_alarm + self.confusion) / self.total if self.total else 0.0

    def as_dict(self) -> dict:
        t = self.total or 1.0
        return {
            "der": round(self.der, 6),
            "missed": round(self.missed / t, 6),
            "false_alarm": round(self.false_alarm / t, 6),
            "confusion": round(self.confusion / t, 6),
            "scored_speech_s": round(self.total, 3),
            "ref_speakers": self.ref_speakers,
            "hyp_speakers": self.hyp_speakers,
            "mapping": self.mapping,
        }


# --- reading -----------------------------------------------------------------

def read_rttm(path: Path) -> list[Segment]:
    out: list[Segment] = []
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[0] != "SPEAKER":
            continue
        start, duration = float(parts[3]), float(parts[4])
        out.append(Segment(start, start + duration, parts[7]))
    return out


def read_spans_json(path: Path) -> list[Segment]:
    """`diarbench` output: {"spans": [{"start": s, "end": s, "speaker": id}]}."""
    data = json.loads(path.read_text())
    spans = data["spans"] if isinstance(data, dict) else data
    return [Segment(float(s["start"]), float(s["end"]), str(s["speaker"])) for s in spans]


def read_segments(path: Path) -> list[Segment]:
    return read_spans_json(path) if path.suffix == ".json" else read_rttm(path)


def write_rttm(segments: list[Segment], path: Path, uri: str) -> None:
    lines = [
        f"SPEAKER {uri} 1 {s.start:.3f} {s.end - s.start:.3f} <NA> <NA> {s.speaker} <NA> <NA>"
        for s in sorted(segments, key=lambda s: (s.start, s.end))
    ]
    path.write_text("\n".join(lines) + "\n")


# --- scoring -----------------------------------------------------------------

def _speakers(segments: list[Segment]) -> list[str]:
    return sorted({s.speaker for s in segments})


def _labels(segments: list[Segment], frame: float, n_frames: int,
            index: dict[str, int]) -> list[int]:
    """One bitmask of active speakers per frame. A frame belongs to a segment
    when its centre falls inside it, so segment edges round to the nearest frame."""
    masks = [0] * n_frames
    for seg in segments:
        first = max(0, int(round(seg.start / frame - 0.5)))
        last = min(n_frames, int(round(seg.end / frame - 0.5)) + 1)
        bit = 1 << index[seg.speaker]
        for i in range(first, last):
            if (i + 0.5) * frame >= seg.start and (i + 0.5) * frame < seg.end:
                masks[i] |= bit
    return masks


def _scored_frames(ref: list[Segment], n_frames: int, frame: float, collar: float) -> list[bool]:
    keep = [True] * n_frames
    if collar <= 0:
        return keep
    for seg in ref:
        for edge in (seg.start, seg.end):
            lo = max(0, int((edge - collar) / frame))
            hi = min(n_frames, int((edge + collar) / frame) + 1)
            for i in range(lo, hi):
                centre = (i + 0.5) * frame
                if edge - collar <= centre < edge + collar:
                    keep[i] = False
    return keep


def score(ref: list[Segment], hyp: list[Segment], *, collar: float = 0.25,
          frame: float = 0.01) -> Score:
    ref_ids, hyp_ids = _speakers(ref), _speakers(hyp)
    ref_index = {s: i for i, s in enumerate(ref_ids)}
    hyp_index = {s: i for i, s in enumerate(hyp_ids)}
    horizon = max([s.end for s in ref] + [s.end for s in hyp] + [0.0])
    n_frames = int(horizon / frame) + 1

    ref_mask = _labels(ref, frame, n_frames, ref_index)
    hyp_mask = _labels(hyp, frame, n_frames, hyp_index)
    keep = _scored_frames(ref, n_frames, frame, collar)

    # Seconds of co-occurrence for every (ref speaker, hyp speaker) pair.
    overlap = [[0] * len(hyp_ids) for _ in ref_ids]
    for i in range(n_frames):
        if not keep[i] or not ref_mask[i] or not hyp_mask[i]:
            continue
        for r in range(len(ref_ids)):
            if ref_mask[i] >> r & 1:
                for h in range(len(hyp_ids)):
                    if hyp_mask[i] >> h & 1:
                        overlap[r][h] += 1

    mapping = _best_mapping(overlap, len(ref_ids), len(hyp_ids))

    total = missed = false_alarm = confusion = 0
    for i in range(n_frames):
        if not keep[i]:
            continue
        n_ref = bin(ref_mask[i]).count("1")
        n_hyp = bin(hyp_mask[i]).count("1")
        correct = sum(
            1 for r, h in mapping.items()
            if h is not None and ref_mask[i] >> r & 1 and hyp_mask[i] >> h & 1
        )
        total += n_ref
        missed += max(0, n_ref - n_hyp)
        false_alarm += max(0, n_hyp - n_ref)
        confusion += min(n_ref, n_hyp) - correct

    return Score(
        total=total * frame, missed=missed * frame, false_alarm=false_alarm * frame,
        confusion=confusion * frame, ref_speakers=len(ref_ids), hyp_speakers=len(hyp_ids),
        mapping={ref_ids[r]: (hyp_ids[h] if h is not None else None) for r, h in mapping.items()},
    )


def _best_mapping(overlap: list[list[int]], n_ref: int, n_hyp: int) -> dict[int, int | None]:
    """Injective ref -> hyp assignment maximising shared time.

    Exhaustive over permutations, which is fine for meetings (a handful of
    speakers) and keeps this file free of a Hungarian implementation to get
    wrong. A reference speaker may map to nothing when the hypothesis has fewer.
    """
    if n_ref == 0:
        return {}
    pool: list[int | None] = list(range(n_hyp)) + [None] * n_ref
    best_total, best = -1, {r: None for r in range(n_ref)}
    seen: set[tuple] = set()
    for choice in itertools.permutations(pool, n_ref):
        if choice in seen:
            continue
        seen.add(choice)
        total = sum(overlap[r][h] for r, h in enumerate(choice) if h is not None)
        if total > best_total:
            best_total, best = total, dict(enumerate(choice))
    return best


# --- command line ------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--ref", type=Path, required=True)
    parser.add_argument("--hyp", type=Path, required=True)
    parser.add_argument("--collar", type=float, default=0.25, help="seconds, default 0.25")
    parser.add_argument("--frame", type=float, default=0.01, help="seconds, default 0.01")
    parser.add_argument("--json", action="store_true", help="print one JSON object")
    args = parser.parse_args(argv)

    result = score(read_segments(args.ref), read_segments(args.hyp),
                   collar=args.collar, frame=args.frame)
    if args.json:
        print(json.dumps(result.as_dict(), sort_keys=True))
    else:
        d = result.as_dict()
        print(f"DER       {d['der'] * 100:6.2f}%")
        print(f"  missed     {d['missed'] * 100:6.2f}%")
        print(f"  false alarm{d['false_alarm'] * 100:6.2f}%")
        print(f"  confusion  {d['confusion'] * 100:6.2f}%")
        print(f"speakers   ref {d['ref_speakers']}  hyp {d['hyp_speakers']}"
              f"   scored {d['scored_speech_s']:.1f} s, collar {args.collar} s")
        print(f"mapping    {d['mapping']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
