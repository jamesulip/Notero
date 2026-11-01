# Regression report

- Suite: `quick`; base `addf5f8 Merge pull request #8 from jamesulip/microphone-test`, candidate `57dcc14 Use the BSD time wrapper only on macOS in the benchmark har...`; interleave `abba` (20261031T193618Z).
- Machine: Mac14,12 / Apple M2 Pro / 16 GB / macOS 26.6.2; model `openai_whisper-large-v3-v20240930_turbo`; date 2026-10-31T19:36:18+00:00.
- Bench lock: used.
- Collapse rule: a run is COLLAPSED if its WER is more than 15 points above the reference level (the median of the best half, the ceil(n/2) lowest, of the runs judged, pooled over both arms of a comparison), or if it produced fewer than 75% of the reference's words, or if it contains an invented-filler phrase the reference lacks.
- Decision rule: n ≥ 8 per arm interleaved; rank-sum permutation test per metric; Holm over all 13 tested metrics (α = 0.05); effect-size floors; timing believed only on a quiet, balanced machine (median load ≤ 2, arms within 1); one session only SUSPECTS, a reproduced second session CONFIRMS.

## Verdict

INCOMPLETE (der-quick: ms-two-distinct: no successful runs on one side; der-quick: ms-three-voices: no successful runs on one side): this verdict covers only what ran. SUSPECTED IMPROVEMENT in offline-synthetic:WER; a single session cannot confirm: repeat it in a second interleaved session (`regress.py --confirm-with THIS_REPORT.json`) before acting; INDICATIVE ONLY, not believed (machine not quiet or load not recorded): offline-synthetic:RTF (improvement).

> WARNING: series live-synthetic: commit latency median is reported by only one build (missing in the base); not tested

## Series

### offline-synthetic (offline)

Base `addf5f8 Merge pull request #8 from jamesulip/microphone-test` n = 8; candidate `57dcc14 Use the BSD time wrapper only on macOS in the benchmark har...` n = 8.
Audio `synthetic-taglish` sha256 `e858bd6a1da5`, reference 128 words (SYNTHETIC).

| metric | base median [min..max] | cand median [min..max] | cand − base | p (rank sum) | p (Holm) | status |
| --- | --- | --- | ---: | ---: | ---: | --- |
| WER | 34.4% [30.5%..58.6%] | 24.2% [24.2%..24.2%] | -10.2 pt | <0.001 | 0.002 | **IMPROVEMENT (suspected)** |
| words (normalized) | 120 [83..122] | 120 [120..120] | +0 (+0%) | 0.610 | 1.000 | not significant |
| RTF | 0.092 [0.090..0.129] | 0.083 [0.083..0.084] | -0.0094 (-10%) | <0.001 | 0.002 | indicative only (load) (improvement; the machine was busy: median load average 6.4 (A) and 6.4 (B) against a limit of 2) |
| decodeMs | 5236 ms [5088 ms..7287 ms] | 4704 ms [4689 ms..4778 ms] | -532 ms (-10%) | <0.001 | — | not tested |
| collapsed runs | 3/8 | 0/8 | -3 runs | 0.200 | 1.000 | not significant |

Collapsed runs (level 24.2% WER, threshold 39.2%, word floor 96): base 3 [3, 5, 8], cand 0 [].
Why: A#3 filler; A#5 wer; A#8 wer+words+filler.
- load average (1 min) at launch, median / max: base 6.37 / 8.30, cand 6.37 / 7.29 — NOT reliable: the machine was busy: median load average 6.4 (A) and 6.4 (B) against a limit of 2
- before: uptime load [6.45, 8.53, 7.97], memory free 64%, pageouts 628369, compressor pages 259918
- after: uptime load [6.27, 5.61, 5.35], memory free 65%, pageouts 629809, compressor pages 253100
- pageouts during the series: 1440

### live-synthetic (live)

Base `addf5f8 Merge pull request #8 from jamesulip/microphone-test` n = 8; candidate `57dcc14 Use the BSD time wrapper only on macOS in the benchmark har...` n = 8.
Audio `synthetic-taglish` sha256 `e858bd6a1da5`, reference 128 words (SYNTHETIC).

| metric | base median [min..max] | cand median [min..max] | cand − base | p (rank sum) | p (Holm) | status |
| --- | --- | --- | ---: | ---: | ---: | --- |
| WER | 28.1% [25.8%..32.8%] | 26.2% [22.7%..30.5%] | -2.0 pt | 0.124 | 1.000 | not significant |
| words (normalized) | 120 [115..124] | 118 [115..125] | -1.5 (-1%) | 0.331 | 1.000 | not significant |
| RTF | 0.958 [0.821..1.054] | 1.007 [0.949..1.074] | +0.0482 (+5%) | 0.234 | 1.000 | not significant |
| decodeMs | 54270 ms [46501 ms..59687 ms] | 57000 ms [53730 ms..60812 ms] | +2730 ms (+5%) | 0.234 | — | not tested |
| dropped hops | 0 [0..0] | 0 [0..0] | +0 | 1.000 | 1.000 | not significant |
| forced commits | 5.500 [0..11] | 6.500 [0..11] | +1 (+18%) | 0.354 | 1.000 | not significant |
| unagreed tail words | 17.500 [5..37] | 15.500 [3..37] | -2 (-11%) | 0.812 | 1.000 | not significant |
| mean per-decode RTF | 0.127 [0.114..0.165] | 0.121 [0.115..0.159] | -0.00586 (-5%) | 0.382 | 1.000 | not significant |
| infer ms per hop | 1424 ms [1220 ms..1567 ms] | 1496 ms [1410 ms..1596 ms] | +72 ms (+5%) | 0.234 | 1.000 | not significant |
| collapsed runs | 0/8 | 0/8 | +0 runs | 1.000 | 1.000 | not significant |

Collapsed runs (level 25.8% WER, threshold 40.8%, word floor 96): base 0 [], cand 0 [].
Not tested, reported by only one build: commit latency median (missing in the base).
- load average (1 min) at launch, median / max: base 1.21 / 2.46, cand 1.18 / 2.52 — quiet and balanced
- before: uptime load [2.01, 4.96, 5.62], memory free 65%, pageouts 727324, compressor pages 250994
- after: uptime load [4.02, 2.72, 2.48], memory free 66%, pageouts 987488, compressor pages 240961
- pageouts during the series: 260164

### Diarization (DER, synthetic fixtures)

DER of the raw diarizer spans against the synthetic RTTM, collar 0.25 s (`der.py`). SYNTHETIC text-to-speech clips with exact boundaries: this supports A/B between two builds, not a claim about real meetings. Not part of the Holm family; a change is reported at 2 points or more.

| fixture | base DER per round | cand DER per round | cand − base (median) | deterministic | status |
| --- | --- | --- | ---: | --- | --- |
| ms-two-distinct |  |  | +0.0 pt | NO | no successful runs on one side |
| ms-three-voices |  |  | +0.0 pt | NO | no successful runs on one side |

### Determinism of `base addf5f8 Merge pull request #8 from jamesulip/microphone-test / offline-synthetic`

8 runs of one binary on one file: **NOT identical: 8 distinct transcripts** (groups of [1, 1, 1, 1, 1, 1, 1, 1]).
First divergence: run 1 vs run 2 at word 0 (≈ 0 ms), window unknown (this binary's report lists no windows): `Kalo na pagi` vs `Kumusta kayong lahit?`.

### Determinism of `candidate 57dcc14 Use the BSD time wrapper only on macOS in the benchmark har... / offline-synthetic`

8 runs of one binary on one file: **byte-identical** (groups of [8]).

### Determinism of `base addf5f8 Merge pull request #8 from jamesulip/microphone-test / live-synthetic`

8 runs of one binary on one file: **NOT identical: 8 distinct transcripts** (groups of [1, 1, 1, 1, 1, 1, 1, 1]).
First divergence: run 1 vs run 2 at word 3 (≈ 1180 ms), window unknown (this binary's report lists no windows): `Kumusta kayong lah at? Welcome sa` vs `Kumusta kayong lah at. Welcome sa`.

### Determinism of `candidate 57dcc14 Use the BSD time wrapper only on macOS in the benchmark har... / live-synthetic`

8 runs of one binary on one file: **NOT identical: 8 distinct transcripts** (groups of [1, 1, 1, 1, 1, 1, 1, 1]).
First divergence: run 1 vs run 2 at word 0 (≈ 0 ms), window unknown (this binary's report lists no windows): `Kumusta kayong Welcome` vs `I'm kayong Welcome`.


Everything above was measured on SYNTHETIC audio unless a series says otherwise; it supports an A/B statement about two builds, not a claim about real meetings or real Taglish. "Not significant" is never "equivalent".
