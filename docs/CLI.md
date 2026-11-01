# The `transcribe` command-line tool

`transcribe` runs the same pipeline as the app, with no window. Use it for
evaluation, for measurement and for continuous integration.

**It is not a second implementation.** It calls `OfflinePipeline`,
`LiveDecoder`, `SpeakerEngine` and `Exporter` exactly as the app does. It
therefore verifies the real path on real audio with no window, no microphone
and no person.

## Build

```bash
cd app && swift build -c release --product transcribe
```

The binary is at `app/.build/release/transcribe`.

## Usage

```bash
./.build/release/transcribe --audio meeting.m4a --reference truth.txt --format srt
```

```
transcribe --audio FILE [--reference FILE] [--models DIR]
           [--model ID | --tier fast|balanced|best]
           [--language tl] [--prompt "Maria, Jose"] [--style-hint]
           [--fast-diarize | --no-diarize] [--room-mode]
           [--format txt|markdown|srt|vtt|json] [--out FILE] [--json FILE]
           [--live [--realtime] [--hop MS] [--pre-roll MS] [--context MS] [--adaptive-hop]]
transcribe --audio FILE --lane room|remote
transcribe --record [--source microphone|systemAudio|both] [--device UID]
           [--seconds N] [--out FILE.m4a] [--gui]
transcribe --mic-check [--device UID] [--seconds N] [--gui]
transcribe --devices
transcribe --channels [--seconds N]
```

`--help` prints these lines. An unknown option stops the tool with exit code 2.

## Examples

Transcribe a file and print the text:

```bash
./.build/release/transcribe --audio meeting.m4a
```

Transcribe with the model weights that this repository already holds, and write
subtitles:

```bash
./.build/release/transcribe --audio meeting.m4a --models models \
    --format srt --out meeting.srt
```

Score a transcript against a reference, and write a machine-readable report:

```bash
./.build/release/transcribe --audio clip.wav --reference clip.txt \
    --json out/run.json
```

Replay a file through the live path at wall-clock speed:

```bash
./.build/release/transcribe --audio clip.wav --reference clip.txt \
    --live --realtime --no-diarize
```

## Options

| Option | Function |
| --- | --- |
| `--audio FILE` | The audio or video file to transcribe. **Required.** |
| `--reference FILE` | A reference transcript, plain text or the JSON reference form. The tool then reports the WER, and the result of the evaluation framework. |
| `--models DIR` | Read the model weights from this directory. The default is `~/Library/Application Support/Transcriber/Models`. |
| `--model ID` | Use this WhisperKit model. It overrides `--tier`. [MODELS.md](MODELS.md) lists the ids. |
| `--tier fast\|balanced\|best` | Use the default model for this tier. The default is `balanced`. The flag also accepts `accurate`, which is the name that the `best` tier had before. |
| `--language CODE` | Force this language. The default is `tl`. `auto` selects automatic detection. |
| `--prompt TEXT` | Names and terms for the decoder, as the Names and terms field of the app. |
| `--style-hint` | Put the Taglish style primer of `TranscriptionPrompt` in front of the prompt. **The app does not do this.** Finding 12 in [FINDINGS.md](FINDINGS.md) gives the measurement: the primer made the live path worse. The flag exists to repeat that measurement. |
| `--fast-diarize` | Do one speaker pass only. |
| `--no-diarize` | Do no speaker identification. |
| `--room-mode` | Apply the high-pass filter for far-field room audio. |
| `--format txt\|markdown\|srt\|vtt\|json` | The export format. The default is `txt`. |
| `--out FILE` | Write the export to this file. Without it, the tool prints the export. |
| `--json FILE` | Write a machine-readable report to this file. |
| `--live` | Replay the file through the live path. |
| `--realtime` | With `--live`, feed the audio at wall-clock speed. |
| `--hop MS` | With `--live`, set the hop. The default is 1500. |
| `--pre-roll MS` | With `--live`, set the pre-roll. The default is 1500. |
| `--context MS` | With `--live`, set the context length. The default is 15000. |
| `--adaptive-hop` | With `--live`, shorten the hop while decodes are fast. |
| `--lane room\|remote` | Read one channel of a two-lane recording. Channel 1 is `room` and channel 2 is `remote`. |
| `--record` | Capture audio for `--seconds` and report the peak level of each lane. Refer to "Capture check". |
| `--source microphone\|systemAudio\|both` | With `--record`, the lanes to capture. The default is `microphone`. |
| `--device UID` | With `--record` or `--mic-check`, the microphone to use. `--devices` gives the UID. The default is the default input of macOS. |
| `--seconds N` | With `--record`, `--channels` or `--mic-check`, the capture time in seconds. The default is 10. |
| `--gui` | With `--record` or `--mic-check`, make the tool a foreground application, thus macOS can show the permission prompt. |
| `--mic-check` | Capture a take for `--seconds`, then play it back. Refer to "Microphone check". |
| `--devices` | List each audio device with its channel counts and its UID, then stop. |
| `--channels` | Capture the raw channels of the combined device and report the peak level of each channel. |
| `--log FILE` | Write a copy of the stderr output to this file. |
| `--eval-config FILE` | With `--reference` or `--score`, the evaluation configuration. The default is the content of `eval/evaluation-config.v1.json`. |
| `--policy ID` | With `--reference` or `--score`, use this scoring policy. It replaces the policy of the configuration. |
| `--eval-json FILE` | With `--reference`, write an evaluation report for this one recording. |
| `--eval-md FILE` | With `--reference`, write the same report as Markdown. |
| `--label NAME` | The name of the system in an evaluation report. |
| `--model-revision REV` | Record this model revision. Without it, the tool reads the revision from the local download cache. |
| `--build ID` | Record this build, for example a commit. |
| `--score MANIFEST` | Score saved transcripts. Refer to "Score saved transcripts". The tool needs no `--audio` and loads no model. |
| `--hypotheses DIR` | With `--score`, the folder of transcripts to score. |
| `--compare DIR` | With `--score`, a second folder of transcripts. The tool compares it with `--hypotheses`. |
| `--compare-label NAME` | With `--compare`, the name of the second system. |
| `--corpus-id ID` | With `--score`, the corpus ID. It replaces the ID of the manifest. |
| `--out-dir DIR` | With `--score`, write the reports to this folder. Without it, the tool prints the Markdown report. |
| `--print-eval-config` | Write the evaluation configuration as JSON, then stop. |

The default speaker mode is `accurate`. Use `--fast-diarize` or `--no-diarize`
to change it.

## Output formats

`--format` selects the export, which is the same exporter that the app uses:

| Format | Contents |
| --- | --- |
| `txt` | The speaker labels and the notes. |
| `markdown` | Minutes: attendees, summary, action items with checkboxes, then the transcript. |
| `srt` | Subtitle cues in order, which do not overlap. |
| `vtt` | The same cues as WebVTT. |
| `json` | The complete meeting document. |

## What the tool reports

The tool writes its progress and its measurements to stderr, and the export to
stdout or to `--out`. It reports:

- The duration of the audio and the sample count.
- The model id that it loaded.
- The speech regions and the windows that the voice detector found.
- The number of decoded words, the decode time and the RTF.
- The number of windows that needed a retry: a lead-in of silence, wider audio or half the window. Builds before 2026-11-01 printed "a warmer retry".
- **A warning for each window that never decoded.** That audio is missing from
  the transcript. Finding 9 in [FINDINGS.md](FINDINGS.md) explains why this
  warning exists.
- The model load time, which no RTF includes.
- The cost of each call to the recognizer, apart from the RTF: median, p95 and
  maximum of the model's own time and of the wall time around it.
- With `--live`, the **commit latency**: how far behind the audio each committed
  word trails. With `--live --realtime`, the same against wall time.
- The number of speakers and the time that speaker identification took.
- The WER, if you gave `--reference`. Then also the line `evaluation (…)` with
  the WER, the substitutions, deletions and insertions, the CER and, with a
  timed JSON reference, the share of missing speech.
- **Memory, in two lines.** The footprint of this process at exit, its lifetime
  peak footprint, and its footprint before and after the model loads. Then the
  Neural Engine memory that the process owns, which the footprint does not
  include. Until 2026-11-01 the tool printed one line, `peak memory N MB`. N was
  `phys_footprint` read once at exit. It was not a peak and it was not the
  model's memory: after the model loaded, the footprint was 77 MB and the Neural
  Engine memory was 1581 MB. [BENCHMARKS.md](BENCHMARKS.md#which-number-is-which)
  says which figure answers which question.
- The total time.

### The WER

`--reference FILE` scores the transcript against the file with
`WordErrorRate.score`. The tool prints the score as a fraction and as a
percentage, for example `WER 0.2734 (27.3%)`.

The WER of this tool splits an intra-word hyphen. `eval/langscore.py` keeps it,
thus "i-send" stays one Filipino word there. The two scorers therefore report
different numbers for the same transcript. [BENCHMARKS.md](BENCHMARKS.md) says
which scorer produced each number.

The `evaluation (…)` line comes from the evaluation framework. It names its
scoring policy. With the default policy, `notero-standard`, it gives the same
words as `eval/score.py`. `WER 0.2734` is from the older scorer, which has not
changed. The two lines can therefore show different values.
[BENCHMARKS.md](BENCHMARKS.md#the-evaluation-framework) gives the method.

### The JSON report

`--json FILE` writes the `RunReport` structure, which
`eval/compare_language.py` reads. It holds the audio path, the mode, the model,
the language that you asked for, the language that the model detected, the
language of each window, the duration, the decode time, the RTF, the word
count, the transcript, each token, the WER, the live statistics and the live
configuration.

Six fields are for the benchmark harness, and each is optional: a report from an
older binary lacks them, and a reader has to cope.

| Field | Contents |
| --- | --- |
| `loadMs` | Wall time to load the model. |
| `decodeTiming` | Per-call recognizer cost: `calls`, `inferRtf`, `wallRtf`, mean, median, p95 and maximum of `inferMs` and of the wall time. |
| `commitLatency` | Live only. Words committed, with minimum, median, mean, p95 and maximum of (audio fed so far − the word's end time), and `aheadOfAudio`, the number of words that ended after the audio fed so far. |
| `commitLatencyWall` | Live with `--realtime` only. The same, against wall time since the replay began. |
| `memory` | A list of snapshots at the stages `start`, `beforeModelLoad`, `afterModelLoad`, `afterVADLoad`, `afterDecode` and `end`. Each holds `physFootprintMB`, `lifetimePeakFootprintMB`, `residentMB`, `internalMB`, `externalMB`, `compressedMB`, `neuralMB` and `neuralPeakMB`. |
| `windows` | Offline only. The decode windows in order, each `{startMs, endMs}`. `eval/regress.py determinism` uses it to name the window in which two runs of one binary first differ. A live replay has none. |

Three fields are for the evaluation framework. Each is optional.

| Field | Contents |
| --- | --- |
| `evaluation` | With `--reference` only. The score of `transcript`: WER, CER, the counts, the utterances and the breakdowns. Refer to [BENCHMARKS.md](BENCHMARKS.md#the-evaluation-framework). |
| `provenance` | The label, the model, the model revision, the hardware, the inference settings and the build. |
| `performance` | The whole-file RTF, the live commit latency, the process peak footprint and the model residency, each apart, each "unavailable" when the run did not measure it. |

`transcribe --score` reads these reports as hypotheses.

In a live report, `rtf` is the **replay** RTF, not a per-hop cost. With every
decode awaited it is how fast the Mac replays the file. With `--realtime` it is
about 1.0 by construction.

## Score saved transcripts

`--score` applies the evaluation framework to transcripts that already exist.
It loads no model, opens no audio device and uses no network.

```bash
# One system:
./.build/release/transcribe --score ../eval/fixtures/scoring/manifest.json \
    --hypotheses ../eval/fixtures/scoring/hyp-baseline --out-dir /tmp/eval-one

# Two systems on the same references, with a paired bootstrap:
./.build/release/transcribe --score ../eval/fixtures/scoring/manifest.json \
    --hypotheses ../eval/fixtures/scoring/hyp-baseline --label baseline \
    --compare ../eval/fixtures/scoring/hyp-candidate --compare-label candidate \
    --out-dir /tmp/eval-ab
```

For each manifest item, the tool reads `<id>.json` from the hypothesis folder.
This is the `--json` report of a `transcribe` run. If there is no such file,
it reads `<id>.txt`, plain text from any system. To make the hypotheses of one
build, run `transcribe --audio … --json DIR/<id>.json` once for each item.

An item without a reference or without a hypothesis is "unavailable" in the
report, with the reason. The corpus figures do not include it. The tool exits
with 3 when no item of a system could be scored.

[BENCHMARKS.md](BENCHMARKS.md#the-evaluation-framework) describes the reference
forms, the scoring policies, the metrics, the intervals and the output files.

## Live mode

`--live` replays the file through the live path instead of the whole-file path.
It uses the same ring buffer, the same voice detector, the same hop schedule,
the same LocalAgreement policy and the same finalization as a recording. It
feeds the decoder 100 ms at a time.

**By default the tool waits for each decode.** The schedule then runs as if the
model were infinitely fast, and nothing is dropped. This measures the
mechanism, and not the machine.

`--realtime` paces the feed at wall-clock speed instead. This measures the
drops on your machine. Use it when you want to know whether your Mac keeps up.

Live mode reports the number of decodes, the dropped hops, the silent hops, the
forced commits, the boundaries, the final decodes, the abandoned
finalizations, the unagreed tail words, the empty finals, the deduplicated
words and the mean RTF. A failed decode raises a warning with the last error.

## Benchmark output

The tool prints the RTF for each run, and the peak memory at the end. To
compare tiers or languages over a set of clips, use the harness in `eval/`:

```bash
python3 eval/compare_language.py --bin app/.build/release/transcribe \
    --models models --tier balanced
```

This runs `tl` and `auto` over `eval/manifest.json`, scores each run with
`eval/langscore.py`, and writes a Markdown table and a JSON file.
[BENCHMARKS.md](BENCHMARKS.md) holds the results, and
[LEGACY-SERVER.md](LEGACY-SERVER.md) describes the rest of the harness.

**Do not build while a `--realtime` run is in progress.** The build competes
for the machine and changes the drop count.

### Repeated runs and an A/B comparison

One run proves nothing: the offline pass is not deterministic (finding 15 in
[FINDINGS.md](FINDINGS.md)). `eval/bench_runs.py` runs a binary several times, or
two binaries interleaved, summarizes with the median and the range, counts the
collapsed runs, and compares two builds. `eval/regress.py` does the same over a
whole suite in one command. Both decide with one rule (rank-sum permutation tests,
Holm's correction over every metric together, effect-size floors, timing believed
only on a quiet machine) and one collapse rule, and both refuse below 8 runs per arm.
[BENCHMARKS.md](BENCHMARKS.md#compare-two-builds) gives the commands and the rules,
and [how often the rule raises a false alarm](BENCHMARKS.md#how-often-this-harness-cries-wolf).
`eval/residency.py` measures the memory of a run from outside the process, with
`footprint(1)`.

```bash
# One clip, two builds
python3 eval/bench_runs.py run --interleave BASE/transcribe CAND/transcribe \
    --audio clip.wav --ref clip.txt --mode offline --runs 12 --out-dir /tmp/ab

# A whole suite, two git revisions (built from `git archive` into /tmp/notero-regress)
python3 eval/regress.py --base addf5f8 --cand HEAD --suite quick
```

`regress.py` takes these options. A BUILD is an executable `transcribe`, a git revision, or
`WORKTREE` (the working copy of `app/`).

| Option | Function |
| --- | --- |
| `--base BUILD`, `--cand BUILD` | The two builds. `--base` may be omitted when `--baseline` names a commit. |
| `--suite quick\|full` | `quick`: the synthetic clip offline and live, DER on two synthetic multi-speaker clips. `full` adds the paused clip, five more multi-speaker clips and the FLEURS subset when present. |
| `--only SERIES …` | Run only these series: `offline-synthetic`, `live-synthetic`, `live-paused`, `offline-fleurs`, `der-quick`, `der-full`. |
| `--runs N` | Runs per arm for the transcription series (default 8). `--rounds N` sets the DER rounds. |
| `--order abba\|abab` | The interleave order. `abba` (the default) alternates who goes first. |
| `--out-dir DIR` | Where `report.md`, `report.json`, `plan.json` and the raw runs go. Default `/tmp/notero-regress/reports/<session>-<base>-<cand>`. |
| `--confirm-with REPORT.json` | A report of an earlier session of the same pair: only a metric that it flagged and this one reproduces is CONFIRMED. |
| `--baseline FILE` | A committed baseline from `eval/baselines/`. Prints a baseline drift warning when the machine, OS, model or fixture differs. |
| `--dry-run` | Resolve the builds and fixtures and print the plan, running nothing. |
| `--scratch DIR`, `--fixture-dir DIR`, `--fleurs-dir DIR` | Where builds and generated fixtures go (default `$NOTERO_REGRESS_SCRATCH` or `/tmp/notero-regress`), where to look for fixture audio first, and where FLEURS is. |
| `--hold-seconds S` | Aim for bench-lock holds of about this long (default 240). |
| `--no-lock`, `--no-build`, `--timeout S`, `--models DIR`, `--extra …` | Run unlocked (the report says so), never build, seconds per run, `transcribe --models`, and the rest passed to `transcribe`. |

Other commands: `regress.py reanalyze DIR` redoes the analysis of a stored session;
`regress.py determinism --bin BUILD --runs N` checks that one build gives byte-identical
transcripts and names the first diverging window; `regress.py stream --bin BUILD --runs N
--out-dir DIR` takes consecutive runs of one build for `eval/calibrate_aa.py`;
`regress.py save-baseline REPORT.json --name NAME --out FILE` writes a small baseline;
`eval/fixtures.py generate|verify|list|path` regenerates and checks the fixtures.

## Capture check

`--record` captures audio with the same `AudioCapture` that the app uses. It
reports the peak level of each lane each second. Use it to check that this Mac
permits a system audio tap, and that a two-lane recording puts the room in
channel 1 and the call in channel 2. The archive that `--out` writes can go
back into `--audio`, and `--lane` reads one channel of it.

**macOS gives the system audio permission only to an app bundle.** A tool that
you start in a terminal gets no prompt and no error, and the capture delivers
no samples. Use `app/scripts/record-probe.sh`. It puts the tool in a signed
bundle and starts it through LaunchServices.
[DEVELOPMENT.md](DEVELOPMENT.md) describes the script.

`--devices` lists each audio device. `--channels` shows the peak level of each
raw channel of the combined device, before the lane mapping. Use it if the
room and the call come out in the wrong channels.

`--record` exits with `0` when it heard audio, with `3` when no lane heard
anything, and with `1` for a failure.

## Microphone check

`--mic-check` lets you hear what the model hears. Speak for `--seconds`. The
tool then plays the take back through the default output and stops. Each
second it reports the peak level.

The take is the 16 kHz mono copy that goes to the model, not the archive. Use
it to hear clipping, noise, or the gaps of a Bluetooth link.

The check needs the microphone permission. Start it with
`app/scripts/record-probe.sh --mic-check --device UID`, for the same reason as
`--record`.

`--mic-check` exits with `0` after the playback, with `3` when it heard
nothing, and with `1` for a failure.

## Debugging

| Variable | Function |
| --- | --- |
| `TRANSCRIBE_DEBUG_SPANS` | Set it to any value to write each speech region and each speaker span to stderr. |

The tool checks that `--audio` exists before it starts. AVFoundation reports a
missing file as "The operation could not be completed", which sends people to
look for a codec problem that they do not have.

Exit codes: `0` for success, `1` for a failure during the run, and `2` for a
usage error.
