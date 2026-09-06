import SwiftUI
import TranscriberCore
import TranscriberStore

/// The model's draft, before any of it becomes a note.
///
/// Every item is a checkbox, on by default, with the timestamp it came from
/// so it can be checked against the audio before it is kept. The summary is
/// a checkbox too, and it is off when the user already wrote one: a summary
/// written by hand is never replaced without a click that says so.
struct NotesDraftSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let recording: StoredRecording
    let draft: NotesDraft

    @State private var selected: Set<UUID>
    @State private var useSummary: Bool

    init(recording: StoredRecording, draft: NotesDraft) {
        self.recording = recording
        self.draft = draft
        _selected = State(initialValue: Set(draft.items.map(\.id)))
        _useSummary = State(initialValue: recording.summary.isEmpty && !draft.summary.isEmpty)
    }

    private var hadSummary: Bool { !recording.summary.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !draft.warnings.isEmpty { warnings }
                    if !draft.summary.isEmpty { summarySection }
                    ForEach(MeetingItemKind.allCases) { kind in
                        let items = draft.items(kind)
                        if !items.isEmpty { section(kind, items: items) }
                    }
                    if draft.isEmpty {
                        Text("The model found nothing worth keeping in this transcript.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 660)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Draft of the notes")
                .font(.title2.weight(.semibold))
            Text("Written by \(AppState.notesModelLabel(draft.modelId)) from \(draft.chunkCount) "
                 + "part\(draft.chunkCount == 1 ? "" : "s") of the transcript in "
                 + "\(TimeFormat.short(ms: draft.elapsedMs)). Select what to keep. Each note "
                 + "shows the moment it came from.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(draft.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $useSummary) {
                Text(hadSummary ? "REPLACE THE SUMMARY" : "SUMMARY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            Text(draft.summary)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(useSummary ? .primary : .secondary)
            if hadSummary {
                Text("You wrote a summary. It stays unless you select this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ kind: MeetingItemKind, items: [NotesDraft.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(kind.plural.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: kind.symbol).font(.caption)
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { selected.contains(item.id) },
                        set: { on in if on { selected.insert(item.id) } else { selected.remove(item.id) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(selected.contains(item.id) ? .primary : .secondary)
                        if let at = item.sourceMs {
                            Button {
                                state.pendingScrollTarget = item.sourceSegmentId
                                state.seek(to: at, in: recording)
                            } label: {
                                Label(state.timestamp(ms: at, in: recording), systemImage: "arrow.turn.up.left")
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .help("Play the line this came from")
                        } else {
                            Text("No line named")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .help("The model did not say which line this came from.")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var keptCount: Int { selected.count }

    private var footer: some View {
        HStack {
            Button("Select All") { selected = Set(draft.items.map(\.id)) }
                .disabled(selected.count == draft.items.count)
            Button("Select None") { selected.removeAll() }
                .disabled(selected.isEmpty)
            Spacer()
            Button("Cancel") {
                state.notes.dismiss(recording.id)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(addLabel) {
                let items = draft.items.filter { selected.contains($0.id) }
                state.acceptNotes(items, summary: useSummary ? draft.summary : nil, for: recording)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(keptCount == 0 && !useSummary)
        }
        .padding(16)
    }

    private var addLabel: String {
        switch (keptCount, useSummary) {
        case (0, true): return "Use the Summary"
        case (1, _): return "Add 1 Note"
        default: return "Add \(keptCount) Notes"
        }
    }
}
