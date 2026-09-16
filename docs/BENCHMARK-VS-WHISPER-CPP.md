# Benchmark: this app (WhisperKit) against the Tauri Notero (whisper.cpp)

The Tauri rewrite of Notero runs whisper.cpp on Metal. This app runs the same
OpenAI weights through WhisperKit on the Neural Engine. This page gives the same
audio to both, and scores the results with one script.

Dates: 2026-09-13 to 2026-09-15. Machine: Apple M5 Pro, macOS 26.6.2.
The short summary is [FINDINGS.md §14](FINDINGS.md#14-the-same-audio-through-whisperkit-and-whispercpp-2026-09-14).

## Fixtures and their sources

This repository holds no audio. Each fixture has a source that you can fetch or
rebuild.

| Fixture | Length | Content | Source |
| --- | --- | --- | --- |
| `M_1017_11y8m_1` | 2:29 | A boy of 11y8m. He stutters. He speaks about school. | UCLASS. `eval/get-uclass.sh` fetches it. **It has a human reference.** |
| `F_1211_11y3m_1` | 2:57 | A girl of 11y3m. She stutters. An interview. | UCLASS. No human reference exists for this file. |
| Tagalog vlog clip | 0:34 | Fast Tagalog speech. | A public clip. Coverage only, because it has no reference. |
| Taglish meeting | 0:48 | A recorded meeting. | Local. Not public. Qualitative use only. |

**All audio here is a real recording.** This page had a set of 8 sentences from
the macOS `say` command. That set is removed. Synthetic speech measures the
voice, and not the model. [FINDINGS.md](FINDINGS.md) records the same problem
with an earlier Taglish fixture, which used an Indonesian voice.

Three more UCLASS monologues carry a human transcript: `M_1017_13y2m_1`,
`M_0017_19y2m_1` and `M_0065_20y1m_1`. `eval/get-uclass.sh` fetches them. The
Limits section says why this page does not score them yet.

**About UCLASS.** UCLASS is the UCL Archive of Stuttered Speech. It is free for
research and for teaching. Two conditions apply to all use of it:

1. You must acknowledge the source of the data.
2. You must state that the Wellcome Trust supported the data collection.

UCL removes names and postcodes from the audio. The speaker identifiers are the
archive's own anonymous labels.

**Why speech with a stutter.** Notero must transcribe real meetings. Real speech
has repetitions, false starts and filled pauses. This is also the point where
speech systems differ most, and where they differ by *convention* and not by
accuracy. A system that omits a repeated word is not always wrong.

## Systems

| Name | Model | Size | Backend |
| --- | --- | ---: | --- |
| Swift `small` | `openai_whisper-small` | 464 MB | WhisperKit, CoreML, Neural Engine |
| Swift `balanced` | `openai_whisper-large-v3-v20240930_turbo` | 1.5 GB | WhisperKit, CoreML, Neural Engine |
| Swift `best` | `openai_whisper-large-v3_turbo` | 3.2 GB | WhisperKit, CoreML, Neural Engine |
| Tauri `small` | `ggml-small` | 487 MB | whisper.cpp, Metal |
| Tauri `turbo` | `ggml-large-v3-turbo-q5_0` | 574 MB | whisper.cpp, Metal |
| Tauri `turbo` full | `ggml-large-v3-turbo` | 1.6 GB | whisper.cpp, Metal |
| Tauri `large-v3` | `ggml-large-v3` | 3.1 GB | whisper.cpp, Metal |

Swift `balanced` is the default tier of the app.

## The result with a human reference (2026-09-15)

`M_1017_11y8m_1` is the only fixture with a reference that this project did not
write. UCLASS supplies a time-aligned syllable transcript for it. This is the
one number here that nobody must take on trust.

The transcript gives two references:

- **Verbatim** — every token that the speaker produced. Filled pauses,
  repetitions and aborted words stay in.
- **Cleaned** — the same text without filled pauses, aborted words and immediate
  repetitions.

The pair separates a mishearing from a convention. `eval/uclass_score.py` builds
both and scores them. It applies three mechanical corrections:

1. It drops a reference token whose audio is silent. UCL removes names and
   postcodes from the wav, so no system can transcribe them.
2. It drops a hypothesis word inside a gap longer than 3 s between subject
   tokens. The wav holds the interviewer, and the transcript does not.
3. It fits a constant time offset from the words that both sides share. Some
   UCLASS transcripts are aligned to a master with a longer lead-in than the
   released wav. For this file the offset is -0.14 s from 121 shared words, and
   the median residual is 60 ms. The scorer fits the offset once, and it reuses
   the value for every model, so no model gets a timeline tuned to itself.

| `M_1017_11y8m_1` | Verbatim WER | Cleaned WER | Decode |
| --- | --- | --- | --- |
| Swift `small`, offline | 18.7% | 10.1% | 3.3 s |
| Swift `balanced`, offline | **16.3%** | **9.5%** | 4.4 s |
| Swift `balanced`, live at real time | 19.3% | 11.5% | 155.6 s |

Three results come out of this table.

**Most of the error on speech with a stutter is convention.** The default tier
scores 16.3% verbatim and 9.5% cleaned. Therefore 6.8 of the 16.3 points are
filled pauses and repetitions that the model omits. The model heard the speech.
It chose not to write the speech down. For a meeting transcript this choice is
correct, and a verbatim score punishes it.

**The gap between the models is small.** Against this reference, `small` and the
default tier are 0.6 points apart on the cleaned score. Against the `F_1211`
reference below, which this app wrote itself, the same two models are 7.5 points
apart. The reference caused most of that distance, and not the models. Prefer
the numbers on this page's first table.

**The live path costs 2.0 points**, and not the 6.6 points that `F_1211`
reported. The live run dropped 0 hops here. It dropped 3 hops on `F_1211`.

## The comparison against whisper.cpp

These numbers use the `F_1211` interview and the Tagalog clip.

> **Read the interview column with care.** The `F_1211` reference is a machine
> transcript from this app. It contains this app's own errors, such as "No, I'm
> a daddy". It also contains this app's own convention for a repeated word.
> Every other system pays for a difference from that convention. The measurement
> above puts this cost near 6 points. No fixture in this section has an exact
> reference. Read the section as a runtime comparison, where both sides carry
> the same handicap.

### Accuracy

| File | Reference | Tauri small | Tauri turbo | Swift |
| --- | --- | --- | --- | --- |
| `F_1211` interview (2:57) | this app's export (biased) | 30.6% | 18.3% | 8.4% |
| Tagalog vlog (0:34) | none; word count only | 78 words | 72 words | **25 offline / 75 live** |

### Speed, decode only, model warm

| File | Tauri small | Tauri turbo | Swift |
| --- | --- | --- | --- |
| Interview, 177.8 s | 6.8 s (26x) | 26.6 s (6.7x) | 8.7 s (20x) |
| Tagalog, 34.3 s | 0.9 s | 1.4 s | 1.9 s offline / 21 s live |

Model load: Tauri 6.0 s cold, then 0.3 s warm for `small` and 0.5 s for turbo q5.
A Swift CLI run of the interview took 17 s to 19 s in total. Approximately 9 s of
this is start-up. The start-up loads the CoreML model and the VAD model.

## The same model through two runtimes

Both runtimes ran `small` on the same files.

| File | WhisperKit small | whisper.cpp small, per utterance | whisper.cpp small, 28 s windows |
| --- | --- | --- | --- |
| Interview WER | 15.9% | 30.6% | 19.2% |
| Tagalog words | 69 | 78 | — |
| Interview decode | 9.1 s | 6.8 s | 2.5 s |

Both runtimes ran the large-v3-turbo class.

| | WhisperKit turbo | whisper.cpp turbo-q5, per utterance | whisper.cpp turbo-q5, 28 s windows |
| --- | --- | --- | --- |
| Interview WER | 8.4% | 18.3% | 12.9% |
| Interview decode | 8.7 s | 26.6 s | 5.1 s |

And the full-precision turbo weights:

| Interview | WER | Decode |
| --- | --- | --- |
| WhisperKit large-v3-turbo | 8.4% | 8.7 s |
| whisper.cpp large-v3-turbo, per utterance | 17.1% | 24.5 s |
| whisper.cpp large-v3-turbo, 28 s windows | 12.0% | 5.1 s |
| whisper.cpp large-v3-turbo-q5_0, 28 s windows | 12.9% | 5.1 s |

The 5-bit quantization costs approximately one WER point.

**What this says.** Hold the model constant, and approximately half of the
whisper.cpp gap comes from how it feeds the model. Whisper pads each input to
30 s. A reply of two seconds therefore gets 28 s of silence for context, and it
still costs a full encoder pass. Packed windows halve the errors and cut the
decode time by 3x to 5x, because the encoder runs 7 times and not 43 times. The
rest of the gap is the decoder settings, plus the biased reference.

**For the Tauri app.** Keep a commit for each utterance. That behaviour saved the
Tagalog clip and it keeps the latency low. But decode each new utterance with the
previous ~20 s of audio in front of it, and keep only the segments inside the new
utterance. The encoder cost does not change and the latency does not change.

## Live paths, same audio, same model

Each app replayed the interview at real time.

| Interview, large-v3-turbo | WER | Decodes | Note |
| --- | --- | --- | --- |
| Swift live path, 1.5 s hop, LocalAgreement | 15.0% | 116, 3 dropped, 10 abandoned | mean RTF 0.092 |
| Tauri live path, one decode per utterance | 17.1% | 42, none dropped | same text as its offline run |

LocalAgreement commits only the text that two hypotheses agree on. This costs
the Swift app 6.6 points against its own offline pass on `F_1211`, and 2.0 points
on `M_1017`. The Tauri live path equals its own offline pass by design. Its gain
from windowed context would therefore carry into live use.

## The full large-v3, the "Best" tier

| Interview, English | WER | Decode |
| --- | --- | --- |
| Swift, WhisperKit large-v3 | 12.6% | 24 s |
| Tauri, whisper.cpp large-v3, per utterance | 21.0% | 32.5 s |
| Tauri, whisper.cpp large-v3, 28 s windows | 11.4% | 12.2 s |
| Each app's large-v3-turbo | 8.4% Swift / 12.0% Tauri | 8.7 s / 5.1 s |

Both apps got **worse** with the full large-v3, and both got approximately three
times slower. On the Tagalog clip the full model kept 33 words (Tauri) and 31
words (Swift) of the 72 to 78 words that turbo produces. The 32-layer decoder
sends end-of-text early on fast Tagalog inside one utterance. Neither
segmentation prevents this. On the Taglish recording the Swift large-v3 pass
added "Thank you for watching! Thankyou" to the trailing silence. This is a known
large-v3 hallucination. The whisper.cpp pass did not add it.

**Keep large-v3-turbo as the default in both apps. The full large-v3 is not an
upgrade for Taglish.**

## Limits

1. **One machine, one run.** Every number comes from one M5 Pro. No number is a
   mean of repeated runs, so no number has a variance. The thermal state was not
   controlled.
2. **One speaker for each file.** Diarization is off in all runs.
3. **One fixture has an exact reference**: `M_1017_11y8m_1`. The `F_1211`
   reference is this app's own output. The Tagalog clip and the Taglish
   recording have no reference.
4. **`M_1017` covers the Swift side only.** The whisper.cpp runs use the older
   fixtures. A whisper.cpp run against the UCLASS reference is the next step.
5. **The Swift Best tier is absent from the `M_1017` table.** Those weights are
   3.2 GB and they were not on the test machine.
6. **The cleaned reference uses a mechanical rule.** It removes filled pauses,
   aborted words and each immediate repetition of one token. It keeps a
   repetition that changes form, such as "marks mark". **It does not remove a
   repetition of a phrase**, such as "i didn't i didn't" or "in in in Japanese".
   The rule therefore suits a mild stutter. It reports too high a score for a
   severe stutter.
7. **The three other UCLASS transcripts are not scored yet.** Two problems stop
   them. Their time offset from the released wav is larger, and the fit leaves a
   residual of 166 ms to 315 ms. At 315 ms the silence test in the scorer marks
   ordinary words as redacted, which is wrong. Their speakers also repeat
   phrases, which limit 6 covers. `eval/get-uclass.sh` fetches the files. Do not
   quote a number from them until both problems are solved.
8. **English only for the reference numbers.** The Tagalog and Taglish results
   are coverage and observation, and not WER.

## Reproduce this

Fetch the UCLASS fixture. The audio is not in this repository.

```sh
./eval/get-uclass.sh                       # M_1017_11y8m_1 audio and transcript
```

Run the Swift side from `app/`:

```sh
swift build -c release --product transcribe
./.build/release/transcribe --audio eval/audio/M_1017_11y8m_1.wav \
    --language en --no-diarize --tier balanced --models models \
    --format txt --out out.txt --json out.json
```

Add `--live --realtime` for the live path. Add `--model openai_whisper-small`
for the small model. Add `--tier best` for the full large-v3.

Score the run against the human reference:

```sh
python3 eval/uclass_score.py eval/audio/M_1017_11y8m_1.wav \
    eval/refs/M_1017_11y8m_1.cha balanced=out.json
```

Run the Tauri side from that repository's `src-tauri`:

```sh
cargo run --release --example transcribe_eval -- FILE.wav /path/ggml-MODEL.bin en
```

Set `NOTERO_EVAL_WINDOW_MS=28000` for the windowed variant. The live path is the
ignored test `session_transcribes_with_whisper`.

The scorer lowercases the text and removes the punctuation. It maps the UCLASS
pronunciation spelling and the ASR spelling onto one form. For the older
fixtures, remove the header and the timestamp lines from a Swift `.txt` export
first. Those lines are not transcript.

## Transcripts

### `M_1017_11y8m_1`, where the systems differ

The UCLASS reference writes each filled pause and each repetition. Both models
omit most of them. These lines show the pattern. `(UM)` is a filled pause. A
capital marks the token that the speaker repeated.

| Reference | Swift `balanced` | Swift `small` |
| --- | --- | --- |
| `I i live in chis -sick` | "I live in Chiswick" | "I live in Chiswick" |
| `for my my end of year ex -ams` | "for my for my end of year exams" | "for my for my end of year exams" |
| `i/m just I/M near -ly go -ing` | "I'm just I'm nearly going" | "I'm just I'm really going" |
| `good marks mark in them` | "good marks in them" | "good marks in them" |
| `(UM) i am RAre -vi -sing` | "I'm revising" | "I'm revising" |
| `sled storm es us ex trik -ee` | "Sledstorm, SSX Tricky" | "Sladstone, SSX tricky" |

The models keep one repetition ("my my"), and they drop another ("marks mark").
The same run does both. This is why this page scores a verbatim reference and a
cleaned reference.


### `F_1211` interview

The full transcripts are not reproduced here. The audio is public, so any reader
can rebuild them. These are the lines that the text above refers to.

| Point | Reference (this app's own export) | Tauri turbo | Tauri small |
| --- | --- | --- | --- |
| A machine error inside the reference | "No, I'm a daddy" | "No, I went to that too" | "No, I want that too" |
| The drink | "It's called pinagalas. It's nice." | "It's called Pinaclade, it's nice." | "It's called peanut gratis, nice." |
| A block | "This... Drink." | "This, um, this / This, um... Drink." | "I hope I'm... this and this / This, um... Drink." |

The third row shows the same problem as `M_1017`. The three systems disagree
about how to write a block. They do not disagree about the word.

### Tagalog vlog clip

**Swift, offline.** The decode stopped after the first sentence.

> Gusto lamang niya sana kumain ng bulalo, totoong bulalo at hindi cup noodles
> na bulalo flavor. Saño juegas! Peñalang paproles togumpanan just auto teño
> paprobles!

**Swift, live path.** The live path recovered the clip.

> Gusto lamam niya sana kumain ng bulalo, totoong bulalo at hindi cup noodles na
> bulalo flavor. Ang gusto ko lang malaman, ang go-order ko ay bulalo. Bakit ako
> bibigyan sa knowledge? [...] Pequean lo kapdodils.

**Tauri turbo.**

> Gusto lamang niya sana kumain ng bulalo, totoong bulalo at hindi cup noodles na
> bulalo flavor. Ang gusto ko lang malaman, ang go-order ko ay bulalo. Bakit ako
> bibigyan sa knowledge? [...] Sige lang cup noodles.

The offline Swift run lost approximately 60% of the clip. Two windows held 29 s
of detected speech. The decode of the first window returned its opening sentence
only, which is 25 words of approximately 75. The live path recovered the clip at
12 times the decode cost. The per-utterance decode of whisper.cpp lost nothing
here, because its VAD caps an utterance at 25 s.

**A decode that returns far fewer words than its window predicts is a failure.
Retry it. Do not accept it as a result.**

## Acknowledgement

This page uses recordings from UCLASS, the UCL Archive of Stuttered Speech.
The Wellcome Trust supported the UCLASS data collection.
