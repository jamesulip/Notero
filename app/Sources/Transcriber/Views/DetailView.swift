import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

struct DetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.route {
        case .search:
            SearchView()
        case .benchmark:
            BenchmarkView()
        case .recording(let id):
            if let recording = state.recording(id) {
                // `isLive`, not `isRecording`: the model load happens before
                // capture starts, and gating on `isRecording` showed the
                // finished-recording pane -- empty, static -- for all of it.
                if state.isLive(id) {
                    RecordingView(recording: recording)
                } else if recording.kind == .note {
                    NoteEditorView(recording: recording)
                } else {
                    // Keyed by recording so per-recording view state (which
                    // revision is open, whether the inspector is shown) does
                    // not carry over when the selection changes.
                    RecordingDetailView(recording: recording)
                        .id(recording.id)
                }
            } else {
                ContentUnavailableView("Recording not found", systemImage: "questionmark.folder")
            }
        case nil:
            ContentUnavailableView {
                Label("Nothing selected", systemImage: "waveform")
            } description: {
                Text("Pick something from the sidebar, press ⌘R to record, or drop an audio file here.")
            } actions: {
                Button("New Recording") { state.newItem(.recording) }
                Button("New Meeting") { state.newItem(.meeting) }
            }
        }
    }
}

/// A finished recording: transcript in the middle, audio underneath, and the
/// meeting workspace on the right when there is one.
struct RecordingDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    @State private var inspector: InspectorTab = .notes
    @State private var showInspector = true
    /// An earlier transcript revision open for reading. Nil is the latest.
    @State private var revision: Int?

    enum InspectorTab: String, CaseIterable, Identifiable {
        case notes, bookmarks, speakers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notes: return "Notes"
            case .bookmarks: return "Bookmarks"
            case .speakers: return "Speakers"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            RecordingInfoBar(recording: recording, revision: $revision)
            Divider()

            HStack(spacing: 0) {
                // maxHeight as well as maxWidth. Without it the pane sizes to
                // its content, and with the inspector collapsed nothing else
                // is left to hold the row open -- so the whole header sinks to
                // the middle of the window.
                TranscriptView(recording: recording, revision: revision)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    VStack(spacing: 0) {
                        Picker("", selection: $inspector) {
                            ForEach(InspectorTab.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(10)
                        Divider()
                        switch inspector {
                        case .notes: NotesPane(recording: recording)
                        case .bookmarks: BookmarksPane(recording: recording)
                        case .speakers: SpeakersPane(recording: recording)
                        }
                    }
                    // maxHeight, or the column sizes to its content and the
                    // HStack centres it -- leaving the tab bar floating in the
                    // middle of a tall window with its background painted as a
                    // band rather than a column.
                    .frame(width: 330)
                    .frame(maxHeight: .infinity)
                    .background(.background.secondary)
                }
            }

            if recording.hasAudio {
                Divider()
                PlayerBar(recording: recording)
            }
        }
        .onAppear { showInspector = recording.kind == .meeting }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation(.snappy) { showInspector.toggle() }
                } label: {
                    Label("Meeting Notes", systemImage: "sidebar.right")
                }
                .help("Show or hide the meeting workspace")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("Title", text: Binding(
                get: { recording.title },
                set: { recording.title = $0; recording.updatedAt = Date() }
            ))
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .onSubmit {
                RecordingStore.reindex(recording)
                try? context.save()
            }

            Spacer(minLength: 12)

            if let progress = state.progress[recording.id] {
                StatusChip(status: progress.status, fraction: progress.fraction,
                           remaining: progress.remaining)
                Button("Cancel") { state.cancelJob(recording.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            } else if recording.status.isBusy {
                // Live work never reaches the queue, so it has no progress
                // entry. Without this fallback the preparing and recording
                // phases show no chip at all.
                StatusChip(status: recording.status)
            } else if recording.status == .failed {
                StatusChip(status: .failed)
                if recording.hasAudio { RerunButton(recording: recording, label: "Retry") }
            } else if let warning = state.warnings[recording.id] {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(warning)
                if recording.hasAudio { RerunButton(recording: recording) }
            } else if recording.hasAudio {
                RerunButton(recording: recording, label: "Re-run")
                    .help("Transcribe again on another tier, or identify speakers again")
            }

            Button {
                state.isExporting = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export as TXT, SRT, VTT or JSON (⌘E)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// A note with no audio. Just text.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: Binding(
                get: { recording.title },
                set: { recording.title = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TextEditor(text: Binding(
                get: { recording.body },
                set: { recording.body = $0; recording.updatedAt = Date() }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
        }
        .onDisappear {
            RecordingStore.reindex(recording)
            try? context.save()
        }
    }
}
