"""Controlled experiment on the live path: can text be committed sooner without losing any?

The question (FINDINGS 26, 27, 38): the wait for LocalAgreement, not the decode, is most of a
word's commit latency. Head-tolerant agreement cut it by 35-43% on two synthetic clips and was
left off for want of a second session on real audio. This runs that session, and the other
levers of the live path one at a time, against the production configuration.

    prepare   cut the evaluation clips from real public corpora (Liva AI, AMI, FLEURS)
    plan      fix arms, clips, rounds, the seeded order, the statistics and the gate -- BEFORE any run
    run       replay every (round, clip, arm) in real time, offline, under the bench lock; resumable
    score     one numbers-only record per run (no audio, no words)
    analyze   paired effects with intervals, the A/A spread, every gate; one session
    decide    apply the plan's rule to the sessions: change the default, or keep it

One variable at a time. Every arm is the production configuration plus ONE flag set of
`transcribe --live` (`ARMS` below). The control runs TWICE in every block (C0 and C1): C1 is
the A/A replicate, so every block carries its own measure of the noise, and the variants are
compared with the mean of the two controls. A block is one clip in one round; its arms run in a
seeded random order, back to back, so a slow stretch of the machine lands on all of them.

Data rules (docs/BENCHMARKS.md, eval/REAL-TAGLISH-PROTOCOL.md). The sources are public corpora
with a licence (CC BY 4.0) already on this Mac under /tmp/notero-data: Liva AI en-tl, AMI,
FLEURS. They are read, never uploaded, never put in git. Only numbers leave the work folder.
Nothing here opens a recording of the app, and no transcription service is used. Every
measured run is serialized by the bench lock and has its network denied. Standard library only;
run it with `python3 -I`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import random
import math
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO = EVAL_DIR.parent
sys.path.insert(0, str(EVAL_DIR))

import live_latency_lib as ll  # noqa: E402
from score import normalize  # noqa: E402

SCHEMA = 1
SEED = 20261102
LOCK = Path("/tmp/notero-team/bench-lock.sh")
WRAP = [str(LOCK), "sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"]
SAMPLE_RATE = 16_000
DEFAULT_WORK = Path("/tmp/notero-p2")
CLIP_FIXTURE = EVAL_DIR / "fixtures" / "live-latency-clips.json"

#: One variable at a time. Every arm is `transcribe --live --realtime --live-trace` with
#: the production configuration plus these flags. C0 and C1 are the same arm twice.
ARMS: dict[str, dict] = {
    "C0": {"flags": [], "variable": "control", "what": "production: context 15 s, hop 1.5 s, pre-roll 1.5 s, boundary 700 ms, LocalAgreement-2"},
    "C1": {"flags": [], "variable": "control", "what": "the control again: the A/A replicate"},
    "HT": {"flags": ["--head-tolerance", "3", "--head-min-run", "3"], "variable": "agreement",
           "what": "head-tolerant agreement: tolerance 3 words, run of 3 (FINDINGS 27)"},
    "VAD": {"flags": ["--silence-boundary", "500"], "variable": "VAD finalization",
            "what": "an utterance closes after 500 ms of silence instead of 700 ms"},
    "PRE": {"flags": ["--pre-roll", "3000"], "variable": "context anchoring",
            "what": "3 s of committed audio kept in front of the active region instead of 1.5 s (the ring holds context + pre-roll, so the active region is still capped at 15 s)"},
    "HOP": {"flags": ["--hop", "1300"], "variable": "hop scheduling",
            "what": "a decode every 1.3 s instead of 1.5 s (the replay hands over 100 ms chunks, so a hop is a whole number of chunks)"},
    "ADA": {"flags": ["--adaptive-hop"], "variable": "hop scheduling",
            "what": "the hop tracks the last decode (1.5x, between 1.0 and 1.5 s)"},
    "CTX": {"flags": ["--context", "12000"], "variable": "forced commits",
            "what": "the active region is capped at 12 s, so a stalled window is forced sooner"},
}
CONTROLS = ("C0", "C1")

#: Fixed in the plan before the first run; `analyze` and `decide` read the plan's copy.
DEFAULT_GATE = {
    "latency": {
        "metric": "the geometric mean, over the blocks of a session, of (the variant run's median wall commit latency / the mean of the two control runs' medians in the same block); the reduction is 1 minus that. A block is one clip in one round. Not a pooled median of words: pooled over clips that differ by 5x it sits in the gap of a bimodal mixture and moves by seconds on a few words.",
        "minRelativeReduction": 0.20,
        "support": "one-sided randomization test of that statistic, p < 0.05: in a block any of the three runs (C0, C1, the variant) is as likely to be the variant under 'no effect'",
        "supportAlpha": 0.05,
        "randomizationResamples": 10000,
        "interval": "t-interval on the per-block log ratio of median latencies (blocks are the unit); reported, and its one-sided lower bound must also be above 0",
        "tailGuard": {"minReduction": -0.05, "what": "the p90 and the p95 commit latency must not be more than 5% worse, by the same statistic"},
        "perClipGuard": {"minReduction": -0.10, "what": "no clip may get more than 10% slower (its reduction, as a geometric mean over its rounds)"},
        "referenceAnchor": {"minReduction": 0.10, "what": "the same statistic on the time from the end of each reference segment (a speaker turn, an utterance, a read sentence) to the commit of the last word inside it must fall by at least 10%: a variant that only shifts the model's own word timestamps cannot pass"},
    },
    "wer": {
        "clips": "clips with a word reference",
        "supportedRegressionAlpha": 0.05,
        "test": "paired randomization over blocks (variant minus the mean of the two controls, one-sided), Holm-adjusted over the four safety metrics",
        "maxMeanIncreasePt": 0.5,
        "maxClipMeanIncreasePt": 3.0,
    },
    "missingSpeech": {
        "alpha": 0.05,
        "maxDeletionRateIncreasePt": 0.5,
        "maxMissingShareIncreasePt": 0.5,
        "maxOmittedSegmentsIncreasePt": 0.5,
        "what": "deletion rate (word-reference clips); share of reference speech time with no word within 1 s; share of reference segments of 1 s or more (one speaker's turn, one utterance) with no word overlapping them, 300 ms either side. The last two on every clip, AMI included.",
    },
    "hallucinations": {"rule": "the variant's total of critical hallucinations (invented filler phrases, loops of 4 repeats or more, runs of 6 or more inserted words on clean references, and a 4-word phrase committed again within 30 words, each net of the reference's own) must not exceed the mean of the two controls' totals; the same for ghost words (words more than 1 s from any reference speech)"},
    "immutability": {"maxViolations": 0, "scope": "every run of every arm of the session, and the monitor's word count must equal the words committed"},
    "droppedHops": {"maxRelativeIncrease": 0.20, "orAbsolutePp": 1.0},
    "failures": {"maxFailedRuns": 0, "maxFailedDecodesIncrease": 0},
    "aa": {"maxAbsEffect": 0.10, "twoSidedRandomizationPMustBeAtLeast": 0.05},
    "contention": {"otherCoresP90Above": 2.0, "minBlocksForSensitivity": 4,
                   "what": "a run is shared when the other jobs on the Mac used more than 2 cores at the 90th percentile of the samples taken during it; its whole block is then shared. Every gate is evaluated on all blocks AND, when 4 or more blocks are not shared, on those alone; both must pass."},
    "reproducibility": "every rule above holds in session 1 AND in session 2, which runs later, in its own invocation, on the clips of session 1 and the held-out clips",
    "promotion": {"minSession1Reduction": 0.15, "requiresImmutability": True},
    "default": "unchanged unless every gate passes; the feature flag stays off otherwise",
}


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_text(cmd: list[str], timeout: float = 30) -> str | None:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def git(*args: str) -> str:
    return run_text(["git", "-C", str(REPO), *args]) or ""


def hardware() -> dict:
    def sysctl(key: str) -> str:
        return run_text(["sysctl", "-n", key]) or ""
    return {"model": sysctl("hw.model"), "chip": sysctl("machdep.cpu.brand_string"),
            "cores": int(sysctl("hw.ncpu") or 0),
            "memoryGB": round(int(sysctl("hw.memsize") or 0) / 2**30), "os": platform.mac_ver()[0]}


def pcm_from(path: Path, *, start_s: float | None = None, duration_s: float | None = None) -> bytes:
    """16 kHz mono s16le samples of any audio file, through ffmpeg (a trusted binary reading
    untrusted data; the samples are the only thing taken from the file)."""
    cmd = ["ffmpeg", "-v", "error"]
    if start_s is not None:
        cmd += ["-ss", f"{start_s:.3f}"]
    cmd += ["-i", str(path)]
    if duration_s is not None:
        cmd += ["-t", f"{duration_s:.3f}"]
    cmd += ["-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"]
    out = subprocess.run(cmd, capture_output=True)
    if out.returncode != 0:
        raise SystemExit(f"ffmpeg failed on {path.name}: {out.stderr.decode(errors='replace')[:200]}")
    return out.stdout


def write_wav(path: Path, pcm: bytes) -> None:
    """Write 16 kHz mono s16 WAV, unless the file already holds exactly these samples: a plan
    may be reading the clip, and re-preparing must not touch it."""
    import wave
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        with wave.open(str(path), "rb") as existing:
            if existing.readframes(existing.getnframes()) == pcm:
                return
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def rng_for(*parts) -> random.Random:
    return random.Random("-".join(str(p) for p in (SEED, *parts)))


# --------------------------------------------------------------------------
# prepare: the clips
# --------------------------------------------------------------------------

def parse_rttm(path: Path) -> list[tuple[int, int]]:
    """Every speaker segment of an RTTM file in ms, in order, NOT merged: a turn that is dropped
    beside one that is kept must be seen. Merge before asking where speech is."""
    spans = []
    for line in path.read_text().splitlines():
        fields = line.split()
        if len(fields) >= 5 and fields[0] == "SPEAKER":
            start, duration = float(fields[3]), float(fields[4])
            spans.append((round(start * 1000), round((start + duration) * 1000)))
    return sorted(spans)


def densest_window(weights: list[tuple[int, int]], total_ms: int, window_ms: int, *,
                   earliest_ms: int, step_ms: int = 30_000) -> int:
    """Start (a multiple of `step_ms`, not before `earliest_ms`) of the window holding the
    most reference speech. A rule on the reference alone, written before any decode, so the
    choice of excerpt cannot depend on how the model did."""
    best, best_start = -1, earliest_ms
    start = earliest_ms
    while start + window_ms <= total_ms:
        covered = sum(max(0, min(e, start + window_ms) - max(s, start)) for s, e in weights)
        if covered > best:
            best, best_start = covered, start
        start += step_ms
    return best_start


def clip_entry(cid: str, corpus: str, kind: str, language: str, wav: Path, work: Path, *,
               ref_text: str | None, spans: list[tuple[int, int]], source: dict) -> dict:
    duration_ms = (wav.stat().st_size - 44) * 1000 // (SAMPLE_RATE * 2)
    ref_path = None
    if ref_text is not None:
        ref_path = work / "refs" / f"{cid}.txt"
        ref_path.parent.mkdir(parents=True, exist_ok=True)
        ref_path.write_text(ref_text)
    span_path = work / "refs" / f"{cid}.spans.json"
    span_path.parent.mkdir(parents=True, exist_ok=True)
    span_path.write_text(json.dumps(spans))
    return {"id": cid, "corpus": corpus, "kind": kind, "language": language, "wav": str(wav),
            "wavSha256": sha256_of(wav), "durationMs": duration_ms,
            "refText": str(ref_path) if ref_path else None,
            "refWords": len(normalize(ref_text)) if ref_text is not None else None,
            "refSpans": str(span_path), "refSpanCount": len(spans),
            "refSpansSha256": hashlib.sha256(json.dumps(spans).encode()).hexdigest(),
            "source": source}


def cmd_prepare(args) -> int:
    work: Path = args.work
    clips_dir = work / "clips"
    entries: list[dict] = []

    # FLEURS read Tagalog: the long-form files that eval/fleurs_eval.py constructed (consecutive
    # sentences, seeded 0.3-1.5 s gaps of digital silence), cut at a part boundary.
    fleurs_manifest = json.loads((args.fleurs / "manifest.json").read_text())
    parts_by_lf: dict[str, list[dict]] = {}
    for part in fleurs_manifest["sets"]["parts"]:
        parts_by_lf.setdefault(part["longform"], []).append(part)
    for lf, cid in (("lf1", "fleurs-lf1"), ("lf2", "fleurs-lf2")):
        parts = sorted(parts_by_lf[lf], key=lambda p: p["start_s"])
        kept = [p for p in parts if p["end_s"] <= args.fleurs_max_s] or parts[:1]
        end_s = kept[-1]["end_s"]
        wav = clips_dir / f"{cid}.wav"
        write_wav(wav, pcm_from(Path(next(l for l in fleurs_manifest["sets"]["longform"] if l["id"] == lf)["wav"]),
                                duration_s=end_s))
        entries.append(clip_entry(
            cid, "fleurs", "read Tagalog, constructed long-form", "tl", wav, work,
            ref_text="\n".join(p["ref"] for p in kept),
            spans=[(round(p["start_s"] * 1000), round(p["end_s"] * 1000)) for p in kept],
            source={"dataset": "FLEURS fil_ph test", "licence": "CC BY 4.0", "sentences": [p["sent_id"] for p in kept],
                    "cutAtS": round(end_s, 2)}))

    # Liva AI en-tl: the densest window of reference speech, after the first minute.
    liva_manifest = json.loads((args.liva / "manifest.json").read_text())
    liva_items = sorted(liva_manifest["items"], key=lambda i: i["id"])
    order = list(liva_items)
    rng_for("liva-files").shuffle(order)
    for label, item, window_s in (("liva-a", order[0], args.clip_s), ("liva-b", order[1], args.clip_s),
                                  ("pilot-liva", order[2], args.pilot_s)):
        ref = json.loads((args.liva / item["ref"]).read_text())
        utterances = sorted(ref["utterances"], key=lambda u: u["startMs"])
        wav_src = args.liva / item["audio"]
        total_ms = int(float(run_text(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                       "-of", "csv=p=0", str(wav_src)]) or 0) * 1000)
        window_ms = window_s * 1000
        weights = ll.merge_spans((u["startMs"], u["endMs"]) for u in utterances)
        start_ms = densest_window(weights, total_ms, window_ms, earliest_ms=60_000)
        picked = [u for u in utterances if start_ms <= (u["startMs"] + u["endMs"]) // 2 < start_ms + window_ms]
        wav = clips_dir / f"{label}.wav"
        write_wav(wav, pcm_from(wav_src, start_s=start_ms / 1000, duration_s=window_s))
        entries.append(clip_entry(
            label, "liva", "conversational Taglish, 4-5 friends in a voice chat", "tl", wav, work,
            ref_text="\n".join(u["text"] for u in picked),
            spans=[(max(0, u["startMs"] - start_ms), min(window_ms, u["endMs"] - start_ms)) for u in picked],
            source={"dataset": "Liva AI en-tl (code-switching-asr, rev 51b5d0b)", "licence": "CC BY 4.0",
                    "file": item["id"], "startMs": start_ms, "windowMs": window_ms,
                    "utterances": len(picked)}))

    # AMI English meetings: two series chosen by seed, the densest window of speech after two minutes.
    ami_manifest = json.loads((args.ami / "manifest.json").read_text())
    by_series: dict[str, list[dict]] = {}
    for item in ami_manifest["items"]:
        by_series.setdefault(item["id"].removeprefix("ami-")[:-1], []).append(item)
    series = sorted(by_series)
    rng_for("ami-series").shuffle(series)
    for label, name, window_s in (("ami-a", series[0], args.clip_s), ("ami-b", series[1], args.clip_s),
                                  ("pilot-ami", series[2], args.pilot_s)):
        pool = sorted(by_series[name], key=lambda i: i["id"])
        rng_for("ami-meeting", name).shuffle(pool)
        item = pool[0]
        spans = parse_rttm(args.ami / item["ref"])
        window_ms = window_s * 1000
        start_ms = densest_window(ll.merge_spans(spans), int(item["durationS"] * 1000), window_ms, earliest_ms=120_000)
        wav = clips_dir / f"{label}.wav"
        write_wav(wav, pcm_from(args.ami / item["audio"], start_s=start_ms / 1000, duration_s=window_s))
        inside = [(max(0, s - start_ms), min(window_ms, e - start_ms)) for s, e in spans
                  if e > start_ms and s < start_ms + window_ms]
        entries.append(clip_entry(
            label, "ami", "English meeting, headset mix (speech activity reference only)", "en", wav, work,
            ref_text=None, spans=inside,
            source={"dataset": "AMI Meeting Corpus, test set, Mix-Headset", "licence": "CC BY 4.0",
                    "meeting": item["id"], "startMs": start_ms, "windowMs": window_ms}))

    manifest = {"schema": SCHEMA, "seed": SEED, "created": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                "clips": entries}
    work.mkdir(parents=True, exist_ok=True)
    (work / "clips.json").write_text(json.dumps(manifest, indent=2))

    # What goes into git: which excerpt of which public recording, its hash and size. No audio, no words.
    fixture = {"schema": SCHEMA, "seed": SEED,
               "note": "Descriptions of the clips cut from public corpora by eval/live_latency.py prepare. No audio and no transcript text; the sources are CC BY 4.0 and stay in the work folders outside the repository.",
               "clips": [{k: c[k] for k in ("id", "corpus", "kind", "language", "durationMs", "wavSha256",
                                            "refWords", "refSpanCount", "refSpansSha256", "source")}
                         for c in entries]}
    CLIP_FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    CLIP_FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n")
    for c in entries:
        print(f"  {c['id']:11s} {c['durationMs'] / 1000:6.1f} s  ref words {c['refWords']}  speech spans {c['refSpanCount']}  {c['wavSha256'][:12]}")
    print(f"wrote {work / 'clips.json'} and {CLIP_FIXTURE}")
    return 0


# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------

def make_schedule(session: int, clips: list[str], arms: list[str], rounds: int) -> list[dict]:
    """Rounds outermost; inside a round the clips in a seeded order; inside a block the arms in
    a seeded order. The position of each arm in its block is recorded."""
    order: list[dict] = []
    for r in range(1, rounds + 1):
        clip_order = list(clips)
        rng_for("s", session, "clips", r).shuffle(clip_order)
        for clip in clip_order:
            arm_order = list(arms)
            rng_for("s", session, "arms", r, clip).shuffle(arm_order)
            for position, arm in enumerate(arm_order, start=1):
                order.append({"round": r, "clip": clip, "arm": arm, "position": position})
    return order


def cmd_plan(args) -> int:
    clips_manifest = json.loads((args.work / "clips.json").read_text())
    by_id = {c["id"]: c for c in clips_manifest["clips"]}
    clip_ids = args.clips.split(",")
    arm_ids = args.arms.split(",")
    for cid in clip_ids:
        if cid not in by_id:
            raise SystemExit(f"unknown clip {cid}")
    for aid in arm_ids:
        if aid not in ARMS:
            raise SystemExit(f"unknown arm {aid}")
    if not all(c in arm_ids for c in CONTROLS):
        raise SystemExit("both controls (C0, C1) must be in every session")
    binary = args.bin.resolve()
    scratch_bin = args.work / "bin" / "transcribe"
    scratch_bin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, scratch_bin)
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    plan = {
        "schema": SCHEMA,
        "session": args.session,
        "name": args.name,
        "created": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "commit": git("rev-parse", "HEAD"),
        "dirty": bool(git("status", "--porcelain")),
        "hardware": hardware(),
        "binary": {"path": str(scratch_bin), "sha256": sha256_of(scratch_bin), "builtFrom": str(binary)},
        "tier": "balanced",
        "wrap": WRAP,
        "base": ["--no-diarize", "--live", "--realtime", "--live-trace"],
        "seed": SEED,
        "rounds": args.rounds,
        "arms": {a: {**ARMS[a]} for a in arm_ids},
        "controls": list(CONTROLS),
        "variants": [a for a in arm_ids if a not in CONTROLS],
        "clips": [{k: by_id[c][k] for k in ("id", "corpus", "kind", "language", "wav", "wavSha256", "durationMs",
                                           "refText", "refWords", "refSpans", "refSpansSha256", "source")}
                  for c in clip_ids],
        "order": make_schedule(args.session, clip_ids, arm_ids, args.rounds),
        "gate": DEFAULT_GATE,
        "statistics": {"seed": SEED, "randomizationResamples": DEFAULT_GATE["latency"]["randomizationResamples"],
                       "unit": "the block (one clip in one round); words are never resampled",
                       "controlForVariants": "the mean (or the pool, for latency) of C0 and C1 in the same block",
                       "aa": "C0 against C1, the same statistics, two-sided",
                       "whyNotABootstrap": "a bootstrap over 3 to 4 rounds per clip was simulated before the first run: its 95% intervals covered a true null 80% of the time. The randomization test has exact size; the t-interval covered 91-92%.",
                       "whyNotAPooledMedian": "the pilot (not evidence) showed C0 at 3.9 s and C1 at 6.9 s pooled over a 3 s clip and a 17 s clip: a bimodal pool has a median in the gap"},
        "notes": args.note or [],
    }
    path = out / f"plan-session-{args.session}.json"
    if path.exists() and not args.force:
        raise SystemExit(f"{path} exists: a plan is written once, before any run (--force to replace)")
    path.write_text(json.dumps(plan, indent=2))
    plan["planSha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"wrote {path} ({len(plan['order'])} runs, sha256 {plan['planSha256'][:12]})")
    seconds = sum(by_id[o["clip"]]["durationMs"] for o in plan["order"]) / 1000
    print(f"audio to replay in real time: {seconds / 60:.0f} min over {len(plan['order'])} runs")
    return 0


# --------------------------------------------------------------------------
# run
# --------------------------------------------------------------------------

def descendants(pid: int) -> list[tuple[int, str]]:
    out = run_text(["ps", "-A", "-o", "pid=,ppid=,comm="]) or ""
    table: dict[int, list[tuple[int, str]]] = {}
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            table.setdefault(int(parts[1]), []).append((int(parts[0]), parts[2]))
    found: list[tuple[int, str]] = []
    stack = [pid]
    while stack:
        for child, comm in table.get(stack.pop(), []):
            found.append((child, comm))
            stack.append(child)
    return found


def machine_busy_percent() -> float | None:
    """Whole-machine CPU use (user + system, percent of all cores) over one second, from
    `top`. The second of its two samples is the instantaneous one."""
    out = run_text(["top", "-l", "2", "-n", "0", "-s", "1"], timeout=20) or ""
    lines = [l for l in out.splitlines() if l.startswith("CPU usage:")]
    if not lines:
        return None
    try:
        parts = lines[-1].removeprefix("CPU usage:").split(",")
        return float(parts[0].split("%")[0]) + float(parts[1].split("%")[0])
    except (ValueError, IndexError):
        return None


class LoadSampler(threading.Thread):
    """While the replay itself runs (not while it waits for the lock), sample how busy the
    whole machine is. What the replay used is known from its own CPU time; the rest is the
    other jobs on this Mac, which the lock does not stop."""

    def __init__(self, proc_pid: int, interval_s: float = 60.0):
        super().__init__(daemon=True)
        self.pid = proc_pid
        self.interval = interval_s
        self.samples: list[float] = []
        self.started_running: float | None = None
        self._halt = threading.Event()

    def run(self) -> None:
        last_sample = -1e9
        while not self._halt.is_set():
            running = any(comm.endswith("transcribe") for _, comm in descendants(self.pid))
            if running:
                if self.started_running is None:
                    self.started_running = time.monotonic()
                if time.monotonic() - last_sample >= self.interval:
                    last_sample = time.monotonic()
                    busy = machine_busy_percent()
                    if busy is not None:
                        self.samples.append(busy)
            self._halt.wait(1.0)

    def stop(self) -> None:
        self._halt.set()


def run_id(entry: dict) -> str:
    return f"r{entry['round']}-{entry['clip']}-{entry['arm']}"


def execute(plan: dict, entry: dict, runs_dir: Path, timeout_s: float) -> dict:
    clip = next(c for c in plan["clips"] if c["id"] == entry["clip"])
    rid = run_id(entry)
    report_path = runs_dir / f"{rid}.report.json"
    stderr_path = runs_dir / f"{rid}.stderr.txt"
    attempt = entry.get("attempt", 1)
    if attempt > 1:
        stderr_path = runs_dir / f"{rid}.attempt{attempt}.stderr.txt"
    cmd = [*plan["wrap"], plan["binary"]["path"], "--audio", clip["wav"], "--language", clip["language"],
           "--tier", plan["tier"], *plan["base"], *plan["arms"][entry["arm"]]["flags"], "--json", str(report_path)]
    record: dict = {"id": rid, **entry, "cmd": cmd, "planSha256": plan["planSha256"],
                    "startedUtc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                    "loadavgAtLaunch": round(os.getloadavg()[0], 2)}
    began = time.monotonic()
    with stderr_path.open("w") as stderr_file:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=stderr_file, start_new_session=True)
        return _supervise(proc, record, report_path, began, timeout_s)


def _supervise(proc, record: dict, report_path: Path, began: float, timeout_s: float) -> dict:
    sampler = LoadSampler(proc.pid)
    sampler.start()
    try:
        proc.wait(timeout=timeout_s)
        record["returncode"] = proc.returncode
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        record["returncode"] = None
        record["error"] = f"timed out after {timeout_s:.0f} s"
    sampler.stop()
    record["wallSecondsWithLockWait"] = round(time.monotonic() - began, 1)
    record["lockWaitSeconds"] = (round(sampler.started_running - began, 1)
                                 if sampler.started_running is not None else None)
    record["machineBusyPercent"] = sampler.samples
    record["loadavgAtEnd"] = round(os.getloadavg()[0], 2)
    ok = record.get("returncode") == 0 and report_path.exists()
    record["ok"] = ok
    if not ok and "error" not in record:
        record["error"] = f"exit code {record.get('returncode')}" if record.get("returncode") != 0 else "no report written"
    return record


def cmd_run(args) -> int:
    plan_path = args.plan
    plan = json.loads(plan_path.read_text())
    plan["planSha256"] = hashlib.sha256(plan_path.read_bytes()).hexdigest()
    if sha256_of(Path(plan["binary"]["path"])) != plan["binary"]["sha256"]:
        raise SystemExit("the binary changed since the plan was written")
    for clip in plan["clips"]:
        if sha256_of(Path(clip["wav"])) != clip["wavSha256"]:
            raise SystemExit(f"clip {clip['id']} changed since the plan was written")
    runs_dir = args.work / "runs" / f"session-{plan['session']}"
    runs_dir.mkdir(parents=True, exist_ok=True)
    todo = [e for e in plan["order"] if not (runs_dir / f"{run_id(e)}.run.json").exists()
            or not json.loads((runs_dir / f"{run_id(e)}.run.json").read_text()).get("ok")]
    if args.limit:
        todo = todo[:args.limit]
    print(f"session {plan['session']}: {len(plan['order']) - len(todo)} done, {len(todo)} to run")
    for index, entry in enumerate(todo, start=1):
        clip = next(c for c in plan["clips"] if c["id"] == entry["clip"])
        attempts = 0
        while True:
            attempts += 1
            record = execute(plan, {**entry, "attempt": attempts}, runs_dir,
                             timeout_s=clip["durationMs"] / 1000 * 3 + args.lock_budget_s)
            record["attempt"] = attempts
            (runs_dir / f"{run_id(entry)}.run.json").write_text(json.dumps(record, indent=2))
            print(f"[{index}/{len(todo)}] {run_id(entry)} {'ok' if record['ok'] else 'FAILED ' + record.get('error', '')}"
                  f" ({record['wallSecondsWithLockWait']:.0f} s, lock wait {record['lockWaitSeconds']} s)", flush=True)
            if record["ok"] or attempts >= 2:
                break
    return 0


# --------------------------------------------------------------------------
# score
# --------------------------------------------------------------------------

def load_clip_reference(clip: dict) -> tuple[list[str] | None, list[list[int]]]:
    ref_words = normalize(Path(clip["refText"]).read_text()) if clip.get("refText") else None
    spans = json.loads(Path(clip["refSpans"]).read_text())
    return ref_words, spans


def cmd_score(args) -> int:
    plan = json.loads(args.plan.read_text())
    runs_dir = args.work / "runs" / f"session-{plan['session']}"
    references = {c["id"]: load_clip_reference(c) for c in plan["clips"]}
    clip_by_id = {c["id"]: c for c in plan["clips"]}
    records = []
    for entry in plan["order"]:
        run_path = runs_dir / f"{run_id(entry)}.run.json"
        record = {**entry, "id": run_id(entry), "ok": False}
        if run_path.exists():
            run = json.loads(run_path.read_text())
            record.update({k: run.get(k) for k in ("returncode", "attempt", "error", "wallSecondsWithLockWait",
                                                  "lockWaitSeconds", "loadavgAtLaunch", "loadavgAtEnd",
                                                  "machineBusyPercent", "startedUtc")})
            if run.get("ok"):
                report = json.loads((runs_dir / f"{run_id(entry)}.report.json").read_text())
                words, spans = references[entry["clip"]]
                record["metrics"] = ll.run_metrics(report, clip_by_id[entry["clip"]], ref_words=words, ref_spans=spans)
                record["ok"] = True
                record["model"] = report.get("model")
                record["liveConfig"] = report.get("config")
        records.append(record)
    out = {"schema": SCHEMA, "session": plan["session"], "planSha256": hashlib.sha256(args.plan.read_bytes()).hexdigest(),
           "note": "numbers only: no audio, no words. Per-word latencies are integers in ms; `reason` indexes live_latency_lib.REASONS.",
           "runs": records}
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / f"results-session-{plan['session']}.json"
    path.write_text(json.dumps(out, separators=(",", ":")))
    done = sum(1 for r in records if r["ok"])
    print(f"scored {done}/{len(records)} runs -> {path} ({path.stat().st_size // 1024} KB)")
    return 0


# --------------------------------------------------------------------------
# analyze
# --------------------------------------------------------------------------

def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def blocks_of(plan: dict, results: dict) -> tuple[dict, list[dict]]:
    """Complete blocks only: every arm of the block ran and scored. Returns the blocks, keyed
    (clip, round) -> arm -> run, and the list of excluded (incomplete) blocks."""
    arms = list(plan["arms"])
    by_block: dict[tuple[str, int], dict[str, dict]] = {}
    for run in results["runs"]:
        if run["ok"]:
            by_block.setdefault((run["clip"], run["round"]), {})[run["arm"]] = run
    complete, excluded = {}, []
    for clip in plan["clips"]:
        for r in range(1, plan["rounds"] + 1):
            block = by_block.get((clip["id"], r), {})
            if all(a in block for a in arms):
                complete[(clip["id"], r)] = block
            else:
                excluded.append({"clip": clip["id"], "round": r, "missing": [a for a in arms if a not in block]})
    return complete, excluded


def run_contention(run: dict, cores: int) -> float | None:
    """The 90th percentile of the cores that OTHER jobs used while this replay ran: the
    whole machine's busy share, in cores, minus what the replay itself used on average."""
    samples = run.get("machineBusyPercent") or []
    if not run.get("ok") or not samples:
        return None
    own = run["metrics"]["cpu_s_per_audio_min"] / 60
    return ll.quantile([max(0.0, s / 100 * cores - own) for s in samples], 0.9)


def contended_blocks(blocks: dict, cores: int, limit: float) -> set:
    bad = set()
    for key, block in blocks.items():
        for run in block.values():
            c = run_contention(run, cores)
            if c is not None and c > limit:
                bad.add(key)
    return bad


def block_words(blocks: dict, arms: list[str], clip_ids: set[str] | None = None,
                key: str = "latency_wall_ms") -> list[list[list[int]]]:
    """For each complete block, the word latencies of each named arm's run, in the order given."""
    return [[block[a]["metrics"][key] for a in arms]
            for (clip, _), block in sorted(blocks.items()) if clip_ids is None or clip in clip_ids]


def block_values(blocks: dict, arms: list[str], key: str, clip_ids: set[str] | None = None) -> list[list]:
    return [[block[a]["metrics"][key] for a in arms]
            for (clip, _), block in sorted(blocks.items()) if clip_ids is None or clip in clip_ids]


def per_clip_effects(blocks: dict, arms3: list[str], clip_ids: list[str], key: str = "latency_wall_ms") -> dict:
    """The reduction of each clip's median commit latency, as the geometric mean over its rounds."""
    out = {}
    for clip in clip_ids:
        rows = block_words(blocks, arms3, {clip}, key)
        if not rows:
            continue
        medians = [ll.run_quantiles(r, 0.5) for r in rows]
        logs = [x for x in (ll.log_ratio(m, 2) for m in medians) if x is not None]
        have = [m for m in medians if all(v is not None for v in m)]
        out[clip] = {"median_control_ms": mean([v for m in have for v in m[:2]]),
                     "median_variant_ms": mean([m[2] for m in have]),
                     "effect": ll.reduction(logs), "rounds": len(rows),
                     "per_round": [1 - math.exp(x) for x in logs]}
    return out


def aa_per_clip(blocks: dict, clip_ids: list[str]) -> dict:
    out = {}
    for clip in clip_ids:
        rows = block_words(blocks, ["C0", "C1"], {clip})
        logs = [x for x in (ll.log_ratio(ll.run_quantiles(r, 0.5), 1) for r in rows) if x is not None]
        if rows:
            out[clip] = {"effect": ll.reduction(logs), "rounds": len(rows)}
    return out


def pooled(blocks: dict, arm: str, key: str, clips: set[str] | None = None):
    return [x for (clip, _), b in blocks.items() if clips is None or clip in clips for x in b[arm]["metrics"][key]]


def evaluate_variant(plan: dict, blocks: dict, v: str, session_facts: dict) -> dict:
    """Every measurement and gate for one variant over the given blocks. `session_facts` holds
    what is a property of the whole session (failed runs, invariant checks over every arm)."""
    g = plan["gate"]
    seed = plan["seed"]
    n_resamples = g["latency"]["randomizationResamples"]
    clip_ids = [c["id"] for c in plan["clips"]]
    corpus_of = {c["id"]: c["corpus"] for c in plan["clips"]}
    text_clips = {c["id"] for c in plan["clips"] if c["refWords"]}
    arms3 = ["C0", "C1", v]

    # Latency.
    words = block_words(blocks, arms3)
    test = ll.randomization_test(words, 2, quantiles=(0.5, 0.9, 0.95), resamples=n_resamples, seed=seed)
    interval = {q: ll.block_reduction_interval(words, 2, q) for q in (0.5, 0.9, 0.95)}
    latency = {name: {"reduction": test[q]["reduction"], "p": test[q]["p"], "interval": interval[q]}
               for name, q in (("median", 0.5), ("p90", 0.9), ("p95", 0.95))}
    audio_words = block_words(blocks, arms3, key="latency_audio_ms")
    audio_test = ll.randomization_test(audio_words, 2, resamples=max(1000, n_resamples // 5), seed=seed)[0.5]
    segments = block_words(blocks, arms3, key="segment_latency_ms")
    seg_test = ll.randomization_test(segments, 2, resamples=max(1000, n_resamples // 5), seed=seed)[0.5]
    per_clip = per_clip_effects(blocks, arms3, clip_ids)
    per_corpus = {}
    for corpus in sorted(set(corpus_of.values())):
        ids = {c for c in clip_ids if corpus_of[c] == corpus}
        sub = block_words(blocks, arms3, ids)
        if sub:
            t = ll.randomization_test(sub, 2, resamples=max(1000, n_resamples // 5), seed=seed)[0.5]
            per_corpus[corpus] = {"reduction": t["reduction"], "p": t["p"], "blocks": len(sub),
                                  "interval": ll.block_reduction_interval(sub, 2, 0.5)}

    # Paired safety metrics: variant minus the mean of the controls, by block.
    def paired(key, clips=None, scale=100.0):
        rows = block_values(blocks, arms3, key, clips)
        t = ll.randomization_mean_delta(rows, 2, alternative="greater", resamples=n_resamples, seed=seed)
        deltas = [(r[2] - (r[0] + r[1]) / 2) * scale for r in rows if all(x is not None for x in r)]
        return {"mean_delta": None if t["mean_delta"] is None else t["mean_delta"] * scale, "p": t["p"],
                "blocks": t["blocks"], "interval": ll.t_mean_ci(deltas)}

    wer, deletion = paired("wer", text_clips), paired("deletion_rate", text_clips)
    missing, omitted = paired("missing_speech_share"), paired("omitted_segment_share")
    wer_by_clip = {c: paired("wer", {c}) for c in sorted(text_clips)}
    p_adj = ll.holm([wer["p"], deletion["p"], missing["p"], omitted["p"]])

    def total(arm, key):
        return sum((b[arm]["metrics"][key] or 0) for b in blocks.values())

    def control_mean(key):
        return (total("C0", key) + total("C1", key)) / 2

    attempts_c = total("C0", "attempts") + total("C1", "attempts")
    rate_c = (total("C0", "dropped_hops") + total("C1", "dropped_hops")) / attempts_c if attempts_c else 0.0
    rate_v = total(v, "dropped_hops") / total(v, "attempts") if total(v, "attempts") else 0.0

    med, p90, p95 = latency["median"], latency["p90"], latency["p95"]
    lower = (med["interval"] or {}).get("lower95_one_sided")
    lg = g["latency"]
    clip_worst = min((x["effect"] for x in per_clip.values() if x["effect"] is not None), default=None)
    gates = {
        "latency": {
            "median_reduction": med["reduction"], "p": med["p"], "lower95_one_sided": lower,
            "p90_reduction": p90["reduction"], "p95_reduction": p95["reduction"],
            "worst_clip_reduction": clip_worst, "segment_anchor_reduction": seg_test["reduction"],
            "pass": bool(med["reduction"] is not None and med["reduction"] >= lg["minRelativeReduction"]
                         and med["p"] is not None and med["p"] < lg["supportAlpha"]
                         and lower is not None and lower > 0
                         and p90["reduction"] is not None and p90["reduction"] >= lg["tailGuard"]["minReduction"]
                         and p95["reduction"] is not None and p95["reduction"] >= lg["tailGuard"]["minReduction"]
                         and clip_worst is not None and clip_worst >= lg["perClipGuard"]["minReduction"]
                         and seg_test["reduction"] is not None
                         and seg_test["reduction"] >= lg["referenceAnchor"]["minReduction"])},
        "wer": {
            "mean_delta_pt": wer["mean_delta"], "p": wer["p"], "holm_p": p_adj[0],
            "clip_mean_delta_pt": {c: x["mean_delta"] for c, x in wer_by_clip.items()},
            "pass": bool(wer["mean_delta"] is not None
                         and wer["mean_delta"] <= g["wer"]["maxMeanIncreasePt"]
                         and (p_adj[0] if p_adj[0] is not None else 0) >= g["wer"]["supportedRegressionAlpha"]
                         and all(x["mean_delta"] is None or x["mean_delta"] <= g["wer"]["maxClipMeanIncreasePt"]
                                 for x in wer_by_clip.values()))},
        "missingSpeech": {
            "deletion_rate_delta_pt": deletion["mean_delta"], "deletion_holm_p": p_adj[1],
            "missing_share_delta_pt": missing["mean_delta"], "missing_holm_p": p_adj[2],
            "omitted_segments_delta_pt": omitted["mean_delta"], "omitted_holm_p": p_adj[3],
            "pass": bool(deletion["mean_delta"] is not None and missing["mean_delta"] is not None
                         and omitted["mean_delta"] is not None
                         and deletion["mean_delta"] <= g["missingSpeech"]["maxDeletionRateIncreasePt"]
                         and missing["mean_delta"] <= g["missingSpeech"]["maxMissingShareIncreasePt"]
                         and omitted["mean_delta"] <= g["missingSpeech"]["maxOmittedSegmentsIncreasePt"]
                         and all((p if p is not None else 0) >= g["missingSpeech"]["alpha"] for p in p_adj[1:]))},
        "hallucinations": {
            "critical_variant": total(v, "hallucinations_critical"),
            "critical_control_mean": control_mean("hallucinations_critical"),
            "ghost_words_variant": total(v, "ghost_words"), "ghost_words_control_mean": control_mean("ghost_words"),
            "pass": bool(total(v, "hallucinations_critical") <= control_mean("hallucinations_critical")
                         and total(v, "ghost_words") <= control_mean("ghost_words"))},
        "immutability": {
            "violations_all_arms": session_facts["violations_all_arms"],
            "runs_with_unmatched_words": session_facts["unmatched_runs"],
            "pass": bool(session_facts["violations_all_arms"] <= g["immutability"]["maxViolations"]
                         and not session_facts["unmatched_runs"])},
        "droppedHops": {
            "variant_rate": rate_v, "control_rate": rate_c,
            "pass": bool(rate_v <= max(rate_c * (1 + g["droppedHops"]["maxRelativeIncrease"]),
                                       rate_c + g["droppedHops"]["orAbsolutePp"] / 100))},
        "failures": {
            "failed_runs": session_facts["failed_runs"],
            "failed_hops_variant": total(v, "failed_hops"), "failed_hops_control_mean": control_mean("failed_hops"),
            "pass": bool(session_facts["failed_runs"] <= g["failures"]["maxFailedRuns"]
                         and total(v, "failed_hops") <= control_mean("failed_hops") + g["failures"]["maxFailedDecodesIncrease"])},
    }
    gates["all_pass"] = all(x["pass"] for x in gates.values())

    secondary = {
        "forced_commits": paired("forced_commits", scale=1.0), "empty_hypotheses": paired("empty_hypotheses", scale=1.0),
        "dropped_hops": paired("dropped_hops", scale=1.0), "repeat_excess": paired("repeat_excess", text_clips, 1.0),
        "ghost_words": paired("ghost_words", scale=1.0), "cpu_s_per_audio_min": paired("cpu_s_per_audio_min", scale=1.0),
        "infer_rtf": paired("infer_rtf", scale=1.0), "decodes_per_min": paired("decodes_per_min", scale=1.0),
        "mean_window_ms": paired("mean_window_ms", scale=1.0),
        "finalization_latency_median_ms": {
            "variant": (ll.latency_summary(pooled(blocks, v, "finalization_latency_ms")) or {}).get("median"),
            "controls": (ll.latency_summary(pooled(blocks, "C0", "finalization_latency_ms")
                                            + pooled(blocks, "C1", "finalization_latency_ms")) or {}).get("median")}}
    return {"blocks": len(blocks), "latency": latency, "latency_audio_median": {
                "reduction": audio_test["reduction"], "p": audio_test["p"]},
            "segment_anchor": {"reduction": seg_test["reduction"], "p": seg_test["p"]},
            "per_clip": per_clip, "per_corpus": per_corpus,
            "clips_faster": sum(1 for x in per_clip.values() if (x["effect"] or 0) > 0), "clips": len(per_clip),
            "wer": wer, "deletion": deletion, "missing": missing, "omitted": omitted,
            "secondary": secondary, "gates": gates}


def analyze_session(plan: dict, results: dict) -> dict:
    gate = plan["gate"]
    blocks, excluded = blocks_of(plan, results)
    clip_ids = [c["id"] for c in plan["clips"]]
    text_clips = {c["id"] for c in plan["clips"] if c["refWords"]}
    corpus_of = {c["id"]: c["corpus"] for c in plan["clips"]}
    seed = plan["seed"]
    n_resamples = gate["latency"]["randomizationResamples"]

    runs = results["runs"]
    failed = [r["id"] for r in runs if not r["ok"]]
    ok_runs = [r for r in runs if r["ok"]]
    facts = {"failed_runs": len(failed),
             "violations_all_arms": sum(r["metrics"]["invariant_violations"] for r in ok_runs),
             "unmatched_runs": [r["id"] for r in ok_runs
                                if not (r["metrics"]["tokens_match_commits"] and r["metrics"]["invariant_words_match"])]}
    violations = {}
    for r in ok_runs:
        violations[r["arm"]] = violations.get(r["arm"], 0) + r["metrics"]["invariant_violations"]

    # Machine state during the replays, and which blocks were shared with other jobs.
    cores = plan["hardware"].get("cores") or 1
    cg = gate["contention"]
    bad_blocks = contended_blocks(blocks, cores, cg["otherCoresP90Above"])
    busy = [x for r in ok_runs for x in (r.get("machineBusyPercent") or [])]
    own = [r["metrics"]["cpu_s_per_audio_min"] / 60 for r in ok_runs]
    waits = [r["lockWaitSeconds"] for r in ok_runs if r.get("lockWaitSeconds") is not None]
    loads = [r["loadavgAtLaunch"] for r in ok_runs if r.get("loadavgAtLaunch") is not None]
    load = {"machine_busy_cores_median": (ll.quantile(busy, 0.5) / 100 * cores) if busy else None,
            "machine_busy_cores_p90": (ll.quantile(busy, 0.9) / 100 * cores) if busy else None,
            "replay_own_cores_median": ll.quantile(own, 0.5) if own else None, "samples": len(busy), "cores": cores,
            "lock_wait_seconds_median": ll.quantile(waits, 0.5) if waits else None,
            "loadavg_at_launch_median": ll.quantile(loads, 0.5) if loads else None,
            "contended_blocks": sorted(f"{c}/r{r}" for c, r in bad_blocks),
            "run_other_cores_p90": {r["id"]: run_contention(r, cores) for r in ok_runs}}

    analysis: dict = {"session": plan["session"], "planSha256": results["planSha256"],
                      "blocks": len(blocks), "blocksPlanned": len(clip_ids) * plan["rounds"],
                      "excluded": excluded, "failedRuns": failed, "load": load,
                      "tokenCommitMismatch": facts["unmatched_runs"], "invariantViolationsByArm": violations}

    # Per-arm descriptives. The headline figures are the mean over runs of each run's own
    # median, p90 and p95: pooled over clips that differ by 5x, the median of all words sits in
    # the gap between two clusters and moves by seconds on a few words. Words pooled by CORPUS
    # are kept beside them.
    arms = list(plan["arms"])
    desc = {}

    def run_mean(arm_: str, key: str, q: float) -> float | None:
        return mean([ll.quantile(b[arm_]["metrics"][key], q) for b in blocks.values() if b[arm_]["metrics"][key]])

    for arm in arms:
        wall = pooled(blocks, arm, "latency_wall_ms")
        by_corpus = {}
        for corpus in sorted(set(corpus_of.values())):
            ids = {c for c in clip_ids if corpus_of[c] == corpus}
            by_corpus[corpus] = ll.latency_summary(pooled(blocks, arm, "latency_wall_ms", ids))
        reasons = [x for b in blocks.values() for x in b[arm]["metrics"]["reason"]]
        sums = lambda key: sum((b[arm]["metrics"][key] or 0) for b in blocks.values())  # noqa: E731
        attempts = sums("attempts")
        errs = {r: {"ok": 0, "sub": 0, "ins": 0} for r in ll.REASONS}
        for b in blocks.values():
            e = b[arm]["metrics"].get("errors_by_reason")
            if e:
                for r in ll.REASONS:
                    for op in ("ok", "sub", "ins"):
                        errs[r][op] += e[r][op]
        desc[arm] = {
            "runs": len(blocks), "words": len(wall),
            "latency_wall": {"median": run_mean(arm, "latency_wall_ms", 0.5), "p90": run_mean(arm, "latency_wall_ms", 0.9),
                             "p95": run_mean(arm, "latency_wall_ms", 0.95), "n": len(wall)},
            "latency_audio": {"median": run_mean(arm, "latency_audio_ms", 0.5), "p90": run_mean(arm, "latency_audio_ms", 0.9),
                              "p95": run_mean(arm, "latency_audio_ms", 0.95)},
            "latency_wall_by_corpus": by_corpus,
            "reason_share": {r: (reasons.count(i) / len(reasons) if reasons else None) for i, r in enumerate(ll.REASONS)},
            "dropped_hops": sums("dropped_hops"), "attempts": attempts,
            "dropped_rate": sums("dropped_hops") / attempts if attempts else None,
            "forced_commits": sums("forced_commits"), "empty_hypotheses": sums("empty_hypotheses"),
            "failed_hops": sums("failed_hops"), "head_skips": sums("head_skips"),
            "head_skipped_words": sums("head_skipped_words"), "boundaries": sums("boundaries"),
            "finalizations": sums("finalizations"), "finalizations_abandoned": sums("finalizations_abandoned"),
            "unagreed_tail_words": sums("unagreed_tail_words"),
            "hallucinations_critical": sums("hallucinations_critical"),
            "hallucination_fillers": sums("hallucination_fillers"), "hallucination_loops": sums("hallucination_loops"),
            "hallucination_invented_spans": sums("hallucination_invented_spans"),
            "hallucination_repeated_phrases": sums("hallucination_repeated_phrases"),
            "repeats": sums("repeats"), "ghost_words": sums("ghost_words"), "empty_words": sums("empty_words"),
            "finalization_latency": ll.latency_summary(pooled(blocks, arm, "finalization_latency_ms")),
            "segment_latency_median_ms": mean([(b[arm]["metrics"]["segment_latency"] or {}).get("median")
                                               for b in blocks.values()]),
            "cpu_s_per_audio_min": mean([b[arm]["metrics"]["cpu_s_per_audio_min"] for b in blocks.values()]),
            "infer_rtf": mean([b[arm]["metrics"]["infer_rtf"] for b in blocks.values()]),
            "decodes_per_min": mean([b[arm]["metrics"]["decodes_per_min"] for b in blocks.values()]),
            "mean_window_ms": mean([b[arm]["metrics"]["mean_window_ms"] for b in blocks.values()]),
            "decode_wall_median_ms": mean([b[arm]["metrics"]["decode_wall_median_ms"] for b in blocks.values()]),
            "replay_overrun_ms": mean([b[arm]["metrics"]["replay_overrun_ms"] for b in blocks.values()]),
            "wer_mean": mean([b[arm]["metrics"]["wer"] for (c, _), b in blocks.items() if c in text_clips]),
            "deletion_rate_mean": mean([b[arm]["metrics"]["deletion_rate"] for (c, _), b in blocks.items() if c in text_clips]),
            "missing_share_mean": mean([b[arm]["metrics"]["missing_speech_share"] for b in blocks.values()]),
            "omitted_segment_share_mean": mean([b[arm]["metrics"]["omitted_segment_share"] for b in blocks.values()]),
            "errors_by_reason": errs,
        }
    analysis["arms"] = desc

    # A/A: the control against itself, with the very statistics used for the variants.
    aa_words = block_words(blocks, ["C0", "C1"])
    aa_test = ll.randomization_test(aa_words, 1, quantiles=(0.5, 0.9, 0.95), resamples=n_resamples, seed=seed,
                                    two_sided=True)
    aa_int = {q: ll.block_reduction_interval(aa_words, 1, q) for q in (0.5, 0.9, 0.95)}
    aa_point = aa_test[0.5]["reduction"]
    aa_wer = [(r[1] - r[0]) * 100 for r in block_values(blocks, ["C0", "C1"], "wer", text_clips) if None not in r]
    analysis["aa"] = {
        "median": {"reduction": aa_point, "p_two_sided": aa_test[0.5]["p"], "interval": aa_int[0.5]},
        "p90": {"reduction": aa_test[0.9]["reduction"], "p_two_sided": aa_test[0.9]["p"], "interval": aa_int[0.9]},
        "p95": {"reduction": aa_test[0.95]["reduction"], "p_two_sided": aa_test[0.95]["p"], "interval": aa_int[0.95]},
        "per_clip": aa_per_clip(blocks, clip_ids),
        "valid": bool(aa_point is not None and abs(aa_point) <= gate["aa"]["maxAbsEffect"]
                      and aa_test[0.5]["p"] is not None
                      and aa_test[0.5]["p"] >= gate["aa"]["twoSidedRandomizationPMustBeAtLeast"]),
        "wer_delta_pt": ll.t_mean_ci(aa_wer),
        "block_median_ratio": [r[1] / r[0] for r in (ll.run_quantiles(b, 0.5) for b in aa_words) if None not in r and r[0]]}

    # Variants against the pooled controls, on every block and on the uncontended blocks alone.
    quiet = {k: b for k, b in blocks.items() if k not in bad_blocks}
    variants = {}
    for v in plan["variants"]:
        full = evaluate_variant(plan, blocks, v, facts)
        sensitivity = None
        if bad_blocks and len(quiet) >= cg["minBlocksForSensitivity"]:
            sensitivity = evaluate_variant(plan, quiet, v, facts)
        gates = dict(full["gates"])
        gates["session_valid"] = {"aa_valid": analysis["aa"]["valid"], "pass": analysis["aa"]["valid"]}
        gates["uncontended"] = {"contended_blocks": len(bad_blocks), "blocks_without": len(quiet),
                                "evaluated": sensitivity is not None,
                                "all_pass_without_contended_blocks": None if sensitivity is None else sensitivity["gates"]["all_pass"],
                                "pass": sensitivity is None or sensitivity["gates"]["all_pass"]}
        gates["all_pass"] = all(x["pass"] for k, x in gates.items() if k != "all_pass")
        variants[v] = {"variable": plan["arms"][v]["variable"], "what": plan["arms"][v]["what"],
                       "flags": plan["arms"][v]["flags"], **{k: x for k, x in full.items() if k != "gates"},
                       "gates": gates,
                       "uncontended": None if sensitivity is None else {
                           "median_reduction": sensitivity["latency"]["median"]["reduction"],
                           "p": sensitivity["latency"]["median"]["p"], "gates": sensitivity["gates"]}}
    analysis["variants"] = variants
    return analysis


def cmd_analyze(args) -> int:
    plan = json.loads(args.plan.read_text())
    results = json.loads((args.out / f"results-session-{plan['session']}.json").read_text())
    if results["planSha256"] != hashlib.sha256(args.plan.read_bytes()).hexdigest():
        raise SystemExit("the results were scored against a different plan")
    analysis = analyze_session(plan, results)
    path = args.out / f"analysis-session-{plan['session']}.json"
    path.write_text(json.dumps(analysis, indent=2))
    (args.out / f"report-session-{plan['session']}.md").write_text(render_session(plan, analysis))
    print(f"wrote {path}")
    print(render_session(plan, analysis))
    return 0


def pct(x, digits=1):
    return "n/a" if x is None else f"{x * 100:.{digits}f}%"


def ms(x):
    return "n/a" if x is None else f"{x:,.0f}"


def fnum(x, fmt="{:+.2f}"):
    return "n/a" if x is None else fmt.format(x)


def render_session(plan: dict, a: dict) -> str:
    L = []
    L.append(f"# Session {a['session']}: {plan.get('name', '')}")
    L.append("")
    L.append(f"Plan sha256 `{a['planSha256'][:16]}`, commit `{plan['commit'][:10]}`, binary `{plan['binary']['sha256'][:12]}`. "
             f"{a['blocks']} of {a['blocksPlanned']} blocks complete; {len(a['failedRuns'])} failed runs.")
    ld = a["load"]
    L.append("")
    if ld["machine_busy_cores_median"] is not None:
        L.append(f"Machine during the replays: median {ld['machine_busy_cores_median']:.1f} of {ld['cores']} cores busy in total "
                 f"(p90 {ld['machine_busy_cores_p90']:.1f}); the replay itself used a median {ld['replay_own_cores_median']:.2f} cores; "
                 f"lock wait median {ld['lock_wait_seconds_median']:.0f} s. "
                 f"Blocks shared with other jobs (other cores p90 above the plan's limit): {len(ld['contended_blocks'])} "
                 f"({', '.join(ld['contended_blocks']) or 'none'}).")
    else:
        L.append("Machine load was not sampled.")
    L.append("")
    L.append("## Commit latency by arm (mean over runs of each run's own quantile, wall clock, ms)")
    L.append("")
    L.append("| arm | words | median | p90 | p95 | audio-clock median | dropped hops | forced | empty | failed hops | critical halluc. | invariant breaks |")
    L.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for arm, d in a["arms"].items():
        w, au = d["latency_wall"], d["latency_audio"]
        L.append(f"| {arm} | {w['n']} | {ms(w['median'])} | {ms(w['p90'])} | {ms(w['p95'])} | {ms(au['median'])} | "
                 f"{d['dropped_hops']} ({pct(d['dropped_rate'])}) | {d['forced_commits']} | {d['empty_hypotheses']} | {d['failed_hops']} | "
                 f"{d['hallucinations_critical']} | {a['invariantViolationsByArm'].get(arm, 0)} |")
    L.append("")
    L.append("Median commit latency of the words pooled by corpus, per arm (ms):")
    L.append("")
    corpora = sorted({c for d in a["arms"].values() for c in d["latency_wall_by_corpus"]})
    L.append("| arm | " + " | ".join(corpora) + " | reference-anchored segment median |")
    L.append("| --- | " + " | ".join("---:" for _ in corpora) + " | ---: |")
    for arm, d in a["arms"].items():
        L.append(f"| {arm} | " + " | ".join(ms((d["latency_wall_by_corpus"].get(c) or {}).get("median")) for c in corpora)
                 + f" | {ms(d['segment_latency_median_ms'])} |")
    L.append("")
    L.append("## A/A: the control against itself")
    L.append("")
    aa = a["aa"]

    def iv(x):
        return f"[{pct(x['ci95'][0])}, {pct(x['ci95'][1])}]" if x else "n/a"
    L.append(f"C1 against C0, commit latency reduction: median {pct(aa['median']['reduction'])} {iv(aa['median']['interval'])} "
             f"(two-sided p {fnum(aa['median']['p_two_sided'], '{:.3f}')}), p90 {pct(aa['p90']['reduction'])}, p95 {pct(aa['p95']['reduction'])}. "
             f"Session {'valid' if aa['valid'] else 'NOT VALID for timing'}. "
             f"Per-block median ratios C1/C0: {', '.join(f'{x:.2f}' for x in aa['block_median_ratio'])}.")
    if aa["wer_delta_pt"]:
        w = aa["wer_delta_pt"]
        L.append(f"WER, C1 minus C0, over {w['n']} blocks: {w['mean']:+.2f} points, 95% interval {w['ci95'][0]:+.2f} to {w['ci95'][1]:+.2f}.")
    L.append("")
    L.append("## Variants against the controls")
    for v, d in a["variants"].items():
        L.append("")
        L.append(f"### {v}: {d['variable']}. {d['what']}")
        L.append("")
        m, p90, p95 = d["latency"]["median"], d["latency"]["p90"], d["latency"]["p95"]

        def ci(x):
            i = x.get("interval")
            return f"[{pct(i['ci95'][0])}, {pct(i['ci95'][1])}]" if i else ""
        L.append(f"* Commit latency reduction (wall): median {pct(m['reduction'])} {ci(m)} (randomization p {fnum(m['p'], '{:.4f}')}), "
                 f"p90 {pct(p90['reduction'])} {ci(p90)} (p {fnum(p90['p'], '{:.4f}')}), p95 {pct(p95['reduction'])} {ci(p95)} (p {fnum(p95['p'], '{:.4f}')}). "
                 f"Audio-clock median {pct(d['latency_audio_median']['reduction'])}; anchored on the reference segment ends {pct(d['segment_anchor']['reduction'])}. "
                 f"Faster on {d['clips_faster']} of {d['clips']} clips: "
                 + ", ".join(f"{c} {pct(x['effect'])}" for c, x in d["per_clip"].items()))
        L.append("* By corpus (median): " + ", ".join(f"{c} {pct(x['reduction'])} {ci(x)}" for c, x in d["per_corpus"].items()))
        gt = d["gates"]

        def delta(x, unit=" points"):
            i = x.get("interval")
            return (f"{fnum(x['mean_delta'])}{unit}" + (f" [{i['ci95'][0]:+.2f}, {i['ci95'][1]:+.2f}]" if i else "")
                    + f", p {fnum(x['p'], '{:.3f}')}") if x["mean_delta"] is not None else "n/a"
        L.append(f"* Variant minus control, per block: WER {delta(d['wer'])} (Holm p {fnum(gt['wer']['holm_p'], '{:.3f}')}); "
                 f"deletion rate {delta(d['deletion'])}; missing-speech share {delta(d['missing'])}; omitted turns {delta(d['omitted'])}.")
        s = d["secondary"]

        def sm(x, fmt="{:+.2f}"):
            return "n/a" if x is None or x["mean_delta"] is None else fmt.format(x["mean_delta"])
        L.append(f"* Also, variant minus control per block: forced commits {sm(s['forced_commits'])}, dropped hops {sm(s['dropped_hops'])}, "
                 f"empty hypotheses {sm(s['empty_hypotheses'])}, repeat excess {sm(s['repeat_excess'])}, ghost words {sm(s['ghost_words'])}, "
                 f"CPU {sm(s['cpu_s_per_audio_min'])} s per audio minute, infer RTF {sm(s['infer_rtf'], '{:+.3f}')}, "
                 f"decodes/min {sm(s['decodes_per_min'], '{:+.1f}')}, mean window {sm(s['mean_window_ms'], '{:+.0f}')} ms. "
                 f"Finalization latency median {ms(s['finalization_latency_median_ms']['variant'])} ms against {ms(s['finalization_latency_median_ms']['controls'])} ms.")
        h = gt["hallucinations"]
        L.append(f"* Critical hallucinations {h['critical_variant']} against a control mean of {h['critical_control_mean']:.1f}; "
                 f"ghost words {h['ghost_words_variant']} against {h['ghost_words_control_mean']:.1f}.")
        if d.get("uncontended"):
            u = d["uncontended"]
            L.append(f"* Without the {gt['uncontended']['contended_blocks']} shared blocks: median reduction {pct(u['median_reduction'])} "
                     f"(p {fnum(u['p'], '{:.4f}')}), every gate {'passes' if u['gates']['all_pass'] else 'does not pass'}.")
        L.append("* Gates: " + ", ".join(f"{k} {'PASS' if v_['pass'] else 'FAIL'}" for k, v_ in gt.items()
                                          if isinstance(v_, dict) and 'pass' in v_)
                 + f" -> **{'all pass' if gt['all_pass'] else 'not all pass'}**")
    L.append("")
    return "\n".join(L)


# --------------------------------------------------------------------------
# decide
# --------------------------------------------------------------------------

def promote(plan: dict, analysis: dict) -> list[str]:
    rule = plan["gate"]["promotion"]
    out = []
    for v, d in analysis["variants"].items():
        point = d["latency"]["median"]["reduction"]
        if point is not None and point >= rule["minSession1Reduction"] and d["gates"]["immutability"]["pass"]:
            out.append(v)
    return out


def cmd_promote(args) -> int:
    plan = json.loads(args.plan.read_text())
    analysis = json.loads((args.out / f"analysis-session-{plan['session']}.json").read_text())
    print(",".join(promote(plan, analysis)))
    return 0


def check_sessions(sessions: list[tuple[dict, dict]]) -> list[str]:
    """What makes two sessions independent and comparable. Returns the reasons they are not."""
    problems = []
    numbers = [p["session"] for p, _ in sessions]
    if len(set(numbers)) < 2:
        problems.append("fewer than two distinct sessions: reproducibility needs session 1 and session 2")
    hashes = [a["planSha256"] for _, a in sessions]
    if len(set(hashes)) != len(hashes):
        problems.append("two sessions share a plan")
    for plan, _ in sessions:
        if plan["gate"] != DEFAULT_GATE:
            problems.append(f"session {plan['session']}: the gate in the plan is not the gate in this version of the harness")
    first = sessions[0][0]
    for plan, _ in sessions[1:]:
        if plan["seed"] != first["seed"] or plan["tier"] != first["tier"] or plan["base"] != first["base"]:
            problems.append(f"session {plan['session']}: seed, tier or base flags differ from session {first['session']}")
        for arm, definition in plan["arms"].items():
            if arm in first["arms"] and definition["flags"] != first["arms"][arm]["flags"]:
                problems.append(f"session {plan['session']}: arm {arm} has other flags than in session {first['session']}")
        wavs = {c["id"]: c["wavSha256"] for c in first["clips"]}
        for c in plan["clips"]:
            if c["id"] in wavs and wavs[c["id"]] != c["wavSha256"]:
                problems.append(f"session {plan['session']}: clip {c['id']} is not the clip of session {first['session']}")
    return problems


def cmd_decide(args) -> int:
    sessions = []
    for number in args.sessions:
        plan = json.loads((args.out / f"plan-session-{number}.json").read_text())
        analysis = json.loads((args.out / f"analysis-session-{number}.json").read_text())
        sessions.append((plan, analysis))
    gate = DEFAULT_GATE
    problems = check_sessions(sessions) if not args.allow_unchecked else []
    candidates = sorted({v for _, a in sessions for v in a["variants"]})
    verdicts = {}
    for v in candidates:
        per_session = {}
        for plan, analysis in sessions:
            d = analysis["variants"].get(v)
            per_session[plan["session"]] = None if d is None else {
                "reduction": d["latency"]["median"]["reduction"], "all_pass": d["gates"]["all_pass"],
                "failed": [k for k, g in d["gates"].items() if isinstance(g, dict) and not g.get("pass", True)]}
        ran_all = all(per_session.get(plan["session"]) is not None for plan, _ in sessions)
        passed = ran_all and not problems and all(s["all_pass"] for s in per_session.values())
        verdicts[v] = {"per_session": per_session, "ran_in_every_session": ran_all, "meets_every_gate": passed}
    meeting = [v for v, x in verdicts.items() if x["meets_every_gate"]]
    # Each variant was tested alone. A default is changed by one variable; a pair was never tested.
    best = max(meeting, key=lambda v: verdicts[v]["per_session"][sessions[-1][0]["session"]]["reduction"], default=None)
    decision = {"schema": SCHEMA, "created": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                "rule": gate["default"], "reproducibility": gate["reproducibility"], "problems": problems,
                "verdicts": verdicts, "meetEveryGate": meeting, "changeDefaultTo": [best] if best else [],
                "productionConfigurationChanged": best is not None,
                "note": "only one variable is ever changed at once; combinations were not tested"}
    (args.out / "decision.json").write_text(json.dumps(decision, indent=2))
    lines = ["# Decision", "", f"Rule: {gate['default']}.", "", f"Reproducibility: {gate['reproducibility']}.", ""]
    for p in problems:
        lines.append(f"* **Not a valid pair of sessions:** {p}")
    for v, x in verdicts.items():
        lines.append(f"* **{v}**: " + "; ".join(
            f"session {s}: " + ("not run" if r is None else f"latency {pct(r['reduction'])}, "
                                + ("every gate passes" if r["all_pass"] else "fails " + ", ".join(r["failed"])))
            for s, r in x["per_session"].items()) + f" -> {'MEETS EVERY GATE' if x['meets_every_gate'] else 'default stays'}")
    lines += ["", f"**Production configuration {'CHANGED to ' + best if best else 'UNCHANGED'}.**", ""]
    (args.out / "DECISION.md").write_text("\n".join(lines))
    print("\n".join(lines))
    return 0


# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("prepare", help="cut the clips from the public corpora")
    a.add_argument("--work", type=Path, default=DEFAULT_WORK)
    a.add_argument("--fleurs", type=Path, default=Path("/tmp/notero-data/fleurs-eval"))
    a.add_argument("--liva", type=Path, default=Path("/tmp/notero-data/tiers/liva"))
    a.add_argument("--ami", type=Path, default=Path("/tmp/notero-data/diar/ami"))
    a.add_argument("--clip-s", type=int, default=180)
    a.add_argument("--pilot-s", type=int, default=75)
    a.add_argument("--fleurs-max-s", type=float, default=190.0)
    a.set_defaults(fn=cmd_prepare)

    a = sub.add_parser("plan", help="write the plan before any run")
    a.add_argument("--work", type=Path, default=DEFAULT_WORK)
    a.add_argument("--bin", type=Path, default=REPO / "app/.build/release/transcribe")
    a.add_argument("--session", type=int, required=True)
    a.add_argument("--name", default="")
    a.add_argument("--clips", required=True)
    a.add_argument("--arms", required=True)
    a.add_argument("--rounds", type=int, required=True)
    a.add_argument("--out", type=Path, required=True)
    a.add_argument("--note", action="append")
    a.add_argument("--force", action="store_true")
    a.set_defaults(fn=cmd_plan)

    a = sub.add_parser("run", help="replay every planned run not yet done")
    a.add_argument("--plan", type=Path, required=True)
    a.add_argument("--work", type=Path, default=DEFAULT_WORK)
    a.add_argument("--limit", type=int, default=0)
    a.add_argument("--lock-budget-s", type=float, default=4 * 3600, help="how long one run may wait for the bench lock")
    a.set_defaults(fn=cmd_run)

    for name, fn, helptext in (("score", cmd_score, "numbers-only record per run"),
                               ("analyze", cmd_analyze, "paired statistics and gates for one session")):
        a = sub.add_parser(name, help=helptext)
        a.add_argument("--plan", type=Path, required=True)
        a.add_argument("--work", type=Path, default=DEFAULT_WORK)
        a.add_argument("--out", type=Path, required=True)
        a.set_defaults(fn=fn)

    a = sub.add_parser("promote", help="which variants session 1 sends on to session 2")
    a.add_argument("--plan", type=Path, required=True)
    a.add_argument("--out", type=Path, required=True)
    a.set_defaults(fn=cmd_promote)

    a = sub.add_parser("decide", help="apply the plan's rule across sessions")
    a.add_argument("--out", type=Path, required=True)
    a.add_argument("--sessions", type=int, nargs="+", required=True)
    a.add_argument("--allow-unchecked", action="store_true", help="skip the checks that two sessions are independent (tests only)")
    a.set_defaults(fn=cmd_decide)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
