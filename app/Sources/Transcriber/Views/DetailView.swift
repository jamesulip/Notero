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
            if !state.settings.hasSeenWelcome {
                WelcomeCard()
            } else {
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
}

/// The three things a first recording needs, checked before the first ⌘R
/// rather than discovered by it: the microphone permission (a refusal sounds
/// like silence), the model (1.6 GB, which used to start downloading with
/// only the preparing header to explain it), and the language.
struct WelcomeCard: View {
    @Environment(AppState.self) private var state

    private var modelId: String { state.settings.liveModelId }
    private var model: ModelOption? { ModelCatalogue.option(modelId) }

    var body: some View {
        @Bindable var settings = state.settings

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before your first recording")
                    .font(.title2.weight(.semibold))
                Text("Everything runs on this Mac. Nothing leaves it.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    MicrophonePermissionRow()
                    Divider()
                    modelRow
                    Divider()
                    HStack {
                        Text("Language")
                        Spacer()
                        Picker("Language", selection: $settings.language) {
                            ForEach(LanguageCatalogue.all) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                    if let note = LanguageCatalogue.option(settings.language)?.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(settings.language == "auto" ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
            }

            HStack {
                Button("New Recording") {
                    settings.hasSeenWelcome = true
                    state.newItem(.recording)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Import Audio…") {
                    settings.hasSeenWelcome = true
                    state.isImporting = true
                }
                Spacer()
                Button("Done") { settings.hasSeenWelcome = true }
                    .help("Hide this card. Everything on it is also in Settings.")
            }
        }
        .frame(maxWidth: 520)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modelRow: some View {
        // Read against the revision so a finished download re-checks the disk.
        let _ = state.modelsRevision
        let downloaded = state.isModelDownloaded(modelId)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(downloaded ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Speech model")
                Text(downloaded
                     ? "\(model?.label ?? modelId) is on this Mac."
                     : "\(model?.label ?? modelId) (\(model?.sizeLabel ?? "")) downloads once. "
                       + "Starting it now means the first recording does not wait for it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let fraction = state.modelDownloads[modelId] {
                HStack(spacing: 6) {
                    ProgressView(value: fraction).frame(width: 80)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            } else if !downloaded {
                Button("Download") { state.downloadModel(modelId) }
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

            // maxHeight as well as maxWidth. Without it the pane sizes to its
            // content and nothing else is left to hold the column open -- so
            // the whole header sinks to the middle of the window.
            TranscriptView(recording: recording, revision: revision)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if recording.hasAudio {
                Divider()
                PlayerBar(recording: recording)
            }
        }
        // The system inspector rather than a hand-rolled HStack column: it
        // gets the standard divider, drags to resize, and remembers nothing
        // we do not tell it to.
        .inspector(isPresented: $showInspector) {
            VStack(spacing: 0) {
                Picker("", selection: $inspector) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(title(for: tab)).tag(tab)
                    }
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
            .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
        }
        .onAppear { showInspector = state.settings.inspectorShown(for: recording.kind) }
        .onChange(of: showInspector) { _, shown in
            state.settings.setInspectorShown(shown, for: recording.kind)
        }
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

    /// "Notes 7", "Speakers 6": the count is the reason to open the tab.
    private func title(for tab: InspectorTab) -> String {
        let count: Int
        switch tab {
        case .notes: count = recording.items?.count ?? 0
        case .bookmarks: count = recording.bookmarks?.count ?? 0
        case .speakers: count = recording.speakers?.count ?? 0
        }
        return count > 0 ? "\(tab.label) \(count)" : tab.label
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
            } else if let warning = recording.warningMessage ?? state.warnings[recording.id] {
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

            // Click exports; the arrow offers the clipboard. Copy is the more
            // common of the two for a transcript going into an email.
            Menu {
                Button("Copy as Text", systemImage: "doc.on.doc") {
                    state.copyTranscript(recording, format: .txt)
                }
                Button("Copy as Markdown", systemImage: "text.badge.checkmark") {
                    state.copyTranscript(recording, format: .markdown)
                }
                Divider()
                Button("Export…", systemImage: "square.and.arrow.up") {
                    state.isExporting = true
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            } primaryAction: {
                state.isExporting = true
            }
            .help("Export as text, Markdown minutes, SRT, VTT or JSON (⌘E). "
                + "The arrow copies to the clipboard instead.")
            .disabled(recording.transcript == nil)
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
