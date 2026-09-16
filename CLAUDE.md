# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Notero: a native macOS app (Swift 6, SwiftUI, SwiftData) that records a meeting, transcribes it on-device with WhisperKit and FluidAudio, identifies speakers, and keeps notes with the transcript. Everything runs locally on Apple silicon; there is no server, account, telemetry or cloud path, and adding one is refused on principle.

The product is `app/`. The Swift modules and the data directory (`~/Library/Application Support/Transcriber/`) keep the old name "Transcriber" on purpose; do not rename them.

`server/`, `sidecar/`, `client/`, `bench/` and most of `eval/` are the **legacy Python/FastAPI build** that the app replaced. Nothing in the app depends on them. `eval/compare_language.py` and `eval/langscore.py` are still live: they drive the Swift CLI.

## Commands

All app work happens in `app/`.

```bash
cd app && swift build                 # must stay at zero warnings
cd app && swift test                  # 301 tests; no weights, mic or network needed
cd app && swift test --filter SegmentMergerTests            # one XCTest class
cd app && swift test --filter SegmentMergerTests/testName   # one XCTest method
cd app && swift test --filter HighPassFilterTests           # swift-testing suites filter the same way
cd app && ./build-app.sh && open Notero.app          # release bundle; ./build-app.sh debug for debug
cd app && swift build -c release --product transcribe   # headless CLI at .build/release/transcribe
```

`--filter` matches the test type name, which often differs from the file name (`MergerTests.swift` holds `SegmentMergerTests` and `GroupingTests`). Two files (`HighPassFilterTests`, `InputGainTests`) use swift-testing; the rest are XCTest. Both runners run under `swift test`.

The app bundle is not optional for anything that touches audio: macOS grants microphone and system-audio permission only to a signed bundle, and a refusal looks like silence, not an error. Use `app/scripts/record-probe.sh` to run the CLI's capture diagnostics inside a bundle.

A cached `swift build` hides warnings. Touch or clean before claiming zero.

Legacy server (only if you change `server/` or `tests/`):

```bash
python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
./.venv/bin/python -m pytest              # 75 tests; asyncio_mode = auto
./.venv/bin/python -m pytest tests/test_commit.py::test_name
```

Evaluation against real audio (the app itself cannot be scripted):

```bash
eval/make-synthetic.sh                    # builds eval/audio/synthetic-taglish.wav with `say`; no ffmpeg
./app/.build/release/transcribe --audio clip.wav --reference clip.txt --models models --json out/run.json
python3 eval/compare_language.py --bin app/.build/release/transcribe --models models --tier balanced
```

`--models models` points at weights already in the repo's ignored `models/` directory and avoids a 1.6 GB download. Do not run `swift build` while a `--live --realtime` run is in progress; it changes the drop count.

Release: bump `app/VERSION` (three numbers, no suffix), add a CHANGELOG section, commit, then `cd app && ./scripts/release.sh --dry-run` and `./scripts/release.sh --notes ~/notes.md`. See `docs/RELEASE.md`.

## Architecture: the four layers

`app/Package.swift` defines four layers plus a CLI. **Each layer must build and test without the layer above it.** This is what lets CI run with no model weights and no microphone, and it is the rule most likely to be broken by a careless change.

| Target | May depend on | Must never touch |
| --- | --- | --- |
| `TranscriberCore` | nothing | AVFoundation, CoreML, SwiftUI, SwiftData, models |
| `TranscriberStore` | Core | inference of any kind |
| `TranscriberEngine` | Core | SwiftUI |
| `Transcriber` (app) | Core, Store, Engine | — |
| `TranscriberCLI` (`transcribe`) | Core, Engine | — |

Store and Engine do not depend on each other; only the app sees all three. The app target compiles with `defaultIsolation(MainActor.self)`; the others do not.

- **Core** holds the algorithms: `LocalAgreement` (live commit policy), `SegmentMerger` (spans into speaker turns), `Exporter` (txt/markdown/srt/vtt/json), search index, `RingBuffer`, `HighPassFilter`, `WordErrorRate`, `Benchmark`, the `PCMSource` protocol, and `Catalogues.swift` (model catalogue, `ModelTier`, `DiarizationMode`, languages). New logic goes here, with a test, not in a view.
- **Store** is the SwiftData schema (`StoredRecording` → many `StoredTranscript` revisions → `StoredSegment`, plus `StoredSpeaker`, `StoredBookmark`, `StoredMeetingItem`, `StoredTag`). `TranscriptWriter` writes a new revision; `TranscriptReader` reads one transcript as value types on a `@ModelActor`. Create a fresh reader per read; a long-lived context returns stale rows.
- **Engine** owns audio and models. Three protocols in `Protocols.swift` hide the backends: `SpeechRecognizing` (WhisperKit), `VoiceActivityDetecting` (FluidAudio Silero VAD), `SpeakerDiarizing` (FluidAudio pyannote + WeSpeaker). Tests use fake conformances; write a new conformance rather than calling a concrete engine. `EngineHost` holds exactly one instance of each model. `OfflinePipeline` is the whole-file path, `LiveDecoder`/`LiveSession` the live path, `TranscriptionQueue` the background jobs, `AudioCapture` + `SystemAudioTap` the two-lane capture (channel 1 room mic, channel 2 system audio).
- **CLI** is not a second implementation. It calls the same `OfflinePipeline`, `LiveDecoder`, `SpeakerEngine` and `Exporter` as the app, which is why it is the verification path for real audio.

### Pipeline facts that shape the code

- **Whole-file path**: VAD in 5-minute windows → pack speech into ≤28 s windows ending in silence → decode each window once → drop words starting >250 ms past the window's audio (Whisper hallucinates into padding). An empty result set from WhisperKit is silent data loss, so a refused window is retried wider (700 ms, 1400 ms), then split in halves to two levels, and the count of undecodable windows is shown to the user (finding 9: one refused window once deleted 44% of a transcript with no error).
- **Live path**: hop every 1.5 s over a fixed-origin window; VAD (700 ms silence) triggers finalization; LocalAgreement-2 commits a token only when two consecutive passes agree, and committed text never changes. Consecutive windows must start at the same audio point; a freely sliding ring buffer breaks the policy permanently (finding 5). Live text is off by default and no model loads at start when it is off.
- **Speaker ID** runs after transcription, never during. Segments store the model label (`S1`, `S2`); the display name lives on `StoredSpeaker`. The default `accurate` mode re-embeds each turn because FluidAudio fuses voices sharing one 10 s chunk (finding 10).
- **Memory**: never read a whole audio file into `[Float]` (two hours = 460 MB). Read through `PCMSource`/`MappedPCM` slices. The queue refuses background work while a recording runs, because a competing decode drops live hops.
- **Revisions**: a transcript is an immutable revision; edits go to `StoredSegment.textClean` (nil until edited) and `displayText` is `textClean ?? text`. "Transcribe this turn again" (`Work.range`) replaces rows in place in the latest revision so note references survive.

## Rules this project enforces

- **Never change a model id by name match.** WhisperKit's `_turbo` suffix is a compute variant, not OpenAI's large-v3-turbo. The default `openai_whisper-large-v3-v20240930_turbo` is the turbo model; `openai_whisper-large-v3_turbo` is the full large-v3 with a 5.3× heavier decoder. See `docs/MODELS.md` and finding 1.
- **Tiers**: Fast / Balanced (default) / Best. Best was called Accurate; stored `accurate` values and `--tier accurate` must keep working. Only Balanced has measured accuracy numbers; do not describe Best as "more accurate" in docs or UI.
- **No translation or correction of transcript text.** The app forces the selected language (Tagalog default) and writes code-switched English as spoken.
- **No new dependencies** without a strong reason. There are two Swift packages (WhisperKit pinned exact 1.1.0, FluidAudio) and one transitive (swift-argument-parser).
- **Do not skip a test** because weights are unavailable; add a fake.
- **No linter or formatter.** Match surrounding style; `.editorconfig` gives 4-space indentation (2 for yml/json/html/js/css).
- **Record measured findings** in `docs/FINDINGS.md` as a new dated entry.
- Commit messages: imperative, describing what changed.
- Never commit audio, recordings, transcripts or model weights (`.gitignore` covers `data/`, `models/`, `eval/audio/`, media extensions). Never attach real meeting audio or transcripts to issues or screenshots; use `eval/make-synthetic.sh` or `app/scripts/make-demo-meetings.sh` output.

## Documentation language

User-facing docs (`README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/ARCHITECTURE.md`, `DEVELOPMENT.md`, `BENCHMARKS.md`, `BENCHMARK-VS-WHISPER-CPP.md`, `MODELS.md`, `CLI.md`, `RELEASE.md`, `LEGACY-SERVER.md`, `DEPLOY.md`, `.env.example` comments) and the app's UI strings are written in **ASD-STE100 Simplified Technical English**: one word per meaning, active voice, ≤25 words per descriptive sentence, ≤20 per instruction, one instruction per sentence, no -ing verb forms outside technical names, no idioms, keep articles.

Four files are **frozen design history** and must not be rewritten in any form: `docs/PLAN.md`, `docs/FINDINGS.md`, `docs/ENVIRONMENT.md`, `docs/APP-UPDATE-PLAN.md`. Append a new dated entry instead.

## CI

`.github/workflows/app.yml` runs `swift build`, `swift test` and `build-app.sh release` on macos-15 for changes under `app/`; it fails if either test runner reports a failure or reports no tests at all. `.github/workflows/server.yml` runs pytest for `server/` and `tests/`. Neither needs secrets.
