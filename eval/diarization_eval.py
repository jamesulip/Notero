"""Compare speaker-diarization backends on the same annotated audio.

    prepare-ami        AMI test set (CC BY 4.0) + pyannote/AMI-diarization-setup RTTMs
    prepare-liva       Liva AI en-tl sample (CC BY 4.0): speaker-labelled Taglish
    prepare-synthetic  make_multispeaker.py fixtures (SYNTHETIC)
    plan               fix arms, items, run order, scoring rules and the gate, before any run
    run                run every (item, arm, repeat) not yet done; resumable
    score              metrics for every output (eval/diarization_metrics.py)
    rescore            score the same outputs of one corpus against another reference set
                       (secondary: the plan's references stay the primary ones)
    residency          sample `footprint(1)` from outside each arm on one file: Neural Engine
                       and GPU memory, which the process footprint leaves out
    identity           re-run each arm on changed audio with `--carry-from` its first run, and
                       count speech that a carried name would put under the wrong person
    decide             apply the gate written in the plan

Each arm is a command template. `diarbench` (the app's `SpeakerEngine`) and the
experimental `nemodiarbench` (experimental/nemotron3) write the same JSON:

    --arm 'pyannote=/path/diarbench --audio {audio} --models M --json {json} --mode accurate'
    --arm 'nemotron3=/path/nemodiarbench --audio {audio} --models M --json {json}'

The first arm is the baseline. Every command runs under `--wrap` (the bench lock and
a network-denied sandbox by default), so a timing is not shared with another
measured job and nothing is downloaded.

All audio is prepared as 16 kHz mono 16-bit WAV, so every arm reads the same samples.
Recordings and references stay in the work directory and are never uploaded.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import random
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import der  # noqa: E402
import diarization_metrics as dm  # noqa: E402

SCHEMA = 1
DEFAULT_WRAP = ["/tmp/notero-team/bench-lock.sh", "sandbox-exec", "-p",
                "(version 1)(allow default)(deny network*)"]

# Written into every plan before the first run. The candidate is every arm after the
# first; the baseline is the first.
DEFAULT_GATE = {
    "minRelativeDerImprovement": 0.15,     # on EVERY real corpus, pooled, primary rules
    "realCorpora": ["ami", "liva"],
    "maxMergedSpeakersIncrease": 0,        # per file, real and synthetic
    "maxPeakFootprintMB": 1024,            # candidate, any run
    "maxMedianRealTimeFactor": 0.10,       # candidate diarize time / audio time, real files
    "maxRepeatDerSpread": 0.01,            # candidate, |DER run1 - run2| on a repeated file
    # Speaker-name carry (eval/speaker_stability.py, policy "carry"): share of speech
    # under a wrong name after a re-run on changed audio, pooled over `identityCorpora`.
    "maxWrongNameIncreasePoints": 1.0,
    "identityCorpora": ["liva", "synth-tuning", "synth-n"],
}

PRIMARY = dm.Rules()                                   # collar 0.25, overlap scored
SECONDARY = [dm.Rules(collar=0.0), dm.Rules(skip_overlap=True)]


# --- preparation -----------------------------------------------------------------

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def to_wav16(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(src), str(dst)],
                   check=True)


def wav_seconds(path: Path) -> float:
    import wave
    with wave.open(str(path)) as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        return w.getnframes() / 16000


def write_manifest(work: Path, corpus: str, items: list[dict], card: dict) -> None:
    work.mkdir(parents=True, exist_ok=True)
    (work / "manifest.json").write_text(json.dumps(
        {"schemaVersion": SCHEMA, "corpus": corpus, "card": card, "items": items},
        indent=1, sort_keys=True) + "\n")
    print(f"{corpus}: {len(items)} items, "
          f"{sum(i['durationS'] for i in items) / 60:.1f} min -> {work / 'manifest.json'}")


def item_record(corpus: str, item_id: str, wav: Path, rttm: Path, work: Path, **extra) -> dict:
    ref = der.read_rttm(rttm)
    return {
        "id": item_id, "corpus": corpus,
        "audio": str(wav.relative_to(work)), "ref": str(rttm.relative_to(work)),
        "audioSha256": sha256(wav), "durationS": round(wav_seconds(wav), 3),
        "refSpeakers": len({s.speaker for s in ref}),
        "refSpeechS": round(sum(s.end - s.start for s in ref), 3),
        **extra,
    }


def prepare_ami(src: Path, work: Path) -> int:
    setup = src / "setup"
    meetings = (setup / "lists" / "test.meetings.txt").read_text().split()
    items = []
    for m in meetings:
        raw = src / "audio" / f"{m}.Mix-Headset.wav"
        if not raw.exists():
            print(f"error: missing {raw}", file=sys.stderr)
            return 2
        wav, rttm = work / "audio" / f"ami-{m}.wav", work / "refs" / f"ami-{m}.rttm"
        to_wav16(raw, wav)
        rttm.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(setup / "only_words" / "rttms" / "test" / f"{m}.rttm", rttm)
        items.append(item_record("ami", f"ami-{m}", wav, rttm, work, sourceSha256=sha256(raw)))
    rev = subprocess.run(["git", "-C", str(setup), "rev-parse", "HEAD"],
                         capture_output=True, text=True).stdout.strip()
    write_manifest(work, "ami", items, {
        "name": "AMI Meeting Corpus, test set (16 meetings), Mix-Headset",
        "licence": "CC BY 4.0 (audio and annotations), https://groups.inf.ed.ac.uk/ami/corpus/license.shtml",
        "reference": f"pyannote/AMI-diarization-setup only_words RTTM, commit {rev} (Apache-2.0), "
                     "from AMI manual annotations 1.6.2",
        "speech": "English scenario and non-scenario meetings, close-talk headsets mixed to one track",
        "attribution": "AMI Meeting Corpus, University of Edinburgh et al., CC BY 4.0. Audio resampled to 16 kHz.",
    })
    return 0


LIVA_LINE = re.compile(
    r"^(Speaker \d+) \[(\d+):(\d+):(\d+\.\d+) - (\d+):(\d+):(\d+\.\d+)\]:\s*(.*)$")


def parse_liva_speech(text: str) -> list[der.Segment]:
    """Speaker turns with speech. A line whose text is only event tags such as
    `[laughing]` is not speech and is left out of the reference."""
    out = []
    for line in text.splitlines():
        m = LIVA_LINE.match(line.strip())
        if not m:
            continue
        words = re.sub(r"\[[^\]]*\]", " ", m.group(8)).strip()
        if not re.search(r"\w", words):
            continue
        h1, m1, s1, h2, m2, s2 = (float(m.group(i)) for i in range(2, 8))
        start, end = h1 * 3600 + m1 * 60 + s1, h2 * 3600 + m2 * 60 + s2
        if end > start:
            out.append(der.Segment(start, end, m.group(1).replace(" ", "")))
    return out


def prepare_liva(src: Path, work: Path) -> int:
    items = []
    for txt in sorted(src.glob("C_*.txt")):
        stem = txt.stem
        wav, rttm = work / "audio" / f"liva-{stem}.wav", work / "refs" / f"liva-{stem}.rttm"
        to_wav16(src / f"{stem}.wav", wav)
        rttm.parent.mkdir(parents=True, exist_ok=True)
        der.write_rttm(parse_liva_speech(txt.read_text()), rttm, stem)
        items.append(item_record("liva", f"liva-{stem}", wav, rttm, work,
                                 sourceSha256=sha256(src / f"{stem}.wav")))
    write_manifest(work, "liva", items, {
        "name": "Liva AI Code-Switching ASR, en-tl sample, revision 51b5d0b419e4e96cbc658603fc728a76b53be5fc",
        "licence": "CC BY 4.0 (dataset card)",
        "reference": "vendor speaker-labelled transcripts made from channel-separated audio; "
                     "lines with only event tags are left out",
        "speech": "conversational Taglish, one group of friends in a gaming voice chat, mixed to one track",
        "attribution": "Liva AI, Code-Switching ASR (en-tl), CC BY 4.0. Audio resampled to 16 kHz mono.",
    })
    return 0


def prepare_synthetic(fixtures: Path, work: Path, corpus: str) -> int:
    items = []
    for wav_src in sorted(fixtures.glob("*.wav")):
        rttm_src = wav_src.with_suffix(".rttm")
        if not rttm_src.exists():
            continue
        wav, rttm = work / "audio" / wav_src.name, work / "refs" / rttm_src.name
        wav.parent.mkdir(parents=True, exist_ok=True)
        rttm.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(wav_src, wav)
        shutil.copyfile(rttm_src, rttm)
        items.append(item_record(corpus, f"{corpus}-{wav_src.stem}", wav, rttm, work))
    write_manifest(work, corpus, items, {
        "name": f"SYNTHETIC: eval/make_multispeaker.py fixtures from {fixtures}",
        "licence": "generated on this machine with macOS `say`",
        "speech": "text-to-speech voices on one timeline, exact boundaries. Not a claim about real meetings.",
    })
    return 0


# --- plan ------------------------------------------------------------------------

def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True,
                          cwd=Path(__file__).resolve().parent).stdout.strip()


def hardware() -> dict:
    def sysctl(key: str) -> str:
        return subprocess.run(["sysctl", "-n", key], capture_output=True, text=True).stdout.strip()
    return {"model": sysctl("hw.model"), "chip": sysctl("machdep.cpu.brand_string"),
            "memoryGB": round(int(sysctl("hw.memsize") or 0) / 2**30),
            "os": platform.mac_ver()[0]}


def parse_arm(text: str) -> dict:
    label, _, command = text.partition("=")
    argv = shlex.split(command)
    if not label or not argv or "{audio}" not in command or "{json}" not in command:
        raise argparse.ArgumentTypeError("arm is label=command with {audio} and {json}")
    binary = Path(argv[0])
    return {"label": label, "argv": argv,
            "binarySha256": sha256(binary) if binary.exists() else None}


def cmd_plan(args) -> int:
    items = []
    for manifest_path in args.manifest:
        manifest = json.loads(manifest_path.read_text())
        root = manifest_path.parent.resolve()
        for item in manifest["items"]:
            items.append({**item, "audio": str(root / item["audio"]), "ref": str(root / item["ref"])})
    arms = args.arm
    labels = [a["label"] for a in arms]
    if len(set(labels)) != len(labels):
        print("error: arm labels repeat", file=sys.stderr)
        return 2
    rng = random.Random(args.seed)
    order = []
    for repeat in range(1, args.runs + 1):
        for item in items:
            if repeat > 1 and args.repeat_corpora and item["corpus"] not in args.repeat_corpora:
                continue
            arm_order = labels[:]
            rng.shuffle(arm_order)
            order += [{"item": item["id"], "arm": a, "run": repeat} for a in arm_order]
    plan = {
        "schemaVersion": SCHEMA,
        "created": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "commit": git("rev-parse", "HEAD"),
        "dirty": bool(git("status", "--porcelain")),
        "hardware": hardware(),
        "baseline": labels[0],
        "candidates": labels[1:],
        "primaryCandidate": args.primary or (labels[1] if len(labels) > 1 else None),
        "arms": arms,
        "wrap": args.wrap if args.wrap is not None else DEFAULT_WRAP,
        "seed": args.seed,
        "rules": {"primary": PRIMARY.as_dict(), "secondary": [r.as_dict() for r in SECONDARY]},
        "gate": DEFAULT_GATE,
        "items": items,
        "order": order,
        "notes": args.note or [],
    }
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "plan.json").write_text(json.dumps(plan, indent=1, sort_keys=True) + "\n")
    print(f"plan: {len(items)} items, {len(arms)} arms, {len(order)} runs -> {args.out / 'plan.json'}")
    return 0


# --- run -------------------------------------------------------------------------

def output_path(out: Path, arm: str, item: str, run: int) -> Path:
    return out / "runs" / arm / f"{item}.r{run}.json"


def cmd_run(args) -> int:
    plan_path = args.plan.resolve()
    out = plan_path.parent
    plan = json.loads(plan_path.read_text())
    items = {i["id"]: i for i in plan["items"]}
    arms = {a["label"]: a for a in plan["arms"]}
    for arm in plan["arms"]:
        binary = Path(arm["argv"][0])
        if arm["binarySha256"] and sha256(binary) != arm["binarySha256"]:
            print(f"error: {binary} changed since the plan was written", file=sys.stderr)
            return 2
    log = out / "run-log.jsonl"
    todo = [o for o in plan["order"]
            if not output_path(out, o["arm"], o["item"], o["run"]).exists()]
    print(f"{len(plan['order']) - len(todo)} done, {len(todo)} to run")
    failures = 0
    for k, entry in enumerate(todo, 1):
        item, arm = items[entry["item"]], arms[entry["arm"]]
        target = output_path(out, entry["arm"], entry["item"], entry["run"])
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_suffix(".partial.json")
        argv = [a.replace("{audio}", item["audio"]).replace("{json}", str(partial))
                 .replace("{label}", entry["arm"]) for a in arm["argv"]]
        started = time.time()
        proc = subprocess.run(plan["wrap"] + argv, capture_output=True, text=True)
        wall = time.time() - started
        ok = proc.returncode == 0 and partial.exists()
        if ok:
            partial.rename(target)
        else:
            failures += 1
            partial.unlink(missing_ok=True)
        with log.open("a") as f:
            f.write(json.dumps({**entry, "exit": proc.returncode, "ok": ok, "wallS": round(wall, 3),
                                "stderr": proc.stderr[-2000:],
                                "at": dt.datetime.now().astimezone().isoformat(timespec="seconds")},
                               sort_keys=True) + "\n")
        print(f"[{k}/{len(todo)}] {entry['arm']:<12} {entry['item']:<28} r{entry['run']} "
              f"{'ok' if ok else 'FAILED'} {wall:6.1f} s", flush=True)
    return 1 if failures else 0


# --- score -----------------------------------------------------------------------

def fingerprint(spans: list[dict]) -> str:
    return hashlib.sha256(json.dumps(
        [(round(s["start"], 3), round(s["end"], 3), s["speaker"]) for s in spans]).encode()).hexdigest()


def failed_runs(out: Path) -> list[dict]:
    log = out / "run-log.jsonl"
    if not log.exists():
        return []
    last = {}
    for line in log.read_text().splitlines():
        e = json.loads(line)
        last[(e["arm"], e["item"], e["run"])] = e
    return [e for e in last.values() if not e["ok"]]


def cmd_score(args) -> int:
    out = args.plan.resolve().parent
    plan = json.loads(args.plan.read_text())
    primary = dm.Rules(**plan["rules"]["primary"])
    secondary = [dm.Rules(**r) for r in plan["rules"]["secondary"]]
    rows = []
    missing = []
    for item in plan["items"]:
        ref = der.read_rttm(Path(item["ref"]))
        for arm in plan["arms"]:
            for run in sorted({o["run"] for o in plan["order"]
                               if o["item"] == item["id"] and o["arm"] == arm["label"]}):
                path = output_path(out, arm["label"], item["id"], run)
                if not path.exists():
                    missing.append(f"{arm['label']}/{item['id']}.r{run}")
                    continue
                data = json.loads(path.read_text())
                hyp = [der.Segment(float(s["start"]), float(s["end"]), str(s["speaker"]))
                       for s in data["spans"]]
                row = {
                    "item": item["id"], "corpus": item["corpus"], "arm": arm["label"], "run": run,
                    "refSpeakers": item["refSpeakers"], "durationS": item["durationS"],
                    "primary": dm.evaluate(ref, hyp, primary),
                    "secondary": [dm.evaluate(ref, hyp, r) for r in secondary] if run == 1 else [],
                    "timestampProblems": dm.timestamp_problems(data["spans"], item["durationS"]),
                    "diarizeMs": data.get("diarizeMs"), "prepareMs": data.get("prepareMs"),
                    "peakFootprintMB": round(data.get("peakFootprintBytes", 0) / 2**20, 1),
                    "rtf": round(data["diarizeMs"] / 1000 / item["durationS"], 5)
                           if data.get("diarizeMs") else None,
                    "fingerprint": fingerprint(data["spans"]),
                    "spanCount": len(data["spans"]),
                }
                rows.append(row)
                print(f"{arm['label']:<12} {item['id']:<28} r{run} "
                      f"DER {row['primary']['der'] * 100 if row['primary']['der'] is not None else float('nan'):6.2f}%",
                      flush=True)
    scores = {"plan": str(args.plan.resolve()), "planSha256": sha256(args.plan.resolve()),
              "missing": missing,
              "failedRuns": failed_runs(out), "rows": rows}
    (out / "scores.json").write_text(json.dumps(scores, indent=1, sort_keys=True) + "\n")
    (out / "report.md").write_text(render_report(plan, scores))
    print(f"wrote {out / 'scores.json'} and report.md ({len(missing)} missing)")
    return 0


def pct(x) -> str:
    return "—" if x is None else f"{x * 100:.2f}%"


def by_arm_corpus(rows: list[dict], run: int = 1) -> dict:
    out: dict = {}
    for r in rows:
        if r["run"] == run:
            out.setdefault((r["arm"], r["corpus"]), []).append(r)
    return out


def render_report(plan: dict, scores: dict) -> str:
    rows = scores["rows"]
    labels = [a["label"] for a in plan["arms"]]
    corpora = list(dict.fromkeys(i["corpus"] for i in plan["items"]))
    groups = by_arm_corpus(rows)
    L = [f"# Diarization comparison", "",
         f"Commit `{plan['commit'][:10]}`{' (dirty)' if plan['dirty'] else ''}, "
         f"{plan['hardware']['model']} {plan['hardware']['chip']} {plan['hardware']['memoryGB']} GB, "
         f"macOS {plan['hardware']['os']}. Baseline `{plan['baseline']}`.", "",
         f"Primary rules: {dm.Rules(**plan['rules']['primary']).describe()}.", ""]
    if scores["missing"] or scores["failedRuns"]:
        L += [f"**Missing outputs: {len(scores['missing'])}; failed runs: {len(scores['failedRuns'])}.**", ""]

    L += ["## Pooled DER by corpus (run 1)", "",
          "| Corpus | Arm | Files | DER | Missed | False alarm | Confusion | DER, overlap only | DER, single-speaker only | Overlap share |",
          "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for c in corpora:
        for a in labels:
            g = groups.get((a, c), [])
            if not g:
                continue
            p = dm.pooled([r["primary"] for r in g])
            share = p["overlap"]["speech_s"] / p["speech_s"] if p["speech_s"] else None
            L.append(f"| {c} | {a} | {p['files']} | {pct(p['der'])} | {pct(p['missed'])} | "
                     f"{pct(p['false_alarm'])} | {pct(p['confusion'])} | {pct(p['overlap']['der'])} | "
                     f"{pct(p['single']['der'])} | {pct(share)} |")
    L += ["", "## Other scoring rules (run 1, pooled DER)", "",
          "| Corpus | Arm | " + " | ".join(
              f"collar {r['collar']} s, overlap {'skipped' if r['skip_overlap'] else 'scored'}"
              for r in plan["rules"]["secondary"]) + " |",
          "| --- | --- |" + " ---: |" * len(plan["rules"]["secondary"])]
    for c in corpora:
        for a in labels:
            g = groups.get((a, c), [])
            if not g:
                continue
            cells = [pct(dm.pooled([r["secondary"][k] for r in g])["der"])
                     for k in range(len(plan["rules"]["secondary"]))]
            L.append(f"| {c} | {a} | " + " | ".join(cells) + " |")

    L += ["", "## Speakers, merges, fragments (run 1)", "",
          "| Corpus | Arm | Files with a wrong count | Sum of count errors | Merged reference speakers | Fragmented reference speakers | Overlap detection recall | precision |",
          "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for c in corpora:
        for a in labels:
            g = groups.get((a, c), [])
            if not g:
                continue
            p = dm.pooled([r["primary"] for r in g])
            rec = [r["primary"]["overlap"]["detection_recall"] for r in g
                   if r["primary"]["overlap"]["detection_recall"] is not None]
            prec = [r["primary"]["overlap"]["detection_precision"] for r in g
                    if r["primary"]["overlap"]["detection_precision"] is not None]
            L.append(f"| {c} | {a} | {p['count_errors']} | "
                     f"{sum(r['primary']['speakers']['count_error'] for r in g):+d} | "
                     f"{p['merged_ref_speakers']} | {p['fragmented_ref_speakers']} | "
                     f"{pct(statistics.mean(rec)) if rec else '—'} | {pct(statistics.mean(prec)) if prec else '—'} |")

    L += ["", "## By number of reference speakers (run 1, pooled over all corpora)", "",
          "| Speakers | Arm | Files | DER | Confusion | Merged | Fragmented |",
          "| ---: | --- | ---: | ---: | ---: | ---: | ---: |"]
    for n in sorted({r["refSpeakers"] for r in rows}):
        for a in labels:
            g = [r for r in rows if r["run"] == 1 and r["arm"] == a and r["refSpeakers"] == n]
            if not g:
                continue
            p = dm.pooled([r["primary"] for r in g])
            L.append(f"| {n} | {a} | {len(g)} | {pct(p['der'])} | {pct(p['confusion'])} | "
                     f"{p['merged_ref_speakers']} | {p['fragmented_ref_speakers']} |")

    L += ["", "## Runtime and memory (all runs)", "",
          "| Corpus | Arm | Median speaker-pass RTF | Median diarize s | Median load s | Max peak footprint MB |",
          "| --- | --- | ---: | ---: | ---: | ---: |"]
    for c in corpora:
        for a in labels:
            g = [r for r in rows if r["arm"] == a and r["corpus"] == c]
            if not g:
                continue
            L.append(f"| {c} | {a} | {statistics.median(r['rtf'] for r in g):.4f} | "
                     f"{statistics.median(r['diarizeMs'] for r in g) / 1000:.1f} | "
                     f"{statistics.median(r['prepareMs'] for r in g) / 1000:.2f} | "
                     f"{max(r['peakFootprintMB'] for r in g):.0f} |")
    L += ["", "Peak footprint is process memory. Core ML weights held by the Neural Engine or GPU "
          "are not all inside it, so it is not model residency.", ""]

    L += ["## Repeat stability", "", "| Arm | Repeated files | Identical output | Max DER spread |",
          "| --- | ---: | ---: | ---: |"]
    for a in labels:
        pairs = repeat_pairs(rows, a)
        if not pairs:
            continue
        same = sum(1 for x, y in pairs if x["fingerprint"] == y["fingerprint"])
        spread = max((abs(x["primary"]["der"] - y["primary"]["der"]) for x, y in pairs
                      if x["primary"]["der"] is not None and y["primary"]["der"] is not None),
                     default=0.0)
        L.append(f"| {a} | {len(pairs)} | {same} | {spread * 100:.2f} pt |")

    L += ["", "## Per file (run 1)", "",
          "| File | Ref speakers | " + " | ".join(f"{a} DER (hyp speakers)" for a in labels) + " |",
          "| --- | ---: |" + " ---: |" * len(labels)]
    for item in plan["items"]:
        cells = []
        for a in labels:
            r = next((r for r in rows if r["item"] == item["id"] and r["arm"] == a and r["run"] == 1), None)
            cells.append("—" if r is None else
                         f"{pct(r['primary']['der'])} ({r['primary']['speakers']['hyp']})"
                         + (" M" if r["primary"]["merged_ref_speakers"] else "")
                         + (" F" if r["primary"]["fragmented_ref_speakers"] else ""))
        L.append(f"| {item['id']} | {item['refSpeakers']} | " + " | ".join(cells) + " |")
    L += ["", "M: at least two reference speakers merged. F: at least one reference speaker fragmented.", ""]
    return "\n".join(L) + "\n"


def repeat_pairs(rows: list[dict], arm: str) -> list[tuple[dict, dict]]:
    by = {}
    for r in rows:
        if r["arm"] == arm:
            by.setdefault(r["item"], {})[r["run"]] = r
    return [(runs[1], runs[2]) for runs in by.values() if 1 in runs and 2 in runs]


def cmd_rescore(args) -> int:
    """Score outputs that already exist against other references, by meeting name."""
    out = args.plan.resolve().parent
    plan = json.loads(args.plan.read_text())
    rules = [dm.Rules(**plan["rules"]["primary"])] + [dm.Rules(**r) for r in plan["rules"]["secondary"]]
    labels = [a["label"] for a in plan["arms"]]
    results: dict = {a: {k: [] for k in range(len(rules))} for a in labels}
    used = []
    for item in plan["items"]:
        if item["corpus"] != args.corpus:
            continue
        name = item["id"].split("-", 1)[1]
        ref_path = args.refs / f"{name}.rttm"
        if not ref_path.exists():
            print(f"error: no {ref_path}", file=sys.stderr)
            return 2
        ref = der.read_rttm(ref_path)
        used.append({"item": item["id"], "ref": str(ref_path), "sha256": sha256(ref_path)})
        for a in labels:
            hyp = der.read_spans_json(output_path(out, a, item["id"], 1))
            for k, r in enumerate(rules):
                results[a][k].append(dm.evaluate(ref, hyp, r))
    head = [f"collar {r.collar} s, overlap {'skipped' if r.skip_overlap else 'scored'}" for r in rules]
    lines = [f"# {args.corpus} against {args.label}", "", f"References: `{args.refs}`. {args.note or ''}", "",
             "| Arm | " + " | ".join(f"DER, {h}" for h in head) + " | Missed | False alarm | Confusion | Merged |",
             "| --- |" + " ---: |" * (len(rules) + 4)]
    summary = {}
    for a in labels:
        pooled = [dm.pooled(results[a][k]) for k in range(len(rules))]
        summary[a] = pooled
        p = pooled[0]
        lines.append(f"| {a} | " + " | ".join(pct(x["der"]) for x in pooled)
                     + f" | {pct(p['missed'])} | {pct(p['false_alarm'])} | {pct(p['confusion'])} | "
                     f"{p['merged_ref_speakers']} |")
    (out / f"rescore-{args.label}.json").write_text(json.dumps(
        {"references": used, "rules": [r.as_dict() for r in rules], "pooled": summary},
        indent=1, sort_keys=True) + "\n")
    (out / f"rescore-{args.label}.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


# --- residency -------------------------------------------------------------------

def footprint_sample(pid: int) -> dict:
    """`footprint -j` of one process, in MB: the total, the Neural Engine
    categories and the graphics (IOAccelerator / IOSurface) categories, every column."""
    import tempfile
    with tempfile.TemporaryDirectory() as directory:
        target = Path(directory) / "fp.json"
        proc = subprocess.run(["footprint", "-p", str(pid), "-j", str(target)],
                              capture_output=True, text=True)
        if proc.returncode != 0 or not target.exists():
            return {}
        try:
            doc = json.loads(target.read_text())
        except json.JSONDecodeError:
            return {}
    procs = doc.get("processes") or []
    if not procs:
        return {}
    cats = procs[0].get("categories") or {}

    def total(match) -> float:
        return sum(sum(c.get(k, 0) for k in ("dirty", "clean", "swapped"))
                   for name, c in cats.items() if match(name.lower())) / 2**20
    return {"footprintMB": procs[0].get("footprint", 0) / 2**20,
            "neuralMB": total(lambda n: "neural" in n),
            "graphicsMB": total(lambda n: "ioaccelerator" in n or "iosurface" in n or "gpu" in n),
            "allCategoriesMB": total(lambda n: True)}


def cmd_residency(args) -> int:
    out = args.plan.resolve().parent
    plan = json.loads(args.plan.read_text())
    item = next(i for i in plan["items"] if i["id"] == args.item)
    results = []
    for repeat in range(1, args.runs + 1):
        for arm in plan["arms"]:
            target = out / "residency" / f"{arm['label']}.{item['id']}.r{repeat}.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            argv = [a.replace("{audio}", item["audio"]).replace("{json}", str(target))
                     .replace("{label}", arm["label"]) for a in arm["argv"]]
            # The lock is taken by a wrapper around this sampler's whole run, so
            # the sampled process is the diarizer itself.
            proc = subprocess.Popen(plan["wrap"][1:] + argv if plan["wrap"][:1] == [DEFAULT_WRAP[0]]
                                    else plan["wrap"] + argv)
            peak: dict = {}
            samples = 0
            while proc.poll() is None:
                for pid in child_pids(proc.pid) + [proc.pid]:
                    got = footprint_sample(pid)
                    if got:
                        samples += 1
                        for k, v in got.items():
                            peak[k] = max(peak.get(k, 0.0), v)
                time.sleep(args.interval)
            results.append({"arm": arm["label"], "item": item["id"], "run": repeat,
                            "exit": proc.returncode, "samples": samples,
                            **{f"max{k[0].upper()}{k[1:]}": round(v, 1) for k, v in peak.items()}})
            print(json.dumps(results[-1], sort_keys=True), flush=True)
    (out / "residency.json").write_text(json.dumps(results, indent=1, sort_keys=True) + "\n")
    return 0 if all(r["exit"] == 0 and r["samples"] for r in results) else 1


def child_pids(pid: int) -> list[int]:
    """Every descendant of `pid` (sandbox-exec execs in place, but a wrapper may not)."""
    found, frontier = [], [pid]
    while frontier:
        parent = frontier.pop()
        proc = subprocess.run(["pgrep", "-P", str(parent)], capture_output=True, text=True)
        kids = [int(x) for x in proc.stdout.split()]
        found += kids
        frontier += kids
    return found


# --- identity --------------------------------------------------------------------

IDENTITY_VARIANTS = ("mute-opener", "trim-head", "noise40", "aac64")


def build_variants(item: dict, vdir: Path) -> list[tuple[str, Path, Path]]:
    """The speaker_stability variants of one item, as 16 kHz WAVs every arm reads."""
    import speaker_stability as ss
    stem = item["id"]
    want = [(t, vdir / f"{stem}.{t}.wav", vdir / f"{stem}.{t}.rttm") for t in IDENTITY_VARIANTS]
    if all(w.exists() and r.exists() for _, w, r in want):
        return want
    vdir.mkdir(parents=True, exist_ok=True)
    src = vdir / f"{stem}.wav"
    shutil.copyfile(item["audio"], src)
    shutil.copyfile(item["ref"], vdir / f"{stem}.rttm")
    ss.variants_of(stem, src, vdir / f"{stem}.rttm", vdir)
    aac = vdir / f"{stem}.aac64.m4a"
    if aac.exists():
        to_wav16(aac, vdir / f"{stem}.aac64.wav")
        aac.unlink()
    src.unlink()
    (vdir / f"{stem}.rttm").unlink()
    return want


def cmd_identity(args) -> int:
    import speaker_stability as ss
    out = args.plan.resolve().parent
    plan = json.loads(args.plan.read_text())
    corpora = set(plan["gate"]["identityCorpora"])
    rows, failures = [], 0
    for item in plan["items"]:
        if item["corpus"] not in corpora:
            continue
        variants = build_variants(item, out / "identity" / "variants")
        ref = der.read_rttm(Path(item["ref"]))
        for arm in plan["arms"]:
            base = output_path(out, arm["label"], item["id"], 1)
            if not base.exists():
                print(f"error: run first; no {base}", file=sys.stderr)
                return 2
            old = der.read_spans_json(base)
            for tag, wav, rttm in variants:
                target = out / "identity" / arm["label"] / f"{item['id']}.{tag}.json"
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    argv = [a.replace("{audio}", str(wav)).replace("{json}", str(target))
                             .replace("{label}", arm["label"]) for a in arm["argv"]]
                    proc = subprocess.run(plan["wrap"] + argv + ["--carry-from", str(base)],
                                          capture_output=True, text=True)
                    if proc.returncode != 0 or not target.exists():
                        failures += 1
                        print(f"FAILED {arm['label']} {item['id']} {tag}: {proc.stderr[-300:]}")
                        continue
                new = json.loads(target.read_text())
                result = ss.stability(ref, old, der.read_rttm(rttm),
                                      der.read_spans_json(target), new.get("carry"))
                rows.append({"arm": arm["label"], "item": item["id"], "corpus": item["corpus"],
                             "variant": tag, **result})
                print(f"{arm['label']:<12} {item['id']:<28} {tag:<12} carry wrong "
                      f"{result['carry']['wrong']:5.1f}%  label wrong {result['label']['wrong']:5.1f}%",
                      flush=True)
    (out / "identity.json").write_text(json.dumps({"rows": rows, "failures": failures,
                                                   "planSha256": sha256(args.plan.resolve())},
                                                  indent=1, sort_keys=True) + "\n")
    print(f"wrote {out / 'identity.json'}")
    return 1 if failures else 0


def identity_summary(rows: list[dict], arm: str) -> dict:
    """Pooled seconds under a right, wrong and no name, policy carry and label."""
    out = {}
    for policy in ("carry", "label"):
        totals = {"right": 0.0, "wrong": 0.0, "default": 0.0}
        for r in rows:
            if r["arm"] != arm:
                continue
            seconds = r[policy]["seconds"]
            for k in totals:
                totals[k] += r[policy][k] / 100 * seconds
        whole = sum(totals.values())
        out[policy] = {k: (round(100 * v / whole, 2) if whole else None) for k, v in totals.items()}
        out[policy]["seconds"] = round(whole, 1)
    out["runs"] = sum(1 for r in rows if r["arm"] == arm)
    return out


# --- decide ----------------------------------------------------------------------

def decide(plan: dict, scores: dict, identity_rows: list[dict] | None = None) -> dict:
    gate = plan["gate"]
    rows = scores["rows"]
    base = plan["baseline"]
    result = {"baseline": base, "candidates": {}}
    expected = {(o["arm"], o["item"], o["run"]) for o in plan["order"]}
    present = {(r["arm"], r["item"], r["run"]) for r in rows}
    for cand in plan["candidates"]:
        checks = {}
        for corpus in gate["realCorpora"]:
            b = [r["primary"] for r in rows if r["arm"] == base and r["corpus"] == corpus and r["run"] == 1]
            c = [r["primary"] for r in rows if r["arm"] == cand and r["corpus"] == corpus and r["run"] == 1]
            if not b or not c or len(b) != len(c):
                checks[f"relativeDerImprovement:{corpus}"] = {"pass": False, "why": "not scored on every file"}
                continue
            bd, cd = dm.pooled(b)["der"], dm.pooled(c)["der"]
            rel = (bd - cd) / bd if bd else None
            checks[f"relativeDerImprovement:{corpus}"] = {
                "pass": rel is not None and rel >= gate["minRelativeDerImprovement"],
                "baselineDer": bd, "candidateDer": cd, "relative": None if rel is None else round(rel, 4)}
        worse = []
        for item in plan["items"]:
            b = next((r for r in rows if r["arm"] == base and r["item"] == item["id"] and r["run"] == 1), None)
            c = next((r for r in rows if r["arm"] == cand and r["item"] == item["id"] and r["run"] == 1), None)
            if b and c and c["primary"]["merged_ref_speakers"] - b["primary"]["merged_ref_speakers"] \
                    > gate["maxMergedSpeakersIncrease"]:
                worse.append(item["id"])
        checks["noNewMerges"] = {"pass": not worse, "files": worse}
        mine = [r for r in rows if r["arm"] == cand]
        bad_ts = sorted({r["item"] for r in mine if r["timestampProblems"]})
        checks["timestampsValid"] = {"pass": not bad_ts, "files": bad_ts}
        peak = max((r["peakFootprintMB"] for r in mine), default=None)
        checks["peakFootprint"] = {"pass": peak is not None and peak <= gate["maxPeakFootprintMB"], "maxMB": peak}
        real = [r["rtf"] for r in mine if r["corpus"] in gate["realCorpora"] and r["rtf"] is not None]
        med = statistics.median(real) if real else None
        checks["realTimeFactor"] = {"pass": med is not None and med <= gate["maxMedianRealTimeFactor"],
                                    "median": med}
        pairs = repeat_pairs(rows, cand)
        unscorable = [x["item"] for x, y in pairs
                      if x["primary"]["der"] is None or y["primary"]["der"] is None]
        spread = max((abs(x["primary"]["der"] - y["primary"]["der"]) for x, y in pairs
                      if x["item"] not in unscorable), default=None)
        checks["repeatStable"] = {
            "pass": bool(pairs) and not unscorable and spread is not None
                    and spread <= gate["maxRepeatDerSpread"],
            "pairs": len(pairs), "maxSpread": spread, "unscorable": unscorable}
        missing = sorted(f"{a}/{i}.r{k}" for a, i, k in expected - present if a in (base, cand))
        failed = [f"{e['arm']}/{e['item']}.r{e['run']}" for e in scores["failedRuns"]
                  if e["arm"] in (base, cand)]
        checks["allRunsScored"] = {"pass": not missing and not failed, "missing": missing, "failed": failed}
        ident = identity_rows
        if ident is None:
            checks["speakerNamesCarry"] = {"pass": False, "why": "identity not run"}
        else:
            b, c = identity_summary(ident, base), identity_summary(ident, cand)
            bw, cw = b["carry"]["wrong"], c["carry"]["wrong"]
            checks["speakerNamesCarry"] = {
                "pass": bw is not None and cw is not None and c["runs"] == b["runs"] > 0
                        and cw <= bw + gate["maxWrongNameIncreasePoints"],
                "baselineWrongPct": bw, "candidateWrongPct": cw, "runs": c["runs"]}
        passed = all(c["pass"] for c in checks.values())
        result["candidates"][cand] = {"checks": checks, "passesGate": passed}
    primary = plan.get("primaryCandidate")
    ok = primary in result["candidates"] and result["candidates"][primary]["passesGate"]
    result["recommendation"] = (
        f"{primary} passes every measured check; replacement also needs the speaker-name "
        "persistence suite and an offline test of the FluidAudio upgrade" if ok else
        f"keep {base}: {primary} does not pass the gate")
    return result


def cmd_decide(args) -> int:
    out = args.plan.resolve().parent
    plan = json.loads(args.plan.read_text())
    scores_path = out / "scores.json"
    if not scores_path.exists():
        print("error: run `score` first", file=sys.stderr)
        return 2
    plan_hash = sha256(args.plan.resolve())
    scores = json.loads(scores_path.read_text())
    if scores.get("planSha256") != plan_hash:
        print("error: scores.json was not made from this plan; run `score` again", file=sys.stderr)
        return 2
    identity_path = out / "identity.json"
    identity_rows = None
    if identity_path.exists():
        data = json.loads(identity_path.read_text())
        if data.get("planSha256") == plan_hash and not data["failures"]:
            identity_rows = data["rows"]
    result = decide(plan, scores, identity_rows)
    (out / "decision.json").write_text(json.dumps(result, indent=1, sort_keys=True) + "\n")
    lines = [f"# Decision", "", f"**{result['recommendation']}**", ""]
    for cand, r in result["candidates"].items():
        lines += [f"## {cand}: {'passes' if r['passesGate'] else 'does not pass'}", "",
                  "| Check | Pass | Detail |", "| --- | --- | --- |"]
        for name, c in r["checks"].items():
            detail = {k: v for k, v in c.items() if k != "pass"}
            lines.append(f"| {name} | {'yes' if c['pass'] else '**no**'} | `{json.dumps(detail, sort_keys=True)[:300]}` |")
        lines.append("")
    (out / "decision.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("prepare-ami"); a.add_argument("--src", type=Path, required=True); a.add_argument("--work", type=Path, required=True)
    b = sub.add_parser("prepare-liva"); b.add_argument("--src", type=Path, required=True); b.add_argument("--work", type=Path, required=True)
    c = sub.add_parser("prepare-synthetic"); c.add_argument("--fixtures", type=Path, required=True)
    c.add_argument("--work", type=Path, required=True); c.add_argument("--corpus", required=True)
    d = sub.add_parser("plan")
    d.add_argument("--manifest", type=Path, action="append", required=True)
    d.add_argument("--arm", type=parse_arm, action="append", required=True)
    d.add_argument("--primary", help="the candidate the recommendation is about (default: the second arm)")
    d.add_argument("--runs", type=int, default=2)
    d.add_argument("--repeat-corpora", nargs="*", help="corpora that get runs after the first (default: all)")
    d.add_argument("--seed", type=int, default=20261102)
    d.add_argument("--wrap", nargs="*", default=None)
    d.add_argument("--note", action="append")
    d.add_argument("--out", type=Path, required=True)
    for name in ("run", "score", "identity", "decide"):
        s = sub.add_parser(name); s.add_argument("--plan", type=Path, required=True)
    q = sub.add_parser("residency"); q.add_argument("--plan", type=Path, required=True)
    q.add_argument("--item", required=True); q.add_argument("--runs", type=int, default=2)
    q.add_argument("--interval", type=float, default=0.5)
    r = sub.add_parser("rescore"); r.add_argument("--plan", type=Path, required=True)
    r.add_argument("--corpus", required=True); r.add_argument("--refs", type=Path, required=True)
    r.add_argument("--label", required=True); r.add_argument("--note")
    args = p.parse_args(argv)
    if args.cmd == "prepare-ami":
        return prepare_ami(args.src, args.work)
    if args.cmd == "prepare-liva":
        return prepare_liva(args.src, args.work)
    if args.cmd == "prepare-synthetic":
        return prepare_synthetic(args.fixtures, args.work, args.corpus)
    return {"plan": cmd_plan, "run": cmd_run, "score": cmd_score,
            "identity": cmd_identity, "decide": cmd_decide, "rescore": cmd_rescore,
            "residency": cmd_residency}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
