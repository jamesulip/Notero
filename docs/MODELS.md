# Models

Which models the app uses, what their names mean, and where the weights go.

**Model names in this area are confusing, and the obvious reading of one name
is wrong.** Read [The `_turbo` trap](#the-_turbo-trap) before you change a model
id anywhere in this repository.

## The three tiers

The app shows three tiers instead of model names. A tier is a promise about
speed and not a model name.

| Tier | Model | Behaviour |
| --- | --- | --- |
| **Fast** | `openai_whisper-large-v3-v20240930_626MB` | The quantized turbo model, with the smallest Neural Engine residency (878 MB). On the Mac mini M2 Pro it was **slower** than Balanced and slightly less accurate on read Tagalog. [TIER-RESULTS.md](../eval/TIER-RESULTS.md) gives the measurements. |
| **Balanced** | `openai_whisper-large-v3-v20240930_turbo` | **The default.** The full large-v3 encoder with a 4-layer decoder. This is what keeps live transcription at real-time speed. |
| **Best** | `openai_whisper-large-v3_turbo` | The full large-v3, and the largest model here. The decode cost is approximately 4 times the cost for each window, measured on read Tagalog. Use it to transcribe a finished recording again, and not for the live path. **On read Tagalog it was not more accurate than Balanced** and it failed on one long utterance in every repeat. Read [Measured and inferred](#measured-and-inferred). |

**The Best tier was named Accurate before.** The app reads a stored
`accurate` and gives you the Best tier, and `transcribe --tier accurate` also
still works. The name changed because "Accurate" states a property of the
transcript that this project has not measured, and "Best" names a position on
the speed ladder.

**Best is not suitable for the live path.** A 15-second window costs
multiples of the 1.5-second hop. Each hop would be dropped, and the commit
policy would never see two consecutive passes. `ModelTier.suitableForLive`
returns false for it.

Press ⇧⌘K to measure all three tiers on your own audio. The benchmark
recommends the slowest tier that stays at real-time speed, and it also reports
the tier that finished fastest. A quantized model uses less memory, but it is
not the fastest model on every generation of Apple silicon.

**The benchmark recommends a tier. It does not change which model sits behind
a tier.** The table above is the mapping, and this version of the app has no
code that changes it. You select a tier, and the tier selects the model.

**The benchmark ranks the tiers by decode time only. It does not measure
accuracy.** It reports a word error rate only if the caller gives it a
reference transcript, and the app has no reference transcript to give. The rule
"the slowest tier is the most accurate tier" comes from the model sizes. It is
an assumption. `BenchmarkReport.recommendedTier` records this.

The benchmark measures the Best tier if you select that tier. The weights
are approximately 3.2 GB, and the first start does not download them.
Therefore the first measurement downloads them, and it also pays the one-time
CoreML compile that [BENCHMARKS.md](BENCHMARKS.md) records.

## Measured and inferred

**The 2026-11-02 tier comparison measured all three tiers** on two corpora: 349 sentences of
read Tagalog (FLEURS `fil_ph`) and a 40-minute sample of conversational Taglish (Liva AI
`en-tl`). [eval/TIER-RESULTS.md](../eval/TIER-RESULTS.md) has the numbers and the method. The
decision was to keep Balanced as the default. The rows below give the result, then the
older, smaller measurements.

| Claim | Status |
| --- | --- |
| Balanced keeps live transcription at real-time speed | Measured. [BENCHMARKS.md](BENCHMARKS.md) gives the numbers. |
| Balanced is the model behind the offline Tagalog word error rate | Measured. Finding 1 in [FINDINGS.md](FINDINGS.md) records it. |
| Best gives a better transcript than Balanced | **2026-11-02: on read Tagalog, not supported** (11.35% against 11.66% WER, interval of the difference −0.97 to +0.34 points, 349 sentences). **On conversational Taglish, better by about 4 points** (64.8% against 68.3%, and 65.6% against 69.6% in a second decode), which is 5–6% relative, at 0.61 of real time against 0.15. One 40-minute voice chat of one group, not a meeting. Earlier: **Measured on read Tagalog, and not supported.** On 29 utterances of the FLEURS Filipino test set, Best scored 10.0% WER against 9.75% for Balanced, at about 4 times the decode time. On one 35 s utterance Best failed in 8 of 8 repeats (WER 30–86%) while Balanced scored 9.5%. This is read speech, and not Taglish or a meeting. [FINDINGS.md](FINDINGS.md) entry 25. |
| Fast gives up some accuracy against Balanced | **2026-11-02: a small loss on read Tagalog** (12.16% against 11.66%, interval −0.01 to +1.00 points; 75 sentences worse and 45 better, sign test p = 0.008). On conversational Taglish no stable difference (+2.2 points in one decode, −0.6 in the second). Fast was slower than Balanced (median RTF 0.086 against 0.067). Earlier: **Measured on read Tagalog: no loss found.** 9.3% against 9.7% over 30 utterances (confidence interval −1.4 to +0.4 points). Fast was not faster on the Mac mini M2 Pro (RTF 0.081 against 0.065). Not measured on Taglish. |
| The full large-v3 costs approximately 5 times the decode | Measured at about 4 times on read Tagalog (RTF 0.254 against 0.065), with a Neural Engine residency of 3,000 MB against 1,580 MB for Balanced. |

**Do not treat the Best tier as a known-better meeting transcript.** It was better on
one sample of conversational Taglish, by less than the 10% that a change of default needs, and
it cannot run live. The tier names a
position on the speed ladder, and not a measured result. To make it a measured
result, compare it against the Balanced tier on a real recording with a correct
reference transcript. The two clips that [BENCHMARKS.md](BENCHMARKS.md)
describes cannot answer this question. One clip uses an Indonesian voice, and
the reference transcript of the other clip is too poor.

## The full catalogue

`ModelCatalogue.all` in `app/Sources/TranscriberCore/Catalogues.swift` is the
list. Each entry carries what the model **is**, and not what it is called.

| Model ID | Label | Size | Multilingual | What it is |
| --- | --- | ---: | --- | --- |
| `openai_whisper-large-v3-v20240930_turbo` | large-v3-turbo | 1638 MB | yes | The turbo model of OpenAI: large-v3 with the decoder cut from 32 layers to 4. The same encoder, approximately 809M parameters. **The default.** |
| `openai_whisper-large-v3-v20240930_626MB` | large-v3-turbo (quantized) | 626 MB | yes | The same turbo model, quantized. Faster and lighter. No accuracy cost was measured on read Tagalog, and Taglish is unmeasured. |
| `openai_whisper-large-v3_turbo` | large-v3 (full, not turbo) | 3195 MB | yes | The full 1.5B large-v3. The `_turbo` suffix here is a compute variant of WhisperKit and **not** the turbo model. Its decoder is 5.3 times heavier. |
| `openai_whisper-medium` | medium | 1530 MB | yes | Much lighter. Expect a real accuracy drop on Taglish. |
| `openai_whisper-small` | small | 483 MB | yes | The fastest multilingual option. Use it to check the pipeline, and not for a transcript that you intend to keep. |
| `distil-whisper_distil-large-v3_turbo` | distil-large-v3 (English only) | 600 MB | **no** | English only. On Tagalog it translates instead of transcribes. |

## The `_turbo` trap

**The `_turbo` suffix of WhisperKit marks a compute variant. It is not the
large-v3-turbo model of OpenAI.**

OpenAI publishes large-v3-turbo under its September 2024 date stamp,
`large-v3-v20240930`. A match on the name "large-v3-turbo" therefore gives you
`openai_whisper-large-v3_turbo`, which is the full 1.5B large-v3.

Measured from the Hugging Face repository `argmaxinc/whisperkit-coreml`:

| WhisperKit model ID | TextDecoder weights | Total | What it actually is |
| --- | ---: | ---: | --- |
| `openai_whisper-large-v3` | 1813 MB | 3090 MB | large-v3, 32-layer decoder |
| `openai_whisper-large-v3_turbo` | 1813 MB | 3195 MB | still large-v3 — *not* turbo |
| `openai_whisper-large-v3-v20240930` | 344 MB | 1620 MB | large-v3-turbo, 4-layer decoder |
| **`openai_whisper-large-v3-v20240930_turbo`** | **344 MB** | **1638 MB** | **large-v3-turbo with prefill — the default** |

The decoder is 5.3 times smaller in the correct model. The live path decodes a
15-second window every 1.5 seconds, thus the decoder cost dominates the loop. A
choice by name match is therefore both much slower **and a different model**
from the one that the accuracy numbers were measured on.

Finding 1 in [FINDINGS.md](FINDINGS.md) and the model-ID table in
[ENVIRONMENT.md](ENVIRONMENT.md) record the measurements. **A change of model
id by name match is a change that this project usually refuses.**

## Languages

The app forces one language and does not translate. It writes code-switched
English inside another language as the speaker said it.

`LanguageCatalogue.all` gives the choices in Settings:

Tagalog / Taglish (`tl`, the default), English (`en`), Indonesian (`id`),
Malay (`ms`), Chinese (`zh`), Japanese (`ja`), Korean (`ko`), Spanish (`es`),
French (`fr`), German (`de`), Portuguese (`pt`), Arabic (`ar`), Hindi (`hi`),
Vietnamese (`vi`), Thai (`th`), and Auto-detect (`auto`).

The command-line tool passes `--language CODE` to the model without a check
against this list. Any language code that the model supports therefore works
from the command line.

**Automatic detection is available, and the app marks it as a risk.** The
decoder picks a language for each window, and it can translate instead of
transcribe. On the Taglish test clip, the decoder reported Indonesian for all
three windows and lost 48 words to deletion. The decoder listens to the voice.
It does not read the script. Pooled over the test set, forced `tl` is 23 points
better than `auto` and costs half the decode time on the synthetic clip. On
real read Tagalog (FLEURS, 40 utterances) `auto` gave the same text as forced
`tl` every time, at the same speed, so the difference above comes from the
Indonesian voice of that clip and not from Tagalog speech. Nothing has measured
`auto` on real Taglish. The default stays `tl`.
[BENCHMARKS.md](BENCHMARKS.md) gives the table.

**A model that is not multilingual translates instead of transcribes.** The
catalogue marks `distil-large-v3` as English only for this reason.

## Where the weights go

The app downloads the weights at the first start to
`~/Library/Application Support/Transcriber/Models`. WhisperKit lays them out
under `<base>/models/argmaxinc/whisperkit-coreml/<model-id>/`.

`ModelCatalogue.isDownloaded` tests for `TextDecoder.mlmodelc`. That is a hint and not
proof that the download finished: WhisperKit fetches its file names as a `Set`, so the
order is random and the decoder folder can exist after its first file. A folder that is
missing a part, or truncated, makes the folder load throw (QA tried a missing encoder,
missing weights and truncated weights with the network denied, and each threw a Swift
error and fell through), and the loader then takes the download path.

`transcribe --models DIR` reads the weights from `DIR` instead. Point it at a
directory that already holds them, and no download happens.

**The first load of a model compiles CoreML for the Neural Engine.** That took
284 seconds on the measurement Mac (160 s for the default model on the Mac mini M2 Pro,
82 s for Fast and 158 s for Best, n = 1 each). Later loads hit the cache. They took 9 to 11
seconds while every load asked the Hugging Face Hub, and they take about 1.6 seconds now that
a model that is already on disk is loaded from its folder with no Hub request (finding 30
in [FINDINGS.md](FINDINGS.md)). The first compile is still slow, so do not assume that the
first start is cheap.

## Memory

The models set the memory budget on a 16 GB Mac:

| Component | Resident memory |
| --- | ---: |
| large-v3-turbo (Balanced) | approximately 1.6 GB of Neural Engine memory (1,580 MB measured), and 66 to 77 MB of process footprint. Fast is 878 MB and Best is 3,000 MB. |
| The two speaker models | 13 MB on disk, about 23 MB of process footprint when loaded, and no Neural Engine memory (measured on 2026-11-01; the earlier figure of 200 MB was never measured) |

macOS starts to compress memory well before the ceiling. `EngineHost` therefore
holds exactly one instance of each model, shares them between the live path and
the background queue, and releases the speaker models as soon as no job needs
them. [ARCHITECTURE.md](ARCHITECTURE.md) gives the rest of the memory design.

Disk space is larger than resident memory. Reserve approximately 1.9 GB for the
default speech model and the two speaker models together.

## Licences

**This repository contains no model weights.** The app downloads them at the
first start from Hugging Face. The sources are `argmaxinc/whisperkit-coreml`
and the CoreML conversions of Silero VAD and pyannote by FluidAudio.

**Each model has its own upstream licence, and some licences control access
with an agreement.** Read each model card on Hugging Face before you distribute
a bundle that contains these weights. The MIT licence of this repository covers
the code only.

The app has two direct Swift package dependencies and one transitive
dependency. `app/Package.resolved` pins all three, and the assembled
`Notero.app` contains all three:

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT, Argmax Inc.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Apache-2.0,
  FluidInference. It supplies Silero VAD, pyannote segmentation and WeSpeaker
  embedding as CoreML models.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) —
  Apache-2.0, Apple. A transitive dependency.

**The model weights are third-party code that runs on your Mac.** If you point
the app or `transcribe --models DIR` at a different weights directory, you also
trust the person who made that directory.
