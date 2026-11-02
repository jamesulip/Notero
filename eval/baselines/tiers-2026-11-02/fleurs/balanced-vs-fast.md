# ASR comparison: balanced → fast

| | |
| --- | --- |
| Corpus | `fleurs-fil_ph-test-onepersentence-seed7` |
| Configuration | `notero-eval-v1`, fingerprint `96fdf032732a3b31` |
| Scoring policy | `notero-standard` v1 |
| Baseline System | balanced |
| Baseline Model | `openai_whisper-large-v3-v20240930_turbo` |
| Baseline Model revision | `0f63a7800b00dd0226abd051b906c246e1907482` |
| Baseline Build | `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78` |
| Baseline Hardware | Mac14,12 · 10 cores · macOS 26.6, 16 GB |
| Baseline Inference | mode offline, language tl, diarization off, roomMode false, styleHint false |
| Candidate System | fast |
| Candidate Model | `openai_whisper-large-v3-v20240930_626MB` |
| Candidate Model revision | `0f63a7800b00dd0226abd051b906c246e1907482` |
| Candidate Build | `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78` |
| Candidate Hardware | Mac14,12 · 10 cores · macOS 26.6, 16 GB |
| Candidate Inference | mode offline, language tl, diarization off, roomMode false, styleHint false |

Difference = candidate − baseline. Negative means fewer errors in the candidate. "Candidate lower" is the share of resamples in which the candidate's rate was lower: a description of the resamples, not a p-value.

| Metric | Baseline | Candidate | Difference | 95% interval of difference | Candidate lower | Tied | Units |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| WER | 11.66% | 12.16% | +0.50 pt | -0.01 to +1.00 pt | 2.60% | 0.30% | 349 |
| CER | 3.64% | 3.86% | +0.23 pt | -0.00 to +0.51 pt | 2.60% | 0.00% | 349 |
| WER, tagalog | 11.66% | 12.16% | +0.50 pt | -0.01 to +1.00 pt | 2.60% | 0.30% | 349 |

Interval: percentile bootstrap of the pooled rate ΣE/ΣN, type-7 quantiles, SplitMix64; 2000 paired resamples, seed 20261102, stratified by utterance language class.

