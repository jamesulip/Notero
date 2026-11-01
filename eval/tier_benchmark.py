"""Compare the model tiers on one corpus, under one plan, and apply a fixed decision rule.

The question this answers: should the Balanced tier stay the default? It answers it in
four steps, each a subcommand, each resumable:

    # 1. a corpus: any versioned manifest with audio, or FLEURS fil_ph built from the
    #    verified tarball that eval/fleurs_eval.py fetches
    python3 -I eval/tier_benchmark.py fleurs-manifest --src /tmp/notero-data/fleurs \\
        --work /tmp/notero-data/tiers/fleurs --seed 7
    # 2. a plan: binary, its sha256, the commit, the tiers and their model ids, the
    #    revisions on disk, the schedule and the decision gate -- written BEFORE any decode
    python3 -I eval/tier_benchmark.py plan --manifest /tmp/notero-data/tiers/fleurs/manifest.json \\
        --bin app/.build/release/transcribe --out /tmp/notero-data/tiers/run1
    # 3. the decodes, interleaved across tiers, each under the bench lock
    python3 -I eval/tier_benchmark.py decode --plan /tmp/notero-data/tiers/run1/plan.json
    # 4. the scores (transcribe --score), the paired comparisons and the decision
    python3 -I eval/tier_benchmark.py score  --plan /tmp/notero-data/tiers/run1/plan.json
    python3 -I eval/tier_benchmark.py decide --plan /tmp/notero-data/tiers/run1/plan.json

Rules this script keeps:

  * Every tier decodes the same audio files with the same flags; only `--tier` differs.
    The model id each tier resolved to is read back from the run report and checked.
  * The order is interleaved: for each item, the tiers run in a seeded rotation, so a
    slow stretch of the machine does not land on one tier.
  * Scoring is `transcribe --score` with one evaluation config for every tier, so the
    numbers are comparable by construction; a comparison across configs is refused.
  * The decision rule is fixed in the plan before the first decode. `decide` applies it
    and does not take thresholds of its own.
  * Data stays outside the repository (the work folders are under /tmp by convention),
    is read locally, and is never uploaded. Standard library only; run with `python3 -I`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO = EVAL_DIR.parent
sys.path.insert(0, str(EVAL_DIR))

TIERS = ("fast", "balanced", "best")
BASELINE = "balanced"
LOCK = Path("/tmp/notero-team/bench-lock.sh")
MODELS_DEFAULT = Path.home() / "Library/Application Support/Transcriber/Models"

#: The decision gate, copied into every plan. `decide` reads it from the plan, never from here.
DEFAULT_GATE = {
    "baseline": BASELINE,
    "min_relative_wer_improvement": 0.10,
    "difference_interval_must_exclude_zero": True,
    "require_live_capable": True,
    "max_median_whole_file_rtf": 0.6,
    "max_model_residency_mb": 3500,
    "max_failed_decodes_over_baseline": 0,
    "notes": (
        "A tier replaces the baseline as the default only if every condition holds on the "
        "corpus of this plan. live_capable is ModelTier.suitableForLive: the default tier also "
        "drives live transcription. max_median_whole_file_rtf is the canKeepUpLive proxy of "
        "BenchmarkRun. max_model_residency_mb keeps the model inside a 16 GB Mac's budget "
        "next to the speaker models and the app. A result on read speech can at most support "
        "a change pending real-Taglish validation; it cannot settle it."
    ),
}

#: ModelTier.suitableForLive in app/Sources/TranscriberCore/Catalogues.swift.
LIVE_CAPABLE = {"fast": True, "balanced": True, "best": False}


# ---------------------------------------------------------------- helpers

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def git_commit() -> str:
    out = subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"], capture_output=True, text=True)
    dirty = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--untracked-files=no"],
                           capture_output=True, text=True).stdout.strip()
    return out.stdout.strip() + ("+dirty" if dirty else "")


def model_revision(models: Path, model_id: str) -> str | None:
    """The Hugging Face commit in the local download cache, as EvaluationProvenance reads it."""
    cache = models / "models/argmaxinc/whisperkit-coreml/.cache/huggingface/download" / model_id
    commits = set()
    for meta in cache.rglob("*.metadata") if cache.exists() else []:
        first = meta.read_text(errors="replace").splitlines()[:1]
        if first and len(first[0].strip()) == 40:
            commits.add(first[0].strip())
    if not commits:
        return None
    return commits.pop() if len(commits) == 1 else "mixed: " + ", ".join(sorted(commits))


def seeded_rotation(item_id: str, seed: int, tiers: list[str]) -> list[str]:
    """The tier order for one item: a rotation chosen by a hash, stable across runs."""
    k = int.from_bytes(hashlib.sha256(f"{seed}:{item_id}".encode()).digest()[:4], "big") % len(tiers)
    return tiers[k:] + tiers[:k]


def load_avg() -> float | None:
    try:
        return round(os.getloadavg()[0], 2)
    except OSError:
        return None


# ---------------------------------------------------------------- corpus: FLEURS fil_ph

def command_fleurs_manifest(args: argparse.Namespace) -> int:
    import fleurs_eval  # the same parser, hash check and selection as the earlier FLEURS work

    src, work = Path(args.src), Path(args.work)
    tar = src / "test.tar.gz"
    if not args.skip_hash:
        digest = sha256_file(tar)
        if digest != fleurs_eval.SOURCE_INFO["tar_sha256_published"]:
            print(f"stop: {tar} sha256 {digest} is not the published hash", file=sys.stderr)
            return 2
    utts = fleurs_eval.parse_tsv((src / "test.tsv").read_text())
    chosen = fleurs_eval.one_per_sentence(utts, args.seed)
    if args.limit:
        chosen = fleurs_eval.select_subset(chosen, args.limit, args.seed)
    audio_dir = fleurs_eval.find_audio_dir(src)
    # Gender is column 7 of test.tsv; fleurs_eval does not keep it.
    gender_of = {}
    for line in (src / "test.tsv").read_text().splitlines():
        cols = line.split("\t")
        if len(cols) >= 7:
            gender_of[cols[1]] = cols[6].strip()
    (work / "refs").mkdir(parents=True, exist_ok=True)
    (work / "audio").mkdir(parents=True, exist_ok=True)
    items, genders = [], {}
    for u in chosen:
        item_id = f"fleurs-{u.sent_id}"
        wav = audio_dir / u.filename
        link = work / "audio" / f"{item_id}.wav"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(wav)
        (work / "refs" / f"{item_id}.txt").write_text(u.raw.strip() + "\n")
        gender = gender_of.get(u.filename, "unknown")
        genders[gender] = genders.get(gender, 0) + 1
        items.append({"id": item_id, "audio": f"audio/{item_id}.wav", "ref": f"refs/{item_id}.txt",
                      "category": "tagalog"})
    corpus_id = f"fleurs-fil_ph-test-onepersentence-seed{args.seed}" + (f"-n{args.limit}" if args.limit else "")
    write_json(work / "manifest.json", {"schemaVersion": 1, "corpusId": corpus_id, "items": items})
    write_json(work / "corpus-card.json", {
        "corpusId": corpus_id,
        "source": fleurs_eval.SOURCE_INFO,
        "split": "test",
        "speech": "read Wikipedia-style sentences, one sentence per recording",
        "items": len(items),
        "audioSeconds": round(sum(u.num_samples for u in chosen) / 16000, 1),
        "gender": genders,
        "selection": f"one recording per sentence by seeded hash (seed {args.seed})",
        "references": "FLEURS raw_transcription, verbatim; category tagalog for every item",
        "speakerIds": "not published by FLEURS; speaker diversity cannot be counted",
        "leakage": ("Evaluation only, nothing is trained. Whisper's training data is not published; "
                    "OpenAI reports FLEURS as an evaluation set for Whisper (published claim, unverified here)."),
    })
    print(f"{corpus_id}: {len(items)} items -> {work / 'manifest.json'}")
    return 0


# ---------------------------------------------------------------- corpus: Liva AI en-tl

#: liva-ai/code-switching-asr, en-tl/overlapping, pinned. Licence: the dataset card's YAML says
#: `license: cc-by-4.0` at this revision (checked 2026-11-02). Attribution: Liva AI.
LIVA = {
    "repo": "liva-ai/code-switching-asr",
    "revision": "51b5d0b419e4e96cbc658603fc728a76b53be5fc",
    "license": "cc-by-4.0 (dataset card YAML at the pinned revision)",
    "attribution": "Liva AI, Code-Switching ASR, https://huggingface.co/datasets/liva-ai/code-switching-asr",
    "files": {
        "C_001_007": "4dcb6188295b5228ba2694e742b31de5c3773db905b0b3f0c1385b8aa183d524",
        "C_001_009": "8718674b7ff3bb0ba14f2598a8fb849e9a1be999130f2fd6413e0121e5443870",
        "C_001_015": "48077950a052879bf022555d0e277f5baa17258d06950803c4a03d53a9050c81",
        "C_001_016": "188109e2a93bd46f534ccce4a2a9421be36f45f77c115eeeddd07cf3b4bd9c5b",
    },
}


def command_liva_fetch(args: argparse.Namespace) -> int:
    """Downloads the four en-tl recordings and transcripts at the pinned revision and checks
    each WAV against the LFS SHA-256 that Hugging Face publishes. About 346 MB."""
    import urllib.request

    src = Path(args.src)
    src.mkdir(parents=True, exist_ok=True)
    base = f"https://huggingface.co/datasets/{LIVA['repo']}/resolve/{LIVA['revision']}/en-tl/overlapping"
    for name, digest in LIVA["files"].items():
        for ext in ("txt", "wav"):
            target = src / f"{name}.{ext}"
            if not target.exists():
                print(f"fetch {name}.{ext}", flush=True)
                urllib.request.urlretrieve(f"{base}/{name}.{ext}", target)
        got = sha256_file(src / f"{name}.wav")
        if got != digest:
            print(f"stop: {name}.wav sha256 {got} is not the published {digest}", file=sys.stderr)
            return 2
    for name in ("README.md",):
        urllib.request.urlretrieve(f"https://huggingface.co/datasets/{LIVA['repo']}/raw/{LIVA['revision']}/{name}",
                                   src / name)
    print(f"verified {len(LIVA['files'])} recordings in {src}")
    return 0


def parse_liva_transcript(text: str) -> list[dict]:
    """`Speaker N [hh:mm:ss.mmm - hh:mm:ss.mmm]: text` lines into utterances.

    Event tags such as `[laughing]` are not speech and are removed from the scored text;
    a line that is only tags is skipped. The line as written is kept in `source`."""
    import re

    line_re = re.compile(r"^(Speaker \S+) \[(\d+):(\d+):(\d+)\.(\d+) - (\d+):(\d+):(\d+)\.(\d+)\]: ?(.*)$")
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        m = line_re.match(line.strip())
        if not m:
            continue
        g = m.groups()
        start = ((int(g[1]) * 60 + int(g[2])) * 60 + int(g[3])) * 1000 + int(g[4].ljust(3, "0")[:3])
        end = ((int(g[5]) * 60 + int(g[6])) * 60 + int(g[7])) * 1000 + int(g[8].ljust(3, "0")[:3])
        spoken = re.sub(r"\[[^\]]*\]", " ", g[9])
        spoken = re.sub(r"\s+", " ", spoken).strip()
        if not re.search(r"\w", spoken):
            continue
        out.append({"id": f"line-{n}", "speaker": g[0], "startMs": start, "endMs": max(end, start),
                    "text": spoken, "language": "mixed"})
    return out


def command_liva_manifest(args: argparse.Namespace) -> int:
    src, work = Path(args.src).resolve(), Path(args.work)
    (work / "refs").mkdir(parents=True, exist_ok=True)
    (work / "audio").mkdir(parents=True, exist_ok=True)
    items, utterances, seconds = [], 0, 0.0
    for name in LIVA["files"]:
        item_id = f"liva-en-tl-{name}"
        utts = parse_liva_transcript((src / f"{name}.txt").read_text())
        write_json(work / "refs" / f"{item_id}.json",
                   {"schemaVersion": 1, "itemId": item_id, "utterances": utts})
        link = work / "audio" / f"{item_id}.wav"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(src / f"{name}.wav")
        utterances += len(utts)
        seconds += (src / f"{name}.wav").stat().st_size / (48000 * 3)
        items.append({"id": item_id, "audio": f"audio/{item_id}.wav", "ref": f"refs/{item_id}.json",
                      "category": "mixed"})
    corpus_id = f"liva-en-tl-overlapping-{LIVA['revision'][:7]}"
    write_json(work / "manifest.json", {"schemaVersion": 1, "corpusId": corpus_id, "items": items})
    write_json(work / "corpus-card.json", {
        "corpusId": corpus_id, "source": LIVA,
        "speech": "conversational Taglish: friends talking in a voice chat while gaming, one mixed-down track",
        "items": len(items), "utterances": utterances, "audioSecondsApprox": round(seconds, 1),
        "speakers": "4-5 per file; all four files are session C_001, so probably one group of friends",
        "references": ("vendor transcripts, 'AI-generated and then human reviewed, or fully human generated' (card); "
                       "event tags removed; utterance language set to 'mixed'; no word-level language"),
        "leakage": "evaluation only; the vendor says the audio is collected in-house, not from YouTube (unverified)",
        "limits": "about 40 minutes of one group: a smoke test of conversational Taglish, not a benchmark",
    })
    print(f"{corpus_id}: {len(items)} items, {utterances} utterances -> {work / 'manifest.json'}")
    return 0


# ---------------------------------------------------------------- plan

def command_plan(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).resolve()
    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1:
        print("stop: the manifest must be the versioned form with a corpusId", file=sys.stderr)
        return 2
    binary = Path(args.bin).resolve()
    out = Path(args.out).resolve()
    tiers = args.tiers.split(",")
    if BASELINE not in tiers:
        print(f"stop: the tiers must include the baseline {BASELINE}", file=sys.stderr)
        return 2
    models = Path(args.models)
    tier_models = json.loads(args.tier_models) if args.tier_models else {
        # ModelTier.defaultModelId at the inspected commit; decode checks it against the reports.
        "fast": "openai_whisper-large-v3-v20240930_626MB",
        "balanced": "openai_whisper-large-v3-v20240930_turbo",
        "best": "openai_whisper-large-v3_turbo",
    }
    missing_audio = [i["id"] for i in manifest["items"]
                     if not (manifest_path.parent / i.get("audio", "")).exists()]
    if missing_audio:
        print(f"stop: no audio for {len(missing_audio)} items, e.g. {missing_audio[:3]}", file=sys.stderr)
        return 2
    schedule = []
    for item in manifest["items"]:
        for tier in seeded_rotation(item["id"], args.seed, tiers):
            schedule.append({"item": item["id"], "tier": tier, "repeat": 0})
    repeat_items = [i["id"] for i in manifest["items"][: args.repeat_subset]]
    for item_id in repeat_items:
        for tier in seeded_rotation(item_id + ":r1", args.seed, tiers):
            schedule.append({"item": item_id, "tier": tier, "repeat": 1})
    gate = dict(DEFAULT_GATE)
    if args.gate:
        gate.update(json.loads(args.gate))
    plan = {
        "schema": 1,
        "what": "tier comparison plan; written before any decode",
        "createdUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "commit": git_commit(),
        "binary": {"path": str(binary), "sha256": sha256_file(binary)},
        "manifest": {"path": str(manifest_path), "sha256": sha256_file(manifest_path),
                     "corpusId": manifest["corpusId"], "items": len(manifest["items"])},
        "modelsDirectory": str(models),
        "tiers": {t: {"modelId": tier_models[t], "revision": model_revision(models, tier_models[t]),
                      "liveCapable": LIVE_CAPABLE.get(t)} for t in tiers},
        "decodeFlags": ["--language", args.language, "--no-diarize"] + (args.extra or []),
        "evalConfig": str(Path(args.eval_config).resolve()),
        "evalConfigSha256": sha256_file(Path(args.eval_config)),
        "seed": args.seed,
        "repeatItems": repeat_items,
        "schedule": schedule,
        "gate": gate,
        "machine": subprocess.run(["sysctl", "-n", "hw.model", "machdep.cpu.brand_string", "hw.memsize"],
                                  capture_output=True, text=True).stdout.split("\n")[:3],
    }
    write_json(out / "plan.json", plan)
    print(f"plan: {len(schedule)} decodes ({len(manifest['items'])} items x {len(tiers)} tiers"
          f" + {len(repeat_items)} repeated) -> {out / 'plan.json'}")
    return 0


# ---------------------------------------------------------------- decode

def run_path(out: Path, tier: str, item: str, repeat: int) -> Path:
    folder = out / "hyp" / tier if repeat == 0 else out / f"hyp-repeat{repeat}" / tier
    return folder / f"{item}.json"


def command_decode(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).resolve()
    plan = json.loads(plan_path.read_text())
    out = plan_path.parent
    if sha256_file(Path(plan["binary"]["path"])) != plan["binary"]["sha256"]:
        print("stop: the binary changed since the plan was written", file=sys.stderr)
        return 2
    manifest_path = Path(plan["manifest"]["path"])
    items = {i["id"]: i for i in json.loads(manifest_path.read_text())["items"]}
    log_path = out / "decode-log.jsonl"
    use_lock = LOCK.exists() and not args.no_lock
    todo = [s for s in plan["schedule"] if not run_path(out, s["tier"], s["item"], s["repeat"]).exists()]
    done = len(plan["schedule"]) - len(todo)
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(todo)} decodes to run now ({done} of {len(plan['schedule'])} already done)", flush=True)
    for n, step in enumerate(todo, 1):
        tier, item_id, repeat = step["tier"], step["item"], step["repeat"]
        target = run_path(out, tier, item_id, repeat)
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(".partial.json")
        stderr_path = target.with_suffix(".stderr.txt")
        audio = manifest_path.parent / items[item_id]["audio"]
        cmd = [plan["binary"]["path"], "--audio", str(audio), "--tier", tier,
               "--models", plan["modelsDirectory"], *plan["decodeFlags"],
               "--eval-config", plan["evalConfig"], "--label", tier,
               "--build", plan["commit"], "--json", str(tmp)]
        # The export goes to stdout, which is discarded: `--out /dev/null` fails, because
        # the tool writes the export atomically through a temporary file beside the target.
        if use_lock:
            cmd = [str(LOCK), *cmd]
        load_before = load_avg()
        started = time.monotonic()
        with open(stderr_path, "w") as err:
            code = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=err).returncode
        wall = round(time.monotonic() - started, 3)
        entry = {"item": item_id, "tier": tier, "repeat": repeat, "exit": code, "wallS": wall,
                 "loadAvg1mBefore": load_before, "loadAvg1mAfter": load_avg()}
        if code == 0 and tmp.exists():
            report = json.loads(tmp.read_text())
            expected = plan["tiers"][tier]["modelId"]
            if report.get("model") != expected:
                entry["error"] = f"model {report.get('model')} is not the planned {expected}"
                print(f"stop: {entry['error']}", file=sys.stderr)
                with open(log_path, "a") as log:
                    log.write(json.dumps(entry, sort_keys=True) + "\n")
                return 1
            tmp.rename(target)
        else:
            entry["error"] = "decode failed; stderr kept"
        with open(log_path, "a") as log:
            log.write(json.dumps(entry, sort_keys=True) + "\n")
        if n % 25 == 0 or n == len(todo):
            print(f"  {n}/{len(todo)} {tier} {item_id} exit {code} {wall}s load {entry['loadAvg1mBefore']}",
                  flush=True)
    return 0


# ---------------------------------------------------------------- score

def transcribe_score(plan: dict, hyp: Path, label: str, out_dir: Path, compare: tuple[Path, str] | None = None) -> int:
    cmd = [plan["binary"]["path"], "--score", plan["manifest"]["path"], "--hypotheses", str(hyp),
           "--label", label, "--eval-config", plan["evalConfig"], "--build", plan["commit"],
           "--out-dir", str(out_dir)]
    if compare:
        cmd += ["--compare", str(compare[0]), "--compare-label", compare[1]]
    result = subprocess.run(cmd, capture_output=True, text=True)
    (out_dir / "score-stderr.txt").parent.mkdir(parents=True, exist_ok=True)
    (out_dir / "score-stderr.txt").write_text(result.stderr)
    return result.returncode


def failed_decodes(out: Path, plan: dict) -> dict[str, list[str]]:
    """Every planned decode, first pass and repeats, without a clean log entry and an output.

    Fails closed: a decode with no log entry, a logged error with exit 0, or a missing
    output counts as failed, and so does every decode when the log itself is missing."""
    failed: dict[str, list[str]] = {}
    log = out / "decode-log.jsonl"
    latest = {}
    for line in log.read_text().splitlines() if log.exists() else []:
        e = json.loads(line)
        latest[(e["item"], e["tier"], e["repeat"])] = e
    for step in plan["schedule"]:
        e = latest.get((step["item"], step["tier"], step["repeat"]))
        ok = (e is not None and e.get("exit") == 0 and not e.get("error")
              and run_path(out, step["tier"], step["item"], step["repeat"]).exists())
        if not ok:
            label = step["item"] if step["repeat"] == 0 else f"{step['item']} (repeat {step['repeat']})"
            failed.setdefault(step["tier"], []).append(label)
    return failed


def command_score(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).resolve()
    plan = json.loads(plan_path.read_text())
    out = plan_path.parent
    reports = out / "reports"
    if reports.exists():
        shutil.rmtree(reports)
    status = {}
    for tier in plan["tiers"]:
        status[tier] = transcribe_score(plan, out / "hyp" / tier, tier, reports / tier)
    for tier in plan["tiers"]:
        if tier == BASELINE:
            continue
        status[f"{BASELINE}-vs-{tier}"] = transcribe_score(
            plan, out / "hyp" / BASELINE, BASELINE, reports / f"{BASELINE}-vs-{tier}",
            compare=(out / "hyp" / tier, tier))
    # A full second pass gives a second, independent comparison: the decode-to-decode
    # variation that the bootstrap over utterances cannot see.
    if len(plan["repeatItems"]) == plan["manifest"]["items"]:
        for tier in plan["tiers"]:
            if tier == BASELINE:
                continue
            status[f"repeat1:{BASELINE}-vs-{tier}"] = transcribe_score(
                plan, out / "hyp-repeat1" / BASELINE, BASELINE,
                reports / "repeat1" / f"{BASELINE}-vs-{tier}", compare=(out / "hyp-repeat1" / tier, tier))
    write_json(reports / "score-status.json", status)
    print(json.dumps(status, sort_keys=True))
    return 0 if all(code == 0 for code in status.values()) else 1


# ---------------------------------------------------------------- decide

def run_figures(out: Path, tier: str) -> dict:
    """Load time, RTF, memory and decode failures read from the run reports themselves."""
    load, rtf, footprint, residency, words, windows_dropped = [], [], [], [], 0, 0
    for path in sorted((out / "hyp" / tier).glob("*.json")):
        r = json.loads(path.read_text())
        if r.get("loadMs") is not None:
            load.append(r["loadMs"])
        if r.get("durationMs"):
            rtf.append(r["decodeMs"] / r["durationMs"])
        perf = r.get("performance") or {}
        if (perf.get("processPeakFootprintMB") or {}).get("status") == "available":
            footprint.append(perf["processPeakFootprintMB"]["value"])
        if (perf.get("modelResidencyMB") or {}).get("status") == "available":
            residency.append(perf["modelResidencyMB"]["value"])
        words += r.get("wordCount", 0)
        stderr = path.with_suffix(".stderr.txt")
        if stderr.exists() and "never decoded" in stderr.read_text():
            windows_dropped += 1

    def summary(values):
        if not values:
            return None
        values = sorted(values)
        return {"n": len(values), "median": statistics.median(values), "min": values[0], "max": values[-1],
                "p90": values[min(len(values) - 1, int(round(0.9 * (len(values) - 1))))]}

    items = len(list((out / "hyp" / tier).glob("*.json")))
    return {"loadMs": summary(load), "wholeFileRTF": summary(rtf), "items": items,
            "residencyOnEveryItem": len(residency) == items and items > 0,
            "processPeakFootprintMB": summary(footprint), "modelResidencyMB": summary(residency),
            "itemsWithDroppedWindows": windows_dropped, "hypothesisWords": words}


def repeat_agreement(out: Path, plan: dict, tier: str) -> dict | None:
    if not plan["repeatItems"]:
        return None
    same = differ = missing = 0
    for item in plan["repeatItems"]:
        a, b = run_path(out, tier, item, 0), run_path(out, tier, item, 1)
        if not (a.exists() and b.exists()):
            missing += 1
            continue
        ta, tb = json.loads(a.read_text())["transcript"], json.loads(b.read_text())["transcript"]
        same, differ = (same + 1, differ) if ta == tb else (same, differ + 1)
    return {"identical": same, "different": differ, "missing": missing}


def stability(out: Path, plan: dict, reports: Path, tier: str, base: dict, gate: dict) -> dict:
    """A difference has to survive a second decode when decodes are not repeatable.

    Passes when every repeated item decoded identically for both tiers (the corpus is
    deterministic, so one pass is the measurement), or when a full second pass exists and
    its comparison also meets the improvement threshold. Fails otherwise: a gain seen in
    one pass of a corpus that decodes differently each time is not yet a measurement."""
    agreements = [repeat_agreement(out, plan, t) for t in (gate["baseline"], tier)]
    if all(a and a["different"] == 0 and a["missing"] == 0 and a["identical"] > 0 for a in agreements):
        return {"value": "repeats identical", "need": "deterministic, or a second pass that agrees",
                "pass": True}
    second = reports / "repeat1" / f"{gate['baseline']}-vs-{tier}" / "comparison.json"
    if not second.exists():
        return {"value": "decodes differ between runs and there is no full second pass" if any(agreements)
                else "no repeated decodes", "need": "deterministic, or a second pass that agrees", "pass": False}
    wer = value(json.loads(second.read_text())["wer"]) or {}
    diff, baseline_wer = value(wer.get("difference")), value(wer.get("baseline"))
    relative = (-diff / baseline_wer) if (diff is not None and baseline_wer) else None
    return {"value": f"second-pass relative improvement {relative:.4f}" if relative is not None else "unavailable",
            "need": f">= {gate['min_relative_wer_improvement']} in the second pass too",
            "pass": relative is not None and relative >= gate["min_relative_wer_improvement"]}


def value(m):
    return m.get("value") if isinstance(m, dict) and m.get("status") == "available" else None


def command_decide(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).resolve()
    plan = json.loads(plan_path.read_text())
    out = plan_path.parent
    reports = out / "reports"
    gate = plan["gate"]
    if not (out / "decode-log.jsonl").exists():
        print("stop: no decode-log.jsonl; without it nothing says which decodes succeeded", file=sys.stderr)
        return 2
    failed = failed_decodes(out, plan)
    tiers = {}
    for tier in plan["tiers"]:
        report = json.loads((reports / tier / "report.json").read_text())
        corpus = report["corpus"]
        tiers[tier] = {
            "modelId": plan["tiers"][tier]["modelId"],
            "revision": plan["tiers"][tier]["revision"],
            "itemsScored": corpus["itemsScored"], "itemsInManifest": corpus["itemsInManifest"],
            "wer": value(corpus["wer"]), "werInterval": value((value(corpus["werInterval"]) or {}).get("interval")),
            "cer": value(corpus["cer"]), "words": corpus["words"], "characters": corpus["characters"],
            "deletionBurstWords": sum(b["length"] for b in (value(corpus["deletionBursts"]) or [])),
            "failedDecodes": failed.get(tier, []),
            "repeatAgreement": repeat_agreement(out, plan, tier),
            **run_figures(out, tier),
        }
    base = tiers[gate["baseline"]]
    verdicts = {}
    for tier, figures in tiers.items():
        if tier == gate["baseline"]:
            continue
        comparison = json.loads((reports / f"{gate['baseline']}-vs-{tier}" / "comparison.json").read_text())
        wer = value(comparison["wer"]) or {}
        diff = value(wer.get("difference"))
        interval = value(wer.get("differenceInterval"))
        relative = (-diff / base["wer"]) if (diff is not None and base["wer"]) else None
        checks = {
            "relativeWerImprovement": {"value": relative, "need": f">= {gate['min_relative_wer_improvement']}",
                                       "pass": relative is not None and relative >= gate["min_relative_wer_improvement"]},
            "differenceIntervalBelowZero": {"value": interval, "need": "upper < 0",
                                            "pass": (not gate["difference_interval_must_exclude_zero"])
                                            or (interval is not None and interval["upper"] < 0)},
            "liveCapable": {"value": plan["tiers"][tier]["liveCapable"], "need": "true",
                            "pass": (not gate["require_live_capable"]) or bool(plan["tiers"][tier]["liveCapable"])},
            "medianWholeFileRTF": {"value": (figures["wholeFileRTF"] or {}).get("median"),
                                   "need": f"<= {gate['max_median_whole_file_rtf']}",
                                   "pass": figures["wholeFileRTF"] is not None
                                   and figures["wholeFileRTF"]["median"] <= gate["max_median_whole_file_rtf"]},
            "modelResidencyMB": {"value": (figures["modelResidencyMB"] or {}).get("median"),
                                 "need": f"<= {gate['max_model_residency_mb']}",
                                 "pass": figures["modelResidencyMB"] is not None
                                 and figures["modelResidencyMB"]["median"] <= gate["max_model_residency_mb"]},
            "allItemsScored": {"value": f"{figures['itemsScored']}/{figures['itemsInManifest']}",
                               "need": "every item, both tiers",
                               "pass": figures["itemsScored"] == figures["itemsInManifest"]
                               and base["itemsScored"] == base["itemsInManifest"]},
            "residencyMeasuredOnEveryItem": {"value": figures["residencyOnEveryItem"], "need": "true",
                                             "pass": figures["residencyOnEveryItem"]},
            "stableAcrossDecodes": stability(out, plan, reports, tier, base, gate),
            "failedDecodes": {"value": len(figures["failedDecodes"]),
                              "need": f"<= baseline + {gate['max_failed_decodes_over_baseline']}",
                              "pass": len(figures["failedDecodes"])
                              <= len(base["failedDecodes"]) + gate["max_failed_decodes_over_baseline"]},
        }
        verdicts[tier] = {"difference": diff, "differenceInterval": interval,
                          "shareCandidateLower": value(wer.get("shareCandidateLower")),
                          "checks": checks, "meetsGate": all(c["pass"] for c in checks.values())}
    winners = [t for t, v in verdicts.items() if v["meetsGate"]]
    decision = {
        "corpusId": plan["manifest"]["corpusId"], "commit": plan["commit"], "binarySha256": plan["binary"]["sha256"],
        "gate": gate, "tiers": tiers, "verdicts": verdicts,
        "decision": (f"change the default to {winners[0]} (gate met on this corpus)" if len(winners) == 1
                     else f"keep {gate['baseline']}" if not winners
                     else "more than one tier met the gate: inspect before any change"),
    }
    write_json(reports / "decision.json", decision)
    (reports / "decision.md").write_text(render_decision(decision))
    print(decision["decision"])
    return 0


def pct(v, digits=2):
    return "—" if v is None else f"{v * 100:.{digits}f}%"


def render_decision(d: dict) -> str:
    lines = [f"# Tier decision on `{d['corpusId']}`", "",
             f"Commit `{d['commit']}`, binary sha256 `{d['binarySha256'][:16]}…`.", "",
             f"**Decision: {d['decision']}.**", "",
             "| Tier | Model | WER | 95% CI | CER | S / D / I | Items | Failed | Median RTF | Median load | Model residency | Peak footprint |",
             "| --- | --- | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for tier, f in d["tiers"].items():
        ci = f["werInterval"] or {}
        rtf = (f["wholeFileRTF"] or {}).get("median")
        load = (f["loadMs"] or {}).get("median")
        res = (f["modelResidencyMB"] or {}).get("median")
        fp = (f["processPeakFootprintMB"] or {}).get("median")
        w = f["words"]
        lines.append(
            f"| {tier} | `{f['modelId']}` | {pct(f['wer'])} | "
            + (f"{pct(ci.get('lower'))}–{pct(ci.get('upper'))}" if ci else "—")
            + f" | {pct(f['cer'])} | {w['substitutions']} / {w['deletions']} / {w['insertions']} | "
            f"{f['itemsScored']}/{f['itemsInManifest']} | {len(f['failedDecodes'])} | "
            + ("—" if rtf is None else f"{rtf:.3f}") + " | "
            + ("—" if load is None else f"{load / 1000:.1f} s") + " | "
            + ("—" if res is None else f"{res:.0f} MB") + " | "
            + ("—" if fp is None else f"{fp:.0f} MB") + " |")
    lines += ["", "## Gate", ""]
    for tier, v in d["verdicts"].items():
        lines.append(f"### {tier} against {d['gate']['baseline']}")
        lines.append("")
        iv = v["differenceInterval"]
        diff = "—" if v["difference"] is None else f"{v['difference'] * 100:+.2f} pt"
        lines.append(f"Difference {diff}"
                     + (f", 95% interval {iv['lower'] * 100:+.2f} to {iv['upper'] * 100:+.2f} pt" if iv else "")
                     + f". Meets the gate: **{'yes' if v['meetsGate'] else 'no'}**.")
        lines.append("")
        lines.append("| Check | Value | Needed | Pass |")
        lines.append("| --- | --- | --- | --- |")
        for name, c in v["checks"].items():
            val = c["value"]
            if isinstance(val, dict):
                val = f"{val['lower'] * 100:+.2f} to {val['upper'] * 100:+.2f} pt"
            elif isinstance(val, float):
                val = f"{val:.4f}"
            lines.append(f"| {name} | {val} | {c['need']} | {'yes' if c['pass'] else 'no'} |")
        lines.append("")
    lines += ["Peak footprint is the `phys_footprint` of the decoding process and does not contain the "
              "model: add the model residency for the memory the process really used. The 95% intervals "
              "resample utterances or items of one decode; where decodes are not repeatable, the "
              "`stableAcrossDecodes` check, not the interval, says whether a difference survives a second "
              "pass. A tier that is not live-capable cannot pass, whatever its accuracy, because the default "
              "tier also drives live transcription.", "",
              "Every figure above is measured in this run. The gate was fixed in the plan before the first "
              "decode. The corpus is what its corpus card says it is; a result here is not a result on "
              "speech the corpus does not contain."]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("fleurs-manifest", help="build a versioned manifest from the verified FLEURS fil_ph test split")
    p.add_argument("--src", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--limit", type=int, default=0, help="seeded subset of this many sentences (0: all)")
    p.add_argument("--skip-hash", action="store_true")
    p.set_defaults(func=command_fleurs_manifest)

    p = sub.add_parser("liva-fetch", help="download and verify the Liva AI en-tl sample (CC-BY-4.0)")
    p.add_argument("--src", required=True)
    p.set_defaults(func=command_liva_fetch)

    p = sub.add_parser("liva-manifest", help="build a versioned manifest from the Liva AI en-tl sample")
    p.add_argument("--src", required=True)
    p.add_argument("--work", required=True)
    p.set_defaults(func=command_liva_manifest)

    p = sub.add_parser("plan", help="write the plan, including the decision gate, before any decode")
    p.add_argument("--manifest", required=True)
    p.add_argument("--bin", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--models", default=str(MODELS_DEFAULT))
    p.add_argument("--tiers", default=",".join(TIERS))
    p.add_argument("--tier-models", help="JSON {tier: model id}, when the catalogue has changed")
    p.add_argument("--language", default="tl")
    p.add_argument("--extra", nargs="*", help="more transcribe flags, the same for every tier")
    p.add_argument("--eval-config", default=str(EVAL_DIR / "evaluation-config.v1.json"))
    p.add_argument("--seed", type=int, default=20261102)
    p.add_argument("--repeat-subset", type=int, default=0, help="decode the first N items a second time")
    p.add_argument("--gate", help="JSON overrides of the gate, recorded in the plan")
    p.set_defaults(func=command_plan)

    p = sub.add_parser("decode", help="run the planned decodes; resumable")
    p.add_argument("--plan", required=True)
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--no-lock", action="store_true")
    p.set_defaults(func=command_decode)

    p = sub.add_parser("score", help="score each tier and compare each with the baseline")
    p.add_argument("--plan", required=True)
    p.set_defaults(func=command_score)

    p = sub.add_parser("decide", help="apply the plan's gate")
    p.add_argument("--plan", required=True)
    p.set_defaults(func=command_decide)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
