# How to use Notero

What each part of the app does. For the build, read
[DEVELOPMENT.md](DEVELOPMENT.md). For the design, read
[ARCHITECTURE.md](ARCHITECTURE.md). For the command-line tool, read
[CLI.md](CLI.md).

## Simple and Advanced

The app has two modes. **Simple** is the default. It shows the recordings, a
button to record, a button to transcribe a file, the transcript and the notes.
The app selects the model and the audio settings. **Advanced** adds the model
tiers, the audio controls, the benchmark, the decode statistics and the
transcript revisions.

To change the mode, click the mode name at the bottom of the sidebar, or
select **View › Advanced Mode** (⌥⌘A), or go to **Settings › General › Mode**.
The two modes use the same library and the same pipeline.

This document describes the Advanced mode. A setting that this document names
is not on the screen in Simple mode.

## Record or import

**Record.** Click **Record** in the toolbar, or press ⌘R. The app asks for the
microphone permission at the first recording, and not before. The app records
from the microphone and writes two files from one audio tap. The first file is a 64 kbps AAC archive at the hardware sample rate.
The second file is a 16 kHz mono working copy for the models. Both files come
from the same tap, thus their samples stay aligned.

**Pause.** Click **Pause** (⇧⌘P) to stop the clock and the file during a
break. Click **Resume** to continue. The break is not in the recording, and
the transcript continues with no gap. **Mute** is different: the clock
continues, and the file gets silence for the length of the mute. A time of day
in the transcript does not count the paused time.

**The menu bar.** Notero puts an item in the menu bar. Click it to record,
pause, resume or stop from any application, and to add a bookmark. During a
recording, macOS draws its orange microphone indicator on the item. Open the
menu to see the clock and the paused state. Two shortcuts work in every application
while the item is on: ⌃⌥R starts or stops a recording, and ⌃⌥P pauses or
resumes it. To hide the item, turn off **Settings › General › Show Notero in
the menu bar**. This also removes the two shortcuts.

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
that device only, and it tells you if the device is not connected. If the
device disconnects during a recording, the recording continues on the default
input of macOS and shows a message. The recording keeps the message as a
warning.

**Transcribe a file.** Drop an MP3, WAV, M4A, AIFF, MP4 or MOV file on the
window or on the Dock icon. You can also click **Transcribe a File** (⌘O), or
select **Open With › Notero** in the Finder. The window shows a frame while a
file is over it. The app copies the file into the library and adds it to the
queue. If a file with the same size is already in the library, the app asks
before it imports a second copy.

## Transcribe

**Live text is off by default.** The app records only, and it makes the
transcript when you stop. Nothing runs on the Mac during the meeting, and the
app loads no model at the start. To see text during a recording, turn on
**Settings › General › Show text while you record**.

**Live text**, when it is on, decodes a 15-second context every 1.5 seconds and
applies LocalAgreement-2. **Committed text never changes later.** Each decode
also reads 1.5 seconds of committed audio in front of the active region, thus
the model does not start cold at a commit boundary. When the voice detector
hears 700 ms of silence, the app decodes the audio up to that pause and closes
the utterance. The app drops a word that the model places inside such a pause,
because the model read it out of silence.

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

### Draft the notes automatically

On macOS 26 with Apple Intelligence on, the notes pane has a button, **Draft
Notes from the Transcript** (⇧⌘D). The Apple Intelligence model on this Mac
reads the transcript in parts and proposes a summary and notes of the five
kinds. Nothing leaves the Mac.

**The app writes nothing until you select it.** A sheet shows the draft. Each
note has a checkbox and the moment it came from, thus you can play the line
before you keep the note. The summary has a checkbox too. If you wrote a
summary, the draft does not replace it unless you select that.

**The model does not accept Tagalog.** It refuses a part of the transcript
that is mostly Tagalog before it reads it. On a 93-minute Taglish meeting, a
part with 28 % Tagalog words was accepted and parts with 50 % or more were
refused. A Taglish meeting therefore gets the message "The model does not
accept the language of this transcript", and no draft. Finding 13 in
[FINDINGS.md](FINDINGS.md) gives the measurement, and the measurement of the
models that do accept Taglish, none of which is in the app. An English
meeting works.

**Settings › General › Automatic notes** selects the language of the notes:
English, or the mix of languages that the speakers used.

**Draft after every recording, with no button.** Turn on **Draft the notes
when a recording is complete** in the same place. The app then drafts as soon
as a transcript is ready and shows you the sheet. It is off unless you turn it
on, because it costs time on the chip after every recording.

**The model never runs during a recording.** An automatic draft waits until
the recording stops, and a draft that is already running stops when you press
Record. The speech model and the notes model would otherwise share one chip,
and a decode that arrives late is words missing from the transcript. This is
the same rule that stops the transcription queue during a recording.

## Edit the transcript

**Transcribe one turn again.** Right-click a turn and select **Transcribe
This Turn Again**. The app decodes only that turn, on the Accurate tier in
Simple mode and on the tier that you select in Advanced mode, and replaces the
lines of the turn. The rest of the transcript does not change, and the turn
keeps its speaker. A four-hour meeting with one bad window is therefore fixed
in seconds. The first run on the Accurate tier downloads its model.

Double-click a turn to edit it line by line. The app keeps the raw model output
below your edit. The search index and the exports read the edited text.

You can restore a line, delete it, or move it to a different speaker. Press ⌘Z
to undo all edits to one turn in one step. A menu in the info bar shows the
earlier revisions.

## Your corrections as references

Each edit that you make is stored beside the raw model text. A recording with
edits is therefore a scored pair: the raw text is the hypothesis, and your
edited transcript is the reference. In Advanced mode, select **File › Export
Corrections as References…** and select a folder. The app writes a dated
folder with a copy of each corrected recording, its reference text, the raw
text, the corrected lines with the raw text beside each, `manifest.json` for
the evaluation harness, and `summary.md`. The summary scores the raw text
against your corrections with no new decode.

To score a configuration against the folder, from the repository root:

```bash
python3 eval/compare_language.py --manifest FOLDER/manifest.json \
    --bin app/.build/release/transcribe --models models --arms tl
```

**The folder holds real meetings.** Do not attach it to a public issue.

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
| ⌘R | Record. In Advanced mode, ⇧⌘M makes a meeting and ⌘N makes a note |
| ⇧⌘P | Pause or resume the recording |
| ⌘. | Stop the recording |
| ⌃⌥R | Start or stop a recording, from any application |
| ⌃⌥P | Pause or resume the recording, from any application |
| ⌘O | Transcribe a file |
| ⌘E | Export |
| ⌥⌘A | Advanced mode on or off |
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
