# Notero

Notero is a native macOS app. It records meetings in Tagalog and Taglish,
writes the transcript, and keeps your notes with it. The app does all the work
on your Mac. It has no account and no API key, and no audio goes off the
machine.

**Status.** Version 1.0 shipped on 2026-09-02. Version 1.1 is complete but not
released. [CHANGELOG.md](CHANGELOG.md) lists what each version contains. These
functions are complete and tested:

- Recordings from the microphone, and imported media files
- Live transcription and whole-file transcription
- Speaker identification, with manual merge and reassignment
- Transcript edits, with revisions
- Synchronized transcript and audio playback
- Full-text search of the library
- The manual meeting workspace
- Export to TXT, Markdown, SRT, VTT and JSON
- The model benchmark

The maintainer builds and measures the app on an M-series Mac. The memory
target is a 16 GB M2 Pro. On the Taglish test clip, whole-file transcription
gives a real-time factor (RTF) of 0.09 to 0.14. That is 7 to 11 times faster
than real time. The peak memory is approximately 300 MB. The word error rate
(WER) is 20.3% to 25.8%. The offline WER that this repository recorded for the
same clip is 27.3%.

Eleven findings changed the plan. In one of them, a single refused decode
window deleted 44% of a transcript and reported no error. In another, the
speaker model merged two different voices that shared a 10-second chunk. Read
[docs/FINDINGS.md](docs/FINDINGS.md) before you trust a number on this page.

## The app

```
app/            Swift 6 and SwiftUI. The product.
├── Sources/TranscriberCore/     pure logic: commit policy, merger, exports, search
├── Sources/TranscriberStore/    SwiftData schema and queries
├── Sources/TranscriberEngine/   audio, WhisperKit, FluidAudio VAD and speaker models
├── Sources/Transcriber/         the SwiftUI app
└── Sources/TranscriberCLI/      the same pipeline, with no window
```

There are four layers. You can build and test each layer without the layer
above it. This split lets you test the commit policy, the segment merger and
the exporters on a Mac that has no microphone and no model weights.

The app is Notero, but the Swift modules and the data directory keep the name
Transcriber, which the app had up to version 1.1. The data directory holds the
recordings that version 1.0 wrote, thus a rename there hides them. The module
names are internal and a rename gives the user nothing.

Three protocols hide the engines: `SpeechRecognizing`, `VoiceActivityDetecting`
and `SpeakerDiarizing`. To replace a backend, write a new conformance to the
related protocol. You do not have to change the user interface.

### Requirements

- **macOS 15 or later** to run the app. `Package.swift` declares `.macOS(.v15)`.
- **Xcode 26 or later** to build the app. `Package.swift` sets
  `swift-tools-version: 6.2`, which Xcode 26 supplies. To see your version,
  run `swift --version`.
- **A Mac with Apple silicon.** The models run on the Neural Engine.
- **Approximately 1.9 GB of free disk space** for the model weights.
- **A network connection** for the first build and the first start. SwiftPM
  gets WhisperKit and FluidAudio, and `app/Package.resolved` pins both.

### Build and run

```bash
cd app && ./build-app.sh && open Notero.app
```

The app bundle is necessary. macOS gives microphone access only to a signed app
that declares `NSMicrophoneUsageDescription`. If it does not, macOS refuses
access, and the refusal sounds like silence instead of an error. The signature
is ad-hoc, thus the app runs only on the Mac that built it.

At the first start, the app downloads the model weights to
`~/Library/Application Support/Transcriber/Models`. The default speech model is
approximately 1.6 GB. Voice activity detection and speaker identification add
approximately 250 MB.

```bash
cd app && swift test
```

There are 248 tests: 226 XCTest tests and 22 swift-testing tests. They need no
model weights, no microphone and no network.

`build-app.sh` writes the version from `app/VERSION` and the commit count into
the bundle. [`.github/workflows/app.yml`](.github/workflows/app.yml) runs the
same build and the same tests on each push.

`app/scripts/snap.sh` makes a screenshot of the app, and clicks first if you
ask it to. Use it to compare a change to the real app. The script refuses to
click unless Notero is the frontmost app.

### The command-line tool

`transcribe` runs the same pipeline with no window. Use it for evaluation and
for continuous integration.

```bash
cd app && swift build -c release --product transcribe
./.build/release/transcribe --audio meeting.m4a --reference truth.txt --format srt
```

| Option | Function |
| --- | --- |
| `--audio FILE` | The audio or video file to transcribe. Required. |
| `--reference FILE` | A reference transcript. The tool then reports the WER. |
| `--models DIR` | Read the model weights from this directory. |
| `--model ID` | Use this WhisperKit model. |
| `--tier fast\|balanced\|accurate` | Use the model for this tier. |
| `--language CODE` | Force this language. The default is `tl`. |
| `--fast-diarize` | Do one speaker pass only. |
| `--no-diarize` | Do no speaker identification. |
| `--room-mode` | Apply the high-pass filter for far-field room audio. |
| `--format txt\|markdown\|srt\|vtt\|json` | The export format. |
| `--out FILE` | Write the export to this file. |
| `--json FILE` | Write a machine-readable report to this file. |
| `--live` | Replay the file through the live path. |
| `--realtime` | With `--live`, feed the audio at wall-clock speed. |
| `--hop MS` | With `--live`, set the hop. |
| `--pre-roll MS` | With `--live`, set the pre-roll. |
| `--context MS` | With `--live`, set the context length. |
| `--adaptive-hop` | With `--live`, shorten the hop while decodes are fast. |

The tool reports the number of decoded words, the RTF, the number of retried
and dropped windows, and the peak memory. If you give `--reference`, it also
reports the WER.

## What it does

**Record or import.** The app records from the microphone and writes two files
from one audio tap. The first file is a 64 kbps AAC archive at the hardware
sample rate. The second file is a 16 kHz mono working copy for the models. Both
files come from the same tap, thus their samples stay aligned. You can also
drop an MP3, WAV, M4A, MP4 or MOV file on the window. The app copies the file
into the library and adds it to the queue.

**Transcribe.** Live transcription decodes a 15-second context every 1.5
seconds and applies LocalAgreement-2. Committed text never changes later. Each
decode also reads 1.5 seconds of committed audio in front of the active region,
thus the model does not start cold at a commit boundary. When the voice
detector hears 700 ms of silence, the app decodes the audio up to that pause
and closes the utterance.

Whole-file transcription finds the speech with Silero VAD. It packs the speech
into windows that are shorter than the 30-second limit of Whisper and that end
in silence, and it decodes each window one time. If the model refuses a window,
the app decodes the window again, then makes it wider, and finally splits it.
The app scans and decodes the file in 5-minute batches, thus the transcript
starts to appear early on a long recording.

**Identify the speakers.** Speaker identification runs after transcription. The
app numbers the speakers by first appearance, thus the person who opened the
meeting is Speaker 1. A rename changes one row, because a segment holds the
label from the speaker model and never the name that you gave the speaker. A rename therefore stays
correct after you transcribe the recording again. You can merge two speakers,
and you can move one turn to a different speaker.

There are three modes. **Accurate** is the default and examines each turn a
second time. **Fast** does one pass only and is much quicker on a long
recording, but it can merge similar voices. **Off** skips the stage.

**Take notes.** A meeting has a summary and five lists: key points, decisions,
action items, questions and follow-ups. Each item keeps the timestamp and the
segment that it came from. You can therefore compare a decision to the words
that the speaker said. Press ⌘B to bookmark the moment during a recording or
during playback.

**Edit the transcript.** Double-click a turn to edit it line by line. The app
keeps the raw model output below your edit, and the search index and the
exports read the edited text. You can restore a line, delete it, or move it to
a different speaker. Press ⌘Z to undo all edits to one turn in one step. A menu
in the info bar shows the earlier revisions.

**Find it again.** Search reads the transcripts, the notes, the action items
and the bookmark labels, and it ignores case and diacritics. When you open a
result, the app opens the recording and moves to that moment.

**Export.** TXT gives the speaker labels and the notes. Markdown gives minutes:
attendees, summary, action items with checkboxes, then the transcript. SRT and
VTT give cues in order that do not overlap. JSON contains the complete meeting.
You can also export selected speakers only, or one time range only.

### Keyboard

| Keys | Function |
| --- | --- |
| ⌘R, ⇧⌘M, ⌘N | New recording, meeting or note |
| ⌘. | Stop the recording |
| ⌘O, ⌘E | Import, export |
| ⌘F | Find in this transcript |
| ⇧⌘F | Search all recordings |
| ⌘B | Bookmark this moment |
| ⌃⌘K, D, A, Q, U | Add the selection as a key point, decision, action, question or follow-up |
| Space | Play or pause. ⌥Space does this from any view. |
| ⌥←, ⌥→ | Go back or forward 5 seconds |
| ⌘[, ⌘] | Previous turn, next turn |
| ⌥↑, ⌥↓ | Faster playback, slower playback |
| ⌥⌘T | Show the time of day |
| ⇧⌘K | Model benchmark |

## Memory on a 16 GB Mac

The models set the memory budget. large-v3-turbo holds approximately 1.6 GB,
and the two speaker models hold approximately 200 MB more. The app therefore
keeps one instance of each model and shares it between the live path and the
background queue. It releases the speaker models as soon as no job needs them.
The queue also refuses to start work while a recording runs. A background
decode competes for the Neural Engine and makes a live hop 3 seconds long
instead of 0.9 seconds.

The app never reads a complete audio file into memory. It maps the 16 kHz
working copy and reads it in slices. Two hours of audio in a `[Float]` array
holds 460 MB. On a Mac that already holds the model, that difference makes
the Mac swap memory to disk. The app deletes the working copy after transcription and speaker
identification are complete. If you run either stage again, the app builds the
working copy again from the archive.

## Models

The app shows three tiers instead of model names. **Fast** is the quantized
turbo model. **Balanced** is large-v3-turbo. It is the default, and it keeps
live transcription at real-time speed. **Accurate** is the full large-v3 model.
It costs approximately 5 times more to decode, thus use it to transcribe a
recording again and not for the live path. Press ⇧⌘K to measure all three tiers
on your own audio. The benchmark recommends the slowest tier that stays at
real-time speed.

The `_turbo` suffix of WhisperKit marks a compute variant. It is not the
large-v3-turbo model of OpenAI. OpenAI publishes that model under its September
2024 date stamp. Finding 1 in FINDINGS.md explains the difference. Read it
before you change a model id.

## Tagalog and Taglish

The default language is `tl`, and the app forces it. The app does not translate
the transcript and does not rewrite it. It writes code-switched English inside
Tagalog as the speaker said it. Automatic detection is available, but the app
marks it as a risk. On a Taglish test clip, the decoder reported Indonesian and
started to translate. The decoder listens to the voice. It does not read the
script.

## Updates

The app can update itself. **Notero ▸ Check for Updates…** asks GitHub
which releases exist. Settings ▸ Updates has a switch for a check once a day at
launch. **The switch is off until you turn it on.** Everything else in this app
happens on your Mac, thus the one request that leaves it is your decision. The
request carries no identifier and nothing about this Mac. No recording, no
transcript and no note goes anywhere.

Each release is signed with an Ed25519 key. The app holds the public half. It
checks the signature of a download, and then that the download is Notero
at the version that the release gives, before it replaces anything. It installs
nothing that fails one of those checks. The app then quits, a small script moves
the new bundle into position, and the app opens again.

The bundle has an ad-hoc signature and not a Developer ID. Thus macOS can ask
for microphone access again after an update.

[docs/RELEASE.md](docs/RELEASE.md) tells you how to publish a release that the
app accepts. **The list of releases must be readable without a token**, because
the app sends none. A private repository is not readable, and the app says so.

## Configuration

**The app has no configuration.** It has no configuration file, no environment
variables, no accounts and no keys. All adjustable items are in Settings (⌘,),
and macOS keeps them in user defaults. The app writes the recordings and the
SwiftData store to `~/Library/Application Support/Transcriber/`.

The command-line tool reads one environment variable:

| Variable | Function |
| --- | --- |
| `TRANSCRIBE_DEBUG_SPANS` | Set it to any value to write each speech region and each speaker span to stderr. |

The Python server reads two environment variables. Both defaults work, and
[`.env.example`](.env.example) records them and is safe to copy:

| Variable | Function |
| --- | --- |
| `ASR_MODEL` | The WhisperKit model to load. The default is `openai_whisper-large-v3-v20240930_turbo`. `server/models.py` holds the catalogue. Read finding 1 in [docs/FINDINGS.md](docs/FINDINGS.md) before you change this value. |
| `ASR_MAX_SESSIONS` | The number of concurrent live sessions. The default is 3. The server refuses a session above the limit with the error `at_capacity`. |

```bash
cp .env.example .env
./.venv/bin/uvicorn server.main:app --env-file .env --host 127.0.0.1 --port 8000
```

## Prior work: the Python server

The first build was a FastAPI orchestrator, a resident Swift WhisperKit
sidecar, and a browser capture page. That code is still here and still works.
The native app replaces it.

```
server/     FastAPI orchestrator. adapters/ holds the ASR backends.
sidecar/    Swift. A persistent WhisperKit process (asrd).
client/     The browser capture page
eval/       The evaluation set and the scorer
bench/      Latency and RTF measurement
```

```bash
cd sidecar && swift build -c release
cd .. && python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
```

Then open <http://127.0.0.1:8000> for the capture page. The server listens on
the loopback interface because it has **no authentication of any kind**. A
person who can reach the port can open sessions, read the stored transcripts
and delete the archived audio.

**Do not change the bind address to reach the server from another device.**
Use an SSH tunnel, or put TLS and a password in front of the server.
[docs/DEPLOY.md](docs/DEPLOY.md) gives a procedure for each case. The
microphone does not work over plain HTTP.

To run the tests of the server:

```bash
./.venv/bin/pip install -r requirements-dev.txt
./.venv/bin/python -m pytest -q
```

There are 75 tests.

`eval/` compares transcripts to the references in `eval/refs/`, and `bench/`
measures latency and RTF. Both read audio from `eval/audio/`, which is not in
git. Run `eval/make-synthetic.sh` first to make the synthetic Taglish test clip
that the default paths point to. The script does not need ffmpeg. It uses the
`say` and `afconvert` commands that macOS supplies.

[docs/PLAN.md](docs/PLAN.md) is the build plan, and
[docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) records the Mac that gave the
numbers. Both files are design history and not current documentation.

## Not in version 1

The app does not contain a local LLM, automatic summaries, automatic extraction
of action items and decisions, topic detection, semantic search, speaker voice
profiles, or any cloud function.

The data model already has the shape that each of these functions needs. Note
rows have types and source timestamps, transcripts have revisions, and the
speaker roster is separate from the segments. None of these functions needs a
rebuild of the app.

## Third-party software

The app has two direct Swift package dependencies and one transitive
dependency. `app/Package.resolved` pins all three, and the assembled
`Notero.app` contains all three.

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT, Argmax Inc.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Apache-2.0,
  FluidInference. It supplies Silero VAD, pyannote segmentation and WeSpeaker
  embedding as CoreML models.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) —
  Apache-2.0, Apple. A transitive dependency.

This repository does **not** contain the model weights. The app downloads them
at the first start from Hugging Face. The sources are
`argmaxinc/whisperkit-coreml` and the CoreML conversions of Silero VAD and
pyannote by FluidAudio. Each model has its own upstream licence, and some
licences control access with an agreement. Read each model card on Hugging Face
before you distribute a bundle that contains these weights.

## How to contribute

[CONTRIBUTING.md](CONTRIBUTING.md) gives the layer rules, the checks to run
before a pull request, and the changes that are usually refused. Report a
security problem privately through [SECURITY.md](SECURITY.md) and not in a
public issue.

**Do not attach a real meeting recording or a real transcript to an issue.**

## Licence

Notero is MIT licensed. [LICENSE](LICENSE) gives the terms.

The licence covers the code in this repository. It does not cover the model
weights, which the app downloads at the first start and which each carry the
licence of their own publisher. Read the Third-party software section above.
