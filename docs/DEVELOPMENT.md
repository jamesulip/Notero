# Development

How to build, test and work on this repository. For the design, read
[ARCHITECTURE.md](ARCHITECTURE.md). For the rules that a pull request must
follow, read [CONTRIBUTING.md](../CONTRIBUTING.md).

## Requirements

For the native app, which most work touches:

- **macOS 15 or later.** `app/Package.swift` declares `.macOS(.v15)`.
- **Xcode 26 or later.** `app/Package.swift` sets `swift-tools-version: 6.2`,
  which Xcode 26 supplies. To see your version, run `swift --version`. The
  maintainer develops against Swift 6.3.3.
- **A Mac with Apple silicon.** The models run on the Neural Engine.
- **Approximately 1.9 GB of free disk space** for the model weights. The app
  downloads them at the first start to
  `~/Library/Application Support/Transcriber/Models`.
- **A network connection** for the first build and the first start. SwiftPM
  gets WhisperKit and FluidAudio, and `app/Package.resolved` pins both.

For the legacy Python server in `server/`, read
[LEGACY-SERVER.md](LEGACY-SERVER.md).

## Build the app

```bash
cd app && ./build-app.sh && open Notero.app
```

**The app bundle is necessary.** macOS gives microphone access only to a signed
app bundle that declares `NSMicrophoneUsageDescription`. If the bundle does not
declare it, macOS refuses access, and the refusal sounds like silence instead
of an error. SwiftData also derives its paths from the bundle identifier, thus
it needs a real one.

`build-app.sh` does this:

1. It runs `swift build -c release`. To build the debug configuration, run
   `./build-app.sh debug`.
2. It writes `Notero.app` with the marketing version from `app/VERSION` and the
   build number from the commit count. Two bundles from different commits
   therefore never share a build number. To override either number, run
   `VERSION=1.2.0 BUILD=57 ./build-app.sh`.
3. It writes the `Info.plist`, which declares the bundle identifier
   `local.notero`, the microphone use description and the document types for
   audio and video.
4. It signs the bundle with the audio-input entitlement. It uses an Apple
   Development identity if the Mac has one, and an ad-hoc signature if not.

**Neither signature is a Developer ID.** The app therefore runs only on the Mac
that built it. [RELEASE.md](RELEASE.md) gives the limits that this puts on a
release.

At the first start, the app downloads the model weights. The default speech
model is approximately 1.6 GB. Voice activity detection and speaker
identification add approximately 250 MB. [MODELS.md](MODELS.md) gives the
catalogue and the storage layout.

## Test the app

```bash
cd app && swift test
```

There are 272 tests: 244 XCTest tests and 28 swift-testing tests. **They need
no model weights, no microphone and no network.** This property is deliberate,
and you must keep it. The four-layer split in
[ARCHITECTURE.md](ARCHITECTURE.md) is what makes it possible.

| Test target | What it covers |
| --- | --- |
| `TranscriberCoreTests` | Pure logic. No fakes are necessary. |
| `TranscriberStoreTests` | The SwiftData schema and the queries. |
| `TranscriberEngineTests` | The real pipeline, driven through fakes for the three engine protocols. |

If model weights are unavailable for a test, add a fake. Do not skip the test.

Keep `swift build` at **zero warnings**. There is no linter and no formatter
for either language. Write code in the style of the code around it.
`.editorconfig` gives the indentation.

## Build the command-line tool

```bash
cd app && swift build -c release --product transcribe
```

The binary is at `app/.build/release/transcribe`. [CLI.md](CLI.md) gives the
options, the output formats and the debugging switches. Use it to measure a
change against real audio, because the app itself cannot be scripted.

## Continuous integration

[`.github/workflows/app.yml`](../.github/workflows/app.yml) runs on each push
and each pull request that touches `app/`. The job:

1. Checks out the repository with `fetch-depth: 0`, because `build-app.sh`
   derives the build number from the commit count.
2. Selects the latest stable Xcode.
3. Restores the SwiftPM cache, which is keyed on `app/Package.resolved`.
4. Runs `swift build`, then `swift test`.
5. Checks the result. It fails the job on a failure from either test runner,
   and it also fails if either runner reported no tests at all. A crash that
   produces no summary must not pass as "nothing failed".
6. Runs `./build-app.sh release` and uploads `Notero.app` as an artifact.

**CI needs no secrets, thus it also runs on a fork.** The uploaded bundle is an
assembly smoke test only. The signature is ad hoc, and the zip drops the
executable bit, thus the artifact does not start on another Mac.

## Scripts

### `app/scripts/record-probe.sh` — check what the app can record

```bash
scripts/record-probe.sh --devices                     # list the input devices
scripts/record-probe.sh --record --source both --seconds 20 --out /tmp/x.m4a
scripts/record-probe.sh --channels --seconds 15       # raw channels of the tap
```

The script puts the `transcribe` tool in a signed app bundle and starts it
through LaunchServices. The bundle is necessary. macOS gives no system audio
permission to a command line tool, because the prompt needs a bundle identifier
to attach the answer to and a foreground application to appear in front of. A
tool that you start in a terminal has neither, and macOS refuses the request
without a prompt and without an error. The capture then starts, reports
success and delivers no samples.

Output goes to `/tmp/notero-record-probe.log`, because LaunchServices discards
stderr. To ask for the permission again, use
`tccutil reset AudioCapture local.notero`.

### `app/scripts/snap.sh` — screenshot the running app

```bash
scripts/snap.sh out.png                  # capture the main window
scripts/snap.sh out.png 858 296          # click at 858,296 then capture
scripts/snap.sh out.png 1535 564 right   # right-click then capture
WINDOW=2 scripts/snap.sh out.png         # another window, such as Settings
```

The script writes `out.png` at full resolution and `out.small.png` scaled to
1000 px wide. It prints the window origin and the scale, thus you can map an
image coordinate back to a screen point with
`screen = origin + image_xy * scale`.

**The script refuses to click unless Notero is frontmost.** A click goes to
whatever window is in front. A right-click that was meant for the app once
opened the menu of a different app. If the app does not come to the front,
another person is using the Mac. Stop instead of a fight for the focus.

Use this script to compare a change to the real app.

### `app/scripts/release.sh` — build and publish a release

It builds the bundle, packages it with `ditto`, tags the commit, and publishes
the zip with the CHANGELOG section as the release notes.
[RELEASE.md](RELEASE.md) gives the procedure.

## Local development notes

- **`app/VERSION` holds the marketing version.** Use three numbers, for example
  `1.2.0`. The release script refuses a suffix such as `1.2.0-rc1`.
- **The modules keep the name Transcriber.** The app is Notero. The data
  directory `~/Library/Application Support/Transcriber/` holds the recordings
  of the private builds, thus a rename there hides them.
- **The models directory can be anywhere.** `transcribe --models DIR` reads the
  weights from `DIR`. Point it at a directory that already holds the weights,
  and no download happens.
- **`eval/` and `bench/` hold the evaluation tools** from the Python server.
  They still work against the command-line tool.
  [LEGACY-SERVER.md](LEGACY-SERVER.md) describes them, and
  [BENCHMARKS.md](BENCHMARKS.md) gives the measurements that they produced.
- **`eval/audio/` is not in git.** Run `eval/make-synthetic.sh` first to make
  the synthetic Taglish test clip that the default paths point to. The script
  needs no ffmpeg. It uses the `say` and `afconvert` commands that macOS
  supplies.

## The documentation language

Write the documentation in ASD-STE100 Simplified Technical English. Many
readers of this project use English as a second language.
[CONTRIBUTING.md](../CONTRIBUTING.md) lists the files that use it and gives the
most important rules.

**Four files in `docs/` are design history:** `PLAN.md`, `FINDINGS.md`,
`ENVIRONMENT.md` and `APP-UPDATE-PLAN.md`. They keep the words that they had on
the date at the top. Do not rewrite them. Add a new dated entry instead.
