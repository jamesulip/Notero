# Findings

> **Engineering findings, and not product guarantees. Read this note first.**
> Each entry is a measurement or a failure that the maintainer recorded on one
> Mac, on the test material that [BENCHMARKS.md](BENCHMARKS.md) describes. The
> entries keep the words that they had on the day of writing, thus some of them
> describe a problem that the app has since fixed. Read the entry to the end
> before you use a number from it, and read the
> [caveat](#caveat-the-audio-was-synthetic) at the bottom of this file.
>
> [BENCHMARKS.md](BENCHMARKS.md) gives the current measurements with their
> conditions. The [README](../README.md) describes the product.

Measurements and failure modes recorded while building the Python server
(phases 1–5) and the native app (phase 6). Several of these exist because a
plausible-looking change quietly lost transcript data; this is the file to read
before changing a model id, a decode parameter or the commit policy.

Numbers are from a MacBook Pro M5 Pro (see [ENVIRONMENT.md](ENVIRONMENT.md)) —
not the Mac mini M2 Pro [PLAN.md](PLAN.md) assumes, so they are an upper bound
on that machine. "Section N" throughout refers to PLAN.md. Findings are
numbered in the order they were found and are referenced by number elsewhere,
so they are never renumbered.

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

Found on a real recording of two female speakers with similar timbre: every
turn in the first 24 seconds came back as one speaker, including the opening
question, while the same speaker was correctly split out as a second speaker
later in the file.

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

## 11. Pre-roll and VAD-timed finalization on the live path

The native app's live path had never been measured: the numbers in finding 6
came from the retired Python server. `transcribe --live` now replays a file
through the same `LiveDecoder` a recording uses, so the live path can be scored
against the offline pass on identical audio. Two clips exist on disk -- the
57 s synthetic Taglish fixture and a 25 s real meeting excerpt with a hand-kept
reference -- and the second is too noisy a reference to draw conclusions from
(offline WER 60%; live 60-67% with every variant inside that spread). The
synthetic clip is the one that separates the variants.

**Cold start at the commit was costing six WER points.** The window used to be
trimmed exactly to the last committed word, so every decode began mid-stream
with no acoustic context. Keeping 1.5 s of committed audio in front of the
active region (`SessionConfig.preRollMs`), and dropping what the model re-reads
from it by time and, for the boundary word, by text:

| Live variant (1.5 s hop, 15 s context) | WER | Forced commits | Tail words committed unagreed | Dedup by text |
|---|---:|---:|---:|---:|
| pre-roll 0 (old context window) | 33.6% | 9 | 33 | 0 |
| **pre-roll 1.5 s** | **27.3%** | **2** | 4 | 5 |
| pre-roll 1.5 s, real-time pacing | 26.6% | 2 | 12 | 7 |
| offline pass, same model | 27.3% | — | — | — |

The live path with pre-roll lands *on* the offline number. Forced commits fell
from 9 to 2 because agreement now succeeds where the cold start used to make
consecutive passes disagree on the first words; the phrases the old path
mangled at those points ("Bisa Portney Maria", "Ang Thank you for atapos") come
back whole ("Base sa report ni Maria", "Ang problema kasi, hindi pa tapos"). No
adjacent duplicated word appears in any variant's transcript. Real-time pacing
dropped 4 of 38 hops (11%) on this machine, against 15% for the Python server
at the same hop in finding 6.

**The old boundary never decoded the end of an utterance.** `boundary()` fired
at the next hop after 700 ms of silence and flushed the *previous* hop's
hypothesis -- a window that ended up to 1.5 s before the pause. The speech
between that hop and the pause was never decoded by anyone; the last second of
every utterance could simply be missing, and the words that were committed were
the least-evidenced ones in the transcript. Finalization is now requested by
the VAD the moment trailing silence reaches the threshold, runs a decode of the
audio up to the pause (or reuses the hop already in flight if its window
reached past the speech), puts it through LocalAgreement, and commits the
remainder only if the room is still silent when the decode returns.

Neither clip contains a pause of 768 ms (three Silero chunks), so on them the
boundary never fires and the whole effect is the one measured above. To
exercise it, `eval/make_paused.py` inserts 1.2 s of silence after each
sentence-final word of the synthetic clip:

| Paused clip (87 s, 25 pauses) | Boundaries closed | Final decodes | Tail words committed unagreed | WER |
|---|---:|---:|---:|---:|
| live, pre-roll 0 | 24 | 21 | 30 | 44.5% |
| **live, pre-roll 1.5 s** | 24 | 21 | 41 | **41.4%** |
| live, pre-roll 1.5 s, real-time pacing | 13 (+11 abandoned) | 13 | 42 | 42.2% |
| offline pass, same clip | — | — | — | 67.2% |

Every pause closed an utterance, 21 of them with a decode of their own and 3
on a hop that was already in flight and had reached past the speech. The
offline number is worse than any live variant here: 1.2 s of digital zeros is
not how a room falls silent, and the offline VAD/windowing loses whole windows
on it -- so this clip is a stress test for the boundary logic, not a benchmark.
Under real-time pacing 11 of the 24 requests were *abandoned*: the gap is
shorter than a decode plus the VAD's lag, so someone was talking again by the
time the decode returned, and the tail stayed provisional and was committed at
the next pause instead. Nothing was lost; that is the policy working.

The first run of this clip found a bug the unpaused clips could not: the same
sentence committed two and three times around a pause ("Magyo dilet tayo ng
one week pero managable panaman" three times over), every copy timestamped
`start == end == ceiling`. Whisper pads each window to 30 s and reads the
padding, most often by repeating the last phrase, with timestamps past the end
of the audio; the offline path drops those in `rebase`, the live path clamped
them to the ceiling and committed them. Two filters fixed it and took the clip
from 58.6% to 41.4%: a word starting past the window's audio (plus the 250 ms
the offline path already tolerates) is dropped, and at a final decode a word
starting after the point where the VAD heard speech end is dropped too --
that one is the "Thank you." Whisper reads out of a silence. Both are counted
as `hallucinationsDropped`. One such phrase still survives at the first pause
(it was decoded by a hop, not a final, and the hop's version agreed with the
final's); a silence-aware filter on hops is the obvious next step if real
recordings show it.

**Adaptive hop: measured, and left off.** Shortening the hop to 1.0 s while
decodes are fast (`SessionConfig.adaptiveHop`, gated on 1.5x the last decode's
reported inference time) was tried under real-time pacing:

| Real-time replay | Dropped hops | Forced commits | WER |
|---|---:|---:|---:|
| fixed 1.5 s hop | 4 / 38 | 2 | 26.6% |
| adaptive 1.0-1.5 s | 10 / 46 | 9 | 29.7% |

More drops and more forced commits, exactly the failure finding 6 predicted
for a 1.0 s hop. The reported `inferMs` understates the wall-clock cost of a
decode (audio conversion, actor hops and the main-actor ingest path all sit
outside it), so the gate lets the hop shrink further than the machine can
sustain. The flag stays available for a machine that is faster than this one;
the default is off.

**Forced `tl` beats `auto`, and `auto` hears Indonesian.**
`eval/compare_language.py` runs both modes over the manifest and scores each
with `eval/langscore.py`, which classes every reference word as Filipino or
English (hyphenated Tagalog affixes and a function-word list first, then the
system English lexicon) and reports error rates per class and at code-switch
points:

| clip | mode | WER | S/D/I | Filipino err | English err | code-switch err | RTF | detected |
|---|---|---:|---|---:|---:|---:|---:|---|
| synthetic | tl | 25.2% | 24/5/2 | 29.8% | 10.3% | 13.0% | 0.145 | tl |
| synthetic | auto | 62.6% | 28/48/1 | 67.9% | 48.7% | 53.7% | 0.110 | id x3 |
| meeting01 | tl | 72.9% | 13/30/0 | 75.5% | 60.0% | 64.3% | 0.120 | tl |
| meeting01 | auto | 66.1% | 34/1/4 | 63.3% | 40.0% | 50.0% | 0.608 | tl x1 |
| **all** | tl | **40.7%** | 37/35/2 | 46.6% | 20.4% | 23.5% | 0.137 | |
| **all** | auto | 63.7% | 62/49/5 | 66.2% | 46.9% | 52.9% | 0.263 | |

On the synthetic clip `auto` resolves to Indonesian for all three windows and
loses 48 words to deletion -- which is the documented failure, though this
fixture is the least fair test of it imaginable, since the voice *is*
Indonesian. On the real excerpt `auto` edges `tl` (66% against 73%) at five
times the decode time, and the reference there is too poor to trust either
number. Pooled, `tl` is 23 points better and half the cost. **The default stays
`tl`.** The harness is the point: run it on real Taglish recordings with clean
references before revisiting this. (WER here is `langscore`'s, which keeps
intra-word hyphens so "i-send" stays one Filipino word; the CLI's own WER
splits it and reads 27.3% for the same transcript.)

## 12. A confirmed pause drops what a hop read out of it; a style primer does not help (2026-09-06)

Finding 11 left one hallucination standing on the paused clip: a phrase a *hop*
had read out of a pause survived because speech resumed before the final
decode returned, the boundary was abandoned, and the next two hops -- whose
windows still covered the pause -- agreed on the phrase and committed it. The
final decode's own filter (`speechEndMs + 250 ms`) never saw those hops.

`LiveDecoder` now records every pause the VAD confirms at `silenceBoundaryMs`
or longer, on the session timeline, and drops from *every* hypothesis a word
that starts inside one (250 ms of slack at each edge, the same drift the padding
filter allows). Pauses that end before the commit are pruned. Measured on the
paused synthetic clip (87 s, 25 inserted pauses of 1.2 s), every decode awaited,
Balanced tier, today's baseline against today's build:

| Paused clip, live replay | WER | Words | Tail words committed unagreed | Deduplicated by text |
|---|---:|---:|---:|---:|
| before | 51.6% | 122 | 59 | 14 |
| **confirmed-pause filter** | **39.1%** | 127 | 46 | 17 |

Twelve and a half points, and thirteen fewer unagreed tail words: the phrases
that used to be committed from a pause were exactly the ones no second pass had
agreed with. The unpaused clips are unchanged (no pause on them reaches 700 ms),
which is the expected null result. A test reproduces the abandoned-final
sequence with a scripted VAD and a phantom word and asserts the phantom never
reaches a partial once the pause is confirmed
(`LiveDecoderTests.testAWordReadOutOfAConfirmedPauseNeverCommitsEvenWhenTheFinalIsAbandoned`).

**A Taglish style primer in the prompt makes the live path collapse.** The idea
was to hand Whisper one sentence of ordinary Taglish as the "previous
transcript" before each window, so it would spell English words in English and
keep the hyphen in "i-send". The primer names none of the fixture's content
words, and `TranscriptionPrompt` carries it so the measurement can be repeated
(`transcribe --style-hint`). Measured, Balanced tier:

| Clip | Path | No primer | Primer |
|---|---|---:|---:|
| synthetic | offline | 24.2% | 44.5% |
| synthetic | live | 27.3% | **96.1%** |
| meeting01 | offline | 71.7% | 65.0% |
| meeting01 | live | 63.3% | **280.0%** |

On the live path the model repeats the primer into the hypotheses: 153 and 195
decoded words against 123 and 51 without it, and the unagreed tail counts go
from 37 to 5 and from 4 to 38, which is agreement on invented text. Offline it
is worse on the clip with the trustworthy reference and better on the one whose
reference is too poor to weigh. The primer is not sent by the app. The user's
own Names and terms field still goes through, unchanged: it is a short list,
and this measurement says nothing about short prompts. `suppressBlank` was
measured in the same run (25.8% / 27.3% / 58.3% against 24.2% / 27.3% / 71.7%)
and left at WhisperKit's default.

## 13. Automatic notes: Apple's model refuses Taglish, and the small MLX models write English notes from it but not Tagalog ones (2026-09-06)

The notes workspace has had the shape for this since v1: a summary and five
typed lists whose rows keep a source timestamp. The question was which
on-device model could write into it, and how well, on a Taglish meeting. The
reference is the one meeting in the library with notes written by hand: a
93-minute product-taxonomy meeting, 1,525 segments, an 845-character summary and
41 notes (15 decisions, 9 action items, 9 key points, 5 questions, 3
follow-ups). `eval/langscore.py` classes 64 % of its words as Tagalog; the
function-word list in `NotesScoring.languageMix` classes 43 %. Both numbers
below name their heuristic.

**Apple's Foundation Models framework refuses the transcript before it reads
it.** `SystemLanguageModel.default` is available on this Mac and lists 23
locales, none of them Filipino. A `LanguageModelSession.respond` with a part of
the transcript as the prompt returns `unsupportedLanguageOrLocale` in 0.0 s.
Four parts of the same meeting, chosen by their Tagalog share, with the default
guardrails and with `.permissiveContentTransformations`:

| Part of the meeting | Tagalog words (langscore) | Default guardrails | Permissive guardrails |
|---|---:|---|---|
| the most English turns, 3,646 chars | 28 % | accepted, 3.5 s | accepted, 2.0 s |
| mixed turns, 3,744 chars | 50 % | refused | refused |
| 6:21–12:00 in order, 4,450 chars | 71 % | refused | refused |
| the most Tagalog turns, 3,452 chars | 92 % | refused | refused |

The limit is somewhere between 28 % and 50 % Tagalog words, and it is a check on
the prompt's language, not on its content: the guardrail setting changes
nothing, and the instructions were English in every case. A Taglish meeting
is refused whole, since every part of it is over the limit. The pipeline
treats that refusal as fatal rather than skipping the refused parts: a draft
made from the English-heavy minutes of a Taglish meeting would misrepresent
it. The app says "The model does not accept the language of this transcript."

On what it accepts, the model works. An export reduced to the 95 segments
with at most 25 % Tagalog words (6 % overall) gave 8 notes in 11 s across 2
parts, 6 of them with a source line, grounding 0.68 with none under 0.4 -- and
two of the eight were noise ("25, 25." as a key point, "Akay, sir?" as a
question). Guided generation held the shape; it did not hold the judgement.

**The MLX models accept Taglish.** `eval/notes_eval.py` runs the same parts,
the same instructions and the same JSON request through `mlx_lm`, and scores
the draft as `transcribe --notes` does. Five runs on the reference meeting,
14 parts of at most 5,000 characters, temperature 0.2, on this 24 GB Mac:

| Model (4-bit) | Weights | s per part | Notes K/D/A/Q/F | With a line | Grounding mean, under 0.4 | Tagalog in notes (langscore) | Hand-written notes covered at 0.5 / 0.3 of 41 | Draft notes that match one at 0.5 / 0.3 |
|---|---:|---:|---|---:|---|---:|---|---|
| Qwen2.5-3B-Instruct, English | 1.6 GB | 4.1 | 41/5/27/10/20 = 103 | 100 | 0.42, 48 | 10 % | 3 / 15 | 5 / 28 of 103 |
| Qwen3-4B-Instruct-2507, English | 2.1 GB | 6.6 | 90/0/3/7/13 = 113 | 111 | 0.47, 36 | 12 % | 11 / 25 | 15 / 48 of 113 |
| Qwen3-4B-Instruct-2507, as spoken | 2.1 GB | 8.0 | 92/0/2/7/10 = 111 | 105 | 0.55, 30 | 46 % | 9 / 22 | 9 / 42 of 111 |
| gemma-3-4b-it-qat, English | 2.8 GB | 7.0 | 74/12/21/15/9 = 131 | 126 | 0.46, 47 | 13 % | 6 / 21 | 8 / 35 of 131 |
| Qwen3-8B, English | 4.3 GB | 11.3 | 71/1/13/8/7 = 100 | 92 | 0.42, 40 | 13 % | 5 / 17 | 5 / 33 of 100 |
| Qwen3-4B-Instruct-2507, English, at most 5 notes a part | 2.1 GB | 4.5 | 47/0/2/4/6 = 59 | 56 | 0.47, 22 | 15 % | 10 / 19 | 10 / 25 of 59 |

Loading takes 1.5 to 2.6 s; a 93-minute meeting is read in one and a half to
two minutes on the 4B models. "Grounding" is the share of a note's content
words that occur in the transcript within two minutes of the note's
timestamp, and English notes about Tagalog speech score lower by
construction -- which is why the as-spoken run has the best grounding and the
worst text. "Covered at 0.5" needs half of a hand-written note's content words
in one draft note; 0.3 is the looser match a paraphrase gets. Neither is a
judgement of the writing, so the drafts were also read.

What the reading says:

- **Qwen3-4B's English summary is the hand-written summary in other words.**
  It names the flowchart module and its highlighting, the hierarchy of
  groupings, each person's own workspace with a super admin publishing to
  the company backbone, the prefix for unapproved modules, the
  taxonomy of category, product family, product, model and variant, the 10 %
  costing buffer and the Thursday review. The key points are specific and
  carry the right timestamps ("To avoid naming conflicts, modules created by
  a user carry a prefix until they are approved. (30:39)").
- **Every 4B-class model over-extracts, and Qwen3 cannot tell a decision from
  a key point.** 103 to 131 notes against 41 by hand. Qwen3-4B filed 90 of
  its 113 as key points and none as decisions, where the hand-written notes
  have 15 decisions; sentences that begin "The group agreed to..." landed
  under key points. Gemma spread its notes across the kinds but invented
  more (47 under 0.4). Qwen2.5-3B called 27 notes action items. The content
  is largely right; the kind is the weak part, and that is what the review
  sheet's Change To menu is for until a second pass fixes it.
- **The as-spoken style does not work at 4B.** Qwen3-4B reads Taglish well
  enough to write the English notes above, and cannot write Tagalog: "Pinagkakatiwalaan
  ang pagbabayad ng version at approval para sa pagkakaiba ng data" -- payment
  for the version, entrusted, for the difference of the data -- is
  representative, and the notes drift into English half-way through. The
  notes reach 46 % Tagalog words against the transcript's 64 %, and the
  Tagalog that is there is wrong. English is the default for the notes.
- **Twice the weights bought nothing.** Qwen3-8B covered 5 hand-written
  notes to the 4B's 11, took 11.3 s a part to its 6.6, and its summary says
  "no specific decisions were made" of a meeting whose notes hold 15. The
  4B-Instruct-2507 tune is the better note-taker of the two on this meeting.
- **A cap of five notes a part halves the draft and keeps the coverage.** The
  same Qwen3-4B with "at most 5 items" wrote 59 notes instead of 113, covered
  10 hand-written notes at 0.5 to the 11 before, and took 4.5 s a part to
  6.6. The cap costs nothing that the reference measures; the app's prompt
  and the guided schema still say ten, and should say five.
- Qwen2.5-3B broke the JSON on 8 of its 14 answers, closing with `}}}` and
  no `]`. Every one of them held usable notes, and `ChunkNotes.parse` now
  reads the summary string and each item object on its own when the brackets
  are wrong. Its first score, with the strict parser, was 31 notes and
  0 of 41 covered.

What follows. English notes are the default. A Taglish meeting needs an MLX
backend, which is a new `NotesGenerating` conformance and a 2.1 GB download;
Qwen3-4B-Instruct-2507 is the candidate; the 8B row above rules out the
larger one. Before either ships as a default, the kind
classification needs a second pass or a sharper prompt, and the per-part cap
should drop to five, as the variant row shows. The harness and the CLI report the same scores,
so the next candidate is one command on the same meeting.

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
