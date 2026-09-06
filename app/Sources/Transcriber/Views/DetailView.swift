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
                ContentUnavailableView("The recording is not in the library",
                                       systemImage: "questionmark.folder")
            }
        case nil:
            HomeView()
        }
    }
}

/// The detail column with nothing selected: a drop zone, and the two things
/// a person can do first.
///
/// One target, two buttons. The whole window accepts a drop (see
/// `ContentView`), but a target that looks like one is what tells a new user
/// that a drop is possible at all.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop an audio or video file here")
                    .font(.title2.weight(.semibold))
                Text("The app transcribes the file on this Mac. No audio leaves it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    state.isImporting = true
                } label: {
                    Label("Choose a File…", systemImage: "folder")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    state.newItem(state.newRecordingKind)
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .frame(minWidth: 130)
                }
                .controlSize(.large)
            }

            if mode == .advanced {
                HStack(spacing: 16) {
                    Button("New Meeting") { state.newItem(.meeting) }
                    Button("New Note") { state.newItem(.note) }
                }
                .buttonStyle(.link)
                .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Drop a file, or click Record.")
                    step(2, "Wait. The transcript appears line by line.")
                    step(3, "Read it, correct it, and export it.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Text("MP3, WAV, M4A, AIFF, MP4 or MOV")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 36)
        .frame(maxWidth: 520)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [9, 7]))
                .foregroundStyle(.quaternary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.quaternary))
            Text(text)
        }
    }
}

/// The three things a first recording needs, checked before the first ⌘R
/// rather than discovered by it: the microphone permission (a refusal sounds
/// like silence), the model (1.6 GB, which used to start downloading with
/// only the preparing header to explain it), and the language.
///
/// Shown as a dialog over the window (see `ContentView.welcomeDialog`), not as
/// a pane in the detail column. In the column it took the whole split view
/// down with it: the split view stopped being laid out at the window's height
/// and was laid out at the sidebar list's full content height instead, so the
/// sidebar came up empty with its rows above the window, over the traffic
/// lights, and no resize of the window would bring them back. Whatever in this
/// card the split view was reading, it cannot read it from an overlay.
///
/// A dialog is also the right shape for what this is: asked once, and up until
/// it is answered.
///
/// In Simple mode the card asks for no microphone permission. The first
/// recording asks for it, at the moment it is needed; a person who only drops
/// files is never asked.
struct WelcomeCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode

    /// Called when a button has answered the card. Recording that it was seen
    /// is the card's; taking it off the screen is the caller's.
    var onAnswer: () -> Void = {}

    private var modelId: String { state.settings.offlineModelId }
    private var model: ModelOption? { ModelCatalogue.option(modelId) }

    var body: some View {
        @Bindable var settings = state.settings

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Notero")
                    .font(.title2.weight(.semibold))
                Text("Drop an audio or video file on the window, or record a meeting. "
                     + "Everything runs on this Mac. Nothing leaves it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .advanced {
                        MicrophonePermissionRow()
                        Divider()
                    }
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
                Button("Choose a File…") {
                    answered()
                    state.isImporting = true
                }
                Spacer()
                // Closing is always allowed, download running or not: the
                // download continues without the card, and everything on it
                // is in Settings too.
                Button("Done") { answered() }
                    .help("Close this card. Everything on it is also in Settings.")
                Button("Record") {
                    answered()
                    state.newItem(state.newRecordingKind)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        // Wide enough to read, and no wider; the caller caps it. Stated as a
        // maximum rather than a width so a narrow window shrinks the card
        // instead of cropping it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Closes the card for good. Only a button calls this, so a card closed
    /// any other way -- by quitting with it up -- is asked again next launch.
    private func answered() {
        state.settings.hasSeenWelcome = true
        onAnswer()
    }

    private var modelRow: some View {
        // Read against the revision so a finished download re-checks the disk.
        let _ = state.modelsRevision
        let downloaded = state.isModelDownloaded(modelId)
        let fraction = state.modelDownloads[modelId]
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(downloaded ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Speech model")
                Text(modelDetail(downloaded: downloaded, downloading: fraction != nil))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let fraction {
                HStack(spacing: 6) {
                    ProgressView(value: fraction).frame(width: 80)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            } else if !downloaded {
                // Prominent because nothing transcribes without it, and this
                // is the one place the app asks for it before a recording
                // needs it.
                Button("Download") { state.downloadModel(modelId) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func modelDetail(downloaded: Bool, downloading: Bool) -> String {
        let name = model?.label ?? modelId
        if downloaded { return "\(name) is on this Mac." }
        let size = model?.sizeLabel ?? ""
        if downloading {
            return "The app downloads \(name) in the background. You can close this card."
        }
        return "\(name) (\(size)) is not on this Mac. The app cannot transcribe without it. "
             + "Download it now, and the first transcription does not wait for it. "
             + "You can also download it later in Settings."
    }
}

/// A finished recording: transcript in the middle, audio underneath, and the
/// meeting workspace on the right when there is one.
struct RecordingDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    @State private var inspector: InspectorTab = .notes
    /// Nil until the user has clicked the toggle in this view: until then the
    /// remembered choice for the recording kind applies. Read on demand, not
    /// copied in `onAppear`: an `onAppear` write flipped the inspector after
    /// the first layout, and the flip rebuilt the transcript view, which read
    /// the whole transcript a second time.
    @State private var showInspector: Bool?
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
        // The column's floor. Without one, its minimum is whatever its widest
        // row happens to need, and once the sidebar and inspector had taken
        // their share of a 1000 pt window that was more than what was left:
        // the split view overflowed and the window was cropped at both edges.
        // Every row above can lay itself out in this much.
        // The ideal matters as much as the minimum: the split view sizes
        // this column to what it asks for and lets the window overflow, so
        // the column must ask for less than a 700 pt window minus the sidebar.
        .frame(minWidth: 260, idealWidth: 400, maxWidth: .infinity)
        // The system inspector rather than a hand-rolled HStack column: it
        // gets the standard divider, drags to resize, and remembers nothing
        // we do not tell it to.
        // Shown only when wanted *and* there is room. In a window narrower
        // than `AppState.inspectorNeedsWidth` the split view cannot fit the
        // sidebar, a readable transcript and the inspector, and rather than
        // shrink a column it overflows the window -- the sidebar's rows lose
        // their left edge and the inspector its right. Folding the inspector
        // keeps the transcript whole; widening the window brings it back.
        .inspector(isPresented: Binding(
            get: { inspectorWanted && state.hasRoomForInspector },
            set: { showInspector = $0 }
        )) {
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
            .inspectorColumnWidth(min: 260, ideal: 320, max: 520)
        }
        .onChange(of: showInspector) { _, shown in
            if let shown { state.settings.setInspectorShown(shown, for: recording.kind) }
        }
        // The review of a draft, on the recording and not on the notes pane.
        // An automatic draft finishes whether or not that pane is open, and a
        // draft nobody is shown is two minutes of the GPU for nothing.
        // Closing the sheet any way other than a button is a dismiss.
        .sheet(isPresented: Binding(
            get: { state.notes.draft(for: recording.id) != nil },
            set: { if !$0 { state.notes.dismiss(recording.id) } }
        )) {
            if let draft = state.notes.draft(for: recording.id) {
                NotesDraftSheet(recording: recording, draft: draft)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation(.snappy) { showInspector = !inspectorWanted }
                } label: {
                    Label("Notes", systemImage: "sidebar.right")
                }
                .disabled(!state.hasRoomForInspector)
                .help(state.hasRoomForInspector
                      ? "Show or hide the notes"
                      : "Make the window wider to show the notes beside the transcript")
            }
        }
    }

    private var inspectorWanted: Bool {
        showInspector ?? state.settings.inspectorShown(for: recording.kind)
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

            // Words on the buttons while there is room, icons when the column
            // is narrow. Measured as a cluster so the title keeps the rest.
            ViewThatFits(in: .horizontal) {
                headerControls.fixedSize()
                headerControls.labelStyle(.iconOnly).fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var headerControls: some View {
        let display = state.displayStatus(for: recording)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let chip = display.chip {
                StatusChip(status: chip.status, fraction: chip.fraction, remaining: chip.remaining)
            }
            if let warning = display.warning, !display.isBusy {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(warning)
            }
            switch display.action {
            case .cancel:
                Button("Cancel") { state.cancelJob(recording.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            case .retry: rerun("Retry")
            case .transcribe: rerun("Transcribe")
            case .transcribeAgain: rerun("Transcribe Again")
            case nil: EmptyView()
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
            .help("Export as text, Markdown, SRT, VTT or JSON (⌘E). "
                + "The arrow copies the transcript to the clipboard.")
            .disabled(recording.transcript == nil)
        }
    }

    /// Advanced mode offers the tiers and the speaker pass; Simple mode has
    /// one button that uses the tier from Settings.
    @ViewBuilder
    private func rerun(_ label: String) -> some View {
        if mode == .advanced {
            RerunButton(recording: recording, label: label)
                .help("Transcribe again on another tier, or identify the speakers again")
        } else {
            Button(label) { state.retranscribe(recording) }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Transcribe this recording again")
        }
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
