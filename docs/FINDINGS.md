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

## 13. A 16 kHz microphone could not start a recording (2026-09-10)

Selecting a USB conference speakerphone as the microphone failed with
"The operation couldn't be completed. (com.apple.coreaudio.avfaudio error
560226676.)" over Bluetooth and over USB alike. The code is `'!dat'`,
`kAudioDeviceUnsupportedFormatError`, and it names the wrong culprit: the
device opened fine. A standalone `AVAudioEngine` pinned to either connection
started and delivered buffers.

The device offers one input format on each transport: 16 kHz mono over
Bluetooth, 16 kHz stereo over USB (its 48 kHz side is the speaker). The
archive writer then asked the AAC encoder for 64 kbps a channel at 16 kHz,
and the encoder refused inside `AudioConverterSetProperty(...,
kAudioConverterEncodeBitRate, ...)`. Apple's encoder caps the bitrate by
sample rate, measured on this Mac with `kAudioConverterApplicableEncodeBitRates`:

| Sample rate | Highest AAC bitrate |
| --- | --- |
| 8 kHz mono | 24 kbps |
| 16 kHz mono | 48 kbps |
| 16 kHz, 2 ch | 96 kbps |
| 24 kHz mono | 64 kbps |
| 32 kHz mono | 96 kbps |
| 44.1 / 48 kHz mono | 256 kbps |

Every Bluetooth headset in hands-free mode is 8 or 16 kHz, so the app refused
the whole class of device the meeting-room use case is most likely to meet,
before a frame was captured and with no message a user could act on.

The fix asks the encoder for its applicable range at the archive format and
clamps the 64 kbps request into it; when the encoder cannot be asked, the key
is omitted. After the change the probe records from both connections at
16 kHz (archive bit rates 44 and 51 kbps), and the offline pipeline reads the
16 kHz archive and transcribes it. The archive stays at the device's rate on
purpose: a 16 kHz microphone carries nothing above 8 kHz, and the model
resamples to 16 kHz anyway.

## 14. A full disk crashed the app and made the archive unreadable (2026-10-31)

Found by code audit and then reproduced. Two separate failures happened when the
disk filled up during a recording:

- **The working copy crashed the app.** `WavWriter` appended with the legacy
  `FileHandle.write(_:)`. On any write error that call raises an Objective-C
  exception, and Swift cannot catch one. A standalone program that made the
  same calls into a 4 MB disk image ended with `NSFileHandleOperationException:
  -[NSConcreteFileHandle writeData:]: No space left on device`, exit 134. The
  throwing `write(contentsOf:)` reported the same condition as an ordinary
  error after 4,009,280 bytes. In the app, the crash also left the AAC archive
  unfinalized.
- **The archive lost everything, not only its end.** `ArchiveWriter` discarded
  its write errors with `try?`. `AVAudioFile` *does* report a full disk (it
  threw `com.apple.coreaudio.avfaudio -40` after 538 s of 48 kHz AAC on the same
  4 MB image), but nobody heard it, and the file it left could not be opened:
  `afinfo` failed with `AudioFileOpenURL failed`. An MPEG-4 file is readable
  only once its index (the `moov` atom) is written at close, and a full disk
  has no room for that. Nine minutes of audio were lost.

**The fix stops writing before the disk is full.** Both writers now look at the
free space every 5 s of audio. Below a 100 MB reserve, they stop and close the
file while closing can still succeed. The reserve is far more than any index
needs (a six-hour AAC index is about 4 MB) and leaves SwiftData room to save the
transcript. If a recording starts with less than the reserve free, it is
refused with a message that says the disk is almost full. A write that fails
anyway (another program filled the disk between two looks, or a volume went
away) now stops that writer cleanly. Each writer reports the failure once, as a
notice on the recording screen that is also kept with the recording. The live
transcript is unaffected, because it does not depend on either file. An import
that runs out of space now throws, so it no longer returns a short working copy
that looks complete.

Checked on a real 200 MB volume filled to 108 MB free, with the real `statfs`
probe and no fakes: both writers stopped at 99.9 MB free, nothing crashed, the
working copy held a clean 259 s, and the archive opened in `afinfo`. (The
archive was 4 s long only because the check loop ran far faster than real time,
so the working copy used up the space before the archive's queue looked at the
disk.) `DiskFullTests` reproduces the crash without a disk image:
`RLIMIT_FSIZE` makes `write(2)` fail with `EFBIG` through the same path. With
the legacy call put back, the test fails with
`NSFileHandleOperationException: File too large`.

## 15. The same file decodes differently on each run; WhisperKit 1.1.1 is not adopted (2026-10-31)

WhisperKit 1.1.1 was evaluated as a patch upgrade. Its release notes replace
force-unwraps in logits sampling with typed errors, which is on the path that
every `transcribe(audioArray:)` call takes. The plan was to adopt it if the
transcript did not change. That needed a baseline, and the baseline found the
larger problem first: **the offline pass is not deterministic.**

Measured on the 16 GB **Mac mini M2 Pro** (Mac14,12, macOS 26.6.2) that this project targets, not the M5 Pro
in BENCHMARKS.md. The audio is the synthetic clip (57 s), the tier is Balanced,
there is no diarization, and `transcribe` ran eight times per build on
identical input:

| Build | Runs | First window collapsed | Median WER | WER range | Median RTF |
| --- | ---: | ---: | ---: | --- | ---: |
| WhisperKit 1.1.0 (shipping) | 8 | 1 | 28.1% | 25.0–57.0% | 0.135 |
| WhisperKit 1.1.1 | 8 | **5** | 57.8% | 26.6–60.2% | 0.091 |

"Collapsed" means that the first decode window of about 40 words came back as
English filler that nobody spoke, for example "How are you? Welcome to meeting.
Thank you. Thank you. Thank goodness." or "Thank you so much for watching." The
remainder of the transcript was the same as in the other runs. The retry ladder
does not see this failure, because the window is not empty. The shipping build
does it too, in one run of eight. 1.1.1 did it in five runs of eight. With
eight runs each the difference is not significant (Fisher exact, two-sided,
p = 0.12). The result still points the wrong way, and nothing showed 1.1.1 to
be safe, so **the pin stays at 1.1.0.** Look at it again when a release
changes sampling or fallback, and use more runs.

**Hypothesis, not verified:** attempt 0 is greedy and therefore deterministic.
Randomness enters only when WhisperKit's own temperature fallback re-samples a
window whose greedy decode tripped the log-probability or compression
threshold. The fixture starts at full amplitude at sample 0, which makes its
first window the one most likely to trip a threshold. Finding 16 tests it and confirms it. To test the hypothesis,
log WhisperKit's per-window fallback count beside the collapsed windows. If it
holds, the fix belongs in the decode policy, for example a repetition or
known-filler check that sends a window to the retry ladder. That fix needs real
recordings to tune it, not this clip.

The live path varied too, by less: 24.2–35.9% WER and 5–8 forced commits on
1.1.0 over three runs. **One run on this clip proves nothing.** Before you
compare two builds, run each several times and compare the spread.

## 16. The first window failed greedy decoding, and the random fallback was the only way out (2026-11-01)

This confirms the hypothesis in finding 15. It was measured on the 16 GB Mac mini
M2 Pro with WhisperKit 1.1.0, on the 57 s synthetic clip, offline, Balanced tier,
with no diarization.

The first 24.9 s window starts at full amplitude on sample 0. Its greedy decode
is refused at the first token by `firstTokenLogProbThreshold`, every time (an
empty result in about 0.44 s). WhisperKit then re-samples at temperatures 0.2 and
0.4 with an unseeded random number generator, and it has no seed option. In every
probe all three attempts failed their gates, and WhisperKit returned the last one
anyway. Over 30 production-configuration decodes of that window, 7 returned
nothing, 7 had less than half of their words in the reference (for example
"Thank you so much for coming"), and 16 were usable.

**Dead ends.** A deterministic ladder (`topK = 1`) loops ("Kalo mga mga…",
compression ratio 38). Disabling or relaxing the first-token gate,
`withoutTimestamps`, a 100 ms fade, and widening the window by 700 ms did not
help. Rejecting any result with a compression ratio above 2.4 and retrying cut
the collapses from 5 to 2 in 12 runs, but the median WER rose from 30.1% to
36.7%, and the rule rejected good text, so it was not adopted.

**Fix.** With 50–550 ms of silence in front of the window, the greedy decode
passes the gate and returns the same text every time. `OfflinePipeline.decode`
now runs the greedy step alone. If that step is refused with no text, it retries
with 250 ms and then 450 ms of silence in front. Any other outcome falls through
to the rest of the old ladder in the old order: the sampled retries, wider audio,
then halves. The live path is unchanged: a test asserts that every live request
uses the standard ladder at attempt 0.

**Result (interleaved, one series by the agent that wrote the fix, one by the
lead).** The agent's series: n = 20 per arm, collapsed first windows 7 of 20
against 0 of 20 (Fisher exact, two-sided, p = 0.008). All 20 candidate runs gave
24.2% WER with 120 words and the same text, and the baseline gave 24.2–70.3%.
The lead's series: n = 6 per arm, baseline 4 of 6 collapsed (WER 29.7–63.3%),
candidate 0 of 6 (24.2% in all six, identical text). The median RTF fell from 0.092 to 0.082
in the lead's series, and from 0.110 to 0.084 and from 0.099 to 0.082 in the agent's.
Process footprint was 126–133 MB against 129–136 MB. Model residency was not
measured.

**The baseline collapse rate depends on the session.** The same shipping build
collapsed in 1 of 12 offline runs in the benchmark agent's session (its own
collapse rule), in 7 of 20 in the ASR agent's, and in 4 of 6 in the lead's. The
agents used different collapse rules and the machine load differed, so the three
rates cannot be pooled as if they were one measurement. The candidate collapsed in
none of the runs in any session, and its transcript was the same each time.

**Left open.** English filler that does not trip any gate can still pass the
sampled ladder (1 of 30 baseline decodes, with a compression ratio of 0.81). A
window with very few words is not caught either. Every number here is from one
synthetic clip whose abrupt start is the cause of the failure, so none of it says
how often a real recording starts a window that way. A real recording needs
checking before this is called a fix for real use. The change only acts on a
window that was refused with no text, so a recording whose first greedy decode
passes behaves as before.

## 17. A quit, a crash or a kill made the whole archive unreadable (2026-11-01)

An m4a written by `AVAudioFile` is readable only after it is closed. A real
SIGKILL at 30 s left 241 KB with every sample in it, and `afinfo` reported
`AudioFileOpenURL failed` (`ffprobe`: `moov atom not found`). Nothing intercepts
quit, so a ⌘Q during a recording had the same result. Only the 16 kHz working
copy survived, and by default the app deleted it as soon as the user did what the
recovery message said, which was "transcribe it again". An AAC-in-CAF file opened
but could not be converted (`afconvert` error -66567), so that option was dropped.

**Fix, in two halves.** `ArchiveWriter` now writes through `AVAssetWriter` with 5 s
movie fragments. In 24 real SIGKILLs of the real writer at random times between
2.5 s and 12 s (16 mono, 8 stereo), every file was readable and at most 4.81 s was
lost. Killed files play in `AVAudioPlayer` and decode through `AVAssetReader`, and
a clean close holds exactly the frames written, at about 4% more file size. The app
side holds a quit until the recording is stopped and closed (`QuitGate`), deletes
the working copy only when the archive opens and holds at least as much audio
(`WorkingCopyPolicy`), and says what survived in the recovery message.

**Not covered.** A kill in the first 5 s, before the first fragment (1 of 12 in the
prototype). Power loss, because neither writer calls `fsync`. Archives that were
made before this change and never closed stay unreadable, and only their working
copy recovers them. A crashed two-lane recording keeps only the mixed working copy,
so it transcribes as one lane. The quit gate is unit-tested through its seam, and a
real ⌘Q during a recording was not driven. An independent review found three more
limits. First, the 30 s quit timer runs on the main actor, and Stop calls
`ArchiveWriter.finish()` synchronously on it, so a stalled encoder would freeze Stop
and the quit past the timer. A probe with a 0.1 s timeout and a stop that blocked the
main thread for 1.5 s replied after 1.51 s. Second, after a disk-low stop the archive
holds only what was written before it (4.0 s in a probe) while `frameCount`, and so
the stored duration, still reports the whole 60 s that was handed to it (the first two are fixed: finding 33). Third, a
quit between pressing Stop and the end of the save went straight through, because
the gate read the state, which leaves `.recording` at once. That one is fixed: a
second request now joins the stop in progress.

Two smaller fixes in the same area. After a sleep the first buffer reports the
whole sleep as a gap, and `fillGap` allocated it as one buffer per lane: an hour at
48 kHz raised the footprint by 770 MB, made one 115 MB chunk and held the capture
thread for 19 s. It is written in 1 s slices now, and any gap of 1 s or more raises
a notice. Interfaces at 88.2, 96 or 192 kHz were refused (the encoder offers nothing
above 48 kHz); they are archived at 44.1 or 48 kHz now.

## 18. The live ring buffer grew by the whole PCM rate (2026-11-01)

`Data.removeFirst` only moves the start of a slice over the same storage, and the
next `append` extends that storage, so the dead prefix is never freed. The live
decoder's ring held a window of about 145 KB and grew 112 MB an hour without bound
(671 MB over a simulated 6 h session). It was found by the audio agent and measured
again independently, pushing audio through the ring and trimming every 1.5 s as the
decoder does: the footprint grew 112, 222 and 332 MB after 1, 2 and 3 simulated
hours, and 0, 1 and 1 MB with the fix, at the same window size. The fix drops the
prefix into fresh storage. The regression test fails on the old code (37 MB of growth
in 20 simulated minutes against a 12 MB limit). Every other part of the capture and
decode path stayed flat in the simulated 1 h, 3 h and 6 h runs (about 1 MB an hour of
footprint growth). These runs used a scripted device, recognizer and voice-activity
detector, so they say nothing about the model's own memory.

## 19. Long transcripts slowed down quadratically, and finishing one could empty it (2026-11-01)

On an on-disk store, setting `row.transcript` before inserting the row made SwiftData
rework the transcript's whole `segments` list for each row. A 250-row batch cost
24 ms into an empty transcript and 3.6 s into one of 3,000 rows. Deleting the partial
rows one by one made the save grow with the square of the row count: 159 s for
`completeTranscript` at 15,000 rows (a six-hour meeting). `completeTranscript` also
saved the delete before the insert, so a failure between the two left the transcript
empty.

The fixes insert before linking, save the final revision first, and then delete the
partial revision by predicate. At 15,000 rows `completeTranscript` took 6.5 s and a
250-row append 84 ms. `TranscriptWriter` is built on the main actor in `AppState.init`,
so it runs on the main thread (finding 21), and the 6.5 s at 15,000 rows still blocks
the window at Stop (fixed in finding 32: the longest gap is now 22 ms). It was 159 s before. These are single debug-build runs on an
on-disk store by the agent that made the changes, so read them as the size of the effect and not as exact
timings. Related fixes in the same pass: a job whose transcript could not be saved is
no longer marked complete (and a failed job keeps its reason), live lines that stop
being saved are reported while recording, a running job steps aside and restarts when
a recording starts (it loses its progress, but it no longer competes with live
decoding or has its model unloaded), a request made while a cancelled run unwinds is
no longer dropped, and an empty diarization result no longer wipes the speaker names a
person chose.

## 20. FluidAudio 0.15.8 and 0.18.0 change nothing we measured, and reusing the first pass's embeddings loses turns (2026-11-01)

On 7 synthetic multi-speaker fixtures with known turn boundaries (`say` voices that
were measured to be far enough apart; `eval/make_multispeaker.py`, scored with
`eval/der.py`), on the Mac mini M2 Pro, with release builds, n = 5 per arm,
interleaved, with the network denied, FluidAudio 0.15.6, 0.15.8 and 0.18.0 produced
identical spans to the 10 ms, label for label, in the same time (1115, 1113 and
1115 ms) and the same footprint (164–165 MB, process footprint and not model
residency). Mean DER was 16.98% for all three. Every arm gave one distinct output
across its 5 runs, so speaker ids are stable run to run. Notero calls no symbol whose
signature changed in 0.18.0, and both versions build with zero warnings.

**Upgrading costs something.** On 0.15.8 and 0.18.0, a model cache without a revision
marker triggers a network check at first load. With the network denied, speaker
identification failed and the cache directory was deleted (once on 0.15.8, twice on
0.18.0). Online, the weights came out byte-identical. The same code path serves the
voice-activity model, which was not tested. This is the reason `Package.swift` keeps
FluidAudio on patch releases of 0.15.6. Version 0.18.0's default traits also compile
the text-to-speech code; `traits: ["Diarizer"]` removes it with identical output
(the release build of the benchmark tool was 12.0 MB against 24.6 MB).

**Reusing embeddings is faster and worse.** Three candidates re-used the first pass's
embeddings (chunk-slot embeddings from 0.18.0, segment embeddings, and a hybrid). The
time for speaker processing fell 39.5%, 39.4% and 17.3%, and the footprint fell to
124–146 MB. Mean DER rose from 16.98% to 24.44%, 18.56% and 18.11%, and the
speaker count was wrong on 2, 3 and 3 of 7 fixtures against 1 of 7 (a pair that every
arm fuses). On the fixture where Daniel and Tessa trade short turns, which reproduces
finding 10, the shipping path scored 8.5% DER and chunk-slot embeddings scored 49.8%,
the same as the first pass alone. The embedding-reuse candidates added a phantom third
speaker. With a stated head-count of four, the three candidates fell to 33.1% DER
because consolidation merged the wrong pair. None of them was adopted.

All of this is synthetic. No real recording and no real DER reference exist on this
machine, and the first pass drops turns under 1 s, which is why "missed" is large and
equal in every arm.

## 21. A `@ModelActor` that is called from the main actor runs on the main thread (2026-11-01)

A search was moved to a `@ModelActor` reader to keep a long meeting from stalling the
window. It did not work: the half-second search still ran on the main thread. The
first diagnosis, in this entry as first written, blamed the thread that *created* the
actor. That was wrong, and finding 32 corrects it: the thread that *calls* the actor
decides. Called from the main actor, a `@ModelActor` ran on the main thread 20 of 20
times whether it was created on the main thread or in a detached task. Called from a
detached task it was never on the main thread (0 of 20), whoever created it. The fix
here worked only because `SearchReader.search(_:in:)` creates the reader and calls it
inside the same detached task.

The test that was meant to catch it passed anyway, because its ticker never ran during
the search and a gap of 0 ms satisfied the assertion. The ticker now returns its own
measurement and the test asserts that it ticked. With the old call pattern restored it
fails, and with the fix the longest main-actor gap was 15 ms during a 0.17 s search.

`TranscriptWriter` and `TranscriptReader` had the same problem, and finding 32 records
the fix.

## 22. "Peak memory" was a footprint read once at exit, and the model is not in the footprint (2026-11-01)

`transcribe` printed `phys_footprint` once, when it finished, under the label
"peak memory". That is neither a peak nor the model's memory. Measured on the Mac
mini M2 Pro with `footprint(1)` and `/usr/bin/time -l`: after the default model
loaded, the footprint was 76–77 MB, while the Neural Engine memory that the process
owned was 1580 MB (`footprint(1)` reported 1581 MB, as "neural, nofootprint"). The
lifetime peak footprint over 24 runs was 150 MB (142–254), and the footprint at exit
was 138 MB (89–248). The README's "approximately 300 MB" came from this reading. The
tool now reports the lifetime peak footprint and the Neural Engine memory separately,
and `eval/residency.py` takes an independent reading from outside the process. A
smaller footprint is not lower model memory: the model is somewhere the footprint does
not look. Compare footprints only between stages of one build, and quote the Neural
Engine figure when the claim is about the model.

## 23. Windows that needed the retry ladder scored better, and an A/A run was "significant" (2026-11-01)

In 24 offline runs of the synthetic clip on the shipping build, 9 runs had a window go
through the retry ladder and scored 21.1–28.9% WER. The other 15 did not and scored
30.5–57.8%, and all four collapsed runs were among those 15. That is an association
and it fits finding 16, which found the mechanism. It was measured before that fix.

The harness (`eval/bench_runs.py`) was calibrated against itself. Two byte-identical
binaries, live, n = 8 per arm, differed significantly on WER (+2.3 points, p = 0.041).
A 17% timing difference between two builds at p = 0.003 in one session came out as 1%
(p = 0.73) in a repeat, because the machine was shared and not because the builds
differ. The verdict line now adds "CONFIRM BEFORE ACTING" to any significant result
below 12 runs per arm. A result at n < 12 needs a second session before it is acted on.
The fix in finding 16 was confirmed in a second session for this reason. All 24 live
runs also contained no pause boundary, so the 12 s commit latency measured on this clip
says nothing about a recording with pauses.

## 24. P6 changes nothing on real read Tagalog, and long-form costs no accuracy (2026-11-01)

Measured on the Mac mini M2 Pro with FLEURS `fil_ph` (the public Filipino test set,
CC-BY-4.0; **read Tagalog, not Taglish**), Balanced tier, forced `tl`, load average
median about 2 (0.7–13.6). The tarball hash matches the one Hugging Face publishes. The
subset is 100 utterances (2,838 words) chosen with a fixed seed.

The pre-P6 build (`addf5f8`) and the P6 build gave **byte-identical transcripts on 100 of
100 utterances** (WER 11.1%, confidence interval 9.6–12.6), on 40 of 40 utterances that
were cut to start abruptly (median 0.13 s cut, WER 10.7%) and on every long-form run, with
no window retried and none empty. Decoding was deterministic: 0 of 20 utterances differed
on a repeat, and 8 runs per arm of the two long-form files gave one transcript each. The
long-form files (250 s and 330 s, 10 and 14 windows) are the same sentences joined with
0.3–1.5 s gaps, so they are constructed and not meetings. Decoding them whole cost nothing
against decoding the sentences one at a time (8.3% against 8.0%, and 13.1% against 13.7%).

FLEURS recordings start within a median 0.13 s of speech, so the abrupt-start collapse of
finding 16 does not reproduce on them. The result therefore shows that the P6 change does no
harm on real voices and never fires on them. It does not show that the change helps on real
recordings, and it says nothing about Taglish.

**Code-switch evidence.** `langscore` counts 192 reference tokens as English (6.9% of 2,793
words). A hand-made list of 58 Tagalog words that spell like English ones
(`eval/fleurs_tagalog_collisions.txt`, which a native reader should check) leaves 134
tokens, mostly English terms and foreign names read inside Tagalog sentences. The error
rate was 9.9% on 2,571 Filipino words, 17.9% on those 134 English tokens (24 errors,
Wilson interval 12–25%), and 11.2% at 277 code-switch points. These are not code-switching
accuracy figures for meetings and must not be read as one.

## 25. On read Tagalog, `auto` equals `tl`, Fast equals Balanced, and Best is not better (2026-11-01)

Same data and machine as finding 24 (30 utterances for the tier comparison, 40 for the
language comparison). With `auto`, the text was identical to forced `tl` on 40 of 40
utterances, at the same speed (median RTF 0.066), so the 23-point gain of forced `tl` in
finding 11 came from the Indonesian voice of that clip and not from Tagalog speech. `auto`
reported `en` for 2 utterances and `id` for one window and still wrote the same Tagalog
text. The reported language may not be the one the decode used, and this was not checked.

Fast scored 9.3% against 9.7% for Balanced (confidence interval −1.4 to +0.4 points) and
was not faster on this Mac (RTF 0.081 against 0.065). Best scored 10.0% against 9.75% on
29 utterances, at about four times the decode time (RTF 0.254). On one 34.7 s utterance
(63 words) Best failed in all 8 repeats, on both builds (WER 30–86%, a mangled first
window), while Balanced scored 9.5%. Which build was worse was not distinguishable
(p = 0.34, n = 4 each). The Balanced row of the tier comparison was not interleaved with
the tier runs and ran under heavier load (median 4.6), so the speed ratios are indicative.
Forced `tl` stays the default, and the Best tier has no measured accuracy advantage.
Nothing here was measured on Taglish.

## 26. Live commit latency is the wait for agreement, not the decode; and where the dropped hops come from (2026-11-01)

FINDINGS 11 left three questions about the live path open: why commits take ~12 s, why hops are dropped, and
whether `inferMs` understates the cost of a decode. `LiveDecoder` now has an opt-in `trace` hook (nil by
default) that reports every decode with its phases, every dropped hop, every VAD batch and every commit on one
clock. Replayed in real time (absolute-clock pacing, the same decoder the app and `transcribe --live` use),
through the bench lock, strict LocalAgreement (the baseline arm of an interleaved A/B), n = 12 per clip, other
processes using a median 0.8-0.9 cores (0.2-2.5) while it ran:

| Real-time replay | paused Taglish (85 s, 24 x 1.2 s pauses) | three-voices (en, 125 s) | two-distinct (en, 102 s) |
|---|---:|---:|---:|
| WER, median [min..max] | 41.4% [33.6..46.9] | 11.5% [9.3..13.8] | 3.7% [3.7..3.7] |
| words committed / words in the script | 117 / 128 | 290 / 312 | 298 / 301 |
| **whole-run RTF** (replay wall incl. final flush / audio; ~1 by construction) | 1.015 | 1.005 | 1.006 |
| whole-run RTF with every decode awaited (n = 8) | 0.85 [0.79..0.90] | not run | 0.50 [0.50..0.50] |
| **per-hop decode wall**, median / p90 | 1,070 / 1,816 ms | 728 / 1,223 ms | 691 / 895 ms |
| decodes longer than the 1.5 s hop | 22% | 7% | 0% |
| decoder duty cycle (decode wall / session) | 0.69 | 0.55 | 0.49 |
| dropped hops, median [min..max] (share of attempts) | 8 [3..13] (13%) | 6 [2..13] (8%) | 0 |
| forced commits / unagreed tail words | 4 / 24 | 4 / 5 | 1 / 2 |
| boundaries closed / final decodes / abandoned | 3 / 12 / 18 | 0 / 0 / 1 | 1 / 3 / 4 |
| **end-to-end commit latency** (word end to committed, wall), median / p90 | 8.7 s / 17.0 s | 5.2 s / 16.0 s | 3.0 s / 8.0 s |
| pause to last word committed, median | 7.6 s | 6.2 s | 1.9 s |
| collapsed runs (benchstats rule) | 0/12 | 0/12 | 0/12 |

Offline whole-file RTF for the same model is ~0.15 (FINDINGS 11, not re-measured); the live path costs 3-6x that
because every hop re-decodes the active window. Three numbers, three questions. The whole-run RTF says the machine
keeps up (1.0 in real time). The per-hop decode wall says how much of each 1.5 s hop is spent (0.5-0.7). The commit
latency says what the user waits for (3-17 s). Only the last is bad, and it is not the decode.

**Where the latency is.** Each committed word's latency splits into A, the wait for a hop to cover it; B, the wall
time of the decode that first covered it; C, the wait from that decode to the commit:

| median ms | A hop wait | B decode | C agreement or boundary | total | C share |
|---|---:|---:|---:|---:|---:|
| paused | 923 | 1,080 | 5,885 | 8,277 | 71% |
| three-voices | 842 | 761 | 3,070 | 5,212 | 59% |
| two-distinct | 742 | 694 | 1,509 | 3,039 | 50% |

C dominates, and its tail is the forced commits: a word that waited for the 15 s window cap has a median C of 15.2
(paused) and 15.9 s (three-voices). The floor of LocalAgreement-2 at a 1.5 s hop is A + B + one more hop and decode,
about 3 s, and two-distinct sits on it.

**What blocks agreement.** Strict agreement compares prefixes, so a first word that two passes hear differently holds
back everything after it. On the baseline traces 65% of comparable hops (15 of 20 per run on paused, 18 of 30 on
three-voices) had an agreed prefix of zero. The partials show it: `Dens, ok. Kai, muhang nandito`, then `s, ok kai,
muhang nandito`, then `dan s, ok kai, muhang nandito`: three passes, one stable tail, a different first word each time,
nothing committed. The window then grows to the cap, and Whisper decodes a 15 s window worse than a short one: on
three-voices a 17 s turn lost "short outage turned into forty minutes of degraded service" in the first baseline runs.
Over all twelve, 11% of the words in long turns that follow a pause of 700 ms or more were deleted against 2% after
shorter gaps (two-distinct: 2% against 1%). It is not the pause filter: the confirmed pauses never overlap speech.

**What is not the cause.** The decoder's wall time minus `inferMs` is a median 1.0 ms (p99 3.0, max 16) over 6,189
decodes; the main-actor wait before a decode starts is under 0.6 ms, the work after the model returns under 0.5 ms,
the VAD lags 0.7 ms (max 20) and its 300 ms batches never queued; the main actor stalled for more than 16 ms 0-2
times per run (max 50 ms); an ingest call takes 0.5 ms. With 50% of every 16 ms frame burned on the main actor (n = 3,
three-voices) nothing moved: WER 10.9 against 11.5, dropped hops 6 against 6, commit latency 5.2 against 5.2 s, decode
wall 709 against 728 ms; the schedule delay rose to 8 ms. So FINDINGS 11's explanation for the adaptive hop's failure,
that `inferMs` understates the wall cost, is not supported: it understates by a millisecond. What predicts a dropped hop
is the decode itself: after a decode under 1.0 s the next exceeds 1.5 s in 4% of cases and 1.0 s in 14%, so a hop
shortened to 1.5x the last decode was overrun 12% of the time. Not carried by this replay: SwiftUI rendering and the
`@Observable` writes (level, elapsed, meter and stats, ~12 per second), SwiftData persistence per commit, the
AVAudioEngine tap and the archive writer. A multi-hundred-millisecond UI hitch would delay a hop by that much; none
was tested.

**Where the drops come from.** A tick that lands during a decode is dropped and the timer resets, so a decode over
1.5 s costs a 3.0 s gap. Every drop sits behind a decode of 1.8 s (paused, median; 50 of 95 behind a final) or 2.8 s
(three-voices; 36 tokens, a ~10 s window), while ordinary decodes of the same windows take 0.7-1.1 s. The hypothesis
is the temperature-fallback ladder re-decoding a window whose greedy pass failed a gate (`WhisperEngine.sampling`
allows two retries, and its own comment measures that gate firing on 16-37% of hops); the trace does not record the
attempt count, so this is not proved. Decode wall grows with window length only mildly (0.66 s at 3-6 s, 0.76 at 6-10,
0.93 at 10-15, 1.2 s above 15), so the floor is the encoder and a shorter window buys little.

**Pauses almost never finalize.** The VAD hears 256 ms chunks, so 700 ms of silence is 768 ms and is confirmed a
median 0.9-1.0 s after the pause starts; the final decode then takes 0.65-1.7 s. Of 288 pauses of 1.2 s on the paused
clip, 30 closed inside the pause, 88 had their final decode return after speech resumed (abandoned), 62 started no
final, 108 were never confirmed. On the two multi-speaker clips 0 of 264 gaps of 0.7-1.5 s closed and 204 were never
confirmed. In conversation the text arrives by agreement and by nothing else.

**Phantom words (FINDINGS 12 follow-up).** Across 128 runs (28,314 committed words) 266 words are insertions against
the script and 9 of those are timed inside a known silence; none repeats the preceding words, none is a stock filler,
and they are misheard words at pause edges ("dan" before "s, ok kai", "It," after a sentence). No fix is warranted
and none could be made to fail a test. No hop was ever decoded with no new speech since the previous decode (0 of 7,386
considered; `skippedSilent` fired 77 times where it should).

## 27. Head-tolerant agreement cuts the wait by 35-43% on two synthetic clips and is implemented but off; catch-up and a 10 s window do not help (2026-11-01)

Each candidate ran against an interleaved baseline arm in the same lock ticket, with the acceptance rule written
before the first run: median commit latency >= 10% lower with one-sided p < 0.10; WER, forced commits and duplicated
words no higher; no collapsed run; dropped hops not more than 20% higher.

**Head-tolerant agreement (implemented, off by default; see the decision below).** When two passes disagree on the first word but
agree on a run of 3 or more words starting within 3 words of each head, commit that run and the newest pass's own head
words. Committed text is still only appended to; `CommitImmutabilityPropertyTests` and `LiveDecoderPropertyTests`
check, over hundreds of random scripted recognizers, that a committed prefix never changes, no word is committed
twice or out of order, and nothing is stamped past the audio. The setting came from the baseline traces, never from the
candidate's own runs. n = 12 per arm:

| | median commit latency | p90 | forced | WER | partial rewrites per update |
|---|---|---|---|---|---|
| paused | 8,680 -> 4,978 ms (-43%, p = 0.006) | 17,032 -> 11,720 (-31%) | 4 -> 0 | 41.4 -> 40.6% | 2.99 -> 1.83 (-39%) |
| three-voices | 5,169 -> 3,366 ms (-35%, p < 0.001) | 15,956 -> 6,352 (-60%) | 4 -> 0 | 11.5 -> 8.0% | 2.39 -> 1.61 (-33%) |
| two-distinct | 3,036 -> 2,985 ms (-2%) | 8,027 -> 3,712 (-54%) | 1 -> 0 | 3.7 -> 3.3% | 0.16 -> 0.16 |

It commits 1-9 words per run on one pass's say-so, against dozens of forced commits in the baseline, and it shortens the
active window, so per-hop decode wall falls too (paused -15%, three-voices -6%). The partial flicker falls as a side
effect. Against the written rules: two-distinct fails the 10% median bar (it sits at the 3 s floor, only its p90
moves) and its dropped hops go from 0 to 2 in 8 of 12 runs, every one behind a single 3-6 s decode of the same 5.7 s
window at 64 s that the new window alignment happens to reach. Every rule passes on the other two clips. The clips are
synthetic (a `say` voice reading Taglish; two English multi-speaker mixes), the twelve rounds are one long session on a
shared machine, and no real Taglish was available: this wants a second session, preferably on real audio.

**Catch-up on a dropped hop (rejected; n = 8).** Start the next decode as soon as the slot frees instead of a full hop
after the dropped tick. Paused: median commit latency +27% (7,555 -> 9,608 ms; no sign of improvement, one-sided
p = 0.74), forced commits 4 -> 6. Three-voices: -11% (p = 0.12) but WER 11.5 -> 13.0% and forced commits 2 -> 3. The
decoder did not get faster; it started the same slow decodes sooner.

**A 10 s active region instead of 15 s (rejected; n = 6).** Median commit latency -36% on paused (p = 0.056) and -12% on
three-voices, but the paused WER median rose 37.9 -> 40.2% and three-voices forced commits rose from a median of 3
to 6 (p = 0.017 that they rose). It buys latency by committing without agreement more often, which head-tolerant agreement does not.

**Not worth doing.** Skipping silent hops (nothing to skip, above); a cheaper hop window (the encoder is the floor); a
separate display-only stabiliser for partials (head-tolerant agreement already removes a third of the flicker).

**What is left.** On easy audio, the 3 s floor of LocalAgreement-2 at a 1.5 s hop. On hard audio, decodes that run to
2-3 s when the ladder re-decodes (the engine's, not the decoder's), and a boundary that needs a pause of 2.5 s or more
to close. The next experiments, in order: a second session confirming head-tolerant agreement, on real audio; a cap on
the ladder for live hops (WhisperEngine); a silence threshold below 700 ms together with a final decode started before
the pause is confirmed.

**Decision.** `SessionConfig.headTolerance` is 0, which is strict LocalAgreement as before, and the
feature is implemented and tested behind it. Head-tolerant agreement commits up to three head words
per event on one pass's say-so, in front of a run that two passes agree on, and drops the older pass's
differing head words. That is less than a forced commit, which also commits without agreement, but it
is still a trade of agreement for latency, and the older pass could have been the right one. The
evidence is two synthetic clips in one long session on a shared machine, one of three clips missed
two written rules, and no real recording was available. By the decision rule of finding 34, one
session suspects and a second confirms. A test pins the live defaults, including the tolerance of 0.
To turn it on after a second session on real audio, change the default in `SessionConfig` and the pin.

## 28. A speaker's name followed the label number, not the voice (2026-11-01)

A segment holds a label (`S1`) and the name a person typed lives on the row for that label.
`SegmentMerger.normalize` numbers the labels by who speaks first, and that changes between two
runs over the same audio, so "Maria" moved to whoever was `S1` in the new run. ARCHITECTURE
said the rename "stays correct" after Transcribe Again; it did only while the numbering held.

**How often the numbering changed.** 7 synthetic fixtures (`eval/make_multispeaker.py`), the
first run renamed after the voice each label actually is, then 52 re-runs of the same audio
(`eval/speaker_stability.py`, `diarbench --carry-from`), none of them a second pass over a
different recording. The numbering of at least one voice changed in 12 of 52 (23%):

| re-run | voices renumbered |
|---|---|
| same audio, same settings | 0 of 7 fixtures |
| AAC round trip through the archive's codec (48 kHz, 64 kbit/s) | 0 of 7 |
| room noise added at -40 dBFS | 3 of 7 |
| the opener muted (a turn under a second dropped) | 4 of 7 |
| Fast mode instead of Accurate | 2 of 7 |
| head-count stated, true | 0 of 7 |
| head-count stated, one too few | 2 of 3 fixtures with three or more voices |
| head trimmed (the timeline shifts) | 1 of 7 |

**What it did to the names.** In the 38 re-runs that kept the timeline and differed in some way,
the name stayed on the label number for 28.2% of the speech, so 28.2% of it sat under another
person's name. With the opener muted it was 57.5%. A re-run with nothing changed puts 7.4% under
a wrong name for either policy, which is the diarizer's own error and the floor.

**Fix.** `SpeakerMatching` (pure, `TranscriberCore`) decides by the overlap in time between the
old transcript's lines and the new run's spans which new speaker is which old one. A pair is
matched only if it is mutual (each is the other's best by 2x), the overlap is at least 2 s, and it
covers half the smaller speaker. An even split, an even fusion, or a shifted timeline is left
unmatched and the old name stays off the new speaker. `applySpeakers` applies it: a matched
speaker takes its predecessor's label, name and colour; a speaker with a typed name that nobody
inherits stays in the roster with no talk time instead of being deleted; any other speaker keeps
the label it came with unless that label is taken. On the same 38 re-runs: 6.3% of the speech
under a wrong name (the floor is 7.4%), 10.4% under no name (declined), and in no single run
more wrong than before. With the opener muted: 94.3% right.

**Tests.** 30 pure tests (swapped labels, a speaker that disappeared, a new one, two merging, one
splitting, ties, a shifted timeline, and two properties over 200 seeds each) and 21 store tests,
9 of the first 13 of which fail on the old code. Each rule was mutated away to show a test
notices: 10 of 10 in `applySpeakers` and the matching, 4 of 4 in the Transcribe Again helper. One
older test, which split a merged speaker three and three, now documents the new rule: the
target does not inherit its name by a coin flip.

**Not done, and why.**
- Transcribe Again is covered by `TranscriptWriter.carriedSpeakers`, called from
  `storeTranscript` and `completeTranscript` as well (applied by the lead after the merge).
- A line a person moved by hand cannot be told from one the diarizer placed: nothing stores which.
  Identify Again re-places every line, as before; the moved line still counts as the territory of
  the speaker it was given to when matching. Needs a flag on `StoredSegment`.
- The speaker count (sidebar, "found N speakers for M persons") counts a kept name with no lines.
- A timeline that shifts (trimmed audio) matches nothing, by design: 78.9% of that speech is
  unnamed, 5.0% wrong, against 27.8% wrong before.
- Centroid distance is not available through `SpeakerDiarizing`; the evidence is time only.

All of it is synthetic. How often real meetings renumber is not known.

## 29. Similar voices: the turn boundary, not the threshold, decides (2026-11-01)

**Where the errors are.** On the 7 fixtures the first pass leaves 17 turns of a second or more
with no span at all, and bridges every gap up to 0.36 s between two voices: in `two-similar`, 7 of
18 spans each cover turns of both voices, so no clustering threshold reaches them. Missed speech
is not only backchannels. Of 72 s of turns missed, 15 s are under a second and 20 s are 1-2 s;
38 s are turns of one quiet voice (Albert, one of 17 s) that the segmentation never saw.
`config.minSilenceGap` is declared by FluidAudio 0.15.6 and never read: setting it did nothing.

**Method, written first.** `eval/tuning_verdict.py` (commit 2bd4680, before any sweep) is the
rule as code: a candidate passes a set if mean DER falls 2 points (or a wrong speaker count is
fixed with no worse mean), with no new merge, no phantom speaker, no fixture's missed speech
more than 0.5 point up, no instability, no fixture more than 3 points worse and speaker
processing within 10%. A threshold is accepted only if it passes the set it was chosen on
(7 fixtures + 12 near-twin pairs) and a hold-out set (5 fixtures + 12 pairs, other voices and
seeds, chosen by embedding distance and not by outcome). The grid was fixed in the same file.

**Tuning set, one run per cell (the 19 fixtures; baseline mean DER 26.15%, 8 wrong speaker counts):**

| arm | mean DER | verdict |
|---|---|---|
| mergeGapMs 120 | 23.64 | fail: missed +0.6-0.8 on 3 fixtures |
| mergeGapMs 0 | 21.24 | fail: missed +0.5-1.0 on 5 (but fixes 2 fused pairs) |
| min speech 0.6 s | 23.72 | pass |
| min speech 0.4 s | 25.26 | fail: two voices merged into one, one fixture +41.5 |
| foundingTurnMs 1500 / 1000 / 3000 | 26.15 | no gain, no change at all |
| sameSpeakerDistance 0.65 / 0.75 | 26.15 | no gain, no change at all |
| sameSpeakerDistance 0.60 | 23.85 | pass, by one fixture; **fails hold-out: no gain. Rejected as overfit** |

**Candidates designed after seeing that table** (so the hold-out is their only test): the merge
before clustering switched off and a join of same-speaker spans after it (`gap0post250`), and its
combinations. All n = 3 runs on 36 fixtures; every arm gave one distinct output per cell.

| arm | tuning DER | hold-out DER | speaker-count errors (tune / hold) | time, lock-held, n = 5 | verdict |
|---|---|---|---|---|---|
| baseline | 26.15 | 8.54 | 8 / 1 | 2090 ms | |
| min speech 0.6 s | 23.72 | 6.42 | 8 / 1 | +5.7% (long file +6.7%) | passes the rule; not adopted (below) |
| gap0post250 | 20.85 | 4.82 | 6 / 0 | +11.3% (long +12.3%) | **reject: over the 10% limit** |
| both | 18.24 | 2.47 | 6 / 0 | +20.2% (long +20.4%) | reject: time |

`gap0post250` removes nearly all confusion (hold-out 3.74% to 0.04%) and fixes a fused pair on
the hold-out (49.8% to 4.4%); it costs more because every first-pass segment is embedded alone.
It misses the rule by 1.3 points of time. `min speech 0.6 s` halves missed speech (6.7% to 3.6%,
4.8% to 2.4%) and puts 98 spans under a second in the output where there were none, so a
backchannel inside a sentence now splits the transcript line.

**Fast mode.** The same 0.6 s in Fast mode, which has no second pass, adds phantom speakers on
4 of 12 fixtures (count errors 3 to 6), so it fails the rule there. FluidAudio's minimum is a
`let` of its manager; the engine now builds one manager per mode and only Accurate uses 0.6 s.

**Head-count.** A correct or too-high count changes nothing (mean DER 16.98%, as in finding 20).
One too few merges real people: four-voices 16.8% to 30.8%, three-overlap 14.8% to 23.5%.
A consolidation distance of 0.75 instead of 0.85 stops one of the two merges (three-overlap) and
not the other (the pair is closer than 0.75). The count never fixed a wrong speaker count, because
it only merges. No fixture has a fragmented voice, so the case it exists for is unmeasured: not
adopted.

**Overlap.** `three-overlap` has 2.2 s of overlapped speech in 86 s, almost all of it inside the
0.25 s collar. It says nothing about overlap attribution.

Everything is synthetic, the pairs are near-twins in a text-to-speech sense and not in a human
one, and one-label spans cannot represent overlap.

**Decision.** The 0.6 s minimum passes the rule that was written first, on synthetic voices, and it is not
adopted: `Tuning.firstPassMinSpeechSeconds` stays at 1.0 s. The minimum of 1.0 s exists so that a
backchannel inside someone else's sentence does not split a transcript line (the comment in
`SpeakerEngine.prepare`), and clean synthetic boundaries cannot show that harm. The change put 98
sub-second spans into the output, and the same value added phantom speakers in Fast mode. It needs a real
recording before it becomes the default. The per-mode manager and the `Tuning` knob stay, so the change is
one value and its pin test. The post-cluster join (`gap0post250`) misses the time limit by 1.3 points and
is also not adopted.

## 30. Every model load asked the Hub, the app measured and released the wrong memory, and a switch held two models (2026-11-01)

Measured on the Mac mini M2 Pro with the default model, interleaved, with a load average of
0.8–11 at launch. A load with `download: true` and no folder lists the Hugging Face Hub's
files every time. That cost 7 of the 8.6 s: a warm load was 8.64 s (8.23–16.04, n = 15), and
loading from the model folder is 1.61 s (1.58–2.05, n = 16), with byte-identical transcripts
(10 of 10) and the same 1,580 MB. The lead repeated it on a quiet machine (load average 0.7–0.9, n = 5
per arm, interleaved): 8.5–9.6 s against 1.53–1.55 s, the same transcript, the same decode speed.
With the network blocked by a sandbox, the old path crashed and the new one loaded. Real airplane
mode was not tried. Time to first token fell from 10.0 s to 2.9 s, and a reload after an unload
from 8.10 s to 1.58 s. A cold compile took 160 s for the default model, 82 s for Fast and 158 s for
Best (n = 1 each).

The default model is 66–77 MB of process footprint and **1,580 MB of wired Neural Engine memory**
(Fast 878 MB, Best 3,000 MB; 69 of 69 loads gave 1,580). The Benchmark view's memory column,
Settings' "In use now" and the "Release the Models from Memory" button all show or release the
footprint, so they describe the wrong thing. `BenchmarkRun.modelResidencyMB` now carries the
residency; the views were not changed. A switch used to hold both models: the Neural Engine peak was
2,458 MB for Balanced to Fast and 4,581 MB for Balanced to Best. The old model is now released first
and the peaks are 1,580 and 3,000 MB (−36% and −35%, no spread). The cost is that pressing Record while a job is
loading another model always reloads the live model.

The "approximately 200 MB" that the docs and app comments gave for the speaker models was never
measured. They are 13 MB on disk, 0 MB on the Neural Engine, and +23 MB of footprint when loaded.

## 31. Cancelled and failed jobs left the speaker models loaded, a cancelled waiter held Record, and what did not help (2026-11-01)

Finding F13 of the audit is real but small. A cancelled or failed job left the speaker models
loaded after the run; on real engines that was about 20 MB of footprint and nothing on the Neural
Engine (n = 3, indistinguishable from noise). The queue now releases them after every run; 4 of
the 6 new tests fail on the old code. A caller that was cancelled while it waited for a model load
now leaves at once and no longer inherits the owner's cancellation (4 of 4 tests fail on the old
code); loads are still not cancellable once they start. A failed switch no longer brings back a model
that was released in the meantime, and a failed load with a corrupt encoder leaves no half-loaded
model (peak 1,092 to 878 MB, n = 4). Pressing Record with a job on the same model: the job steps aside
in 21 ms (median) and the first hop comes 2.09 s later (n = 6).

Rejected with numbers: putting the encoder, the decoder or both on the GPU is 51%, 51% and 79%
slower (n = 5, ranges never overlap), and the memory moves from the Neural Engine into the footprint
with the total unchanged. Fast was not faster on this Mac. Turning prewarm off saves at most 0.6 s
of a 1.6 s load, and its cold-cache safety was not measured, so prewarm stays on. Releasing the
ASR model when idle would give back 1.58 GB of wired memory for a 3.5 s reload to first token; that
is a product decision with app wiring. Two measurements never ran because the benchmark lock never
reached them: the cold-cache peak with prewarm off, and Record-to-first-hop with the final code.

## 32. A `@ModelActor` runs on its caller's thread, so moving the writer needed plain actors and an explicit refresh (2026-11-01)

Called from the main actor, a `@ModelActor` ran on the main thread 20 of 20 times whether it was
created on the main thread or in a detached task, and called from a detached task it was never on
the main thread (0 of 20). This corrects finding 21, which blamed the creating thread. The
consequence was that `TranscriptWriter` and `TranscriptReader` stalled the window whenever the app
called them: the longest main-actor gap at Stop was 6,920 ms at 15,000 rows and 400 ms at 2,000
(debug build, on-disk store, load about 10, n = 1 per cell). The writer, the reader and
`SearchReader` are now plain actors, so no caller can bring the stall back, and the same gap is 22 ms
and 15 ms (546 and 35 ticks; the tests assert that the ticker ran).

Moving the writer off the main thread changed one behaviour: a `@Query` view is current at the moment
the writer's call returns about half the time (32 of 60, and 306 of 600 in a longer run) instead of
always, and always within 7–11 ms. So `AppState` calls `RecordingStore.refresh` (three small fetches,
1.3 ms on 6,000 rows) before each re-read. Re-measured with the writer off the main thread, 600 cycles
per pattern: 0 stale reads for fetches (`attachAudio`, status, warning, `appendPartial`, the sidebar
fetch and relationships), for revision swaps (`completeTranscript`, `replaceSegments`,
`applySpeakers`, 300 cycles) and for `refresh`. A row held on the main context does not see another
context's save until the main context fetches again, before and after the change. The earlier
300-of-300 read-after-write result had been taken with the writer on the main thread and did not carry over.

## 33. Closing the archive, filling a gap and killing early (2026-11-01)

Stop's `finishWriting` wait ran on the main actor and froze the quit gate's own timer. It now runs off
the main actor with a 10 s bound (the archive writer's own wait is bounded at 30 s). A test with an
archive double that really hangs: the old code ticked the main actor 7 times with a 3,017 ms gap; the
new code ticked 47 times with a 15 ms gap, and Stop returned at 0.52 s. After a disk-low or failed
write, `ArchiveWriter.frameCount` is what the file holds (288,000 frames were reported against 192,000
in the file before). The stored duration stays the recording's true length, because the working copy
holds all of it. A 10-minute device gap held the capture thread 3.6 s with one lane and 10.8 s with two in a debug
build, and 0.09 s and 0.56 s in a release build (n = 1); the silence now goes on a queue, and audio
that arrives behind it is queued after it, which brings the hold to 0.000 s (n = 5). The alignment of the soak markers is
unchanged (0.12 ms in the working copy, 0.06–0.08 ms in the archive).

A kill in the first 5 s lost the whole archive (9 of 10 real SIGKILLs). The first fragment is now written after 1 s, and
1 of 10 was lost (the one at 0.8 s). The later fragments keep their 5 s spacing, and the cost was 52 bytes
on a 120 s file. A two-lane recording whose archive cannot be opened now transcribes from the mixed copy as one lane,
with a warning, and the lanes are stored at the start of the recording. Soaks with a scripted device (frozen snapshot, debug build):
1 h, 3 h and 6 h, 354 to 2,154 markers, the footprint slope is flat (the 1 h figure of 10.3 MB per hour is a fit
artefact; the peak is 25–26 MB in all three). No result here is from real hardware: the machine has no audio input
device, and the built app opens the user's real store, which the data rules forbid, so the kill tests ran against a
child process holding the real `ArchiveWriter`. A quit at the instant of model preparation was not tested.

## 34. The harness was not trustworthy at n = 8, so the decision rule changed (2026-11-01)

`eval/regress.py` compares two builds over a defined suite in one command, with one collapse rule and
one decision rule. The collapse rule: a run collapsed when its WER is more than 15 points above a pooled
level, or it produced fewer than 75% of the reference words, or it contains a filler phrase. It flags the
57.0% filler run that the earlier rule missed, and the 15-point margin sits in the empty gap of the 80
P6 runs (the largest normal excess was +10.9, the smallest collapsed one +26.2). A multi-metric table
read without correction flagged 10.8–23.8% of simulated A/A sessions as different (2,000 resampled
sessions per pool at n = 8). The shipped rule (a rank-sum permutation, Holm correction over every
metric, effect-size floors, timing believed only on a quiet and balanced machine, and a second session to
confirm) flags 1.7–2.6% (upper 95% bound 3.4%), and two agreeing sessions flagged 0 of 2,000. The cost is power:
a 10-point WER shift is seen 29–100% of the time depending on the pool, and a 10% shift in RTF only 3–24%.

One real session (`eval/baselines/sessions/quick-ab-addf5f8-vs-57dcc14/`, n = 8, through the lock; the
DER half and a real A/A were not run). Offline WER fell from 34.4% [30.5–58.6] to 24.2% [24.2–24.2] with 8 distinct
transcripts against byte-identical ones (p after Holm 0.002, a suspected improvement, load median 6.4, so the
−10% RTF is not believed). Collapsed runs were 3 of 8 against 0 of 8 (Fisher p = 0.20, not significant). Live,
on a quiet machine (load 1.2), nothing was significant (WER 28.1% against 26.2%, p = 0.12), and both builds were
nondeterministic live. The baselines of the first cycle are committed in `eval/baselines/`, so the next
cycle compares against files and not against `/tmp`.

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
