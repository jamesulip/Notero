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
    /// What the user last chose while there was room, restored on widening.
    @State private var wideVisibility = NavigationSplitViewVisibility.all
    @State private var showWelcome = false

    var body: some View {
        @Bindable var state = state

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 268, max: 300)
        } detail: {
            DetailView()
                // The detail's ideal, stated where the split view reads it.
                // Its rows all have compact forms; what it asks for by default
                // is what decides whether the sidebar fits beside it.
                .navigationSplitViewColumnWidth(min: 260, ideal: 400)
        }
        // Up on every launch until a button answers it. An overlay, not a pane
        // in the detail column and not a sheet: as a pane it took the split
        // view's layout with it (see WelcomeCard), and a sheet cannot be left
        // up -- macOS refuses to quit the app while one is open, so ⌘Q did
        // nothing until the card was answered. An overlay is laid out inside
        // the frame the window already gave the split view, so it can neither
        // resize anything nor block the app.
        .overlay { welcomeDialog }
        .task { showWelcome = !state.settings.hasSeenWelcome }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .background {
            // The window's width, not the split view's: an overflowing split
            // view never reports a smaller size, so the fold below would
            // never happen.
            WindowWidthReader { width in state.contentWidth = width }
        }
        // Narrow: fold the sidebar rather than let the split view overflow.
        // The user can still open it from the toolbar; that choice holds until
        // the width changes again. Wide: put back whatever they had.
        .onChange(of: state.isCompact) { _, compact in
            withAnimation(.snappy) {
                columnVisibility = compact ? .detailOnly : wideVisibility
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            if !state.isCompact { wideVisibility = visibility }
        }
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
        .alert(
            "Already imported?",
            isPresented: Binding(
                get: { !state.duplicateImports.isEmpty },
                set: { if !$0, let first = state.duplicateImports.first {
                    state.duplicateImports.removeAll { $0.id == first.id }
                } }
            ),
            presenting: state.duplicateImports.first
        ) { duplicate in
            Button("Open Existing") { state.resolveDuplicate(duplicate, importAnyway: false) }
                .keyboardShortcut(.defaultAction)
            Button("Import Anyway") { state.resolveDuplicate(duplicate, importAnyway: true) }
            Button("Cancel", role: .cancel) {
                state.duplicateImports.removeAll { $0.id == duplicate.id }
            }
        } message: { duplicate in
            Text("“\(duplicate.url.lastPathComponent)” is the same size as the audio behind "
                 + "“\(duplicate.existingTitle)”. Open that recording, or import a second copy?")
        }
        .toolbar { toolbar }
    }

    /// The first-run card, over a scrim that takes the clicks meant for the
    /// window behind it.
    ///
    /// Held in its own state rather than read straight from `hasSeenWelcome`:
    /// only the card's own buttons record an answer, so closing the window or
    /// quitting with the card up asks again next launch.
    @ViewBuilder
    private var welcomeDialog: some View {
        if showWelcome {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .contentShape(Rectangle())
                    .onTapGesture { }
                WelcomeCard { showWelcome = false }
                    .frame(maxWidth: 480)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                    .padding(20)
            }
        }
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
        case .recording: return state.selectedRecording?.title ?? "Notero"
        case nil: return "Notero"
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
                    if let fraction = state.live.state.fraction {
                        ProgressView(value: fraction)
                            .frame(width: 90)
                        Text("\(Int(fraction * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(state.live.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
