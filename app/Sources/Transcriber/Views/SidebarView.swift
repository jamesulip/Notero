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

    enum Filter: String, CaseIterable, Identifiable {
        case all, favorites, meetings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .meetings: return "Meetings"
            }
        }
    }

    var body: some View {
        @Bindable var state = state

        List(selection: Binding(
            get: { state.route },
            set: { state.route = $0 }
        )) {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowSeparator(.hidden)
            }

            ForEach(RecordingStore.group(filtered), id: \.bucket.id) { section in
                Section(section.bucket.label) {
                    ForEach(section.items) { recording in
                        HistoryRow(recording: recording)
                            .tag(Route.recording(recording.id))
                            .contextMenu { menu(for: recording) }
                    }
                }
            }

            if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No recordings yet", systemImage: "waveform")
                } description: {
                    Text("Press ⌘R to record, or drop an audio file onto the window.")
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var filtered: [StoredRecording] {
        switch filter {
        case .all: return recordings
        case .favorites: return recordings.filter(\.isFavorite)
        case .meetings: return recordings.filter { $0.kind == .meeting }
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
        Button(recording.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: recording.isFavorite ? "star.slash" : "star") {
            recording.isFavorite.toggle()
            try? context.save()
        }
        if recording.hasAudio {
            Button("Transcribe Again", systemImage: "arrow.clockwise") {
                state.retranscribe(recording)
            }
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
        Button("Delete", systemImage: "trash", role: .destructive) {
            state.delete(recording)
        }
    }
}

struct HistoryRow: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recording.kind.symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(recording.title)
                        .lineLimit(1)
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
    }
}
