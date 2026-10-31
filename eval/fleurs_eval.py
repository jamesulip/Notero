"""Real-voice evaluation on the public FLEURS Filipino (fil_ph) test split.

WHAT THIS IS. Read Tagalog speech by real people, with human references. It
replaces "all accuracy evidence is one synthetic clip" with the best real-voice
evidence that can be had without touching anyone's recordings.

WHAT THIS IS NOT. It is not Taglish and it is not meetings. FLEURS reads
Wikipedia-style sentences aloud, one sentence per recording, mostly Tagalog with
a few English names and loanwords. No number from here is a statement about
code-switched speech, overlapping speakers, a far-field room or a call. The
long-form files are CONSTRUCTED: consecutive sentences joined with seeded gaps
of digital silence. Each sentence is a separate recording, so the speaker and
the room can change at every join. It exercises the offline windowing and VAD
path on a few minutes of real voices; it is not a meeting.

Data rules (docs: eval/REAL-TAGLISH-PROTOCOL.md). The source is downloaded to
/tmp/notero-data/fleurs (never the repository), treated as untrusted data, and
only ever read by this script. Run it with `python3 -I`. Nothing here opens the
app's recordings or its store.

    # 1. fetch the data (once; the tarball is 889 MB). See `fetch`'s docstring.
    python3 -I eval/fleurs_eval.py fetch --src /tmp/notero-data/fleurs
    # 2. choose the subset, convert to 16 kHz WAV, build the long-form files
    python3 -I eval/fleurs_eval.py prepare --src /tmp/notero-data/fleurs \\
        --work /tmp/notero-data/fleurs-eval --subset 100 --seed 7
    # 3. decode with one or more `transcribe` binaries, interleaved
    python3 -I eval/fleurs_eval.py decode --work /tmp/notero-data/fleurs-eval \\
        --set subset --arm "p6|/path/to/transcribe" --arm "base|/path/to/other"
    # 4. score and compare
    python3 -I eval/fleurs_eval.py score   --work ... --set subset --arm p6 --arm base
    python3 -I eval/fleurs_eval.py compare --work ... --set subset --a base --b p6

Normalization (the same rules as the rest of the repository, stated so they can
be argued with):

  * WER and CER use `score.normalize`: NFKC, lower case, curly quotes to ASCII,
    punctuation dropped, intra-word apostrophes kept, an intra-word HYPHEN
    SPLITS the word ("i-send" is two words). That is what the CLI's own WER does.
  * The per-language split uses `langscore.normalize` (a hyphen survives) and
    `langscore.classify`. Its WER can differ from the pooled one by the handful
    of hyphenated words; both are printed.
  * CER is the character edit distance between the normalized words joined by a
    single space, over the number of reference characters.
  * The reference is FLEURS `raw_transcription` (casing, punctuation and digits
    as written) put through those rules. The FLEURS `transcription` column is
    its own normalization and is scored once as a sensitivity check.
  * Digits stay digits on both sides. Whisper writes "800" where a reader might
    say "walong daan"; FLEURS writes "800" too, so nothing is converted.

The English-token error rate is NOT an English WER. `langscore` classes a word
by a heuristic (Tagalog function words, then the system English word list, else
Filipino). On Filipino read speech its "English" class is a mix of English
loanwords, foreign proper names and Tagalog words that spell like English ones.
`score` prints the most frequent such tokens so a reader can judge.

Standard library only. Everything except `decode` (which runs `transcribe`) and
the optional audio converters runs on Linux.
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import random
import re
import shlex
import shutil
import signal
import statistics
import struct
import subprocess
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence

EVAL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(EVAL_DIR))

import langscore  # noqa: E402
from score import levenshtein, normalize  # noqa: E402

#: The shared first-come lock for anything measured. Overridable so a test can use a stand-in
#: and never touch the real queue.
LOCK_SCRIPT = Path(os.environ.get("NOTERO_BENCH_LOCK", "/tmp/notero-team/bench-lock.sh"))
SAMPLE_RATE = 16_000
SCHEMA = 1

SOURCE_INFO = {
    "dataset": "google/fleurs",
    "config": "fil_ph",
    "split": "test",
    "license": "CC-BY-4.0",
    "license_evidence": (
        "Hugging Face dataset card front matter `license: - cc-by-4.0`, and the card line "
        "'All datasets are licensed under the Creative Commons license (CC-BY).'"
    ),
    "page": "https://huggingface.co/datasets/google/fleurs",
    "tsv_url": "https://huggingface.co/datasets/google/fleurs/resolve/main/data/fil_ph/test.tsv",
    "audio_url": "https://huggingface.co/datasets/google/fleurs/resolve/main/data/fil_ph/audio/test.tar.gz",
    "gated": False,
    "hf_repo_commit": "70bb2e84b976b7e960aa89f1c648e09c59f894dd",
    "tar_sha256_published": "eb8349c6fc36fb363d6d9c30e53c503d1531ca599ad2100afd822aec2774e31b",
    "tar_size_published": 889_243_315,
    "citation": "Conneau et al., FLEURS: Few-shot Learning Evaluation of Universal "
                "Representations of Speech, arXiv:2205.12446",
}


# --------------------------------------------------------------------------
# The TSV, and choosing a subset (pure)
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Utterance:
    sent_id: int
    filename: str
    raw: str          # raw_transcription: casing, punctuation and digits as written
    fleurs_norm: str  # transcription: FLEURS's own normalization
    num_samples: int

    @property
    def uid(self) -> str:
        return Path(self.filename).stem

    @property
    def duration_s(self) -> float:
        return self.num_samples / SAMPLE_RATE


def parse_tsv(text: str) -> list[Utterance]:
    """FLEURS test.tsv: id, file, raw transcription, transcription, characters,
    num_samples, gender. Split on tabs only: the raw text holds double quotes,
    so the `csv` module would eat them."""
    out: list[Utterance] = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) < 6:
            raise ValueError(f"line {number}: expected at least 6 tab-separated columns, got {len(cols)}")
        try:
            out.append(Utterance(int(cols[0]), cols[1], cols[2], cols[3], int(cols[5])))
        except ValueError as error:
            raise ValueError(f"line {number}: {error}") from error
    return out


def _digest(*parts: object) -> int:
    return int.from_bytes(hashlib.sha256(":".join(str(p) for p in parts).encode()).digest()[:8], "big")


def _unit(*parts: object) -> float:
    """A reproducible number in [0, 1) from a label. Independent of the Python
    version, unlike `random.sample`."""
    return _digest(*parts) / 2 ** 64


def one_per_sentence(utts: Sequence[Utterance], seed: int) -> list[Utterance]:
    """FLEURS has up to three recordings of each sentence. Keep one per
    sentence, chosen by a seeded hash, so that no sentence is counted twice and
    one speaker cannot dominate. Sorted by sentence id."""
    best: dict[int, Utterance] = {}
    for utt in utts:
        current = best.get(utt.sent_id)
        if current is None or _digest(seed, "rec", utt.filename) < _digest(seed, "rec", current.filename):
            best[utt.sent_id] = utt
    return [best[k] for k in sorted(best)]


def select_subset(utts: Sequence[Utterance], n: int, seed: int) -> list[Utterance]:
    """`n` utterances, each from a different sentence, in a fixed seeded order.
    A prefix of a longer selection with the same seed: asking for more later
    only adds items, it never reshuffles the first hundred."""
    chosen = one_per_sentence(utts, seed)
    chosen.sort(key=lambda u: _digest(seed, "sent", u.sent_id))
    return chosen[:n]


# --------------------------------------------------------------------------
# WAV in and out (pure; stdlib `wave` cannot read float WAV, which FLEURS is)
# --------------------------------------------------------------------------

class NeedsConversion(Exception):
    """The file is not 16 kHz mono PCM16/float32; an external converter must do it."""


def read_pcm16_mono(data: bytes) -> tuple[int, array.array]:
    """Parse a RIFF/WAVE file and return (sample rate, mono int16 samples).

    Accepts 16-bit PCM and 32-bit IEEE float, mono. Anything else raises
    `NeedsConversion`. A data chunk whose declared size runs past the end of the
    file (a truncated or streamed file) is read up to the end."""
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    fmt = None
    payload = None
    pos = 12
    while pos + 8 <= len(data):
        chunk_id = data[pos:pos + 4]
        (size,) = struct.unpack("<I", data[pos + 4:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        if chunk_id == b"fmt ":
            fmt = body
        elif chunk_id == b"data":
            payload = body
            break
        pos += 8 + size + (size & 1)
    if fmt is None or payload is None or len(fmt) < 16:
        raise ValueError("WAVE file without a usable fmt/data chunk")
    tag, channels, rate, _, _, bits = struct.unpack("<HHIIHH", fmt[:16])
    if tag == 0xFFFE and len(fmt) >= 26:
        (tag,) = struct.unpack("<H", fmt[24:26])
    if channels != 1:
        raise NeedsConversion(f"{channels} channels")
    if tag == 1 and bits == 16:
        usable = len(payload) - len(payload) % 2
        samples = array.array("h")
        samples.frombytes(payload[:usable])
        if sys.byteorder == "big":
            samples.byteswap()
        return rate, samples
    if tag == 3 and bits == 32:
        usable = len(payload) - len(payload) % 4
        floats = array.array("f")
        floats.frombytes(payload[:usable])
        if sys.byteorder == "big":
            floats.byteswap()
        return rate, array.array(
            "h", (max(-32768, min(32767, int(round(x * 32767.0)))) for x in floats))
    raise NeedsConversion(f"format tag {tag}, {bits} bits")


def wav_bytes(samples: array.array, rate: int = SAMPLE_RATE) -> bytes:
    """A canonical 16-bit mono PCM WAV."""
    body = array.array("h", samples)
    if sys.byteorder == "big":
        body.byteswap()
    raw = body.tobytes()
    header = (b"RIFF" + struct.pack("<I", 36 + len(raw)) + b"WAVE"
              + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
              + b"data" + struct.pack("<I", len(raw)))
    return header + raw


def converter_command(src: Path, dst: Path, *, platform: str, have: dict[str, bool]) -> list[str]:
    """The external converter to use when a file is not already 16 kHz mono.
    afconvert on macOS, otherwise ffmpeg. Raises if neither exists."""
    if platform == "darwin" and have.get("afconvert"):
        return ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(src), str(dst)]
    if have.get("ffmpeg"):
        return ["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", str(src), "-ar", "16000",
                "-ac", "1", "-c:a", "pcm_s16le", str(dst)]
    raise RuntimeError("no audio converter: need afconvert (macOS) or ffmpeg")


def load_16k_mono(path: Path) -> array.array:
    """The file as 16 kHz mono int16, converting through a tool if it has to."""
    try:
        rate, samples = read_pcm16_mono(path.read_bytes())
        if rate == SAMPLE_RATE:
            return samples
    except NeedsConversion:
        pass
    scratch = path.with_suffix(".converted.wav")
    have = {"afconvert": shutil.which("afconvert") is not None, "ffmpeg": shutil.which("ffmpeg") is not None}
    subprocess.run(converter_command(path, scratch, platform=sys.platform, have=have), check=True)
    try:
        rate, samples = read_pcm16_mono(scratch.read_bytes())
    finally:
        scratch.unlink(missing_ok=True)
    if rate != SAMPLE_RATE:
        raise RuntimeError(f"{path.name}: converter produced {rate} Hz")
    return samples


# --------------------------------------------------------------------------
# Constructed long-form files (pure)
# --------------------------------------------------------------------------

GAP_MIN_S = 0.3
GAP_MAX_S = 1.5


def gap_seconds(seed: int, label: str, index: int) -> float:
    """The silence after part `index`, uniform in [0.3, 1.5] s, from a seeded hash."""
    return GAP_MIN_S + (GAP_MAX_S - GAP_MIN_S) * _unit(seed, "gap", label, index)


@dataclass(frozen=True)
class Part:
    utt: Utterance
    start_s: float
    end_s: float


def plan_longform(chosen: Sequence[Utterance], *, start_index: int, target_s: float,
                  seed: int, label: str) -> tuple[list[Part], list[float]]:
    """Walk `chosen` (one recording per sentence, ascending sentence id) from
    `start_index`, adding consecutive sentences with a seeded 0.3-1.5 s gap
    between them, until the file is at least `target_s` long. Returns the parts
    with their offsets and the gaps. Raises if the list runs out first."""
    parts: list[Part] = []
    gaps: list[float] = []
    cursor = 0.0
    for offset, utt in enumerate(chosen[start_index:]):
        if parts:
            gap = gap_seconds(seed, label, offset - 1)
            gaps.append(gap)
            cursor += gap
        parts.append(Part(utt, cursor, cursor + utt.duration_s))
        cursor += utt.duration_s
        if cursor >= target_s:
            return parts, gaps
    raise ValueError(f"{label}: ran out of sentences at {cursor:.0f} s before reaching {target_s:.0f} s")


def render_longform(clips: Sequence[array.array], gaps: Sequence[float]) -> tuple[array.array, list[tuple[int, int]]]:
    """Join clips with digital silence. Returns the samples and each clip's
    (start, end) sample offsets in the result."""
    if len(gaps) != len(clips) - 1:
        raise ValueError("need exactly one gap between each pair of clips")
    out = array.array("h")
    spans: list[tuple[int, int]] = []
    for index, clip in enumerate(clips):
        if index:
            out.extend(array.array("h", bytes(2 * int(round(gaps[index - 1] * SAMPLE_RATE)))))
        start = len(out)
        out.extend(clip)
        spans.append((start, len(out)))
    return out, spans


# --------------------------------------------------------------------------
# Scoring (pure)
# --------------------------------------------------------------------------

def edit_distance(a: Sequence, b: Sequence) -> int:
    """Exact Levenshtein distance. Banded, widening the band until the result
    is provably exact: a path of cost c never leaves the diagonal band of width
    c, so a result no larger than the band is the true distance. Fast when the
    sequences are close, which a transcript against its reference is."""
    n, m = len(a), len(b)
    if n == 0:
        return m
    if m == 0:
        return n
    band = max(32, abs(n - m), max(n, m) // 8)
    while True:
        if band >= max(n, m):
            band = max(n, m)
        d = _banded(a, b, band)
        if d <= band:
            return d
        band *= 2


def _banded(a: Sequence, b: Sequence, band: int) -> int:
    n, m = len(a), len(b)
    inf = n + m + 1
    prev = [inf] * (m + 2)
    cur = [inf] * (m + 2)
    for j in range(min(m, band) + 1):
        prev[j] = j
    for i in range(1, n + 1):
        lo = max(0, i - band)
        hi = min(m, i + band)
        if lo > 0:
            cur[lo - 1] = inf
        if lo == 0:
            cur[0] = i
            start = 1
        else:
            start = lo
        ai = a[i - 1]
        for j in range(start, hi + 1):
            best = prev[j - 1] + (0 if ai == b[j - 1] else 1)
            up = prev[j] + 1
            left = cur[j - 1] + 1
            if up < best:
                best = up
            if left < best:
                best = left
            cur[j] = best
        if hi + 1 <= m:
            cur[hi + 1] = inf
        prev, cur = cur, prev
    return prev[m]


#: Above this many reference characters the character edit distance is skipped:
#: it is quadratic in pure Python and a long meeting would take minutes per file.
#: The row says so (`cer_skipped`) and pooled CER counts only the rows that have one.
CER_MAX_CHARS = 20_000


def cer_counts(reference: str, hypothesis: str) -> tuple[int, int]:
    """(character errors, reference characters) on the normalized text."""
    ref = " ".join(normalize(reference))
    hyp = " ".join(normalize(hypothesis))
    return edit_distance(ref, hyp), len(ref)


def load_collisions(path: Path) -> frozenset[str]:
    """The audited Tagalog-collision list: one token per line, '#' comments."""
    return frozenset(line.strip().lower() for line in path.read_text(encoding="utf8").splitlines()
                     if line.strip() and not line.lstrip().startswith("#"))


def audited_english(reference: str, hypothesis: str, tagalog: frozenset[str]) -> tuple[int, int]:
    """(English reference tokens, how many of them were substituted or deleted),
    where a token `langscore` calls English but the audit lists as Tagalog does
    not count. Same alignment as `langscore.score`."""
    ref = langscore.normalize(reference)
    hyp = langscore.normalize(hypothesis)
    classes = langscore.classify_words(ref)
    english = [c == "en" and w not in tagalog for w, c in zip(ref, classes)]
    ops = langscore.align(ref, hyp)
    wrong = {ri for op, ri, _ in ops if op in ("sub", "del") and ri is not None}
    return sum(english), sum(1 for i, flag in enumerate(english) if flag and i in wrong)


def score_utterance(reference: str, hypothesis: str, tagalog: frozenset[str] = frozenset()) -> dict:
    """Everything one utterance contributes to a pooled score, as integers, so
    that pooling is a sum and not an average of averages. `tagalog` is the
    audited collision list; without it the audited English count equals langscore's."""
    ref_words = normalize(reference)
    hyp_words = normalize(hypothesis)
    subs, dels, ins = levenshtein(ref_words, hyp_words)
    ref_chars = len(" ".join(ref_words))
    cer_skipped = ref_chars > CER_MAX_CHARS
    char_err, char_ref = (0, 0) if cer_skipped else cer_counts(reference, hypothesis)
    lang = langscore.score(reference, hypothesis)
    classes = {c: {"ref": v["ref_words"], "err": v["errors"], "ins": v["insertions"]}
               for c, v in lang["by_class"].items()}
    en_ref, en_err = audited_english(reference, hypothesis, tagalog)
    return {
        "ref_words": len(ref_words), "hyp_words": len(hyp_words),
        "sub": subs, "del": dels, "ins": ins,
        "char_err": char_err, "char_ref": char_ref, "cer_skipped": cer_skipped,
        "langscore_errors": lang["sub"] + lang["del"] + lang["ins"],
        "langscore_ref_words": lang["ref_words"],
        "classes": classes,
        "en_audited_ref": en_ref, "en_audited_err": en_err,
        "switch_positions": lang["code_switch"]["positions"],
        "switch_errors": lang["code_switch"]["errors"],
    }


def pooled(rows: Sequence[dict]) -> dict:
    """Pooled (micro-averaged) WER, CER and per-class error rates. Word errors
    are substitutions + deletions + insertions over reference words, the same
    definition as `score.py`, and the same as the CLI's WER."""
    words = sum(r["ref_words"] for r in rows)
    errors = sum(r["sub"] + r["del"] + r["ins"] for r in rows)
    chars = sum(r["char_ref"] for r in rows)
    char_errors = sum(r["char_err"] for r in rows)
    classes: dict[str, dict] = {}
    for name in ("tl", "en", "other"):
        ref = sum(r["classes"][name]["ref"] for r in rows)
        err = sum(r["classes"][name]["err"] for r in rows)
        ins = sum(r["classes"][name]["ins"] for r in rows)
        classes[name] = {"ref_words": ref, "errors": err, "insertions": ins,
                         "error_rate": err / ref if ref else None}
    lang_words = sum(r["langscore_ref_words"] for r in rows)
    switches = sum(r["switch_positions"] for r in rows)
    return {
        "utterances": len(rows),
        "ref_words": words,
        "sub": sum(r["sub"] for r in rows), "del": sum(r["del"] for r in rows),
        "ins": sum(r["ins"] for r in rows),
        "wer": errors / words if words else None,
        "cer": char_errors / chars if chars else None,
        "cer_skipped_rows": sum(1 for r in rows if r["cer_skipped"]),
        "langscore_wer": sum(r["langscore_errors"] for r in rows) / lang_words if lang_words else None,
        "classes": classes,
        "en_audited": {"ref_words": sum(r["en_audited_ref"] for r in rows),
                       "errors": sum(r["en_audited_err"] for r in rows),
                       "error_rate": (sum(r["en_audited_err"] for r in rows) / sum(r["en_audited_ref"] for r in rows))
                       if sum(r["en_audited_ref"] for r in rows) else None},
        "code_switch": {"positions": switches, "errors": sum(r["switch_errors"] for r in rows),
                        "error_rate": (sum(r["switch_errors"] for r in rows) / switches) if switches else None},
        "empty_transcripts": sum(1 for r in rows if r["hyp_words"] == 0),
    }


def per_utterance_wer(row: dict) -> float | None:
    return (row["sub"] + row["del"] + row["ins"]) / row["ref_words"] if row["ref_words"] else None


def bootstrap_pooled(rows: Sequence[dict], *, seed: int = 11, resamples: int = 2000,
                     alpha: float = 0.05) -> tuple[float, float] | None:
    """Percentile interval for the pooled WER, resampling UTTERANCES with
    replacement. It says how much the choice of utterances moves the number; it
    says nothing about speakers or microphones outside FLEURS."""
    if not rows:
        return None
    rng = random.Random(seed)
    errors = [r["sub"] + r["del"] + r["ins"] for r in rows]
    words = [r["ref_words"] for r in rows]
    n = len(rows)
    values = []
    for _ in range(resamples):
        idx = [rng.randrange(n) for _ in range(n)]
        w = sum(words[i] for i in idx)
        if w:
            values.append(sum(errors[i] for i in idx) / w)
    values.sort()
    lo = values[int(alpha / 2 * (len(values) - 1))]
    hi = values[int((1 - alpha / 2) * (len(values) - 1))]
    return lo, hi


def sign_test_p(wins_a: int, wins_b: int) -> float:
    """Two-sided exact binomial sign test on the items where the arms differ."""
    n = wins_a + wins_b
    if n == 0:
        return 1.0
    k = min(wins_a, wins_b)
    tail = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * tail)


def paired_compare(rows_a: dict[str, dict], rows_b: dict[str, dict], *, seed: int = 11,
                   resamples: int = 4000) -> dict:
    """A against B on the utterances both decoded. Differences are B - A in
    word errors, so a NEGATIVE pooled difference means B is better."""
    ids = sorted(set(rows_a) & set(rows_b))
    if not ids:
        raise ValueError("the two arms share no utterances")
    err_a = {i: rows_a[i]["sub"] + rows_a[i]["del"] + rows_a[i]["ins"] for i in ids}
    err_b = {i: rows_b[i]["sub"] + rows_b[i]["del"] + rows_b[i]["ins"] for i in ids}
    words = {i: rows_a[i]["ref_words"] for i in ids}
    total = sum(words.values())
    wer_a = sum(err_a.values()) / total
    wer_b = sum(err_b.values()) / total
    better_a = [i for i in ids if err_a[i] < err_b[i]]
    better_b = [i for i in ids if err_b[i] < err_a[i]]
    same = [i for i in ids if err_a[i] == err_b[i]]
    rng = random.Random(seed)
    diffs = []
    for _ in range(resamples):
        idx = [ids[rng.randrange(len(ids))] for _ in ids]
        w = sum(words[i] for i in idx)
        diffs.append((sum(err_b[i] for i in idx) - sum(err_a[i] for i in idx)) / w)
    diffs.sort()
    return {
        "utterances": len(ids), "ref_words": total,
        "wer_a": wer_a, "wer_b": wer_b, "wer_diff_b_minus_a": wer_b - wer_a,
        "ci95": (diffs[int(0.025 * (len(diffs) - 1))], diffs[int(0.975 * (len(diffs) - 1))]),
        "identical_error_counts": len(same),
        "a_better": sorted(better_a, key=lambda i: err_b[i] - err_a[i], reverse=True),
        "b_better": sorted(better_b, key=lambda i: err_a[i] - err_b[i], reverse=True),
        "sign_p": sign_test_p(len(better_a), len(better_b)),
        "worst_regressions_of_b": sorted(
            ((err_b[i] - err_a[i], i) for i in better_a), reverse=True)[:10],
    }


# --------------------------------------------------------------------------
# Decoding through the `transcribe` CLI
# --------------------------------------------------------------------------

def parse_stderr(text: str) -> dict:
    """The window counters the JSON report does not carry. Reuses the benchmark
    harness's parser, so one definition of 'retried' and 'dropped' serves both."""
    from bench_runs import parse_stderr as bench_parse
    return bench_parse(text)


def decode_command(binary: Path, audio: Path, json_path: Path, extra: Sequence[str],
                   *, use_lock: bool) -> list[str]:
    """One decode. No reference is passed: this script scores the text itself,
    so every arm is scored by the same code. No diarization: this is a
    transcription test."""
    cmd: list[str] = []
    if use_lock:
        cmd.append(str(LOCK_SCRIPT))
    cmd += [str(binary), "--audio", str(audio), "--no-diarize", "--json", str(json_path)]
    return cmd + list(extra)


def schedule(items: Sequence[str], arms: Sequence[str], repeats: int) -> list[tuple[int, str, str]]:
    """(repeat, item, arm) in the order to run them: every arm on one item
    back to back, the starting arm rotating from item to item (A B, B A, ...),
    so slow drift in machine load is not charged to one arm."""
    out: list[tuple[int, str, str]] = []
    for rep in range(repeats):
        for k, item in enumerate(items):
            shift = (k + rep) % len(arms)
            for arm in list(arms[shift:]) + list(arms[:shift]):
                out.append((rep, item, arm))
    return out


def with_ext(prefix: Path, ext: str) -> Path:
    """`prefix` plus an extension. Not `Path.with_suffix`: the prefix ends in
    '.r0' (the repeat number), which with_suffix would replace."""
    return prefix.parent / (prefix.name + ext)


def run_decode(*, binary: Path, extra: list[str], audio: Path, out_prefix: Path, use_lock: bool,
               timeout: float) -> dict:
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    json_path = with_ext(out_prefix, ".report.json")
    cmd = decode_command(binary, audio, json_path, extra, use_lock=use_lock)
    record: dict = {"schema": SCHEMA, "cmd": cmd,
                    "started_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                    "loadavg_1m_at_launch": round(os.getloadavg()[0], 2)}
    began = time.monotonic()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                            start_new_session=True)
    try:
        _, stderr = proc.communicate(timeout=timeout)
        record["returncode"] = proc.returncode
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            _, stderr = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            _, stderr = proc.communicate()
        record.update(ok=False, error=f"timed out after {timeout:.0f} s (lock wait included)")
    record["wall_s_including_lock_wait"] = round(time.monotonic() - began, 2)
    with_ext(out_prefix, ".stderr.txt").write_text(stderr)
    record["stderr_info"] = parse_stderr(stderr)
    if "error" not in record:
        if record["returncode"] != 0:
            record.update(ok=False, error=f"exit code {record['returncode']}")
        elif not json_path.exists():
            record.update(ok=False, error="no JSON report was written")
        else:
            report = json.loads(json_path.read_text())
            record.update(
                ok=True, transcript=report.get("transcript", ""),
                rtf=report.get("rtf"), decode_ms=report.get("decodeMs"),
                duration_ms=report.get("durationMs"), load_ms=report.get("loadMs"),
                model=report.get("model"), language=report.get("language"),
                detected_language=report.get("detectedLanguage"),
                window_languages=report.get("windowLanguages"), words=report.get("wordCount"))
    record.setdefault("ok", False)
    with_ext(out_prefix, ".json").write_text(json.dumps(record, indent=2, sort_keys=True))
    return record


# --------------------------------------------------------------------------
# Subcommands
# --------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def command_fetch(args: argparse.Namespace) -> int:
    """Download the TSV and the audio tarball, verify the tarball against the
    hash Hugging Face publishes, and extract it with tarfile's `data` filter
    (no absolute paths, no links outside the directory). Anonymous: the dataset
    is not gated. If the endpoint asks for a token, this stops and says so."""
    src = args.src
    src.mkdir(parents=True, exist_ok=True)
    for url, name in ((SOURCE_INFO["tsv_url"], "test.tsv"), (SOURCE_INFO["audio_url"], "test.tar.gz")):
        target = src / name
        if target.exists() and name == "test.tar.gz" and target.stat().st_size == SOURCE_INFO["tar_size_published"]:
            continue
        cmd = ["curl", "-sS", "-L", "-C", "-", "--retry", "5", "-o", str(target),
               "-w", "%{http_code}", url]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() not in ("200", "206", "416"):
            print(f"stop: {url} -> HTTP {result.stdout.strip() or '?'} {result.stderr.strip()}\n"
                  "The endpoint is unavailable or wants a token. Do not look for one.", file=sys.stderr)
            return 1
    digest = sha256_file(src / "test.tar.gz")
    if digest != SOURCE_INFO["tar_sha256_published"]:
        print(f"stop: tarball sha256 {digest} != published {SOURCE_INFO['tar_sha256_published']}",
              file=sys.stderr)
        return 1
    import tarfile
    target = src / "test"
    if not target.exists():
        target.mkdir()
        with tarfile.open(src / "test.tar.gz") as tar:
            tar.extractall(target, filter="data")
    print(f"ok: {len(list(target.rglob('*.wav')))} wav files under {target}")
    return 0


def find_audio_dir(src: Path) -> Path:
    """The tarball nests its files in test/; accept both layouts."""
    for candidate in (src / "test" / "test", src / "test"):
        if candidate.is_dir() and any(candidate.glob("*.wav")):
            return candidate
    raise FileNotFoundError(f"no wav files under {src}/test; run `fetch` first")


def command_prepare(args: argparse.Namespace) -> int:
    utts = parse_tsv((args.src / "test.tsv").read_text(encoding="utf8"))
    audio_dir = find_audio_dir(args.src)
    missing = [u.filename for u in utts if not (audio_dir / u.filename).exists()]
    if missing:
        print(f"error: {len(missing)} audio files from the TSV are missing, e.g. {missing[:3]}", file=sys.stderr)
        return 1
    work: Path = args.work
    (work / "audio").mkdir(parents=True, exist_ok=True)

    def emit(uid: str, samples: array.array) -> dict:
        path = work / "audio" / f"{uid}.wav"
        data = wav_bytes(samples)
        path.write_bytes(data)
        return {"wav": str(path), "sha256": hashlib.sha256(data).hexdigest(),
                "duration_s": round(len(samples) / SAMPLE_RATE, 3)}

    def item(utt: Utterance, uid: str, samples: array.array) -> dict:
        entry = {"id": uid, "sent_id": utt.sent_id, "source_file": utt.filename,
                 "ref": utt.raw, "ref_fleurs_norm": utt.fleurs_norm}
        entry.update(emit(uid, samples))
        return entry

    cache: dict[str, array.array] = {}

    def clip(utt: Utterance) -> array.array:
        if utt.filename not in cache:
            cache[utt.filename] = load_16k_mono(audio_dir / utt.filename)
        return cache[utt.filename]

    subset = [item(u, f"u{u.sent_id}-{u.uid[:8]}", clip(u)) for u in select_subset(utts, args.subset, args.seed)]

    chosen = one_per_sentence(utts, args.seed)
    targets = [float(t) for t in args.longform_seconds]
    region = len(chosen) // len(targets)
    longforms, parts = [], []
    for k, target in enumerate(targets):
        label = f"lf{k + 1}"
        start = k * region + int(_unit(args.seed, "lfstart", label) * 10)
        plan, gaps = plan_longform(chosen, start_index=start, target_s=target, seed=args.seed, label=label)
        clips = [clip(p.utt) for p in plan]
        samples, spans = render_longform(clips, gaps)
        entry = {"id": label, "target_s": target, "gaps_s": [round(g, 3) for g in gaps],
                 "ref": " ".join(p.utt.raw for p in plan),
                 "ref_fleurs_norm": " ".join(p.utt.fleurs_norm for p in plan),
                 "parts": [p.utt.sent_id for p in plan]}
        entry.update(emit(label, samples))
        longforms.append(entry)
        for index, (p, (a, b)) in enumerate(zip(plan, spans)):
            part = item(p.utt, f"{label}-p{index:02d}", clips[index])
            part.update(longform=label, start_s=round(a / SAMPLE_RATE, 3), end_s=round(b / SAMPLE_RATE, 3),
                        start_sample=a, end_sample=b)
            parts.append(part)

    manifest = {
        "schema": SCHEMA, "seed": args.seed, "source": SOURCE_INFO,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "notes": ("FLEURS fil_ph test, read Tagalog. One recording per sentence. Long-form files "
                  "are constructed from consecutive sentence ids with seeded 0.3-1.5 s gaps of "
                  "digital silence; each part is a separate recording, so voice and room can change "
                  "at each join. Not Taglish, not a meeting."),
        "sets": {"subset": subset, "parts": parts, "longform": longforms},
    }
    (work / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    lf_summary = ", ".join("%s %.0f s" % (lf["id"], lf["duration_s"]) for lf in longforms)
    print(f"subset {len(subset)} utterances, {len(parts)} long-form parts, {len(longforms)} long-form files "
          f"({lf_summary}) -> {work}")
    return 0


def command_manifest(args: argparse.Namespace) -> int:
    """Hashes and sizes of every source file, written next to the data."""
    audio_dir = find_audio_dir(args.src)
    files = {}
    for path in sorted(audio_dir.glob("*.wav")):
        files[path.name] = {"size": path.stat().st_size, "sha256": sha256_file(path)}
    out = dict(SOURCE_INFO)
    out["downloaded_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    out["tar"] = {"size": (args.src / "test.tar.gz").stat().st_size, "sha256": sha256_file(args.src / "test.tar.gz")}
    out["tsv"] = {"size": (args.src / "test.tsv").stat().st_size, "sha256": sha256_file(args.src / "test.tsv")}
    out["wav_files"] = files
    target = args.src / "MANIFEST.json"
    target.write_text(json.dumps(out, indent=2))
    print(f"wrote {target} ({len(files)} wav files)")
    return 0


_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$")


def references_to_manifest(folder: Path, entries: Sequence[dict]) -> dict:
    """A work manifest from the folder that File > Export Corrections as References
    writes (its manifest.json holds `id`, `audio`, `ref`). Only paths inside `folder`
    are accepted, and the audio is not copied: the decode reads it where it is.
    The reference is the transcript with the person's corrections applied, one row per line."""
    root = folder.resolve()
    items = []
    for entry in entries:
        entry_id = str(entry["id"])
        if not _SAFE_ID.match(entry_id):
            raise ValueError(f"unusable id {entry_id!r}: use letters, digits, '-' and '_'")
        paths = []
        for key in ("audio", "ref"):
            path = (root / entry[key]).resolve()
            if root not in path.parents:
                raise ValueError(f"{entry_id}: {key} path {entry[key]!r} leaves {root}")
            if not path.is_file():
                raise FileNotFoundError(f"{entry_id}: no such {key} file {path}")
            paths.append(path)
        items.append({"id": entry_id, "sent_id": None, "wav": str(paths[0]),
                      "ref": paths[1].read_text(encoding="utf8"), "ref_fleurs_norm": "",
                      "category": entry.get("category", "own"),
                      "duration_s": round(entry.get("durationMs", 0) / 1000, 3)})
    if not items:
        raise ValueError("the reference set has no recordings")
    return {"schema": SCHEMA, "seed": None, "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": {"dataset": "user-reference-set", "license": "private, not for redistribution",
                       "folder": str(root)},
            "notes": "The user's own corrected transcripts. Scored on this machine only.",
            "sets": {"subset": items, "parts": [], "longform": []}}


def command_import_references(args: argparse.Namespace) -> int:
    entries = json.loads((args.refs / "manifest.json").read_text(encoding="utf8"))
    manifest = references_to_manifest(args.refs, entries)
    args.work.mkdir(parents=True, exist_ok=True)
    (args.work / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    words = sum(len(normalize(i["ref"])) for i in manifest["sets"]["subset"])
    print(f"{len(manifest['sets']['subset'])} recordings, {words} reference words -> {args.work}")
    return 0


def load_manifest(work: Path) -> dict:
    return json.loads((work / "manifest.json").read_text())


def parse_arm(spec: str) -> tuple[str, Path, list[str]]:
    """'name|/path/to/transcribe|--language auto --tier fast'."""
    parts = spec.split("|", 2)
    if len(parts) < 2 or not parts[0] or not parts[1]:
        raise argparse.ArgumentTypeError("arm must be 'name|binary[|extra arguments]'")
    return parts[0], Path(parts[1]), shlex.split(parts[2]) if len(parts) == 3 else []


def chunked(entries: Sequence, size: int) -> list[list]:
    return [list(entries[i:i + size]) for i in range(0, len(entries), size)]


def command_decode(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.work)
    items = {e["id"]: e for e in manifest["sets"][args.set]}
    ids = list(items)[: args.limit] if args.limit else list(items)
    arm_specs = list(args.arm)
    arms = {name: (binary, extra) for name, binary, extra in map(parse_arm, arm_specs)}
    use_lock = LOCK_SCRIPT.exists() and not args.no_lock
    if not use_lock and not args.no_lock:
        print("note: no bench lock on this machine; do not quote timings", file=sys.stderr)
    for binary, _ in arms.values():
        if not binary.exists():
            print(f"error: no such binary {binary}", file=sys.stderr)
            return 2

    def finished(rep: int, item_id: str, arm: str) -> bool:
        record = with_ext(args.work / "decode" / args.set / arm / f"{item_id}.r{rep}", ".json")
        return record.exists() and bool(json.loads(record.read_text()).get("ok")) and not args.force

    if args.plan_file:                      # a batch handed down by a parent that holds the lock
        plan = [tuple(entry) for entry in json.loads(args.plan_file.read_text())]
    else:
        plan = schedule(ids, list(arms), args.repeats)
    pending = [entry for entry in plan if not finished(*entry)]

    if use_lock and args.lock_batch > 1:
        # Hold the bench lock once per batch of decodes, not once per decode. Each
        # decode is about 11 s but waits behind other people's minutes-long holds, so
        # one lock per decode costs hours of queueing. A batch is still short (a
        # minute or two); the arms inside it stay interleaved.
        batches = chunked(pending, args.lock_batch)
        script = Path(__file__).resolve()
        for number, batch in enumerate(batches, 1):
            plan_path = args.work / "decode" / "_batches" / f"{os.getpid()}-{number}.json"
            plan_path.parent.mkdir(parents=True, exist_ok=True)
            plan_path.write_text(json.dumps(batch))
            cmd = [str(LOCK_SCRIPT), sys.executable, "-I", str(script), "decode", "--work", str(args.work),
                   "--set", args.set, "--no-lock", "--plan-file", str(plan_path),
                   "--timeout", str(args.timeout)]
            for spec in arm_specs:
                cmd += ["--arm", spec]
            if args.force:
                cmd.append("--force")
            print(f"batch {number}/{len(batches)}: {len(batch)} decodes under one lock", flush=True)
            result = subprocess.run(cmd)
            plan_path.unlink(missing_ok=True)
            if result.returncode != 0:
                print(f"error: batch {number} exited {result.returncode}", file=sys.stderr)
                return result.returncode
        return 0

    done = len(plan) - len(pending)
    for rep, item_id, arm in pending:
        prefix = args.work / "decode" / args.set / arm / f"{item_id}.r{rep}"
        binary, extra = arms[arm]
        record = run_decode(binary=binary, extra=extra, audio=Path(items[item_id]["wav"]),
                            out_prefix=prefix, use_lock=use_lock, timeout=args.timeout)
        done += 1
        flag = "" if record["ok"] else f"  FAILED {record.get('error')}"
        rtf = f"{record['rtf']:.3f}" if record.get("rtf") is not None else "-"
        print(f"[{done}/{len(plan)}] {arm:<14} r{rep} {item_id:<22} rtf {rtf} "
              f"retried {record['stderr_info'].get('retried_windows', 0)} "
              f"dropped {record['stderr_info'].get('dropped_windows', 0)}{flag}", flush=True)
    return 0


COLLISIONS_FILE = EVAL_DIR / "fleurs_tagalog_collisions.txt"


def load_arm_rows(work: Path, set_name: str, arm: str, *, norm_field: str = "ref",
                  tagalog: frozenset[str] = frozenset()) -> tuple[dict, list[dict]]:
    """Scored rows for each (item, repeat) of one arm. Returns ({id: repeat-0 row}, all records)."""
    manifest = load_manifest(work)
    items = {e["id"]: e for e in manifest["sets"][set_name]}
    records: list[dict] = []
    for path in sorted((work / "decode" / set_name / arm).glob("*.json")):
        if path.name.endswith(".report.json"):
            continue
        record = json.loads(path.read_text())
        stem = path.stem
        item_id, rep = stem.rsplit(".r", 1)
        if item_id not in items or not record.get("ok"):
            continue
        record["item"] = item_id
        record["rep"] = int(rep)
        record["score"] = score_utterance(items[item_id][norm_field], record["transcript"], tagalog)
        records.append(record)
    first = {r["item"]: r["score"] for r in records if r["rep"] == 0}
    return first, records


def fmt_pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def english_tokens(reference_texts: Sequence[str]) -> Counter:
    """The tokens `langscore` classes as English in the references, so a
    reader can see what the 'English' class really holds."""
    counts: Counter = Counter()
    for text in reference_texts:
        words = langscore.normalize(text)
        for word, cls in zip(words, langscore.classify_words(words)):
            if cls == "en":
                counts[word] += 1
    return counts


def summarize_arm(records: list[dict]) -> dict:
    """One arm's table row from all its records (all repeats pooled as separate runs)."""
    rows = [r["score"] for r in records]
    summary = pooled(rows)
    wers = [w for w in (per_utterance_wer(r) for r in rows) if w is not None]
    summary["wer_median_per_utterance"] = statistics.median(wers) if wers else None
    summary["wer_p90_per_utterance"] = sorted(wers)[int(0.9 * (len(wers) - 1))] if wers else None
    summary["wer_ci95"] = bootstrap_pooled(rows)
    rtfs = [r["rtf"] for r in records if r.get("rtf") is not None]
    summary["rtf_median"] = statistics.median(rtfs) if rtfs else None
    summary["rtf_range"] = (min(rtfs), max(rtfs)) if rtfs else None
    loads = [r["loadavg_1m_at_launch"] for r in records if "loadavg_1m_at_launch" in r]
    summary["loadavg_median"] = statistics.median(loads) if loads else None
    summary["loadavg_range"] = (min(loads), max(loads)) if loads else None
    info = [r["stderr_info"] for r in records]
    summary["windows_total"] = sum(i.get("windows", 0) for i in info)
    summary["windows_retried"] = sum(i.get("retried_windows", 0) for i in info)
    summary["windows_dropped"] = sum(i.get("dropped_windows", 0) for i in info)
    summary["runs_with_retry"] = sum(1 for i in info if i.get("retried_windows", 0) > 0)
    languages = Counter(r.get("detected_language") for r in records)
    summary["detected_language"] = dict(languages)
    return summary


def run_to_run(records: list[dict]) -> dict:
    """Repeats of the same item on the same arm: how many produced different text."""
    by_item: dict[str, list[dict]] = defaultdict(list)
    for r in records:
        by_item[r["item"]].append(r)
    repeated = {k: v for k, v in by_item.items() if len(v) > 1}
    differing = {k: v for k, v in repeated.items() if len({x["transcript"] for x in v}) > 1}
    spread = {}
    for k, v in differing.items():
        wers = [per_utterance_wer(x["score"]) for x in v]
        spread[k] = (min(wers), max(wers))
    return {"items_repeated": len(repeated), "items_with_different_text": len(differing),
            "repeats_per_item": sorted({len(v) for v in repeated.values()}), "spread": spread}


def format_summary_table(name_to_summary: dict[str, dict]) -> str:
    head = ("| arm | utts | ref words | WER | 95% CI | CER | median utt WER | tl err | en err (n) | "
            "en* err (n) | switch err (n) | retried / dropped windows | empty | RTF med (range) | load |\n"
            "|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---|---:|---|---|\n")
    lines = []
    for name, s in name_to_summary.items():
        en = s["classes"]["en"]
        ci = s["wer_ci95"]
        rtf = (f"{s['rtf_median']:.3f} ({s['rtf_range'][0]:.3f}-{s['rtf_range'][1]:.3f})"
               if s["rtf_median"] is not None else "n/a")
        load = (f"{s['loadavg_median']:.1f} ({s['loadavg_range'][0]:.1f}-{s['loadavg_range'][1]:.1f})"
                if s["loadavg_median"] is not None else "n/a")
        lines.append(
            f"| {name} | {s['utterances']} | {s['ref_words']} | {fmt_pct(s['wer'])} | "
            f"{fmt_pct(ci[0]) + '-' + fmt_pct(ci[1]) if ci else 'n/a'} | {fmt_pct(s['cer'])} | "
            f"{fmt_pct(s['wer_median_per_utterance'])} | {fmt_pct(s['classes']['tl']['error_rate'])} | "
            f"{fmt_pct(en['error_rate'])} ({en['ref_words']}) | "
            f"{fmt_pct(s['en_audited']['error_rate'])} ({s['en_audited']['ref_words']}) | "
            f"{fmt_pct(s['code_switch']['error_rate'])} ({s['code_switch']['positions']}) | "
            f"{s['windows_retried']} / {s['windows_dropped']} | {s['empty_transcripts']} | {rtf} | {load} |")
    return head + "\n".join(lines)


def command_score(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.work)
    items = manifest["sets"][args.set]
    field = "ref_fleurs_norm" if args.fleurs_norm else "ref"
    summaries: dict[str, dict] = {}
    detail: dict[str, dict] = {}
    fleurs = manifest["source"].get("dataset") == "google/fleurs"
    tagalog = load_collisions(COLLISIONS_FILE) if fleurs else frozenset()
    for arm in args.arm:
        _, records = load_arm_rows(args.work, args.set, arm, norm_field=field, tagalog=tagalog)
        if not records:
            print(f"no decoded records for arm {arm}", file=sys.stderr)
            continue
        # One row per arm from repeat 0 (each item counted once). Further repeats of
        # the same items get their own rows, so run-to-run spread is visible.
        for rep in sorted({r["rep"] for r in records}):
            name = arm if rep == 0 else f"{arm} r{rep}"
            summaries[name] = summarize_arm([r for r in records if r["rep"] == rep])
        detail[arm] = {"run_to_run": run_to_run(records)}
    print(f"set: {args.set}   reference: {'FLEURS `transcription`' if args.fleurs_norm else '`raw_transcription`'}"
          f" through score.normalize\n")
    print(format_summary_table(summaries))
    for arm, d in detail.items():
        r = d["run_to_run"]
        if r["items_repeated"]:
            print(f"\nrun-to-run, {arm}: {r['items_repeated']} items decoded {r['repeats_per_item']} times, "
                  f"{r['items_with_different_text']} produced different text between repeats")
            for k, (lo, hi) in sorted(r["spread"].items()):
                print(f"    {k}: WER {lo * 100:.1f}%-{hi * 100:.1f}%")
    tokens = english_tokens([e[field] for e in items])
    audited = Counter({w: c for w, c in tokens.items() if w not in tagalog})
    print(f"\n`langscore` 'English' tokens in these {len(items)} references (en): {sum(tokens.values())} tokens, "
          f"{len(tokens)} distinct. Most frequent: "
          + ", ".join(f"{w}({c})" for w, c in tokens.most_common(15)))
    if tagalog:
        print(f"After removing {len(tagalog)} hand-audited Tagalog collisions (en*): {sum(audited.values())} tokens, "
              f"{len(audited)} distinct. These are English words, technical terms and foreign proper names, "
              f"read inside Tagalog sentences; they are not code-switching. Most frequent: "
              + ", ".join(f"{w}({c})" for w, c in audited.most_common(15)))
    if args.json:
        args.json.write_text(json.dumps({"set": args.set, "summaries": summaries, "detail": detail},
                                        indent=2, default=str))
    return 0


def command_compare(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.work)
    items = {e["id"]: e for e in manifest["sets"][args.set]}
    first_a, rec_a = load_arm_rows(args.work, args.set, args.a)
    first_b, rec_b = load_arm_rows(args.work, args.set, args.b)
    result = paired_compare(first_a, first_b)
    print(f"{args.set}: {args.b} against {args.a}, {result['utterances']} utterances, "
          f"{result['ref_words']} reference words (repeat 0 of each)")
    print(f"WER {args.a} {fmt_pct(result['wer_a'])}  {args.b} {fmt_pct(result['wer_b'])}  "
          f"difference {result['wer_diff_b_minus_a'] * 100:+.2f} points "
          f"(95% CI {result['ci95'][0] * 100:+.2f} to {result['ci95'][1] * 100:+.2f}, resampling utterances)")
    print(f"utterances where {args.a} had fewer errors: {len(result['a_better'])}, "
          f"{args.b}: {len(result['b_better'])}, same: {result['identical_error_counts']}; "
          f"sign test p = {result['sign_p']:.3f}")
    ha = {r["item"]: r for r in rec_a if r["rep"] == 0}
    hb = {r["item"]: r for r in rec_b if r["rep"] == 0}
    identical = sum(1 for i in ha if i in hb and ha[i]["transcript"] == hb[i]["transcript"])
    print(f"transcripts byte-identical between the arms: {identical} of {len(set(ha) & set(hb))}")
    if result["worst_regressions_of_b"]:
        print(f"\nutterances where {args.b} is worse than {args.a} (most word errors added first):")
        for added, item_id in result["worst_regressions_of_b"]:
            print(f"  {item_id}  +{added} errors")
            print(f"    ref : {items[item_id]['ref'][:160]}")
            print(f"    {args.a:<4}: {ha[item_id]['transcript'][:160]}")
            print(f"    {args.b:<4}: {hb[item_id]['transcript'][:160]}")
    if args.json:
        args.json.write_text(json.dumps(result, indent=2, default=str))
    return 0


def command_longform(args: argparse.Namespace) -> int:
    """Long-form against the same sentences decoded one at a time. Sentence
    boundaries in the long-form transcript are unknown, so the comparison is on
    the pooled word errors against the same references, not word by word."""
    manifest = load_manifest(args.work)
    longforms = {e["id"]: e for e in manifest["sets"]["longform"]}
    parts = manifest["sets"]["parts"]
    _, rec_long = load_arm_rows(args.work, "longform", args.arm)
    _, rec_parts = load_arm_rows(args.work, "parts", args.arm)
    print(f"arm {args.arm}: long-form file against the same sentences decoded one at a time\n")
    print("| file | length | runs | long-form WER med (range) | CER med | same sentences one by one | "
          "windows | retried | dropped | RTF med (range) |")
    print("|---|---:|---:|---|---:|---:|---:|---:|---:|---|")
    for lf_id, lf in longforms.items():
        mine = [r for r in rec_long if r["item"] == lf_id]
        if not mine:
            continue
        part_ids = {p["id"] for p in parts if p["longform"] == lf_id}
        part_rows = [r["score"] for r in rec_parts if r["item"] in part_ids and r["rep"] == 0]
        per_part = pooled(part_rows) if part_rows else None
        wers = [per_utterance_wer(r["score"]) for r in mine]
        cers = [r["score"]["char_err"] / r["score"]["char_ref"] for r in mine]
        info = [r["stderr_info"] for r in mine]
        rtfs = [r["rtf"] for r in mine if r.get("rtf") is not None]
        print(f"| {lf_id} | {lf['duration_s']:.0f} s | {len(mine)} | {fmt_pct(statistics.median(wers))} "
              f"({fmt_pct(min(wers))}-{fmt_pct(max(wers))}) | {fmt_pct(statistics.median(cers))} | "
              f"{fmt_pct(per_part['wer']) if per_part else 'n/a'} | "
              f"{statistics.median(i.get('windows', 0) for i in info):g} | "
              f"{sum(i.get('retried_windows', 0) for i in info)} | {sum(i.get('dropped_windows', 0) for i in info)} | "
              f"{statistics.median(rtfs):.3f} ({min(rtfs):.3f}-{max(rtfs):.3f}) |")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("fetch", help="download, verify and extract FLEURS fil_ph test")
    p.add_argument("--src", type=Path, required=True)
    p.set_defaults(func=command_fetch)

    p = sub.add_parser("manifest", help="write MANIFEST.json (hashes and sizes) beside the data")
    p.add_argument("--src", type=Path, required=True)
    p.set_defaults(func=command_manifest)

    p = sub.add_parser("prepare", help="choose the subset, convert to 16 kHz WAV, build long-form files")
    p.add_argument("--src", type=Path, required=True)
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--subset", type=int, default=100)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--longform-seconds", nargs="+", type=float, default=[180, 270, 360])
    p.set_defaults(func=command_prepare)

    p = sub.add_parser("import-references",
                       help="use the folder 'Export Corrections as References' wrote (private; stays on this machine)")
    p.add_argument("--refs", type=Path, required=True)
    p.add_argument("--work", type=Path, required=True)
    p.set_defaults(func=command_import_references)

    p = sub.add_parser("decode", help="run `transcribe` over a set, arms interleaved")
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--set", choices=["subset", "parts", "longform"], required=True)
    p.add_argument("--arm", action="append", required=True,
                   help="'name|/path/to/transcribe|extra args'; repeat for each arm")
    p.add_argument("--repeats", type=int, default=1)
    p.add_argument("--limit", type=int, default=0, help="only the first N items of the set")
    p.add_argument("--timeout", type=float, default=1800)
    p.add_argument("--no-lock", action="store_true")
    p.add_argument("--lock-batch", type=int, default=1,
                   help="hold the bench lock once per this many decodes instead of once per decode")
    p.add_argument("--plan-file", type=Path, help=argparse.SUPPRESS)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=command_decode)

    p = sub.add_parser("score", help="WER, CER and per-class errors per arm")
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--set", choices=["subset", "parts", "longform"], required=True)
    p.add_argument("--arm", action="append", required=True)
    p.add_argument("--fleurs-norm", action="store_true", help="score against FLEURS's own normalization")
    p.add_argument("--json", type=Path)
    p.set_defaults(func=command_score)

    p = sub.add_parser("compare", help="paired comparison of two arms on one set")
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--set", choices=["subset", "parts", "longform"], required=True)
    p.add_argument("--a", required=True, help="the baseline arm")
    p.add_argument("--b", required=True, help="the candidate arm")
    p.add_argument("--json", type=Path)
    p.set_defaults(func=command_compare)

    p = sub.add_parser("longform", help="long-form files against the same sentences one by one")
    p.add_argument("--work", type=Path, required=True)
    p.add_argument("--arm", required=True)
    p.set_defaults(func=command_longform)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
