# Tier decision on `fleurs-fil_ph-test-onepersentence-seed7`

Commit `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78`, binary sha256 `0eb68b4cac0e9947…`.

**Decision: keep balanced.**

| Tier | Model | WER | 95% CI | CER | S / D / I | Items | Failed | Median RTF | Median load | Model residency | Peak footprint |
| --- | --- | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| balanced | `openai_whisper-large-v3-v20240930_turbo` | 11.66% | 10.73%–12.64% | 3.64% | 869 / 123 / 129 | 349/349 | 0 | 0.067 | 1.9 s | 1580 MB | 133 MB |
| best | `openai_whisper-large-v3_turbo` | 11.35% | 10.41%–12.34% | 3.45% | 842 / 124 / 125 | 349/349 | 0 | 0.247 | 2.2 s | 3000 MB | 184 MB |
| fast | `openai_whisper-large-v3-v20240930_626MB` | 12.16% | 11.18%–13.22% | 3.86% | 900 / 120 / 149 | 349/349 | 0 | 0.086 | 2.0 s | 878 MB | 96 MB |

## Gate

### best against balanced

Difference -0.31 pt, 95% interval -0.97 to +0.34 pt. Meets the gate: **no**.

| Check | Value | Needed | Pass |
| --- | --- | --- | --- |
| relativeWerImprovement | 0.0268 | >= 0.1 | no |
| differenceIntervalBelowZero | -0.97 to +0.34 pt | upper < 0 | no |
| liveCapable | False | true | no |
| medianWholeFileRTF | 0.2467 | <= 0.6 | yes |
| modelResidencyMB | 3000 | <= 3500 | yes |
| allItemsScored | 349/349 | every item, both tiers | yes |
| residencyMeasuredOnEveryItem | True | true | yes |
| stableAcrossDecodes | repeats identical | deterministic, or a second pass that agrees | yes |
| failedDecodes | 0 | <= baseline + 0 | yes |

### fast against balanced

Difference +0.50 pt, 95% interval -0.01 to +1.00 pt. Meets the gate: **no**.

| Check | Value | Needed | Pass |
| --- | --- | --- | --- |
| relativeWerImprovement | -0.0428 | >= 0.1 | no |
| differenceIntervalBelowZero | -0.01 to +1.00 pt | upper < 0 | no |
| liveCapable | True | true | yes |
| medianWholeFileRTF | 0.0856 | <= 0.6 | yes |
| modelResidencyMB | 878 | <= 3500 | yes |
| allItemsScored | 349/349 | every item, both tiers | yes |
| residencyMeasuredOnEveryItem | True | true | yes |
| stableAcrossDecodes | repeats identical | deterministic, or a second pass that agrees | yes |
| failedDecodes | 0 | <= baseline + 0 | yes |

Peak footprint is the `phys_footprint` of the decoding process and does not contain the model: add the model residency for the memory the process really used. The 95% intervals resample utterances or items of one decode; where decodes are not repeatable, the `stableAcrossDecodes` check, not the interval, says whether a difference survives a second pass. A tier that is not live-capable cannot pass, whatever its accuracy, because the default tier also drives live transcription.

Every figure above is measured in this run. The gate was fixed in the plan before the first decode. The corpus is what its corpus card says it is; a result here is not a result on speech the corpus does not contain.
