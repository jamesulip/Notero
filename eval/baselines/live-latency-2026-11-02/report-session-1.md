# Session 1: screening: every variant against the control, three clips

Plan sha256 `13a1355d07c74fdc`, commit `cab57f7308`, binary `93f6b23deb9e`. 9 of 9 blocks complete; 0 failed runs.

Machine during the replays: median 0.7 of 10 cores busy in total (p90 1.2); the replay itself used a median 0.16 cores; lock wait median 1 s. Blocks shared with other jobs (other cores p90 above the plan's limit): 2 (fleurs-lf1/r1, liva-a/r2).

## Commit latency by arm (mean over runs of each run's own quantile, wall clock, ms)

| arm | words | median | p90 | p95 | audio-clock median | dropped hops | forced | empty | failed hops | critical halluc. | invariant breaks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| C0 | 2727 | 8,202 | 14,504 | 16,415 | 8,123 | 212 (21.1%) | 115 | 49 | 0 | 11 | 0 |
| C1 | 2736 | 8,183 | 15,431 | 16,869 | 8,096 | 181 (18.1%) | 130 | 60 | 0 | 9 | 0 |
| HT | 2692 | 8,094 | 12,146 | 13,986 | 7,981 | 170 (16.8%) | 89 | 74 | 0 | 7 | 0 |
| VAD | 2785 | 8,160 | 14,968 | 16,994 | 8,068 | 148 (14.7%) | 115 | 72 | 0 | 7 | 0 |
| PRE | 2499 | 8,883 | 16,241 | 17,955 | 8,741 | 183 (18.4%) | 80 | 53 | 0 | 8 | 0 |
| HOP | 2707 | 7,731 | 13,348 | 14,734 | 7,671 | 239 (20.4%) | 99 | 80 | 0 | 9 | 0 |
| ADA | 2676 | 7,526 | 12,758 | 15,080 | 7,471 | 204 (16.8%) | 117 | 72 | 0 | 9 | 0 |
| CTX | 2714 | 6,824 | 12,286 | 13,677 | 6,765 | 152 (15.1%) | 97 | 62 | 0 | 16 | 0 |

Median commit latency of the words pooled by corpus, per arm (ms):

| arm | ami | fleurs | liva | reference-anchored segment median |
| --- | ---: | ---: | ---: | ---: |
| C0 | 3,468 | 3,612 | 17,442 | 7,186 |
| C1 | 3,443 | 3,634 | 17,387 | 7,415 |
| HT | 3,158 | 3,664 | 16,866 | 6,988 |
| VAD | 3,263 | 4,154 | 16,983 | 7,062 |
| PRE | 3,718 | 3,880 | 18,470 | 7,330 |
| HOP | 3,160 | 3,007 | 17,026 | 6,778 |
| ADA | 2,603 | 2,799 | 17,106 | 7,009 |
| CTX | 3,498 | 3,706 | 13,662 | 6,007 |

## A/A: the control against itself

C1 against C0, commit latency reduction: median 0.2% [-3.1%, 3.4%] (two-sided p 0.918), p90 -7.5%, p95 -3.3%. Session valid. Per-block median ratios C1/C0: 1.03, 0.95, 0.99, 0.94, 1.01, 1.08, 1.01, 1.01, 0.97.
WER, C1 minus C0, over 6 blocks: +0.75 points, 95% interval -1.89 to +3.38.

## Variants against the controls

### HT: agreement. head-tolerant agreement: tolerance 3 words, run of 3 (FINDINGS 27)

* Commit latency reduction (wall): median 0.6% [-14.6%, 13.7%] (randomization p 0.5846), p90 27.3% [-6.7%, 50.5%] (p 0.0141), p95 23.6% [-12.2%, 48.0%] (p 0.0431). Audio-clock median 1.0%; anchored on the reference segment ends -7.0%. Faster on 2 of 3 clips: fleurs-lf1 -11.0%, liva-a 3.0%, ami-a 8.7%
* By corpus (median): ami 8.7% [-2.7%, 18.8%], fleurs -11.0% [-147.8%, 50.3%], liva 3.0% [-1.4%, 7.2%]
* Variant minus control, per block: WER -1.15 points [-5.42, +3.13], p 0.807 (Holm p 1.000); deletion rate +0.94 points [-2.02, +3.91], p 0.247; missing-speech share -0.19 points [-1.16, +0.78], p 0.504; omitted turns +0.64 points [-0.18, +1.46], p 0.370.
* Also, variant minus control per block: forced commits -3.72, dropped hops -2.94, empty hypotheses +2.17, repeat excess -1.33, ghost words -0.39, CPU -1.12 s per audio minute, infer RTF -0.029, decodes/min +1.2, mean window -725 ms. Finalization latency median 1,368 ms against 1,350 ms.
* Critical hallucinations 7 against a control mean of 10.0; ghost words 1 against 4.5.
* Without the 2 shared blocks: median reduction 6.5% (p 0.0008), every gate does not pass.
* Gates: latency FAIL, wer PASS, missingSpeech FAIL, hallucinations PASS, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### VAD: VAD finalization. an utterance closes after 500 ms of silence instead of 700 ms

* Commit latency reduction (wall): median -1.4% [-9.9%, 6.4%] (randomization p 0.7086), p90 -0.1% [-10.0%, 8.8%] (p 0.5255), p95 -2.9% [-9.9%, 3.6%] (p 0.7863). Audio-clock median -1.1%; anchored on the reference segment ends 3.5%. Faster on 2 of 3 clips: fleurs-lf1 -12.3%, liva-a 2.3%, ami-a 4.9%
* By corpus (median): ami 4.9% [1.8%, 7.9%], fleurs -12.3% [-58.9%, 20.6%], liva 2.3% [-1.3%, 5.7%]
* Variant minus control, per block: WER +1.00 points [-1.69, +3.69], p 0.162 (Holm p 0.650); deletion rate -1.64 points [-5.02, +1.74], p 0.867; missing-speech share -1.14 points [-3.46, +1.18], p 0.809; omitted turns -0.82 points [-3.28, +1.64], p 0.707.
* Also, variant minus control per block: forced commits -0.83, dropped hops -5.39, empty hypotheses +1.94, repeat excess -1.00, ghost words +0.39, CPU -0.26 s per audio minute, infer RTF -0.001, decodes/min +1.9, mean window -238 ms. Finalization latency median 1,118 ms against 1,350 ms.
* Critical hallucinations 7 against a control mean of 10.0; ghost words 8 against 4.5.
* Without the 2 shared blocks: median reduction -2.2% (p 0.7289), every gate does not pass.
* Gates: latency FAIL, wer FAIL, missingSpeech PASS, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### PRE: context anchoring. 3 s of committed audio kept in front of the active region instead of 1.5 s (the ring holds context + pre-roll, so the active region is still capped at 15 s)

* Commit latency reduction (wall): median -10.3% [-21.6%, -0.1%] (randomization p 0.9998), p90 -7.5% [-26.7%, 8.8%] (p 0.8963), p95 -7.7% [-19.0%, 2.5%] (p 0.9550). Audio-clock median -9.5%; anchored on the reference segment ends -36.1%. Faster on 0 of 3 clips: fleurs-lf1 -17.4%, liva-a -5.7%, ami-a -8.2%
* By corpus (median): ami -8.2% [-24.0%, 5.6%], fleurs -17.4% [-105.6%, 32.9%], liva -5.7% [-13.4%, 1.6%]
* Variant minus control, per block: WER +1.19 points [-2.40, +4.78], p 0.156 (Holm p 0.156); deletion rate +7.98 points [-2.73, +18.70], p 0.023; missing-speech share +5.72 points [-1.49, +12.93], p 0.016; omitted turns +5.37 points [-1.02, +11.77], p 0.040.
* Also, variant minus control per block: forced commits -4.72, dropped hops -1.50, empty hypotheses -0.17, repeat excess -1.50, ghost words +0.28, CPU +0.17 s per audio minute, infer RTF +0.010, decodes/min +0.3, mean window +1438 ms. Finalization latency median 1,392 ms against 1,350 ms.
* Critical hallucinations 8 against a control mean of 10.0; ghost words 7 against 4.5.
* Without the 2 shared blocks: median reduction -12.4% (p 1.0000), every gate does not pass.
* Gates: latency FAIL, wer FAIL, missingSpeech FAIL, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### HOP: hop scheduling. a decode every 1.3 s instead of 1.5 s (the replay hands over 100 ms chunks, so a hop is a whole number of chunks)

* Commit latency reduction (wall): median 10.0% [2.6%, 16.9%] (randomization p 0.0003), p90 15.6% [-11.3%, 36.0%] (p 0.0507), p95 15.1% [-7.1%, 32.7%] (p 0.0389). Audio-clock median 9.6%; anchored on the reference segment ends 5.2%. Faster on 3 of 3 clips: fleurs-lf1 18.6%, liva-a 2.3%, ami-a 8.4%
* By corpus (median): ami 8.4% [-2.4%, 18.2%], fleurs 18.6% [-9.3%, 39.4%], liva 2.3% [-2.1%, 6.4%]
* Variant minus control, per block: WER -0.46 points [-2.69, +1.76], p 0.682 (Holm p 0.987); deletion rate +0.38 points [-2.19, +2.95], p 0.329; missing-speech share +0.41 points [-2.01, +2.83], p 0.360; omitted turns +1.91 points [-2.46, +6.29], p 0.152.
* Also, variant minus control per block: forced commits -2.61, dropped hops +4.72, empty hypotheses +2.83, repeat excess -1.00, ghost words +1.06, CPU -0.08 s per audio minute, infer RTF +0.032, decodes/min +4.9, mean window -828 ms. Finalization latency median 1,346 ms against 1,350 ms.
* Critical hallucinations 9 against a control mean of 10.0; ghost words 14 against 4.5.
* Without the 2 shared blocks: median reduction 10.4% (p 0.0011), every gate does not pass.
* Gates: latency FAIL, wer PASS, missingSpeech FAIL, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### ADA: hop scheduling. the hop tracks the last decode (1.5x, between 1.0 and 1.5 s)

* Commit latency reduction (wall): median 17.1% [6.5%, 26.4%] (randomization p 0.0003), p90 18.2% [-1.6%, 34.1%] (p 0.0094), p95 10.8% [-6.5%, 25.2%] (p 0.0642). Audio-clock median 17.0%; anchored on the reference segment ends 18.7%. Faster on 3 of 3 clips: fleurs-lf1 23.3%, liva-a 1.7%, ami-a 24.3%
* By corpus (median): ami 24.3% [19.4%, 29.0%], fleurs 23.3% [-19.0%, 50.6%], liva 1.7% [-0.4%, 3.7%]
* Variant minus control, per block: WER -0.27 points [-2.21, +1.68], p 0.584 (Holm p 0.793); deletion rate +1.04 points [-3.92, +6.00], p 0.264; missing-speech share +0.64 points [-1.57, +2.85], p 0.397; omitted turns +1.73 points [-1.80, +5.26], p 0.185.
* Also, variant minus control per block: forced commits -0.61, dropped hops +0.83, empty hypotheses +1.94, repeat excess -0.50, ghost words +0.28, CPU -0.47 s per audio minute, infer RTF +0.033, decodes/min +7.9, mean window -1124 ms. Finalization latency median 1,234 ms against 1,350 ms.
* Critical hallucinations 9 against a control mean of 10.0; ghost words 7 against 4.5.
* Without the 2 shared blocks: median reduction 17.6% (p 0.0011), every gate does not pass.
* Gates: latency FAIL, wer PASS, missingSpeech FAIL, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**

### CTX: forced commits. the active region is capped at 12 s, so a stalled window is forced sooner

* Commit latency reduction (wall): median 8.2% [-3.2%, 18.3%] (randomization p 0.0290), p90 18.2% [0.2%, 32.9%] (p 0.0028), p95 18.2% [3.2%, 30.9%] (p 0.0022). Audio-clock median 7.5%; anchored on the reference segment ends -6.8%. Faster on 1 of 3 clips: fleurs-lf1 -1.1%, liva-a 24.1%, ami-a -1.0%
* By corpus (median): ami -1.0% [-17.3%, 13.1%], fleurs -1.1% [-10.3%, 7.3%], liva 24.1% [8.8%, 36.9%]
* Variant minus control, per block: WER +0.82 points [-5.13, +6.77], p 0.306 (Holm p 0.865); deletion rate +1.58 points [-2.14, +5.31], p 0.140; missing-speech share +0.84 points [-2.81, +4.49], p 0.288; omitted turns +1.18 points [-2.70, +5.07], p 0.302.
* Also, variant minus control per block: forced commits -2.83, dropped hops -4.94, empty hypotheses +0.83, repeat excess +0.33, ghost words -0.50, CPU -1.08 s per audio minute, infer RTF -0.026, decodes/min +1.8, mean window -1037 ms. Finalization latency median 1,348 ms against 1,350 ms.
* Critical hallucinations 16 against a control mean of 10.0; ghost words 0 against 4.5.
* Without the 2 shared blocks: median reduction 7.7% (p 0.0784), every gate does not pass.
* Gates: latency FAIL, wer FAIL, missingSpeech FAIL, hallucinations FAIL, immutability PASS, droppedHops PASS, failures PASS, session_valid PASS, uncontended FAIL -> **not all pass**
