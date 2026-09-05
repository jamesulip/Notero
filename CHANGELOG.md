# Changelog

## Unreleased

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
