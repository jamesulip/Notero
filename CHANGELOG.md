# Changelog

## 1.1.0 (not yet released)

### The name

- The app is now **Notero**. It was Transcriber up to version 1.0. The bundle,
  the window and the menu carry the new name, and the bundle identifier is now
  `local.notero`. macOS asks for microphone access one more time after the
  change, because it grants that access per bundle identifier.
- The Swift modules and `~/Library/Application Support/Transcriber/` keep the
  old name. The directory holds the recordings of version 1.0, thus a rename
  there hides them from the app.

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

### Updates

- The app can update itself. **Notero ▸ Check for Updates…** asks GitHub
  which releases exist. Settings ▸ Updates holds a switch for a check once a
  day at launch. The switch is off until you turn it on, because the request is
  the one thing this app does that leaves the Mac. The request carries no
  identifier, and it sends no recording, transcript or note.
- Each release is signed with an Ed25519 key, and the public half is compiled
  into the app. Before it replaces anything, the app checks the SHA-256 digest
  of the download against the signature file, the signature against the key,
  and the bundle in the download against the bundle identifier and the version
  that the release gives. A download that fails one of those checks is thrown
  away, and the message says which check refused.
- The install quits the app, moves the new bundle into position with a small
  script, and opens the app again. The old bundle stays on disk until the new
  one is in position, thus a failure puts the old one back. The script writes
  what it did to `~/Library/Logs/Transcriber/update.log`.
- The app refuses to install while a recording runs, and when it is in a folder
  that it cannot write. It never asks for an administrator password.
- `app/scripts/release.sh` builds, packages, signs and publishes a release.
  `app/scripts/relkey.swift` makes the signing key and the signatures. Both
  compile `Sources/TranscriberCore/Update.swift`, thus the format that the tool
  writes and the format that the app reads are one piece of code.
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

## 1.0.1 — 2026-09-03

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

## 1.0 — 2026-09-02

- The first native macOS release.
