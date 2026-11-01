# Real-voice results on FLEURS Filipino (read Tagalog), 2026-11-01

**What this is.** Read Tagalog speech by real people, scored against human references. **What it
is not.** Taglish, a meeting, a far-field room, overlapping speakers, or anything with
code-switching beyond English names and loanwords inside Tagalog sentences. Every number is
about *read Tagalog sentences*. Do not quote one as the accuracy of the app on meetings.

Raw runs (JSON and stderr of every decode): `/tmp/notero-data/fleurs-eval/decode/` (not in git).
Reproduce with `eval/fleurs_eval.py`; commands at the end.

## Conditions

| | |
|---|---|
| Data | FLEURS `fil_ph` test split, CC-BY-4.0, Hugging Face `google/fleurs` at commit `70bb2e8…`. 964 recordings of 349 sentences. Tarball SHA-256 `eb8349c6…` (889,243,315 bytes), verified against the hash Hugging Face publishes. |
| Subset | 100 utterances, one recording per sentence, ordered by a seeded hash (seed 7): 2,838 reference words (score.py tokenization), 30.8 min. |
| Long-form | Constructed: consecutive sentence ids joined with seeded 0.3-1.5 s gaps of digital silence. Each sentence is a separate recording, so the voice and the room can change at every join. lf1 193 s (9 parts), lf2 250 s (11), lf3 330 s (21). Not a meeting. |
| Reference | FLEURS `raw_transcription` through `score.normalize` (lower case, punctuation dropped, hyphen splits a word). FLEURS's own `transcription` column gave the same WER (11.1%). |
| Machine | Mac mini M2 Pro (Mac14,12), 16 GB, macOS 26.6.2, release builds, every decode through `/tmp/notero-team/bench-lock.sh`, in holds of 3 to about 160 decodes with the arms interleaved inside a hold. The queue was up to 12 deep, so the series ran from 02:57 to 10:21 local time. |
| Binaries | P6: this branch at 57dcc14, `transcribe` SHA-256 `b39eb39d…`. Base: `git archive addf5f8`, SHA-256 `278f771c…`. |
| Settings | Balanced tier, `--language tl`, `--no-diarize`, unless the row says otherwise. |
| Load | 1-minute load average at launch, per decode, recorded in the raw JSON: median 2.1 (1.1-13.2) for the P6 subset runs and 2.0 (1.1-13.6) for base; 1.9 (0.8-4.0) and 1.8 (0.7-3.4) for the long-form runs. Other agents built and tested without the lock throughout. |

## Run-to-run variance (measured first)

20 utterances, each decoded twice by each build (80 decodes): **0 of 20 produced different text
between repeats, for both builds.** Long-form lf2 and lf3: 8 runs per build per file, **one
distinct transcript per build per file.** Offline decoding of these recordings is deterministic.
No Balanced decode collapsed: the worst single utterance is 33.3% WER (90th percentile 21.6%)
and no transcript is empty.

## (a) P6 (greedy-first, lead-in) against shipping `addf5f8`, Balanced

| Set | n | Reference words | WER base / P6 | Transcripts byte-identical | Windows retried / empty |
|---|---:|---:|---|---:|---|
| Subset | 100 | 2,838 | 11.1% / 11.1% (95% CI 9.6-12.6%) | **100 of 100** | 0 / 0 both |
| Abrupt start (leading silence cut away, median 0.13 s, max 1.78 s) | 40 | 1,154 | 10.7% / 10.7% | **40 of 40** | 0 / 0 both |
| Long-form lf2, 250 s, 10 windows | 8 per arm | 341 | 8.3% / 8.3% | identical, every run | 0 / 0 |
| Long-form lf3, 330 s, 14 windows | 8 per arm | 477 | 13.1% / 13.1% | identical, every run | 0 / 0 |

CER 3.7% (subset). **P6 does nothing on these real voices, in either direction.** The greedy
decode is not refused at the first token on any of 140 utterances or 32 long-form decodes, so the
lead-in path never ran. It also did not regress anything. This does not show that P6 helps on a
recording that starts abruptly at full amplitude: FLEURS recordings already start within a
median of 0.13 s of speech, and cutting that off did not trigger a refusal either.

## (b) Forced `tl` against `auto`, Balanced, interleaved, n = 40 utterances (1,154 words)

| | WER | CER | Filipino-word errors | Median RTF (range) | Load |
|---|---:|---:|---:|---|---|
| forced `tl` | 10.7% | 3.5% | 8.9% | 0.066 (0.046-0.133) | 2.1 |
| `auto` | 10.7% | 3.5% | 8.9% | 0.066 (0.048-0.137) | 2.2 |

**Byte-identical transcripts on 40 of 40.** `auto` reported `tl` for 38 utterances, `en` for 2, and
`id` for one window of a two-window utterance, and still wrote the same Tagalog text. Why a
reported `en` does not change the text is not explained (hypothesis, unchecked: in WhisperKit
1.1.0 the language reported by the detection pass is not the language the decode used). On pure
read Tagalog `auto` is neither better nor worse, and costs no measurable extra time. This says
nothing about Taglish: the earlier failure of `auto` (FINDINGS 11) was an Indonesian voice
reading Taglish, and the risk there is a window of mostly English or mixed speech detected as
another language. FLEURS cannot test that.

## (c) Model tiers, first 30 utterances (873 words), read Tagalog

| Tier | WER | CER | WER without u1852 (29 utt.) | Median RTF (range) | Load (median) |
|---|---:|---:|---:|---|---|
| Fast (626 MB) | 9.3% | 3.2% | 9.4% | 0.081 (0.057-0.177) | 1.9 |
| Balanced (default) | 9.7% | 3.3% | 9.75% | 0.065 (0.047-0.132) | 4.6 |
| Best (full large-v3) | **15.5%** | 8.0% | 10.0% | 0.254 (0.175-0.597) | 1.7 |

Fast against Balanced: -0.46 points (95% CI -1.4 to +0.4, paired, resampling utterances), 4 versus 3
utterances better, 16 of 30 transcripts identical. Fast was **not faster** on this Mac: its RTF is
higher. Balanced's runs were not interleaved with the tier runs, and it ran under heavier load, so the
speed ratio is indicative. Best against Balanced excluding u1852: +0.25 points (CI -1.5 to +2.0): no
measurable gain, at about four times the decode time.

**Best collapsed on one utterance, u1852 (34.7 s, two windows, 63 reference words).** Balanced
decodes it at 9.5% WER with 66 words; Fast gives 65 words. Best, repeated: **WER 85.7%, 54.0%,
52.4%, 50.8% (P6 binary) and 73.0%, 41.3%, 34.9%, 30.2% (base binary), 8 of 8 decodes failed**:
the first window comes back as mangled words ("Ang tamam paggamitan ng mula-mula ay maaaring
magbigaya sa mababalik…") and 20 to 75 words come back instead of 63. No window is reported empty
or retried. The text differs between runs, so the sampled fallback is involved; P6 against base on
this one utterance is not distinguishable (permutation p = 0.34, n = 4 per arm). The default tier
is unaffected on all 100 utterances.

## (d) Long-form against the same sentences decoded one at a time (P6)

| File | Long-form WER | Same sentences, one by one | Windows | Retried / empty |
|---|---:|---:|---:|---|
| lf2 | 8.3% | 8.0% | 10 | 0 / 0 |
| lf3 | 13.1% | 13.7% | 14 | 0 / 0 |

Joining sentences with 0.3-1.5 s gaps and decoding through the VAD and window path costs no
accuracy against decoding each sentence alone, on this constructed material. lf1 (193 s) was not
run: the shared lock queue was hours deep and two files already show the path.

## (e) Code-switch evidence, and what it can and cannot say

The 100 references hold 192 tokens that `langscore` classes as English, 6.9% of its 2,793 words.
**Most are not English.** Words such as `pa`, `iba`, `tubig`, `pang`, `halos` are Tagalog words
that are also in the macOS English word list. After removing 58 such tokens by hand
(`eval/fleurs_tagalog_collisions.txt`, one author's judgement, a native reader should check it) 134
remain (4.8% of the 2,793 words `langscore` counts): English words and technical terms (`hydrogen`, `proton`, `design`, `hockey`) and
foreign proper names (`Greenland`, `Canada`, `Trump`, `Pohutukawa`), read inside Tagalog sentences.

| Class (P6, 100 utterances) | Reference tokens | Error rate |
|---|---:|---:|
| Filipino words | 2,571 | 9.9% (254 errors) |
| English per langscore | 192 | 14.1% (27 errors) |
| English after the audit | 134 | 17.9% (24 errors) |
| Code-switch points | 277 | 11.2% (31 errors) |

The English-token error rate is **17.9% of 134 tokens, 24 errors**. At that size the
interval is wide (Wilson 12 to 25%, wider with clustering), and the tokens are
names and technical terms, not the everyday English a speaker mixes into a Tagalog sentence. Treat
it as a hint that names and foreign terms are harder than ordinary words, not as a measurement of
code-switching accuracy. **A real Taglish number needs `REAL-TAGLISH-PROTOCOL.md`.**

## Commands

```bash
python3 -I eval/fleurs_eval.py fetch    --src /tmp/notero-data/fleurs
python3 -I eval/fleurs_eval.py prepare  --src /tmp/notero-data/fleurs --work /tmp/notero-data/fleurs-eval \
    --subset 100 --seed 7 --longform-seconds 165 245 325
python3 -I eval/fleurs_eval.py add-abrupt --work /tmp/notero-data/fleurs-eval --n 40
python3 -I eval/fleurs_eval.py decode   --work /tmp/notero-data/fleurs-eval --set subset --lock-batch 40 \
    --arm "p6|app/.build/release/transcribe" --arm "base|/tmp/taglish-base/app/.build/release/transcribe"
python3 -I eval/fleurs_eval.py score    --work /tmp/notero-data/fleurs-eval --set subset --arm p6 --arm base
python3 -I eval/fleurs_eval.py compare  --work /tmp/notero-data/fleurs-eval --set subset --a base --b p6
python3 -I eval/fleurs_eval.py longform --work /tmp/notero-data/fleurs-eval --arm p6
```
