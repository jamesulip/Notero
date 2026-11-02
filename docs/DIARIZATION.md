# Speaker diarization: evaluation and the Nemotron 3 experiment (2026-11-02)

**Decision: keep the shipping backend (pyannote segmentation with WeSpeaker embeddings) as the
default.** The experimental Nemotron 3 backend did not pass the gate that was written before the
first run. It failed two checks:

1. On the AMI meetings with the manual-annotation references, its DER is the same as the
   baseline's (24.1% against 23.7%), not 15% lower.
2. On one synthetic hold-out file, it merged two similar voices that the baseline kept apart.

The experiment found a large and consistent gain in *who spoke* on real conversation. That gain is
the reason to continue the work (see [Before a replacement](#before-a-replacement)). It does not
justify a change of the default now.

This file keeps three kinds of statement apart:

- **Measured:** computed in this run. The files are listed under [Reproduce](#reproduce).
- **Published:** a claim by a model vendor or a data publisher. This project did not check it.
- **Inference:** a reading of the measurements. It can be wrong.

## Current architecture (audit)

| Part | File | What it does |
| --- | --- | --- |
| Seam | `app/Sources/TranscriberEngine/Protocols.swift` (`SpeakerDiarizing`) | `prepare`, `diarize(source, speechRegions, mode, expectedSpeakers, progress)`, `unload`. Returns `SpeakerSpan`s on the session timeline. |
| Backend | `TranscriberEngine/SpeakerEngine.swift` | FluidAudio 0.15.6 `DiarizerManager`. First pass: pyannote segmentation in 10 s chunks, 10-minute windows, long silences skipped. Second pass (Accurate mode): every merged span is embedded again from its own audio (WeSpeaker, at most 10 s) and clustered globally, longest first (`TurnClusterer`, `SpeakerClustering.swift`). |
| Wiring | `EngineHost.swift:31` | One line selects the backend. Nothing else above the seam knows FluidAudio. |
| Labels | `TranscriberCore/SegmentMerger.swift` | `normalize` numbers speakers S1, S2… by first appearance. `segments` and `attribute` give each word or line the speaker that holds most of its time (`dominantSpeaker`, minimum share 0.34). |
| Names | `TranscriberCore/SpeakerMatching.swift`, `TranscriberStore/TranscriptWriter+SpeakerCarry.swift` | A typed name follows the voice, matched by overlap in time between the old lines and the new spans (FINDINGS 28). |
| Manual edits | `TranscriberStore/RecordingStore.swift` (`rename`, `merge`, `assign`, `addSpeaker`) | A user renames, merges and reassigns. Identify Again and Transcribe Again re-run the diarizer and carry the names. |

Known failure modes (FINDINGS 10, 20, 28, 29), with what this work measured about each:

| Failure mode | Before | Measured now |
| --- | --- | --- |
| Similar voices merge when they share a 10 s chunk (10, 29) | Fixed in part by the second pass. | On real audio, the baseline merged two or more reference speakers on 11 of 16 AMI meetings and all 4 Liva files. |
| Turns under 1 s are missed (29) | Tuning not adopted. | Missed speech is the largest error of both backends. |
| Overlapped speech is given to one speaker at most (one label per span) | Not measured on real audio. | The baseline detected 0–14% of the overlapped frames. |
| A name followed the label number (28) | Fixed by `SpeakerMatching`. | A new path that lost names was found and fixed (below). |
| Ties in `dominantSpeaker` | Not known. | Found and fixed (below). |

## Nemotron 3 (published, checked where stated)

- **Nemotron 3 Diarization** is an NVIDIA end-to-end streaming diarizer for up to **8 speakers**
  with 10 ms frames (`nvidia/Nemotron-3-Diarization`). It has no speaker embeddings and no
  clustering: the model writes one activity probability per speaker channel.
- **Licence:** OpenMDW 1.1 for the weights and for FluidInference's Core ML conversion
  (`FluidInference/nemotron-3-diarization-coreml`, revision `25a90f97f254`). It permits commercial
  use. Redistribution of the weights must include the licence and the notices. Checked against the
  model cards and the licence text. This is not legal advice.
- **Apple Silicon:** FluidAudio ships the Core ML port from **v0.17.0** (`Nemotron3Diarizer`). It ran
  on this M2 Pro. `footprint(1)` showed about 200 MB of Neural Engine memory.
- **Not the 4-speaker Sortformer.** That model's Core ML repository is labelled CC BY 4.0, but its
  weights are under the NVIDIA Open Model License. It was not used.

### The experimental backend

`experimental/nemotron3/` is a **separate Swift package**. The app does not build it, and nothing
selects it.

- **Why a separate package:** the port needs FluidAudio 0.17.4 or later, and the app keeps 0.15.x.
  FINDINGS 20 records that 0.15.8 and 0.18.0 deleted a model cache without a revision marker when the
  network was denied. A move of the app's pin needs its own offline test.
- **Same protocol:** `Nemotron3SpeakerEngine` conforms to the app's own `SpeakerDiarizing`. The
  package compiles `app/Sources/TranscriberCore` and `Protocols.swift` through symbolic links, so a
  change to the protocol breaks this build too.
- **Offline-first:** `prepare` loads only from a local folder. With no models it fails, and it
  creates nothing. `nemodiarbench --fetch` is the only download step. All measured runs had the
  network denied (`sandbox-exec`).
- **Audio:** it feeds the audio to the model in 30 s pieces through the streaming API, which the
  vendor states is frame-exact with whole-file processing. Its spans are clamped to the recording.
- **What it does not use:** `expectedSpeakers` and `mode`, because there is no clustering and no
  second pass.
- **Overlap:** spans of two speakers can overlap. The app reads them through
  `SegmentMerger.dominantSpeaker`, so a transcript line still shows one speaker.
- **Same output as the vendor's tool (measured):** on AMI TS3003b, FluidAudio's own
  `fluidaudiocli nemotron3-diarize` (whole-file path) and this backend gave the same DER and the same
  errors.

## Method

| | |
| --- | --- |
| Commit | `304ca22` (harness and backend). The plan records it. |
| Machine | Mac mini M2 Pro (Mac14,12), 16 GB, macOS 26.6.2. No other Mac was measured. |
| Baseline | `diarbench`, the shipping `SpeakerEngine`, Accurate mode, default tuning, FluidAudio 0.15.6 |
| Primary candidate | `nemodiarbench`, Nemotron 3, preset `offline`, threshold 0.5, minimum 0.2 s (FluidAudio defaults), FluidAudio 0.18.0. Chosen before any real-audio run. |
| Secondary | the same with preset `fast128`. Reported, and not the subject of the recommendation. |
| Order | Every file, every arm, 2 passes. The arm order is a seeded shuffle for each file. Each run is under the bench lock with the network denied. |
| Input | Every corpus as 16 kHz mono 16-bit WAV, so both backends read the same samples. |

**Data**

| Corpus | Speech | Size | Speakers | Licence |
| --- | --- | --- | --- | --- |
| AMI test set (`ami`) | English meetings, headsets mixed to one track | 16 meetings, 9.1 h | 3–4 | CC BY 4.0 (audio and annotations). Reference: `pyannote/AMI-diarization-setup` `only_words` RTTM (commit `67c2d53`), from the manual annotations 1.6.2. |
| Liva AI en-tl sample (`liva`) | **Conversational Taglish**: one group of friends in a gaming voice chat | 4 × 10 min | 4–5 | CC BY 4.0. The vendor's speaker-labelled transcripts were made from channel-separated audio. Lines with only event tags such as `[laughing]` are not speech. |
| Synthetic (`synth-tuning`, `synth-holdout`, `synth-n`) | macOS `say` voices, exact boundaries | 17 files, 38 min | 2–6 | Generated here. **Synthetic.** `synth-n` is new: 2 to 6 voices with some overlap. |

FilSwitch has no stated licence and was not used, as in the tier comparison.

**Scoring rules** (`eval/diarization_metrics.py`, printed into every report):

- **Primary:** DER with a 0.25 s collar around every reference boundary (NIST). Overlapped speech
  **is scored**: two people speaking at once count twice. 10 ms frames. The speakers are mapped
  one to one to maximise shared time.
- **Also reported:** collar 0, and overlap not scored.
- **Merge:** two reference speakers, each with at least 5 s of speech, whose largest share goes to
  the same hypothesis speaker.
- **Fragment:** a hypothesis speaker that holds at least 10% of a reference speaker that it mostly
  belongs to. Two or more such pieces make a fragmented speaker.
- **Speaker count:** hypothesis speakers with at least 1 s.
- **Overlap detection:** of the frames with two or more reference speakers, the share where the
  hypothesis also has two or more.
- Corpus DER is pooled by speech time.

**Gate** (written into `plan.json` before the first run; `eval/diarization_eval.py` `DEFAULT_GATE`):

1. At least 15% relative DER improvement on **each** real corpus (AMI and Liva), pooled, with the
   primary rules.
2. No file on which the candidate merges more reference speakers than the baseline.
3. Every span valid on the timeline.
4. A process footprint of 1,024 MB or less.
5. A median speaker-pass RTF of 0.10 or less on real files.
6. A DER spread of 1 point or less between the two passes.
7. Every run scored.
8. Speech under a wrong name after a re-run no more than 1 point above the baseline's.

## Results (measured)

### DER, pass 1, pooled, primary rules

| Corpus | Backend | DER | Missed | False alarm | Confusion | DER in overlap | DER outside overlap | Merged ref. speakers |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AMI | **pyannote** | **23.70%** | 12.73% | 1.52% | 9.45% | 53.41% | 17.31% | 19 |
| AMI | Nemotron 3 | 24.13% | 23.28% | 0.45% | 0.40% | 40.73% | 20.56% | 2 |
| Liva | **pyannote** | **58.13%** | 23.36% | 2.66% | 32.12% | 63.52% | 56.73% | 16 |
| Liva | Nemotron 3 | 16.07% | 13.78% | 0.56% | 1.73% | 24.84% | 13.79% | 2 |
| synth-tuning | pyannote | 17.66% | 11.85% | 0.02% | 5.78% | — | 17.66% | 2 |
| synth-tuning | Nemotron 3 | 3.15% | 2.82% | 0.10% | 0.24% | — | 3.15% | 0 |
| synth-holdout | pyannote | 5.87% | 4.53% | 0.11% | 1.24% | — | 5.87% | 2 |
| synth-holdout | Nemotron 3 | 7.90% | 4.08% | 0.11% | 3.71% | — | 7.90% | 2 |
| synth-n | pyannote | 15.38% | 10.09% | 0.19% | 5.10% | 48.21% | 14.91% | 4 |
| synth-n | Nemotron 3 | 11.40% | 3.39% | 0.10% | 7.90% | 15.02% | 11.35% | 4 |

- **Overlap:** overlapped speech is 17.7% (AMI) and 20.7% (Liva) of the reference speech.
  - Nemotron 3 detected 46% (AMI) and 63% (Liva) of the overlapped frames, with 91% and 99%
    precision.
  - pyannote detected 14% and 0%.
- **Per file:** Nemotron 3 is better on 8 of 16 AMI meetings and worse on 8. It is better on all 4
  Liva files.
- **Other rules:**

  | Corpus | Backend | Collar 0 | Overlap not scored |
  | --- | --- | ---: | ---: |
  | AMI | pyannote | 30.91% | 17.31% |
  | AMI | Nemotron 3 | 26.24% | 20.56% |
  | Liva | pyannote | 67.90% | 56.73% |
  | Liva | Nemotron 3 | 24.03% | 13.79% |

- **`fast128`:** within about 2 points of `offline` everywhere (AMI 24.15%, Liva 17.99%).

### Speaker count: two to six speakers (pass 1, all corpora pooled)

| Speakers | Files | pyannote DER | Nemotron 3 DER | pyannote merged | Nemotron 3 merged |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 7 | 10.42% | 1.27% | 2 | 0 |
| 3 | 6 | 21.32% | 24.71% | 2 | 0 |
| 4 | 19 | 23.83% | 23.27% | 22 | 4 |
| 5 | 4 | 51.95% | 15.82% | 15 | 4 |
| 6 | 1 | 22.58% | 26.98% | 2 | 2 |

- The 2- and 6-speaker rows are synthetic only. The 5-speaker row is mostly Liva.
- The six-voice fixture has a pair of voices close together to the embedding model (centroid
  distance 0.62, `diarbench --probe-ref`). Both backends merged that pair.
- **No backend fragmented a speaker** on any file, under the rule above.

### The AMI tie depends on the reference

The same outputs, scored against the **forced-alignment** AMI references
(`nttcslab-sp/diar-forced-alignment` commit `9527b7c`, AMI files CC BY 4.0, Montreal Forced Aligner
word intervals):

| Backend | Collar 0.25 s | Collar 0 | Overlap not scored | Missed | False alarm | Confusion | Merged |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pyannote | 24.86% | 45.44% | 22.80% | 4.88% | 9.57% | 10.41% | 19 |
| Nemotron 3 | 3.49% | 9.41% | 2.65% | 1.76% | 1.28% | 0.46% | 2 |

- **Published:** FluidAudio reports 9.47% for this preset on these references at collar 0. This
  run measured 9.41%.
- **Inference:** the manual-annotation segments run across the pauses between words, and the
  forced-alignment segments stop at them.
  - Nemotron 3 marks speech word by word, so the manual references charge it with "missed" speech
    in those pauses (23.3% missed).
  - pyannote bridges short pauses (`mergeGapMs` 250), so the manual references suit it.
- **Independent check of the reading:** Nemotron 3's output covers 97.2% of the
  forced-alignment speech and 81.1% of the manual-reference speech. pyannote's covers 95.5% and
  93.0%.
- **The speaker part of the error does not depend on the reference.** Confusion on AMI is
  9.4–10.4% for pyannote and 0.4–0.5% for Nemotron 3 under both reference sets.
- **The gate used the manual references, as the plan says.** The forced-alignment result is
  secondary and was not used for the decision.

### Stability, runtime and memory

| | pyannote | Nemotron 3 |
| --- | --- | --- |
| Identical output, pass 1 against pass 2 | 37 of 37 files | 37 of 37 files |
| Median speaker-pass RTF, AMI | 0.0064 (13.1 s median) | 0.0028 (6.0 s) |
| Median speaker-pass RTF, Liva | 0.0094 | 0.0029 |
| Load | 0.12 s | 0.10 s (after the first Core ML compile, about 13 s) |
| Peak process footprint, 50-min meeting (`footprint(1)`, 2 runs) | 1,653–1,659 MB | 86–89 MB |
| Neural Engine memory, same run | under 1 MB | 213 MB |
| All categories, same run | 1,761–1,767 MB | 400–401 MB |
| Model files on disk | 13 MB | 190 MB |

**The shipping speaker pass grows with the recording (measured, not explained).** Its peak process
footprint was 450–533 MB on 10-minute files and 1,678 MB on a 50-minute meeting, about 27 MB per
minute. If that holds, a 2-hour meeting needs about 3.4 GB for speaker processing alone. This is an
extrapolation, and the cause is not known. It is a risk on 16 GB Macs and needs its own
investigation.

## Speaker identity and persistence

**Names after a re-run (measured with `eval/speaker_stability.py`'s method).**

- *The method:* a person names every speaker of pass 1 after the voice it really is. Each backend
  is then re-run with `--carry-from` on changed audio: the opener muted, the head trimmed, noise at
  −40 dBFS, and an AAC 64 kbit/s round trip. The score is the speech that the carried names put
  under the wrong person.
- *Scope:* Liva, `synth-tuning` and `synth-n`, 64 re-runs per backend.

| Backend | Right name | **Wrong name** | No name |
| --- | ---: | ---: | ---: |
| pyannote | 54.0% | **27.9%** | 18.2% |
| Nemotron 3 | 67.5% | **7.2%** | 25.3% |

On Liva alone the wrong-name share is 46.0% against 11.3%. **Inference:** most of the wrong names
are the diarizer's own confusion, not the carry rule.

**The store (automated tests; backend-independent).** The persistence agent added
`SpeakerIdentityRegressionTests` (10 tests). They cover these combinations, each over a real
on-disk store that is closed and opened again:

- rename, reassign, Identify Again, restart and Transcribe Again;
- a merge across a restart;
- a speaker made by hand;
- "No Speaker";
- one turn decoded again;
- Identify Again twice.

Every test checks that start and end times do not change, that lines stay in order, that the
roster is consistent and that no two speakers share a label.

**One bug found and fixed.**

- *What happened:* after Transcribe Again with speaker identification **off**, the next
  identification put every voice under a new default name. The typed names stayed on speakers with
  no lines.
- *Fix:* the evidence is now the newest finished revision that has labels
  (`TranscriptWriter.labelledRows`).
- *Tests:* both regression tests failed before the fix.

**A fix to that fix, found by the independent review.**

- *What happened:* a merge rewrote only the current revision, but an older revision is now the
  evidence. A new speaker could take the merged-away label (`addSpeaker` numbers after the
  roster). The next Identify Again then gave the new person's name to the lines the user had merged
  into someone else.
- *Fix:* a merge now rewrites every revision, and a new speaker is numbered after every label that
  any revision still carries.
- *Tests:* the regression test failed on the earlier code.
- *Still open:* if one line of an unlabelled revision is assigned by hand, that revision counts as
  labelled and hides the older evidence. Names then fall back to defaults, as before the fix, and
  are not wrong.

**A second fix.** `SegmentMerger.dominantSpeaker` took the winner of a tie from `Dictionary` order,
which changes from one process to the next.

- *Why it matters:* overlapping spans make ties common, for example two speakers over the whole of
  a word.
- *Fix:* a tie now goes to the lower label. The labels compare as text, so `S10` sorts before
  `S2`. That is deterministic, which is the point.
- *Tests:* the new test failed on every run of the old code. `OverlappingSpansTests` pin the rest:
  word times never move, each line goes to the speaker that holds most of it, and names carry over
  overlapping spans.

**Not fixed, noted by the persistence agent.** Both come from reading the code and were not
tested:

- The name field writes on every keystroke (`MeetingPanes.swift:403–408`).
- A turn decoded again relabels a line in its range that was moved by hand
  (`TranscriptionQueue.swift:581`).

## Independent verification

A separate agent reviewed the work without the author's conclusions. It wrote its own
interval-based scorer and **reproduced these from the run outputs**:

- every pooled DER and its three parts, under all three rules, for AMI and Liva;
- the forced-alignment rescore;
- the merge counts on all 111 file and backend pairs;
- the name-carry shares;
- the gate decision.

It also checked the following:

- `optimal_mapping` agrees with brute force on 4,000 random matrices.
- The Liva conversion keeps every speech line and drops only event tags.
- The gate in `plan.json` equals the code's gate. The scoring and gate code did not change after
  the run.
- `app/Package.swift` and `Package.resolved` are unchanged.
- Nothing in `app/` refers to the experimental package.

It did not re-run the diarizers, the timings or the memory sampling. Its findings changed this
work:

- the stale-label fix above;
- `decide` no longer fails on a file without reference speech;
- `score`, `identity` and `decide` now check that their files come from the same plan.

It also pointed out that the Liva gain rests on 4 files from one group, about 14 minutes of scored
speech.

## Before a replacement

The measurements support **continuing** with Nemotron 3. They do not support **switching** now. A
replacement needs all of these:

1. **A meeting reference with a written boundary convention, and the gate run on it.** The AMI
   result changes sign with the reference. Ideally use consented Taglish meeting recordings with
   two annotators (BENCHMARKS, the DER protocol).
2. **The similar-voice merge examined.** Nemotron 3 merged Sandy and Shelley (two UK female
   synthetic voices) on `h-four-voices`, where pyannote did not.
3. **The FluidAudio upgrade proved offline.** First load with the network denied, an existing
   cache, no deletion (FINDINGS 20).
4. **The integration designed.**
   - There is a limit of 8 speakers.
   - `expectedSpeakers` cannot apply.
   - Overlapping spans go into the transcript as one speaker per line.
   - The 190 MB model must be downloaded once, with the OpenMDW notices.
5. **The memory growth of the current backend explained,** whatever the decision.

## Reproduce

Data stays in `/tmp/notero-data/diar/`. Compact results are in
[`eval/baselines/diarization-2026-11-02/`](../eval/baselines/diarization-2026-11-02/). The folder
holds no audio and no transcript text.

```bash
# Backends
(cd app && swift build -c release --product diarbench)
(cd experimental/nemotron3 && swift build -c release \
  && .build/release/nemodiarbench --fetch /tmp/n3-cache --models /tmp/n3/offline --preset offline)
# Data: AMI test Mix-Headset WAVs + pyannote/AMI-diarization-setup in SRC/{audio,setup}
python3 -I eval/diarization_eval.py prepare-ami  --src SRC --work W/ami
python3 -I eval/diarization_eval.py prepare-liva --src LIVA --work W/liva   # tier_benchmark.py liva-fetch
python3 -I eval/make_multispeaker.py --set speakers --out FIX/n
python3 -I eval/diarization_eval.py prepare-synthetic --fixtures FIX/n --work W/syn-n --corpus synth-n
# Plan (the gate is fixed here), run, score, names, residency, decide
python3 -I eval/diarization_eval.py plan --manifest W/ami/manifest.json ... \
  --arm 'pyannote=BIN/diarbench --audio {audio} --models M --json {json} --mode accurate' \
  --arm 'nemotron3=BIN/nemodiarbench --audio {audio} --models N --preset offline --json {json}' \
  --primary nemotron3 --runs 2 --out OUT
python3 -I eval/diarization_eval.py run      --plan OUT/plan.json
python3 -I eval/diarization_eval.py score    --plan OUT/plan.json
python3 -I eval/diarization_eval.py identity --plan OUT/plan.json
/tmp/notero-team/bench-lock.sh python3 -I eval/diarization_eval.py residency --plan OUT/plan.json --item ami-EN2002c
python3 -I eval/diarization_eval.py rescore  --plan OUT/plan.json --corpus ami --refs FA/AMI/test --label ami-forced-alignment
python3 -I eval/diarization_eval.py decide   --plan OUT/plan.json
```

The 222 runs took 17 minutes on the M2 Pro. The name-carry re-runs (64 for each backend) and the
residency runs are extra.

**Attribution.** AMI Meeting Corpus, University of Edinburgh and partners, CC BY 4.0. The audio
was resampled to 16 kHz. Liva AI, Code-Switching ASR (en-tl), CC BY 4.0. Forced-alignment AMI
references by NTT CS Labs, CC BY 4.0. Nemotron 3 Diarization by NVIDIA, Core ML conversion by
FluidInference, OpenMDW 1.1.
