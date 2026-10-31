"""Model residency, measured from OUTSIDE the `transcribe` process.

The process footprint that `transcribe` has always printed is not what a loaded
model costs. On the synthetic clip, after loading large-v3-turbo, `phys_footprint`
was 77 MB while `footprint(1)` showed 1581 MB owned by the process as "neural,
nofootprint": memory CoreML placed on the Neural Engine. Calling the 77 MB (or
the "approximately 300 MB" in older docs) "memory use" would make the model look
free, and a build with a smaller footprint would look like a build that needs
less memory when it may need exactly as much.

This script launches `transcribe`, samples `footprint(1)` and `ps` against it
about every half second, timestamps the lines it writes to stderr, and reports
the memory at the stages that matter: before the model loads, right after, and
the peak during the decode. A sampler this coarse can miss the instant before
the load; the in-process snapshots in `transcribe`'s JSON (`memory`, from
`MemorySnapshot`) are exact for the stages, and this script is the independent
check on them. It also takes `vm_stat` snapshots of the whole
machine. Those are SYSTEM-WIDE and noisy: anything else running on this Mac
moves them, so read only large, consistent changes and never quote a delta as
the model's size. The per-process `footprint` figures are the ones to quote.

    residency.py --bin app/.build/release/transcribe \\
        --audio eval/audio/synthetic-taglish.wav --out /tmp/residency.json

Standard library only. Takes /tmp/notero-team/bench-lock.sh unless --no-lock.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

LOCK_SCRIPT = Path("/tmp/notero-team/bench-lock.sh")
MB = 1024 * 1024


def parse_footprint_json(document: dict) -> dict:
    """The numbers worth keeping from `footprint -j`, in megabytes.

    Neural Engine memory shows up as categories whose name contains "neural"
    (for example "Owned physical footprint (unmapped) (neural) (nofootprint)"),
    and as `neural_peak` in the auxiliary data. Categories are summed over every
    column, because the weights show up under "clean", not "dirty".
    """
    processes = document.get("processes") or []
    if not processes:
        return {}
    process = processes[0]
    neural = 0
    categories = process.get("categories") or {}
    for name, columns in categories.items():
        if "neural" in name.lower():
            neural += sum(columns.get(key, 0) for key in ("dirty", "clean", "swapped"))
    auxiliary = process.get("auxiliary") or {}
    out = {
        "footprint_mb": process.get("footprint", 0) / MB,
        "neural_mb": neural / MB,
    }
    for key in ("neural_peak", "phys_footprint", "phys_footprint_peak"):
        if key in auxiliary:
            out[f"{key}_mb"] = auxiliary[key] / MB
    return out


def parse_vm_stat(text: str) -> dict:
    """`vm_stat` output as megabytes, by name. Pages are 16 KiB on Apple silicon;
    the header says which, so it is read and not assumed."""
    match = re.search(r"page size of (\d+) bytes", text)
    page = int(match.group(1)) if match else 16384
    wanted = {
        "Pages free": "free_mb",
        "Pages active": "active_mb",
        "Pages inactive": "inactive_mb",
        "Pages wired down": "wired_mb",
        "Pages occupied by compressor": "compressor_mb",
        "File-backed pages": "file_backed_mb",
        "Anonymous pages": "anonymous_mb",
    }
    out = {}
    for line in text.splitlines():
        name, _, value = line.partition(":")
        if name in wanted:
            out[wanted[name]] = int(value.strip().rstrip(".")) * page / MB
    return out


def stage_table(samples: list[dict], marks: dict[str, float]) -> dict:
    """Memory at the stages, from timestamped samples and timestamped log lines.

    `marks` holds seconds since launch: `load_start`, `load_end`, `decode_end`.
    A stage with no sample around it is absent, not interpolated."""
    def last_before(t):
        found = [s for s in samples if s["t"] < t and "footprint_mb" in s]
        return found[-1] if found else None

    def first_after(t):
        found = [s for s in samples if s["t"] >= t and "footprint_mb" in s]
        return found[0] if found else None

    table: dict = {}
    if "load_start" in marks and (s := last_before(marks["load_start"])):
        table["before_model_load"] = s
    if "load_end" in marks and (s := first_after(marks["load_end"])):
        table["after_model_load"] = s
    during = [s for s in samples if s["t"] >= marks.get("load_end", float("inf"))
              and s["t"] <= marks.get("decode_end", float("inf")) and "footprint_mb" in s]
    if during:
        table["peak_during_decode"] = {
            "footprint_mb": max(s["footprint_mb"] for s in during),
            "neural_mb": max(s.get("neural_mb", 0) for s in during),
            "rss_mb": max(s.get("rss_mb", 0) for s in during),
        }
    return table


def sample_footprint(pid: int) -> dict:
    with tempfile.TemporaryDirectory() as directory:
        target = Path(directory) / "fp.json"
        proc = subprocess.run(["footprint", "-p", str(pid), "-j", str(target)],
                              capture_output=True, text=True)
        if proc.returncode != 0 or not target.exists():
            return {}
        try:
            return parse_footprint_json(json.loads(target.read_text()))
        except json.JSONDecodeError:
            return {}


def sample_rss_mb(pid: int) -> float | None:
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout
    return int(out.strip()) / 1024 if out.strip().isdigit() else None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bin", required=True, type=Path)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--interval", type=float, default=0.25)
    parser.add_argument("--out", type=Path, help="write the full result as JSON")
    parser.add_argument("--no-lock", action="store_true")
    parser.add_argument("--extra", nargs=argparse.REMAINDER, default=[])
    args = parser.parse_args(argv)

    cmd = [str(args.bin.resolve()), "--audio", str(args.audio.resolve()), "--no-diarize",
           "--json", tempfile.mktemp(suffix=".json", prefix="residency-")]
    if args.live:
        cmd.append("--live")
    cmd += args.extra
    use_lock = LOCK_SCRIPT.exists() and not args.no_lock
    if use_lock:
        cmd = [str(LOCK_SCRIPT)] + cmd

    vm_before = parse_vm_stat(subprocess.run(["vm_stat"], capture_output=True, text=True).stdout)
    began = time.monotonic()
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    marks: dict[str, float] = {}
    lines: list[tuple[float, str]] = []

    def read_stderr() -> None:
        for line in proc.stderr:
            t = time.monotonic() - began
            lines.append((t, line.rstrip()))
            if "Loading large-v3" in line or re.search(r"^\s+Loading .*…", line):
                marks.setdefault("load_start", t)
            if line.strip() == "Ready":
                marks.setdefault("load_end", t)
            if line.startswith("decoded "):
                marks["decode_end"] = t

    reader = threading.Thread(target=read_stderr, daemon=True)
    reader.start()

    # With the lock, the transcribe process is a child of bench-lock.sh; find it
    # by name once it exists, because footprint needs the real pid.
    samples: list[dict] = []
    vm_samples: list[dict] = []
    target_pid = None
    while proc.poll() is None:
        if target_pid is None:
            if not use_lock:
                target_pid = proc.pid
            else:
                found = subprocess.run(["pgrep", "-f", f"{args.bin.resolve()} --audio"],
                                       capture_output=True, text=True).stdout.split()
                candidates = [int(p) for p in found if int(p) not in (os.getpid(), proc.pid)]
                target_pid = candidates[-1] if candidates else None
            if target_pid is None:
                time.sleep(args.interval)
                continue
        t = time.monotonic() - began
        sample = sample_footprint(target_pid)
        if sample:
            sample["t"] = t
            sample["rss_mb"] = sample_rss_mb(target_pid) or 0
            samples.append(sample)
            vm_samples.append({"t": t, **parse_vm_stat(
                subprocess.run(["vm_stat"], capture_output=True, text=True).stdout)})
        time.sleep(args.interval)
    reader.join(timeout=5)
    vm_after = parse_vm_stat(subprocess.run(["vm_stat"], capture_output=True, text=True).stdout)

    stages = stage_table(samples, marks)
    result = {
        "command": cmd, "returncode": proc.returncode, "marks_s": marks,
        "sample_count": len(samples), "interval_s": args.interval,
        "stages": stages, "vm_stat_before": vm_before, "vm_stat_after": vm_after,
        "vm_stat_samples": vm_samples, "samples": samples,
        "note": ("Per-process figures come from footprint(1). vm_stat is system-wide and shared "
                 "with every other process on this Mac: it is context, not the model's size."),
    }
    if args.out:
        args.out.write_text(json.dumps(result, indent=2))

    print(f"{len(samples)} footprint samples, exit code {proc.returncode}")
    for name, row in stages.items():
        print(f"  {name:<20} footprint {row.get('footprint_mb', 0):7.0f} MB   "
              f"neural {row.get('neural_mb', 0):7.0f} MB   rss {row.get('rss_mb', 0):7.0f} MB")
    peak = max((s.get("neural_peak_mb", 0) for s in samples), default=0)
    peak_fp = max((s.get("phys_footprint_peak_mb", 0) for s in samples), default=0)
    print(f"  footprint(1) neural_peak {peak:.0f} MB, phys_footprint_peak {peak_fp:.0f} MB")
    if args.out:
        print(f"wrote {args.out}")
    return 0 if proc.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
