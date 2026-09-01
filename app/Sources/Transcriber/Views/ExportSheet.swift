import SwiftUI
import TranscriberCore
import TranscriberStore
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let recording: StoredRecording

    @State private var format: ExportFormat = .txt
    @State private var isSaving = false
    /// Rendered once per format change. Recomputing it on every redraw would
    /// re-render the whole transcript each time the sheet so much as blinks.
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export “\(recording.title)”")
                .font(.headline)

            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            Text(format.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") { isSaving = true }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task(id: format) { text = state.exportText(recording, format: format) }
        .fileExporter(
            isPresented: $isSaving,
            document: TextDocument(text: text, format: format),
            contentType: format.contentType,
            defaultFilename: Exporter.filename(
                for: RecordingStore.document(for: recording), format: format
            )
        ) { result in
            if case .failure(let error) = result {
                state.alert = AppState.AppAlert(title: "Export failed",
                                                message: error.localizedDescription)
            }
            dismiss()
        }
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
        // No system type for either subtitle format, so the extension is what
        // carries the meaning. `.data` keeps the panel from renaming the file.
        case .srt, .vtt: return .data
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
