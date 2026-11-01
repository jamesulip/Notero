# Tier comparison: Fast, Balanced and Best, 2026-11-02

**Decision: keep Balanced as the default.** No tier met the decision gate on either corpus.
Validation on real meetings is **blocked**: no public, permissively licensed corpus of
conversational Taglish meetings exists (see [Data](#data)), and no consented meeting recordings
were available.

This file keeps three kinds of statement apart:

- **Measured:** computed in this run, from files listed under [Reproduce](#reproduce).
- **Published:** a claim by a data publisher or a model vendor. This project did not check it.
- **Inference:** a reading of the measurements. It can be wrong.

## Conditions (measured)

| | |
| --- | --- |
| Commit | `5f34fbc` (`main` at `8c47d2c` plus the evaluation framework, PR #14) |
| Binary | `transcribe` release build, SHA-256 `0eb68b4cac0e9947…` |
| Machine | Mac mini M2 Pro (Mac14,12), 16 GB, macOS 26.6.2: the hardware the app targets. No other Mac was measured. |
| Tiers | Fast `openai_whisper-large-v3-v20240930_626MB`, Balanced `openai_whisper-large-v3-v20240930_turbo`, Best `openai_whisper-large-v3_turbo`. All three folders record Hugging Face commit `0f63a7800b00…` of `argmaxinc/whisperkit-coreml`. |
| Decode | `transcribe --tier T --language tl --no-diarize`, offline path, identical for every tier. Interleaved: a seeded rotation of the tier order for each item. Each decode under the bench lock. |
| Scoring | `transcribe --score`, configuration `eval/evaluation-config.v1.json`, policy `notero-standard` (the rules of `eval/score.py`). Paired, stratified percentile bootstrap, 2000 resamples, seed 20261102. |
| Gate | Fixed in each `plan.json` before the first decode: at least 10% relative WER improvement over Balanced, a 95% interval of the difference below zero, a live-capable tier, a median whole-file RTF of 0.6 or less, a model residency of 3,500 MB or less, and no more failed decodes than Balanced. |

**The gate was made stricter after the decodes, and only stricter.** The independent verification
found cases where the first version would have passed a tier on incomplete data. The added checks
are: every item scored, residency measured on every item, no failure hidden behind exit code 0,
no decision without the decode log, and stability across decodes (below). A stricter gate cannot
turn "keep" into "change", and the decision is "keep" under both versions.

## Data

| Corpus | Speech | Size | Licence | Used |
| --- | --- | --- | --- | --- |
| FLEURS `fil_ph` test (Google) | Read Wikipedia-style sentences, Tagalog with English names and loanwords. Not code-switched, not conversational. | 349 recordings, one for each sentence, 104.5 min, 9,613 reference words | CC-BY-4.0 (published). Tarball SHA-256 matches the published `eb8349c6…` (measured). | Yes |
| Liva AI `en-tl` sample | **Conversational Taglish**: one group of friends in a voice chat while gaming, mixed to one track, 4–5 speakers in each file. | 4 × 10 min, 1,245 utterances, 5,537 reference words | CC-BY-4.0 in the dataset card at revision `51b5d0b` (published, read 2026-11-02). Each WAV matches the published LFS SHA-256 (measured). Attribution: Liva AI, Code-Switching ASR. | Yes, as a smoke test |
| FilSwitch (DLSU authors) | Read Philippine news in Taglish, 152 speakers, 2.04 h speaker-disjoint test split (published) | — | **No licence stated.** | **No.** Blocked until the authors grant permission. It is the best public Taglish test set found. |
| Others | Common Voice has no `tl` audio; Babel Tagalog is paid telephone speech; the rest are non-commercial, research-only or have no rights. | — | — | No |

Caveats (measured or published, as marked):

- FLEURS labels all 964 `fil_ph` test recordings MALE and publishes no speaker IDs (published). Speaker diversity cannot be counted.
- Nothing here is trained. Whisper's training data is not published. OpenAI reports FLEURS as a Whisper evaluation set (published, not checked).
- The Liva references are vendor transcripts, "AI-generated and then human reviewed, or fully human generated" (published). Event tags such as `[laughing]` were removed before scoring. One friend group only: **a smoke test, not a benchmark.**

## Results (measured)

### FLEURS `fil_ph`, read Tagalog

| Tier | WER (95% CI) | CER | S / D / I | Median whole-file RTF | Median load | Model residency | Process peak footprint |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: |
| Fast | 12.16% (11.18–13.22) | 3.86% | 900 / 120 / 149 | 0.086 | 2.0 s | 878 MB | 96 MB |
| **Balanced** | **11.66% (10.73–12.64)** | **3.64%** | 869 / 123 / 129 | **0.067** | 1.9 s | 1,580 MB | 133 MB |
| Best | 11.35% (10.41–12.34) | 3.45% | 842 / 124 / 125 | 0.247 | 2.2 s | 3,000 MB | 184 MB |

| Against Balanced | Difference | 95% interval | Relative | Items better / worse / tied | Gate |
| --- | ---: | --- | ---: | --- | --- |
| Best | −0.31 pt | −0.97 to +0.34 | 2.7% better | 96 / 77 / 176 | **No**: under 10%, interval contains 0, not live-capable |
| Fast | +0.50 pt | −0.01 to +1.00 | 4.3% worse | 45 / 75 / 229 (sign test p = 0.008) | **No**: worse |

- 1,107 of 1,107 decodes succeeded. No window was dropped.
- 20 items were decoded twice on each tier, and **20 of 20 transcripts were identical on every tier**: offline decoding of these short read clips is deterministic.
- Best's worst item is `fleurs-1852` (63 words, +27 points against Balanced). Earlier, FINDINGS entry 25 recorded Best failing on one long utterance.

### Liva AI `en-tl`, conversational Taglish

| Tier | WER, pass 1 (95% CI) | WER, pass 2 | CER, pass 1 | Median whole-file RTF | Model residency |
| --- | --- | ---: | ---: | ---: | ---: |
| Fast | 70.49% (68.43–72.49) | 68.99% | 56.68% | 0.258 | 878 MB |
| **Balanced** | **68.34% (66.26–70.47)** | **69.59%** | **53.83%** | **0.153** | 1,580 MB |
| Best | 64.80% (62.52–67.22) | 65.61% | 50.61% | 0.606 | 3,000 MB |

| Against Balanced | Pass 1 | Pass 2 | Relative (pass 1 / 2) | Gate |
| --- | ---: | ---: | --- | --- |
| Best | −3.54 pt (−5.49 to −1.36) | −3.97 pt | 5.2% / 5.7% better | **No**: under 10%, not live-capable, RTF 0.606 > 0.6 |
| Fast | +2.15 pt (+0.64 to +3.60) | −0.60 pt | worse / 0.9% better | **No** |

- **No Liva transcript was identical between its two decodes, on any tier.** Single files moved by up to 9 points. The 95% intervals resample utterances of one decode and do not include this variation. Do not read them as the uncertainty of a tier difference.
- The pass-1 result "Fast is significantly worse" did not repeat in pass 2.
- Best's advantage did repeat: in 92.6% of the utterances where both passes show a difference, its sign is the same.
- The gate's `stableAcrossDecodes` check fails for both tiers here.

### Error analysis of the Liva sample (measured unless marked)

- **The voice detector loses nothing.** 2 of 5,537 reference words fall outside a decode window.
- **The model writes at most one speaker when two talk at once.** In 175 pairs of strongly overlapping utterances, both were transcribed in 1–2% of pairs.
  - WER rises from 60% on utterances without overlap to 90% on utterances that are 75% or more overlapped.
  - Overlap accounts for about 8 points of the corpus WER.
- **Clean speech is still hard.** Utterances without overlap score 58–63%. Two of the speakers score 72–86% even without overlap.
- **Spelling is not the problem.** Spelling-only substitutions ("jan"/"diyan") are 1.5–3.3% of substitutions. A sensitivity recount with an equivalence list lowers WER by 1.0–1.5 points on every tier.
- **No translation into English was found.** The utterances whose hypothesis is English where the reference is Tagalog are repetition loops.
- **Code-switch points are not worse** than other words. This uses the heuristic word classes of `eval/langscore.py`, not ground truth.
- **Repetition loops are the main hallucination.** For example, "hello" written 30–182 times where it was said 11 times. Stock Whisper phrases are almost absent.
  - Loops hold 4.7–9.3% of hypothesis tokens.
  - One loop window holds 72 of Best's 195 errors that changed between passes.
- **Best's gain is fewer substitutions,** and it is larger on Tagalog-classed words (−5 points) than on English-classed words (−2 points, heuristic). Best also makes longer loops (up to 102 inserted words).

## Decision (inference from the measurements above)

1. **Keep Balanced.**
   - Nothing beats it by 10% on either corpus.
   - On read Tagalog the three tiers are within about half a point.
   - Best is better on conversational Taglish by about 4 points (5–6% relative) in both passes. That is not enough for the gate, and Best cannot be the default: it cannot keep up with live transcription, and on the conversational audio it ran at 0.61 of real time.
2. **Fast has no advantage except memory.**
   - It is slower than Balanced on this M2 Pro (median RTF 0.086 against 0.067, and 0.258 against 0.153).
   - It is slightly less accurate on read Tagalog: 4.3% relative, interval just reaching 0, sign test p = 0.008.
   - It uses 878 MB of Neural Engine memory against 1,580 MB.
3. **Best is a reasonable choice for a second pass of a finished conversational recording,** where its speed is not a problem. That is the use the app already gives it. This is an inference from a 40-minute sample of one group, and it is not a measured claim about meetings.
4. **Accuracy on conversational Taglish is the gap, not the tier.** About 65–70% WER on the voice-chat sample, against about 11–12% on read Tagalog. The causes are crosstalk and noisy, informal speech, which no tier fixes. **This is a voice chat between friends, not a meeting.** Real meeting accuracy is unmeasured.

## Not measured

- Real meetings, far-field rooms, two-lane recordings (validation blocked: no data).
- FilSwitch (no licence).
- The live path: these are offline decodes. The live suitability of each tier comes from `ModelTier.suitableForLive` and earlier measurements.
- Any Mac other than this M2 Pro. No M5 or other result is claimed.

## Reproduce

Data stays in `/tmp/notero-data/` and does not go into git. Compact copies of the plans, the decisions and the
Markdown reports are in [`baselines/tiers-2026-11-02/`](baselines/tiers-2026-11-02/).

```bash
cd app && swift build -c release --product transcribe && cd ..
# FLEURS (fetch once with eval/fleurs_eval.py fetch)
python3 -I eval/tier_benchmark.py fleurs-manifest --src /tmp/notero-data/fleurs --work /tmp/notero-data/tiers/fleurs --seed 7
python3 -I eval/tier_benchmark.py plan --manifest /tmp/notero-data/tiers/fleurs/manifest.json \
    --bin app/.build/release/transcribe --out /tmp/notero-data/tiers/run1 --repeat-subset 20
# Liva AI en-tl
python3 -I eval/tier_benchmark.py liva-fetch --src /tmp/notero-data/liva-src
python3 -I eval/tier_benchmark.py liva-manifest --src /tmp/notero-data/liva-src --work /tmp/notero-data/tiers/liva
python3 -I eval/tier_benchmark.py plan --manifest /tmp/notero-data/tiers/liva/manifest.json \
    --bin app/.build/release/transcribe --out /tmp/notero-data/tiers/liva-run1 --repeat-subset 4
# For each plan:
python3 -I eval/tier_benchmark.py decode --plan PLAN   # resumable
python3 -I eval/tier_benchmark.py score  --plan PLAN
python3 -I eval/tier_benchmark.py decide --plan PLAN
```

FLEURS took about 2.5 hours on the M2 Pro and Liva about 1 hour; they shared the bench lock.
The verification recomputed every FLEURS figure and the Liva Fast and Balanced figures exactly
with `eval/score.py`. Liva Best differs by 0.07 points: two backticks ("Don`t") that this
framework counts as an apostrophe and `score.py` does not.
