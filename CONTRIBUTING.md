# How to contribute

Thank you for your interest. This is a small, local-first project with one
maintainer. A change must continue to work on a different Mac that has no
microphone, no model weights and no network.

This file gives the rules. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) gives the
build, the tests, the CI job and the scripts.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) gives the design.

## Requirements

For the native app, which most contributions touch:

- **macOS 15 or later.** `Package.swift` declares `.macOS(.v15)`.
- **Xcode 26 or later.** `Package.swift` sets `swift-tools-version: 6.2`, which
  Xcode 26 supplies. The maintainer develops against Swift 6.3.3.
- **A Mac with Apple silicon.** The models run on the Neural Engine.
- **Approximately 1.9 GB of free disk space** for the model weights. The app
  downloads them at the first start to
  `~/Library/Application Support/Transcriber/Models`.

For the legacy Python server in `server/`:

- **Python 3.11 or later.** The maintainer develops on 3.14.

## How to set up

```bash
git clone <your fork> && cd notero

# The app
cd app && swift build && swift test

# The Python server, if you change it
cd .. && python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt -r requirements-dev.txt
./.venv/bin/python -m pytest
```

Neither test suite needs model weights, a microphone or a network. This is
deliberate, and you must keep this property. Refer to "The four layers".

## Before you open a pull request

Run each command that applies to your change:

```bash
cd app && swift build && swift test    # 272 tests, and 0 warnings
./.venv/bin/python -m pytest           # 75 tests
```

The 272 tests are 244 XCTest tests and 28 swift-testing tests. Keep
`swift build` at **zero warnings**. There is no linter and no formatter for
either language. Write code in the style of the code around it.
`.editorconfig` gives the indentation.

CI (`.github/workflows/app.yml`) builds the app, runs `swift test`, and
assembles the release bundle. It does this on each push and each pull request
that touches `app/`. CI needs no secrets, thus it also runs on a fork.

## The four layers

`app/Sources/` has four layers. Each layer must build and be testable without
the layer above it:

| Layer | Can depend on | Must not touch |
| --- | --- | --- |
| `TranscriberCore` | nothing | AVFoundation, CoreML, SwiftUI, SwiftData, models |
| `TranscriberStore` | Core | inference of any kind |
| `TranscriberEngine` | Core | SwiftUI |
| `Transcriber` | Core, Store, Engine | — |

This split lets you test the commit policy, the segment merger, the exporters
and the search index on a Mac that has no microphone and no model weights.
**Do not put inference into Core, and do not put a view into Engine. Either
change breaks CI for everyone.**

Put new logic in `TranscriberCore` with a test. Do not put it in a view. Three
protocols in `TranscriberEngine/Protocols.swift` hide the ASR, VAD and speaker
backends: `SpeechRecognizing`, `VoiceActivityDetecting` and `SpeakerDiarizing`.
Write a new conformance instead of a call to a concrete engine.

## Changes that are usually refused

- **A change of model id by name match.** Read
  [docs/MODELS.md](docs/MODELS.md) and finding 1 in `docs/FINDINGS.md` first.
  The `_turbo` suffix of WhisperKit marks a compute variant and not the
  large-v3-turbo model of OpenAI. This mistake silently changes the model that
  gave the accuracy numbers.
- **Translation or correction of transcript text.** The app forces the language
  that the user selected, and it writes code-switched English as the speaker
  said it. Tagalog is the default. This is a product decision and not an
  oversight.
- **A read of a complete audio file into memory.** The app maps the 16 kHz
  working copy and reads it in slices, because two hours in a `[Float]` array
  holds 460 MB. Use `PCMSource`.
- **A new dependency.** There are two Swift dependencies, and the Python server
  pins its own. A new one needs a better reason than convenience.
- **Any cloud function.** No telemetry, no analytics, no crash reports, no
  remote inference. Audio that stays on the machine is the primary rule of this
  project.

## Tests

- `TranscriberCoreTests` and `TranscriberStoreTests` test pure logic. They need
  no fakes.
- `TranscriberEngineTests` drives the real pipeline through fakes for the three
  engine protocols. If model weights are unavailable, add a fake. Do not skip a
  test.

Record a finding that is worth memory in `docs/FINDINGS.md`, together with the
measurement that produced it. Several entries in that file exist because a
change that looked correct silently lost transcript data.

## The language of the documentation

Write the documentation for readers in ASD-STE100 Simplified Technical
English. Many readers of this project use English as a second language, and
Simplified Technical English keeps the instructions unambiguous for them. These
files use it:

- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`
- `docs/ARCHITECTURE.md`, `docs/DEVELOPMENT.md`, `docs/BENCHMARKS.md`,
  `docs/MODELS.md`, `docs/CLI.md`, `docs/RELEASE.md`,
  `docs/LEGACY-SERVER.md`, `docs/DEPLOY.md`
- The comments in `.env.example`

The most important rules are:

1. Use one word for one meaning. Use the same term for the same thing in every
   file.
2. Write in the active voice.
3. Keep a descriptive sentence to 25 words or fewer. Keep an instruction to
   20 words or fewer.
4. Give one instruction in one sentence.
5. Do not use the -ing form of a verb, unless it is part of a technical name.
6. Do not use idioms, metaphors or humour.
7. Start a warning with the command, then give the condition.
8. Do not remove articles or other words to make a sentence shorter.

These four files in `docs/` are design history: `PLAN.md`, `FINDINGS.md`,
`ENVIRONMENT.md` and `APP-UPDATE-PLAN.md`. They keep the words that they had on
the date at the top. Do not rewrite them, in Simplified Technical English or in
any other form. Add a new dated entry instead.

## Commit messages and history

Write the commit message in the imperative and say what changed. A reader must
be able to compare the message to the diff.

## How to report a bug

Give your macOS version, the chip in your Mac, the app version from
`app/VERSION`, and a description of the recording. Give the length of the
recording, the approximate number of speakers, and the distance to the
microphone. The primary case for this project is Tagalog that several people
speak across a room. It is also the hardest case to reproduce without your
data.

**Do not attach a real meeting recording or a real transcript to a public
issue.** Use the output of `eval/make-synthetic.sh`, or a clip that you own.

## Security

Report a vulnerability privately. Refer to [SECURITY.md](SECURITY.md).
