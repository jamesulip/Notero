import SwiftUI
import TranscriberCore
import TranscriberStore

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            TranscriptionSettings().tabItem { Label("Transcription", systemImage: "waveform") }
            ModelSettings().tabItem { Label("Models", systemImage: "cpu") }
            StorageSettings().tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 560, height: 430)
    }
}

struct TranscriptionSettings: View {
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

            Section("Microphone") {
                InputGainSlider(gainDb: $settings.inputGainDb)
                Text("Built-in laptop microphones run 15-20 dB quieter than a "
                     + "headset at conversational distance. The boost applies to "
                     + "the saved recording as well as to transcription, and can "
                     + "be adjusted while recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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

            Section("Pipeline") {
                Toggle("Transcribe while recording", isOn: $settings.liveTranscription)
                Toggle("Identify speakers", isOn: $settings.diarize)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ModelCatalogue.option(id)?.label ?? id)
                        Text(ModelCatalogue.option(id)?.sizeLabel ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Downloaded") {
                ForEach(ModelCatalogue.all) { option in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ModelCatalogue.isDownloaded(option.id, modelsDirectory: Paths.models)
                              ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(option.label)
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
                        Spacer()
                        Text(option.sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button("Run the Benchmark") { state.route = .benchmark }
                Button("Release Models from Memory") { state.releaseIdleModels() }
                LabeledContent("Memory in use", value: "\(footprint) MB")
            } footer: {
                Text("Everything runs on this Mac. No account, no API key, and no audio "
                     + "leaves the machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                footprint = MemoryProbe.footprintMB()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

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
                            Button("Show") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.link)
                        }
                    }
                }
                Button("Refresh") { measure() }
            }
        }
        .formStyle(.grouped)
        .task { measure() }
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
