# Session 2: independent session on held-out real clips: the promoted variant and head-tolerant agreement

Plan sha256 `45fba632139fbc73`, commit `f7a24db416`, binary `93f6b23deb9e`. 9 of 9 blocks complete; 0 failed runs.

Machine during the replays: median 0.7 of 10 cores busy in total (p90 1.0); the replay itself used a median 0.18 cores; lock wait median 1 s. Blocks shared with other jobs (other cores p90 above the plan's limit): 1 (liva-b/r1).

## Commit latency by arm (mean over runs of each run's own quantile, wall clock, ms)

| arm | words | median | p90 | p95 | audio-clock median | dropped hops | forced | empty | failed hops | critical halluc. | invariant breaks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| C0 | 3102 | 8,553 | 13,916 | 15,560 | 8,418 | 190 (18.4%) | 92 | 62 | 0 | 3 | 0 |
| C1 | 3094 | 8,989 | 14,137 | 15,683 | 8,904 | 185 (17.9%) | 106 | 61 | 0 | 2 | 0 |
| ADA | 3106 | 7,797 | 14,527 | 15,967 | 7,484 | 197 (16.4%) | 92 | 66 | 0 | 2 | 0 |
| HT | 3099 | 7,501 | 13,083 | 15,012 | 7,216 | 174 (16.9%) | 62 | 66 | 0 | 3 | 0 |

Median commit latency of the words pooled by corpus, per arm (ms):

| arm | ami | fleurs | liva | reference-anchored segment median |
| --- | ---: | ---: | ---: | ---: |
| C0 | 5,283 | 3,271 | 17,107 | 7,791 |
| C1 | 6,604 | 3,229 | 17,087 | 7,995 |
| ADA | 3,937 | 2,741 | 16,786 | 6,584 |
| HT | 4,300 | 3,227 | 15,146 | 5,925 |

## A/A: the control against itself

C1 against C0, commit latency reduction: median -7.7% [-18.5%, 2.2%] (two-sided p 0.156), p90 -1.4%, p95 -1.5%. Session valid. Per-block median ratios C1/C0: 1.13, 1.29, 1.35, 0.98, 1.03, 0.98, 1.00, 1.01, 0.99.
WER, C1 minus C0, over 6 blocks: -0.44 points, 95% interval -1.61 to +0.72.

## Variants against the controls

### ADA: hop scheduling. the hop tracks the last decode (1.5x, between 1.0 and 1.5 s)

* Commit latency reduction (wall): median 16.7% [1.2%, 29.8%] (randomization p 0.0032), p90 -2.6% [-35.6%, 22.3%] (p 0.6216), p95 -1.5% [-30.1%, 20.8%] (p 0.5612). Audio-clock median 17.9%; anchored on the reference segment ends 24.4%. Faster on 3 of 3 clips: fleurs-lf2 15.8%, liva-b 5.4%, ami-b 27.4%
* By corpus (median): ami 27.4% [-81.6%, 70.9%], fleurs 15.8% [10.0%, 21.2%], liva 5.4% [-18.4%, 24.5%]
* Variant minus control, per block: WER -0.32 points [-2.01, +1.37], p 0.717 (Holm p 1.000); deletion rate +0.47 points [-2.71, +3.65], p 0.293; missing-speech share -0.36 points [-0.84, +0.12], p 0.935; omitted turns -0.48 points [-1.20, +0.25], p 1.000.
* Also, variant minus control per block: forced commits -0.78, dropped hops +1.06, empty hypotheses +0.50, repeat excess -1.00, ghost words +0.00, CPU +0.20 s per audio minute, infer RTF +0.044, decodes/min +6.0, mean window -1170 ms. Finalization latency median 1,321 ms against 1,398 ms.
* Critical hallucinations 2 against a control mean of 2.5; ghost words 0 against 0.0.
* Without the 1 shared blocks: median reduction 16.9% (p 0.0068), every gate does not pass.
* Gates: latency FAIL, wer PASS, missingSpeech PASS, hallucinations PASS, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### HT: agreement. head-tolerant agreement: tolerance 3 words, run of 3 (FINDINGS 27)

* Commit latency reduction (wall): median 14.5% [2.5%, 25.0%] (randomization p 0.0007), p90 7.0% [-7.0%, 19.2%] (p 0.1004), p95 3.3% [-9.0%, 14.1%] (p 0.2389). Audio-clock median 15.5%; anchored on the reference segment ends 29.5%. Faster on 3 of 3 clips: fleurs-lf2 0.3%, liva-b 13.4%, ami-b 27.7%
* By corpus (median): ami 27.7% [10.4%, 41.6%], fleurs 0.3% [-6.7%, 6.8%], liva 13.4% [-33.7%, 43.9%]
* Variant minus control, per block: WER +0.28 points [-3.47, +4.04], p 0.396 (Holm p 1.000); deletion rate +0.92 points [-2.85, +4.68], p 0.185; missing-speech share -0.47 points [-1.45, +0.52], p 0.885; omitted turns +0.16 points [-0.56, +0.87], p 0.443.
* Also, variant minus control per block: forced commits -4.11, dropped hops -1.50, empty hypotheses +0.50, repeat excess -1.50, ghost words +0.00, CPU -0.33 s per audio minute, infer RTF -0.013, decodes/min +0.4, mean window -952 ms. Finalization latency median 1,399 ms against 1,398 ms.
* Critical hallucinations 3 against a control mean of 2.5; ghost words 0 against 0.0.
* Without the 1 shared blocks: median reduction 12.5% (p 0.0023), every gate does not pass.
* Gates: latency FAIL, wer PASS, missingSpeech FAIL, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**
