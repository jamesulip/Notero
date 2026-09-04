# Benchmarks

Measured performance, with the conditions that produced each number.

**Read the conditions before you use a number.** Most of the results here come
from one 57-second synthetic test clip on one Mac. They are useful to compare
one configuration against another. They are not a promise about your meetings,
your voices or your Mac. [Limitations](#limitations) says where each number
stops being valid.

[FINDINGS.md](FINDINGS.md) holds the numbered findings that these measurements
came from, together with the failures that they exposed.

## The hardware

| | The plan assumed | The measurement Mac |
| --- | --- | --- |
| Machine | Mac mini M2 Pro | **MacBook Pro, Apple M5 Pro** |
| Cores | — | 15 (5 efficiency and 10 performance) |
| RAM | — | 24 GB |
| macOS | — | 26.6.2 |

**The measurement Mac is faster than the memory target.** The app is designed
for a 16 GB M2 Pro. Every measurement here is therefore an upper bound on what
an M2 Pro would do. [ENVIRONMENT.md](ENVIRONMENT.md) is the dated record of
this machine.

## The test material

| Clip | Length | Source | Reference |
| --- | --- | --- | --- |
| `synthetic-taglish` | 57 s | The macOS `say` command with the Indonesian voice, reading a Taglish script. `eval/make-synthetic.sh` builds it. | 123 words, `eval/synthetic-taglish.txt` |
| `meeting01` | 25 s | A real meeting excerpt. | 59 words, hand-kept, `eval/refs/meeting01.txt` |

**Neither clip is a fair test.** `eval/audio/` is not in git, thus these are
the two clips that the maintainer has. The synthetic clip uses an Indonesian
voice, because macOS ships no Filipino voice. It is close in phonology and
wrong in acoustics. It also begins at full amplitude at sample 0 with no
lead-in, which is not how a real recording behaves. The real excerpt is short
and its reference is too poor to draw a conclusion from: the offline WER on it
is 60%, and each live variant sits inside that spread.

## The method

`transcribe` produces every number below. It calls the same pipeline as the
app, thus a measurement here is a measurement of the shipping code and not of a
test harness. [CLI.md](CLI.md) gives the options.

- **RTF** is the wall-clock decode time divided by the audio duration. Lower is
  faster. 0.10 means 10 times faster than real time.
- **WER** is the word error rate against the reference file. Two scorers exist.
  The WER of the command-line tool splits an intra-word hyphen.
  `eval/langscore.py` keeps it, thus "i-send" stays one Filipino word there.
  The two therefore report different numbers for the same transcript, and each
  table below says which one produced it.
- **Peak memory** is the process footprint that `transcribe` reports at the
  end of a run.
- `eval/out/run-live.sh` is the script that produced the live comparison.
- `eval/compare_language.py` produced the language comparison.

## Headline results

Whole-file transcription, the Balanced tier, the synthetic Taglish clip:

| Measurement | Result |
| --- | ---: |
| RTF | 0.09 to 0.14 |
| Speed against real time | 7 to 11 times faster |
| WER | 20.3% to 25.8% |
| Peak memory | approximately 300 MB |

These are the numbers in the [README](../README.md). The WER range is from five
runs after the retry ladder in finding 9 was in place. The runs produced 119 to
121 words against the 123 words in the reference, and no dropped window. The
offline WER that this repository recorded for the same clip before that change
is **27.3%**, which the documents treat as the ceiling for this fixture.

## Whole-file transcription

Single runs from `eval/out/run-live.log`, the Balanced tier, no speaker
identification, the command-line scorer:

| Clip | Words | Decode time | RTF | WER |
| --- | ---: | ---: | ---: | ---: |
| `synthetic-taglish` | 121 | 4 s | 0.072 | 27.3% |
| `meeting01` | 51 | 3 s | 0.143 | 60.0% |

The 60% on `meeting01` is the reference and not the model. Read
[The test material](#the-test-material).

### The retry ladder

Before the retry ladder, one window of the synthetic clip returned nothing on
every attempt:

| Window | Decoded |
| --- | --- |
| 0.000–24.876 s | **empty, every attempt** |
| 24.532–49.708 s | 54 words |
| 49.364–57.049 s | 16 words |

**Twenty-five seconds of speech, which is 44% of the clip, disappeared. The
transcript looked short and not broken, and every stage reported success.** The
WER doubled from 27% to 56%. The failure is deterministic: five consecutive
runs produced the identical empty result.

It is the window boundary and not the audio. The same leading audio decoded
correctly at each other length:

| Window length | Result |
| --- | --- |
| 24.876 s | empty |
| 25.500 s | 90 words |
| 26.000 s | 56 words |
| 27.000 s | 60 words |
| 28.000 s | 70 words |

Finding 9 in [FINDINGS.md](FINDINGS.md) gives the mechanism and the fix.

## Live transcription

`transcribe --live` replays a clip through the same `LiveDecoder` that a
recording uses. The synthetic clip separates the variants. A 1.5-second hop and
a 15-second context, scored with the command-line scorer:

| Live variant | WER | Forced commits | Tail words committed unagreed | Deduplicated by text |
| --- | ---: | ---: | ---: | ---: |
| pre-roll 0 (the old context window) | 33.6% | 9 | 33 | 0 |
| **pre-roll 1.5 s** | **27.3%** | **2** | 4 | 5 |
| pre-roll 1.5 s, real-time pacing | 26.6% | 2 | 12 | 7 |
| the offline pass, the same model | 27.3% | — | — | — |

**The live path with pre-roll lands on the offline number.** A cold start at
each commit boundary was costing six WER points. Real-time pacing dropped 4 of
38 hops, which is 11%.

### The adaptive hop

Under real-time pacing:

| Real-time replay | Dropped hops | Forced commits | WER |
| --- | ---: | ---: | ---: |
| fixed 1.5 s hop | 4 / 38 | 2 | 26.6% |
| adaptive 1.0–1.5 s | 10 / 46 | 9 | 29.7% |

More drops and more forced commits. The `inferMs` that the model reports
understates the wall-clock cost of a decode, because audio conversion, actor
hops and the main-actor ingest path all sit outside it. **The adaptive hop
stays off by default.** The flag remains for a machine that is faster than this
one.

## Forced `tl` against automatic detection

`eval/compare_language.py` over the manifest, the Balanced tier, offline,
scored with `eval/langscore.py`:

| Clip | Mode | WER | S/D/I | Filipino err | English err | Code-switch err | RTF | Detected |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| synthetic | `tl` | 25.2% | 24/5/2 | 29.8% | 10.3% | 13.0% | 0.145 | tl |
| synthetic | `auto` | 62.6% | 28/48/1 | 67.9% | 48.7% | 53.7% | 0.110 | id ×3 |
| meeting01 | `tl` | 72.9% | 13/30/0 | 75.5% | 60.0% | 64.3% | 0.120 | tl |
| meeting01 | `auto` | 66.1% | 34/1/4 | 63.3% | 40.0% | 50.0% | 0.608 | tl ×1 |
| **all** | `tl` | **40.7%** | 37/35/2 | 46.6% | 20.4% | 23.5% | 0.137 | |
| **all** | `auto` | 63.7% | 62/49/5 | 66.2% | 46.9% | 52.9% | 0.263 | |

On the synthetic clip, `auto` resolves to Indonesian for all three windows and
loses 48 words to deletion. **This fixture is the least fair test of that
failure, because the voice is Indonesian.** On the real excerpt, `auto` is
better than `tl` (66% against 73%) at five times the decode time, and the
reference there is too poor to trust either number.

Pooled, `tl` is 23 points better and costs half the decode time. **The default
stays `tl`.** Run the harness on real Taglish recordings with clean references
before you revisit this.

## Model load time

**The first load of a model compiles CoreML for the Neural Engine, and that
took 284 seconds.** Later loads hit the cache at 9 to 11 seconds. Know this
before you assume that a restart is cheap.

## Memory

| Component | Resident memory |
| --- | ---: |
| large-v3-turbo (Balanced) | approximately 1.6 GB |
| The two speaker models | approximately 200 MB |
| Peak footprint of a whole-file run | approximately 300 MB, as `transcribe` reports it on the test clip |

**Two hours of audio in a `[Float]` array holds 460 MB.** The app therefore
maps the 16 kHz working copy and reads it in slices. On a Mac that already
holds the model, that difference makes the Mac swap memory to disk.

A background decode that competes for the Neural Engine turns a live hop from
0.9 seconds into 3 seconds. The job queue therefore refuses to start work while
a recording runs.

## Historical results

These numbers came from the retired Python server, not from the native app.
They are here because the design decisions that they produced are still in the
app. Do not compare them to the tables above.

| Path | Window | Median inference | RTF |
| --- | --- | ---: | ---: |
| Sliding (Phase 2 geometry) | 15 s | 891 ms | 0.059 |
| Fixed chunks (Phase 1, end to end) | 5 s | 516 ms | 0.103 |

The 15-second window costs approximately 0.9 seconds to decode. **A 1.0-second
hop therefore drops two thirds of its hops**, and consecutive passes stop being
consecutive, which is exactly what LocalAgreement needs. A 1.5-second hop
landed live accuracy within approximately 1.6 points of the offline ceiling. A
1.0-second hop was 14 points off. A 2.0-second hop was worse again, because the
buffer outruns agreement and starts to force commits instead of earning them.
The hop default of 1500 ms comes from this measurement.

The Python server dropped 15% of its hops at the same hop under real-time
pacing. The native app dropped 11%.

Findings 3, 4, 6 and 7 in [FINDINGS.md](FINDINGS.md) hold the rest, including
the concurrency measurement: partial latency holds to 4 streams, but the number
of commits for each stream falls by approximately one third.

## Limitations

1. **One machine.** Every number comes from one MacBook Pro M5 Pro. The app
   targets a 16 GB M2 Pro, which is slower.
2. **One synthetic clip carries most of the conclusions.** The voice is
   Indonesian, the acoustics are wrong, and the clip starts at full amplitude
   with no lead-in.
3. **The real excerpt is 25 seconds and its reference is poor.** A 60% WER on
   it measures the reference.
4. **No far-field room recording was measured.** Several people who speak
   Tagalog across a room is the primary case for this app, and it is also the
   hardest case to reproduce without private data.
5. **Two scorers report different WER for the same transcript.** Check which
   one a number came from before you compare it to another number.
6. **Each accuracy number is the Balanced tier.** No measurement compares one
   model against another model. Therefore this file cannot tell you if the
   Accurate tier or the Fast tier gives a better or a worse transcript.
   [MODELS.md](MODELS.md) lists which tier promises this project measured,
   and which ones it infers.
7. **The findings are engineering results and not product guarantees.** The
   caveat section of [FINDINGS.md](FINDINGS.md) says which findings are
   structural, and which ones must be derived again against your own
   recordings.

## Measure your own audio

In the app, press ⇧⌘K for the model benchmark. It measures the three tiers on
your own audio and recommends the slowest tier that stays at real-time speed.
**It ranks the tiers by decode time, and it does not measure accuracy.**

From the command line:

```bash
cd app && swift build -c release --product transcribe
./.build/release/transcribe --audio yours.m4a --reference yours.txt \
    --models ../models --json /tmp/run.json
```

[CLI.md](CLI.md) gives the rest of the options.
