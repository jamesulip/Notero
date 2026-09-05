# How to use Notero

What each part of the app does. For the build, read
[DEVELOPMENT.md](DEVELOPMENT.md). For the design, read
[ARCHITECTURE.md](ARCHITECTURE.md). For the command-line tool, read
[CLI.md](CLI.md).

## Record or import

**Record.** The app records from the microphone and writes two files from one
audio tap. The first file is a 64 kbps AAC archive at the hardware sample rate.
The second file is a 16 kHz mono working copy for the models. Both files come
from the same tap, thus their samples stay aligned.

**Select the input.** Go to **Settings › Audio › Record**. There are three
inputs:

| Input | What it records |
| --- | --- |
| Microphone | The persons in the room. |
| This Mac's audio | The persons on a call, before the speaker. |
| Both | The two above, in different channels of one file. |

A meeting with remote persons needs both. The microphone cannot hear the
persons on the call, except as the sound of a speaker in a room. The audio of
this Mac cannot hear the room.

With both inputs, the app transcribes each channel independently and then puts
the lines in time order. Each line shows if the person is in the room or on the
call.

**Permission.** The audio of this Mac needs a permission that is different from
the microphone permission. Go to **Settings › Audio › Permissions** to give it.
If you refuse this permission, macOS gives no error and records no audio from
the call.

**Select the microphone.** Go to **Settings › Audio › Record › Microphone**.
The default is the input device of macOS. If you select a device, the app uses
that device only, and it tells you if the device is not connected.

**Import.** Drop an MP3, WAV, M4A, MP4 or MOV file on the window, or on the
Dock icon. The app copies the file into the library and adds it to the queue.

## Transcribe

**Live transcription** runs while you record. It decodes a 15-second context
every 1.5 seconds and applies LocalAgreement-2. **Committed text never changes
later.** Each decode also reads 1.5 seconds of committed audio in front of the
active region, thus the model does not start cold at a commit boundary. When
the voice detector hears 700 ms of silence, the app decodes the audio up to
that pause and closes the utterance.

**Whole-file transcription** runs after a recording, and on each import. It
finds the speech, packs it into windows that end in silence, and decodes each
window one time. The app scans and decodes the file in 5-minute batches, thus
the transcript starts to appear early on a long recording. A banner gives the
stage, the percentage and the time that remains. A job that stops part-way
keeps what it had, with the label Partial.

**Select the language in Settings.** The default is Tagalog, which also covers
Taglish. The app does not translate the transcript and does not rewrite it. It
writes code-switched English inside another language as the speaker said it.
[MODELS.md](MODELS.md) lists the languages and explains why automatic detection
carries a risk.

**Select the speed tier in Settings.** Fast, Balanced and Accurate.
[MODELS.md](MODELS.md) gives the model behind each tier. Press ⇧⌘K to measure
all three on your own audio.

**Room mode** applies a high-pass filter for far-field room audio. The app
reads the switch when it puts the job in the queue. A meeting that was captured
in the wrong mode is therefore fixed with the switch and one more
transcription.

## Identify the speakers

Speaker identification runs after transcription. The app numbers the speakers
by first appearance, thus the person who opened the meeting is Speaker 1.

There are three modes in Settings:

| Mode | Behaviour |
| --- | --- |
| **Accurate** | The default. It examines each turn a second time. |
| **Fast** | One pass only. Much quicker on a long recording, but it can merge similar voices. |
| **Off** | It skips the stage. |

**A rename changes one row.** A segment holds the label from the speaker model
and never the name that you gave the speaker. A rename therefore stays correct
after you transcribe the recording again.

You can merge two speakers, and you can move one turn to a different speaker.

## Take notes

A meeting has a summary and five lists: key points, decisions, action items,
questions and follow-ups. **Each item keeps the timestamp and the segment that
it came from.** You can therefore compare a decision to the words that the
speaker said.

Press ⌘B to bookmark the moment during a recording or during playback.

## Edit the transcript

Double-click a turn to edit it line by line. The app keeps the raw model output
below your edit. The search index and the exports read the edited text.

You can restore a line, delete it, or move it to a different speaker. Press ⌘Z
to undo all edits to one turn in one step. A menu in the info bar shows the
earlier revisions.

## Find it again

Search reads the transcripts, the notes, the action items and the bookmark
labels. It ignores case and diacritics. When you open a result, the app opens
the recording and moves to that moment.

## Export

| Format | Contents |
| --- | --- |
| TXT | The speaker labels and the notes. |
| Markdown | Minutes: attendees, summary, action items with checkboxes, then the transcript. |
| SRT | Subtitle cues in order, which do not overlap. |
| VTT | The same cues as WebVTT. |
| JSON | The complete meeting. |

You can also export selected speakers only, or one time range only.

## Keyboard

| Keys | Function |
| --- | --- |
| ⌘R, ⇧⌘M, ⌘N | New recording, meeting or note |
| ⌘. | Stop the recording |
| ⌘O, ⌘E | Import, export |
| ⌘F | Find in this transcript |
| ⇧⌘F | Search all recordings |
| ⌘B | Bookmark this moment |
| ⌃⌘K, D, A, Q, U | Add the selection as a key point, decision, action, question or follow-up |
| Space | Play or pause. ⌥Space does this from any view. |
| ⌥←, ⌥→ | Go back or forward 5 seconds |
| ⌘[, ⌘] | Previous turn, next turn |
| ⌥↑, ⌥↓ | Faster playback, slower playback |
| ⌥⌘T | Show the time of day |
| ⇧⌘K | Model benchmark |
| ⌘, | Settings |

## Configuration

**The app has no configuration.** It has no configuration file, no environment
variables, no accounts and no keys. All adjustable items are in Settings (⌘,),
and macOS keeps them in user defaults.

The app writes the recordings and the SwiftData store to
`~/Library/Application Support/Transcriber/`. The model weights go to
`~/Library/Application Support/Transcriber/Models`. The directory keeps the
name Transcriber, because it holds the recordings that the private builds
wrote.

**The app adds no encryption of its own, thus FileVault is the only
protection.** An export contains the full transcript, word for word. Read an
export before you send it to another person.

## A newer version

**The app does not update itself.** It downloads no code, checks no server for
a version, and replaces nothing on your Mac by itself.

**Notero ▸ Releases on GitHub…** opens the releases page in your browser.
Settings ▸ About holds the same link and the version of this copy.

To move to a newer version:

1. Open the releases page and download the zip of the version that you want.
2. Unpack it.
3. Quit Notero.
4. Replace the old `Notero.app` with the new one.

Your recordings, transcripts and notes are in
`~/Library/Application Support/Transcriber/`. **A replacement of the app does
not touch that directory.**

**macOS asks for microphone access again after you replace the app.** The
bundle has an ad-hoc signature and not a Developer ID, and macOS connects the
permission to the signature. Gatekeeper also refuses a bundle that a browser
downloaded. To open it the first time, right-click the app and select Open, or
build the app yourself. [DEVELOPMENT.md](DEVELOPMENT.md) gives the build.
