import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

/// The transcript, grouped into speaker turns, every row a seek target.
struct TranscriptView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    @FocusState private var focused: Bool
    /// Grouping is recomputed when the transcript changes, not when the
    /// playhead moves. The player ticks 20 times a second; regrouping tens of
    /// thousands of segments at that rate would make a long meeting unscrollable.
    @State private var blocks: [TranscriptBlock] = []

    var body: some View {
        Group {
            if segments.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .focusable()
        .focused($focused)
        // Space belongs here rather than in the menu bar: as a menu key
        // equivalent it would be consumed before the responder chain and eat
        // every space typed into a note.
        .onKeyPress(.space) {
            guard state.player.loadedURL != nil else { return .ignored }
            state.player.toggle()
            return .handled
        }
        .onAppear { focused = true }
        .task(id: transcriptSignature) { regroup() }
    }

    private func regroup() {
        blocks = TranscriptGrouping.blocks(from: segments.map(value(of:)))
    }

    private var segments: [StoredSegment] {
        recording.transcript?.orderedSegments ?? []
    }

    /// Changes exactly when the rows do: a new revision, or edits within one.
    private var transcriptSignature: String {
        let transcript = recording.transcript
        return "\(transcript?.id.uuidString ?? "-")-\(transcript?.segments?.count ?? 0)"
    }

    private func value(of row: StoredSegment) -> Segment {
        Segment(id: row.id, index: row.index, startMs: row.startMs, endMs: row.endMs,
                text: row.text, textClean: row.textClean, speakerId: row.speakerId,
                confidence: row.confidence)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(blocks) { block in
                        TranscriptBlockRow(
                            recording: recording,
                            block: block,
                            speakerName: name(for: block.speakerId),
                            speakerColor: color(for: block.speakerId)
                        )
                        .id(block.id)
                    }
                }
                .padding(20)
            }
            .onChange(of: state.pendingScrollTarget) { _, target in
                guard let target else { return }
                // Search hits address a segment; the view shows blocks. Land on
                // the block that contains it.
                let anchor = blocks.first { $0.segments.contains { $0.id == target } }?.id ?? target
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(anchor, anchor: .center)
                }
                state.selectedSegmentId = target
                state.pendingScrollTarget = nil
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(label, systemImage: icon)
        } description: {
            Text(detail)
        } actions: {
            if recording.hasAudio, state.progress[recording.id] == nil {
                Button("Transcribe") { state.retranscribe(recording) }
            }
        }
    }

    private var label: String {
        if state.progress[recording.id] != nil { return "Working on it" }
        return recording.status == .failed ? "Transcription failed" : "No transcript yet"
    }

    private var icon: String {
        recording.status == .failed ? "exclamationmark.triangle" : "text.alignleft"
    }

    private var detail: String {
        if let progress = state.progress[recording.id] { return progress.status.label }
        if let error = recording.errorMessage, recording.status == .failed { return error }
        return recording.hasAudio
            ? "The audio is here but has not been transcribed."
            : "This recording has no audio."
    }

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

struct TranscriptBlockRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context

    let recording: StoredRecording
    let block: TranscriptBlock
    let speakerName: String?
    let speakerColor: Color

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

            Text(block.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14)
                                 : (isPlaying ? Color.accentColor.opacity(0.07) : .clear))
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
            Divider()
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(block.text, forType: .string)
            }
        }
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
