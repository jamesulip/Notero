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
        .toolbar { toolbar }
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
