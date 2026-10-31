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
real ⌘Q during a recording was not driven.

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
250-row append 84 ms. These are single debug-build runs on an on-disk store by the
agent that made the changes, so read them as the size of the effect and not as exact
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

## 21. A `@ModelActor` created on the main actor runs on the main thread (2026-11-01)

A search was moved to a `@ModelActor` reader to keep a long meeting from stalling the
window. It did not work: `isMainThread` was true for a reader created from a
`@MainActor` method and false for one created in a detached task. The app target's
default isolation is the main actor, so `AppState.makeSearcher()` built the reader on
the main thread and the half-second search still ran there. The test that was meant to
catch it passed anyway, because its ticker never ran during the search and a gap of
0 ms satisfied the assertion. The reader is now created inside a detached task
(`SearchReader.search(_:in:)`), and the test asserts that the ticker ran. With the old
call pattern restored it fails, and with the fix the longest main-actor gap was 15 ms
during a 0.17 s search.

`AppState.makeReader()` creates a `TranscriptReader` in the same way and probably has
the same problem, which would mean the transcript loads that were described as off the
main actor run on it. That was not measured and not changed.

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
