import SwiftUI
import TranscriberCore
import TranscriberStore

/// Settings as a sidebar of panes rather than a tab strip.
///
/// The tab version was a fixed 560×430 and clipped its own content: the
/// Models tab hid the tier picker under the toolbar. Panes scroll on their
/// own, the window resizes, and each pane holds one subject.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var pane: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, audio, models, storage, updates
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .audio: return "Audio"
            case .models: return "Models"
            case .storage: return "Storage"
            case .updates: return "Updates"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "text.bubble"
            case .audio: return "mic"
            case .models: return "cpu"
            case .storage: return "internaldrive"
            case .updates: return "arrow.down.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
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
            case .updates: UpdateSettings()
            }
        }
        .navigationTitle((pane ?? .general).label)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 500, idealHeight: 580)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings

        Form {
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
                Text("Transcripts are never translated or rewritten. Code-switched "
                     + "English inside Tagalog is written as spoken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Vocabulary") {
                TextField("Names and terms", text: $settings.prompt, axis: .vertical)
                    .lineLimit(2...4)
                Text("Comma-separated hints, e.g. names of the people in the meeting. "
                     + "The model is more likely to spell them correctly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While recording") {
                Toggle("Transcribe while recording", isOn: $settings.liveTranscription)
                Text(settings.liveTranscription
                     ? "Text appears as people speak, on the Balanced model. The "
                       + "recording still gets the full whole-file pass afterwards "
                       + "for speaker identification."
                     : "Recording only. The transcript is made when you stop, by the "
                       + "whole-file pass on the tier chosen under Models — the better "
                       + "transcript, and nothing runs on the Mac during the meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("After recording") {
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
                     ? "Silero on the Neural Engine. Better in a noisy room; falls back "
                       + "to energy detection if the model cannot load."
                     : "Energy thresholding. No model to download, worse with background noise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio

struct AudioSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("Microphone") {
                MicrophonePermissionRow()
            }

            Section("Input") {
                InputGainSlider(gainDb: $settings.inputGainDb)
                Text("Built-in laptop microphones run 15-20 dB quieter than a "
                     + "headset at conversational distance. The boost applies to "
                     + "the saved recording as well as to transcription, and can "
                     + "be adjusted while recording.")
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
                     ? "Removes rumble below \(Int(HighPassFilter.roomCornerHz)) Hz — "
                     + "desk knocks, typing and aircon — before transcription. The "
                     + "saved recording keeps the full range, so turning this off "
                     + "and transcribing again undoes it."
                     : "For a microphone picking up a room rather than a person. On a "
                     + "meeting recorded across a table, most of what reaches the mic "
                     + "is low-frequency noise rather than speech. Leave this off for "
                     + "dictation or a headset, where it would cut the voice instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Label("Live recordings fall back to Balanced. Accurate cannot decode "
                          + "a window inside the hop interval, so nothing would commit.",
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
                             ? "Downloaded"
                             : "Not downloaded — fetched on first use, or below")
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
                     + "leaves the machine. Weights live in Application Support and can "
                     + "be removed and fetched again at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                LabeledContent("In use now", value: "\(footprint) MB")
                Button("Release Models from Memory") { state.releaseIdleModels() }
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
            .help("Downloading \(option.label)")
        } else if isDownloaded {
            Button("Remove") { state.removeModel(option.id) }
                .controlSize(.small)
                .disabled(state.isLiveBusy)
                .help(state.isLiveBusy
                      ? "Not while a recording is in progress"
                      : "Delete the weights from this Mac. They can be downloaded again.")
        } else {
            Button("Download") { state.downloadModel(option.id) }
                .controlSize(.small)
                .help("Fetch \(option.sizeLabel) now, so the first recording does not wait for it")
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
                     + "read. It is about 115 MB per hour and is rebuilt from the original "
                     + "when needed, so keeping it only saves time on a re-run.")
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

// MARK: - Updates

/// The only pane that describes something leaving the Mac, so it says so
/// plainly rather than putting one switch on the page and nothing else.
struct UpdateSettings: View {
    @Environment(AppState.self) private var state

    private var updater: Updater { state.updater }

    var body: some View {
        @Bindable var settings = state.settings

        Form {
            Section("This copy") {
                LabeledContent("Version", value: updater.versionText)
                LabeledContent("Last checked") {
                    Text(updater.lastChecked
                            .map { $0.formatted(date: .abbreviated, time: .shortened) }
                            ?? "Never")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Check for Updates…") { updater.checkNow(present: false) }
                        .disabled(updater.isBusy)
                    if updater.isBusy { ProgressView().controlSize(.small) }
                    if updater.hasDetails {
                        Button("Show Details…") { updater.showDetails() }
                    }
                }
                if let status = updater.statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(updater.didFail ? AnyShapeStyle(.orange)
                                                         : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.automaticUpdateChecks)
                Text("Once a day at launch, the app asks GitHub which releases exist. "
                     + "The request carries no identifier and nothing about this Mac, "
                     + "and no recording, transcript or note is ever sent anywhere. "
                     + "Turn this off and the button above still works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.skippedUpdate != nil {
                    Button("Stop skipping version \(settings.skippedUpdate ?? "")") {
                        settings.skippedUpdate = nil
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Automatic checks")
            }

            Section("How an update is checked") {
                Text(Self.checkingSummary)
                    .font(.caption)
                    .foregroundStyle(UpdateSource.canInstall ? AnyShapeStyle(.secondary)
                                                             : AnyShapeStyle(.orange))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Because the app is signed ad hoc rather than with a Developer ID, "
                     + "macOS may ask for microphone access again after an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Releases Page") { updater.openReleasesPage() }
                    .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }

    /// Built once, outside the view builder: as a ternary between two long
    /// concatenations inside `Text`, the type checker gave up on the whole Form.
    private static let checkingSummary: String = {
        guard UpdateSource.canInstall else {
            return "This build carries no update key, so it cannot check that a download "
                 + "is genuine and will not install one. It can still tell you a newer "
                 + "release exists."
        }
        return "Each release is signed with the maintainer's key. The app checks that "
             + "signature, then that the download really is Notero at the version "
             + "the release promised, before it replaces anything. A download that fails "
             + "any of those checks is thrown away."
    }()
}
