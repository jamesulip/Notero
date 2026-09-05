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
├── Sources/Transcriber/         the SwiftUI app
└── Sources/TranscriberCLI/      the same pipeline, with no window
```

The app is Notero, but the Swift modules and the data directory keep the name
Transcriber, which the app had through its private builds. The data directory
holds the recordings that those builds wrote, thus a rename there hides them.
The module names are internal, and a rename gives the user nothing.

## The four layers

Each layer builds and tests without the layer above it:

| Layer | Can depend on | Must not touch |
| --- | --- | --- |
| `TranscriberCore` | nothing | AVFoundation, CoreML, SwiftUI, SwiftData, models |
| `TranscriberStore` | Core | inference of any kind |
| `TranscriberEngine` | Core | SwiftUI |
| `Transcriber` | Core, Store, Engine | — |

This split lets you test the commit policy, the segment merger, the exporters
and the search index on a Mac that has no microphone and no model weights. That
property is what keeps the CI job free of secrets and free of model downloads.

The diagram in the [README](../README.md) shows the same four layers as a
stack, from the user interface down to the models. The table above is the
dependency rule. `TranscriberStore` and `TranscriberEngine` both depend on
`TranscriberCore` and not on each other. The SwiftUI app is the only layer that
sees all three.

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
`BenchmarkRunner` measures the tiers.

### `Transcriber`

The SwiftUI app. `AppState` and its extensions hold the observable state for
the library, the jobs, the recording and the models. `Views/` holds the window,
the sidebar, the transcript view, the meeting panes, the settings, the export
sheet and the benchmark. `About.swift` holds the version of this copy and the
address of the releases page, which is the only address in the app target.

### `TranscriberCLI`

`transcribe` is two files, `main.swift` and `Record.swift`. It is not a second
implementation. It calls `OfflinePipeline`, `LiveDecoder`, `SpeakerEngine` and
`Exporter` exactly as the app does. It therefore verifies the real path on real
audio with no window, no microphone and no person. That is what makes it usable
from CI and from the evaluation harness in `eval/`. [CLI.md](CLI.md) gives its
options.

## The engine protocols

Three protocols in `TranscriberEngine/Protocols.swift` hide the backends:

| Protocol | Current backend |
| --- | --- |
| `SpeechRecognizing` | WhisperKit |
| `VoiceActivityDetecting` | FluidAudio Silero VAD, with an energy fallback |
| `SpeakerDiarizing` | FluidAudio pyannote segmentation and WeSpeaker embedding |

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
puts the two transcripts in time order.

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
