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
           [--model ID | --tier fast|balanced|accurate]
           [--language tl] [--prompt "Maria, Jose"] [--style-hint]
           [--fast-diarize | --no-diarize] [--room-mode]
           [--format txt|markdown|srt|vtt|json] [--out FILE] [--json FILE]
           [--live [--realtime] [--hop MS] [--pre-roll MS] [--context MS] [--adaptive-hop]]
transcribe --audio FILE --lane room|remote
transcribe --notes EXPORT.json [--notes-style english|spoken] [--notes-chars N]
           [--out DRAFT.md] [--json REPORT.json]
transcribe --record [--source microphone|systemAudio|both] [--device UID]
           [--seconds N] [--out FILE.m4a] [--gui]
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
| `--reference FILE` | A reference transcript. The tool then reports the WER. |
| `--models DIR` | Read the model weights from this directory. The default is `~/Library/Application Support/Transcriber/Models`. |
| `--model ID` | Use this WhisperKit model. It overrides `--tier`. [MODELS.md](MODELS.md) lists the ids. |
| `--tier fast\|balanced\|accurate` | Use the default model for this tier. The default is `balanced`. |
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
| `--device UID` | With `--record`, the microphone to use. `--devices` gives the UID. The default is the default input of macOS. |
| `--seconds N` | With `--record` or `--channels`, the capture time in seconds. The default is 10. |
| `--gui` | With `--record`, make the tool a foreground application, thus macOS can show the permission prompt. |
| `--devices` | List each audio device with its channel counts and its UID, then stop. |
| `--channels` | Capture the raw channels of the combined device and report the peak level of each channel. |
| `--log FILE` | Write a copy of the stderr output to this file. |
| `--notes EXPORT.json` | Draft the notes for a recording that the app exported as JSON, and score the draft. Refer to "Automatic notes". |
| `--notes-style english\|spoken` | With `--notes`, the language of the notes. The default is `english`. |
| `--notes-chars N` | With `--notes`, the characters of transcript per part. The default is 5000. |

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
- The number of windows that needed a warmer retry.
- **A warning for each window that never decoded.** That audio is missing from
  the transcript. Finding 9 in [FINDINGS.md](FINDINGS.md) explains why this
  warning exists.
- The number of speakers and the time that speaker identification took.
- The WER, if you gave `--reference`.
- The peak memory and the total time.

### The WER

`--reference FILE` scores the transcript against the file with
`WordErrorRate.score`. The tool prints the score as a fraction and as a
percentage, for example `WER 0.2734 (27.3%)`.

The WER of this tool splits an intra-word hyphen. `eval/langscore.py` keeps it,
thus "i-send" stays one Filipino word there. The two scorers therefore report
different numbers for the same transcript. [BENCHMARKS.md](BENCHMARKS.md) says
which scorer produced each number.

### The JSON report

`--json FILE` writes the `RunReport` structure, which
`eval/compare_language.py` reads. It holds the audio path, the mode, the model,
the language that you asked for, the language that the model detected, the
language of each window, the duration, the decode time, the RTF, the word
count, the transcript, each token, the WER, the live statistics and the live
configuration.

## Automatic notes

`--notes EXPORT.json` reads a recording that the app exported as JSON, drafts
the notes with the same pipeline and the same model as the app, prints the
draft as Markdown, and scores it. It needs macOS 26 with Apple Intelligence on.
The model refuses a transcript that is mostly Tagalog; finding 13 in
[FINDINGS.md](FINDINGS.md) gives the limit.

```bash
./.build/release/transcribe --notes meeting.json --json out/notes.json
```

The tool reports:

- The share of Tagalog words in the transcript and in the notes.
- **Grounding:** the share of the content words of each note that occur in the
  transcript within two minutes of the note's timestamp, and how many notes are
  under 0.4. A low value means that the model invented. English notes about
  Tagalog speech score lower by construction.
- **Coverage:** how many of the hand-written notes in the export the draft also
  has, and how many draft notes match a hand-written one, by content-word
  overlap. A meeting with notes that you wrote by hand is therefore a scored
  pair with no extra work.
- The parts that the model skipped, and why.

`--json FILE` writes the `NotesRunReport` structure with these scores and the
draft. `eval/notes_eval.py` writes the same scores for a candidate model, thus the
two can be compared.

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

## Debugging

| Variable | Function |
| --- | --- |
| `TRANSCRIBE_DEBUG_SPANS` | Set it to any value to write each speech region and each speaker span to stderr. |

The tool checks that `--audio` exists before it starts. AVFoundation reports a
missing file as "The operation could not be completed", which sends people to
look for a codec problem that they do not have.

Exit codes: `0` for success, `1` for a failure during the run, and `2` for a
usage error.
