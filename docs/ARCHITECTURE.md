# Architecture

How the native macOS app is designed. This document explains the structure and
the algorithms. It does not explain how to use the app. For the build and the
tests, read [DEVELOPMENT.md](DEVELOPMENT.md). For the command-line tool, read
[CLI.md](CLI.md).

## The Swift package

```
app/            Swift 6 and SwiftUI. The product.
├── Sources/TranscriberCore/     pure logic: commit policy, merger, exports, search
├── Sources/TranscriberStore/    SwiftData schema and queries
├── Sources/TranscriberEngine/   audio, WhisperKit, FluidAudio VAD and speaker models
├── Sources/TranscriberFlow/     the app's decisions with no window
├── Sources/Transcriber/         the SwiftUI app
└── Sources/TranscriberCLI/      the same pipeline, with no window
```

The app is Notero, but the Swift modules and the data directory keep the name
Transcriber, which the app had through its private builds. The data directory
holds the recordings that those builds wrote, thus a rename there hides them.
The module names are internal, and a rename gives the user nothing.

## The five layers

Each layer builds and tests without the layer above it:

| Layer | Can depend on | Must not touch |
| --- | --- | --- |
| `TranscriberCore` | nothing | AVFoundation, CoreML, SwiftUI, SwiftData, models |
| `TranscriberStore` | Core | inference of any kind |
| `TranscriberEngine` | Core | SwiftUI |
| `TranscriberFlow` | Core, Store, Engine | SwiftUI, AppKit |
| `Transcriber` | Core, Store, Engine, Flow | — |

This split lets you test the commit policy, the segment merger, the exporters
and the search index on a Mac that has no microphone and no model weights. That
property is what keeps the CI job free of secrets and free of model downloads.

The diagram in the [README](../README.md) shows the same layers as a stack,
from the user interface down to the models. The table above is the dependency
rule. `TranscriberStore` and `TranscriberEngine` both depend on
`TranscriberCore` and not on each other. `TranscriberFlow` and the SwiftUI app
see all three.

### `TranscriberCore`

Pure logic and no framework. It holds `LocalAgreement` (the commit policy),
`SegmentMerger` (transcript and speaker spans into turns), `Exporter` (the five
formats), the search index, `RingBuffer`, `HighPassFilter`, `WordErrorRate`,
`Benchmark`, and the `PCMSource` protocol. `Catalogues.swift` holds the model
catalogue, the language catalogue, `ModelTier` and `DiarizationMode`.

### `TranscriberStore`

The SwiftData schema and the queries. The model objects are `StoredRecording`,
`StoredTranscript`, `StoredSegment`, `StoredSpeaker`, `StoredBookmark`,
`StoredMeetingItem` and `StoredTag`. `TranscriptWriter` writes a new revision.
`LiveTranscriptPersister` appends committed lines while a recording runs.

### `TranscriberEngine`

The audio and the models. `AudioCapture` owns the capture. The capture is
the microphone, the audio of this Mac through `SystemAudioTap`, or both.
`AudioDevices` lists the microphones.
`AudioCache` builds the 16 kHz working copy. `WhisperEngine`, `VADEngine` and
`SpeakerEngine` wrap WhisperKit and FluidAudio. `LiveDecoder` and `LiveSession`
run the live path. `OfflinePipeline` runs the whole-file path.
`TranscriptionQueue` runs the background jobs. `EngineHost` owns the models.
`BenchmarkRunner` measures the tiers. `NotesEngine.swift` holds the
`NotesGenerating` seam, `NotesPipeline` and the Apple Intelligence backend for
the automatic notes.

### `TranscriberFlow`

The decisions of the app, with no window and no AppKit, so a test can make
them. `JobCoordinator` consumes the events of the transcription queue, writes
to the store through `TranscriptWriter`, and holds the three values the views
read about a job: the progress, the warning and the transcript tick. It also
takes the three commands: enqueue, cancel and add a warning.
`RecordingDisplayStatus` is the one ladder from the stored status, the job
progress, the live session and the warning to what a row, a header and an
empty transcript show. `StopPlan` decides what a stop of the live session does:
the failure warning, where the live transcript goes, the follow-up job, the
device-notice warning and the short-take question. The app executes the plan.
`NotesCoordinator` holds one draft of automatic notes per recording, from the
request through the progress to the review, and writes nothing to the store.

Before this layer existed, the first three lived on the app state as private
methods and internal dictionaries, and no test reached them.

### `Transcriber`

The SwiftUI app. `AppState` and its extensions hold the observable state for
the library, the jobs, the recording and the models. `Views/` holds the window,
the sidebar, the transcript view, the meeting panes, the settings, the export
sheet and the benchmark. `About.swift` holds the version of this copy and the
address of the releases page, which is the only address in the app target.

### `TranscriberCLI`

`transcribe` is three files, `main.swift`, `Record.swift` and `Notes.swift`. It
is not a second implementation. It calls `OfflinePipeline`, `LiveDecoder`,
`SpeakerEngine`, `NotesPipeline` and `Exporter` exactly as the app does. It
therefore verifies the real path on real audio with no window, no microphone
and no person. That is what makes it usable from CI and from the evaluation
harness in `eval/`. [CLI.md](CLI.md) gives its options.

## The engine protocols

Three protocols in `TranscriberEngine/Protocols.swift` and one in
`TranscriberEngine/NotesEngine.swift` hide the backends:

| Protocol | Current backend |
| --- | --- |
| `SpeechRecognizing` | WhisperKit |
| `VoiceActivityDetecting` | FluidAudio Silero VAD, with an energy fallback |
| `SpeakerDiarizing` | FluidAudio pyannote segmentation and WeSpeaker embedding |
| `NotesGenerating` | The Apple Intelligence model, through Foundation Models, on macOS 26 |

To replace a backend, write a new conformance to the related protocol. You do
not have to change the user interface. The tests use fake conformances, which
is why they need no model weights.

## Audio capture

The app writes two files from one audio tap:

1. A 64 kbps AAC archive at the hardware sample rate. This is the recording
   that you keep.
2. A 16 kHz mono working copy for the models.

Both files come from the same tap, thus their samples stay aligned. An imported
MP3, WAV, M4A, MP4 or MOV file goes into the library, and `AudioCache` builds
the same 16 kHz working copy from it.

A recording can hold two lanes. The room lane comes from the microphone. The
remote lane comes from the audio of this Mac, through a Core Audio process tap
in `SystemAudioTap`. The archive keeps the two lanes in different channels of
one file: channel 1 is the room and channel 2 is the call. The live decoder
reads the sum of the two lanes. The whole-file pass decodes each lane on its
own and identifies the speakers in each lane on its own. `LaneTranscript` then
puts the two transcripts in time order. A room line that repeats a remote line
at the same moment is the speakers heard by the microphone, and the merge drops
it. The remote lane holds the clean copy.

The remote lane goes through a soft limiter that starts at 3 dB under full
scale, because a call application sends its mix with no headroom. If a device changes during a
recording, the capture restarts on the device that is available, converts its
samples to the rate of the archive, writes the lost time as silence, and
reports the change to the recording screen.

**Mute and pause are two switches on `AudioCapture`.** Mute writes silence:
the timeline stays on the wall clock, and the transcript stays in step with
the file. Pause drops the frames: nothing reaches the archive, the working copy
or the decoder, the clock of the recording stands still, and resume continues
on the same timeline with no gap. The input keeps running during a pause, thus
resume is immediate, and the app still handles a device change during the pause.

## Live transcription

`LiveDecoder` owns everything between a chunk of PCM and a committed token.
`LiveSession` owns the microphone, the working copy and the state that the user
interface reads. This split makes the schedule testable: give the decoder a
scripted recognizer and a scripted voice detector, and each rule below runs in
a test with no model and no microphone.

Three rules govern the schedule:

- **A hop happens every 1.5 seconds of audio.** It decodes the whole window,
  which is the committed pre-roll, the active region and the silence that
  arrived. One decode runs at a time. A hop that starts while another decode
  runs is dropped and not put in a queue, because a stale partial result is
  worse than no partial result.
- **The voice detector triggers finalization, and not the hop.** When trailing
  silence reaches 700 ms and uncommitted speech exists, the decoder asks for a
  final decode at once. It runs immediately if the slot is free. If the decode
  in flight is a hop whose window already reached the end of the speech, the
  decoder uses that result and makes no second decode.
- **A boundary concludes only after LocalAgreement**, and only if the room is
  still silent when the decode returns. The agreed prefix commits as usual. The
  remainder commits from the final hypothesis at that confirmed boundary. If a
  person started to speak again during the decode, nothing commits unagreed.
- **A confirmed pause is silence in every hypothesis.** The decoder records
  each pause that the voice detector confirms at 700 ms or longer. The decoder
  drops a word that the model places inside one, with 250 ms of slack at each
  edge, from a hop as well as from a final decode. Finding 12 in
  [FINDINGS.md](FINDINGS.md) gives the failure this stops: a phrase read out of
  a pause by a hop, kept when speech resumed before the final decode returned,
  and committed when the next two hops agreed on it.

Live text is off by default. `AppSettings.liveTranscription` is false unless
the user turns it on, and the app then loads no model at the start.

`SessionConfig` holds the measured defaults:

| Setting | Default | Purpose |
| --- | --- | --- |
| `contextMs` | 15000 | The trailing audio that each hop decodes again |
| `hopMs` | 1500 | How often a decode is attempted |
| `silenceBoundaryMs` | 700 | The trailing silence that ends an utterance |
| `agreement` | 2 | The passes that must agree before a token commits |
| `preRollMs` | 1500 | Committed audio kept in front of the active region |
| `adaptiveHop` | off | Shorten the hop while decodes are fast |
| `minHopMs` | 1000 | The floor for the adaptive hop |

**LocalAgreement-2 commits a token when two consecutive passes agree on it.**
Committed text never changes later. The policy compares the prefixes of
consecutive hypotheses, thus consecutive windows must start at the same point
in the audio. A ring buffer that slides freely breaks the policy permanently.
Finding 5 in [FINDINGS.md](FINDINGS.md) records that failure.

**The pre-roll is context only.** Nothing in it can commit a second time. The
ring buffer keeps it, and `LocalAgreement` drops by timestamp whatever the
model reads again from it. The decoder drops the boundary word by text when its
times drifted. Without the pre-roll, each decode starts cold at a commit
boundary, which cost six WER points in finding 11.

`SessionStats` counts the hops, the dropped hops, the silent hops, the forced
commits, the boundaries, the final decodes, the unagreed tail words and the
deduplicated words. The recording footer shows them. Each counter exists
because it was once a bug that nothing made visible.

## Whole-file transcription

`OfflinePipeline` does not make one call for the file, and it does not make one
call for each hop.

1. **Find the speech.** Silero VAD finds the speech regions. The detector takes
   an array, thus the pipeline hands it 5-minute windows. It never reads the
   complete file.
2. **Pack the windows.** The pipeline packs the speech regions into windows
   that are shorter than the 30-second receptive field of Whisper, and that end
   in silence where a pause is available. `maxWindowMs` is 28000, which leaves
   room for 200 ms of padding at each side.
3. **Decode each window one time.** Silence is never decoded, because Whisper
   invents sentences in silence. Peak memory is one window and not one file.
4. **Drop the hallucinated tail.** Whisper pads each input to 30 seconds and
   decodes the padding. The pipeline refuses a word that starts more than
   250 ms past the audio that the window contained.

**A refused window is retried on different audio.** WhisperKit can return an
empty result set for a window and report no error. The retry widens the window
by 700 ms, then by 1400 ms, then cuts the window in half and retries each half,
to two levels of splitting. The pipeline counts a window that nothing decodes
and shows the count to the user. A short transcript must never pass for a
complete one. Finding 9 in [FINDINGS.md](FINDINGS.md) records the failure that
made this necessary: one refused window deleted 44% of a transcript, and every
stage reported success.

The app scans and decodes the file in 5-minute batches, thus the transcript
starts to appear early on a long recording. The two stages stay sequential, and
they therefore do not compete for the Neural Engine.

## Speaker identification

Speaker identification runs after transcription and never during it. The first
FluidAudio pass finds the turns and the speaker clusters. `SegmentMerger`
normalizes the spans and builds the roster.

There are three modes in `DiarizationMode`:

| Mode | Work |
| --- | --- |
| `off` | Skip the stage. The transcript finishes with speech recognition. |
| `fast` | One pass. Much shorter on a long recording, but it can merge similar voices. |
| `accurate` | The default. It extracts a new embedding for each turn and clusters again. |

The accurate mode exists because the diarizer fuses similar voices that share
one internal 10-second chunk. FluidAudio cuts the audio into fixed 10-second
chunks and extracts one embedding for each local segmentation slot in each
chunk. Finding 10 in [FINDINGS.md](FINDINGS.md) gives the mechanism and the
recording that showed it.

**A segment holds the label from the speaker model (`S1`, `S2`) and never the
name that you gave the speaker.** The display name lives on `StoredSpeaker`.
A rename therefore changes one row, and it stays correct after you transcribe
the recording again. The app numbers the speakers by first appearance, thus the
person who opened the meeting is Speaker 1.

A job can carry `expectedSpeakers`, which is the number of people that the user
says were in the room. It is a target for the clustering and never a cap.

## How the app reads a transcript

`TranscriptReader` in `TranscriberStore` reads the rows of one transcript as
value types: one fetch with a predicate on the transcript and a sort descriptor
on `startMs`, on a `@ModelActor` with its own context. `StoredTranscript.
orderedSegments` runs the same fetch on the context of the row. Before this,
each reader walked the `segments` relationship, which returned a fault for
each row and fired every fault in the sort. A 4000-row transcript took 278 ms
on disk that way, on the main thread, and the transcript view did it again on
each redraw. The fetch takes 50 ms, and the view runs it off the main thread.

The view reads again only when the rows change. `StoredRecording.updatedAt`
moves on each write from the user interface. `AppState.transcriptTicks` moves
on each write from a job: a batch of partial rows, the final rows, the speaker
labels. The view does not count the rows.

A new `TranscriptReader` for each read, on purpose. A context keeps the values
it has loaded, and a fetch does not refresh them, thus a long-lived reader
would return an edit that the main context saved a moment ago in its old form.

## One turn again

`TranscriptionJob.Work.range` decodes one stretch of a recording again.
`OfflinePipeline.transcribeRange` runs the voice detector over the stretch,
packs the windows as the whole-file pass does, decodes them with the retry
ladder, and keeps only the words that start inside the stretch. The queue
stamps the speaker of the turn on the new rows, and
`TranscriptWriter.replaceSegments` deletes the rows that start inside the
stretch, inserts the new rows and renumbers the transcript. The rows change in
place, in the latest revision: a new revision for forty seconds of a four-hour
meeting would copy every row and break every note that points at one.

## Transcript revisions

A transcript is a revision and not a mutable document. `StoredRecording` holds
many `StoredTranscript` rows, each with a `revision` number, the model id, the
language and the stage timings. `recording.transcript` returns the highest
revision.

`TranscriptWriter.replace` writes a new revision instead of a change to the
existing one, because notes and action items hold segment ids. A new revision
therefore keeps the transcript that the user annotated.

`StoredSegment` has two text fields. `text` is what the model produced, and
nothing rewrites it. `textClean` is the edit, and it is nil until a person
edits the line. `displayText` returns `textClean ?? text`. The search index and
the exports read `displayText`. The user can restore a line, delete it, or move
it to a different speaker. One undo step reverts each edit to one turn.

`LiveTranscriptPersister` opens a revision when a recording starts and appends
the committed lines in batches of approximately one second. After a crash in
the middle of a meeting, everything up to the last commit is still in the
library.

## Memory management

The models set the memory budget on a 16 GB Mac. large-v3-turbo holds
approximately 1.6 GB, and the two speaker models hold approximately 200 MB
more. macOS starts to compress memory well before the ceiling.

`EngineHost` is therefore the one owner:

- **One instance of each model.** The live path and the background queue share
  them.
- **The speaker models are released** as soon as no job needs them.
- **The queue refuses to start work while a recording runs.** A background
  decode competes for the Neural Engine and makes a live hop 3 seconds long
  instead of 0.9 seconds. A dropped hop is dropped words.

**The app never reads a complete audio file into memory.** It maps the 16 kHz
working copy through `MappedPCM` and reads it in slices through the `PCMSource`
protocol. Two hours of audio in a `[Float]` array holds 460 MB. On a Mac that
already holds the model, that difference makes the Mac swap memory to disk.

The app deletes the working copy after transcription and speaker
identification are complete. If you run either stage again, the app builds the
working copy again from the archive. `TranscriptionJob.discardCacheWhenDone` is
false while the user is likely to run a stage again.

## Room mode

`HighPassPCM` wraps the source and applies `HighPassFilter` at 250 Hz, which
is `HighPassFilter.roomCornerHz`. The queue reads the setting when it puts the job in the queue, and
it does not store the mode on the recording. A meeting that was captured in the
wrong mode is therefore fixed with the switch and one more transcription.

## Automatic notes

The notes model reads the transcript in parts and writes into the shape the
user fills by hand: a summary, and `MeetingItemKind` rows with a source line.
Nothing is written until the user has selected what to keep.

```
segments ──► NotesChunker ──► parts ──► NotesGenerating ──► ChunkNotes
                                              │                   │
                                        (one call each)     NotesReducer
                                                                  │
                                              summaries ──► NotesGenerating ──► NotesDraft
```

`NotesChunker` in `TranscriberCore` cuts the transcript into parts of at most
5,000 characters, at turn boundaries. Apple's model has a window of 4,096
tokens for the instructions, the part and the answer together, and Tagalog
costs more tokens per word than English, thus the budget is in characters and
it is low. Each line of a part is `[m:ss] Name: text`, and the model is asked
to copy the timestamp of the line that a note comes from. `NotesReducer`
resolves that timestamp to the line at or before it, inside the part only: a
timestamp outside the part is a copy error, and the note keeps no link. Two
notes of the same kind that share 70 % of their content words are one note.

`NotesPipeline` in `TranscriberEngine` runs the parts through a
`NotesGenerating` backend and knows two recoveries. A part that the model
reports as too long is cut in two and each half is read, down to one line. A
part that the content filter refuses is skipped, and the draft carries a
warning that says so. A language refusal is not recovered: the rest of the
transcript is in the same language, and a draft made from the parts that
happened to pass would misrepresent the meeting.

`FoundationNotesEngine` is the backend on macOS 26: the Apple Intelligence
model through the Foundation Models framework, with guided generation, thus the
answer is a typed value and not text to parse. **It refuses Tagalog.** Measured
on 2026-09-06 on a 93-minute Taglish meeting, a part with 28 % Tagalog words
was accepted and parts with 50 % and 92 % were refused before any generation,
with the default and the permissive guardrails alike. Finding 13 in
[FINDINGS.md](FINDINGS.md) gives the measurement, and the measurement of the
MLX models on the same meeting. A second backend for those models is a new
conformance to `NotesGenerating` and one line in `AppState+Notes`.

`NotesCoordinator` in `TranscriberFlow` holds one state per recording:
running with the progress, ready with the draft, or failed with the message.
The pane shows the state; the sheet shows the draft; `RecordingStore.apply`
writes the rows the user selected. The package on macOS 15 builds without the
framework, and the pane shows no button there.

`NotesScoring` in `TranscriberCore` is how a backend is measured before it is
trusted: grounding (the content words of a note that occur in the transcript
near its timestamp), the language mix of the transcript against the notes, and
the coverage of the hand-written notes by the draft. `transcribe --notes`
reports the three for the Apple model and `eval/notes_eval.py` for an MLX model,
on the app's JSON export of a recording.
