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

**`meeting01` is not on every machine.** `eval/manifest.json` references it, and
on the Mac mini M2 Pro used for the [2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro)
neither its audio nor its reference exists, so only the synthetic clip was
measured there. [Test material that exists](#test-material-that-exists) lists
what is on disk, and [What real data is needed](#what-real-data-is-needed) says
what to collect.

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
- **"Peak memory"** is what the older numbers in this file call it, and it is
  neither a peak nor a model's memory. `transcribe` printed `phys_footprint`,
  read once at exit: the footprint of one process at that instant. It leaves
  out the Neural Engine memory that holds the loaded model. Read
  [Which number is which](#which-number-is-which) before you quote any memory
  figure here.
- `eval/out/run-live.sh` is the script that produced the live comparison.
- `eval/compare_language.py` produced the language comparison.

## Which number is which

Several figures in this project share a name and measure different things. Each
row says where the number comes from and what it is not.

### Speed

| Figure | What it is | Where `transcribe` reports it | What it is not |
| --- | --- | --- | --- |
| **Whole-file RTF** | `decodeMs` over the audio length for an **offline** run. It includes voice activity detection, every window and every retry. It excludes the model load and diarization. | `rtf` in the JSON, the `decoded … (RTF …)` line | A live latency. A live hop never decodes the whole file. |
| **Model load time** | Wall time to load the model. The first load after a model or OS change compiles CoreML (284 s once); a cached load took about 10 s. | `loadMs` in the JSON, the `model load … ms` line | Part of any RTF. |
| **Replay RTF** (live) | Wall time of a `--live` replay over the audio length. With every decode awaited it is how fast this Mac replays the file on this schedule. Under `--realtime` it is about 1.0 **by construction**, because the feed is paced at wall-clock speed. | `rtf` in the JSON when `mode` starts with `live` | A per-hop cost. Never compare it with an offline RTF. |
| **Per-decode time** | What one call to the recognizer costs: the model's own `inferMs`, and the wall time around the call. The gap between them is audio conversion and actor hops, which the model's clock leaves out ([The adaptive hop](#the-adaptive-hop)). Reported as median, p95 and max. | `decodeTiming` in the JSON, the `per decode:` line | A whole-file figure. |
| **Per-decode RTF** | Sum of `inferMs` over the sum of audio handed to the model. A live decode reads a window of up to 15 s plus pre-roll to advance the transcript by one 1.5 s hop, so this number is **not** `inferMs` over the hop. | `live.meanRtf`, `decodeTiming.inferRtf` | The cost of a hop. Compare per-decode time with the hop: a p95 decode time above 1500 ms means that real-time pacing drops hops. |
| **Commit latency** | The clock at the moment a word was committed, minus the time that the word ended in the audio. Median, mean, p95 and max over words. The clock is *audio fed so far* (the mechanism: how long the commit policy waits for agreement and for a pause) and, under `--realtime` only, *wall time since the replay began* (adds what the machine costs). | `commitLatency`, `commitLatencyWall`, the `commit latency` line | A measure of when the word appears on screen. A provisional word shows earlier. It is when the word becomes **final**. |
| **Dropped hops** | Hops discarded because the previous decode was still running. Meaningful only under `--realtime`. With awaited decodes it is zero by construction. | `live.droppedHops` | |

### Memory

| Figure | What it is | What it is not |
| --- | --- | --- |
| **Process footprint** (`phys_footprint`) | Dirty and compressed pages of this one process, plus some IOKit mappings. What Activity Monitor shows as Memory. | The memory a model needs. |
| **Lifetime peak footprint** | The highest `phys_footprint` this process has reached, from the kernel's ledger and `/usr/bin/time -l` (`peak memory footprint`). | |
| **Footprint at exit** | `phys_footprint` read once, when `transcribe` finished. **This is what `transcribe` printed as "peak memory" until 2026-11-01.** It is a single reading at the end, so it can sit far below the real peak. | A peak. |
| **Neural Engine memory** | Memory that CoreML placed on the Neural Engine and that the kernel attributes to this process as "neural, nofootprint" (`footprint(1)`; `ledger_tag_neural_nofootprint_*`). **It is not in the footprint.** This is the residency-style figure for a loaded model. | A figure for the whole machine. |
| **System-wide `vm_stat`** | Free, wired and compressed pages of the whole Mac. | Anything about one process. On a shared Mac it moves for reasons that have nothing to do with the model, so no figure in this file quotes a `vm_stat` delta as a model's size. |

**Never present a smaller process footprint as lower model memory.** The model
is not in it. A build can show a smaller footprint and need exactly as much
memory for the model, because the model's memory is somewhere the footprint does
not look. Compare footprints only between stages of one build, and quote the
Neural Engine figure beside them. `eval/residency.py` measures the same stages
from outside the process, with `footprint(1)`, as an independent check on the
in-process figures.

## 2026-11-01 baseline: f022c6e on the Mac mini M2 Pro

The first set of numbers from the hardware that the app targets, and the first
with enough runs per build to show the spread. **It is a baseline for comparing
builds on this clip. It is not a statement about real Taglish**: the only fixture
on this machine is the synthetic clip, and there is no real Taglish reference.
Raw JSON of every run: `/tmp/notero-team/baseline/` (not in git). The collated
figures: `/tmp/notero-team/baseline/baseline-summary.json`.

### Conditions

| | |
| --- | --- |
| Date | 2026-11-01, 00:11 to 01:39 local time (UTC+8). Run while other work shared the Mac: the 1-minute load average at launch was 1.6 to 6.4 in the live sessions (it was not yet recorded in the offline session). |
| Machine | Mac mini, Mac14,12, Apple M2 Pro, 10 cores, 16 GB |
| OS and toolchain | macOS 26.6.2 (25G83), Swift 6.3.3 (swiftlang-6.3.3.1.3), release build |
| Model | `openai_whisper-large-v3-v20240930_turbo` (Balanced), language forced to `tl`, no diarization |
| Dependencies | WhisperKit 1.1.0 (exact pin), FluidAudio 0.15.6 |
| Audio | `synthetic-taglish.wav`, 57 s, SHA-256 `e858bd6a…dd05f25` |
| Reference | `synthetic-taglish.txt`, 123 words by whitespace, **128 by `score.py`** (it splits hyphens), which is what every WER below is divided by |
| Scorer | `eval/score.py`. The CLI's own WER matched it in every run (`cli_wer`). |
| Harness | `eval/bench_runs.py` at commit `1a8ab42` (the offline session ran at `d01f895`, which differs by the load-average field), every launch through `/tmp/notero-team/bench-lock.sh` |

**Two binaries, and why.** The pure build is `transcribe` built from
`git archive f022c6e` in a scratch directory (`/tmp/benchmarks-baseline`,
SHA-256 `88c45191…`). It cannot report commit latency, the model load time or the
memory stages. The second binary adds those, and only those: `f022c6e` plus the
two commits `984e1a5` and `96f5a16` under `app/Sources/TranscriberCLI` and
`BenchmarkRunner.swift` (`/tmp/benchmarks-instrumented`, SHA-256 `b14f7b9c…`).
The decode path is the same code. The two were run **interleaved** (order A B,
B A, A B, …), so that both see the same machine. Every number labelled "pure"
comes from the pure build. The live commit latency, the model load time and
every Neural Engine figure can only come from the instrumented one.

### Commands

```bash
# build (scratch copies, not the repository's .build)
git archive f022c6e | tar -x -C /tmp/benchmarks-baseline
(cd /tmp/benchmarks-baseline/app && swift build -c release --product transcribe)
git archive 96f5a16 app | tar -x -C /tmp/benchmarks-instrumented
(cd /tmp/benchmarks-instrumented/app && swift build -c release --product transcribe)

PURE=/tmp/benchmarks-baseline/app/.build/release/transcribe
INSTR=/tmp/benchmarks-instrumented/app/.build/release/transcribe
AUDIO=/Users/server/Documents/GitHub/Notero/eval/audio/synthetic-taglish.wav
REF=eval/synthetic-taglish.txt

python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode offline \
    --runs 12 --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/offline
python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode live \
    --runs 8  --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/live
python3 eval/bench_runs.py run --bin $INSTR --mode live --realtime \
    --runs 8  --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/live-realtime
python3 eval/residency.py --bin $INSTR --audio $AUDIO --out /tmp/notero-team/baseline/residency-offline.json

# Afterwards: a repeat of the live comparison, and the A/A calibration run
python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode live \
    --runs 8 --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/recheck/live
cp -R $(dirname $PURE)/FluidAudio_FluidAudio.bundle /tmp/benchmarks-baseline-copy/
cp $PURE /tmp/benchmarks-baseline-copy/transcribe        # byte-identical copy
python3 eval/bench_runs.py run --interleave $PURE /tmp/benchmarks-baseline-copy/transcribe \
    --order abba --mode live --runs 8 --audio $AUDIO --ref $REF \
    --out-dir /tmp/notero-team/baseline/aa/live
```

`/tmp/notero-team/baseline/run-baseline.sh` holds the first four commands, and
`make-baseline-summary.py` in the same directory writes `baseline-summary.json`.

### Offline, 12 runs of each build

Median, then (minimum–maximum; interquartile range):

| | Pure `f022c6e` | `f022c6e` + CLI instrumentation |
| --- | --- | --- |
| WER | **34.0%** (21.1–57.8%; IQR 5.7) | 28.1% (27.3–57.8%; IQR 6.8) |
| Words, reference 128 | 120 (78–123) | 118 (73–121) |
| **Whole-file RTF** | **0.097** (0.086–0.188; IQR 0.023) | 0.134 (0.091–0.288; IQR 0.065) |
| `decodeMs` | 5514 ms (4867–10669) | 7587 ms (5130–16286) |
| **Collapsed runs** (rule above) | **1 of 12** (run 3: 78 words) | 2 of 12 (runs 9 and 11: 73 and 84 words) |
| Runs with invented-filler phrases | 1 (run 8: 57.0% WER, "welcome to meeting") | 0 |
| Runs where a window needed the retry ladder | 2 of 12 | 7 of 12 |
| Model load | not reported | 8.6 s (8.4–10.9) |

The pure build's WER per run, in order: 31.2, 36.7, 57.8, 32.0, 36.7, 33.6, 34.4,
57.0, 24.2, 35.2, 21.1, 30.5 (%).

**Read this table with the spread in mind, not the medians.**

- The runs are two populations. Most land at 27 to 37%; a run in which a window is
  lost or replaced lands at 57 to 58%. The 8-run range that FINDINGS 15 recorded
  for this build (25.0–57.0%, median 28.1%) lies inside this one (21.1–57.8%,
  median 34.0%), and the medians differ by 6 points because a handful of runs
  decide a median at n = 8 to 12. **Quote the range, and the collapsed count.**
- The collapse rule flagged run 3 (78 words) and not run 8: run 8 has 116 words
  and 57.0% WER, which is the invented-filler failure of FINDINGS 15, but the
  pure arm's best half is at 30.9%, so its threshold is 61.7% and 57.0% stays
  under it. The rule misses a collapse when an arm's ordinary WER is high. That
  is why the filler-phrase count is reported beside it.
- **Whether a window needed the retry ladder separates the runs completely.** A
  window came back empty on its first attempt, and went through the ladder, in 9
  of the 24 runs (2 of 12 pure, 7 of 12 instrumented; the difference between the
  builds is not significant, Fisher p = 0.09). **All 9 of those runs scored 21.1
  to 28.9%. All 15 runs with no retry scored 30.5 to 57.8%, and all four collapses
  are among them.** The perfect separation of 9 against 15 would arise by chance
  about 2 times in 1.3 million. That fits the mechanism proposed in FINDINGS 15:
  the window of about 25 s at the start of the clip came back empty on every
  attempt before the ladder existed (finding 9), so a run is clean when
  WhisperKit's greedy decode and its sampled fallbacks all come back empty and the
  ladder retries with a wider window, and a run goes wrong when a sampled fallback
  produces text that is not empty and not right. **This is an association in 24 runs, not a proof of the
  mechanism.** Logging WhisperKit's per-window fallback count beside each window
  would test it.
- RTF carries the load of the machine: the slowest runs (0.288 and 0.173 for the
  instrumented build, 0.188 for the pure one) are about 2 times the median of
  their arm.

**Compared with each other, the two builds cannot be told apart on WER**
(median difference −5.9 points, permutation p = 0.091, bootstrap 95% interval
−9.4 to +2.0) **or on collapsed runs** (1 against 2 of 12, Fisher p = 1.0). The
instrumented build's RTF was higher (+0.037, p = 0.085); [the section below](#is-the-instrumented-build-slower)
looks at that.

### Live, every decode awaited, 8 runs of each build

Hop 1500 ms, pre-roll 1500 ms, context 15 s. Nothing is dropped by construction.

| | Pure `f022c6e` | `f022c6e` + CLI instrumentation |
| --- | --- | --- |
| WER | 27.3% (24.2–34.4%; IQR 2.9) | 25.8% (22.7–27.3%; IQR 2.0) |
| Words, reference 128 | 122 (120–123) | 119 (118–123) |
| **Replay RTF** | 0.859 (0.712–0.925) | 1.003 (0.882–1.227) |
| Collapsed runs | 0 of 8 | 0 of 8 |
| Dropped hops | 0 | 0 |
| **Forced commits** | 4 (0–9; IQR 5.5) | 7.5 (1–11; IQR 2.3) |
| **Unagreed tail words** | 11 (3–37; IQR 21) | 37 (12–37; IQR 18) |
| **Per-decode RTF** (`meanRtf`) | 0.126 (0.108–0.142) | 0.118 (0.111–0.191) |
| **Model time per hop** (`inferMs`, mean over a run) | 1276 ms (1057–1374) | 1491 ms (1312–1825) |
| Per-decode p95 / max (median over runs of each run's p95 and max) | not reported | 2898 / 3819 ms |
| **Commit latency**, audio clock (median over runs of each run's median word) | not reported | 11.5 s (7.4–12.0) |

**The two columns differ in speed, and that gap is not real.** Replay RTF was
0.859 against 1.003 and the hop 1276 against 1491 ms, but a repeat of this
comparison gave 0.901 against 0.910, and the wrapper cannot change the model's
time. See [Is the instrumented build slower?](#is-the-instrumented-build-slower).

The live WER of 25.8 to 27.3% matches the offline number of the earlier tables,
and it is not significantly different between the builds (permutation p = 0.40).
The forced commits and the unagreed tail words vary a great deal from run to run
(0 to 11, and 3 to 37), which is the same randomness as offline: runs with no
forced commit are also the runs with the fastest hops.

### Live under real-time pacing, 8 runs, instrumented build

The feed is paced at wall-clock speed, so a decode that takes longer than the hop
makes the decoder drop the next hop. Only the instrumented build was run this way.

| | Median (min–max) |
| --- | --- |
| WER | 26.6% (23.4–35.9%; IQR 3.3) |
| Words, reference 128 | 120 (113–123) |
| **Dropped hops** | **8 of 38 (4–11)**; 27 to 34 decodes completed |
| Forced commits | 7 (0–11) |
| Unagreed tail words | 28.5 (3–37) |
| Model time per hop | 1414 ms (1049–1587) |
| Per-decode p95 of `inferMs` (one run's p95) | 1.7 to 3.2 s (runs 3 and 1) |
| **Commit latency, audio clock** (each run's median word) | **12.1 s (5.8–14.4)** |
| Commit latency, wall clock (each run's median word) | 13.8 s in run 1, 7.5 s in run 3 |
| Replay RTF | 1.069 (1.065–1.081), by construction |

On this Mac the **per-decode time sits at the hop**: the mean decode of 1.4 s is
nearly the 1.5 s hop, and the p95 is two to three times it, so real-time pacing
drops 4 to 11 of the 38 hops (the M5 Pro dropped 4 of 38; [Live
transcription](#live-transcription)). Nothing was lost: the WER is the same as
with awaited decodes, because LocalAgreement waits for the next pass.

**The commit latency here is long, and this clip cannot tell you what the product
does.** All 24 live runs had 0 boundaries and 0 final decodes: the voice detector
found no pause of 700 ms in the 57 seconds, so no word was ever committed at an
utterance boundary. Words commit only when two consecutive passes agree on them or
when the window is about to slide and the decoder forces them. The runs split by
the number of forced commits: the three runs with none (3, 5 and 6) have a median
commit latency of 5.8 to 7.1 s, and the five with 5 to 11 forced commits have 12.1
to 14.4 s. Real speech has pauses, so **do not read 12 s as the latency of the
product.** It is the latency of the commit policy on speech that never stops. The
harness reports it so that a change to the commit policy shows up as a change in
this number. Why agreement takes so long on this clip has not been isolated.

### Memory: footprint and the model

Instrumented build, 12 offline and 8 live runs; the figures were the same in
live and offline:

| Stage (median) | Process footprint | Neural Engine memory owned by the process |
| --- | ---: | ---: |
| process start | 1 MB | 0 MB |
| after the audio is mapped, before the model loads | 8–9 MB | 0 MB |
| **after the model loads** | **76–77 MB** | **1580 MB** |
| after the voice model loads | 76–77 MB | 1580 MB |
| end of the run | 85–130 MB | 1580 MB |

| Process figure | Value |
| --- | --- |
| Lifetime peak footprint, `/usr/bin/time -l` (pure build, 12 offline runs) | **150 MB** (149–254) |
| Lifetime peak footprint (instrumented build, 12 offline runs) | 150 MB (142–245) |
| Footprint at exit, what the pure build printed as "peak memory" | 138 MB (89–248) |
| Maximum resident set size, `/usr/bin/time -l` | 274 MB (239–281) |

`footprint(1)`, sampled from outside the process every 0.25 s during an offline
run (`eval/residency.py`), agrees. At the first sample after the model reported
"Ready" it showed 114 MB of footprint and **1581 MB** under "Owned physical
footprint (unmapped) (neural) (nofootprint)", and `neural_peak: 1581 MB`; its
`phys_footprint_peak` was 150 MB, the same figure as the ledger's lifetime peak.
(A hand-run probe at about the same moment of a run showed 77 MB and 1581 MB.) The
in-process stages above read 76 to 77 MB right after the load and before the voice
model and the decode, and the footprint then rises to its peak during the decode.
**The model costs 1.58 GB and a build can show a footprint of 77 MB.** What the
pure build printed, "peak memory 100 MB" in a first run and 138 MB median over
twelve, is a single reading at exit and is neither the peak (the lifetime peak
was 150 MB, up to 254 MB) nor the model.

### Is the instrumented build slower?

**No effect was found, and one session suggested a large one that did not
repeat.** The instrumented build adds a thin wrapper around the recognizer (it
records the wall time of each call and forwards it unchanged), a few memory
readings and one counter. The model's own `inferMs` is measured inside the call
that the wrapper forwards to, so the wrapper cannot lengthen it by construction.
The measurements, each interleaved A B B A …:

| Session | Runs per build | Replay RTF, pure → instrumented | Model time per hop, pure → instrumented | Permutation p (hop) |
| --- | ---: | --- | --- | ---: |
| live, first session (above) | 8 | 0.859 → 1.003 | 1276 → 1491 ms | **0.003** |
| live, repeated later | 8 | 0.901 → 0.910 | 1340 → 1353 ms | 0.73 |
| offline (whole-file RTF) | 12 | 0.097 → 0.134 | not reported | 0.085 |

The first live session gave a 17% slower hop at p = 0.003. The repeat gave 1%.
**A gap of that size between two builds of identical decode code, at p = 0.003,
came from the shared machine and not from the build**, and it is the reason the
verdict line asks for a second session. The pure build's own median per hop was
1276 ms in the first session and 1340 ms in the second; the byte-identical pair
below gave 1387 and 1392 ms. Medians of 8 runs of the same code moved by 8% to 17%
between sessions. Treat a timing difference below about 15% as unresolved until it
repeats, and run timing comparisons when nothing else is running.

### A calibration run: two identical binaries

To see what the harness says when nothing differs, the pure build was copied byte
for byte to a second path (the SHA-256 of both is `88c45191…`) and the two were
run interleaved, live, 8 runs each, with the same command as above:

| | Pure, path 1 | Pure, path 2 (identical copy) | Difference | p |
| --- | --- | --- | ---: | ---: |
| WER | 23.8% (21.9–26.6) | 26.2% (24.2–28.1) | +2.3 points | **0.041** |
| Replay RTF | 0.933 | 0.936 | +0.004 | 0.91 |
| Model time per hop | 1387 ms | 1392 ms | +5 ms | 0.91 |
| Forced commits | 6 (5–10) | 5.5 (0–10) | −0.5 | 0.33 |
| Collapsed runs | 0 of 8 | 0 of 8 | | 1.0 |

**The verdict line called this "SIGNIFICANT"** (permutation p = 0.041, bootstrap
interval +0.4 to +3.9 points, so both criteria passed) for two copies of one
binary. One such result is not a false-positive rate: at a 5% level, one in 20
comparisons is expected to do this, and this was one comparison. It is a
demonstration of what a single significant result at n = 8 is worth, and of how
far the median of 8 runs of the same code can move: the pure build's live WER
median was 27.3% in the first session, 28.9% in the second and 23.8% here.
Hence the line "CONFIRM BEFORE ACTING" on any significant verdict with fewer
than 12 runs per arm.

## Headline results

**These headline numbers are from the MacBook Pro M5 Pro.** For the Mac mini M2 Pro,
with n = 12, see [the 2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro).

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

### The pause filter

The paused synthetic clip (87 s, 25 pauses of 1.2 s) exercises the utterance
boundary. On 2026-09-06 the decoder started to drop, from each hypothesis, a
word that starts inside a pause that the voice detector found. Every decode
awaited, Balanced tier:

| Paused clip, live replay | WER | Words | Tail words committed unagreed | Deduplicated by text |
| --- | ---: | ---: | ---: | ---: |
| before the filter | 51.6% | 122 | 59 | 14 |
| **with the filter** | **39.1%** | 127 | 46 | 17 |

The clips with no pause of 700 ms do not change. Finding 12 in
[FINDINGS.md](FINDINGS.md) gives the mechanism.

### A style primer in the prompt

A sentence of Taglish before each window, as a hint for the spelling. Measured
on 2026-09-06 with `transcribe --style-hint`, Balanced tier:

| Clip | Path | No primer | Primer |
| --- | --- | ---: | ---: |
| synthetic | offline | 24.2% | 44.5% |
| synthetic | live | 27.3% | 96.1% |
| meeting01 | offline | 71.7% | 65.0% |
| meeting01 | live | 63.3% | 280.0% |

**The app does not send the primer.** On the live path the model repeats the
primer instead of the room. The Names and terms field of the app is a short
list, and this measurement does not cover short prompts.

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

Two different questions, two different figures. Read
[Which number is which](#which-number-is-which) first.

| Question | Figure | Value |
| --- | --- | ---: |
| What does the loaded model occupy? | Neural Engine memory owned by the process, large-v3-turbo (Balanced) | approximately 1.6 GB (1580 MB measured on the Mac mini M2 Pro on 2026-11-01, constant across 12 runs) |
| What do the two speaker models occupy? | Neural Engine memory | approximately 200 MB, **not re-measured** |
| What does the process cost to run? | Lifetime peak **footprint** of a whole-file run on the test clip | 150 MB median, 142 to 254 MB over 24 runs (Mac mini M2 Pro, 2026-11-01) |

The figure that earlier versions of this file gave for the process, "approximately
300 MB, as `transcribe` reports it", was `phys_footprint` read once at exit. It
was not a peak, and it does not contain the model: on the Mac mini M2 Pro the
footprint after the model loaded was 76 MB, and the 1580 MB of the model sat
beside it in the Neural Engine figure. See
[the 2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro).

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

## Compare two builds

**One run proves nothing.** The offline pass is not deterministic: eight
identical runs of the synthetic clip gave WER from 25% to 57%
([FINDINGS.md](FINDINGS.md) entry 15). `eval/bench_runs.py` is the harness that
every claim of "faster" or "more accurate" is judged by. It uses only the Python
standard library and the existing `transcribe` binary, and it scores with
`eval/score.py` and `eval/langscore.py`.

```bash
# Baseline and candidate, alternating, 12 runs each (24 launches)
python3 eval/bench_runs.py run --interleave BASE/transcribe CAND/transcribe \
    --labels base cand --audio eval/audio/synthetic-taglish.wav \
    --ref eval/synthetic-taglish.txt --mode offline --runs 12 --out-dir /tmp/ab-offline

# The same for the live path. Add --realtime to measure drops under real-time pacing.
python3 eval/bench_runs.py run --interleave BASE/transcribe CAND/transcribe \
    --audio ... --ref ... --mode live --runs 8 --out-dir /tmp/ab-live

# Re-print a comparison from the saved summaries
python3 eval/bench_runs.py compare /tmp/ab-offline/A/summary.json /tmp/ab-offline/B/summary.json
```

`--order abba` alternates which build goes first (A B, B A, A B, …) and cancels
a steady drift in temperature or background load that strict `abab` would charge
to the second build. `run` also takes a single `--bin`, for a baseline with no
partner. Every measured launch goes through `/tmp/notero-team/bench-lock.sh`
when that file exists, one launch at a time, and `--no-lock` turns that off.
`--extra …` passes the rest of the line to `transcribe`.

**What the harness writes.** For each run: `run-NN.json` (the command, the
binary's SHA-256, the scores, the live counters, the memory stages, the full
`transcribe` report), `run-NN.report.json` and `run-NN.stderr.txt`. For each arm:
`summary.json` with the median, minimum, maximum and interquartile range of the
WER, the word count, the RTF and `decodeMs`; for live runs the dropped hops, the
forced commits, the unagreed tail words, the per-decode RTF and the commit
latency; the machine's load average at each launch; the environment.
A failed run is reported as a failure and is not silently dropped.

**Collapsed runs, reported apart from the median.** A single collapsed window is
the dominant noise source on the synthetic clip, so each summary counts the runs
that collapsed, by this rule, which is printed in every summary and comparison:

> A run is **collapsed** if its WER is more than 2x the median WER of the arm's
> best half of runs (the ceil(n/2) lowest), or if it produced fewer than 75% of
> the reference's words.

The rule is relative to the arm itself, so an arm that is uniformly bad has no
collapsed runs. `compare` therefore also prints the candidate's runs above the
*baseline's* threshold. Runs with invented-filler phrases that the reference
does not contain ("thanks for watching") are counted as an explanation, and they
play no part in the rule.

**What `compare` computes.** For the median WER difference, a two-sided
permutation test on the difference of medians (exact when there are at most
250,000 arrangements, so up to 10 against 10 runs, and otherwise 100,000 seeded
shuffles) and a seeded percentile bootstrap 95% interval (10,000 resamples). For
the collapsed-run counts, Fisher's exact test, two-sided. The other rows (RTF,
words, the live counters) carry a permutation p-value too. The WER row is the
primary test and the rest are secondary and not corrected for multiple
comparisons. Nothing assumes a distribution, and the median and the IQR describe
a mixture of "fine" and "collapsed" runs better than a mean does.

**The verdict line refuses.** It gives `NO VERDICT` when either arm has fewer
than 8 successful runs, whatever the difference. It also refuses when the arms
were not interleaved in one session, when they differ in audio, reference or
mode, and it never says "equivalent": not significant means that the arms could
not be told apart at this n. A difference counts as significant only when the
permutation test gives p < 0.05 **and** the bootstrap interval excludes zero.
At n = 8 the test has little power: a real difference smaller than the spread
between collapsed and healthy runs will usually come out "not significant". It
can also come out "significant" when nothing differs: an **A/A comparison of two
byte-identical binaries at n = 8 gave a significant WER difference** (+2.3
points, permutation p = 0.041, interval +0.4 to +3.9), see
[the calibration run](#a-calibration-run-two-identical-binaries). The verdict
line therefore adds **CONFIRM BEFORE ACTING** to any significant result with
fewer than 12 runs per arm. Repeat it in a second interleaved session before you
act on it.
The tests that carry this are in `tests/test_benchstats.py`, with reference
values worked out by hand or taken from published tables. When they were written,
five deliberate bugs were put into the code one at a time, and the tests caught
each of them.

**RTF moves with background load.** The lock serializes measured runs only.
Builds and tests by other processes do not take it. In the baseline below, the
machine's load average was 2 to 6 for the whole session, and single offline runs
came out up to 2 times slower than the median. The median and the IQR absorb
that, and the per-run `loadavg_1m_at_launch` in each summary lets you see it. For
a timing claim, run when the Mac is quiet and read the IQR.

## Test material that exists

| Clip | Audio on disk | Reference on disk | Notes |
| --- | --- | --- | --- |
| `synthetic-taglish` | `eval/audio/synthetic-taglish.wav`, 57 s, in the maintainer's checkout. `eval/audio/` is git-ignored, so a fresh clone has no audio. `eval/make-synthetic.sh` rebuilds it. | `eval/synthetic-taglish.txt`, tracked | 123 words by whitespace, **128 after `score.py` splits hyphens** ("i-send" is two words). Synthetic, Indonesian voice, starts at full amplitude. |
| `meeting01` | **absent** | **absent** (`eval/refs/` holds only `.gitkeep`) | `eval/manifest.json` references it, so `compare_language.py` prints "skipping clips with no audio or reference on disk: meeting01" and scores one clip. The 25 s excerpt behind the older tables is not on this Mac. |
| the paused clip (87 s) | **absent** | derived from the synthetic text | `eval/make_paused.py` rebuilds it. Not generated here. |
| multi-speaker fixtures | not in this branch | RTTM, exact boundaries | The diarization work owns `eval/make_multispeaker.py`. Synthetic text-to-speech voices. |

There is **no real Taglish recording with a clean reference, and no real
diarization ground truth, on any machine that this project has measured on.**
Every accuracy figure in this file is a comparison on a synthetic clip. None is a
claim about real Taglish.

## What real data is needed

Nothing here is invented. This is the protocol for collecting data that would
let this project make a claim about real speech.

**Amount.** At least 30 minutes of audio in at least 5 recordings of 3 to 10
minutes each. The reason is arithmetic: the synthetic clip has 128 words, and one
collapsed 25-second window of about 40 words moves its WER by 31 points. In a set
of 30 minutes (roughly 4,000 words) the same window moves the pooled WER by one
point, and the set holds enough windows for a rate of collapses to mean something.

**Speakers and rooms.** At least 3 different speakers across the set, with at
least 2 in each recording used for diarization, mixed Tagalog and English as the
speakers really talk. Include the primary case of this app (several people across
a room, far-field) and a close-microphone or headset case. Do not make the
set from one speaker or one room.

**Consent.** Every person on a recording agrees, before it is made, to the
recording **and** to its use as an evaluation reference, in writing. That
includes remote participants of a call. Recordings of anyone who has not agreed
do not enter the set. The audio, the references and every output stay on the
local disk, in `eval/audio/` and `eval/refs/`, which git ignores. They do not go
to a cloud transcription service, to this repository, to an issue or a pull
request, or to a language-model tool. Delete a person's recordings on request.

**Reference format.** One UTF-8 `.txt` file per recording, one utterance per
line, **verbatim as spoken**:

- Spell each word in the language in which it was said, including the English
  words inside a Tagalog sentence. Keep fillers and particles ("ah", "eh",
  "po"), false starts and repeats: the scorer counts them.
- No speaker labels, no timestamps and no stage directions in the `.txt`. A
  label would be scored as a word. Speakers belong in the RTTM file below.
- Punctuation and case do not matter, because both scorers strip them. Write a
  hyphen inside a word as the speakers' written form has it ("i-send"); `score.py`
  splits it and `langscore.py` keeps it.
- Write numbers the way the speaker said them, and do it the same way throughout.
  The scorers do not know that "5" and "lima" are the same word.
- **Two independent transcribers, then adjudication.** Score transcriber 1
  against transcriber 2 with `eval/langscore.py` before adjudicating. That WER is
  the floor of the reference: a model that scores below it cannot be told from
  the reference's own noise. Record it beside the results.

Register each recording in a manifest next to the files, as
`eval/manifest.json` does: `{"id", "audio", "ref", "category"}`, with `category`
one of `tagalog`, `english` or `mixed`, and paths relative to the manifest.

**Diarization ground truth** is a separate annotation of the same recordings,
described in [the DER protocol](#the-der-measurement-protocol).

### Corrections exported from the app

In Advanced mode, **File › Export Corrections as References…** writes a folder
that `eval/compare_language.py --manifest` reads directly. It holds a copy of
each recording that has edits, the transcript with the edits applied as the
reference, and a `manifest.json` with `id`, `audio`, `ref` and `category`
(relative to the manifest), plus `raw`, `edits`, `title` and `durationMs` for the
reader. `ReferenceSet` in `app/Sources/TranscriberCore` writes it.

```bash
python3 eval/compare_language.py --manifest FOLDER/manifest.json \
    --bin app/.build/release/transcribe --arms tl
# One clip, repeated and interleaved, through the benchmark harness:
python3 eval/bench_runs.py run --interleave BASE CAND \
    --audio FOLDER/<audio from the manifest> --ref FOLDER/<ref from the manifest> \
    --mode offline --runs 12 --out-dir /tmp/ab-own
```

Read these references with five cautions:

1. **They lean toward the model.** A line the person did not edit counts as
   accepted, whether it was right or the person did not notice. A WER against a
   corrections reference therefore **understates** the true error, and it is the
   error rate the person *experiences*, not a ground truth.
2. **One reviewer, no adjudication.** There is no inter-annotator floor.
3. **Only recordings with edits are exported.** The set is biased toward the
   meetings where the model did worse.
4. **No speaker labels leave the export**, so it is no diarization ground truth.
5. **Consent still applies** to a folder that you made yourself from a meeting
   with other people in it.

Use corrections references to compare two builds on your own meetings, with the
same n and the same rules as above. Do not use one as the figure for how accurate
the model is.

## The DER measurement protocol

This section defines the protocol only. **The diarization work owns the code**,
in its own worktree, and this repository's benchmark files do not duplicate it:

| File | Owner | What it is |
| --- | --- | --- |
| `eval/der.py`, `tests/test_der.py` | diarization | Frame-level DER scorer; RTTM or `diarbench` JSON in |
| `eval/make_multispeaker.py` | diarization | Synthetic multi-speaker fixtures with exact boundaries |
| `eval/run_diarization_ab.py` | diarization | A/B runner over `diarbench` |
| `app/Sources/DiarizationBench/` (`diarbench`) | diarization | Speaker processing only, no ASR, no VAD |
| `eval/benchstats.py` | benchmark | The statistics below. Import it; do not copy it. |

(File names are those of the diarization worktree's commits `b343fdf` and
`346308b` at the time of writing; they are not in this branch.)

**The metric.** Diarization error rate is

```
DER = (missed speech + false alarm + speaker confusion) / total reference speech
```

counted per speaker per frame (two people talking at once count twice), after the
best one-to-one mapping between hypothesis and reference speakers, with a
**0.25 s collar** around every reference turn boundary removed from the score
(the NIST convention). Report the three components and the total, never the total
alone, and add the **speaker count error** (hypothesis speakers minus reference
speakers), because the failure that this app has measured is a fused or a split
speaker (finding 10). Report a collar of 0 s beside the 0.25 s figure.

**Inputs.**

- *Synthetic fixtures* from `make_multispeaker.py`: text-to-speech turns with
  exact boundaries. They support an **A/B comparison on the same file**. They say
  nothing about real meetings: no breath, no room, no crosstalk, and voices more
  consistent than people. State the fixture name, the seed, the voices and the
  macOS version with every number.
- *Real recordings*, when they exist: at least 10 minutes with at least 3
  speakers, including overlap and one-word backchannels, with an RTTM made by
  **two annotators** and reconciled. Same consent rules as above.

**Runs and statistics.**

1. **Establish determinism first.** Run each arm 3 times on each fixture and
   hash the output. If every hash is the same, a single run per fixture is the
   measurement and no statistical test applies; say that "3 identical runs" was
   the evidence. If the outputs differ, a single run proves nothing, as for the
   ASR: run **at least 8 interleaved A/B runs per arm per fixture**, and compare
   the DER with `benchstats.permutation_p_value`, `benchstats.bootstrap_ci` and
   `benchstats.verdict`, which refuses below 8 runs.
2. **Interleave** A and B, and take `/tmp/notero-team/bench-lock.sh` for each
   launch, because speaker models run on the Neural Engine too.
3. **Pool by speech time.** The pooled DER is the sum of all errors over the sum
   of all reference speech across fixtures, not the mean of per-fixture DERs, so
   a long file counts for more than a short one. Print the per-fixture table.
4. **Name every regression.** A candidate that improves the pooled DER and makes
   one fixture worse is not "better": it is better on some fixtures. The
   `two-similar` fixture (two like voices trading short turns, the finding-10
   case) is the one a fusion regression shows on.
5. **Five synthetic fixtures are five data points about the generator.** They do
   not support a claim about meetings, and a gain that appears on them alone is
   an EXPERIMENT, not an IMPLEMENT.

**Resource side.** Report the wall time of the speaker work and the memory, with
the rules of [Which number is which](#which-number-is-which): `diarbench` prints
the process's peak physical footprint, which **does not include the Neural Engine
memory of the speaker models**. Quote the footprint and the Neural Engine figure
together (`transcribe`'s `memory` stages or `eval/residency.py`), and never read a
smaller footprint as smaller models.

## Limitations

1. **One machine at a time.** The tables above the dated baseline come from one
   MacBook Pro M5 Pro. The [2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro)
   comes from one Mac mini M2 Pro, which is the hardware that the app targets,
   and it is slower. The two sets of numbers are not interchangeable.
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
   Best tier or the Fast tier gives a better or a worse transcript.
   [MODELS.md](MODELS.md) lists which tier promises this project measured,
   and which ones it infers.
7. **One run is not a measurement.** The same build gives a different
   transcript of the same file on different runs. Over eight offline runs of
   the synthetic clip, the WER went from 25% to 57%, because the first window
   sometimes comes back as invented English filler. [FINDINGS.md](FINDINGS.md)
   entry 15 gives the numbers. Run each build several times, and compare the
   spread.
8. **The shared Mac moves the timings.** The bench lock serializes measured
   runs and nothing else. Builds, tests and other agents' work ran at the same
   time as the baseline (load average 1.6 to 6.4), and one agent held the lock
   for long stretches. RTF and per-hop time vary with it. Read the median and the
   interquartile range, and re-run a timing claim on a quiet Mac.
9. **The reference has two word counts, one for each scorer.**
   `synthetic-taglish.txt` has 128 words for `eval/score.py` and for the CLI's
   own scorer, which split "i-send" into two, and 123 for `eval/langscore.py`,
   which keeps the hyphen. The same transcript therefore scores differently: run
   1 of the pure offline baseline is 31.3% by `score.py` and 34.1% by
   `langscore.py`. The tables from 2026-11-01 use `score.py`.
10. **The collapse rule is relative to the arm.** It misses a collapse when an
    arm's ordinary WER is high, and it cannot flag an arm that is bad in every
    run. `compare` adds a check against the baseline's level, and the count of
    invented-filler phrases explains a collapse. Neither is a detector for every
    failure.
11. **Memory figures describe one process.** None describes the whole machine, and
    none of the footprints contains the model. [Which number is which](#which-number-is-which)
    says what each figure is.
12. **The findings are engineering results and not product guarantees.** The
   caveat section of [FINDINGS.md](FINDINGS.md) says which findings are
   structural, and which ones must be derived again against your own
   recordings.

## Measure your own audio

**Your corrections are the best references you have.** In Advanced mode,
**File › Export Corrections as References…** writes a folder with a copy of
each recording that has edits, the edited transcript as the reference, and a
`manifest.json`. Point the harness at it:

```bash
python3 eval/compare_language.py --manifest FOLDER/manifest.json \
    --bin app/.build/release/transcribe --models models --arms tl
```

The folder's `summary.md` also gives the raw model text scored against your
corrections, with no new decode. That number is the error rate you experience.

To compare two builds on your own audio, repeat and interleave them, with the
rules of [Compare two builds](#compare-two-builds): a single run of one build
against a single run of another proves nothing.

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
