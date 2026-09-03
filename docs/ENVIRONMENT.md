# Environment findings — 2026-08-29

> **Design history.** A dated snapshot of the machine this project was
> developed and measured on, kept because the RTF and WER numbers in
> [FINDINGS.md](FINDINGS.md) are relative to it. It is *not* a requirements
> list — see the Requirements section of the [README](../README.md) for what
> you actually need.

Measured on the machine rather than assumed. Two of the plan's premises change
as a result.

## Host

| | Plan assumes | Actually is |
|---|---|---|
| Machine | Mac mini M2 Pro | **MacBook Pro, Apple M5 Pro** |
| Cores | — | 15 (5 efficiency + 10 performance) |
| RAM | — | 24 GB |
| macOS | — | 26.6.2 |

Every latency/RTF number in the plan (sections 3, 7, 10 Phase 1) was reasoned
about for an M2 Pro. The M5 Pro is materially faster, so every measurement
recorded here and in FINDINGS.md is an upper bound on what an M2 Pro would do.

## Toolchain (all present unless noted)

- Xcode 26.6 (17F113), macOS SDK 26.5 — verified a macOS binary compiles and runs
- Swift 6.3.3 — WhisperKit needs `swift-tools-version: 5.10`, `.macOS(.v13)`. Compatible.
- Python 3.14.6 (Homebrew) — `torch` 2.13.0 ships `cp314` macosx arm64 wheels, so
  Silero VAD in Phase 2 is unblocked. No pin to an older Python needed.
- Node 26.5.0, npm 11.17.0, pnpm 10.30.3
- git 2.55.0, Homebrew 6.0.20

**Not installed at the time:** `ffmpeg`, `cmake`, `uv`, `whisperkit-cli`. None
of them turned out to be required — `eval/make-synthetic.sh` builds the fixture
with the `say` and `afconvert` that ship with macOS.

## The model-ID trap

WhisperKit's `_turbo` suffix does **not** mean OpenAI's large-v3-turbo model. It marks
a compute-optimized variant (adds a `TextDecoderContextPrefill` stage). OpenAI's actual
large-v3-turbo is published under the date-stamped name `large-v3-v20240930`.

Measured from the HF repo `argmaxinc/whisperkit-coreml`:

| WhisperKit model ID | TextDecoder weights | Total | What it actually is |
|---|---:|---:|---|
| `openai_whisper-large-v3` | 1813 MB | 3090 MB | large-v3, 32-layer decoder |
| `openai_whisper-large-v3_turbo` | 1813 MB | 3195 MB | still large-v3 — *not* turbo |
| `openai_whisper-large-v3-v20240930` | 344 MB | 1620 MB | large-v3-turbo, 4-layer decoder |
| **`openai_whisper-large-v3-v20240930_turbo`** | **344 MB** | **1638 MB** | **large-v3-turbo + prefill — use this** |

The decoder is 5.3x smaller in the correct model. Since the design re-runs a 15s window
every 1s hop (section 5), decoder cost dominates the loop — picking
`openai_whisper-large-v3_turbo` by name-matching would be both far slower and a
*different model* from the one the offline Tagalog WER was measured on, quietly
invalidating the Phase 2 exit criterion that compares against it.

**Locked:** `openai_whisper-large-v3-v20240930_turbo`.

## Incidental

The WhisperKit package (now `argmax-oss-swift`) ships `SpeakerKit` alongside
`WhisperKit` and `TTSKit`. Section 9 reaches for FluidAudio's diarizer; SpeakerKit may
cover the same ground without a second Swift dependency. Worth evaluating at Phase 6 —
not now, and it does not change the post-session decision.
