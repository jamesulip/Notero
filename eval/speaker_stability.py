"""Does a name a person typed stay with the voice it was given to, run after run?

Speaker labels (S1, S2) are numbered by who speaks first, and the number can change
between two runs over the same audio. This builds the audio variants that make it
change, and scores what a re-run does to a name.

    # variants of every fixture: opener muted, head trimmed, room noise, AAC round trip
    python3 eval/speaker_stability.py variants --fixtures DIR --out DIR

    # one comparison: OLD is the run a person renamed, NEW is the run after it
    python3 eval/speaker_stability.py score --old-ref A.rttm --old A.json \\
        --new-ref B.rttm --new B.json

`score` imagines that a person named every speaker of the OLD run after the voice it
actually is (the name is the reference speaker id, so right and wrong are known), then
asks what the NEW run does with those names under two policies:

    label   the name stays on the label number. This is the behaviour before this work.
    carry   the name follows the speaker that `diarbench --carry-from OLD.json` matched
            to it (`SpeakerMatching`), and is left off a speaker it could not match.

and counts speech seconds under a name that is right, under a name that is wrong, and
under no name (the default "Speaker N"). A wrong name is the defect: it puts one
person's words under another person's name.

Everything here is SYNTHETIC: text-to-speech voices from `make_multispeaker.py`, with
exact boundaries and a clean noise floor. It compares two behaviours on the same audio.
It says nothing about how often real meetings renumber their speakers. Standard library
only, so it runs wherever the tests do; only `diarbench` needs a Mac.
"""

from __future__ import annotations

import argparse
import array
import json
import random
import shutil
import subprocess
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import der  # noqa: E402

SAMPLE_RATE = 16_000


# --- audio variants -----------------------------------------------------------

def read_wav(path: Path) -> tuple[array.array, int]:
    with wave.open(str(path), "rb") as handle:
        assert handle.getnchannels() == 1 and handle.getsampwidth() == 2, "16-bit mono only"
        rate = handle.getframerate()
        samples = array.array("h")
        samples.frombytes(handle.readframes(handle.getnframes()))
    return samples, rate


def write_wav(path: Path, samples: array.array, rate: int) -> None:
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(samples.tobytes())


def mute(samples: array.array, rate: int, start: float, end: float) -> array.array:
    """The same audio with [start, end) replaced by silence. The timeline is unchanged."""
    out = array.array("h", samples)
    for i in range(max(0, int(start * rate)), min(len(out), int(end * rate))):
        out[i] = 0
    return out


def trim_head(samples: array.array, rate: int, seconds: float) -> array.array:
    """The same audio without its first `seconds`. Every later time moves earlier."""
    return array.array("h", samples[int(seconds * rate):])


def add_room_noise(samples: array.array, level_db: float, seed: int) -> array.array:
    """White noise at `level_db` relative to full scale, on top of the audio."""
    sigma = 32767 * 10 ** (level_db / 20)
    rng = random.Random(seed)
    return array.array("h", (
        max(-32768, min(32767, int(round(s + rng.gauss(0.0, sigma))))) for s in samples))


def turns_without(turns: list[der.Segment], dropped: der.Segment) -> list[der.Segment]:
    return [t for t in turns if t != dropped]


def shifted(turns: list[der.Segment], seconds: float) -> list[der.Segment]:
    """Turns of the trimmed audio: moved earlier, and the ones that ended before the cut gone."""
    return [der.Segment(t.start - seconds, t.end - seconds, t.speaker)
            for t in turns if t.end > seconds + 0.5]


def variants_of(name: str, wav: Path, rttm: Path, out: Path, noise_db: float = -40.0) -> list[str]:
    """Writes the variants of one fixture and returns their names."""
    samples, rate = read_wav(wav)
    turns = sorted(der.read_rttm(rttm), key=lambda t: t.start)
    written = []

    def emit(tag: str, audio: array.array, ref: list[der.Segment]) -> None:
        stem = f"{name}.{tag}"
        write_wav(out / f"{stem}.wav", audio, rate)
        der.write_rttm(ref, out / f"{stem}.rttm", stem)
        written.append(stem)

    # The opener drops out: a one-second greeting under the first pass's minimum, a
    # window edge. The timeline is the same, but a different person now speaks first.
    opener = turns[0]
    emit("mute-opener", mute(samples, rate, opener.start - 0.05, opener.end + 0.05),
         turns_without(turns, opener))

    # The head is cut after the second turn, in the middle of the gap after it.
    cut = (turns[1].end + turns[2].start) / 2
    emit("trim-head", trim_head(samples, rate, cut), shifted(turns, cut))

    # The same audio with a room under it, to see whether anything above depends on
    # the digital silence of a text-to-speech file.
    emit(f"noise{int(-noise_db)}", add_room_noise(samples, noise_db, seed=7), turns)

    # What Transcribe Again decodes when the archive stands in for the working copy:
    # the same audio through the app's own codec and bitrate (AAC, 64 kbit/s per
    # lane at the capture rate, see ArchiveWriter), 48 kHz as a microphone gives it.
    # macOS only; skipped where afconvert is missing.
    if shutil.which("afconvert"):
        stem = f"{name}.aac64"
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac@48000", "-b", "64000", "-c", "1",
                        str(wav), str(out / f"{stem}.m4a")], check=True, capture_output=True)
        der.write_rttm(turns, out / f"{stem}.rttm", stem)
        written.append(stem)
    return written


# --- scoring ------------------------------------------------------------------

def label_names(ref: list[der.Segment], hyp: list[der.Segment], collar: float = 0.25) -> dict[str, str]:
    """What a person would call each label of a run: the reference speaker it actually is."""
    mapping = der.score(ref, hyp, collar=collar).mapping
    return {label: voice for voice, label in mapping.items() if label is not None}


def label_in_turn(turn: der.Segment, hyp: list[der.Segment]) -> tuple[str | None, float]:
    """The label holding most of the turn, and how many seconds of it."""
    seconds: dict[str, float] = {}
    for span in hyp:
        shared = min(turn.end, span.end) - max(turn.start, span.start)
        if shared > 0:
            seconds[span.speaker] = seconds.get(span.speaker, 0.0) + shared
    if not seconds:
        return None, 0.0
    label = max(seconds, key=lambda k: seconds[k])
    return label, seconds[label]


def stability(old_ref: list[der.Segment], old: list[der.Segment],
              new_ref: list[der.Segment], new: list[der.Segment],
              carry: dict | None, collar: float = 0.25) -> dict:
    """Seconds under a right, a wrong and no name, for both policies."""
    names = label_names(old_ref, old, collar)           # old label -> the voice it is
    # The label each reference voice has in the new run, for counting swaps.
    new_names = label_names(new_ref, new, collar)       # new label -> voice
    label_of_voice_old = {voice: label for label, voice in names.items()}
    label_of_voice_new = {voice: label for label, voice in new_names.items()}
    shared_voices = sorted(set(label_of_voice_old) & set(label_of_voice_new))
    swapped = [v for v in shared_voices if label_of_voice_old[v] != label_of_voice_new[v]]

    labels = (carry or {}).get("labels", {})
    out = {"label": {"right": 0.0, "wrong": 0.0, "default": 0.0},
           "carry": {"right": 0.0, "wrong": 0.0, "default": 0.0}}

    def tally(policy: str, name: str | None, voice: str, seconds: float) -> None:
        bucket = "default" if name is None else ("right" if name == voice else "wrong")
        out[policy][bucket] += seconds

    for turn in new_ref:
        label, seconds = label_in_turn(turn, new)
        if label is None:
            continue
        tally("label", names.get(label), turn.speaker, seconds)
        final = labels.get(label, label)
        tally("carry", names.get(final), turn.speaker, seconds)

    def pct(policy: str) -> dict:
        total = sum(out[policy].values()) or 1.0
        return {k: round(100 * v / total, 2) for k, v in out[policy].items()} | {
            "seconds": round(sum(out[policy].values()), 2)}

    return {
        "voices_in_both": len(shared_voices), "voices_renumbered": len(swapped),
        "renumbered": swapped, "label": pct("label"), "carry": pct("carry"),
        "carry_inherited": (carry or {}).get("inherited", {}),
        "carry_kept": (carry or {}).get("kept", []),
    }


# --- running diarbench ------------------------------------------------------------

def diarbench(binary: Path, wav: Path, out: Path, models: Path, extra: list[str],
              wrap: list[str]) -> dict:
    command = wrap + [str(binary), "--audio", str(wav), "--models", str(models),
                      "--json", str(out)] + extra
    subprocess.run(command, check=True, capture_output=True)
    return json.loads(out.read_text())


def fingerprint(spans: list[dict]) -> tuple:
    return tuple((round(s["start"], 2), round(s["end"], 2), s["speaker"]) for s in spans)


def matrix(binary: Path, fixtures: Path, variants: Path, models: Path, out: Path,
           wrap: list[str], only: list[str] | None) -> list[dict]:
    """Every fixture: one run to rename, then each way of running it again."""
    rows = []
    out.mkdir(parents=True, exist_ok=True)
    for wav in sorted(fixtures.glob("*.wav")):
        name = wav.stem
        if "." in name or (only and name not in only):
            continue
        ref = der.read_rttm(wav.with_suffix(".rttm"))
        n_ref = len({t.speaker for t in ref})
        base_json = out / f"{name}.base.json"
        base = diarbench(binary, wav, base_json, models, [], wrap)
        old = der.read_spans_json(base_json)

        # (tag, audio, reference of that audio, extra arguments)
        runs = [
            ("again", wav, wav.with_suffix(".rttm"), []),
            ("fast", wav, wav.with_suffix(".rttm"), ["--mode", "fast"]),
            (f"expected-{n_ref}", wav, wav.with_suffix(".rttm"), ["--expected", str(n_ref)]),
        ]
        if n_ref > 2:
            runs.append((f"expected-{n_ref - 1}", wav, wav.with_suffix(".rttm"),
                         ["--expected", str(n_ref - 1)]))
        for tag in ("mute-opener", "trim-head", "noise40", "aac64"):
            for suffix in (".wav", ".m4a"):
                variant = variants / f"{name}.{tag}{suffix}"
                if variant.exists():
                    runs.append((tag, variant, variant.with_suffix(".rttm"), []))

        for tag, audio, ref_path, extra in runs:
            new_json = out / f"{name}.{tag}.json"
            new = diarbench(binary, audio, new_json, models,
                            extra + ["--carry-from", str(base_json)], wrap)
            result = stability(ref, old, der.read_rttm(ref_path),
                               der.read_spans_json(new_json), new.get("carry"))
            result.update(fixture=name, run=tag, speakers_old=base["speakers"],
                          speakers_new=new["speakers"],
                          identical_to_base=fingerprint(base["spans"]) == fingerprint(new["spans"]))
            rows.append(result)
    return rows


def render(rows: list[dict]) -> str:
    head = (f"{'fixture':16} {'run':16} {'renum':>5}  {'label right/wrong/none %':>26}  "
            f"{'carry right/wrong/none %':>26}")
    lines = [head, "-" * len(head)]
    for r in rows:
        lines.append(
            f"{r['fixture']:16} {r['run']:16} {r['voices_renumbered']:>2}/{r['voices_in_both']:<2}  "
            f"{r['label']['right']:7.1f} {r['label']['wrong']:7.1f} {r['label']['default']:7.1f}  "
            f"{r['carry']['right']:7.1f} {r['carry']['wrong']:7.1f} {r['carry']['default']:7.1f}")
    # Pooled by seconds, so a long fixture counts for what it is.
    for policy in ("label", "carry"):
        pooled = {k: sum(r[policy][k] / 100 * r[policy]["seconds"] for r in rows)
                  for k in ("right", "wrong", "default")}
        total = sum(pooled.values()) or 1.0
        lines.append(f"pooled {policy:5}: right {100 * pooled['right'] / total:5.1f}%  "
                     f"wrong {100 * pooled['wrong'] / total:5.1f}%  "
                     f"no name {100 * pooled['default'] / total:5.1f}%  ({total:.0f} s)")
    renumbered = [r for r in rows if r["voices_renumbered"]]
    lines.append(f"runs where at least one voice changed label number: "
                 f"{len(renumbered)} of {len(rows)}")
    return "\n".join(lines)


# --- command line ---------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    v = sub.add_parser("variants", help="write mute-opener, trim-head, noisy and AAC variants")
    v.add_argument("--fixtures", type=Path, required=True)
    v.add_argument("--out", type=Path, required=True)
    v.add_argument("--noise-db", type=float, default=-40.0)

    s = sub.add_parser("score", help="what a re-run does to the names of the run before")
    s.add_argument("--old-ref", type=Path, required=True)
    s.add_argument("--old", type=Path, required=True)
    s.add_argument("--new-ref", type=Path, required=True)
    s.add_argument("--new", type=Path, required=True, help="diarbench JSON, with a `carry` block")
    s.add_argument("--collar", type=float, default=0.25)

    m = sub.add_parser("matrix", help="run diarbench on every fixture and way of re-running it")
    m.add_argument("--diarbench", type=Path, required=True)
    m.add_argument("--fixtures", type=Path, required=True)
    m.add_argument("--variants", type=Path, required=True)
    m.add_argument("--models", type=Path, required=True)
    m.add_argument("--out", type=Path, required=True)
    m.add_argument("--only", action="append")
    m.add_argument("--wrap", action="append", default=[],
                   help="command prefix for each run; give it once per word")

    args = parser.parse_args(argv)
    if args.command == "matrix":
        rows = matrix(args.diarbench, args.fixtures, args.variants, args.models, args.out,
                      args.wrap, args.only)
        (args.out / "matrix.json").write_text(json.dumps(rows, indent=2))
        print(render(rows))
        return 0
    if args.command == "variants":
        args.out.mkdir(parents=True, exist_ok=True)
        for wav in sorted(args.fixtures.glob("*.wav")):
            rttm = wav.with_suffix(".rttm")
            if not rttm.exists() or "." in wav.stem:
                continue
            for stem in variants_of(wav.stem, wav, rttm, args.out, args.noise_db):
                print(stem)
        return 0

    new_json = json.loads(args.new.read_text())
    result = stability(der.read_rttm(args.old_ref), der.read_spans_json(args.old),
                       der.read_rttm(args.new_ref), der.read_spans_json(args.new),
                       new_json.get("carry"), args.collar)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
