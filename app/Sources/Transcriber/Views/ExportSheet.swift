import SwiftUI
import TranscriberCore
import TranscriberStore
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let recording: StoredRecording

    @State private var isSaving = false
    /// Rendered once per format or filter change. Recomputing it on every
    /// redraw would re-render the whole transcript each time the sheet so
    /// much as blinks.
    @State private var text = ""
    @State private var includeSpeakers: Set<String> = []
    @State private var fromText = ""
    @State private var toText = ""

    private var speakers: [StoredSpeaker] {
        (recording.speakers ?? []).sorted { $0.speechMs > $1.speechMs }
    }

    /// Nil when every speaker is ticked, so the export is unfiltered and
    /// unattributed lines stay in.
    private var options: ExportOptions {
        let all = Set(speakers.map(\.speakerId))
        return ExportOptions(
            speakerIds: includeSpeakers == all || speakers.isEmpty ? nil : includeSpeakers,
            fromMs: TimeFormat.parse(fromText),
            toMs: TimeFormat.parse(toText)
        )
    }

    /// Changes whenever the render would.
    private var renderKey: String {
        "\(state.exportFormat.rawValue)|\(includeSpeakers.sorted().joined(separator: ","))|\(fromText)|\(toText)"
    }

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 16) {
            Text("Export “\(recording.title)”")
                .font(.headline)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Format", selection: $state.exportFormat) {
                        ForEach(ExportFormat.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(state.exportFormat.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 220, alignment: .leading)
                }

                filters
            }

            GroupBox("Preview") {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(height: 190)
            }

            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                if options.isFiltering {
                    Text("Filtered")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                        .help("The export contains only the ticked speakers and the time range")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") { isSaving = true }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580)
        .onAppear { includeSpeakers = Set(speakers.map(\.speakerId)) }
        .task(id: renderKey) {
            text = state.exportText(recording, format: state.exportFormat, options: options)
        }
        .fileExporter(
            isPresented: $isSaving,
            document: TextDocument(text: text, format: state.exportFormat),
            contentType: state.exportFormat.contentType,
            defaultFilename: Exporter.filename(
                for: RecordingStore.document(for: recording), format: state.exportFormat
            )
        ) { result in
            if case .failure(let error) = result {
                state.alert = AppState.AppAlert(title: "The export failed",
                                                message: error.localizedDescription)
            }
            dismiss()
        }
    }

    /// Who and when. Both default to everything; a half-typed time is
    /// ignored rather than read as zero.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            if speakers.count > 1 {
                Text("Speakers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(speakers) { speaker in
                        Toggle(isOn: Binding(
                            get: { includeSpeakers.contains(speaker.speakerId) },
                            set: { on in
                                if on { includeSpeakers.insert(speaker.speakerId) }
                                else { includeSpeakers.remove(speaker.speakerId) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SpeakerPalette.color(speaker.colorIndex))
                                    .frame(width: 7, height: 7)
                                Text(speaker.displayName)
                                Text(TimeFormat.coarse(ms: speaker.speechMs))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxHeight: 120)
            }

            Text("Time range")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("0:00", text: $fromText)
                    .frame(width: 70)
                Text("to").foregroundStyle(.secondary)
                TextField(TimeFormat.short(ms: recording.durationMs), text: $toText)
                    .frame(width: 70)
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.callout, design: .monospaced))
            .help("Lines that start inside this range. Type a time as 12:34 or 1:02:03.")
        }
        .frame(minWidth: 200, alignment: .leading)
    }

    private var preview: String {
        text.count > 4_000 ? String(text.prefix(4_000)) + "\n…" : text
    }
}

extension ExportFormat {
    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .json: return .json
        // No system type for the subtitle formats or a reliable one for
        // Markdown, so the extension is what carries the meaning. `.data`
        // keeps the panel from renaming the file.
        case .srt, .vtt, .markdown: return .data
        }
    }
}

struct TextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .json, .data]

    var text: String
    var format: ExportFormat

    init(text: String, format: ExportFormat) {
        self.text = text
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
        format = .txt
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
