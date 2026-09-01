# Phase 1 findings

What the vertical slice actually measured, and the two places the plan needs
amending. Numbers are from a MacBook Pro M5 Pro (see ENVIRONMENT.md) — not the
Mac mini M2 Pro the plan assumes.

## 1. The model ID in section 2 is ambiguous, and the obvious reading is wrong

WhisperKit's `_turbo` suffix marks a compute variant, not OpenAI's
large-v3-turbo model. Name-matching "large-v3-turbo" gets you
`openai_whisper-large-v3_turbo`, which is the full 1.5B large-v3 with a 1813 MB
decoder. The model you validated offline is `large-v3-v20240930`, whose decoder
is 344 MB — 5.3x smaller.

Since the design re-decodes a 15 s window every 1 s hop, decoder cost dominates
the loop. Getting this wrong would have been both far slower and a *different
model* from the one your offline WER was measured on, quietly invalidating the
Phase 2 exit criterion that compares the two.

Locked to `openai_whisper-large-v3-v20240930_turbo`. Full size table in
ENVIRONMENT.md.

## 2. Section 7's "no fallback ladder" is silent data loss

Section 7 specifies temperature 0.0 with the fallback ladder reserved for
offline cleanup. Implemented literally — `temperatureFallbackCount = 0` — this
does not merely disable a quality feature. It turns WhisperKit's decode gates
into silent drops.

WhisperKit applies four gates to a decoded window: `noSpeechThreshold`,
`logProbThreshold`, `compressionRatioThreshold`, and `firstTokenLogProbThreshold`.
When one trips, the decode is meant to be retried at a higher temperature. With
no fallbacks configured there is nothing to retry with, so the window returns
**empty text and no error**. The orchestrator cannot distinguish that from
silence.

Isolated by disabling each gate independently: `firstTokenLogProbThreshold` is
the one that fires. It bails when the first decoded token looks improbable.

**Why this matters more in Phase 2 than Phase 1.** That gate is designed for
file transcription, where a window starts at a natural boundary. A sliding ring
buffer starts a window mid-word on *every hop*. Low-confidence first tokens are
therefore the normal case, not the exception, and the failure mode is invisible.

**Do not fix it by removing the gate.** With `firstTokenLogProbThreshold`
disabled, a 7 s window decoded to:

> Kalo mga mga mga mga mga mga mga mga mga mga mga mga mga mga … (438 chars)

That is precisely the repetition loop the risk register's "hallucination"
row exists to prevent. The gate is doing real work.

**What was changed:** the gates stay on, `temperatureFallbackCount` defaults to
2 so a trip retries instead of vanishing, and the server now logs a warning
whenever a window returns no text. Every gate is exposed as a sidecar flag
(`--fallbacks N`, `--no-firsttoken`, `--no-nospeech`, `--no-logprob`,
`--no-compression`) so this can be tuned rather than guessed at.

**Measured impact.** Simulating the Phase 2 geometry exactly -- 15 s window,
1 s hop, 43 hops across the fixture -- counting hops that returned no text:

| Configuration | Empty hops | Median inference | RTF |
|---|---:|---:|---:|
| thresholds on, `fallbacks=0` (section 7 as written) | **16 / 43 (37.2%)** | 821 ms | 0.055 |
| thresholds on, `fallbacks=2` (now the default) | 7 / 43 (16.3%) | 891 ms | 0.059 |
| `firstTokenLogProbThreshold` removed | 2 / 43 (4.7%) | 873 ms | 0.058 |

As specified, **more than a third of hops would produce nothing at all**, with no
error anywhere. Two fallbacks more than halves that for ~70 ms. Removing the gate
almost eliminates it and is still the wrong trade, for the reason above.

This is also visible in the end-to-end run: streaming the 57 s fixture through
the server produced 11 segments and one hole, where chunk 11 (45-50 s) decoded
to nothing. The new warning names it:

```
WARNING asr.server: chunk 11 returned no text (5000 ms of audio, 726 ms
inference) -- decode threshold likely tripped
```

**Still open:** the right values. See the caveat below.

## 3. Short windows degrade Tagalog badly — section 3 confirmed

Same audio, same model, different window length:

| Window | Output |
|---|---|
| 3 s | "I'm Gustaf Kayong Lahat. Welcome sa meeting nama." |
| 5 s | "I'm Gustaf Kayong Lahat. Welcome sa meeting Natin Ngayong Umaga." |
| 15 s | "Kumusta kayong lahat, welcome sa meeting natin ngayong umaga. Bagotayo magsimula, gusto kolang i confirm…" |

Reference: *"Kumusta kayong lahat, welcome sa meeting natin ngayong umaga."*

At 3–5 s the decoder renders a Tagalog greeting as English ("I'm Gustaf"). At
15 s it is correct. This is section 3's thesis reproduced on the first day:
the language decision is context-dependent, and starving the decoder of context
makes it fall back to English. It argues for keeping the 15 s window and against
trimming it to buy latency.

## 4. Section 7's concurrency cap of 3 is not reachable

A 15 s window costs a median **~880 ms** of inference. At the specified 1 s hop
that is 88% of one model instance's throughput consumed by a **single** session.
A second concurrent session needs 176% of it.

So with one model instance at 15 s / 1 s, the real cap is **one session**, not
three. The scheduler's drop policy would not be trimming an occasional late hop;
it would be discarding most of the work for every session after the first.

Worse, this is measured on an M5 Pro. The plan targets a Mac mini M2 Pro, which
is slower.

Options, in the order worth trying:

1. **Raise the hop to 1.5-2 s.** Section 7 already lists this as the tuning knob
   when the queue backs up. At a 2 s hop, two sessions fit.
2. **Run more than one model instance.** 24 GB of RAM holds several 1.6 GB
   models; whether the ANE parallelises them is an open question worth measuring
   before assuming.
3. **Accept a cap of one.** If this is solo dictation rather than meetings
   (section 15's open item), this costs nothing -- and it also decides whether
   Phase 6 diarization is needed at all.

Either way the number in section 7 should not survive contact with Phase 3's
load test. Measure the degradation curve early rather than at the end.

## Measured RTF on this machine

| Path | Window | Median inference | RTF |
|---|---|---:|---:|
| Sliding (Phase 2 geometry) | 15 s | 891 ms | 0.059 |
| Fixed chunks (Phase 1, end to end) | 5 s | 516 ms | 0.103 |

First model load compiles CoreML for the ANE and took **284 s**. Subsequent
loads hit the cache at **9-11 s**. Worth knowing before assuming a restart is
cheap.

## 5. Phase 2: the commit policy stalls permanently if the window slides

LocalAgreement compares the *prefixes* of consecutive hypotheses. That only
works while consecutive windows start at the same point in the audio. The first
build slid the ring buffer freely, so each pass began a second or two later than
the last, their first words described different audio, the agreed prefix was
empty, and nothing committed -- ever. The provisional tail grew to 200+
characters while `committed=+0` repeated on every hop.

It is not a degraded mode that recovers. Once the window passes the committed
point the misalignment is self-sustaining.

Two changes fix it:

1. `RingBuffer.trim_to()` anchors the window to the last commit, so passes share
   an origin.
2. `LocalAgreement.force_commit_before()` handles the case where the buffer hits
   its cap anyway. Audio about to be discarded is committed unagreed, which
   trades the agreement guarantee for liveness on that span and keeps the window
   anchored. It is counted as `forced_commits`; a high rate means the window and
   hop are mistuned, not that the audio was hard.

## 6. Phase 2 exit criterion: met, at a 1.5 s hop rather than 1.0 s

Replaying the fixture through the real streaming path and scoring it against a
whole-clip offline call on the same model:

| Hop | Hops dropped | Forced commits | Live WER | Gap vs offline |
|---|---:|---:|---:|---:|
| 1.0 s (section 7) | 23 / 34 (68%) | 5 | 41.4% | **+14.1** |
| **1.5 s** | 5 / 33 (15%) | 10 | **28.9%** | **+1.6** |
| 2.0 s | 0 / 28 (0%) | 15 | 45.3% | +18.0 |

Offline on the same clip: 27.3%.

At 1.0 s the hop is shorter than the ~0.9 s a 15 s window costs, so two thirds
of hops are dropped and "consecutive" passes are anything but -- finding 4's
throughput ceiling showing up as an accuracy problem rather than a latency one.

At 2.0 s nothing is dropped and it is *worse*: 29 deletions against 9 at 1.5 s.
The buffer outruns agreement, so commits get forced instead of agreed, and
forced commits take whatever the newest pass said. There is a sweet spot, and
1.0 s and 2.0 s sit on opposite sides of it for opposite reasons.

**`hop_ms` now defaults to 1500.** Re-derive it on real audio -- the mechanism
is real but the optimum depends on the material.

## 7. Phase 3 concurrency: partials hold up, commits do not

Four simulated clients streaming the same 30 s clip at real-time pace:

| Streams | Commits per stream | Partial p50 | Partial p90 | Final p50 |
|---:|---:|---:|---:|---:|
| 1 | 8.0 | 0.26 s | 0.55 s | 13.8 s |
| 2 | 6.5 | 0.28 s | 0.50 s | 15.5 s |
| 3 | 6.3 | 0.35 s | 0.54 s | 15.5 s |
| 4 | 5.2 | 0.34 s | 0.51 s | 15.5 s |

**Partial latency barely moves** -- 0.26 s to 0.35 s from one stream to four,
comfortably inside section 14's 1-1.5 s target. The muted-text experience
survives four concurrent streams on this machine.

**Commits per stream fall by a third.** That is where the throughput ceiling
lands: the same audio yields fewer agreed commits because more hops are dropped.
Text still appears promptly; it just takes longer to settle. Peak scheduler
queue wait was 5.6 s at four streams.

Final latency of ~15 s is not a concurrency effect -- it is flat across all four
counts. It is the commit policy riding the 15 s window cap on audio the model
finds unstable, and it should fall on real recordings where agreement fires more
often. Watch `forced_commits`; if it stays high on real audio, that number is
the thing to fix, not the hop.

Note `dropped_superseded` stayed at 0: each pipeline's own in-flight guard drops
hops before they reach the scheduler, so the scheduler's supersession is a
second line of defence that never fired in this configuration.

## 8. Phase 5: the cleanup model invents, and similarity alone does not catch it

A 3B local model asked to tidy Taglish drops and replaces words while looking
almost unchanged by any character-level measure. Four real examples, with their
similarity scores:

| Raw | Rewrite | Similarity |
|---|---|---:|
| tatlong **bagailangan**. Una, yung update | Tatlong **bagay ang karanasan**. Una, yung update | 0.88 |
| i priority **zayun** this week | i priority, this week | 0.96 |
| Nga **nares** last week | Nga, last week | 0.92 |
| Confirm kung kumple **tona** | Confirm kung kumple | 0.94 |

Every one passed a 0.85 similarity threshold. Losing one word from a
150-character segment moves the score by a few percent while changing what the
sentence says, so a second guard checks that no raw word of four or more
characters vanished entirely from the rewrite. Splits and merges still pass,
because the comparison ignores spacing.

With both guards on the fixture: 17 segments attempted, 11 accepted, **6
rejected for dropped words**, 0 for drift or length. What survives is
conservative -- "lah at" to "lahat", casing, punctuation, "yun MGA" to "yun mga"
-- because anything more ambitious gets rejected.

So the *invented nothing* half of section 10's exit criterion is enforced, and
the *obviously more readable* half is only partly met. The model is the limit,
not the mechanism. A larger local model is the obvious next thing to try, and
`CleanupEngine(model=...)` takes any MLX model id.

One related bug worth knowing about: cleanup has to be idempotent. Writing only
the accepted rewrites left segments holding stale cleaned text from an earlier,
looser run -- precisely the ones that mattered, since the reason to tighten the
guards is that the old output was wrong. A rejected segment now clears its
stored value.

## 9. Phase 6 (native app): the fallback ladder does not save the offline path

Finding 2 established that `firstTokenLogProbThreshold` turns a rejected window
into empty text with no error, and that a fallback ladder is what stops it
being silent data loss. Building the whole-file path in the native app showed
the ladder is necessary but **not sufficient**, and the offline case fails in a
way the live case does not.

Whole-file transcription cuts the audio into windows just under Whisper's 30 s
receptive field, decodes each once, and concatenates. On the Taglish fixture,
one window returned nothing:

| Window | Decoded |
| --- | --- |
| 0.000–24.876 s | **empty, every attempt** |
| 24.532–49.708 s | 54 words |
| 49.364–57.049 s | 16 words |

Twenty-five seconds of speech — 44% of the clip — simply vanished, and the
transcript that came out looked merely short rather than broken. WER doubled
from 27% to 56% while every stage reported success.

Three things about this were not obvious:

**It is deterministic.** Five consecutive runs produced the identical empty
result. This is not sampling variance, so retrying the same window is pointless.

**The ladder does not fix it.** Retrying with `temperature` raised to 0.2 and
0.4 and `temperatureFallbackCount` doubled failed identically. WhisperKit
returns an empty *result set* — not an empty transcription — and it gets there
the same way every time.

**It is the boundary, not the audio.** The same leading audio decoded fine at
every other length tried:

| Window length | Result |
| --- | --- |
| 24.876 s | empty |
| 25.500 s | 90 words |
| 26.000 s | 56 words |
| 27.000 s | 60 words |
| 28.000 s | 70 words |

Whichever gate fires, it is a function of where the window happens to end.

**Why the live path never showed this.** Live windows slide by 1.5 s and
re-decode overlapping audio every hop, so a boundary that trips a gate is gone
1.5 s later and the words are recovered by the next pass. That redundancy is
what LocalAgreement is buying, and it hides the failure. The offline path
decodes each second of audio exactly once, so a refused window is not a delayed
commit — it is deleted audio.

**Fix.** A refused window is retried on *different audio*: widened by 700 ms,
then 1400 ms, and finally cut in half and each half retried independently
(bounded at two levels of splitting). A window nothing can decode is counted and
surfaced to the user, because the one thing that must not happen is a short
transcript passing for a complete one.

Result on the same fixture, five runs: no dropped windows, 119–121 words against
123 in the reference, WER 20.3–25.8% — at or below the 27.3% offline number this
document already records as the fixture's ceiling. Locked in by
`PipelineDecodeTests`, which models the refusal by sample count because the real
model cannot be made to fail on demand.

## 10. The diarizer fuses similar voices that share a 10 s chunk

Found on a real recording (an adult interviewing an 11-year-old, both female):
every turn in the first 24 seconds came back as one speaker, including the
interviewer's opening question, while the same interviewer was correctly split
out as a second speaker later in the file.

**Mechanism.** FluidAudio cuts whatever audio it is handed into fixed 10 s
chunks and extracts ONE embedding per *local segmentation slot* per chunk. The
pyannote segmentation model decides the slots, and for these two voices it put
both speakers in the same slot whenever they shared a chunk. One slot means one
embedding means one cluster — the clustering threshold never gets a say.
Swept `clusteringThreshold` 0.45–0.75 on both the streaming and the offline
(VBx) pipelines: no effect, because the fusion happens before clustering.
Proof it is the chunking: prepending 8.2 s of silence, so the two turns land in
different chunks, splits them cleanly at the default threshold.

**Dead ends worth recording.** Aligning diarizer calls to Silero's speech
regions does not work — Silero bridged the 1.8 s pause between the two voices
(regions are tuned for decode windows, not turns), and per-region calls fed the
online clusterer noisy short embeddings that invented phantom speakers.
`extractSpeakerEmbedding` is documented as returning L2-normalized vectors and
does not (norms up to ~2.1); cosine distances computed on its raw output are
meaningless and cluster everything into one speaker.

**Fix.** A second pass in `SpeakerEngine`: trust the first pass only for *where
turns are*, never for who spoke. Every merged span is re-embedded from exactly
its own audio (`extractSpeakerEmbedding`, then normalize) and re-clustered
globally — longest span first, so the cleanest embeddings found the clusters;
spans under 2 s may join a cluster but never found one, which is what keeps
noisy backchannels from inventing a third speaker. On the recording above the
distances are cleanly bimodal (same speaker ≤ 0.56, different ≥ 0.77 against
the 0.7 threshold), the roster drops from three speakers to the true two, and
every turn in the transcript lands on the right one.

## Caveat: the audio was synthetic

macOS ships no Filipino voice, so the fixture uses the Indonesian one reading a
Taglish script — close in phonology, wrong in acoustics. It also begins at full
amplitude at sample 0 with no lead-in, which is not how real recordings behave
and which is partly why the first window is unusually hostile.

So: findings 1, 2, 4 and 5 are structural and hold regardless of audio. Finding
3 matches the plan's own prediction and is very likely real.

Finding 6 needs the most care. The 27.3% offline WER is the fixture's fault, not
the model's -- an Indonesian voice reading Taglish is not what the model was
measured on. The *gap* between live and offline is the meaningful number, and
the mechanism behind the curve (too fast drops hops, too slow forces commits)
is real. But the specific optimum, and the decode threshold values in finding 2,
must be re-derived against your own recordings.

`eval/replay.py` and `eval/score.py` do exactly that once `eval/audio/` and
`eval/manifest.json` point at real clips:

```
./.venv/bin/python eval/replay.py --out /tmp/off --offline
./.venv/bin/python eval/replay.py --out /tmp/live --hop 1500
./.venv/bin/python eval/score.py /tmp/off  --label offline
./.venv/bin/python eval/score.py /tmp/live --label live
```
