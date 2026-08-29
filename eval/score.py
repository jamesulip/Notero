"""Score transcripts against references, split by language mix.

Phase 2's exit criterion is "live WER within ~5 points of your offline number",
which only means something if both numbers come out of the same scorer. This is
that scorer -- run it on the offline output to establish the baseline, then on
the live pipeline's output to measure what the streaming layer cost you.

Layout:

    eval/manifest.json   [{"id", "audio", "ref", "category"}, ...]
    eval/refs/<id>.txt   reference transcript
    <hyp-dir>/<id>.txt   system output to score

    ./.venv/bin/python eval/score.py <hyp-dir> [--label offline]

`category` is one of tagalog / english / mixed. The split matters: section 3
predicts Taglish degrades worst under streaming, so a single pooled WER would
hide exactly the failure this project is most exposed to.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
CATEGORIES = ("tagalog", "english", "mixed")


def normalize(text: str) -> list[str]:
    """Casing and punctuation are the cleanup pass's job, not the ASR's."""
    text = unicodedata.normalize("NFKC", text).lower()
    text = text.replace("’", "'").replace("‘", "'")
    # Keep intra-word apostrophes (Tagalog "ng'", English "don't"), drop the rest.
    text = re.sub(r"[^\w\s']", " ", text)
    text = re.sub(r"(?<!\w)'|'(?!\w)", " ", text)
    return text.split()


def levenshtein(ref: list[str], hyp: list[str]) -> tuple[int, int, int]:
    """Returns (substitutions, deletions, insertions) via edit-distance backtrace."""
    n, m = len(ref), len(hyp)
    # cost grid with operation counts carried alongside
    prev = [(j, 0, 0, j) for j in range(m + 1)]  # (dist, sub, del, ins)
    for i in range(1, n + 1):
        cur = [(i, 0, i, 0)]
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                cur.append(prev[j - 1])
                continue
            sub_d, sub_s, sub_del, sub_i = prev[j - 1]
            del_d, del_s, del_del, del_i = prev[j]
            ins_d, ins_s, ins_del, ins_i = cur[j - 1]
            best = min(
                (sub_d + 1, sub_s + 1, sub_del, sub_i),
                (del_d + 1, del_s, del_del + 1, del_i),
                (ins_d + 1, ins_s, ins_del, ins_i + 1),
                key=lambda t: t[0],
            )
            cur.append(best)
        prev = cur
    _, subs, dels, ins = prev[m]
    return subs, dels, ins


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hyp_dir", type=Path, help="directory of <id>.txt outputs")
    parser.add_argument("--label", default="system", help="name for this run")
    parser.add_argument("--manifest", type=Path, default=EVAL_DIR / "manifest.json")
    args = parser.parse_args()

    if not args.manifest.exists():
        print(
            f"no manifest at {args.manifest}\n\n"
            "Create one alongside your eval audio:\n"
            '  [{"id": "clip01", "audio": "audio/clip01.wav",\n'
            '    "ref": "refs/clip01.txt", "category": "mixed"}]\n',
            file=sys.stderr,
        )
        return 1

    entries = json.loads(args.manifest.read_text())
    # Reference paths are relative to the manifest, not to eval/, so an
    # alternate manifest elsewhere resolves its own refs.
    base = args.manifest.parent
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0, 0, 0])  # S, D, I, N
    missing = []

    for entry in entries:
        hyp_path = args.hyp_dir / f"{entry['id']}.txt"
        if not hyp_path.exists():
            missing.append(entry["id"])
            continue
        ref = normalize((base / entry["ref"]).read_text())
        hyp = normalize(hyp_path.read_text())
        subs, dels, ins = levenshtein(ref, hyp)
        for bucket in (entry.get("category", "mixed"), "ALL"):
            acc = totals[bucket]
            acc[0] += subs
            acc[1] += dels
            acc[2] += ins
            acc[3] += len(ref)

    if missing:
        print(f"warning: {len(missing)} clips missing from {args.hyp_dir}: "
              f"{', '.join(missing[:5])}{'...' if len(missing) > 5 else ''}\n",
              file=sys.stderr)

    print(f"{args.label}\n")
    header = f"{'split':>9} {'WER':>7} {'sub':>6} {'del':>6} {'ins':>6} {'words':>7}"
    print(header)
    print("-" * len(header))
    for bucket in (*CATEGORIES, "ALL"):
        if bucket not in totals:
            continue
        subs, dels, ins, words = totals[bucket]
        wer = (subs + dels + ins) / words * 100 if words else 0.0
        print(f"{bucket:>9} {wer:>6.2f}% {subs:>6} {dels:>6} {ins:>6} {words:>7}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
