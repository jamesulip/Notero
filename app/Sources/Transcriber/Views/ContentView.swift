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
    /// A drag is over the window. The whole window says "drop here" while it
    /// is, because a drop target that gives no sign is a drop target nobody
    /// finds.
    @State private var isDropTargeted = false

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
        .overlay { dropOverlay }
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
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
        }
        .fileImporter(
            isPresented: $state.isImporting,
            allowedContentTypes: AppState.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): state.importFiles(urls)
            case .failure(let error):
                state.alert = AppState.AppAlert(title: "The import failed",
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
            "Already in the library?",
            isPresented: Binding(
                get: { !state.duplicateImports.isEmpty },
                set: { if !$0, let first = state.duplicateImports.first {
                    state.duplicateImports.removeAll { $0.id == first.id }
                } }
            ),
            presenting: state.duplicateImports.first
        ) { duplicate in
            Button("Open the Existing One") { state.resolveDuplicate(duplicate, importAnyway: false) }
                .keyboardShortcut(.defaultAction)
            Button("Import a Copy") { state.resolveDuplicate(duplicate, importAnyway: true) }
            Button("Cancel", role: .cancel) {
                state.duplicateImports.removeAll { $0.id == duplicate.id }
            }
        } message: { duplicate in
            Text("“\(duplicate.url.lastPathComponent)” has the same size as the audio of "
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

    /// The whole window as a drop target while a drag is over it. It takes no
    /// clicks and no drops of its own: the split view under it receives the
    /// drop, and this is only the sign that it will.
    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            ZStack {
                Rectangle().fill(Color.accentColor.opacity(0.10))
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                    .padding(14)
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 44))
                    Text("Drop to transcribe")
                        .font(.title2.weight(.semibold))
                    Text("MP3, WAV, M4A, AIFF, MP4 or MOV")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                .foregroundStyle(Color.accentColor)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    static func shortTakeMessage(_ take: AppState.ShortTake) -> String {
        let seconds = max(1, (take.durationMs + 500) / 1000)
        let length = "The recording ran for \(seconds) second\(seconds == 1 ? "" : "s")."
        let heard: String
        switch take.words {
        case nil: heard = ""
        case 0: heard = " The app heard no words."
        case 1: heard = " The app heard one word."
        case let words?: heard = " The app heard \(words) words."
        }
        return "\(length)\(heard) Discard deletes the audio."
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
        if state.settings.isAdvanced {
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
                    Button("Transcribe a File…", systemImage: "square.and.arrow.down") {
                        state.isImporting = true
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuIndicator(.hidden)
            }
        } else {
            // Simple mode: the two things a person does, as two buttons, with
            // their names on them. An icon alone is a guess.
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.isImporting = true
                } label: {
                    Label("Transcribe a File", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .help("Select an audio or video file to transcribe (⌘O)")
                .disabled(state.isLiveBusy)

                Button {
                    state.newItem(.meeting)
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Record a meeting from the microphone (⌘R)")
                .disabled(state.isLiveBusy)
            }
        }

        if state.isRecording {
            ToolbarItem(placement: .principal) {
                Button {
                    Task { await state.stopRecording() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
                .help("Stop the recording (⌘.)")
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
