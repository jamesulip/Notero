#!/usr/bin/env python3
"""One-command regression comparison of two `transcribe` builds.

    python3 eval/regress.py --base addf5f8 --cand HEAD --suite quick
    python3 eval/regress.py --base /path/to/transcribe --cand WORKTREE --suite full
    python3 eval/regress.py determinism --bin HEAD --runs 8
    python3 eval/regress.py --base X --cand Y --confirm-with REPORT-OF-SESSION-1/report.json

BASE and CAND are either an executable `transcribe`, a git revision (built from
`git archive` into a scratch directory outside the repository, cached by commit),
or the word WORKTREE (the working copy's `app/`, built the same way). Nothing is
built inside the repository.

What it does, in order:

  1. Resolves both builds and the fixtures (`eval/fixtures.json`: the synthetic
     Taglish clip, the paused clip, the synthetic multi-speaker clips, and the public
     FLEURS subset when /tmp/notero-data/fleurs exists; anything unavailable is
     skipped and said so).
  2. Runs every series INTERLEAVED, A B B A A B B A ..., in batches. A batch is
     whole ABBA blocks, so each arm sees the same machine in every batch, and the
     bench lock (/tmp/notero-team/bench-lock.sh, when present) is taken once per
     batch, not once per run: a per-run ticket behind five other agents' multi-minute
     holds waited from 3 minutes to over half an hour per run.
  3. Records, per series, the load average at every launch and the `uptime`,
     `vm_stat` and `memory_pressure` snapshots before and after.
  4. Decides with ONE rule (benchstats.decide: rank-sum permutation tests, Holm over
     every tested metric together, effect-size floors, timing believed only on a quiet
     machine) and ONE collapse rule (benchstats.COLLAPSE_RULE), and writes ONE report
     (report.md) and its data (report.json) into the output directory, beside the
     raw runs. `--reanalyze DIR` redoes step 4 on stored runs when the rule changes.

A single session only ever SUSPECTS a difference. Re-run the same command later and
pass the first report with `--confirm-with`: a metric is CONFIRMED only when the
second session reproduces it. See docs/BENCHMARKS.md for the measured false-positive
rate, and docs/CLI.md for the options.

Suites: quick = the synthetic clip offline and live (n = 8 per arm) and DER on two
synthetic multi-speaker clips; full adds the paused clip live, the other multi-speaker
clips and the FLEURS subset. Everything except FLEURS is SYNTHETIC.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import bench_runs as br  # noqa: E402
import benchstats as bs  # noqa: E402
import der as der_module  # noqa: E402
import fixtures as fx  # noqa: E402
import regresslib as rl  # noqa: E402

REPO = HERE.parent
DEFAULT_FLEURS = Path("/tmp/notero-data/fleurs")
DEFAULT_RUNS = 8
HOLD_SECONDS = 240

#: Series the suites are made of. `est_s` is one run's wall time on the Mac mini
#: M2 Pro, model load included, used only to size a lock hold.
SERIES = {
    "offline-synthetic": {"kind": "asr", "fixture": "synthetic-taglish", "mode": "offline", "est_s": 16},
    "live-synthetic": {"kind": "asr", "fixture": "synthetic-taglish", "mode": "live", "est_s": 70},
    "live-paused": {"kind": "asr", "fixture": "synthetic-taglish-paused", "mode": "live", "est_s": 100,
                    "reference_fixture": "synthetic-taglish"},
    "offline-fleurs": {"kind": "asr", "fixture": "fleurs-fil-ph-subset", "mode": "offline", "est_s": 30,
                       "optional": True},
    "der-quick": {"kind": "der", "fixtures": ["ms-two-distinct", "ms-three-voices"], "rounds": 2,
                  "est_s": 25},
    "der-full": {"kind": "der", "fixtures": ["ms-two-distinct", "ms-two-similar", "ms-two-short-turns",
                                              "ms-chunk-fusion", "ms-three-voices", "ms-four-voices",
                                              "ms-three-overlap"], "rounds": 3, "est_s": 25},
}
SUITES = {
    "quick": ["offline-synthetic", "live-synthetic", "der-quick"],
    "full": ["offline-synthetic", "live-synthetic", "live-paused", "offline-fleurs", "der-full"],
}

#: DER differences below this many points are not reported as a change (the same
#: floor as `benchstats.METRICS["der"]`).
DER_FLOOR = bs.METRICS["der"]["floor_abs"]


# --------------------------------------------------------------------------
# The machine: load and memory (macOS commands guarded; Linux gets load only)
# --------------------------------------------------------------------------

def parse_vm_stat(text: str) -> dict:
    """Pages by state and the cumulative pageout counter from `vm_stat`."""
    page = re.search(r"page size of (\d+) bytes", text)
    out: dict = {"page_size": int(page.group(1)) if page else None}
    for key, label in (("free_pages", "Pages free"), ("active_pages", "Pages active"),
                       ("inactive_pages", "Pages inactive"), ("wired_pages", "Pages wired down"),
                       ("compressed_pages", "Pages occupied by compressor"),
                       ("pageouts", "Pageouts")):
        match = re.search(rf"^{re.escape(label)}:\s+(\d+)", text, re.MULTILINE)
        if match:
            out[key] = int(match.group(1))
    return out


def parse_memory_pressure(text: str) -> int | None:
    match = re.search(r"System-wide memory free percentage:\s*(\d+)%", text)
    return int(match.group(1)) if match else None


def _run_text(cmd: list[str], timeout: float = 20) -> str | None:
    if shutil.which(cmd[0]) is None:
        return None
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return None


def system_snapshot(platform_name: str | None = None) -> dict:
    """Load and memory state now. `uptime` and the load averages everywhere; on
    macOS also `vm_stat` and `memory_pressure`. Missing tools give missing keys."""
    platform_name = platform_name or sys.platform
    snap: dict = {"time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    try:
        snap["loadavg"] = [round(x, 2) for x in os.getloadavg()]
    except OSError:
        snap["loadavg"] = None
    uptime = _run_text(["uptime"])
    if uptime:
        snap["uptime"] = uptime.strip()
    if platform_name == "darwin":
        memory: dict = {}
        vm = _run_text(["vm_stat"])
        if vm:
            memory.update(parse_vm_stat(vm))
        pressure = _run_text(["memory_pressure"], timeout=30)
        if pressure:
            memory["free_percentage"] = parse_memory_pressure(pressure)
        if memory:
            snap["memory"] = memory
    return snap


def system_summary(before: dict | None, after: dict | None) -> dict:
    out = {"before": before, "after": after}
    pre = ((before or {}).get("memory") or {}).get("pageouts")
    post = ((after or {}).get("memory") or {}).get("pageouts")
    if pre is not None and post is not None:
        out["pageouts_delta"] = post - pre
    return out


# --------------------------------------------------------------------------
# Resolving a build
# --------------------------------------------------------------------------

def default_scratch() -> Path:
    """$NOTERO_REGRESS_SCRATCH, else /tmp/notero-regress (the team's convention, and
    shared between runs), else a directory under the system temp directory. On macOS
    the system temp directory is a per-user /var/folders path, and a build cache
    that moves with $TMPDIR is a build cache that rebuilds for nothing."""
    if os.environ.get("NOTERO_REGRESS_SCRATCH"):
        return Path(os.environ["NOTERO_REGRESS_SCRATCH"])
    shared = Path("/tmp")
    if shared.is_dir() and os.access(shared, os.W_OK):
        return shared / "notero-regress"
    return Path(tempfile.gettempdir()) / "notero-regress"


def _git(args: list[str], cwd: Path = REPO, runner=subprocess.run) -> str:
    done = runner(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {done.stderr.strip()}")
    return done.stdout.strip()


def _archive_into(commit: str, destination: Path, repo: Path) -> None:
    """`git archive COMMIT app`, unpacked into DESTINATION: the committed files
    only, whatever the working tree holds."""
    data = subprocess.run(["git", "-C", str(repo), "archive", commit, "app"],
                          capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        try:
            tar.extractall(destination, filter="data")      # Python 3.12+ (and security releases)
        except TypeError:
            tar.extractall(destination)


def _worktree_digest(repo: Path) -> str:
    """A hash of every file under app/ that the build reads (sources, manifest,
    resolved packages), so a changed working copy is a new build."""
    digest = hashlib.sha256()
    app = repo / "app"
    for path in sorted(p for p in app.rglob("*") if p.is_file()
                       and ".build" not in p.relative_to(app).parts):
        digest.update(str(path.relative_to(app)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()[:16]


class _BuildLock:
    """Exclusive right to build into one cache directory. Two `regress.py` processes that
    want the same commit must not both `rmtree` and rebuild it: the second would delete
    the first's half-built tree. A directory with the holder's pid; a holder that has died
    is cleared; a waiter polls until the holder is done."""

    def __init__(self, path: Path, *, poll: float = 2.0, limit: float = 3600.0):
        self.path, self.poll, self.limit = path, poll, limit

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        waited = 0.0
        while True:
            try:
                self.path.mkdir()
                (self.path / "pid").write_text(str(os.getpid()))
                return self
            except FileExistsError:
                try:
                    holder = int((self.path / "pid").read_text())
                    os.kill(holder, 0)
                except (OSError, ValueError):
                    shutil.rmtree(self.path, ignore_errors=True)       # holder gone: stale
                    continue
                if waited >= self.limit:
                    raise RuntimeError(f"another process (pid {holder}) has been building here for "
                                       f"{self.limit:.0f} s: {self.path}")
                time.sleep(self.poll)
                waited += self.poll

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)


def resolve_binary(spec: str, *, scratch: Path, repo: Path = REPO, build: bool = True,
                   runner=subprocess.run) -> dict:
    """An executable `transcribe` from SPEC: a file path, a git revision, or WORKTREE.

    A revision is built with `swift build -c release --product transcribe` in
    `scratch/builds/<full sha>/app` after `git archive`, and reused on the next call.
    Returns {"spec", "path", "label", "commit", "built"}.
    """
    candidate = Path(spec).expanduser()
    if candidate.is_file():
        if not os.access(candidate, os.X_OK):
            raise RuntimeError(f"{candidate} is not executable")
        return {"spec": spec, "path": str(candidate.resolve()), "label": f"{candidate.name}",
                "commit": None, "built": False}
    if spec == "WORKTREE":
        if not (repo / "app" / "Package.swift").is_file():
            raise RuntimeError(f"no app/Package.swift under {repo}")
        key = f"worktree-{_worktree_digest(repo)}"
        head = _git(["rev-parse", "--short", "HEAD"], repo)
        label, commit = f"WORKTREE (on {head}, {key[9:]})", None
        directory = scratch / "builds" / key

        def fill() -> None:
            shutil.copytree(repo / "app", directory / "app",
                            ignore=shutil.ignore_patterns(".build"))
    else:
        try:
            commit = _git(["rev-parse", "--verify", f"{spec}^{{commit}}"], repo)
        except RuntimeError as error:
            raise RuntimeError(f"{spec!r} is neither an executable file nor a git revision "
                               f"of {repo}: {error}") from None
        subject = _git(["log", "-1", "--format=%h %s", commit], repo)
        label = subject if len(subject) < 70 else subject[:67] + "..."
        directory = scratch / "builds" / commit

        def fill() -> None:
            _archive_into(commit, directory, repo)

    binary = directory / "app" / ".build" / "release" / "transcribe"
    if binary.is_file():
        return {"spec": spec, "path": str(binary), "label": label, "commit": commit, "built": False}
    if not build:
        raise RuntimeError(f"{spec} is not built under {directory} and --no-build was given")
    if sys.platform != "darwin":
        raise RuntimeError("building `transcribe` needs macOS (Core ML, the Neural Engine)")
    with _BuildLock(directory.parent / f".{directory.name}.lock"):
        if binary.is_file():      # another process finished it while we waited
            return {"spec": spec, "path": str(binary), "label": label, "commit": commit, "built": False}
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        fill()
        print(f"building {label} in {directory} (release; the first build takes a few minutes)",
              file=sys.stderr, flush=True)
        log = directory / "build.log"
        with log.open("w") as handle:
            done = runner(["swift", "build", "-c", "release", "--product", "transcribe"],
                          cwd=directory / "app", stdout=handle, stderr=subprocess.STDOUT)
        if done.returncode != 0 or not binary.is_file():
            raise RuntimeError(f"swift build failed for {spec}; see {log}")
    return {"spec": spec, "path": str(binary), "label": label, "commit": commit, "built": True}


# --------------------------------------------------------------------------
# Planning (pure)
# --------------------------------------------------------------------------

def plan_batches(schedule: list[str], est_s: float, hold_seconds: float, *, block: int = 4) -> list[list[str]]:
    """Cut a schedule into lock holds of about `hold_seconds`, on ABBA block
    boundaries (`block` runs), so that every hold contains both arms equally.
    A hold is never shorter than one block."""
    if est_s <= 0 or hold_seconds <= 0:
        raise ValueError("est_s and hold_seconds must be positive")
    per_hold = max(block, int(hold_seconds // est_s) // block * block)
    return [schedule[i:i + per_hold] for i in range(0, len(schedule), per_hold)]


def plan_der_chunks(items: list, per_fixture: int, est_s: float, hold_seconds: float) -> list[list]:
    """Cut the DER work list (fixture after fixture, `per_fixture` runs each, both arms in
    order) into lock holds of about `hold_seconds`, always on a fixture boundary, so each
    hold contains both arms equally for every fixture it touches."""
    if est_s <= 0 or hold_seconds <= 0 or per_fixture < 1:
        raise ValueError("est_s, hold_seconds and per_fixture must be positive")
    per_hold = max(per_fixture, int(hold_seconds // est_s) // per_fixture * per_fixture)
    return [items[i:i + per_hold] for i in range(0, len(items), per_hold)]


SPAN_LINE = re.compile(r"^\s*span\s+(\d+\.\d+)-\s*(\d+\.\d+)\s+(\S+)\s+q=(-?\d+\.\d+)", re.MULTILINE)


def parse_spans(stderr: str) -> list[der_module.Segment]:
    """The raw speaker spans `transcribe` prints under TRANSCRIBE_DEBUG_SPANS=1."""
    return [der_module.Segment(float(m.group(1)), float(m.group(2)), m.group(3))
            for m in SPAN_LINE.finditer(stderr)]


# --------------------------------------------------------------------------
# Running (the worker holds the lock; the coordinator never runs a build itself)
# --------------------------------------------------------------------------

def run_der_once(*, binary: Path, audio: Path, rttm: Path, out_dir: Path, index: int,
                 arm: str, timeout: float, extra: list[str] | None = None) -> dict:
    """One diarization run: `transcribe` on a multi-speaker clip with the raw spans
    printed, scored against the clip's RTTM by `der.py`."""
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"run-{index:02d}"
    record: dict = {"schema": rl.SCHEMA, "index": index, "arm": arm, "kind": "der",
                    "started_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                    "loadavg_1m_at_launch": round(os.getloadavg()[0], 2)}
    env = dict(os.environ, TRANSCRIBE_DEBUG_SPANS="1")
    cmd = [str(binary), "--audio", str(audio), "--language", "en", "--out", str(out_dir / f"{stem}.txt"),
           *(extra or [])]
    began = time.monotonic()
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env,
                              stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        record.update(ok=False, error=f"timed out after {timeout:.0f} s")
    else:
        (out_dir / f"{stem}.stderr.txt").write_text(done.stderr)
        spans = parse_spans(done.stderr)
        if done.returncode != 0:
            record.update(ok=False, error=f"exit code {done.returncode}")
        elif not spans:
            record.update(ok=False, error="no speaker spans in the output: diarization did not run "
                                          "or this binary lacks TRANSCRIBE_DEBUG_SPANS")
        else:
            ref = der_module.read_segments(rttm)
            scored = der_module.score(ref, spans).as_dict()
            at_zero = der_module.score(ref, spans, collar=0.0).as_dict()
            record.update(ok=True, der=scored["der"], der_collar0=at_zero["der"],
                          missed=scored["missed"], false_alarm=scored["false_alarm"],
                          confusion=scored["confusion"], hyp_speakers=scored["hyp_speakers"],
                          ref_speakers=scored["ref_speakers"], spans=len(spans))
    record["wall_s"] = round(time.monotonic() - began, 1)
    record.setdefault("ok", False)
    (out_dir / f"{stem}.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return record


def run_work_order(order: dict) -> dict:
    """The worker side: run every item of a work order, no locking of its own (the
    process as a whole holds the bench lock), and report the machine before and after."""
    before = system_snapshot()
    done = 0
    for item in order["items"]:
        if item["kind"] == "der":
            run_der_once(binary=Path(item["binary"]), audio=Path(item["audio"]),
                         rttm=Path(item["rttm"]), out_dir=Path(item["out_dir"]),
                         index=item["index"], arm=item["arm"], timeout=item["timeout"],
                         extra=item.get("extra"))
        else:
            br.run_once(binary=Path(item["binary"]), audio=Path(item["audio"]), ref=Path(item["ref"]),
                        reference_text=Path(item["ref"]).read_text(), out_dir=Path(item["out_dir"]),
                        index=item["index"], mode=item["mode"], extra=item["extra"],
                        use_lock=False, timeout=item["timeout"], arm=item["arm"])
        done += 1
    return {"runs": done, "system": {"before": before, "after": system_snapshot()}}


def run_batch(items: list[dict], *, scratch: Path, use_lock: bool, tag: str) -> dict:
    """Run one batch of items in a child process, under the bench lock when asked."""
    work = scratch / "work"
    work.mkdir(parents=True, exist_ok=True)
    # unique per batch: two sessions that share an --out-dir name must not share a work file
    path = work / f"{tag}-{uuid.uuid4().hex[:8]}.json"
    path.write_text(json.dumps({"items": items}))
    cmd = [sys.executable, str(Path(__file__).resolve()), "_batch", str(path)]
    if use_lock:
        cmd = [str(br.LOCK_SCRIPT)] + cmd
    done = subprocess.run(cmd, stdin=subprocess.DEVNULL)
    result = path.with_suffix(".result.json")
    if done.returncode != 0 or not result.exists():
        raise RuntimeError(f"a batch of {len(items)} runs exited with code {done.returncode}")
    out = json.loads(result.read_text())
    path.unlink(missing_ok=True)
    result.unlink(missing_ok=True)
    return out


# --------------------------------------------------------------------------
# Series
# --------------------------------------------------------------------------

def collect_fixtures(args, series_id: str, definition: dict, scratch: Path) -> dict:
    """Audio and reference paths for one series, or raise fx.FixtureUnavailable."""
    search = [Path(p) for p in (args.fixture_dir or [])] + [REPO / "eval" / "audio"] \
        + [Path(p) for p in os.environ.get("NOTERO_FIXTURE_DIRS", "").split(os.pathsep) if p] \
        + [scratch / "fixtures"]
    manifest = fx.load_manifest()
    fixtures = fx.by_id(manifest)

    def audio_of(fixture_id: str) -> tuple[Path, dict]:
        if fixture_id == "fleurs-fil-ph-subset":
            fleurs = Path(args.fleurs_dir or DEFAULT_FLEURS)
            built = fx.build_fleurs_subset(fleurs, args.fleurs_clips, scratch / "fixtures")
            return built["audio"], {"sha256": built["sha256"], "source": "built from FLEURS",
                                    "reference": built["reference"], "clips": built["clips"]}
        path, info = fx.resolve(fixture_id, search=search, scratch=scratch / "fixtures", manifest=manifest)
        return path, info

    if definition["kind"] == "der":
        files = {}
        for fixture_id in definition["fixtures"]:
            audio, info = audio_of(fixture_id)
            rttm = audio.parent / fixtures[fixture_id]["reference"].split("/")[-1]
            files[fixture_id] = {"audio": str(audio), "rttm": str(rttm), "sha256": info.get("sha256"),
                                 "matches_manifest": info.get("matches_manifest")}
        return {"files": files}
    audio, info = audio_of(definition["fixture"])
    if definition["fixture"] == "fleurs-fil-ph-subset":
        reference = Path(info["reference"])
    else:
        reference_id = definition.get("reference_fixture", definition["fixture"])
        reference = REPO / fixtures[reference_id]["reference"]
    entry = fixtures[definition["fixture"]]
    return {"audio": str(audio), "reference": str(reference), "sha256": info.get("sha256"),
            "matches_manifest": info.get("matches_manifest"), "id": definition["fixture"],
            "synthetic": entry.get("synthetic", True), "reference_sha256": br.sha256_of(reference)}


def execute_asr_series(series_id: str, definition: dict, files: dict, binaries: dict, *,
                       args, out_dir: Path, scratch: Path, use_lock: bool, runs: int) -> dict:
    schedule = bs.interleave_schedule(runs, args.order)
    batches = plan_batches(schedule, definition["est_s"], args.hold_seconds)
    mode = definition["mode"]
    extra = list(args.extra or [])
    if args.models:
        extra += ["--models", args.models]
    counters = {"A": 0, "B": 0}
    systems = []
    series_dir = out_dir / series_id
    for number, batch in enumerate(batches, 1):
        items = []
        for arm in batch:
            counters[arm] += 1
            items.append({"kind": "asr", "arm": arm, "index": counters[arm], "binary": binaries[arm]["path"],
                          "audio": files["audio"], "ref": files["reference"], "mode": mode, "extra": extra,
                          "out_dir": str(series_dir / arm), "timeout": args.timeout})
        print(f"[{series_id}] batch {number}/{len(batches)}: {len(items)} runs "
              f"({''.join(batch)}), waiting for the bench lock" if use_lock else
              f"[{series_id}] batch {number}/{len(batches)}: {len(items)} runs ({''.join(batch)})",
              file=sys.stderr, flush=True)
        systems.append(run_batch(items, scratch=scratch, use_lock=use_lock,
                                 tag=f"{out_dir.name}-{series_id}-{number}")["system"])
    return {"schedule": "".join(schedule), "batches": [len(b) for b in batches],
            "system": system_summary(systems[0]["before"], systems[-1]["after"]) if systems else None}


def execute_der_series(series_id: str, definition: dict, files: dict, binaries: dict, *,
                       args, out_dir: Path, scratch: Path, use_lock: bool, rounds: int) -> dict:
    series_dir = out_dir / series_id
    systems = []
    per_fixture_schedule = bs.interleave_schedule(rounds, "abba" if rounds % 2 == 0 else "abab")
    items = []
    counters: dict[tuple[str, str], int] = {}
    for fixture_id, info in files["files"].items():
        for arm in per_fixture_schedule:
            counters[(fixture_id, arm)] = counters.get((fixture_id, arm), 0) + 1
            items.append({"kind": "der", "arm": arm, "index": counters[(fixture_id, arm)],
                          "binary": binaries[arm]["path"], "audio": info["audio"], "rttm": info["rttm"],
                          "out_dir": str(series_dir / fixture_id / arm), "timeout": args.timeout,
                          "extra": list(args.extra or []) + (["--models", args.models] if args.models else [])})
    chunks = plan_der_chunks(items, len(per_fixture_schedule), definition["est_s"], args.hold_seconds)
    for number, chunk in enumerate(chunks, 1):
        print(f"[{series_id}] batch {number}/{len(chunks)}: {len(chunk)} diarization runs",
              file=sys.stderr, flush=True)
        systems.append(run_batch(chunk, scratch=scratch, use_lock=use_lock,
                                 tag=f"{out_dir.name}-{series_id}-{number}")["system"])
    return {"schedule": "".join(per_fixture_schedule), "batches": [len(c) for c in chunks],
            "system": system_summary(systems[0]["before"], systems[-1]["after"]) if systems else None}


# --------------------------------------------------------------------------
# Analysis (pure given the stored runs)
# --------------------------------------------------------------------------

def analyze_der(base: dict[str, list[dict]], cand: dict[str, list[dict]]) -> dict:
    """DER per fixture, base against candidate. DER is a deterministic function of
    the diarizer's output, so with the same binary and file it should not vary: where
    it does not, a difference is exact, and where it does, the row says so and is
    descriptive only. No p-value: r runs per arm is too few, and it is not needed
    when every run of an arm agrees."""
    rows = []
    for fixture_id in base:
        a = [r["der"] for r in base[fixture_id] if r.get("ok")]
        b = [r["der"] for r in cand.get(fixture_id, []) if r.get("ok")]
        if not a or not b:
            rows.append({"id": fixture_id, "base": a, "cand": b, "diff": 0.0, "deterministic": False,
                         "status": "no successful runs on one side"})
            continue
        deterministic = len({round(x, 9) for x in a}) == 1 and len({round(x, 9) for x in b}) == 1
        diff = bs.median(b) - bs.median(a)
        speakers_a = sorted({r.get("hyp_speakers") for r in base[fixture_id] if r.get("ok")})
        speakers_b = sorted({r.get("hyp_speakers") for r in cand[fixture_id] if r.get("ok")})
        if abs(diff) < DER_FLOOR - 1e-12:
            status = "no change" if abs(diff) < 1e-12 else f"differs by less than the {DER_FLOOR * 100:g}-point floor"
        elif deterministic:
            status = "**CHANGED (exact: every run of each arm agrees)**"
        else:
            # Two or three rounds of a varying DER say nothing about a difference: by
            # simulation, "same direction every round" is a false alarm on 18-38% of fixtures
            # whose spread is a few points. Descriptive only; use --rounds 8 or more and read
            # the medians, or fix the nondeterminism first.
            status = "differs, but DER varies run to run: descriptive only, not flagged"
        rows.append({"id": fixture_id, "base": a, "cand": b, "diff": diff, "deterministic": deterministic,
                     "hyp_speakers": {"base": speakers_a, "cand": speakers_b},
                     "changed": status.startswith("**"),
                     "worse": status.startswith("**") and diff > 0, "status": status})
    return {"note": ("DER of the raw diarizer spans against the synthetic RTTM, collar 0.25 s (`der.py`). "
                     "SYNTHETIC text-to-speech clips with exact boundaries: this supports A/B between two "
                     "builds, not a claim about real meetings. Not part of the Holm family; "
                     f"a change is reported at {DER_FLOOR * 100:g} points or more."),
            "fixtures": rows,
            "changed": [r["id"] for r in rows if r.get("changed")]}


def read_arm_records(directory: Path) -> list[dict]:
    return [r for r in br.load_records(directory)] if directory.is_dir() else []


def build_result(plan: dict, out_dir: Path) -> dict:
    """Everything the report says, from the plan and the stored raw runs alone."""
    base_info, cand_info = plan["identity"]["base_info"], plan["identity"]["cand_info"]
    series_out: list[dict] = []
    warnings: list[str] = list(plan.get("warnings", []))
    skipped: list[str] = list(plan.get("skipped", []))
    incomplete: list[str] = []
    der_result = None
    determinism: list[dict] = []
    models: set[str] = set()
    for series_id, entry in plan["series"].items():
        definition = entry["definition"]
        if definition["kind"] == "der":
            base, cand = {}, {}
            for fixture_id in entry["files"]["files"]:
                for arm, store in (("A", base), ("B", cand)):
                    store[fixture_id] = br.load_records(out_dir / series_id / fixture_id / arm) \
                        if (out_dir / series_id / fixture_id / arm).is_dir() else []
            der_result = analyze_der(base, cand)
            for row in der_result["fixtures"]:
                if "no successful runs" in row["status"]:
                    incomplete.append(f"{series_id}: {row['id']}: {row['status']}")
            der_result["series"] = series_id
            der_result["rounds"] = definition["rounds"]
            der_result["system"] = entry.get("run", {}).get("system")
            continue
        records = {arm: read_arm_records(out_dir / series_id / arm) for arm in "AB"}
        ok = {arm: [r for r in records[arm] if r.get("ok")] for arm in "AB"}
        failed = {arm: len(records[arm]) - len(ok[arm]) for arm in "AB"}
        if not ok["A"] or not ok["B"]:
            incomplete.append(f"{series_id}: no successful runs on "
                              f"{'the base' if not ok['A'] else 'the candidate'} side, not compared")
            warnings.append(f"series {series_id}: no successful runs on "
                            f"{'the base' if not ok['A'] else 'the candidate'} side; not compared "
                            f"(errors: {[r.get('error') for r in records['A' if not ok['A'] else 'B']][:3]})")
            continue
        for arm, label in (("A", "base"), ("B", "candidate")):
            if failed[arm]:
                incomplete.append(f"{series_id}: {failed[arm]} {label} run(s) failed and are excluded")
                warnings.append(f"series {series_id}: {failed[arm]} {label} run(s) failed and are "
                                f"excluded: {[r.get('error') for r in records[arm] if not r.get('ok')][:3]}")
        for arm in "AB":
            models.update(m for m in (r["report"].get("model") for r in ok[arm]) if m)
        ref_words = ok["A"][0]["score"]["ref_words"]
        arm_a = rl.arm_from_rows([rl.row_from_record(r) for r in ok["A"]], label=base_info["label"],
                                 ref_words=ref_words)
        arm_b = rl.arm_from_rows([rl.row_from_record(r) for r in ok["B"]], label=cand_info["label"],
                                 ref_words=ok["B"][0]["score"]["ref_words"])
        series = rl.compare_series(series_id, definition["mode"], arm_a, arm_b)
        series["fixture"] = {k: entry["files"].get(k) for k in ("id", "sha256", "synthetic", "matches_manifest")}
        series["system"] = (entry.get("run") or {}).get("system")
        series["schedule"] = (entry.get("run") or {}).get("schedule")
        series_out.append(series)
        if entry["files"].get("matches_manifest") is False:
            warnings.append(f"series {series_id}: the audio's sha256 differs from eval/fixtures.json "
                            f"(a different macOS or voice build): results are valid for this A/B but "
                            f"not comparable with earlier ones")
        for arm, label, info in (("A", "base", base_info), ("B", "candidate", cand_info)):
            reports = [r["report"] for r in ok[arm]]
            if len(reports) >= 2:
                det = rl.analyze_determinism(reports, label=f"{label} {info['label']} / {series_id}")
                det["series"] = series_id
                det["arm"] = arm
                determinism.append(det)
    result = {
        "schema": rl.SCHEMA, "kind": "notero-regress-report", "suite": plan["suite"],
        "identity": {"base": base_info["label"], "cand": cand_info["label"],
                     "base_info": base_info, "cand_info": cand_info,
                     "same_binary": base_info["path"] == cand_info["path"]
                     or base_info.get("sha256") == cand_info.get("sha256")},
        "environment": plan["environment"], "model": sorted(models)[0] if len(models) == 1 else sorted(models),
        "lock_used": plan["lock_used"],
        "interleave": plan["interleave"], "series": series_out, "der": der_result,
        "determinism": determinism, "warnings": warnings, "skipped": skipped, "incomplete": incomplete,
        "plan": {k: plan[k] for k in ("args",) if k in plan},
    }
    if result["identity"]["same_binary"]:
        warnings.append("base and candidate are the SAME binary: this is an A/A comparison, so every "
                        "flag below is a false positive by construction")
    if not plan["lock_used"]:
        warnings.append("the bench lock was not used (absent or --no-lock): timings are valid only if "
                        "nothing else ran on this Mac during the series")
    confirm_with = None
    refusal = None
    if plan.get("confirm_with"):
        confirm_with = json.loads(Path(plan["confirm_with"]).read_text())
        first = confirm_with.get("identity", {})
        if first.get("base_info", {}).get("sha256") != base_info.get("sha256") \
                or first.get("cand_info", {}).get("sha256") != cand_info.get("sha256"):
            refusal = ("the first session compared different binaries, so a second session of THIS pair "
                       "confirms nothing about it")
        elif (confirm_with.get("interleave") or {}).get("id") == plan["interleave"]["id"]:
            refusal = ("this is the first session itself (same interleave id): a result does not "
                       "confirm itself; run a second, independent session")
    evaluated = rl.evaluate(series_out, interleaved=True,
                            confirm_with=None if refusal else confirm_with)
    result.update(evaluated)
    if refusal:
        result["confirmation"] = {"results": [], "confirmed": [], "not_reproduced": [], "refused": refusal}
        warnings.append("confirmation refused: " + refusal)
    for series in series_out:
        for m in series.get("skipped_metrics", []):
            warnings.append(f"series {series['id']}: {m['label']} is reported by only one build "
                            f"(missing in the {m['missing_in']}); not tested")
    if incomplete:
        result["decision"]["headline"] = (
            "INCOMPLETE (" + "; ".join(incomplete) + "): this verdict covers only what ran. "
            + result["decision"]["headline"])
    if der_result and der_result["changed"]:
        worse = [r["id"] for r in der_result["fixtures"] if r.get("worse")]
        better = [r["id"] for r in der_result["fixtures"] if r.get("changed") and not r.get("worse")]
        sentence = " DER " + "; ".join(filter(None, [
            f"HIGHER (worse) on {', '.join(worse)}" if worse else "",
            f"LOWER (better) on {', '.join(better)}" if better else ""])) + \
            f" by at least {DER_FLOOR * 100:g} points (synthetic clips; see the DER section)."
        result["decision"]["headline"] += sentence
    if plan.get("baseline"):
        baseline = json.loads(Path(plan["baseline"]).read_text())
        result["baseline"] = {"path": plan["baseline"], "name": baseline.get("name")}
        env = plan["environment"]
        model = result["model"] if isinstance(result["model"], str) else None
        hashes = {(s.get("fixture") or {}).get("id"): (s.get("fixture") or {}).get("sha256")
                  for s in series_out if (s.get("fixture") or {}).get("id")}
        drift = rl.drift_warnings(baseline, env, model=model, fixture_hashes=hashes)
        result["warnings"] += drift
        result["baseline_check"] = rl.baseline_check(baseline, series_out)
    result["warnings"] = list(dict.fromkeys(result["warnings"]))
    return result


def write_report(result: dict, out_dir: Path) -> None:
    (out_dir / "report.json").write_text(rl.dumps(result) + "\n")
    (out_dir / "report.md").write_text(rl.format_report(
        {**result, "determinism": result.get("determinism")}))


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def environment_record() -> dict:
    env = br.capture_environment()
    env["os_build"] = _run_text(["sw_vers", "-buildVersion"]) and _run_text(["sw_vers", "-buildVersion"]).strip()
    env["logical_cpus"] = os.cpu_count()
    env["platform"] = platform.platform()
    return env


def prepare_binary(spec: str, scratch: Path, *, build: bool) -> dict:
    info = resolve_binary(spec, scratch=scratch, build=build)
    info["sha256"] = br.sha256_of(Path(info["path"]))
    return info


def command_compare(args: argparse.Namespace) -> int:
    scratch = Path(args.scratch or default_scratch()).resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    baseline = json.loads(Path(args.baseline).read_text()) if args.baseline else None
    base_spec = args.base or (baseline or {}).get("base_commit")
    if not base_spec or not args.cand:
        print("error: give --base and --cand (a build, a git revision or WORKTREE); "
              "--base may be omitted when --baseline names a commit", file=sys.stderr)
        return 2
    series_ids = args.only or SUITES[args.suite]
    unknown = [s for s in series_ids if s not in SERIES]
    if unknown:
        print(f"error: unknown series {unknown}; known: {sorted(SERIES)}", file=sys.stderr)
        return 2

    base_info = prepare_binary(base_spec, scratch, build=not args.no_build)
    cand_info = base_info if args.cand == base_spec else prepare_binary(args.cand, scratch, build=not args.no_build)
    session = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = Path(args.out_dir or scratch / "reports" /
                   f"{session}-{(base_info.get('commit') or base_info['sha256'])[:8]}-"
                   f"{(cand_info.get('commit') or cand_info['sha256'])[:8]}").resolve()
    if out_dir.exists() and any(out_dir.iterdir()):
        print(f"error: {out_dir} is not empty; refusing to mix sessions. Use a new --out-dir.", file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)
    use_lock = br.LOCK_SCRIPT.exists() and not args.no_lock
    if not use_lock:
        print("note: running WITHOUT /tmp/notero-team/bench-lock.sh "
              + ("(--no-lock)" if args.no_lock else "(file not found)")
              + "; timings are only valid if nothing else uses this Mac", file=sys.stderr)

    plan: dict = {"suite": args.suite if not args.only else "custom: " + ",".join(args.only),
                  "args": {k: v for k, v in vars(args).items() if k != "func"},
                  "identity": {"base_info": base_info, "cand_info": cand_info},
                  "environment": environment_record(), "lock_used": use_lock,
                  "interleave": {"id": session, "scheme": args.order},
                  "series": {}, "warnings": [], "skipped": [],
                  "confirm_with": args.confirm_with, "baseline": args.baseline}
    binaries = {"A": base_info, "B": cand_info}
    for series_id in series_ids:
        definition = dict(SERIES[series_id])
        try:
            files = collect_fixtures(args, series_id, definition, scratch)
        except fx.FixtureUnavailable as error:
            plan["skipped"].append(f"{series_id}: {error}")
            print(f"skipping {series_id}: {error}", file=sys.stderr)
            continue
        if definition["kind"] == "der":
            definition["rounds"] = args.rounds or definition["rounds"]
        plan["series"][series_id] = {"definition": definition, "files": files}
    if not plan["series"]:
        print("error: no series could run (see the messages above)", file=sys.stderr)
        return 2
    (out_dir / "plan.json").write_text(rl.dumps(plan))
    if args.dry_run:
        for series_id, entry in plan["series"].items():
            definition = entry["definition"]
            runs = args.runs or DEFAULT_RUNS
            schedule = bs.interleave_schedule(runs, args.order) if definition["kind"] == "asr" else None
            batches = plan_batches(schedule, definition["est_s"], args.hold_seconds) if schedule else None
            print(f"{series_id}: {definition['kind']} "
                  + (f"{runs} runs per arm in {len(batches)} lock holds {[len(b) for b in batches]}"
                     if batches else f"{definition['rounds']} rounds on {len(entry['files']['files'])} fixtures"))
        print(f"base: {base_info['label']} ({base_info['path']})\ncand: {cand_info['label']} ({cand_info['path']})")
        return 0

    for series_id, entry in plan["series"].items():
        definition = entry["definition"]
        if definition["kind"] == "der":
            entry["run"] = execute_der_series(series_id, definition, entry["files"], binaries, args=args,
                                              out_dir=out_dir, scratch=scratch, use_lock=use_lock,
                                              rounds=definition["rounds"])
        else:
            entry["run"] = execute_asr_series(series_id, definition, entry["files"], binaries, args=args,
                                              out_dir=out_dir, scratch=scratch, use_lock=use_lock,
                                              runs=args.runs or DEFAULT_RUNS)
        (out_dir / "plan.json").write_text(rl.dumps(plan))
    result = build_result(plan, out_dir)
    write_report(result, out_dir)
    print(rl.format_report(result))
    print(f"report: {out_dir / 'report.md'}\ndata:   {out_dir / 'report.json'}", file=sys.stderr)
    if result["incomplete"]:
        print("exit 1: the session is INCOMPLETE (" + "; ".join(result["incomplete"]) + ")", file=sys.stderr)
    return 1 if result["incomplete"] else 0


def command_reanalyze(args: argparse.Namespace) -> int:
    out_dir = Path(args.directory).resolve()
    plan = json.loads((out_dir / "plan.json").read_text())
    if args.confirm_with:
        plan["confirm_with"] = args.confirm_with
    if args.baseline:
        plan["baseline"] = args.baseline
    result = build_result(plan, out_dir)
    write_report(result, out_dir)
    print(rl.format_report(result))
    return 0


def command_determinism(args: argparse.Namespace) -> int:
    scratch = Path(args.scratch or default_scratch()).resolve()
    info = prepare_binary(args.bin, scratch, build=not args.no_build)
    if args.audio:
        audio, reference = Path(args.audio).resolve(), Path(args.ref).resolve() if args.ref else None
        if reference is None:
            print("error: --audio needs --ref", file=sys.stderr)
            return 2
    else:
        try:
            files = collect_fixtures(args, "determinism", {"kind": "asr", "fixture": args.fixture}, scratch)
        except fx.FixtureUnavailable as error:
            print(f"unavailable: {error}", file=sys.stderr)
            return 3
        audio, reference = Path(files["audio"]), Path(files["reference"])
    out_dir = Path(args.out_dir or scratch / "determinism" /
                   datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")).resolve()
    if out_dir.exists() and any(out_dir.glob("run-*.json")):
        print(f"error: {out_dir} already holds runs; refusing to mix sessions. Use a new --out-dir.",
              file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)
    use_lock = br.LOCK_SCRIPT.exists() and not args.no_lock
    per_hold = max(1, int(args.hold_seconds // (16 if args.mode == "offline" else 70)))
    extra = list(args.extra or []) + (["--models", args.models] if args.models else [])
    done = 0
    while done < args.runs:
        count = min(per_hold, args.runs - done)
        items = [{"kind": "asr", "arm": "A", "index": done + i + 1, "binary": info["path"],
                  "audio": str(audio), "ref": str(reference), "mode": args.mode, "extra": extra,
                  "out_dir": str(out_dir), "timeout": args.timeout} for i in range(count)]
        run_batch(items, scratch=scratch, use_lock=use_lock, tag=f"{out_dir.name}-{done}")
        done += count
    records = [r for r in br.load_records(out_dir) if r.get("ok")]
    if not records:
        print("error: no run succeeded", file=sys.stderr)
        return 1
    result = rl.analyze_determinism([r["report"] for r in records], label=f"{info['label']} ({args.mode})")
    result["binary_sha256"] = info["sha256"]
    result["audio"] = str(audio)
    result["wer"] = [r["score"]["wer"] for r in records]
    (out_dir / "determinism.json").write_text(rl.dumps(result))
    text = rl.format_determinism(result)
    wers = ", ".join(f"{w * 100:.1f}" for w in result["wer"])
    print(text + f"\n\nWER of each run (%): {wers}")
    (out_dir / "determinism.md").write_text(text + f"\n\nWER of each run (%): {wers}\n")
    return 0 if result["identical"] else 1


def command_stream(args: argparse.Namespace) -> int:
    """N consecutive runs of ONE binary in lock-sized batches: the raw material of
    `calibrate_aa.py stream`. A/A needs real runs taken the way a comparison takes them."""
    scratch = Path(args.scratch or default_scratch()).resolve()
    info = prepare_binary(args.bin, scratch, build=not args.no_build)
    files = collect_fixtures(args, "stream", {"kind": "asr", "fixture": args.fixture}, scratch)
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    identity = {"binary_sha256": info["sha256"], "mode": args.mode, "fixture": args.fixture,
                "audio_sha256": files.get("sha256")}
    meta = out_dir / "stream.json"
    if meta.exists():
        if json.loads(meta.read_text()) != identity:
            print(f"error: {out_dir} holds a stream of a different binary, mode or fixture; "
                  f"refusing to continue it. Use a new --out-dir.", file=sys.stderr)
            return 2
    elif any(out_dir.glob("run-*.json")):
        print(f"error: {out_dir} holds runs that no stream.json describes; refusing to mix them.",
              file=sys.stderr)
        return 2
    meta.write_text(json.dumps(identity, indent=1))
    start = len(br.load_records(out_dir)) + 1 if any(out_dir.glob("run-*.json")) else 1
    use_lock = br.LOCK_SCRIPT.exists() and not args.no_lock
    per_hold = max(1, int(args.hold_seconds // (16 if args.mode == "offline" else 70)))
    done = start - 1
    while done < args.runs:
        count = min(per_hold, args.runs - done)
        items = [{"kind": "asr", "arm": "A", "index": done + i + 1, "binary": info["path"],
                  "audio": files["audio"], "ref": files["reference"], "mode": args.mode, "extra": [],
                  "out_dir": str(out_dir), "timeout": args.timeout} for i in range(count)]
        run_batch(items, scratch=scratch, use_lock=use_lock, tag=f"{out_dir.name}-{done}")
        done += count
        print(f"stream: {done}/{args.runs} runs", file=sys.stderr, flush=True)
    return 0


def command_save_baseline(args: argparse.Namespace) -> int:
    """Turn a report.json into a small committed baseline: per-run numbers only."""
    report = json.loads(Path(args.report).read_text())
    series = {}
    arms = {}
    for s in report["series"]:
        values = s["per_arm_values"]
        a, b = values["A"], values["B"]
        series[s["id"]] = {"mode": s["mode"], "base_arm": f"{s['id']}-base",
                           "stats": {key: bs.describe(a[key]) for key in ("wer", "rtf") if a.get(key)}}
        for arm, label, vals in (("base", "base", a), ("cand", "candidate", b)):
            arms[f"{s['id']}-{arm}"] = {"series": s["id"], "build": report["identity"][
                "base" if arm == "base" else "cand"], "n": len(vals.get("wer", [])),
                "values": {k: [round(v, 6) for v in vs] for k, vs in vals.items() if vs}}
    baseline = {
        "schema": rl.SCHEMA, "kind": "notero-baseline", "name": args.name, "what": args.what or "",
        "base_commit": (report["identity"]["base_info"] or {}).get("commit"),
        "environment": {k: report["environment"].get(k) for k in
                        ("hardware_model", "cpu", "memory_gb", "macos", "swift", "python", "date_utc")},
        "model": report.get("model"),
        "fixtures": {s["fixture"]["id"]: {k: s["fixture"].get(k) for k in ("sha256", "synthetic")}
                     for s in report["series"] if (s.get("fixture") or {}).get("id")},
        "provenance": {"report": str(args.report), "suite": report.get("suite"),
                       "base": report["identity"]["base"], "cand": report["identity"]["cand"]},
        "series": series, "arms": arms,
    }
    out = Path(args.out)
    out.write_text(json.dumps(rl.json_safe(baseline), indent=1, sort_keys=True) + "\n")
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    return 0


# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------

def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--scratch", help="where builds, fixtures and reports go "
                                          "(default $NOTERO_REGRESS_SCRATCH or /tmp/notero-regress)")
    parser.add_argument("--no-lock", action="store_true", help="do not use bench-lock.sh")
    parser.add_argument("--no-build", action="store_true", help="never build: fail if a revision is not built")
    parser.add_argument("--hold-seconds", type=float, default=HOLD_SECONDS,
                        help="aim for lock holds of about this long (default 240)")
    parser.add_argument("--timeout", type=float, default=900.0, help="seconds per run (default 900)")
    parser.add_argument("--models", help="passed to transcribe --models")
    parser.add_argument("--fixture-dir", action="append",
                        help="a directory to look for fixture audio in before generating it (repeatable)")
    parser.add_argument("--fleurs-dir", help=f"FLEURS Filipino (default {DEFAULT_FLEURS}); optional")
    parser.add_argument("--fleurs-clips", type=int, default=8, help="clips in the FLEURS subset (default 8)")
    parser.add_argument("--extra", nargs=argparse.REMAINDER, default=[],
                        help="everything after is passed to transcribe")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    compare = sub.add_parser("compare", help="interleaved A/B over a suite (the default command)")
    compare.add_argument("--base", help="baseline build: executable, git revision or WORKTREE")
    compare.add_argument("--cand", help="candidate build: executable, git revision or WORKTREE")
    compare.add_argument("--suite", choices=sorted(SUITES), default="quick")
    compare.add_argument("--only", nargs="+", metavar="SERIES", help=f"run only these series of {sorted(SERIES)}")
    compare.add_argument("--runs", type=int, help=f"runs per arm for ASR series (default {DEFAULT_RUNS})")
    compare.add_argument("--rounds", type=int, help="DER rounds per fixture and arm")
    compare.add_argument("--order", choices=("abab", "abba"), default="abba")
    compare.add_argument("--out-dir", help="default SCRATCH/reports/<session>-<base>-<cand>")
    compare.add_argument("--baseline", help="a committed baseline (eval/baselines/NAME.json): names the base "
                                            "commit when --base is omitted, and warns when this machine, OS, "
                                            "model or fixture differs from the one it came from")
    compare.add_argument("--confirm-with", help="report.json of an earlier session of the SAME pair: "
                                                "a metric it flagged is CONFIRMED only if this one reproduces it")
    compare.add_argument("--dry-run", action="store_true", help="resolve builds and fixtures, print the plan")
    add_common(compare)
    compare.set_defaults(func=command_compare)

    reanalyze = sub.add_parser("reanalyze", help="redo the analysis and report on a stored session")
    reanalyze.add_argument("directory")
    reanalyze.add_argument("--confirm-with")
    reanalyze.add_argument("--baseline")
    reanalyze.set_defaults(func=command_reanalyze)

    determinism = sub.add_parser("determinism", help="N runs of ONE build on one file: identical?")
    determinism.add_argument("--bin", required=True, help="executable, git revision or WORKTREE")
    determinism.add_argument("--runs", type=int, default=8)
    determinism.add_argument("--mode", choices=("offline", "live"), default="offline")
    determinism.add_argument("--fixture", default="synthetic-taglish")
    determinism.add_argument("--audio")
    determinism.add_argument("--ref")
    determinism.add_argument("--out-dir")
    add_common(determinism)
    determinism.set_defaults(func=command_determinism)

    stream = sub.add_parser("stream", help="consecutive runs of ONE build, for calibrate_aa.py")
    stream.add_argument("--bin", required=True)
    stream.add_argument("--runs", type=int, required=True)
    stream.add_argument("--mode", choices=("offline", "live"), default="offline")
    stream.add_argument("--fixture", default="synthetic-taglish")
    stream.add_argument("--out-dir", required=True)
    add_common(stream)
    stream.set_defaults(func=command_stream)

    save = sub.add_parser("save-baseline", help="write a small committed baseline from a report.json")
    save.add_argument("report")
    save.add_argument("--name", required=True)
    save.add_argument("--what", default="")
    save.add_argument("--out", required=True)
    save.set_defaults(func=command_save_baseline)

    batch = sub.add_parser("_batch", help=argparse.SUPPRESS)
    batch.add_argument("work")
    batch.set_defaults(func=lambda a: _batch_main(a.work))
    return parser


def _batch_main(work: str) -> int:
    path = Path(work)
    result = run_work_order(json.loads(path.read_text()))
    path.with_suffix(".result.json").write_text(json.dumps(result))
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    commands = {"compare", "reanalyze", "determinism", "stream", "save-baseline", "_batch", "-h", "--help"}
    if argv and argv[0] not in commands:
        argv = ["compare"] + argv      # `regress.py --base X --cand Y` is `compare`
    args = build_parser().parse_args(argv)
    if getattr(args, "runs", 1) is not None and getattr(args, "runs", 1) < 1:
        print("error: --runs must be at least 1", file=sys.stderr)
        return 2
    try:
        return args.func(args)
    except (RuntimeError, KeyError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
