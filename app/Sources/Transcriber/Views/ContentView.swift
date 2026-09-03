import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var state = state

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 268, max: 360)
        } detail: {
            DetailView()
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        // Drop anywhere in the window. Dropping onto a specific recording would
        // suggest the audio joins that recording, which is not what happens.
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter(Self.isImportable)
            guard !audio.isEmpty else { return false }
            state.importFiles(audio)
            return true
        }
        .fileImporter(
            isPresented: $state.isImporting,
            allowedContentTypes: AppState.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): state.importFiles(urls)
            case .failure(let error):
                state.alert = AppState.AppAlert(title: "Import failed",
                                                message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $state.isExporting) {
            if let recording = state.selectedRecording {
                ExportSheet(recording: recording)
            }
        }
        .alert(
            "Keep this recording?",
            isPresented: Binding(
                get: { state.shortTake != nil },
                set: { if !$0 { state.shortTake = nil } }
            ),
            presenting: state.shortTake
        ) { _ in
            Button("Keep") { state.resolveShortTake(keep: true) }
                .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive) { state.resolveShortTake(keep: false) }
        } message: { take in
            Text(Self.shortTakeMessage(take))
        }
        .toolbar { toolbar }
    }

    static func shortTakeMessage(_ take: AppState.ShortTake) -> String {
        let seconds = max(1, (take.durationMs + 500) / 1000)
        let length = "It ran for \(seconds) second\(seconds == 1 ? "" : "s")"
        switch take.words {
        case nil: return "\(length). Discarding deletes the audio."
        case 0: return "\(length) and no words were heard. Discarding deletes the audio."
        case 1: return "\(length) and one word was heard. Discarding deletes the audio."
        case let words?: return "\(length) and \(words) words were heard. Discarding deletes the audio."
        }
    }

    private var title: String {
        switch state.route {
        case .search: return "Search"
        case .benchmark: return "Model Benchmark"
        case .recording: return state.selectedRecording?.title ?? "Transcriber"
        case nil: return "Transcriber"
        }
    }

    private var subtitle: String {
        guard let recording = state.selectedRecording else { return "" }
        var parts: [String] = []
        if recording.durationMs > 0 {
            parts.append(TimeFormat.duration(ms: recording.durationMs))
        }
        let speakers = (recording.speakers ?? []).count
        if speakers > 1 { parts.append("\(speakers) speakers") }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Recording", systemImage: RecordingKind.recording.symbol) {
                    state.newItem(.recording)
                }
                Button("Meeting", systemImage: RecordingKind.meeting.symbol) {
                    state.newItem(.meeting)
                }
                Button("Note", systemImage: RecordingKind.note.symbol) {
                    state.newItem(.note)
                }
                Divider()
                Button("Import Audio or Video…", systemImage: "square.and.arrow.down") {
                    state.isImporting = true
                }
            } label: {
                Label("New", systemImage: "plus")
            }
            .menuIndicator(.hidden)
        }

        if state.isRecording {
            ToolbarItem(placement: .principal) {
                Button {
                    Task { await state.stopRecording() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
                .help("Stop recording (⌘.)")
            }
        } else if state.isLiveBusy {
            // The model load, which is seconds cold. Without this the toolbar
            // is identical to the idle one for the whole wait.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(state.live.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                state.route = .search
                state.focusSearch = true
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search all recordings (⌘F)")
        }
    }

    static func isImportable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return AppState.importableTypes.contains { type.conforms(to: $0) }
    }
}
