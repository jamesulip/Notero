import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

/// The transcript, grouped into speaker turns, every row a seek target.
///
/// Also where the transcript gets fixed: a turn opens for editing on
/// double-click, ⌘F finds within it, and playback keeps the current turn in
/// view until the reader scrolls away.
struct TranscriptView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    let recording: StoredRecording
    /// An earlier revision to read instead of the latest. Read-only: the
    /// notes and the roster belong to the latest, and editing text nothing
    /// exports would be a trap.
    var revision: Int? = nil

    @FocusState private var focused: Bool
    /// Grouping is recomputed when the transcript changes, not when the
    /// playhead moves. The player ticks 20 times a second; regrouping tens of
    /// thousands of segments at that rate would make a long meeting unscrollable.
    @State private var blocks: [TranscriptBlock] = []
    /// Bumped when an edit session ends, so the signature changes and the
    /// blocks pick up the new text.
    @State private var editVersion = 0
    @State private var editingBlockId: UUID?
    @State private var find = FindState()
    @State private var scrollRequest: ScrollRequest?

    struct ScrollRequest: Equatable {
        var id: UUID
        var anchor: UnitPoint
        /// Two requests for the same block must still both scroll.
        var serial: Int
    }

    struct FindState {
        var isShowing = false
        var text = ""
        /// Blocks with a match, in transcript order.
        var hits: [UUID] = []
        var highlights: [UUID: [Range<String.Index>]] = [:]
        var current = 0
        var focusSerial = 0
        var currentHit: UUID? { hits.indices.contains(current) ? hits[current] : nil }
    }

    var body: some View {
        Group {
            if segments.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .focusable()
        // Focus is for the space bar, not for a ring: the whole pane drew a
        // blue border whenever it had focus, which is most of the time.
        .focusEffectDisabled()
        .focused($focused)
        // Space belongs here rather than in the menu bar: as a menu key
        // equivalent it would be consumed before the responder chain and eat
        // every space typed into a note.
        .onKeyPress(.space) {
            guard state.player.loadedURL != nil else { return .ignored }
            state.player.toggle()
            return .handled
        }
        .onAppear {
            focused = true
            // SwiftData registers each change with whatever undo manager the
            // context holds; the window's is the one ⌘Z reaches.
            if context.undoManager == nil { context.undoManager = undoManager }
        }
        .task(id: transcriptSignature) { regroup() }
        .onChange(of: state.findRequested) { _, wanted in
            guard wanted else { return }
            find.isShowing = true
            find.focusSerial += 1
            state.findRequested = false
        }
        .task(id: "\(find.text)|\(transcriptSignature)") { runFind() }
    }

    // MARK: - Data

    /// The transcript on show: an older revision when asked, else the latest.
    private var transcript: StoredTranscript? {
        if let revision,
           let older = (recording.transcripts ?? []).first(where: { $0.revision == revision }) {
            return older
        }
        return recording.transcript
    }

    private var isViewingOlderRevision: Bool {
        guard let revision, let latest = recording.transcript else { return false }
        return revision != latest.revision
    }

    /// No edits while rows are still arriving or an older revision is open.
    private var isReadOnly: Bool {
        isViewingOlderRevision || state.progress[recording.id] != nil
    }

    private var segments: [StoredSegment] {
        transcript?.orderedSegments ?? []
    }

    /// Changes exactly when the rows do: a new revision, edits, or an append.
    private var transcriptSignature: String {
        let transcript = transcript
        return "\(transcript?.id.uuidString ?? "-")-\(transcript?.segments?.count ?? 0)-\(editVersion)"
    }

    private func regroup() {
        blocks = TranscriptGrouping.blocks(from: segments.map(value(of:)))
    }

    private func value(of row: StoredSegment) -> Segment {
        Segment(id: row.id, index: row.index, startMs: row.startMs, endMs: row.endMs,
                text: row.text, textClean: row.textClean, speakerId: row.speakerId,
                confidence: row.confidence)
    }

    // MARK: - Layout

    private var list: some View {
        VStack(spacing: 0) {
            if let progress = state.progress[recording.id] {
                // Rows are arriving under this. Without it a growing list with
                // no status reads as a finished transcript that is oddly short.
                TranscriptProgressBanner(progress: progress, durationMs: recording.durationMs)
                Divider()
            }
            if isViewingOlderRevision, let shown = transcript, let latest = recording.transcript {
                RevisionBanner(shown: shown, latest: latest)
                Divider()
            }
            if find.isShowing {
                TranscriptFindBar(find: $find, onStep: step(_:)) {
                    find.isShowing = false
                    find.text = ""
                    focused = true
                }
                Divider()
            }
            scroller
        }
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(blocks) { block in
                        if editingBlockId == block.id {
                            TranscriptBlockEditor(
                                recording: recording, block: block,
                                speakerName: name(for: block.speakerId),
                                speakerColor: color(for: block.speakerId),
                                onDone: endEditing
                            )
                            .id(block.id)
                        } else {
                            TranscriptBlockRow(
                                recording: recording,
                                block: block,
                                speakerName: name(for: block.speakerId),
                                speakerColor: color(for: block.speakerId),
                                highlights: find.highlights[block.id] ?? [],
                                isCurrentHit: find.currentHit == block.id,
                                onEdit: isReadOnly ? nil : { beginEditing(block) }
                            )
                            .id(block.id)
                        }
                    }
                }
                .padding(20)
                // A transcript is prose, and prose set the full width of a
                // 2560pt window is a wall. The column caps at a readable
                // measure and centres; narrow windows are unaffected.
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background {
                    // Lives inside the scroll view so it re-renders per player
                    // tick on its own, not the whole list with it.
                    PlaybackFollower(blocks: blocks) { blockId in
                        guard state.followPlayback, state.player.isPlaying else { return }
                        request(blockId, anchor: .center)
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                // The reader took the wheel; stop dragging the view back to
                // the playhead until they ask.
                if phase == .interacting || phase == .tracking {
                    state.followPlayback = false
                }
            }
            .overlay(alignment: .bottom) {
                if !state.followPlayback, state.player.isPlaying {
                    Button {
                        state.followPlayback = true
                        if let index = TranscriptGrouping.blockIndex(at: state.player.currentMs, in: blocks) {
                            request(blocks[index].id, anchor: .center)
                        }
                    } label: {
                        Label("Follow playback", systemImage: "arrow.down.to.line")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(Capsule().fill(.regularMaterial).shadow(radius: 4, y: 1))
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: state.followPlayback)
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(request.id, anchor: request.anchor)
                }
            }
            .onChange(of: state.pendingScrollTarget) { _, target in
                guard let target else { return }
                // Search hits address a segment; the view shows blocks. Land on
                // the block that contains it.
                let anchor = blocks.first { $0.segments.contains { $0.id == target } }?.id ?? target
                request(anchor, anchor: .center)
                state.selectedSegmentId = target
                state.pendingScrollTarget = nil
            }
        }
    }

    private func request(_ id: UUID, anchor: UnitPoint) {
        scrollRequest = ScrollRequest(id: id, anchor: anchor,
                                      serial: (scrollRequest?.serial ?? 0) + 1)
    }

    // MARK: - Editing

    private func beginEditing(_ block: TranscriptBlock) {
        if editingBlockId != nil { endEditing() }
        // One undo step per turn edited, not one per keystroke.
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Edit Transcript")
        editingBlockId = block.id
    }

    private func endEditing() {
        guard editingBlockId != nil else { return }
        editingBlockId = nil
        if let undoManager, undoManager.groupingLevel > 0 { undoManager.endUndoGrouping() }
        // Commit deletions before the reindex walks the relationship.
        try? context.save()
        RecordingStore.reindex(recording)
        try? context.save()
        editVersion += 1
        focused = true
    }

    // MARK: - Find

    private func runFind() {
        let terms = TextSearch.terms(find.text)
        guard !terms.isEmpty else {
            find.hits = []
            find.highlights = [:]
            find.current = 0
            return
        }
        var hits: [UUID] = []
        var highlights: [UUID: [Range<String.Index>]] = [:]
        for block in blocks {
            if let ranges = TextSearch.matchAll(terms, in: block.text) {
                hits.append(block.id)
                highlights[block.id] = ranges
            }
        }
        let previous = find.currentHit
        find.hits = hits
        find.highlights = highlights
        find.current = previous.flatMap { hits.firstIndex(of: $0) } ?? 0
        if let first = find.currentHit { request(first, anchor: .center) }
    }

    /// Enter and ⇧Enter in the find bar, and its arrow buttons.
    private func step(_ delta: Int) {
        guard !find.hits.isEmpty else { return }
        find.current = (find.current + delta + find.hits.count) % find.hits.count
        if let hit = find.currentHit { request(hit, anchor: .center) }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label(label, systemImage: icon)
        } description: {
            Text(detail)
        } actions: {
            if recording.hasAudio, state.progress[recording.id] == nil {
                Button("Transcribe") { state.retranscribe(recording) }
            } else if !recording.hasAudio, state.progress[recording.id] == nil {
                // Without this the row is a dead end: no audio means nothing to
                // transcribe, and the only way out was to find it in the
                // sidebar and work out that it should be deleted.
                Button("Delete Recording", role: .destructive) { state.delete(recording) }
                Button("Import Audio…") { state.isImporting = true }
            }
        }
    }

    private var label: String {
        if state.progress[recording.id] != nil { return "Working on it" }
        guard recording.status == .failed else { return "No transcript yet" }
        // "Transcription failed" is wrong for a recording that never captured
        // anything -- nothing got as far as being transcribed.
        return recording.hasAudio ? "Transcription failed" : "Recording interrupted"
    }

    private var icon: String {
        recording.status == .failed ? "exclamationmark.triangle" : "text.alignleft"
    }

    private var detail: String {
        if let progress = state.progress[recording.id] {
            guard let remaining = progress.remaining else { return progress.status.label }
            return "\(progress.status.label) · \(TimeFormat.remaining(seconds: remaining)) left"
        }
        if let error = recording.errorMessage, recording.status == .failed { return error }
        return recording.hasAudio
            ? "The audio is here but has not been transcribed."
            : "No audio was captured, so there is nothing to transcribe. "
              + "Importing a file makes a new recording; this one can be deleted."
    }

    // MARK: - Speakers

    private func name(for speakerId: String?) -> String? {
        guard let speakerId else { return nil }
        return (recording.speakers ?? []).first { $0.speakerId == speakerId }?.displayName
            ?? SpeakerLabel.defaultName(for: speakerId)
    }

    private func color(for speakerId: String?) -> Color {
        guard let speakerId,
              let speaker = (recording.speakers ?? []).first(where: { $0.speakerId == speakerId })
        else { return .secondary }
        return SpeakerPalette.color(speaker.colorIndex)
    }
}

/// Watches the playhead and names the block under it. Its body is the only
/// thing that re-evaluates per tick.
private struct PlaybackFollower: View {
    @Environment(AppState.self) private var state
    let blocks: [TranscriptBlock]
    let onChange: (UUID) -> Void

    var body: some View {
        let current = TranscriptGrouping.blockIndex(at: state.player.currentMs, in: blocks)
            .map { blocks[$0].id }
        Color.clear
            .onChange(of: current) { _, next in
                if let next { onChange(next) }
            }
    }
}

/// "Transcribing · 42% · about 14 min left", over a transcript still arriving.
struct TranscriptProgressBanner: View {
    let progress: AppState.JobProgress
    let durationMs: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(summary)
                .font(.callout)
                .contentTransition(.numericText())
            Spacer()
            if progress.status == .transcribing, progress.coveredMs > 0, durationMs > 0 {
                Text("\(TimeFormat.short(ms: progress.coveredMs)) of \(TimeFormat.short(ms: durationMs))")
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("How far into the audio the decode has reached")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    private var summary: String {
        var parts = [progress.status.label]
        // Same rule as the chip: diarization reports progress too coarsely
        // for a percentage to mean anything.
        if progress.status.isBusy, progress.fraction > 0.01, progress.status != .diarizing {
            parts.append("\(Int(progress.fraction * 100))%")
        }
        if let remaining = progress.remaining {
            parts.append("\(TimeFormat.remaining(seconds: remaining)) left")
        }
        return parts.joined(separator: " · ")
    }
}

/// "Viewing revision 1 of 3 · read-only". The way back is in the info bar.
private struct RevisionBanner: View {
    let shown: StoredTranscript
    let latest: StoredTranscript

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Viewing revision \(shown.revision) of \(latest.revision) · "
                 + "\(ModelCatalogue.option(shown.modelId)?.label ?? shown.modelId) · "
                 + "\(shown.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Read-only")
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.background.secondary)
    }
}

/// Find within this transcript. Enter steps forward, ⇧Enter back, Esc closes.
struct TranscriptFindBar: View {
    @Binding var find: TranscriptView.FindState
    let onStep: (Int) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in transcript", text: $find.text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onStep(1) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    onStep(-1)
                    return .handled
                }
            Text(count)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(find.hits.isEmpty)
                .help("Previous match (⇧↩)")
            Button { onStep(1) } label: { Image(systemName: "chevron.down") }
                .disabled(find.hits.isEmpty)
                .help("Next match (↩)")
            Button("Done") { onClose() }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.background.secondary)
        .onAppear { focused = true }
        .onChange(of: find.focusSerial) { _, _ in focused = true }
        .onExitCommand { onClose() }
    }

    private var count: String {
        if find.text.isEmpty { return "" }
        if find.hits.isEmpty { return "No matches" }
        return "\(find.current + 1) of \(find.hits.count)"
    }
}

struct TranscriptBlockRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    let recording: StoredRecording
    let block: TranscriptBlock
    let speakerName: String?
    let speakerColor: Color
    var highlights: [Range<String.Index>] = []
    var isCurrentHit = false
    /// Nil when the transcript cannot be edited right now.
    var onEdit: (() -> Void)?

    /// Read here rather than passed in from the list. Observation then
    /// invalidates only the rows, and `LazyVStack` only builds the visible
    /// ones -- so a two-hour transcript costs the same per tick as a short one.
    private var isPlaying: Bool {
        block.contains(ms: state.player.currentMs)
    }

    private var isSelected: Bool {
        block.segments.contains { $0.id == state.selectedSegmentId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button {
                    state.seek(to: block.startMs, in: recording)
                } label: {
                    Text(TimeFormat.short(ms: block.startMs))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPlaying ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                if let speakerName {
                    Text(speakerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speakerColor)
                }
            }

            Group {
                if highlights.isEmpty {
                    Text(block.text)
                } else {
                    HighlightedText(text: block.text, highlights: highlights)
                }
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(fill)
        }
        .overlay {
            if isCurrentHit {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.yellow.opacity(0.8), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .leading) {
            if isPlaying {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit?()
        }
        .onTapGesture {
            state.selectedSegmentId = block.segments.first?.id
            state.seek(to: block.startMs, in: recording)
        }
        .contextMenu {
            Button("Play from Here", systemImage: "play") {
                state.seek(to: block.startMs, in: recording, play: true)
            }
            Button("Bookmark This Moment", systemImage: "bookmark") {
                state.selectedSegmentId = block.segments.first?.id
                _ = try? RecordingStore.addBookmark(
                    at: block.startMs,
                    label: String(block.text.prefix(60)),
                    to: recording, in: context
                )
            }
            Divider()
            ForEach(MeetingItemKind.allCases) { kind in
                Button("Add as \(kind.label)", systemImage: kind.symbol) {
                    add(kind)
                }
            }
            if let onEdit {
                Divider()
                Button("Edit Text…", systemImage: "pencil") { onEdit() }
                speakerMenu
            }
            Divider()
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(block.text, forType: .string)
            }
        }
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isCurrentHit { return Color.yellow.opacity(0.10) }
        if isPlaying { return Color.accentColor.opacity(0.07) }
        return .clear
    }

    /// Move this turn to another speaker, when the diarizer credited it wrong.
    /// One turn at a time; merging whole speakers lives in the Speakers pane.
    private var speakerMenu: some View {
        Menu("Speaker", systemImage: "person") {
            ForEach((recording.speakers ?? []).sorted { $0.speechMs > $1.speechMs }) { speaker in
                Button {
                    assign(to: speaker)
                } label: {
                    if speaker.speakerId == block.speakerId {
                        Label(speaker.displayName, systemImage: "checkmark")
                    } else {
                        Text(speaker.displayName)
                    }
                }
            }
            Divider()
            Button("New Speaker") {
                if let speaker = try? RecordingStore.addSpeaker(to: recording, in: context) {
                    assign(to: speaker)
                }
            }
            if block.speakerId != nil {
                Button("No Speaker") { assign(to: nil) }
            }
        }
    }

    private func assign(to speaker: StoredSpeaker?) {
        let ids = Set(block.segments.map(\.id))
        let rows = (recording.transcript?.orderedSegments ?? []).filter { ids.contains($0.id) }
        try? RecordingStore.assign(rows, to: speaker, on: recording, in: context)
    }

    private func add(_ kind: MeetingItemKind) {
        guard let first = block.segments.first,
              let row = (recording.transcript?.orderedSegments ?? [])
                  .first(where: { $0.id == first.id })
        else { return }
        try? RecordingStore.addItem(kind, text: block.text, source: row,
                                    to: recording, in: context)
        RecordingStore.reindex(recording)
        try? context.save()
        if recording.kind == .recording { recording.kind = .meeting }
    }
}

/// A turn open for editing: one line per segment, so a fix keeps the
/// timestamps and the seek targets that hang off them.
///
/// Edits go to `textClean`, never `text`: the raw model output stays as
/// evidence of what was heard, and `displayText` -- which the rows, the
/// search and every export read -- prefers the cleaned line when there is one.
struct TranscriptBlockEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    let block: TranscriptBlock
    let speakerName: String?
    let speakerColor: Color
    let onDone: () -> Void

    @FocusState private var focusedRow: UUID?

    private var rows: [StoredSegment] {
        let ids = Set(block.segments.map(\.id))
        return (recording.transcript?.orderedSegments ?? []).filter { ids.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(TimeFormat.short(ms: block.startMs))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                if let speakerName {
                    Text(speakerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(speakerColor)
                }
                Spacer()
                Text("Editing · ↩ or Esc when done")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Done") { onDone() }
                    .controlSize(.small)
            }

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        state.seek(to: row.startMs, in: recording)
                    } label: {
                        Text(TimeFormat.short(ms: row.startMs))
                            .font(.system(.caption2, design: .monospaced))
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)

                    TextField("", text: Binding(
                        get: { row.displayText },
                        set: { edited in
                            // Back to the raw line when the edit restores it,
                            // so a corrected-then-uncorrected row stays clean.
                            row.textClean = edited == row.text ? nil : edited
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focusedRow, equals: row.id)
                    .onSubmit { onDone() }
                    .contextMenu { lineMenu(row) }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
        }
        .onAppear { focusedRow = rows.first?.id }
        .onExitCommand { onDone() }
    }

    /// Per-line repairs: move just this line to another speaker (which is
    /// what splitting a turn is), or drop a line the model invented.
    @ViewBuilder
    private func lineMenu(_ row: StoredSegment) -> some View {
        Menu("Move This Line To", systemImage: "person") {
            ForEach((recording.speakers ?? []).sorted { $0.speechMs > $1.speechMs }) { speaker in
                Button(speaker.displayName) {
                    try? RecordingStore.assign([row], to: speaker, on: recording, in: context)
                    onDone()
                }
                .disabled(speaker.speakerId == row.speakerId)
            }
            Divider()
            Button("New Speaker") {
                if let speaker = try? RecordingStore.addSpeaker(to: recording, in: context) {
                    try? RecordingStore.assign([row], to: speaker, on: recording, in: context)
                }
                onDone()
            }
        }
        if row.textClean != nil {
            Button("Restore Original Text", systemImage: "arrow.uturn.backward") {
                row.textClean = nil
            }
        }
        Divider()
        Button("Delete Line", systemImage: "trash", role: .destructive) {
            context.delete(row)
            onDone()
        }
    }
}
