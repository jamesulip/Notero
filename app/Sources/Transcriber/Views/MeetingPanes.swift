import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

/// The manual meeting workspace: a free-text summary plus five typed lists.
///
/// Typed rows rather than one text blob, because every row keeps the timestamp
/// it came from. That is what makes a decision written down here checkable
/// against what was actually said -- and it is the shape an automatic
/// extraction pass would later write into, without the notes needing to be
/// re-modelled.
struct NotesPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    @State private var drafts: [MeetingItemKind: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Summary") {
                    TextEditor(text: Binding(
                        get: { recording.summary },
                        set: { recording.summary = $0; recording.updatedAt = Date() }
                    ))
                    .font(.callout)
                    .frame(minHeight: 74)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                    .overlay(alignment: .topLeading) {
                        if recording.summary.isEmpty {
                            Text("What was this about?")
                                .foregroundStyle(.tertiary)
                                .font(.callout)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
                }

                ForEach(MeetingItemKind.allCases) { kind in
                    section(kind.plural, symbol: kind.symbol) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(RecordingStore.items(kind, of: recording)) { item in
                                ItemRow(recording: recording, item: item)
                            }
                            addField(kind)
                        }
                    }
                }
            }
            .padding(14)
        }
        .onDisappear { save() }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                if let symbol { Image(systemName: symbol).font(.caption) }
            }
            content()
        }
    }

    private func addField(_ kind: MeetingItemKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField("Add \(kind.label.lowercased())", text: Binding(
                get: { drafts[kind] ?? "" },
                set: { drafts[kind] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.callout)
            .onSubmit { commit(kind) }
        }
        .padding(.vertical, 3)
    }

    private func commit(_ kind: MeetingItemKind) {
        let text = (drafts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Typed by hand while listening, so the playhead is the right source
        // timestamp -- the same link a note lifted from a transcript row gets.
        let at = state.isRecording ? state.live.currentMs : state.player.currentMs
        let item = try? RecordingStore.addItem(kind, text: text, to: recording, in: context)
        item?.sourceMs = at > 0 ? at : nil
        drafts[kind] = ""
        save()
    }

    private func save() {
        RecordingStore.reindex(recording)
        try? context.save()
    }
}

struct ItemRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    let item: StoredMeetingItem

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if item.kind.isCheckable {
                Toggle("", isOn: Binding(
                    get: { item.isDone },
                    set: { item.isDone = $0; try? context.save() }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: Binding(
                    get: { item.text },
                    set: { item.text = $0 }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .onSubmit { try? context.save() }

                if let at = item.sourceMs {
                    Button {
                        state.pendingScrollTarget = item.sourceSegmentId
                        state.seek(to: at, in: recording)
                    } label: {
                        Label(TimeFormat.short(ms: at), systemImage: "arrow.turn.up.left")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Jump to where this came from")
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if item.kind.isCheckable {
                Button(item.isDone ? "Mark Not Done" : "Mark Done") {
                    item.isDone.toggle()
                    try? context.save()
                }
            }
            Menu("Change To") {
                ForEach(MeetingItemKind.allCases.filter { $0 != item.kind }) { kind in
                    Button(kind.label) { item.kind = kind; try? context.save() }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                context.delete(item)
                try? context.save()
            }
        }
    }
}

struct BookmarksPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    var body: some View {
        Group {
            if (recording.bookmarks ?? []).isEmpty {
                ContentUnavailableView {
                    Label("No bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Press ⌘B while recording or playing to mark the moment.")
                }
            } else {
                List {
                    ForEach((recording.bookmarks ?? []).sorted { $0.atMs < $1.atMs }) { bookmark in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TimeFormat.short(ms: bookmark.atMs))
                                .font(.system(.caption, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                                .frame(width: 52, alignment: .trailing)
                            TextField("Label", text: Binding(
                                get: { bookmark.label },
                                set: { bookmark.label = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .onSubmit { try? context.save() }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.seek(to: bookmark.atMs, in: recording) }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                context.delete(bookmark)
                                try? context.save()
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

/// The roster, by talk time, with the two repairs a far-field recording needs:
/// merge a fragment into the person it belongs to, and tell the next run how
/// many people were actually in the room.
struct SpeakersPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    /// Under this much speech, or under 1 % of the total, a speaker is more
    /// likely a fragment of someone else than a person. Flagged, not merged:
    /// a guest who said one thing is also under 30 s.
    private static let fragmentMs = 30_000

    private var speakers: [StoredSpeaker] {
        (recording.speakers ?? []).sorted { $0.speechMs > $1.speechMs }
    }

    private var totalMs: Int { speakers.reduce(0) { $0 + $1.speechMs } }

    private func isFragment(_ speaker: StoredSpeaker) -> Bool {
        speakers.count > 1
            && (speaker.speechMs < Self.fragmentMs
                || Double(speaker.speechMs) < 0.01 * Double(totalMs))
    }

    var body: some View {
        VStack(spacing: 0) {
            headCount
            Divider()
            if speakers.isEmpty {
                ContentUnavailableView {
                    Label("No speakers yet", systemImage: "person.2")
                } description: {
                    Text(state.progress[recording.id]?.status == .diarizing
                         ? "Identifying speakers…"
                         : "Speakers are identified after transcription finishes.")
                }
            } else {
                List {
                    ForEach(speakers) { speaker in
                        SpeakerRow(recording: recording, speaker: speaker,
                                   share: totalMs > 0 ? Double(speaker.speechMs) / Double(totalMs) : 0,
                                   isFragment: isFragment(speaker),
                                   others: speakers.filter { $0.id != speaker.id })
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    Text("Rename here and every line follows. Right-click a speaker to "
                         + "merge it into another; right-click a transcript line to move "
                         + "just that line.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
        }
    }

    /// "People in the room". Stored on the recording and handed to the next
    /// speaker pass as a target. Shown even before speakers exist, because the
    /// best time to say six is before the run that finds fourteen.
    private var headCount: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Stepper(value: Binding(
                    get: { recording.expectedSpeakers ?? 0 },
                    set: { value in
                        recording.expectedSpeakers = value > 0 ? value : nil
                        recording.updatedAt = Date()
                        try? context.save()
                    }
                ), in: 0...30) {
                    HStack(spacing: 6) {
                        Text("People in the room")
                        Text(recording.expectedSpeakers.map(String.init) ?? "Any")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                }
                .font(.callout)
                Spacer()
                if recording.hasAudio, state.progress[recording.id] == nil {
                    Button("Identify Again") { state.rediarize(recording) }
                        .controlSize(.small)
                        .help("Run speaker identification again, aiming at this count")
                }
            }
            if speakers.count > 1, let expected = recording.expectedSpeakers,
               speakers.count > expected {
                Text("\(speakers.count) found for \(expected) people. Merge the fragments "
                     + "below, or Identify Again to let the count guide the pass.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A target for speaker identification, not a limit. Voices the "
                     + "model hears as clearly different stay separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }
}

struct SpeakerRow: View {
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    let speaker: StoredSpeaker
    let share: Double
    let isFragment: Bool
    let others: [StoredSpeaker]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Circle()
                    .fill(SpeakerPalette.color(speaker.colorIndex))
                    .frame(width: 9, height: 9)
                TextField("Name", text: Binding(
                    get: { speaker.displayName },
                    set: { speaker.displayName = $0 }
                ))
                .textFieldStyle(.plain)
                .onSubmit {
                    try? RecordingStore.rename(speaker, to: speaker.displayName, in: context)
                }
                Spacer()
                Text(TimeFormat.coarse(ms: speaker.speechMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Talk time as a bar, so fourteen rows read as "two people and a
            // dozen slivers" at a glance rather than as a column of numbers.
            GeometryReader { geometry in
                Capsule()
                    .fill(SpeakerPalette.color(speaker.colorIndex).opacity(0.75))
                    .frame(width: max(2, geometry.size.width * share))
            }
            .frame(height: 4)
            .padding(.leading, 18)
            if isFragment {
                Label("Likely a fragment of another speaker", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Menu("Merge Into") {
                ForEach(others) { other in
                    Button(other.displayName) {
                        try? RecordingStore.merge(speaker, into: other, in: context)
                    }
                }
            }
            .disabled(others.isEmpty)
        }
    }
}
