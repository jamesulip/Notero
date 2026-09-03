# Contributing

Thanks for looking. This is a small, single-maintainer, local-first project, and
the bar for a change is that it keeps working on someone else's Mac without a
microphone, without model weights and without a network.

## Requirements

For the native app — the part most contributions touch:

- **macOS 15 or newer.** `Package.swift` declares `.macOS(.v15)`.
- **Xcode 26 or newer.** `Package.swift` is `swift-tools-version: 6.2`, which
  ships with Xcode 26. Developed against Swift 6.3.
- **Apple silicon.** The models run on the Neural Engine.
- About **2 GB of free disk** for model weights, downloaded on first launch into
  `~/Library/Application Support/Transcriber/Models`.

For the legacy Python server under `server/`:

- **Python 3.11 or newer** (developed on 3.14).

## Getting set up

```bash
git clone <your fork> && cd live-transcriber-server

# The app
cd app && swift build && swift test

# The Python server, if you are touching it
cd .. && python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
./.venv/bin/python -m pytest
```

Neither test suite needs model weights, a microphone or a network. That is
deliberate, and it is the property to preserve — see "The four-layer split".

## Before you open a pull request

Run everything that applies:

```bash
cd app && swift build && swift test    # 183 tests, 0 warnings expected
./.venv/bin/python -m pytest           # 75 tests
```

A pull request should keep `swift build` at **zero warnings**. There is no
linter or formatter configured for either language; match the surrounding style
instead. `.editorconfig` covers indentation.

CI (`.github/workflows/app.yml`) builds the app, runs `swift test` and assembles
the release bundle on every push and pull request that touches `app/`. It needs
no secrets, so it runs on forks.

## The four-layer split

`app/Sources/` is four layers, and each one must build and be testable without
the layer above it:

| Layer | May depend on | Must not touch |
| --- | --- | --- |
| `TranscriberCore` | nothing | AVFoundation, CoreML, SwiftUI, SwiftData, models |
| `TranscriberStore` | Core | inference of any kind |
| `TranscriberEngine` | Core | SwiftUI |
| `Transcriber` | Core, Store, Engine | — |

This is what lets the commit policy, the segment merger, the exporters and the
search index be tested on a machine with no microphone and no 1.6 GB of weights.
**Putting inference into Core, or a view into Engine, breaks CI for everyone.**

New logic belongs in `TranscriberCore` with a test, not in a view. The ASR, VAD
and diarization backends sit behind `SpeechRecognizing`,
`VoiceActivityDetecting` and `SpeakerDiarizing` in
`TranscriberEngine/Protocols.swift` — add a conformance rather than reaching for
a concrete engine.

## What tends to get pull requests rejected

- **Changing a model id by name-matching.** Read `docs/FINDINGS.md` finding 1
  first. WhisperKit's `_turbo` suffix is a compute variant, not OpenAI's
  large-v3-turbo, and getting this wrong silently changes which model the
  accuracy numbers were measured on.
- **Translating or rewriting transcript text.** Tagalog is forced by default and
  code-switched English is written as spoken. That is a product decision, not an
  oversight.
- **Loading whole audio files into memory.** The 16 kHz working copy is
  memory-mapped and read in slices on purpose; two hours as a `[Float]` is
  460 MB resident. Go through `PCMSource`.
- **Adding a dependency.** There are two Swift dependencies and the Python
  server's are pinned. Adding one needs a reason beyond convenience.
- **Cloud anything.** No telemetry, no analytics, no crash reporting, no remote
  inference. Audio not leaving the machine is the whole premise.

## Tests

- `TranscriberCoreTests`, `TranscriberStoreTests` — pure logic, no fakes needed.
- `TranscriberEngineTests` — drives the real pipeline through fakes for the
  three engine protocols. Add a fake rather than skipping a test when weights
  are unavailable.

Findings worth remembering go in `docs/FINDINGS.md` with the measurement that
produced them. Several entries there exist because a plausible-looking change
quietly lost transcript data; that file is why.

## Commit messages and history

Describe what changed in the imperative, in a sentence a reader can check
against the diff. `docs/` records design history in
`PLAN.md`, `FINDINGS.md`, `ENVIRONMENT.md` and `APP-UPDATE-PLAN.md`; those are
kept as written at the time rather than retconned.

## Reporting bugs

Include your macOS version, your Mac's chip, the app version (in
`app/VERSION`), and what the recording was — length, roughly how many speakers,
near-mic or across a room. Far-field multi-speaker Tagalog is the case this
project is built for and the hardest one to reproduce blind.

**Never attach a real meeting recording or transcript to a public issue.**
Reproduce with `eval/make-synthetic.sh` output or a clip you own outright.

## Security

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).
