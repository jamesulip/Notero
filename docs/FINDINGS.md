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
