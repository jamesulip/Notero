#!/usr/bin/env python3
"""The fixture set of the regression harness, and a driver that regenerates it.

`eval/fixtures.json` is the manifest: for each fixture its generator, the sha256
of the generated audio (when the generator is deterministic), its reference, a
`synthetic` flag, and what a number measured on it can and cannot support.

    python3 eval/fixtures.py list
    python3 eval/fixtures.py generate --out /tmp/fixtures [--only ID ...]
    python3 eval/fixtures.py verify /tmp/fixtures
    python3 eval/fixtures.py path synthetic-taglish --out /tmp/fixtures

Audio is never written inside the repository: `--out` is a scratch directory, and
the default is a new directory under the system temp directory. Generation needs
macOS (`say`, `afconvert`); on any other system the generators say so and the
harness skips the series that need them instead of failing.

Everything this generates is SYNTHETIC except the optional FLEURS subset, which
is public read speech, not a meeting.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
MANIFEST = HERE / "fixtures.json"
SAMPLE_RATE = 16_000


class FixtureUnavailable(RuntimeError):
    """A fixture cannot be produced here (wrong OS, missing tool, missing data)."""


def load_manifest(path: Path = MANIFEST) -> dict:
    return json.loads(path.read_text())


def by_id(manifest: dict) -> dict[str, dict]:
    return {f["id"]: f for f in manifest["fixtures"]}


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def default_scratch() -> Path:
    return Path(tempfile.gettempdir()) / "notero-fixtures"


# --------------------------------------------------------------------------
# Generating
# --------------------------------------------------------------------------

def _check_tools(generator_name: str, generator: dict) -> None:
    for tool in generator.get("requires", []):
        if shutil.which(tool) is None:
            raise FixtureUnavailable(
                f"generator {generator_name!r} needs `{tool}`, which is not available on this "
                f"system ({sys.platform}); the macOS text-to-speech tools are required")


def _expand(argument: str, *, out: Path, tmp: Path, resolved: dict[str, Path]) -> str:
    text = argument.replace("{repo}", str(REPO)).replace("{out}", str(out)).replace("{tmp}", str(tmp))
    while "{fixture:" in text:
        start = text.index("{fixture:")
        end = text.index("}", start)
        text = text[:start] + str(resolved[text[start + 9:end]]) + text[end + 1:]
    return text


def generate(out: Path, *, only: list[str] | None = None, manifest: dict | None = None,
             run=subprocess.run, resolved: dict[str, Path] | None = None) -> dict[str, dict]:
    """Generate fixtures into `out`. Returns {id: {"path", "sha256", "matches_manifest"}}.

    Fixtures are grouped by generator, so the multi-speaker set is rendered once.
    A fixture whose generator is unavailable here raises `FixtureUnavailable`; one
    with no generator (the external FLEURS subset) is skipped."""
    manifest = manifest or load_manifest()
    fixtures = by_id(manifest)
    wanted = list(only) if only else [f["id"] for f in manifest["fixtures"]]
    unknown = [i for i in wanted if i not in fixtures]
    if unknown:
        raise KeyError(f"unknown fixture id(s): {', '.join(unknown)}")
    out.mkdir(parents=True, exist_ok=True)
    resolved = dict(resolved or {})
    results: dict[str, dict] = {}

    def need(fixture_id: str) -> None:
        if fixture_id in results or fixture_id in resolved:
            return
        fixture = fixtures[fixture_id]
        name = fixture.get("generator")
        if not name:
            return
        generator = manifest["generators"][name]
        for dependency in generator.get("needs", []):
            need(dependency)
        _check_tools(name, generator)
        # One run of a group generator serves every wanted fixture of the group;
        # with a subset flag it renders only those, not the whole set.
        siblings = [f for f in manifest["fixtures"] if f.get("generator") == name
                    and (f["id"] in wanted or f["id"] == fixture_id)]
        flag = generator.get("subset_flag")
        subset: list[str] = []
        if flag:
            for sibling in siblings:
                subset += [flag, sibling["generator_arg"]]
        with tempfile.TemporaryDirectory(prefix="fixture-") as tmp:
            for command in generator["commands"]:
                argv = [_expand(a, out=out, tmp=Path(tmp), resolved=resolved) for a in command]
                run(argv + subset, check=True, capture_output=True)
        for sibling in siblings:
            path = out / sibling["audio"]
            if path.exists():
                resolved[sibling["id"]] = path
                results[sibling["id"]] = describe(sibling, out)

    for fixture_id in wanted:
        need(fixture_id)
    return {i: r for i, r in results.items() if i in wanted}


def describe(fixture: dict, directory: Path) -> dict:
    """Where a fixture is under `directory` and whether its hashes match the manifest."""
    path = directory / fixture["audio"]
    expected = fixture.get("sha256") or {}
    actual = {name: sha256_of(directory / name) for name in expected if (directory / name).exists()}
    matches = None if not expected else (actual == expected)
    return {"path": str(path), "sha256": actual.get(fixture["audio"]) or (
        sha256_of(path) if path.exists() else None), "matches_manifest": matches,
        "mismatched": sorted(name for name in expected if actual.get(name) != expected[name])}


def verify(directory: Path, manifest: dict | None = None) -> list[dict]:
    """One row per fixture found under `directory`, with its hash status."""
    manifest = manifest or load_manifest()
    rows = []
    for fixture in manifest["fixtures"]:
        if not fixture.get("generator"):
            continue
        path = directory / fixture["audio"]
        if not path.exists():
            rows.append({"id": fixture["id"], "status": "missing", "path": str(path)})
            continue
        info = describe(fixture, directory)
        rows.append({"id": fixture["id"], "path": info["path"], "sha256": info["sha256"],
                     "status": ("ok" if info["matches_manifest"] else
                                "no hash recorded" if info["matches_manifest"] is None else
                                "MISMATCH: " + ", ".join(info["mismatched"]))})
    return rows


def resolve(fixture_id: str, *, search: list[Path], scratch: Path, manifest: dict | None = None,
            allow_generate: bool = True, resolved: dict[str, Path] | None = None,
            run=subprocess.run) -> tuple[Path, dict]:
    """The audio file for a fixture: found under one of `search` (when its hash
    matches the manifest or none is recorded), else generated into `scratch`.
    Returns (path, info) with info["source"] in {"found", "generated"} and
    info["matches_manifest"]. Raises FixtureUnavailable if neither is possible."""
    manifest = manifest or load_manifest()
    fixture = by_id(manifest).get(fixture_id)
    if fixture is None:
        raise KeyError(f"unknown fixture id: {fixture_id}")
    for directory in search:
        candidate = directory / fixture["audio"]
        if candidate.is_file():
            info = describe(fixture, directory)
            if info["matches_manifest"] is not False:
                return candidate, {**info, "source": "found"}
    if not allow_generate or not fixture.get("generator"):
        raise FixtureUnavailable(f"fixture {fixture_id} was not found under "
                                 f"{', '.join(str(d) for d in search) or '(no search path)'} "
                                 f"and cannot be generated here")
    made = generate(scratch, only=[fixture_id], manifest=manifest, resolved=resolved, run=run)
    info = made[fixture_id]
    return Path(info["path"]), {**info, "source": "generated"}


# --------------------------------------------------------------------------
# The optional public subset (FLEURS Filipino)
# --------------------------------------------------------------------------

def read_pcm16(path: Path) -> list[int]:
    """Samples of a mono 16 kHz WAV as int16, from either PCM16 or IEEE-float32
    (FLEURS ships float32, which the standard `wave` module refuses). Anything
    else is an error rather than a silent mis-read."""
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path.name}: not a RIFF/WAVE file")
    position = 12
    fmt = None
    samples_bytes = None
    while position + 8 <= len(data):
        chunk_id = data[position:position + 4]
        size = struct.unpack("<I", data[position + 4:position + 8])[0]
        body = data[position + 8:position + 8 + size]
        if chunk_id == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif chunk_id == b"data":
            samples_bytes = body
        position += 8 + size + (size & 1)
    if fmt is None or samples_bytes is None:
        raise ValueError(f"{path.name}: no fmt or data chunk")
    tag, channels, rate, _, _, bits = fmt
    if channels != 1 or rate != SAMPLE_RATE:
        raise ValueError(f"{path.name}: expected mono {SAMPLE_RATE} Hz, got {channels} ch {rate} Hz")
    if tag == 1 and bits == 16:
        return list(struct.unpack(f"<{len(samples_bytes) // 2}h", samples_bytes))
    if tag == 3 and bits == 32:
        floats = struct.unpack(f"<{len(samples_bytes) // 4}f", samples_bytes)
        return [max(-32768, min(32767, int(round(x * 32767)))) for x in floats]
    raise ValueError(f"{path.name}: unsupported format tag {tag} / {bits} bits")


def write_pcm16(path: Path, samples: list[int]) -> None:
    import wave
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def fleurs_selection(fleurs_dir: Path, k: int) -> list[dict]:
    """The K clips with the smallest sha1(file name), from `test.tsv`. A hash order
    is arbitrary but fixed: no hand-picking, the same clips on every machine."""
    tsv = fleurs_dir / "test.tsv"
    if not tsv.is_file():
        raise FixtureUnavailable(f"FLEURS not found: {tsv} does not exist (optional fixture)")
    rows = []
    with tsv.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 4:
                continue
            wav = fleurs_dir / "test" / "test" / row[1]
            if wav.is_file():
                rows.append({"file": row[1], "path": wav, "reference": row[3]})
    if len(rows) < k:
        raise FixtureUnavailable(f"FLEURS has {len(rows)} usable clips under {fleurs_dir}; need {k}")
    rows.sort(key=lambda r: hashlib.sha1(r["file"].encode()).hexdigest())
    return rows[:k]


def build_fleurs_subset(fleurs_dir: Path, k: int, out: Path) -> dict:
    """Concatenate the selected clips (0.5 s of silence between them) into one
    16 kHz mono WAV and write the joined reference beside it. One file means one
    process launch per run instead of K, each paying a ~9 s model load."""
    chosen = fleurs_selection(fleurs_dir, k)
    out.mkdir(parents=True, exist_ok=True)
    gap = [0] * (SAMPLE_RATE // 2)
    samples: list[int] = []
    for i, clip in enumerate(chosen):
        if i:
            samples += gap
        samples += read_pcm16(clip["path"])
    audio, reference = out / f"fleurs-fil-ph-{k}.wav", out / f"fleurs-fil-ph-{k}.txt"
    write_pcm16(audio, samples)
    reference.write_text(" ".join(c["reference"] for c in chosen) + "\n")
    return {"audio": audio, "reference": reference, "clips": [c["file"] for c in chosen],
            "duration_s": len(samples) / SAMPLE_RATE, "sha256": sha256_of(audio),
            "reference_sha256": sha256_of(reference)}


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="the fixtures, what they support and what they cannot")
    gen = sub.add_parser("generate", help="regenerate fixtures into a scratch directory")
    gen.add_argument("--out", type=Path, default=default_scratch())
    gen.add_argument("--only", nargs="+", metavar="ID")
    ver = sub.add_parser("verify", help="compare a generated directory with the manifest's hashes")
    ver.add_argument("directory", type=Path)
    path = sub.add_parser("path", help="print the audio path of one fixture, generating it if needed")
    path.add_argument("id")
    path.add_argument("--out", type=Path, default=default_scratch())
    path.add_argument("--search", type=Path, nargs="*", default=[REPO / "eval" / "audio"])
    args = parser.parse_args(argv)
    manifest = load_manifest()

    if args.command == "list":
        for f in manifest["fixtures"]:
            kind = "SYNTHETIC" if f.get("synthetic") else "public"
            print(f"{f['id']:26s} {kind:9s} {('deterministic' if f.get('deterministic') else 'not deterministic'):17s} "
                  f"{f.get('duration_s', '?')} s")
            print(f"    supports:       {'; '.join(f['supports'])}")
            print(f"    cannot support: {'; '.join(f['cannot_support'])}")
        return 0
    try:
        if args.command == "generate":
            made = generate(args.out, only=args.only, manifest=manifest)
            bad = 0
            for fixture_id, info in made.items():
                status = ("hash matches the manifest" if info["matches_manifest"] else
                          "no hash recorded" if info["matches_manifest"] is None else
                          "HASH DIFFERS from the manifest: " + ", ".join(info["mismatched"]))
                bad += info["matches_manifest"] is False
                print(f"{fixture_id:26s} {info['path']}  {status}")
            return 1 if bad else 0
        if args.command == "verify":
            rows = verify(args.directory, manifest)
            for row in rows:
                print(f"{row['id']:26s} {row['status']}")
            return 0 if all(r["status"] in ("ok", "no hash recorded") for r in rows) else 1
        found, info = resolve(args.id, search=args.search, scratch=args.out, manifest=manifest)
        print(found)
        print(f"({info['source']}; matches manifest: {info['matches_manifest']})", file=sys.stderr)
        return 0
    except FixtureUnavailable as error:
        print(f"unavailable: {error}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
