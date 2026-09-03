# Changelog

## Unreleased (1.1)

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
- Stopping under ten seconds asks Keep or Discard. Several sidebar rows can be
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
