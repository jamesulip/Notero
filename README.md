# Transcriber

A native macOS app for recording, transcribing and taking notes on Tagalog and
Taglish meetings. Everything runs on the Mac: no account, no API key, and no
audio leaves the machine.

**Status: v1 feature-complete.** Recording, import, live transcription, speaker
identification, transcript/audio sync, searchable history, the manual meeting
workspace, TXT/Markdown/SRT/VTT/JSON export and the benchmark are all in and
tested.

Built and measured on an M-series Mac against a 16 GB M2 Pro budget. On the
Taglish fixture the whole-file path runs at **RTF 0.09–0.14** (7–11x faster than
real time) with a peak footprint of **~300 MB**, and scores **20.3–25.8% WER** —
at or below the 27.3% offline number this repo already recorded for that clip.

Ten findings so far change the plan — among them one where a single refused
decode window silently deleted 44% of a transcript, and one where the diarizer
fused two different voices that shared a 10 s chunk. Read
[docs/FINDINGS.md](docs/FINDINGS.md) before trusting any number here.

## The app

```
app/            Swift 6 + SwiftUI. The product.
├── Sources/TranscriberCore/     pure logic: commit policy, merger, exports, search
├── Sources/TranscriberStore/    SwiftData schema and queries
├── Sources/TranscriberEngine/   audio I/O, WhisperKit, FluidAudio VAD + diarization
├── Sources/Transcriber/         the SwiftUI app
└── Sources/TranscriberCLI/      the same pipeline, headless
```

Four layers, each buildable and testable without the one above it. That split is
what lets the commit policy, the segment merger and the exporters be tested on a
machine with no microphone and no 1.6 GB of weights.

The transcription engine sits behind three protocols — `SpeechRecognizing`,
`VoiceActivityDetecting`, `SpeakerDiarizing` — so a backend can be replaced with
a new conformance rather than a rewrite of the UI.

### Requirements

- **macOS 15 or later** to run (`Package.swift` declares `.macOS(.v15)`).
- **Xcode 26 or later** to build: `Package.swift` is
  `swift-tools-version: 6.2`, which ships with Xcode 26. Check with
  `swift --version`.
- **An Apple-silicon Mac.** The models run on the Neural Engine.
- **About 1.9 GB of free disk** for model weights, and a network connection
  for the first build (SwiftPM fetches WhisperKit and FluidAudio, both pinned
  in `app/Package.resolved`) and the first launch.

### Build and run

```bash
cd app && ./build-app.sh && open Transcriber.app
```

The bundle is not cosmetic: macOS only grants microphone access to a signed app
carrying `NSMicrophoneUsageDescription`, and the refusal looks like silence
rather than an error. The signature is ad-hoc, so it runs on the machine that
built it.

First launch downloads model weights into
`~/Library/Application Support/Transcriber/Models` — about 1.6 GB for the
default model, plus ~250 MB for voice activity and speaker identification.

```bash
cd app && swift test
```

`build-app.sh` stamps the bundle with the version in `app/VERSION` and the
commit count as the build number. The same build and test run on every push
in [`.github/workflows/app.yml`](.github/workflows/app.yml); no weights or
microphone are needed, which is what the four-layer split buys.

`app/scripts/snap.sh` screenshots the running app, clicking first if asked,
for checking a view change against the real thing. It refuses to click unless
Transcriber is the frontmost app.

### Headless

The same pipeline without a window, for eval and CI:

```bash
cd app && swift build -c release --product transcribe
./.build/release/transcribe --audio meeting.m4a --reference truth.txt --format srt
```

`--tier fast|balanced|accurate`, `--model <id>`, `--models DIR`, `--language`,
`--no-diarize`, `--room-mode`, `--format txt|markdown|srt|vtt|json`,
`--out FILE`. It reports words decoded, RTF, retried and dropped windows, WER
when given a reference, and peak memory.

`--room-mode` applies the same high-pass filter the app uses for far-field
room audio, and `--models DIR` points at an existing weights directory instead
of the app's.

## What it does

**Record or import.** Microphone capture writes two files from one tap: a 64 kbps
AAC archive at the hardware rate, and a 16 kHz mono working copy for inference.
Deriving both from one tap is what keeps them sample-aligned. Drop an MP3, WAV,
M4A, MP4 or MOV onto the window and it is copied into the library and queued.

**Transcribe.** Live transcription runs a 15 s context on a 1.5 s hop with
LocalAgreement-2: committed text never changes. Whole-file transcription finds
speech with Silero VAD, packs it into windows just under Whisper's 30 s limit
that end *in silence*, and decodes each once — retrying, widening and finally
splitting any window the model refuses.

**Identify speakers.** Diarization runs after transcription, and speakers are
renumbered by first appearance so the person who opened the meeting is Speaker 1.
Renaming one is a single row: segments hold the diarizer's label, never a display
name, so a rename survives re-transcription.

**Take notes.** A meeting has a summary plus five typed lists — key points,
decisions, action items, questions, follow-ups. Every item keeps the timestamp
and segment it came from, so a decision written down stays checkable against
what was actually said. ⌘B bookmarks the moment, recording or playing.

**Find it again.** Full-text search across transcripts, notes, action items and
bookmark labels, case- and diacritic-insensitive. A result opens the recording
and seeks to the moment.

**Export.** TXT (speaker-labelled, with the notes), Markdown minutes
(attendees, summary, checkable action items, then the transcript), SRT and VTT
(ordered, non-overlapping cues), and JSON that round-trips the entire meeting.

### Keyboard

| | |
| --- | --- |
| ⌘R / ⇧⌘M / ⌘N | New recording / meeting / note |
| ⌘. | Stop recording |
| ⌘O / ⌘E | Import / export |
| ⌘F | Find in this transcript |
| ⇧⌘F | Search all recordings |
| ⌘B | Bookmark this moment |
| ⌃⌘K/D/A/Q/U | Add selection as key point / decision / action / question / follow-up |
| Space | Play/pause (⌥Space anywhere) |
| ⌥← / ⌥→ | Skip 5 seconds |
| ⌘[ / ⌘] | Previous / next turn |
| ⌥↑ / ⌥↓ | Faster / slower playback |
| ⌥⌘T | Show times of day |
| ⇧⌘K | Model benchmark |

## Memory, on a 16 GB machine

The models are the budget: large-v3-turbo is ~1.6 GB resident and the diarizer
pair another ~200 MB. So there is one of each, shared between the live path and
the background queue; the diarizer is released the moment a job stops needing
it; and the queue refuses to start work while a recording is in progress,
because a background decode competing for the Neural Engine is what turns a live
hop from 0.9 s into 3 s.

Audio never gets loaded whole. The 16 kHz working copy is memory-mapped and read
in slices — two hours as a `[Float]` array is 460 MB resident, which on a machine
already holding the model is the difference between working and swapping. The
working copy is deleted once a recording is transcribed and diarized, and
rebuilt from the archive if either is ever re-run.

## Models

Three tiers rather than model names: **Fast** (quantized turbo), **Balanced**
(large-v3-turbo — the default, and what keeps live transcription real-time) and
**Accurate** (full large-v3, ~5x the decode cost, meant for re-transcribing
rather than the live path). ⇧⌘K measures all three on your own audio and
recommends the slowest one that still keeps up.

WhisperKit's `_turbo` suffix marks a *compute variant*, not OpenAI's
large-v3-turbo — that one is published under its September 2024 date stamp. The
distinction is finding 1 in FINDINGS.md and it is worth reading before changing
a model id.

## Tagalog and Taglish

Tagalog is forced by default and the transcript is never translated or rewritten
— code-switched English inside Tagalog is written as spoken. Auto-detect is
offered and flagged: on a Taglish fixture the decoder reported Indonesian and
started translating, because it hears the voice rather than reading the script.

## Configuration

**The app has none.** No configuration file, no environment, no accounts, no
keys. Everything adjustable lives in Settings (⌘,) and is stored in user
defaults. Recordings and the SwiftData store go to
`~/Library/Application Support/Transcriber/`.

The headless CLI reads one variable:

| | |
| --- | --- |
| `TRANSCRIBE_DEBUG_SPANS` | Set to anything to dump each detected speech region and speaker span to stderr. |

The Python server reads two, both with working defaults —
[`.env.example`](.env.example) documents them and is safe to copy:

| | |
| --- | --- |
| `ASR_MODEL` | WhisperKit model id to load. Default `openai_whisper-large-v3-v20240930_turbo`; the catalogue is in `server/models.py`. Read finding 1 in [docs/FINDINGS.md](docs/FINDINGS.md) before changing it. |
| `ASR_MAX_SESSIONS` | Concurrent live sessions, default 3. Sessions past the cap are refused with `at_capacity`. |

```bash
cp .env.example .env
./.venv/bin/uvicorn server.main:app --env-file .env --host 127.0.0.1 --port 8000
```

## Prior work: the Python server

The original build was a FastAPI orchestrator driving a resident Swift
WhisperKit sidecar, with a browser capture page. It is still here and still
works; the native app supersedes it.

```
server/     FastAPI orchestrator; adapters/ holds the ASR backends
sidecar/    Swift: persistent WhisperKit process (asrd)
client/     Browser capture page
eval/       Eval set + scorer
bench/      Latency / RTF measurement
```

```bash
cd sidecar && swift build -c release
cd .. && python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
```

Then open <http://127.0.0.1:8000> for the capture page. It binds to loopback
because it has **no authentication of any kind** — anyone who can reach the
port can open sessions, read stored transcripts and delete archived audio. To
reach it from a phone, put TLS and access control in front of it rather than
widening the bind: [docs/DEPLOY.md](docs/DEPLOY.md) does that with Tailscale,
and the microphone will not work over plain HTTP anyway.

Its tests:

```bash
./.venv/bin/pip install -r requirements-dev.txt
./.venv/bin/python -m pytest -q
```

`eval/` scores transcripts against references in `eval/refs/`, and `bench/`
measures latency and RTF. Both expect audio in `eval/audio/`, which is
gitignored — run `eval/make-synthetic.sh` first to generate the synthetic
Taglish fixture the default paths point at. It needs no ffmpeg, only the `say`
and `afconvert` that ship with macOS.

The build plan is [docs/PLAN.md](docs/PLAN.md) and the machine the numbers
were measured on is [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md); both are
design history rather than current documentation.

## Parked for v2

Local LLM, automatic summaries, automatic action-item and decision extraction,
topic detection, semantic search, speaker voice profiles, cloud anything. The
data model already has the shape each of them would write into — typed note rows
with source timestamps, transcript revisions, a speaker roster separate from the
segments — so none of them needs the app rebuilt.

## Third-party

The app declares two Swift package dependencies; all three below are pinned in
`app/Package.resolved` and redistributed inside the assembled
`Transcriber.app`:

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT, Argmax Inc.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Apache-2.0,
  FluidInference. Silero VAD and pyannote segmentation + WeSpeaker embedding,
  as CoreML.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) —
  Apache-2.0, Apple. Pulled in transitively.

Model weights are **not** in this repository. They are downloaded on first
launch from Hugging Face (`argmaxinc/whisperkit-coreml`, and FluidAudio's
CoreML conversions of Silero VAD and pyannote) and carry their own upstream
licences, some of which gate access behind an agreement. Check each one on its
Hugging Face model card before redistributing a bundle that contains them.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers the layer rules, what to run before a
pull request, and the changes that tend to get rejected. Security issues go
through [SECURITY.md](SECURITY.md), privately, rather than a public issue.

**Never attach a real meeting recording or transcript to an issue.**
