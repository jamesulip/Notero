import SwiftUI
import TranscriberCore
import TranscriberStore

/// Settings as a sidebar of panes rather than a tab strip.
///
/// The tab version was a fixed 560×430 and clipped its own content: the
/// Models tab hid the tier picker under the toolbar. Panes scroll on their
/// own, the window resizes, and each pane holds one subject.
///
/// Simple mode has three panes: General, Audio and About. Advanced mode adds
/// Models and Storage, and more rows in the first two.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode
    @State private var pane: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, audio, models, storage, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .audio: return "Audio"
            case .models: return "Models"
            case .storage: return "Storage"
            case .about: return "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "text.bubble"
            case .audio: return "mic"
            case .models: return "cpu"
            case .storage: return "internaldrive"
            case .about: return "info.circle"
            }
        }
        var isAdvanced: Bool { self == .models || self == .storage }
    }

    private var panes: [Pane] {
        Pane.allCases.filter { mode == .advanced || !$0.isAdvanced }
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $pane) { pane in
                Label(pane.label, systemImage: pane.symbol).tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane ?? .general {
            case .general: GeneralSettings()
            case .audio: AudioSettings()
            case .models: ModelSettings()
            case .storage: StorageSettings()
            case .about: AboutSettings()
            }
        }
        .navigationTitle((pane ?? .general).label)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 500, idealHeight: 580)
        .onChange(of: mode) { _, mode in
            // A pane that just left the list must not stay on show.
            if mode == .simple, pane?.isAdvanced == true { pane = .general }
        }
    }
}

/// The Simple/Advanced switch, with what each mode means. The same switch
/// is in the sidebar footer and in the View menu.
struct InterfaceModeSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings

        Section {
            Picker("Mode", selection: $settings.interfaceMode) {
                ForEach(InterfaceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(settings.interfaceMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Mode")
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode
    @State private var notesAvailability: NotesAvailability?

    var body: some View {
        @Bindable var settings = state.settings
        let advanced = mode == .advanced

        Form {
            InterfaceModeSection()

            Section {
                Picker("Language", selection: $settings.language) {
                    ForEach(LanguageCatalogue.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                if let note = LanguageCatalogue.option(settings.language)?.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(settings.language == "auto" ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("The app does not translate a transcript and does not rewrite it. "
                     + "It writes code-switched English inside Tagalog as the speaker said it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Names and terms") {
                TextField("Names and terms", text: $settings.prompt, axis: .vertical)
                    .lineLimit(2...4)
                Text("Names and terms, with commas between them. For example, the names of "
                     + "the persons in the meeting. The model spells them correctly more often.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show Notero in the menu bar", isOn: Binding(
                    get: { settings.menuBarItem },
                    set: { state.setMenuBarItem($0) }
                ))
                Text("Record, pause and stop from any application. The item shows the "
                     + "clock of the recording. ⌃⌥R starts or stops a recording, and ⌃⌥P "
                     + "pauses or resumes it, in every application while the item is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("While you record") {
                Toggle("Show text while you record", isOn: $settings.liveTranscription)
                Text(liveDetail(advanced: advanced))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("After you record") {
                if advanced {
                    Picker("Speaker identification", selection: $settings.diarizationMode) {
                        ForEach(DiarizationMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.diarizationMode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Neural voice activity detection", isOn: $settings.neuralVAD)
                    Text(settings.neuralVAD
                         ? "Silero on the Neural Engine. Better in a noisy room. If the model "
                           + "cannot load, the app uses energy detection."
                         : "Energy detection. No model to download, and worse with background noise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle("Identify the speakers", isOn: Binding(
                        get: { settings.diarizationMode.performsDiarization },
                        set: { settings.diarizationMode = $0 ? .accurate : .off }
                    ))
                    Text(settings.diarizationMode.performsDiarization
                         ? "Each line gets a speaker label: Speaker 1, Speaker 2, and more. "
                           + "You can rename them. This adds time after the transcription."
                         : "No speaker labels. The transcript is ready as soon as the speech "
                           + "recognition is complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state.canDraftNotes {
                Section {
                    Picker("Language of the notes", selection: $settings.notesStyle) {
                        ForEach(NotesStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.notesStyle.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Automatic notes")
                } footer: {
                    Text(notesFooter)
                        .font(.caption)
                        .foregroundStyle(notesAvailability?.isAvailable == false ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .task { notesAvailability = await state.notesAvailability() }
            }
        }
        .formStyle(.grouped)
    }

    /// What the button in the notes pane does, and whether it can run today.
    /// The language limit is stated here because a Taglish meeting is the
    /// normal case for this app, and the model refuses it.
    private var notesFooter: String {
        let what = "Draft Notes in the notes pane reads the transcript with the Apple Intelligence "
                 + "model on this Mac and proposes a summary and notes. You select what to keep. "
                 + "Nothing leaves the Mac. The model does not accept a transcript that is mostly "
                 + "Tagalog."
        guard let notesAvailability, !notesAvailability.isAvailable else { return what }
        return what + " " + notesAvailability.message
    }

    private func liveDetail(advanced: Bool) -> String {
        if state.settings.liveTranscription {
            return "Text appears while the persons speak, on the Balanced model. The app "
                 + "still runs the full pass after the recording, and that pass gives the "
                 + "transcript you keep."
        }
        if advanced {
            return "The app records only. It makes the transcript when you stop, with the "
                 + "tier from Models. This is the better transcript, and nothing runs on "
                 + "the Mac during the meeting."
        }
        return "The app records only. It makes the transcript when you stop. This is the "
             + "better transcript, and nothing runs on the Mac during the meeting."
    }
}

// MARK: - Audio

struct AudioSettings: View {
    @Environment(AppState.self) private var state
    @Environment(\.interfaceMode) private var mode

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("Record") {
                Picker("Audio from", selection: $settings.captureSource) {
                    ForEach(CaptureSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                Text(settings.captureSource.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.captureSource.usesMicrophone {
                    InputDevicePicker(selection: $settings.microphoneUID)
                }
            }

            Section("Permissions") {
                if settings.captureSource.usesMicrophone {
                    MicrophonePermissionRow()
                }
                if settings.captureSource.usesSystemAudio {
                    SystemAudioPermissionRow()
                }
            }

            if mode == .advanced {
                Section("Input") {
                    InputGainSlider(gainDb: $settings.inputGainDb)
                    Text("The microphone in a laptop is 15 to 20 dB quieter than a headset at "
                         + "the distance of a conversation. The boost applies to the saved "
                         + "recording and to the transcription. You can adjust it during a "
                         + "recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Room") {
                    Toggle("Room mode", isOn: Binding(
                        get: { settings.roomMode },
                        set: { state.setRoomMode($0) }
                    ))
                    Text(settings.roomMode
                         ? "Removes the rumble below \(Int(HighPassFilter.roomCornerHz)) Hz before "
                         + "transcription: desk knocks, typing and air conditioning. The saved "
                         + "recording keeps the full range. To undo the effect, turn this off "
                         + "and transcribe again."
                         : "For a microphone that hears a room and not a person. In a meeting "
                         + "across a table, most of the sound at the microphone is low-frequency "
                         + "noise and not speech. Leave this off for dictation or a headset, "
                         + "where it would cut the voice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Models

struct ModelSettings: View {
    @Environment(AppState.self) private var state
    @State private var footprint = 0

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("Quality") {
                Picker("Model", selection: $settings.tier) {
                    ForEach(ModelTier.allCases) { tier in
                        Text(tier.label).tag(tier)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.tier.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !settings.tier.suitableForLive {
                    Label("A live recording uses Balanced. Accurate cannot decode a window "
                          + "inside the hop interval, thus nothing would commit.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Uses") {
                    let id = settings.modelId(for: settings.tier)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ModelCatalogue.option(id)?.label ?? id)
                        Text(state.isModelDownloaded(id)
                             ? "On this Mac"
                             : "Not on this Mac. The app downloads it at the first use, or below.")
                            .font(.caption)
                            .foregroundStyle(state.isModelDownloaded(id) ? Color.secondary : Color.orange)
                    }
                }
            }

            Section {
                ForEach(ModelCatalogue.all) { option in
                    ModelRow(option: option)
                }
            } header: {
                Text("On this Mac")
            } footer: {
                Text("Everything runs on this Mac. No account, no API key, and no audio "
                     + "leaves the machine. The weights are in Application Support. You can "
                     + "remove them and download them again at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                LabeledContent("In use now", value: "\(footprint) MB")
                Button("Release the Models from Memory") { state.releaseIdleModels() }
                    .disabled(state.isLiveBusy)
                Button("Run the Benchmark…") { state.route = .benchmark }
            }
        }
        .formStyle(.grouped)
        // Scoped to this pane: the task ends when the pane is left, so the
        // probe does not tick for a window showing something else.
        .task {
            while !Task.isCancelled {
                footprint = MemoryProbe.footprintMB()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// One catalogue entry: what it is, which tier it serves, and a button that
/// does the one thing its state allows.
private struct ModelRow: View {
    @Environment(AppState.self) private var state
    let option: ModelOption

    private var isDownloaded: Bool {
        // Read against the revision so a finished download re-checks the disk.
        _ = state.modelsRevision
        return state.isModelDownloaded(option.id)
    }

    private var servesTiers: [ModelTier] {
        ModelTier.allCases.filter { state.settings.modelId(for: $0) == option.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isDownloaded ? Color.green : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.label)
                    ForEach(servesTiers) { tier in
                        Text(tier.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .help("The \(tier.label) tier uses this model")
                    }
                    if !option.multilingual {
                        Text("English only")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(option.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                action
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var action: some View {
        if let fraction = state.modelDownloads[option.id] {
            HStack(spacing: 6) {
                ProgressView(value: fraction)
                    .frame(width: 70)
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .help("Download of \(option.label) in progress")
        } else if isDownloaded {
            Button("Remove") { state.removeModel(option.id) }
                .controlSize(.small)
                .disabled(state.isLiveBusy)
                .help(state.isLiveBusy
                      ? "Not available during a recording"
                      : "Delete the weights from this Mac. You can download them again.")
        } else {
            Button("Download") { state.downloadModel(option.id) }
                .controlSize(.small)
                .help("Download \(option.sizeLabel) now, thus the first recording does not wait for it")
        }
    }
}

// MARK: - Storage

struct StorageSettings: View {
    @Environment(AppState.self) private var state
    @State private var sizes: [(String, URL, Int64)] = []

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("Working copies") {
                Toggle("Keep the 16 kHz working copy after transcription",
                       isOn: $settings.keepWorkingCopy)
                Text("The working copy is what transcription and speaker identification "
                     + "read. It is about 115 MB per hour. The app rebuilds it from the "
                     + "original when necessary, thus this only saves time on a second run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("On disk") {
                ForEach(sizes, id: \.0) { name, url, bytes in
                    LabeledContent(name) {
                        HStack(spacing: 8) {
                            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button("Show") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.link)
                        }
                    }
                }
                Button("Refresh") { measure() }
            }
        }
        .formStyle(.grouped)
        .task(id: state.modelsRevision) { measure() }
    }

    private func measure() {
        sizes = [
            ("Recordings", Paths.recordings, size(of: Paths.recordings)),
            ("Models", Paths.models, size(of: Paths.models)),
            ("Working copies", AudioCacheLocation.directory, size(of: AudioCacheLocation.directory)),
        ]
    }

    private func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Small shim so the settings pane can show the cache without the engine's
/// `AudioCache` needing to know where the app keeps its support directory.
enum AudioCacheLocation {
    static var directory: URL {
        Paths.support.appendingPathComponent("Cache/PCM", isDirectory: true)
    }
}

// MARK: - About

/// Version, licence and where a newer build is published.
///
/// **The app does not update itself.** It downloads no code and replaces no
/// bundle, so this pane is a link and a version number rather than a check
/// with a progress bar behind it.
struct AboutSettings: View {

    var body: some View {
        Form {
            Section("This copy") {
                LabeledContent("Version", value: About.versionText)
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
            }

            Section("A newer version") {
                Text("Notero does not update itself. It downloads no code and replaces "
                     + "nothing on this Mac. To move to a newer version, get it from the "
                     + "releases page and replace the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open the Releases Page") { About.openReleasesPage() }
                    .buttonStyle(.link)
                Text("The app has an ad-hoc signature and not a Developer ID. macOS therefore "
                     + "asks for microphone access again after you replace the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Privacy") {
                Text("Every model runs on this Mac. The app has no account, no API key and "
                     + "no telemetry. It makes one request: the model download at the first "
                     + "start. No recording, transcript or note goes anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
