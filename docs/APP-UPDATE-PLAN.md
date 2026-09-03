# Transcriber 1.1 — update plan

Written 2026-09-03 against the `native-macos-app` branch, from a read of every
view and engine file plus screenshots of the running app (a 3:51:08 meeting
was mid-transcription at the time). Priority follows the deployment: six people
around a table, one Mac, Taglish. The post-meeting whole-file pass is what
matters; live transcription is "okay as it stands".

Effort: **S** under a day, **M** two to four days, **L** a week or more.

**Status, 2026-09-03:** step 0 shipped as 1.0.1. All of Release 1.1 is
implemented: 1.1 (soft speaker target threshold untested on real audio), 1.2,
1.3 (split/merge delivered as per-line speaker moves rather than block
operations), 1.4, 1.5, 1.6. Not yet checked by hand: the edit mode, find bar,
follow-scroll, revision menu, and the new Settings window (2.1, done, plus the
"Transcribe while recording" toggle wired to a record-only mode). All of Release
1.2 is done (2.1 through 2.7). Release 1.3 hygiene is done too (CI workflow,
snap.sh harness, VERSION-stamped build, AppState split into +Jobs, +Recording,
+Library, +Models). What remains is a by-hand pass over everything since the
speaker-merge commit, which has not been seen on screen, and tuning the
speaker consolidation distance on the real room recording.

---

## 0. Ship what is already done (today)

The working tree holds a finished, passing batch of work. Commit it as 1.0.1
before starting anything below, so the new work has a clean base.

What is pending:

- Launch-time recovery of recordings a quit left in `preparing`/`recording`/
  `transcribing` (`RecordingStore.recoverInterrupted`, `RecoveryTests`).
- Microphone permission row in Settings, with the ask-once/open-System-Settings
  logic (`MicrophoneAccess`, `MicrophonePermissionRow`, tests).
- Transcript info bar under the title: model, language, words, processing
  ratio, revision (`RecordingInfoBar`).
- Preparing-state UI: header, toolbar spinner and detail routing all switch on
  `isLive`, not `isRecording`, so the cold model load no longer looks like a hang.
- `WavWriter.CannotWrite` names the path, reason and free space; progress from
  `AudioCache.build` is throttled to whole percents.

Housekeeping in the same commit:

- `.gitignore`: `Transcriber*.zip` (a `Transcriber 2.zip` is sitting untracked).
- Decide on `eval/refs/meeting01.txt`. It is a transcript of a real meeting;
  keep it out of the repo unless that is intended.
- `build-app.sh`: bump `CFBundleShortVersionString` to 1.0.1; start a
  `CHANGELOG.md`.

`swift test` passes on the current tree.

---

## 1. Release 1.1 — post-meeting cleanup

Everything here serves the workflow "record the meeting, then fix the
transcript and share it". Ordered by value.

### 1.1 Speaker merge and reassignment — P0, effort M–L

**Evidence.** The sidebar shows **13 speakers** and **14 speakers** on the two
~3 h 50 m recordings of a six-person meeting. The only speaker action in the
app is rename (`RecordingStore.rename`). Far-field audio fragments voices into
phantom speakers, and there is no way to repair that short of re-running.

**Change.**

- `SpeakersPane`: sort by talk time, draw a proportional talk-time bar, and
  flag rows with under 1 % of speech or under 30 s as *likely fragment*.
  Context menu **Merge into…** listing the other speakers; multi-select and
  merge in one go.
- `TranscriptBlockRow`: context menu **Speaker ▸ [roster] / New speaker** to
  reassign one turn.
- Store: `RecordingStore.merge(_:into:in:)` rewrites `speakerId` on the
  segments, sums `speechMs`, removes the row, reindexes search text.
  `RecordingStore.assign(_ speakerId:to segments:)` for single turns.
- Engine: an optional **expected speaker count** on the recording
  (`StoredRecording.expectedSpeakers`), asked for in the Speakers pane
  ("How many people were in the room?"). `SpeakerEngine.recluster` treats it
  as a soft target: while the cluster count exceeds it, merge the closest pair
  *only if* their distance is under a relaxed threshold. Never a hard cap; a
  real seventh voice must survive.
- Re-running diarization (see 1.4) keeps renamed speakers as it does today;
  merges are a property of the current pass and are redone against the new
  roster.

**Files.** `Views/MeetingPanes.swift`, `Views/TranscriptView.swift`,
`TranscriberStore/RecordingStore.swift`, `TranscriberStore/Schema.swift`
(one optional column), `TranscriberEngine/SpeakerEngine.swift`.

**Verify.** Store tests for merge/assign/reindex. A recluster test with
synthetic embeddings: seven clusters and a target of six must merge the closest
pair and leave a distant seventh alone. Then the real 3:51:08 file: speaker
count after suggested merges should land near six.

### 1.2 Progressive transcript and time remaining — P0, effort M

**Evidence.** A 3:51:08 recording sits at "Working on it · Preparing 23 %" over
an empty pane. At RTF 0.1 that is roughly 25 minutes with nothing to read.
`TranscriptionQueue` emits `.transcribed` once, at the end.

**Change.**

- New `JobEvent.segments(id:, segments:, coveredMs:)` emitted after each
  decoded window batch (the pipeline already has a per-window progress hook).
- `TranscriptWriter.appendSegments` creates the new revision on the first batch
  and appends after that; `.transcribed` at the end becomes a finalize.
- `TranscriptView` renders the growing list with a banner:
  *Transcribing · 42 % · about 14 min left · 1:37:00 of 3:51:08*. The estimate
  is elapsed ÷ fraction, smoothed, and it appears only after 5 % so it does
  not flail at the start. The sidebar chip gets the same estimate as a tooltip.
- A failure part-way leaves the partial transcript in place, flagged, instead
  of an empty pane.

**Files.** `TranscriberEngine/TranscriptionQueue.swift`,
`TranscriberEngine/Pipeline.swift`, `TranscriberStore/TranscriptWriter.swift`,
`AppState.swift` (`handle`), `Views/TranscriptView.swift`,
`Views/Components/StatusChip.swift`.

**Verify.** Pipeline test asserting segment events arrive in order and cover
the file; a writer test that appends across batches produce the same rows as
one store. Manually: start a long import and confirm text appears within the
first minute.

### 1.3 Transcript editing — P0, effort M–L

**Evidence.** `TranscriptBlockRow` is read-only. The stated workflow is fixing
the transcript after the meeting, and today that means exporting to a text
editor and losing the audio link.

**Change.**

- Double-click (or ↩ on the selected block) enters edit mode for that block,
  showing its segments as separate editable lines with timestamps, so edits
  keep segment granularity and seek targets stay valid.
- Edits write to the field `displayText` reads, then `RecordingStore.reindex`.
- Block actions: **Split turn here** (new speaker turn from this segment),
  **Merge with previous**.
- Undo through the model context's `undoManager` (⌘Z), scoped to the window.
- Hand edits live on the current revision. Re-transcribing creates a new
  revision and does *not* carry text edits; the info popover says so and
  offers **Show revision N** to read the old one.

**Files.** `Views/TranscriptView.swift` (edit mode), `TranscriberCore/Grouping.swift`
(split/merge helpers), `TranscriberStore/RecordingStore.swift`,
`Views/Components/RecordingInfoBar.swift` (revision picker).

**Verify.** Grouping tests for split/merge; store test that an edit changes
search results; export test that an edited segment exports edited.

### 1.4 Re-run controls — P1, effort S

**Evidence.** **Transcribe Again** silently uses whatever tier Settings holds.
`TranscriptionJob.Work.diarizeOnly` exists but no menu item exposes it, even
though the recovery code's comment assumes one. Accurate-tier re-transcription
is the intended post-meeting step.

**Change.** In the sidebar context menu and the detail header:
**Transcribe Again ▸ Fast / Balanced / Accurate** (current tier marked) and
**Identify Speakers Again**. `AppState.enqueueTranscription` takes an explicit
model id. The header's *Retry* becomes the same menu.

**Files.** `Views/SidebarView.swift`, `Views/DetailView.swift`, `AppState.swift`.

### 1.5 Stop-time triage and bulk delete — P1, effort S

**Evidence.** The sidebar holds recordings of 0:01, 0:03, 0:07, 0:24 and 0:25,
plus one *Failed*. Each is a dead end that has to be deleted one at a time.

**Change.**

- On stop, if the take is under 10 s or committed no words: a sheet with
  **Keep** / **Discard**, Discard default under 3 s.
- Sidebar multi-select, ⌫ to delete with a confirmation naming the count.
- A **Needs attention** group above *Today* for failed rows, with the retry
  menu from 1.4 in its context menu.

**Files.** `AppState.swift` (`stopRecording`), `Views/SidebarView.swift`,
`TranscriberStore/RecordingStore.swift` (`group`).

### 1.6 Follow playback and find in transcript — P1, effort S–M

**Evidence.** `TranscriptView` scrolls only on a search or note back-link. During
playback the highlighted block walks off screen. ⌘F always leaves the
recording for global search.

**Change.**

- Auto-scroll to the playing block when it changes. A **Follow** toggle in the
  player bar turns off on manual scroll; a small *Jump to now* pill re-enables it.
- ⌘F inside a recording opens an inline find bar over the transcript, reusing
  the tokenizer and `HighlightedText`; ⇧⌘F is global search. Enter/⇧Enter step
  through hits.

**Files.** `Views/TranscriptView.swift`, `Views/Components/PlayerBar.swift`,
`AppCommands.swift`, `TranscriberCore/Search.swift`.

---

## 2. Release 1.2 — UI/UX polish

### 2.1 Settings window — effort S–M

**Evidence.** The window is fixed at 560×430. In the screenshot the Models tab
clips the *Model* row under the toolbar and shows a blank ghost header; the
Transcription tab is longer still. The model list shows a download icon that is
not a button.

**Change.** Sidebar-style settings at 720×520, resizable, four panes:
**General** (language, vocabulary), **Audio** (permission, gain, room mode),
**Models**, **Storage**. Each model row gets **Download** with progress and
**Remove**, plus the tier it serves. Stop the 2 s memory poll when the pane is
not visible.

**Files.** `Views/SettingsView.swift`, `TranscriberEngine/EngineHost.swift`
(download progress surface).

### 2.2 Sidebar — effort S

- Inline rename on double-click; today the title is editable only in the
  detail header.
- Filter: **All / In progress / Favorites / Meetings**.
- Import duplicate check by file size and duration: *Already imported on
  Sep 1 — Open it / Import anyway*. The list currently holds several copies of
  one meeting under the same title.
- Rows show the 1.2 time-remaining estimate while processing.

**Files.** `Views/SidebarView.swift`, `AppState.swift` (`importFile`).

### 2.3 Meeting workspace — effort S–M

**Evidence.** A 330 pt column carries summary plus five sections, each with its
own add field, and empty sections take full height. Inspector visibility resets
every time a recording is opened.

**Change.** Collapse empty sections to one *+ Decision* row; counts on the tabs
(*Notes 7 · Bookmarks 3 · Speakers 6*); one add field at the top with a kind
picker (the ⌃⌘K/D/A/Q/U shortcuts already exist); remember inspector
visibility per recording kind in `AppSettings`; use SwiftUI's `.inspector` so
it is resizable and the divider is standard.

**Files.** `Views/DetailView.swift`, `Views/MeetingPanes.swift`, `Settings.swift`.

### 2.4 Export — effort S–M

- **Markdown minutes**: title, date, attendees from the roster, summary,
  decisions, action items with timestamps, then the transcript. This is the
  format that gets pasted into email or chat.
- **Copy transcript** as text or Markdown from the header menu.
- Filter by speaker or time range in the sheet.
- Remember the last format (`AppState.exportFormat` exists but the sheet keeps
  its own state).

**Files.** `TranscriberCore/Exports.swift`, `Views/ExportSheet.swift`,
`Tests/TranscriberCoreTests/ExportTests.swift`.

### 2.5 Status and error surfaces — effort S

- Persist pipeline warnings (`AppState.warnings` is in-memory, per the comment)
  to `StoredRecording.warningMessage` and show them in the info bar.
- A background job failing raises a modal alert over whatever is on screen.
  The row chip and header banner already carry it; drop the alert for queue
  failures and keep it for actions the user just took.
- Live footer: keep model and language, move RTF / decode count / VAD backend
  into an ⓘ popover.

**Files.** `AppState.swift`, `Schema.swift`, `Views/RecordingView.swift`,
`Views/Components/RecordingInfoBar.swift`.

### 2.6 Reading and playback — effort S

- Speaker initials chip next to the name, so colour is not the only cue (eight
  palette colours, and recordings reach fourteen speakers).
- ⌘[ / ⌘] previous and next turn; ⌥↑ / ⌥↓ playback speed.
- Option to show timestamps as wall-clock (*9:47 PM*) using `createdAt`, for
  matching against hand-written minutes.
- Hover tooltip on bookmark ticks in the waveform.

**Files.** `Views/TranscriptView.swift`, `Views/Components/WaveformView.swift`,
`AppCommands.swift`, `TranscriberCore/TimeFormat.swift`.

### 2.7 First run — effort S

The empty detail state gains a one-time card: microphone permission (reusing
`MicrophonePermissionRow`), model download state with a **Download** button,
and the language default. Today the first ⌘R starts a 1.6 GB download with only
the preparing header to explain it.

**Files.** `Views/DetailView.swift`, `Views/MicrophonePermissionRow.swift`.

---

## 3. Release 1.3 — engineering hygiene

- **CI**: a macOS GitHub Actions job running `swift build` and `swift test`.
  Core and Store tests need no models or microphone.
- **Screenshot harness**: put the `screencapture` + CGEvent clicker technique
  into `app/scripts/` so view changes can be checked against the real app.
- **Versioning**: `build-app.sh` takes a version; `CHANGELOG.md` per release.
- **Split `AppState`** (473 lines): move the recording lifecycle
  (`beginRecording`/`stopRecording`/import) into a `RecordingController` so
  the view-facing object stays small.

---

## Order of work

| Step | Items | Effort |
| --- | --- | --- |
| Now | 0 commit, housekeeping | S |
| Week 1 | 1.2 progressive transcript, 1.4 re-run menus, 1.5 triage | M + S + S |
| Week 2 | 1.1 speaker merge (UI and store first, engine hint second) | M–L |
| Week 3 | 1.3 transcript editing, 1.6 follow/find | M–L + S |
| Week 4 | 2.1 settings, 2.2 sidebar, 2.4 export, 2.5 surfaces | S–M each |
| Gaps | 2.3, 2.6, 2.7, 3.x | S each |

Progressive transcript goes first because it is the cheapest change that
transforms the wait on every long meeting, and its event plumbing is what the
partial-failure handling in 1.3 and the ETA in 2.2 both build on.

## Risks

- **Speaker cap merging real people.** Kept soft: a target, not a limit, and
  only merges under a relaxed distance. Test on the real six-person file
  before trusting it.
- **Edits versus revisions.** A re-transcription after hand edits produces a
  new revision without those edits. The UI must say this before starting, and
  the old revision must stay readable.
- **Progressive writes and SwiftData.** Appending per window is a save every
  few seconds; batch to one save per emitted event and never per segment. The
  status-persist lesson in `AppState.handle` applies.
- **Settings redesign touching microphone flow.** The permission row is new
  and tested; move it, do not rewrite it.
