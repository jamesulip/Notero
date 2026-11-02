# Diarization comparison

Commit `304ca227d9` (dirty), Mac14,12 Apple M2 Pro 16 GB, macOS 26.6.2. Baseline `pyannote`.

Primary rules: collar 0.25 s around every reference boundary; frame 0.01 s; overlapped speech scored; merge/fragment judged on reference speakers with >= 5.0 s; a fragment holds >= 10% of its speaker; hypothesis speakers under 1.0 s are not counted.

## Pooled DER by corpus (run 1)

| Corpus | Arm | Files | DER | Missed | False alarm | Confusion | DER, overlap only | DER, single-speaker only | Overlap share |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ami | pyannote | 16 | 23.70% | 12.73% | 1.52% | 9.45% | 53.41% | 17.31% | 17.69% |
| ami | nemotron3 | 16 | 24.13% | 23.28% | 0.45% | 0.40% | 40.73% | 20.56% | 17.69% |
| ami | nemotron3-fast128 | 16 | 24.15% | 23.31% | 0.49% | 0.35% | 40.69% | 20.60% | 17.69% |
| liva | pyannote | 4 | 58.13% | 23.36% | 2.66% | 32.12% | 63.52% | 56.73% | 20.65% |
| liva | nemotron3 | 4 | 16.07% | 13.78% | 0.56% | 1.73% | 24.84% | 13.79% | 20.65% |
| liva | nemotron3-fast128 | 4 | 17.99% | 13.83% | 0.79% | 3.37% | 26.05% | 15.89% | 20.65% |
| synth-tuning | pyannote | 7 | 17.66% | 11.85% | 0.02% | 5.78% | — | 17.66% | 0.00% |
| synth-tuning | nemotron3 | 7 | 3.15% | 2.82% | 0.10% | 0.24% | — | 3.15% | 0.00% |
| synth-tuning | nemotron3-fast128 | 7 | 4.20% | 2.67% | 0.00% | 1.54% | — | 4.20% | 0.00% |
| synth-holdout | pyannote | 5 | 5.87% | 4.53% | 0.11% | 1.24% | — | 5.87% | 0.00% |
| synth-holdout | nemotron3 | 5 | 7.90% | 4.08% | 0.11% | 3.71% | — | 7.90% | 0.00% |
| synth-holdout | nemotron3-fast128 | 5 | 7.94% | 4.20% | 0.00% | 3.74% | — | 7.94% | 0.00% |
| synth-n | pyannote | 5 | 15.38% | 10.09% | 0.19% | 5.10% | 48.21% | 14.91% | 1.40% |
| synth-n | nemotron3 | 5 | 11.40% | 3.39% | 0.10% | 7.90% | 15.02% | 11.35% | 1.40% |
| synth-n | nemotron3-fast128 | 5 | 10.27% | 3.08% | 0.10% | 7.08% | 6.72% | 10.32% | 1.40% |

## Other scoring rules (run 1, pooled DER)

| Corpus | Arm | collar 0.0 s, overlap scored | collar 0.25 s, overlap skipped |
| --- | --- | ---: | ---: |
| ami | pyannote | 30.91% | 17.31% |
| ami | nemotron3 | 26.24% | 20.56% |
| ami | nemotron3-fast128 | 26.33% | 20.60% |
| liva | pyannote | 67.90% | 56.73% |
| liva | nemotron3 | 24.03% | 13.79% |
| liva | nemotron3-fast128 | 25.53% | 15.89% |
| synth-tuning | pyannote | 23.83% | 17.66% |
| synth-tuning | nemotron3 | 3.86% | 3.15% |
| synth-tuning | nemotron3-fast128 | 4.80% | 4.20% |
| synth-holdout | pyannote | 13.75% | 5.87% |
| synth-holdout | nemotron3 | 8.90% | 7.90% |
| synth-holdout | nemotron3-fast128 | 9.00% | 7.94% |
| synth-n | pyannote | 21.72% | 14.91% |
| synth-n | nemotron3 | 12.80% | 11.35% |
| synth-n | nemotron3-fast128 | 11.26% | 10.32% |

## Speakers, merges, fragments (run 1)

| Corpus | Arm | Files with a wrong count | Sum of count errors | Merged reference speakers | Fragmented reference speakers | Overlap detection recall | precision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ami | pyannote | 11 | +1 | 19 | 0 | 13.58% | 88.77% |
| ami | nemotron3 | 1 | +1 | 2 | 0 | 46.26% | 90.72% |
| ami | nemotron3-fast128 | 1 | +1 | 2 | 0 | 45.87% | 90.79% |
| liva | pyannote | 2 | -2 | 16 | 0 | 0.00% | — |
| liva | nemotron3 | 2 | -2 | 2 | 0 | 62.59% | 98.75% |
| liva | nemotron3-fast128 | 3 | -3 | 4 | 0 | 63.55% | 97.66% |
| synth-tuning | pyannote | 1 | -1 | 2 | 0 | — | — |
| synth-tuning | nemotron3 | 0 | +0 | 0 | 0 | — | — |
| synth-tuning | nemotron3-fast128 | 0 | +0 | 0 | 0 | — | — |
| synth-holdout | pyannote | 1 | -1 | 2 | 0 | — | — |
| synth-holdout | nemotron3 | 0 | +0 | 2 | 0 | — | — |
| synth-holdout | nemotron3-fast128 | 1 | -1 | 2 | 0 | — | — |
| synth-n | pyannote | 2 | -2 | 4 | 0 | 6.18% | 100.00% |
| synth-n | nemotron3 | 2 | -2 | 4 | 0 | 99.43% | 90.14% |
| synth-n | nemotron3-fast128 | 1 | -1 | 2 | 0 | 91.23% | 87.39% |

## By number of reference speakers (run 1, pooled over all corpora)

| Speakers | Arm | Files | DER | Confusion | Merged | Fragmented |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 2 | pyannote | 7 | 10.42% | 5.61% | 2 | 0 |
| 2 | nemotron3 | 7 | 1.27% | 0.00% | 0 | 0 |
| 2 | nemotron3-fast128 | 7 | 1.04% | 0.00% | 0 | 0 |
| 3 | pyannote | 6 | 21.32% | 1.89% | 2 | 0 |
| 3 | nemotron3 | 6 | 24.71% | 0.13% | 0 | 0 |
| 3 | nemotron3-fast128 | 6 | 24.70% | 0.15% | 0 | 0 |
| 4 | pyannote | 19 | 23.83% | 10.37% | 22 | 0 |
| 4 | nemotron3 | 19 | 23.27% | 0.53% | 4 | 0 |
| 4 | nemotron3-fast128 | 19 | 23.37% | 0.56% | 4 | 0 |
| 5 | pyannote | 4 | 51.95% | 27.31% | 15 | 0 |
| 5 | nemotron3 | 4 | 15.82% | 2.25% | 4 | 0 |
| 5 | nemotron3-fast128 | 4 | 15.59% | 2.07% | 4 | 0 |
| 6 | pyannote | 1 | 22.58% | 15.43% | 2 | 0 |
| 6 | nemotron3 | 1 | 26.98% | 24.19% | 2 | 0 |
| 6 | nemotron3-fast128 | 1 | 27.06% | 23.48% | 2 | 0 |

## Runtime and memory (all runs)

| Corpus | Arm | Median speaker-pass RTF | Median diarize s | Median load s | Max peak footprint MB |
| --- | --- | ---: | ---: | ---: | ---: |
| ami | pyannote | 0.0064 | 13.1 | 0.12 | 1678 |
| ami | nemotron3 | 0.0028 | 6.0 | 0.10 | 94 |
| ami | nemotron3-fast128 | 0.0035 | 7.6 | 0.09 | 79 |
| liva | pyannote | 0.0094 | 5.6 | 0.12 | 533 |
| liva | nemotron3 | 0.0029 | 1.7 | 0.10 | 74 |
| liva | nemotron3-fast128 | 0.0036 | 2.2 | 0.09 | 61 |
| synth-tuning | pyannote | 0.0103 | 1.1 | 0.12 | 178 |
| synth-tuning | nemotron3 | 0.0033 | 0.3 | 0.10 | 70 |
| synth-tuning | nemotron3-fast128 | 0.0040 | 0.4 | 0.09 | 58 |
| synth-holdout | pyannote | 0.0107 | 1.3 | 0.12 | 196 |
| synth-holdout | nemotron3 | 0.0036 | 0.4 | 0.09 | 69 |
| synth-holdout | nemotron3-fast128 | 0.0039 | 0.4 | 0.09 | 58 |
| synth-n | pyannote | 0.0099 | 1.6 | 0.12 | 245 |
| synth-n | nemotron3 | 0.0031 | 0.6 | 0.09 | 68 |
| synth-n | nemotron3-fast128 | 0.0038 | 0.7 | 0.09 | 58 |

Peak footprint is process memory. Core ML weights held by the Neural Engine or GPU are not all inside it, so it is not model residency.

## Repeat stability

| Arm | Repeated files | Identical output | Max DER spread |
| --- | ---: | ---: | ---: |
| pyannote | 37 | 37 | 0.00 pt |
| nemotron3 | 37 | 37 | 0.00 pt |
| nemotron3-fast128 | 37 | 37 | 0.00 pt |

## Per file (run 1)

| File | Ref speakers | pyannote DER (hyp speakers) | nemotron3 DER (hyp speakers) | nemotron3-fast128 DER (hyp speakers) |
| --- | ---: | ---: | ---: | ---: |
| ami-IS1009a | 4 | 25.83% (6) M | 24.92% (4) M | 23.67% (4) M |
| ami-IS1009b | 4 | 24.76% (4) M | 11.90% (4) | 11.93% (4) |
| ami-IS1009c | 4 | 14.10% (4) | 13.31% (4) | 13.54% (4) |
| ami-IS1009d | 4 | 18.85% (3) M | 16.42% (4) | 16.84% (4) |
| ami-ES2004a | 4 | 14.76% (5) | 24.83% (4) | 25.00% (4) |
| ami-ES2004b | 4 | 10.04% (5) | 19.48% (5) | 19.04% (4) |
| ami-ES2004c | 4 | 9.15% (4) | 18.22% (4) | 18.27% (4) |
| ami-ES2004d | 4 | 36.31% (3) M | 19.40% (4) | 19.56% (4) |
| ami-TS3003a | 4 | 15.81% (3) M | 33.40% (4) | 33.34% (4) |
| ami-TS3003b | 4 | 16.47% (3) M | 25.31% (4) | 25.36% (4) |
| ami-TS3003c | 4 | 42.74% (2) M | 29.23% (4) | 29.37% (4) |
| ami-TS3003d | 4 | 19.51% (4) | 30.37% (4) | 30.52% (4) |
| ami-EN2002a | 4 | 37.32% (5) M | 28.23% (4) | 28.68% (4) |
| ami-EN2002b | 4 | 33.89% (4) M | 28.93% (4) | 28.78% (4) |
| ami-EN2002c | 3 | 22.58% (4) | 28.45% (3) | 28.45% (4) |
| ami-EN2002d | 4 | 30.19% (5) | 32.63% (4) | 32.38% (4) |
| liva-C_001_007 | 4 | 51.16% (4) M | 9.71% (3) | 17.42% (3) |
| liva-C_001_009 | 5 | 57.59% (4) M | 14.63% (5) | 15.94% (5) |
| liva-C_001_015 | 5 | 51.33% (5) M | 20.06% (4) M | 20.25% (4) M |
| liva-C_001_016 | 5 | 69.66% (4) M | 18.83% (5) | 18.48% (4) M |
| synth-tuning-chunk-fusion | 2 | 8.51% (2) | 1.10% (2) | 0.40% (2) |
| synth-tuning-four-voices | 4 | 16.80% (4) | 6.93% (4) | 11.93% (4) |
| synth-tuning-three-overlap | 3 | 14.77% (3) | 5.86% (3) | 6.03% (3) |
| synth-tuning-three-voices | 3 | 25.72% (3) | 2.63% (3) | 2.49% (3) |
| synth-tuning-two-distinct | 2 | 6.69% (2) | 0.61% (2) | 0.24% (2) |
| synth-tuning-two-short-turns | 2 | 6.87% (2) | 0.00% (2) | 0.00% (2) |
| synth-tuning-two-similar | 2 | 39.46% (1) M | 0.96% (2) | 0.96% (2) |
| synth-holdout-h-four-voices | 4 | 6.14% (4) | 21.71% (4) M | 22.17% (3) M |
| synth-holdout-h-three-overlap | 3 | 12.83% (2) M | 2.83% (3) | 2.67% (3) |
| synth-holdout-h-three-voices | 3 | 2.93% (3) | 2.99% (3) | 3.22% (3) |
| synth-holdout-h-two-distinct | 2 | 3.97% (2) | 2.11% (2) | 2.14% (2) |
| synth-holdout-h-two-short-turns | 2 | 4.65% (2) | 3.94% (2) | 3.23% (2) |
| synth-n-n2 | 2 | 4.12% (2) | 0.30% (2) | 0.30% (2) |
| synth-n-n3 | 3 | 14.71% (3) | 3.83% (3) | 3.51% (3) |
| synth-n-n4 | 4 | 11.05% (4) | 9.13% (4) | 7.13% (4) |
| synth-n-n5 | 5 | 18.03% (4) M | 7.67% (4) M | 4.78% (5) |
| synth-n-n6 | 6 | 22.58% (5) M | 26.98% (5) M | 27.06% (5) M |

M: at least two reference speakers merged. F: at least one reference speaker fragmented.

