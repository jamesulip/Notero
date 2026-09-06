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
        VStack(spacing: 0) {
            // The filter is an Advanced control. Simple mode shows the whole
            // library, newest first, and nothing to select before the list.
            if state.settings.isAdvanced {
                filterBar
            } else {
                simpleTopBar
            }
            list
            footer
        }
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
        .onChange(of: state.settings.isAdvanced) { _, advanced in
            if !advanced { filter = .all }
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
            Text("The app removes the audio and the transcript from this Mac. You cannot undo this.")
        }
    }

    private var list: some View {
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
                    Label(filter == .all ? "No recordings yet" : "No recordings match",
                          systemImage: filter == .active ? "hourglass" : "waveform")
                } description: {
                    Text(filter == .all
                         ? "Click Record, or drop an audio or video file on the window."
                         : (filter == .active ? "No recording or transcription is in progress."
                            : "No recording matches this filter."))
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
    }

    private var filtered: [StoredRecording] {
        switch filter {
        case .all: return recordings
        case .active:
            return recordings.filter { state.jobs.isBusy($0.id) || $0.status.isBusy }
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

    /// A sibling of the list rather than a row in it, and its material reaches
    /// up through the titlebar.
    ///
    /// As a row the picker scrolled away, so the filter you were in stopped
    /// being visible once you scrolled. Worse, the sidebar's titlebar strip has
    /// no material of its own -- the window controls sit straight on the list
    /// background -- so scrolled rows rode up under the traffic lights and the
    /// close button landed on top of a recording's duration.
    ///
    /// Stacking the bar above the list, rather than insetting the list's safe
    /// area with it, is what makes that hold: the list's frame stops where the
    /// bar begins, whatever the split view does to the column afterwards, so
    /// there is no arrangement in which a row can be laid out where the window
    /// controls are. Reaching the background into the titlebar covers the strip
    /// itself, which the list would otherwise be showing through.
    private var filterBar: some View {
        VStack(spacing: 0) {
            // Segmented while the column is wide enough for four labels; a
            // menu once it is not, rather than clipped segments. The width is
            // stated rather than left to the control: a segmented picker takes
            // whatever width it is given and clips the labels inside, so it
            // would never report that it does not fit.
            ViewThatFits(in: .horizontal) {
                filterPicker.pickerStyle(.segmented).frame(width: 220)
                filterPicker.pickerStyle(.menu)
            }
            .labelsHidden()
            .help("Active: the recordings in progress or in the queue")
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            Divider()
        }
        .background {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
        }
    }

    /// The same strip in Simple mode, with a title instead of a filter. It
    /// exists for the same reason: it is what keeps rows out from under the
    /// window controls.
    private var simpleTopBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recordings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !recordings.isEmpty {
                    Text("\(recordings.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
        }
        .background {
            Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
        }
    }

    private var filterPicker: some View {
        Picker("Show", selection: $filter) {
            ForEach(Filter.allCases) { Text($0.label).tag($0) }
        }
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
                .help("Search all recordings (⇧⌘F)")
                .labelStyle(.iconOnly)

                // The one switch between the two modes that is always on
                // screen. Settings and the View menu have the same switch.
                Button {
                    withAnimation(.snappy) { state.settings.isAdvanced.toggle() }
                } label: {
                    Label(state.settings.isAdvanced ? "Advanced" : "Simple",
                          systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .help(state.settings.isAdvanced
                      ? "Advanced mode. Click to change to Simple mode, which has fewer controls."
                      : "Simple mode. Click to change to Advanced mode, which shows all controls.")

                Spacer()
                if state.settings.isAdvanced {
                    Button {
                        state.route = .benchmark
                    } label: {
                        Label("Benchmark", systemImage: "speedometer")
                    }
                    .help("Measure the model tiers on this Mac (⇧⌘K)")
                    .labelStyle(.iconOnly)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
                .labelStyle(.iconOnly)
            }
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
            if state.settings.isAdvanced {
                RerunItems(recording: recording)
            } else {
                Button("Transcribe Again", systemImage: "arrow.clockwise") {
                    state.retranscribe(recording)
                }
            }
            Button("Show the Audio in Finder", systemImage: "folder") {
                if let url = recording.audioURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        if recording.kind == .recording, state.settings.isAdvanced {
            Button("Make This a Meeting", systemImage: RecordingKind.meeting.symbol) {
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
        let display = state.displayStatus(for: recording)
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
                    if let warning = display.warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if display.isPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let chip = display.chip {
                    StatusChip(status: chip.status, fraction: chip.fraction, remaining: chip.remaining)
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
