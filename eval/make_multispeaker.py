"""Synthetic multi-speaker fixtures with known turn boundaries.

There is no real diarization ground truth on a developer machine, so this builds
some: it renders turns with different macOS `say` voices, trims each clip to its
audible extent, lays them on one timeline and writes the exact boundaries beside
the audio. Score a diarizer against them with `eval/der.py`.

    python3 eval/make_multispeaker.py                    # the tuning fixtures
    python3 eval/make_multispeaker.py --set holdout      # the hold-out fixtures
    python3 eval/make_multispeaker.py --only four-voices
    python3 eval/make_multispeaker.py --list
    python3 eval/make_multispeaker.py --pair Daniel Tessa --seed 191

Output (default `eval/audio/multispeaker/`, which git ignores):

    <name>.wav     16 kHz mono 16-bit, the format the app's working copy uses
    <name>.rttm    reference turns, one SPEAKER line each
    <name>.json    the same turns with the text and voice, for inspection
    manifest.json  fixtures, seeds, voices and the `say` voices installed

EVERYTHING HERE IS SYNTHETIC. Text-to-speech voices are far more consistent
than people: no breath, no drift, no room, no crosstalk, and the boundaries are
exact. A number measured on these files supports an A/B comparison between two
implementations on the same audio. It is not a claim about real meetings, and
two implementations that tie here can still differ on real speech.

What the set covers, each on purpose:

    two-distinct   two clearly different voices, long and short turns
    two-similar    two voices of the same sex and accent trading SHORT turns, so
                   both land in the same 10 s diarizer chunk: the FINDINGS 10
                   case, where chunk-level embeddings fuse the pair
    two-short-turns two voices that ARE separable, trading short turns inside the
                   same 10 s chunks: the FINDINGS 10 mechanism without the
                   confound of a pair no method can split
    chunk-fusion   Daniel/Tessa: the first pass mixes them up, per-turn embedding
                   separates them. The case chunk-embedding reuse must not break
    three-voices   three speakers, a one-word backchannel every few turns
    four-voices    four speakers, a mix of lengths, longer file
    three-overlap  three speakers with low overlap: a backchannel starts before
                   the previous turn has ended

The schedule is seeded, so a fixture is reproducible on one macOS version. A
different `say` voice build changes the audio but not the reference structure.

Choosing voices matters more than it looks. To the WeSpeaker embedding model many
`say` voices are near-twins: on this machine Samantha and Karen sit at cosine
distance 0.36 from each other, Reed and Eddy at 0.03, against the 0.7 that
`SpeakerEngine` treats as "same speaker". A fixture built from such voices tests
nothing but that. So the multi-voice fixtures use voices measured to be well
apart (nearest turn pair 0.73-0.84), and the one deliberately hard pair,
Samantha/Kathy, sits at 0.62-0.76. Measure your own set:

    python3 eval/make_multispeaker.py --out /tmp/survey --survey Samantha Kathy Daniel
    diarbench --audio /tmp/survey/survey.wav --probe-ref /tmp/survey/survey.rttm
"""

from __future__ import annotations

import argparse
import array
import json
import math
import random
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

SAMPLE_RATE = 16_000
SAY_RATE_WPM = 175
# Every clip is levelled to this RMS before the per-speaker gain, so the voices
# differ in timbre and pitch rather than in how loud `say` happened to render them.
TARGET_RMS = 0.08
NOISE_DB = -62.0  # room tone, relative to full scale; digital silence is not realistic

# --- what is said ---------------------------------------------------------------

# Roughly 8-13 s at 175 wpm.
LONG = [
    "So the main thing I wanted to cover today is the rollout plan. We finished the migration last week, the numbers look stable, and the next step is to move the remaining customers over in two batches.",
    "I looked at the incident from Tuesday and the root cause was a retry loop that never backed off. Every failed request queued three more, so a short outage turned into forty minutes of degraded service.",
    "What worries me about the timeline is not the engineering, it is the review cycle. Legal has to sign off on the new terms, and last time that took three weeks, which would push everything past the quarter end.",
    "Let me walk through the budget quickly. Hardware came in about eight percent under the estimate, travel is roughly on plan, and the contractor line is the one that is going to overshoot if we extend past March.",
    "I talked to four customers this week and the same complaint came up every time. They like the product, but exporting a report takes too many steps, and two of them said they had built spreadsheets just to avoid it.",
    "The way I would structure the pilot is to start with one team for two weeks, collect feedback every Friday, and only then decide whether to open it to the rest of the department. That keeps the risk small.",
    "On the hiring side we have three open roles. The designer position has the strongest pipeline, the backend role is slower than expected, and we have not seen a single good candidate for the data position yet.",
    "I rebuilt the dashboard over the weekend so that it loads the summary first and fetches the details in the background. The first screen now shows up in under a second, even on the slower office network.",
    "Before we commit to this vendor I would like us to run a proper comparison. Same dataset, same questions, and somebody who has not seen the vendor demo should score the answers without knowing which is which.",
    "The reason I keep pushing on documentation is that two people left this year and a lot of what they knew went with them. If it is not written down, we pay for it again every time someone new joins.",
]

# Roughly 3-5 s.
MEDIUM = [
    "I think we should ship it on Thursday if the tests pass.",
    "That makes sense, but who is going to own the follow up?",
    "We tried that last year and it did not scale very well.",
    "Can you share the numbers before the end of the day?",
    "My concern is the cost once we go past ten thousand users.",
    "I can take that one, it should only need a couple of days.",
    "The customer asked for a refund, so I escalated it to support.",
    "Let us put it on the agenda for the next planning session.",
    "I would rather fix the root problem than keep patching it.",
    "The latest build is already on the staging server, please take a look.",
    "We need a second opinion before we sign anything this week.",
    "There was a spike in errors right after the deploy this morning.",
    "I will send everyone the notes and the updated schedule tonight.",
    "It depends on whether the supplier can deliver by the fifteenth.",
    "Honestly the old process was simpler, even if it was slower.",
    "Could we move the review to Friday afternoon instead?",
]

# Roughly 1.2-2.2 s.
SHORT = [
    "Sounds good to me.",
    "Let me check on that.",
    "I disagree a little.",
    "That is fair enough.",
    "Give me five minutes.",
    "We can do that tomorrow.",
    "Not on my side.",
    "Which version was that?",
    "Okay, that works.",
    "I can send it over.",
    "Good point, actually.",
    "Let us wait and see.",
]

# Under about 0.9 s.
BACKCHANNEL = [
    "Mm-hmm.", "Right.", "Yeah.", "Okay.", "Got it.", "Sure.", "I see.", "Exactly.", "Yes.",
    "Uh-huh.",
]

POOLS = {"long": LONG, "medium": MEDIUM, "short": SHORT, "backchannel": BACKCHANNEL}


# --- fixture definitions --------------------------------------------------------

@dataclass(frozen=True)
class Fixture:
    name: str
    voices: tuple[str, ...]
    target_s: float
    seed: int
    # Probability of each turn length. Order: long, medium, short, backchannel.
    weights: tuple[float, float, float, float]
    gap_s: tuple[float, float] = (0.25, 1.1)
    # Chance that a short turn or backchannel starts before the previous turn ends,
    # and by how many seconds at most.
    overlap_chance: float = 0.0
    overlap_s: tuple[float, float] = (0.2, 0.5)
    # Per-voice gain after levelling, so loudness differs between speakers.
    gains: tuple[float, ...] = (1.0, 0.85, 0.95, 0.75)
    note: str = ""


FIXTURES = [
    Fixture(
        "two-distinct", ("Samantha", "Daniel"), 90, seed=11,
        weights=(0.20, 0.40, 0.25, 0.15),
        note="Two clearly different voices; the easy case.",
    ),
    Fixture(
        # Same sex, same accent family, SHORT turns: both voices share every 10 s
        # chunk, which is exactly how FINDINGS 10 fused two similar speakers.
        "two-similar", ("Samantha", "Kathy"), 100, seed=23,
        weights=(0.05, 0.30, 0.40, 0.25), gap_s=(0.2, 0.7),
        note="Two similar voices trading short turns inside shared 10 s chunks.",
    ),
    Fixture(
        # The FINDINGS 10 mechanism with voices that CAN be told apart: two voices
        # whose per-turn embeddings are far apart (Daniel/Moira, nearest turn pair
        # ~0.85) trading short turns, so every 10 s chunk holds both of them. Any
        # method that gives a turn the embedding of its whole chunk slot blurs the
        # two; one that embeds each turn from its own audio does not.
        "two-short-turns", ("Daniel", "Moira"), 100, seed=67,
        weights=(0.05, 0.30, 0.40, 0.25), gap_s=(0.3, 0.8),
        note="Two separable voices trading short turns inside shared 10 s chunks.",
    ),
    Fixture(
        # Found by `--pair` over twelve voice pairs. The per-turn embeddings of
        # Daniel and Tessa are far enough apart to split (centroid distance 0.80),
        # but the first pass, which embeds whole 10 s chunk slots, mixes them up:
        # first-pass-only DER is ~50% where per-turn re-embedding reaches ~8%.
        # This is the FINDINGS 10 failure reproduced with synthetic voices.
        "chunk-fusion", ("Daniel", "Tessa"), 80, seed=91,
        weights=(0.05, 0.30, 0.40, 0.25), gap_s=(0.3, 0.8),
        note="Separable voices the first pass mixes up inside shared 10 s chunks.",
    ),
    Fixture(
        "three-voices", ("Daniel", "Moira", "Albert"), 120, seed=37,
        weights=(0.15, 0.35, 0.25, 0.25),
        note="Three speakers with frequent backchannels.",
    ),
    Fixture(
        "four-voices", ("Daniel", "Moira", "Albert", "Junior"), 160, seed=41,
        weights=(0.20, 0.35, 0.25, 0.20),
        note="Four speakers, longer file.",
    ),
    Fixture(
        "three-overlap", ("Rishi", "Moira", "Albert"), 90, seed=53,
        weights=(0.10, 0.30, 0.30, 0.30), overlap_chance=0.7,
        note="Three speakers; a short turn often starts 0.2-0.5 s before the last one ends.",
    ),
]


# The HOLD-OUT set: the same structures as above with voices and seeds the tuning set
# never used, for checking that a threshold chosen on the first set is not fitted to
# its voices (see eval/tuning_verdict.py). Voices were chosen from `--survey` by how far
# apart the embedding model puts them (nearest turn pair 0.72-0.99), never by what any
# diarizer did with them, which is how the tuning set's voices were chosen too. A bare
# `say` name such as "Sandy" has several locales; the names here are the full ones, which
# are the variants a bare name resolved to on the machine that ran the survey.
HOLDOUT = [
    Fixture(
        "h-two-distinct", ("Sandy (English (UK))", "Fred"), 90, seed=211,
        weights=(0.20, 0.40, 0.25, 0.15),
        note="Hold-out: two separable voices, long and short turns.",
    ),
    Fixture(
        "h-two-short-turns", ("Tara (English (India))", "Ralph"), 100, seed=212,
        weights=(0.05, 0.30, 0.40, 0.25), gap_s=(0.3, 0.8),
        note="Hold-out: two separable voices trading short turns in shared chunks.",
    ),
    Fixture(
        "h-three-voices", ("Sandy (English (UK))", "Tara (English (India))", "Fred"), 120, seed=213,
        weights=(0.15, 0.35, 0.25, 0.25),
        note="Hold-out: three speakers with frequent backchannels.",
    ),
    Fixture(
        "h-four-voices", ("Sandy (English (UK))", "Tara (English (India))", "Ralph", "Shelley (English (UK))"), 160, seed=214,
        weights=(0.20, 0.35, 0.25, 0.20),
        note="Hold-out: four speakers, longer file.",
    ),
    Fixture(
        "h-three-overlap", ("Rocko (English (UK))", "Sandy (English (UK))", "Tara (English (India))"), 90, seed=215,
        weights=(0.10, 0.30, 0.30, 0.30), overlap_chance=0.7,
        note="Hold-out: three speakers; a short turn often starts before the last ends.",
    ),
]


# --- audio helpers --------------------------------------------------------------

def render(voice: str, text: str, workdir: Path) -> list[float]:
    """`say` -> 16 kHz mono floats, trimmed to what is audible."""
    aiff = workdir / "clip.aiff"
    wav = workdir / "clip.wav"
    subprocess.run(["say", "-v", voice, "-r", str(SAY_RATE_WPM), "-o", str(aiff), "--", text],
                   check=True, capture_output=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{SAMPLE_RATE}", "-c", "1",
                    str(aiff), str(wav)], check=True, capture_output=True)
    with wave.open(str(wav), "rb") as handle:
        assert handle.getframerate() == SAMPLE_RATE and handle.getnchannels() == 1
        raw = array.array("h")
        raw.frombytes(handle.readframes(handle.getnframes()))
    samples = [s / 32768.0 for s in raw]
    return level(trim(samples))


def trim(samples: list[float], frame: int = 160, threshold: float = 0.003,
         pad: int = 320) -> list[float]:
    """Cut leading and trailing near-silence so the reference boundary sits on the speech."""
    def loud(index: int) -> bool:
        chunk = samples[index:index + frame]
        return bool(chunk) and math.sqrt(sum(x * x for x in chunk) / len(chunk)) > threshold

    first = next((i for i in range(0, len(samples), frame) if loud(i)), 0)
    last = next((i for i in range(len(samples) - frame, -1, -frame) if loud(i)), len(samples))
    return samples[max(0, first - pad): min(len(samples), last + frame + pad)]


def level(samples: list[float]) -> list[float]:
    rms = math.sqrt(sum(x * x for x in samples) / max(1, len(samples)))
    scale = TARGET_RMS / rms if rms > 0 else 1.0
    return [x * scale for x in samples]


# --- building -------------------------------------------------------------------

def choose(rng: random.Random, fixture: Fixture, used: set[str]) -> tuple[str, str]:
    kind = rng.choices(("long", "medium", "short", "backchannel"), fixture.weights)[0]
    pool = [t for t in POOLS[kind] if t not in used] or POOLS[kind]
    text = rng.choice(pool)
    used.add(text)
    return kind, text


def build(fixture: Fixture, out: Path, workdir: Path) -> dict:
    rng = random.Random(fixture.seed)
    used: set[str] = set()
    cache: dict[tuple[str, str], list[float]] = {}

    timeline = array.array("f")
    turns = []
    cursor = int(0.6 * SAMPLE_RATE)       # lead-in of room tone, not speech at sample 0
    previous_speaker = -1
    previous_start = 0
    previous_end = cursor

    while previous_end / SAMPLE_RATE < fixture.target_s:
        kind, text = choose(rng, fixture, used)
        # A different person from the one who just spoke; a long run by one voice
        # is its own long turn, not two.
        speaker = rng.choice([i for i in range(len(fixture.voices)) if i != previous_speaker])
        voice = fixture.voices[speaker]
        clip = cache.setdefault((voice, text), render(voice, text, workdir))
        gain = fixture.gains[speaker % len(fixture.gains)]

        overlapping = (
            turns and kind in ("short", "backchannel") and rng.random() < fixture.overlap_chance
        )
        if overlapping:
            back = int(rng.uniform(*fixture.overlap_s) * SAMPLE_RATE)
            start = max(previous_start + SAMPLE_RATE // 2, previous_end - back)
        else:
            start = previous_end + int(rng.uniform(*fixture.gap_s) * SAMPLE_RATE)
        # The start can be clamped, so ask the timeline rather than the dice.
        overlapping = start < previous_end
        end = start + len(clip)

        if len(timeline) < end:
            timeline.extend([0.0] * (end - len(timeline)))
        for offset, value in enumerate(clip):
            timeline[start + offset] += value * gain

        turns.append({
            "speaker": f"spk{speaker + 1}", "voice": voice, "kind": kind, "text": text,
            "start": round(start / SAMPLE_RATE, 3), "end": round(end / SAMPLE_RATE, 3),
            "overlaps_previous": bool(overlapping),
        })
        previous_speaker, previous_start = speaker, start
        previous_end = max(previous_end, end) if overlapping else end

    tail = int(0.8 * SAMPLE_RATE)
    timeline.extend([0.0] * tail)

    noise_rng = random.Random(fixture.seed + 1000)
    sigma = 10 ** (NOISE_DB / 20)
    pcm = array.array("h")
    for value in timeline:
        mixed = value + noise_rng.gauss(0.0, sigma)
        pcm.append(max(-32768, min(32767, int(round(mixed * 32767)))))

    with wave.open(str(out / f"{fixture.name}.wav"), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())

    (out / f"{fixture.name}.rttm").write_text("".join(
        f"SPEAKER {fixture.name} 1 {t['start']:.3f} {t['end'] - t['start']:.3f} "
        f"<NA> <NA> {t['speaker']} <NA> <NA>\n"
        for t in turns
    ))
    summary = {
        "name": fixture.name, "note": fixture.note, "seed": fixture.seed,
        "voices": list(fixture.voices), "duration_s": round(len(pcm) / SAMPLE_RATE, 3),
        "turn_count": len(turns),
        "overlap_turns": sum(t["overlaps_previous"] for t in turns),
        "by_kind": {k: sum(t["kind"] == k for t in turns) for k in POOLS},
        "turns": turns, "synthetic": True,
    }
    (out / f"{fixture.name}.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def survey(voices: list[str], out: Path, workdir: Path, turns_each: int = 4) -> None:
    """One file where each voice speaks a few medium turns, plus its RTTM.

    Feed it to `diarbench --probe-ref` to see how far apart the voices are to the
    embedding model: the way to pick a pair that is genuinely hard (centroid
    distance a little under the 0.7 same-speaker rule) or genuinely easy.
    """
    timeline = array.array("f", [0.0] * int(0.5 * SAMPLE_RATE))
    lines = []
    texts = (MEDIUM * 2)[: turns_each]
    for number, voice in enumerate(voices, start=1):
        for text in texts:
            clip = render(voice, text, workdir)
            start = len(timeline)
            timeline.extend(clip)
            timeline.extend([0.0] * int(0.5 * SAMPLE_RATE))
            lines.append(f"SPEAKER survey 1 {start / SAMPLE_RATE:.3f} {len(clip) / SAMPLE_RATE:.3f} "
                         f"<NA> <NA> {number:02d}-{voice.replace(' ', '_')} <NA> <NA>\n")
    pcm = array.array("h", (max(-32768, min(32767, int(round(v * 32767)))) for v in timeline))
    out.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out / "survey.wav"), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    (out / "survey.rttm").write_text("".join(lines))


def installed_voices() -> list[str]:
    result = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, check=True)
    names = []
    for line in result.stdout.splitlines():
        match = re.match(r"^(.+?)\s+[a-z]{2,3}_[A-Za-z0-9]+\s", line)
        if match:
            names.append(match.group(1).strip())
    return names


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent / "audio" / "multispeaker")
    parser.add_argument("--only", action="append", help="fixture name; repeatable")
    parser.add_argument("--list", action="store_true", help="list fixtures and exit")
    parser.add_argument("--set", choices=["tuning", "holdout"], default="tuning",
                        help="which fixture set to build (default: the tuning set)")
    parser.add_argument("--seed", type=int, default=91,
                        help="seed of a --pair fixture (default 91, the tuning pairs')")
    parser.add_argument("--pair", nargs=2, metavar="VOICE",
                        help="write one short-turn fixture for this pair of voices, named "
                             "pair-<a>-<b>, to look for pairs a method fuses")
    parser.add_argument("--survey", nargs="+", metavar="VOICE",
                        help="write survey.wav/.rttm with these voices instead of the fixtures")
    args = parser.parse_args(argv)

    pool = HOLDOUT if args.set == "holdout" else FIXTURES
    if args.list:
        for f in pool:
            print(f"{f.name:14} {len(f.voices)} voices {f.target_s:4.0f}s  {f.note}")
        return 0
    if not shutil.which("say") or not shutil.which("afconvert"):
        print("error: needs macOS `say` and `afconvert`", file=sys.stderr)
        return 2

    if args.survey:
        with tempfile.TemporaryDirectory(prefix="multispeaker-") as scratch:
            survey(args.survey, args.out, Path(scratch))
        print(f"wrote {args.out}/survey.wav and survey.rttm")
        return 0

    if args.pair:
        a, b = args.pair
        pool.append(Fixture(
            re.sub(r"[^A-Za-z0-9-]+", "_", f"pair-{a}-{b}").strip("_"), (a, b), 80, seed=args.seed,
            weights=(0.05, 0.30, 0.40, 0.25), gap_s=(0.3, 0.8),
            note=f"Short turns between {a} and {b}."))
        args.only = [pool[-1].name]

    chosen = [f for f in pool if not args.only or f.name in args.only]
    if not chosen:
        print(f"error: no fixture matches {args.only}", file=sys.stderr)
        return 2
    available = set(installed_voices())
    missing = sorted({v for f in chosen for v in f.voices} - available)
    if missing:
        print(f"error: voices not installed: {', '.join(missing)}\n"
              f"       see `say -v '?'` and edit FIXTURES", file=sys.stderr)
        return 2

    args.out.mkdir(parents=True, exist_ok=True)
    summaries = []
    with tempfile.TemporaryDirectory(prefix="multispeaker-") as scratch:
        for fixture in chosen:
            summary = build(fixture, args.out, Path(scratch))
            summaries.append({k: v for k, v in summary.items() if k != "turns"})
            print(f"{fixture.name}: {summary['duration_s']:.1f} s, "
                  f"{summary['turn_count']} turns, {summary['overlap_turns']} overlapping")
    manifest = {"synthetic": True, "say_voices_installed": sorted(available),
                "fixtures": summaries}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
