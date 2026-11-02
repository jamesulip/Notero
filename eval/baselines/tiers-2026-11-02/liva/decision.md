# Tier decision on `liva-en-tl-overlapping-51b5d0b`

Commit `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78`, binary sha256 `0eb68b4cac0e9947…`.

**Decision: keep balanced.**

| Tier | Model | WER | 95% CI | CER | S / D / I | Items | Failed | Median RTF | Median load | Model residency | Peak footprint |
| --- | --- | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| balanced | `openai_whisper-large-v3-v20240930_turbo` | 68.34% | 66.26%–70.47% | 53.83% | 1843 / 1848 / 93 | 4/4 | 0 | 0.153 | 1.9 s | 1580 MB | 178 MB |
| best | `openai_whisper-large-v3_turbo` | 64.80% | 62.52%–67.22% | 50.61% | 1735 / 1739 / 114 | 4/4 | 0 | 0.606 | 3.0 s | 3000 MB | 268 MB |
| fast | `openai_whisper-large-v3-v20240930_626MB` | 70.49% | 68.43%–72.49% | 56.68% | 1853 / 2000 / 50 | 4/4 | 0 | 0.258 | 2.0 s | 878 MB | 157 MB |

## Gate

### best against balanced

Difference -3.54 pt, 95% interval -5.49 to -1.36 pt. Meets the gate: **no**.

| Check | Value | Needed | Pass |
| --- | --- | --- | --- |
| relativeWerImprovement | 0.0518 | >= 0.1 | no |
| differenceIntervalBelowZero | -5.49 to -1.36 pt | upper < 0 | yes |
| liveCapable | False | true | no |
| medianWholeFileRTF | 0.6056 | <= 0.6 | no |
| modelResidencyMB | 3000.0000 | <= 3500 | yes |
| allItemsScored | 4/4 | every item, both tiers | yes |
| residencyMeasuredOnEveryItem | True | true | yes |
| stableAcrossDecodes | second-pass relative improvement 0.0571 | >= 0.1 in the second pass too | no |
| failedDecodes | 0 | <= baseline + 0 | yes |

### fast against balanced

Difference +2.15 pt, 95% interval +0.64 to +3.60 pt. Meets the gate: **no**.

| Check | Value | Needed | Pass |
| --- | --- | --- | --- |
| relativeWerImprovement | -0.0314 | >= 0.1 | no |
| differenceIntervalBelowZero | +0.64 to +3.60 pt | upper < 0 | no |
| liveCapable | True | true | yes |
| medianWholeFileRTF | 0.2581 | <= 0.6 | yes |
| modelResidencyMB | 878.0000 | <= 3500 | yes |
| allItemsScored | 4/4 | every item, both tiers | yes |
| residencyMeasuredOnEveryItem | True | true | yes |
| stableAcrossDecodes | second-pass relative improvement 0.0086 | >= 0.1 in the second pass too | no |
| failedDecodes | 0 | <= baseline + 0 | yes |

Peak footprint is the `phys_footprint` of the decoding process and does not contain the model: add the model residency for the memory the process really used. The 95% intervals resample utterances or items of one decode; where decodes are not repeatable, the `stableAcrossDecodes` check, not the interval, says whether a difference survives a second pass. A tier that is not live-capable cannot pass, whatever its accuracy, because the default tier also drives live transcription.

Every figure above is measured in this run. The gate was fixed in the plan before the first decode. The corpus is what its corpus card says it is; a result here is not a result on speech the corpus does not contain.
