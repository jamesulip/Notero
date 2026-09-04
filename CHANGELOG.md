# Changelog

## 1.1.0 (unreleased)

- Transcripts appear while a whole-file job runs: each decoded window's
  segments land in the store as it finishes, under a banner with the stage,
  percent and time remaining. A job that dies part-way keeps what it had,
  labelled Partial.
- Speakers can be merged (right-click in the Speakers pane) and a single turn
  moved to another speaker (right-click a transcript line). The pane sorts by
  talk time, draws talk-time bars and flags likely fragments.
- "People in the room" on a recording gives speaker identification a target.
  A soft one: clusters closer than a relaxed distance are folded together
  until the count is met; clearly different voices stay separate.
- Transcribe Again names each tier; Identify Speakers Again runs the speaker
  pass alone.
- Transcript editing: double-click a turn to edit it line by line. Edits keep
  the raw model output underneath and are what search and exports read. A
  line can be moved to another speaker, restored, or deleted. ⌘Z undoes a turn's
  edits in one step.
- ⌘F finds within the open transcript, with matches highlighted in place;
  ⇧⌘F searches the whole library.
- Playback keeps the current turn in view. Scrolling by hand pauses that;
  the Follow button or the "Follow playback" pill resumes it.
- Earlier transcript revisions can be read from a menu in the info bar.
- Settings is a resizable window with General, Audio, Models and Storage
  panes. Models can be downloaded ahead of time, with progress, or removed.
- "Transcribe while recording" now does what it says. Off, the Mac only
  records during the meeting and the whole-file pass makes the transcript
  when you stop.
- Sidebar: double-click or Rename to retitle a recording in place; an Active
  filter for what is recording or being transcribed; the status chip shows
  time remaining. Importing a file that matches one already in the library
  asks before making a second copy.
- Export: Markdown minutes (attendees, summary, checkable action items, then
  the transcript); Copy as Text or Markdown from the Export button's menu;
  export only chosen speakers or a time range; the last format is remembered.
- Warnings about an imperfect job are stored with the recording and shown in
  the sidebar, the header and the info popover. A background job failing no
  longer raises an alert over whatever is on screen. The live footer keeps
  the model and language and moves the engineering numbers behind Stats.
- Meeting workspace: the panel is the system inspector, resizable by drag,
  and remembers whether it was open separately for recordings and meetings.
  Tabs show counts. A quick-add row at the top takes a note of any kind; empty
  note kinds collapse to a single add row.
- Reading: a coloured initials badge beside each speaker; ⌘[ and ⌘] step
  through turns; ⌥↑ and ⌥↓ change speed; View › Show Times of Day (⌥⌘T)
  shows when each turn was said instead of how far in; hovering a bookmark
  tick on the waveform shows its label and clicking jumps to it.
- First run: a card in the empty pane checks microphone access, offers the
  speech model download with progress, and sets the language, before the
  first ⌘R discovers any of it the hard way.
- A model download before a recording, or before a whole-file job, shows a
  progress bar and percentage instead of a spinner.
- Stopping under ten seconds asks Keep or Discard.
- Housekeeping: the build stamps the version from `app/VERSION` and the commit
  count; `swift build` and `swift test` run on every push in GitHub Actions;
  `app/scripts/snap.sh` screenshots the running app for visual checks;
  AppState is split into files by concern. Several sidebar rows can be
  selected and deleted together. Failed recordings group under Needs Attention.

## 1.0.1 — 2026-09-03

- Recordings a quit left in preparing, recording or transcribing are resolved at
  launch: completed if the transcript exists, otherwise marked failed with a
  message that says what to do. Nothing is deleted.
- Settings shows microphone permission state with the right action for it
  (ask once, or open System Settings once denied).
- Transcript info bar under the title: model, language, words, processing ratio,
  revision. An ⓘ popover shows everything stored about the transcript.
- The model load before a recording starts is shown as a preparing state in the
  header, toolbar and detail pane instead of looking like a hang.
- Working-copy write failures name the path, the reason and the free space on
  the volume. Audio-cache progress is reported in whole percents.
- Plan for 1.1 in `docs/APP-UPDATE-PLAN.md`.

## 1.0 — 2026-09-02

- First native macOS release.
