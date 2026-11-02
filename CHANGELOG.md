# Changelog

## Unreleased

### Export

- **Export and Copy write the transcript revision on screen.** With an earlier revision open
  from the info bar, the exported file and the copied text held the latest revision, and nothing
  said so. The open revision now lives on the app state, tagged with its recording and cleared
  when the selection changes, and the export sheet says which revision it will write when that
  is not the latest. Ported from the first part of #10.

### Live latency

- **A controlled experiment on the live path** (`eval/live_latency.py`) tested six variants, one at a
  time, against the production configuration, on real public audio (Liva AI, AMI, FLEURS), in real time,
  with the control run twice in every block as an A/A. **No variant met every gate, and the live
  configuration does not change.** Head-tolerant agreement stays off: its median commit latency gain was
  0.6% and 14.5% in the two sessions (7.8% pooled, with an interval that includes 0), and its p90 gain of
  27% in the first session did not repeat (7%). The adaptive hop gave about 17% in both sessions, under the
  20% bar. [BENCHMARKS.md](docs/BENCHMARKS.md#live-commit-latency-2026-11-02)
  and finding 38 in [FINDINGS.md](docs/FINDINGS.md) give the numbers. The plans, every run's numbers and the
  decision are in `eval/baselines/live-latency-2026-11-02/`. No audio and no words are in the repository.
- **`transcribe --live` checks that committed text is only ever appended to,** on every replay
  (`CommitInvariantMonitor`). It reports `commit invariant: held over N words`, or names what broke.
  The check held over 33,937 words in 108 replays.
- **New `transcribe --live` options:** `--head-tolerance`, `--head-min-run`, `--silence-boundary`,
  `--min-hop` and `--live-trace`, which adds every decode, dropped hop, utterance end and commit, with its
  reason and the CPU used, to the JSON report (numbers only). `LiveReplayRecorder` records them.
- **`--realtime` now follows one absolute clock** and hands each 100 ms chunk over when its last sample
  would have been captured. It no longer drifts by the cost of each chunk.
- **Tests:** 22 Swift tests (the invariant monitor, the recorder, and a property test that runs the
  invariant over every variant on random scripted sessions) and 67 Python tests for the experiment's
  metrics, statistics and gate.

### Evaluation framework

- **`transcribe --score` scores saved transcripts with one written method,** and loads no model,
  opens no audio device and uses no network. It reads a manifest, plain-text or JSON references
  and one hypothesis for each item, and writes a JSON and a Markdown report.
  [BENCHMARKS.md](docs/BENCHMARKS.md#the-evaluation-framework) gives the method.
- **The reports give WER and CER for the corpus, each recording and each utterance,** with
  substitutions, deletions and insertions. They also give results by utterance language, by word
  language and at code-switch points, and by speaker overlap. They list deletion bursts and the
  reference speech that no hypothesis word covers. Each breakdown needs its annotation, and
  without it the report says "unavailable" with the reason.
- **The intervals are a seeded, stratified percentile bootstrap,** and `--compare` adds a paired
  comparison of two systems on the same references. The same inputs give the same bytes.
- **Scoring is versioned.** The configuration (`eval/evaluation-config.v1.json`) and the scoring
  policy have a version and a fingerprint, and each report records them. The report also records
  the corpus ID, the model, the model revision from the local download cache, the hardware and the
  inference settings. It keeps the whole-file RTF, the live commit latency, the process footprint
  and the model residency apart.
- The default policy gives the same words and counts as `eval/score.py`. The older scorers do not
  change: `--reference` still prints the same `WER` line, and the `evaluation (…)` line is new.
- `--reference` accepts the JSON reference form, and the tool checks the reference and the
  configuration before the decode. `transcribe --json` reports gain the optional fields
  `evaluation`, `provenance` and `performance`. A saved benchmark gains `evaluation` and
  `modelRevision`, and older saved benchmarks still load.
- **No benchmark result comes with this change.** The framework was tested on synthetic text only.

### Taglish error taxonomy

- **`eval/taxonomy.py` sorts each word error into one kind.** The kinds are: Tagalog written as
  English and English written as Tagalog, errors at code-switch points, mixed-language words
  (`nag-meeting`, `i-share`), Filipino morphology (affix, reduplication, linker), proper names,
  particles (`po`, `naman`, `lang`), runs of invented words, runs of deleted speech, and
  spelling variants. It also reports timestamp misalignment. It is optional. It uses the same tokens
  and edit distance as the WER, so the error words of all categories add up to S + D + I. No
  existing number or file changes.
  [eval/TAXONOMY.md](eval/TAXONOMY.md) gives the method.
- **Labels are `verified`, `heuristic` or `structural`, and the report never adds them together.**
  A reference can carry word-level language tags in a plain-text or JSON file that a person edits
  (`.tagged.txt`; `languageSpans`). Without tags the language labels come from small word lists
  that an AI model wrote, with no native-speaker review. A word that no list covers is `unknown` and not Filipino. The report says
  how many tokens are `unknown` or `ambiguous`. A person can adjudicate any event in a TSV file.
- **It runs from `score.py --taxonomy-out`, `tier_benchmark.py taxonomy` and
  `compare_language.py --taxonomy`.** The same inputs give byte-identical reports. The reports hold
  no corpus text unless `--include-text` is set.
- **The first results are on the saved Liva and FLEURS tier decodes.**
  [BENCHMARKS.md](docs/BENCHMARKS.md#error-taxonomy-of-the-tier-decodes-2026-11-02) gives them
  with their limits. On the Liva sample, 38.8% of the Balanced errors are runs of three or more
  deleted words. Best has 98 fewer Tagalog-to-English substitutions than Balanced in the first decode (95 in the second; heuristic).
  The category counts move with the alignment tie-break (`--tie-break`): read no difference of less than about 70 words in one category.
  No reference has word-level tags, so no result is `verified`.
- **Synthetic fixtures with expected counts worked out from the text** are in `eval/fixtures/taxonomy/`. `tests/test_taxonomy.py`
  adds 127 tests.
- **A research report corrects an earlier statement.** [docs/TAGLISH-CORPORA.md](docs/TAGLISH-CORPORA.md)
  lists the public Filipino and Taglish speech resources with their licences. FilSwitch still
  states no licence. The earlier claim that no public conversational Taglish corpus has a
  suitable licence was wrong as worded: Liva `en-tl` and CEnTaCS (5.4 hours of monologue, CC BY 4.0)
  are permissive and small. No public Filipino meeting speech exists in the sets found. No new
  corpus was downloaded.

### Tier comparison

- **`eval/tier_benchmark.py` compares the three tiers on one corpus** with identical decodes,
  interleaved under the bench lock, scored by `transcribe --score`, and a decision gate fixed in
  the plan before the first decode. It builds corpora from FLEURS `fil_ph` and from the Liva AI
  `en-tl` sample (CC-BY-4.0), each checked against its published hashes.
- **The default stays Balanced.** On 349 sentences of read Tagalog the tiers are within about
  half a point (Balanced 11.66% WER). On 40 minutes of conversational Taglish, Best is about
  4 points better in two decodes, which is under the 10% that the gate needs, and Best cannot run
  live. Fast was slower than Balanced on the M2 Pro and slightly less accurate.
  [eval/TIER-RESULTS.md](eval/TIER-RESULTS.md) gives the method and the limits.
- Real meeting accuracy is still unmeasured. FilSwitch, the best public Taglish test set,
  states no licence and was not used.

### Speaker diarization

- **`eval/diarization_eval.py` compares speaker backends on the same annotated audio.** It
  prepares the AMI test set, the Liva AI Taglish sample and synthetic fixtures. It fixes the gate
  in a plan before any run, runs every backend under the bench lock with the network denied, and
  scores the results.
  - `eval/diarization_metrics.py` gives DER with an explicit collar and overlap rule, the parts in
    and out of overlap, overlap detection, merged and fragmented speakers, the speaker count and
    timestamp validity.
  - Other steps re-run on changed audio to count names carried to the wrong person, sample Neural
    Engine memory from outside, and score against a second reference set.
  - `make_multispeaker.py --set speakers` builds fixtures with two to six voices.
- **An experimental Nemotron 3 backend, off.** It is a separate package,
  `experimental/nemotron3/`, on FluidAudio 0.18.0. `Nemotron3SpeakerEngine` conforms to the app's
  `SpeakerDiarizing` and never downloads. The app's FluidAudio pin and its default backend do not
  change.
- **The comparison keeps the current backend.**
  - Nemotron 3 cut DER on the Taglish sample from 58.1% to 16.1%, and speaker confusion on AMI
    from 9.5% to 0.4%.
  - It did not lower AMI DER against the manual references (23.7% against 24.1%), and it merged
    one synthetic voice pair. The gate needed 15% on each real corpus.
  - See [DIARIZATION.md](docs/DIARIZATION.md).
- **Fixed: speaker names were lost after Transcribe Again with speaker identification off.** The
  next identification compared against the unlabelled revision, matched nothing and put every
  voice under a new default name. It now uses the newest revision that has labels.
  - A merge now rewrites every revision, and a new speaker is numbered after every label any
    revision still carries. Without this, a new speaker could take the merged-away label and
    inherit the merged lines.
  - 11 store regression tests cover rename, merge, reassign, Identify Again, Transcribe Again and
    restart.
- **Fixed: a line under two speakers at once went to a random one of them.**
  `SegmentMerger.dominantSpeaker` took the winner of a tie from `Dictionary` order. A tie now goes
  to the lower label.
- **Measured, not fixed:** the shipping speaker pass's peak footprint grows by about 27 MB per
  minute of audio (1.68 GB on a 50-minute meeting).

## 1.2.0 — 2026-11-01

### Speed, memory and stability (second cycle)

- **A model that is already on disk loads in about 1.6 seconds, not 8 to 11.** Every load asked
  the Hugging Face Hub, even for a model that was on disk, and failed offline. The load now
  reads the model folder directly, and the transcript is byte-identical. Entry 30 gives the
  measurements.
- **A model switch releases the old model first,** which cuts the Neural Engine peak by about a
  third (2,458 to 1,580 MB, and 4,581 to 3,000 MB). Pressing Record while a job loads another
  model now reloads the live model.
- **The window no longer freezes while Stop saves a long transcript.** The writer and the readers
  ran on the main thread, which froze the window for 6.9 s on a six-hour meeting. Entry 32.
- **A recording file that will not close can no longer freeze Stop or a quit,** and a recording
  killed in its first seconds keeps what was written after the first second.
- **A long device gap no longer holds up capture.** A two-lane, ten-minute gap held it for 0.56 s
  in a release build.
- **A speaker's name and colour follow the voice, not the label number,** when speakers are
  identified again, and a named speaker that the new run does not find is kept. In 12 of 52
  re-runs at least one voice had been renumbered. Entry 28.
- **Transcribe Again works on a two-lane recording whose file cannot be opened,** from the mixed copy,
  with a warning.
- **Audio that arrives during a long device gap is no longer overwritten** when the input reuses its
  buffer (system audio and "both"), and **a recording whose file did not finish closing keeps its
  working copy.** Found in independent review; entry 35.
- **Cancelled and failed jobs release the speaker models,** and a caller that was cancelled while
  it waited for a model load no longer waits for it. The speaker models are small (13 MB); the
  figure of 200 MB in the documentation was never measured.
- Live decoding gained an opt-in trace and property tests that commit immutability holds. Head-tolerant
  agreement, which cut median commit latency by 35 to 43% on two synthetic clips, is implemented
  and off until a second session on real audio confirms it. Entry 27.

### Tools and evidence

- **`eval/regress.py`** compares two builds in one command, with one collapse rule and one decision
  rule that flags 1.7 to 2.6% of simulated A/A sessions (an uncorrected table flags 11 to 24%). It adds
  a determinism check, a fixture manifest and committed baselines in `eval/baselines/`.
- **`eval/fleurs_eval.py`** evaluates read Tagalog on the public FLEURS set, and
  `eval/REAL-TAGLISH-PROTOCOL.md` describes how to build a real Taglish reference from the app's
  corrections export. On read Tagalog, the first cycle's changes alter nothing, `auto` equals `tl`,
  and the Best tier is not more accurate. Entries 24 and 25. None of this is Taglish.
- **`diarbench`** times the speaker stage alone, with the tools to measure whether a name follows the voice.

### Recording and recovery

- **A recording that is killed, crashes or is force-quit now leaves a playable
  file.** The file used to be unreadable, because it only opened after a clean
  close. It is written in 5-second fragments now, and at most the last few
  seconds are lost. Quitting during a recording stops and saves it first.
  [docs/FINDINGS.md](docs/FINDINGS.md) entry 17 gives the details and what is
  not covered. A recording that was killed before this change stays unreadable.
- **The working copy of the audio is kept when the recording file cannot
  replace it.** After an interrupted recording, Transcribe Again no longer
  deletes the only complete copy. The recovery messages say what survived.
- **A job is no longer called Complete when its transcript could not be
  saved,** and a failed job keeps its reason. The warning says when live lines
  or the length of the recording are not being saved.
- **A long meeting finishes in seconds and not minutes.** Saving the final
  transcript of a six-hour meeting took 159 s in a measurement, and 6.5 s after
  the change. Entry 19 gives the conditions.
- **A running transcription steps aside when you start a recording,** and
  starts again from the beginning afterwards. It no longer competes with the
  live transcript.
- **A recording can start again after a refused microphone, a failed model load
  or a failed capture start.** It used to fail until the app was restarted.
- **Interfaces at 88.2, 96 or 192 kHz can record.** They were refused.
- **A Mac that sleeps during a recording no longer allocates the whole sleep at
  once,** and the recording says how long the input was interrupted.
- **Speaker names that you chose survive a re-run that finds no speakers.**
- **Search no longer stalls the window on a long meeting.**

### Transcription

- **The same file no longer transcribes differently on each run.** The first
  window of the test clip decoded as invented English filler in about half of
  the runs. The pipeline now decodes greedily first and, if that is refused,
  retries with a short lead-in of silence before any random re-sampling. On the
  test clip, 0 of 20 runs collapsed against 7 of 20, and every run gave the same
  transcript. That clip starts abruptly, which is the cause, so the change is
  unproven on real recordings. Entry 16 gives the numbers.
- **The live decoder's memory no longer grows with the length of the
  session.** It grew about 110 MB an hour. Entry 18 gives the measurement.
- **Two requests for the same model at the same time share one load.**
- **Voice-activity batches that fail are counted** in the session stats.

### Tools

- **`eval/make_multispeaker.py` and `eval/der.py`** build synthetic
  multi-speaker fixtures with known turn boundaries and score a diarization run
  with a frame-level DER, for A/B comparison. They are not an accuracy measure
  for real meetings.
- **`eval/bench_runs.py` and `eval/residency.py`** run repeated, interleaved A/B
  benchmarks with permutation and Fisher tests that refuse to call a result below
  n = 8, and take a memory reading from outside the process.
- **`transcribe` reports the memory it used properly.** Its "peak memory" line
  was one reading at exit. It now prints the lifetime peak footprint and the Neural
  Engine memory (about 1.6 GB for the default model), plus per-decode time and
  commit latency in a live replay. Entry 22 gives the measurements.
- FluidAudio is pinned to patch releases of 0.15.6. Entry 20 explains why 0.15.8
  and 0.18.0 were not adopted.

### Audio

- **Test the microphone in Settings › Audio.** Click **Test Microphone**, speak,
  then click **Stop**. The app plays back what the microphone heard, at the
  quality the transcription gets. Each take stays in the list with the name of
  its microphone, so you can change the microphone and compare. The same test
  is `transcribe --mic-check` in the command line tool.
  [docs/CLI.md](docs/CLI.md) describes it.
- **A 16 kHz microphone can start a recording.** Bluetooth headsets in
  hands-free mode and USB conference speakerphones deliver 16 kHz. The archive
  asked the encoder for a bitrate it does not permit at this rate, and the
  recording refused to start with a CoreAudio error. The app now asks the
  encoder for the permitted range. [docs/FINDINGS.md](docs/FINDINGS.md) entry
  13 gives the measurements.
- **A full disk no longer crashes a recording or loses its audio.** Writing
  the transcription copy into a full disk crashed the app. The recording file
  stopped silently, and it could not be opened afterwards because its index
  was never written. Notero now stops saving audio while 100 MB is still free,
  closes both files so that they stay playable, and shows a notice that is
  kept with the recording. The live transcript continues. A recording does not
  start when the disk is already that full. [docs/FINDINGS.md](docs/FINDINGS.md)
  entry 14 gives the details.

## 1.1.0 — 2026-09-08

### The model tiers

- **The Accurate tier is called Best.** The name stated a property of the
  transcript that this project has not measured. "Best" names a position on
  the speed ladder instead. The tier, its model and its behaviour do not
  change. A stored `accurate` still selects the tier, and
  `transcribe --tier accurate` still works. [docs/MODELS.md](docs/MODELS.md)
  says which tier promises are measured, and which ones are inferred.

### Simple mode

- The app has two modes. **Simple** is the default. It shows the recordings, a
  **Record** button, a **Transcribe a File** button, the transcript and the
  notes. **Advanced** shows every control: the model tiers, the audio controls,
  the benchmark, the decode statistics and the transcript revisions. To change
  the mode, click the mode name at the bottom of the sidebar, select **View ›
  Advanced Mode** (⌥⌘A), or go to **Settings › General › Mode**.
- The detail column with nothing selected is a drop target with two buttons and
  three steps. The whole window shows a frame while a file is over it.
- A drop on the Dock icon, **Open With › Notero** in the Finder and
  `open -a Notero file.m4a` all transcribe the file. The app declared the file
  types since the first release, but nothing received them.
- Live text is off by default. The app records only and makes the transcript
  when you stop. The app also loads no model at the start when live text is
  off. Before this change the app loaded a 1.6 GB model at each start for a
  path that did not run.
- Simple mode asks for the microphone permission at the first recording, and
  not on the first-run card.
- A menu bar item gives Record, Pause, Resume, Stop and Add a Bookmark from any
  application, and its menu shows the clock of the recording. During a
  recording, macOS draws its orange microphone indicator on the item. ⌃⌥R starts or stops a
  recording and ⌃⌥P pauses or resumes it, in every application, with no
  accessibility permission. **Settings › General › Show Notero in the menu
  bar** turns the item and the two shortcuts off together.
- A recording has a **Pause** button (⇧⌘P). The clock, the file and the live
  text stop, and Resume continues on the same timeline with no gap. Mute is
  the other switch: the clock continues and the file gets silence. Before this
  change, Mute was the only way to stop the sound.
- The labels, the messages and the help texts follow ASD-STE100 Simplified
  Technical English. The status names are nouns: In queue, Preparation,
  Transcription, Speaker identification, Complete.

### One turn again, and your corrections as references

- Right-click a turn and select **Transcribe This Turn Again**. The app
  decodes only that turn, on the Best tier in Simple mode or on the tier
  you select in Advanced mode, and replaces its lines in place. The turn keeps
  its speaker. Before this change, one bad window in a four-hour meeting cost a
  second decode of the four hours.
- **File › Export Corrections as References…** (Advanced) writes a folder with
  a copy of each corrected recording, the reference text with your edits, the
  raw model text, the corrected lines with the raw text beside each, a
  `manifest.json` for `eval/compare_language.py`, and a `summary.md` that
  scores the raw text against your corrections with no new decode. The project
  had no real Taglish references before this.

- A double-click or a right-click works on the whole turn. Before this change,
  the words of a turn were selectable text: a double-click on them selected a
  word instead of opening the editor, and a right-click on them showed the text
  menu of macOS instead of the menu of the turn. Copy is in the menu of the turn.

### A long transcript opens fast

- The transcript view reads the rows in one query, in time order, off the main
  thread, and groups them before they reach the view. Before this change the
  view walked the relationship, which faulted each row one by one on the main
  thread, and it did this again on each redraw. On a store on disk with 4000
  rows, the walk takes 278 ms and the query takes 50 ms. In the app, a
  3909-row transcript of a 3 h 51 min meeting is on the screen in 0.3 to 0.7 s,
  and the window does not wait for it.
- The info bar, the export, the search index and the editor read the rows the
  same way. The editor read the whole transcript at each keystroke. It now
  reads its own lines one time.
- The transcript view no longer reloads when the notes column opens on the
  first layout.

### Live text

- The decoder drops a word that the model places inside a pause that the
  voice detector found, from every hypothesis and not only from the final
  decode. On the paused synthetic clip the word error rate went from 51.6% to
  39.1%, and the decoder committed 13 fewer words with no agreement. Finding 12
  in `docs/FINDINGS.md` gives the mechanism.
- Measured and not shipped: a Taglish style primer in the prompt made the live
  path repeat the primer (27% to 96% WER), and `suppressBlank` was noise.
  `transcribe --style-hint` and `--prompt` repeat the measurement.

### The audio input

- When the room listens through speakers, the microphone also hears the persons
  on the call, and the room lane transcribed each remote sentence a second
  time. The app now drops a room line that repeats a call line at the same
  moment, because the call lane already holds the clean copy. A room line with
  its own words at the same moment stays.

## 1.0.1 — 2026-09-05

### The audio input

- The app records the audio of this Mac, and not only the microphone. In a
  meeting with remote persons, the microphone hears those persons through a
  speaker and a room. The new input hears them before the speaker. Select
  **Notero › Settings › Audio › Record** to set the input to the microphone,
  to the audio of this Mac, or to both.
- With both inputs, the app keeps the two in different channels of one file.
  Channel 1 holds the room. Channel 2 holds the call. A mix of the two cannot
  be separated again, and the microphone copy of a remote voice is the worse
  copy.
- The app transcribes each channel independently and then puts the two
  transcripts in time order. Each line shows if the person is in the room or on
  the call. This is speaker information that no calculation can get wrong,
  because it comes from the source of the samples. If two persons speak at the
  same time, you get two correct lines and not one mixed line.
- The app identifies the speakers in each channel independently. The persons in
  the room get the names Room 1, Room 2, and more. The persons on the call get
  the names Remote 1, Remote 2, and more.
- You can select the microphone. Select **Notero › Settings › Audio › Record ›
  Microphone**. Before this change the app always used the default input of
  macOS, thus a headset that you connected in a meeting moved the recording to
  the headset microphone. The app shows a warning if the microphone that you
  selected is not connected.
- To record the audio of this Mac, macOS must give permission. This permission
  is not the microphone permission. **Notero › Settings › Audio ›
  Permissions** shows the two permissions and requests them. Do not ignore
  this: if you refuse this permission, macOS gives no error and no audio. The
  recording looks the same as a call in which no person spoke.
- The app stops the playback of a recording when a new recording starts, if the
  new recording includes the audio of this Mac. If it did not, the recording
  would contain the playback.
- The build script signs the app with an Apple Development identity if the Mac
  has one. macOS connects a permission to the signature of an app. An ad-hoc
  signature changes with each build, thus macOS asked for the permission again
  after each build.
- The app puts the audio of this Mac through a soft limiter that starts at
  3 dB under full scale. A call application sends its mix with no headroom, and
  that audio clipped in the archive and in the copy that the model reads. The
  limiter changes only the samples above the threshold. It does not limit the
  microphone: the gain slider and the meter control that lane.
- If the microphone that you selected disconnects during a recording, the
  recording continues on the default input of macOS. If the default input
  changes during a recording, the recording follows it. In both cases the
  recording screen shows a message, and the recording keeps the message as a
  warning. The lost time becomes silence, thus the timestamps after it stay
  correct. Before this change, the recording continued with no audio and no
  message.

### The waveform

- The waveform of a recording shows quiet and loud parts at different heights
  again. The app divides an envelope by its loudest bucket, thus that bucket is
  1.0. It then drew the result on the decibel scale of the input meter, which
  is a second correction of the same problem. A bucket at 1% of the loudest
  moment became 33% as tall as it. A meeting drew as one solid block. A stored
  envelope now has its own scale, where that same bucket is 10% as tall.
- The waveform draws one bar for each 3 points of width and keeps the loudest
  sample of each group. Before this change it drew all 600 buckets across a
  view that is rarely 600 points wide. The bars overlapped, thus the shape had
  no gaps in it and did not read as bars.
- The player shows a line at the position of the playhead. It also shows a flat
  line to drag along while the app calculates the envelope of a new recording.
  Before this change that part of the player was empty.
- The bars of the input meter keep one width. Before this change the app spread
  the meter across the full width at all times: the first bar of a recording
  was as wide as the window, and each bar became more narrow as more audio
  arrived. The bars now come in at the right side and move to the left.
- The input meter shows the loudest audio of each 100 ms and not the last block
  of audio in it. The microphone gives approximately 85 ms of audio at one
  time, thus the meter discarded one block in two. A short peak in a discarded
  block did not show. The bars also came at intervals of 170 ms and not 100 ms,
  which put the history of the meter on a different clock from the recording.

## 1.0.0 — 2026-09-04

The first release that anyone outside can download. Everything below is in it.

### The name

- The app is **Notero**. It was Transcriber through the private builds. The
  bundle, the window and the menu carry the new name, and the bundle identifier
  is now `local.notero`. macOS asks for microphone access one more time after
  the change, because it grants that access per bundle identifier.
- The Swift modules and `~/Library/Application Support/Transcriber/` keep the
  old name. The directory holds the recordings that the private builds wrote,
  thus a rename there hides them from the app.

### Live transcription

- Each decode now reads 1.5 seconds of committed audio in front of the active
  region. The model therefore does not start cold at a commit boundary. That
  audio is context only. The app drops a word that the model reads again from
  it by time. It drops the boundary word by text when its times drifted. No
  word commits two times.
- An utterance now ends on the clock of the voice detector and not on the hop.
  After 700 ms of silence, the app decodes all audio up to the pause at one
  time. The agreed prefix commits as usual. The tail commits only if the room
  is still quiet when the decode returns. Before this change, the app saw the
  pause up to 1.5 seconds late and committed the provisional text of the last
  hop. The final second of each utterance was never decoded.
- The app writes each committed line to the library while the recording runs,
  in batches of approximately one second. After a crash in the middle of a
  meeting, everything up to the last commit is still there. The message on the
  row says so, and Transcribe Again redoes the rest from the working copy.
- Stop now waits for the decode in flight and examines the tail one more time
  before it commits. Before this change, the app discarded whatever arrived
  after the snapshot.
- A live segment carries the confidence of the model again. The commit step
  dropped it before.
- The Stats popover shows the number of closed utterances, final decodes,
  unagreed tail words, forced commits and deduplicated boundary words.

### Whole-file transcription

- A whole-file job now finds the speech and decodes it in 5-minute batches.
  Before this change, the app scanned the complete recording before the first
  call to Whisper, and a long file showed no text for many minutes. The two
  stages stay sequential, thus they do not compete for the Neural Engine.
- A transcript now appears while a whole-file job runs. The segments of each
  decoded window go into the store as that window finishes. A banner gives the
  stage, the percentage and the time that remains. A job that stops part-way keeps
  what it had, with the label Partial.
- Speaker identification has three modes in Settings: Off, Fast and Accurate.
  Accurate is the default and examines each turn a second time. Fast does one
  pass and is much quicker on a long recording, but it can merge similar
  voices. The command-line tool takes `--fast-diarize` for the same purpose.
- The app stores the duration of each stage with the transcript and shows it in
  the ⓘ popover: Prepare, Find speech, Transcribe, Identify speakers and
  Finalize.
- The benchmark also reports the tier that finished fastest, with a button to
  select it. A quantized model uses less memory, but it is not the fastest
  model on every generation of Apple silicon.

### Speakers and transcripts

- You can merge two speakers with a right-click in the Speakers pane. You can
  move one turn to a different speaker with a right-click on a transcript line.
  The pane sorts by talk time, draws talk-time bars and marks probable
  fragments.
- "People in the room" on a recording gives speaker identification a target.
  The target is soft. The app merges clusters that are closer than a relaxed
  distance until it reaches the count. Voices that are clearly different stay
  separate.
- Transcribe Again names each tier. Identify Speakers Again runs the speaker
  pass alone.
- Double-click a turn to edit it line by line. An edit keeps the raw model
  output below it, and search and the exports read the edit. You can move a
  line to a different speaker, restore it, or delete it. ⌘Z undoes all edits to
  one turn in one step.
- A menu in the info bar opens an earlier revision of the transcript.
- ⌘F finds text in the open transcript and highlights each match in place.
  ⇧⌘F searches the complete library.

### Windows, views and controls

- The window now works down to 300 pt wide. Before this change, the columns
  kept their widths and the window overflowed. That cropped the left edge of
  the sidebar and the right edge of the inspector. The inspector now folds
  below approximately 1060 pt, and its toolbar button gives the reason. The
  sidebar folds below 800 pt. Both return when the window becomes wider, and
  the toolbar toggle still opens the sidebar in a narrow window. The transcript
  header, the info row, the player bar, the buttons and footer of the live
  view, the sidebar filter and the first-run card each have a compact form.
- Playback keeps the current turn in view. If you scroll by hand, the app stops
  this. The Follow button, or the "Follow playback" pill, starts it again.
- Settings is a resizable window with General, Audio, Models and Storage panes.
  You can download a model before you need it, with progress, or delete it.
- "Transcribe while recording" now does what its name says. If it is off, the
  Mac only records during the meeting, and the whole-file pass makes the
  transcript after you stop.
- Sidebar: double-click a recording, or use Rename, to retitle it in place. An
  Active filter shows what records or transcribes now. The status chip gives
  the time that remains. If you import a file that matches one in the library,
  the app asks before it makes a second copy.
- Export: Markdown minutes with attendees, summary, action items with
  checkboxes, and then the transcript. The Export menu also gives Copy as Text
  and Copy as Markdown. You can export selected speakers only, or one time
  range only. The app remembers the last format.
- The app stores a warning about an imperfect job with the recording, and shows
  it in the sidebar, the header and the info popover. A background job that
  fails no longer opens an alert over the current view. The live footer keeps
  the model and the language and moves the engineering numbers into Stats.
- Meeting workspace: the panel is the system inspector, and you can resize it
  by drag. It remembers its open state separately for a recording and for a
  meeting. Each tab shows a count. A quick-add row at the top takes a note of
  any kind. An empty note kind collapses to one add row.
- Each speaker has a coloured initials badge. ⌘[ and ⌘] step through the turns.
  ⌥↑ and ⌥↓ change the speed. View › Show Times of Day (⌥⌘T) shows the time of
  day of each turn instead of the offset from the start. Hover on a bookmark
  tick on the waveform to see its label, and click the tick to go there.
- First run: a card in the empty pane checks microphone access, offers the
  speech model download with progress, and sets the language. It does this
  before your first ⌘R.
- A model download before a recording, or before a whole-file job, shows a
  progress bar and a percentage instead of a spinner.
- If you stop a recording under ten seconds, the app asks Keep or Discard.

### Releases

- **The app does not update itself.** It downloads no code, checks no
  signature and replaces no bundle. It therefore makes one network request
  only: the model download at the first start.
- **Notero ▸ Releases on GitHub…** opens the releases page in your browser.
  Settings ▸ About holds the same link, with the version of this copy. To move
  to a newer version, get the zip from that page and replace the app.
- `app/scripts/release.sh` builds, packages and publishes a release.
  [docs/RELEASE.md](docs/RELEASE.md) gives the procedure.

### Tools and the build

- `transcribe --live` replays a file through the live path, with `--hop`,
  `--pre-roll`, `--context`, `--adaptive-hop` and `--realtime`. `--json` writes
  a machine-readable report. `eval/compare_language.py` compares forced `tl`
  against `auto` and reports Filipino and English word error rates and a
  code-switch error rate. An adaptive hop is available behind
  `SessionConfig.adaptiveHop`. The default is off.
- The build writes the version from `app/VERSION` and the commit count into the
  bundle. GitHub Actions runs `swift build` and `swift test` on each push.
  `app/scripts/snap.sh` makes a screenshot of the app for a visual check.
  AppState is now several files, one for each concern. You can select several
  sidebar rows and delete them together. A failed recording goes under Needs
  Attention.
- README.md now shows the app. `app/scripts/make-demo-meetings.sh` builds the
  three synthetic Taglish meetings behind those screenshots, thus no real
  meeting goes into this repository. Its comments give the `CFFIXED_USER_HOME`
  route to a demo library that leaves your own recordings alone.

## Before this repository was public

The builds below are private. They have no tag and no download: this
repository became public on 2026-09-04, and 1.0.0 above is the first release
on the releases page. The numbers are the numbers that each bundle carried at
the time, thus the 1.0 here is not the 1.0.0 above. They stay in this file as
the record of how the app reached its shape.

### 1.0.1 — 2026-09-03 (private build)

- When the app starts, it resolves each recording that a quit left in the
  preparing, recording or transcribing state. If the transcript exists, the app
  marks the recording complete. If it does not, the app marks the recording failed and
  gives a message that says what to do. The app deletes nothing.
- Settings shows the microphone permission state and the correct action for it.
  It asks one time, or it opens System Settings after a refusal.
- An info bar under the title gives the model, the language, the number of
  words, the processing ratio and the revision. An ⓘ popover shows everything
  that the app stores about the transcript.
- The model load before a recording is now a preparing state in the header, the
  toolbar and the detail pane. Before this change, the load looked like a hang.
- If a write of the working copy fails, the message gives the path, the reason
  and the free space on the volume. Audio cache progress is in whole percent.
- The plan for 1.1 is in `docs/APP-UPDATE-PLAN.md`.

### 1.0 — 2026-09-02 (private build)

- The first native macOS build.
