import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredRecording.createdAt, order: .reverse)
    private var recordings: [StoredRecording]

    @State private var filter: Filter = .all
    /// The list's own selection. A set, so several rows can be picked and
    /// deleted together; `state.route` follows it whenever exactly one row is
    /// selected, and it follows `state.route` when something else navigates.
    @State private var selection: Set<Route> = []
    @State private var pendingDelete: [StoredRecording] = []
    /// The row whose title is open for editing in place.
    @State private var renaming: UUID?

    enum Filter: String, CaseIterable, Identifiable {
        case all, active, favorites, meetings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .favorites: return "Favorites"
            case .meetings: return "Meetings"
            }
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(RecordingStore.group(filtered), id: \.bucket.id) { section in
                Section(section.bucket.label) {
                    ForEach(section.items) { recording in
                        HistoryRow(recording: recording, renaming: $renaming)
                            .tag(Route.recording(recording.id))
                            .contextMenu { menu(for: recording) }
                    }
                }
            }

            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(filter == .all ? "No recordings yet" : "Nothing here",
                          systemImage: filter == .active ? "hourglass" : "waveform")
                } description: {
                    Text(filter == .all
                         ? "Press ⌘R to record, or drop an audio file onto the window."
                         : (filter == .active ? "Nothing is recording or being transcribed."
                            : "Nothing matches this filter."))
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .safeAreaInset(edge: .bottom) { footer }
        .onChange(of: selection) { _, picked in
            // One row is a navigation; several are a selection to act on, and
            // the detail keeps showing whatever it was showing.
            if picked.count == 1, let only = picked.first, state.route != only {
                state.route = only
            }
        }
        .onChange(of: state.route, initial: true) { _, route in
            if let route, !selection.contains(route) { selection = [route] }
            if route == nil { selection = [] }
        }
        .onDeleteCommand { pendingDelete = selectedRecordings }
        .confirmationDialog(
            deleteTitle, isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ), titleVisibility: .visible
        ) {
            Button(pendingDelete.count == 1 ? "Delete" : "Delete \(pendingDelete.count) Recordings",
                   role: .destructive) {
                state.delete(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("The audio and transcript are removed from this Mac. This cannot be undone.")
        }
    }

    private var filtered: [StoredRecording] {
        switch filter {
        case .all: return recordings
        case .active:
            return recordings.filter { state.progress[$0.id] != nil || $0.status.isBusy }
        case .favorites: return recordings.filter(\.isFavorite)
        case .meetings: return recordings.filter { $0.kind == .meeting }
        }
    }

    private var selectedRecordings: [StoredRecording] {
        recordings.filter { selection.contains(.recording($0.id)) }
    }

    private var deleteTitle: String {
        switch pendingDelete.count {
        case 0: return ""
        case 1: return "Delete “\(pendingDelete[0].title)”?"
        default: return "Delete \(pendingDelete.count) recordings?"
        }
    }

    /// Pinned above the list rather than being its first row.
    ///
    /// As a row it scrolled away, so the filter you were in stopped being
    /// visible once you scrolled. Worse, the sidebar's titlebar strip has no
    /// material of its own -- the window controls sit straight on the list
    /// background -- so scrolled rows rode up under the traffic lights and the
    /// close button landed on top of a recording's duration. An inset bar takes
    /// that strip out of the scroll area, which fixes both.
    private var filterBar: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Active: recording, queued or being transcribed right now")
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button {
                    state.route = .search
                    state.focusSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Spacer()
                Button {
                    state.route = .benchmark
                } label: {
                    Label("Benchmark", systemImage: "speedometer")
                }
                .help("Measure the model tiers on this Mac (⇧⌘K)")
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func menu(for recording: StoredRecording) -> some View {
        Button("Rename", systemImage: "pencil") { renaming = recording.id }
        Button(recording.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: recording.isFavorite ? "star.slash" : "star") {
            recording.isFavorite.toggle()
            try? context.save()
        }
        if recording.hasAudio {
            RerunItems(recording: recording)
            Button("Show Audio in Finder", systemImage: "folder") {
                if let url = recording.audioURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        if recording.kind == .recording {
            Button("Turn into a Meeting", systemImage: RecordingKind.meeting.symbol) {
                recording.kind = .meeting
                try? context.save()
            }
        }
        Divider()
        // Right-clicking inside a multi-selection acts on all of it; outside
        // it, on the row under the pointer alone.
        let selected = selectedRecordings
        if selected.count > 1, selected.contains(where: { $0.id == recording.id }) {
            Button("Delete \(selected.count) Recordings…", systemImage: "trash", role: .destructive) {
                pendingDelete = selected
            }
        } else {
            Button("Delete…", systemImage: "trash", role: .destructive) {
                pendingDelete = [recording]
            }
        }
    }
}

struct HistoryRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    @Binding var renaming: UUID?

    @State private var draft = ""
    @FocusState private var editing: Bool

    private var isRenaming: Bool { renaming == recording.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recording.kind.symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if isRenaming {
                        TextField("Title", text: $draft)
                            .textFieldStyle(.plain)
                            .focused($editing)
                            .onSubmit { commitRename() }
                            .onExitCommand { renaming = nil }
                            .onAppear {
                                draft = recording.title
                                editing = true
                            }
                            .onChange(of: editing) { _, focused in
                                // Clicking away commits, as Finder does.
                                if !focused, isRenaming { commitRename() }
                            }
                    } else {
                        Text(recording.title)
                            .lineLimit(1)
                    }
                    if recording.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 6) {
                    if recording.durationMs > 0 {
                        Text(TimeFormat.duration(ms: recording.durationMs))
                    }
                    if let count = recording.speakers?.count, count > 1 {
                        Text("· \(count) speakers")
                    }
                    if (recording.items?.isEmpty == false) {
                        Image(systemName: "note.text")
                    }
                    if let warning = recording.warningMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let progress = state.progress[recording.id] {
                    StatusChip(status: progress.status, fraction: progress.fraction,
                               remaining: progress.remaining)
                } else if recording.status.isBusy {
                    // Preparing and recording are live-path states; they never
                    // get a queue entry, so they need the stored status.
                    StatusChip(status: recording.status, fraction: 0)
                } else if recording.status == .failed {
                    StatusChip(status: .failed, fraction: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .onTapGesture(count: 2) {
            if !isRenaming { renaming = recording.id }
        }
    }

    private func commitRename() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != recording.title {
            recording.title = trimmed
            recording.updatedAt = Date()
            RecordingStore.reindex(recording)
            try? context.save()
        }
        renaming = nil
    }
}
