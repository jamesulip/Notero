import SwiftUI
import TranscriberCore
import TranscriberStore

/// What produced this transcript, in a row under the title.
///
/// All of it was already stored -- model, language, decode cost, revision --
/// and none of it was shown anywhere. "Which model was this?" is the first
/// question asked of a transcript that reads oddly, and re-transcribing to find
/// out is an expensive way to answer it.
struct RecordingInfoBar: View {
    let recording: StoredRecording
    /// The revision on show in the transcript. Nil is the latest.
    @Binding var revision: Int?

    @State private var facts = RecordingFacts()
    @State private var showAll = false

    /// The transcript the facts describe: an older revision when one is open.
    private var shown: StoredTranscript? {
        if let revision,
           let older = (recording.transcripts ?? []).first(where: { $0.revision == revision }) {
            return older
        }
        return recording.transcript
    }

    /// Recomputing on every redraw would mean counting words across every
    /// segment of a two-hour meeting each time a slider moves. These are the
    /// only things that can change the answer.
    private var reloadKey: String {
        [recording.id.uuidString,
         shown?.id.uuidString ?? "-",
         // Rows arrive in batches while a job runs; the word count follows them.
         String(shown?.segments?.count ?? 0),
         recording.statusRaw,
         String(recording.durationMs)].joined(separator: "|")
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(facts.summary.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Text("·").foregroundStyle(.quaternary)
                }
                Text(item.value)
                    .help("\(item.label): \(item.value)\(item.help.isEmpty ? "" : "\n\n\(item.help)")")
            }

            if let revisions = recording.transcripts, revisions.count > 1 {
                Text("·").foregroundStyle(.quaternary)
                revisionMenu(revisions.sorted { $0.revision > $1.revision })
            }

            if !facts.items.isEmpty {
                Button {
                    showAll.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Everything recorded about this transcript")
                .popover(isPresented: $showAll, arrowEdge: .bottom) {
                    RecordingFactsTable(facts: facts)
                }
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .task(id: reloadKey) { facts = RecordingFacts(recording, transcript: shown) }
    }

    /// Earlier revisions are kept when a recording is transcribed again; this
    /// is the only way to read one. Hand edits stay on the revision they were
    /// made to, which is the reason anyone would look back.
    private func revisionMenu(_ revisions: [StoredTranscript]) -> some View {
        Menu {
            ForEach(revisions, id: \.id) { candidate in
                Button {
                    revision = candidate.revision == recording.transcript?.revision
                        ? nil : candidate.revision
                } label: {
                    let title = "Revision \(candidate.revision) · "
                        + "\(ModelCatalogue.option(candidate.modelId)?.label ?? candidate.modelId) · "
                        + candidate.createdAt.formatted(date: .abbreviated, time: .shortened)
                    if candidate.id == shown?.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Label(revision == nil ? "Latest revision" : "Revision \(revision ?? 0)",
                  systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Read an earlier transcript of this recording. Edits and notes stay "
            + "with the revision they were made on.")
    }
}

/// The popover: everything, laid out as label and value.
private struct RecordingFactsTable: View {
    let facts: RecordingFacts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transcript details")
                .font(.headline)
                .padding(.bottom, 10)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14,
                 verticalSpacing: 7) {
                ForEach(facts.items) { item in
                    GridRow {
                        Text(item.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.value)
                                .textSelection(.enabled)
                            if !item.help.isEmpty {
                                Text(item.help)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 420)
    }
}

/// The facts themselves, computed once per transcript rather than per redraw.
struct RecordingFacts {

    struct Item: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        /// The sentence that stops the number being misread. Empty when the
        /// value speaks for itself.
        var help: String = ""
        /// Whether it is terse enough for the one-line bar.
        var inSummary: Bool = false
    }

    var items: [Item] = []
    var summary: [Item] { items.filter(\.inSummary) }

    init() {}

    init(_ recording: StoredRecording, transcript: StoredTranscript? = nil) {
        let transcript = transcript ?? recording.transcript
        let segments = transcript?.orderedSegments ?? []

        items.append(Item(
            label: "Recorded",
            value: recording.createdAt.formatted(date: .abbreviated, time: .shortened),
            inSummary: true))

        if recording.durationMs > 0 {
            items.append(Item(
                label: "Length",
                value: TimeFormat.duration(ms: recording.durationMs),
                inSummary: true))
        }

        if let transcript {
            if !transcript.isComplete {
                items.append(Item(
                    label: "Transcript",
                    value: recording.status.isBusy ? "Arriving" : "Partial",
                    help: recording.status.isBusy
                        ? "Segments are added as each window is decoded."
                        : "Transcription did not finish. What was decoded is shown; "
                          + "transcribe again for the rest.",
                    inSummary: true))
            }
            let model = ModelCatalogue.option(transcript.modelId)
            items.append(Item(
                label: "Model",
                value: model?.label ?? transcript.modelId,
                help: model?.detail ?? "Not one of the catalogued models.",
                inSummary: true))

            let language = LanguageCatalogue.option(transcript.language)
            items.append(Item(
                label: "Language",
                value: transcript.language == "auto"
                    ? "Auto-detected"
                    : (language?.label ?? transcript.language),
                inSummary: true))

            let words = segments.reduce(0) {
                $0 + $1.displayText.split(whereSeparator: \.isWhitespace).count
            }
            if words > 0 {
                items.append(Item(
                    label: "Words",
                    value: "\(words.formatted()) words",
                    inSummary: true))
            }
            items.append(Item(
                label: "Segments",
                value: segments.count.formatted()))

            if transcript.processMs > 0 {
                items.append(Item(
                    label: "Processing",
                    value: processing(transcript.processMs, audioMs: recording.durationMs),
                    help: "Time the model spent on this recording. A live session "
                        + "decodes while it records, so this overlaps the recording "
                        + "itself rather than following it."))
            }

            items.append(Item(
                label: "Transcribed",
                value: transcript.createdAt.formatted(date: .abbreviated, time: .shortened)))

            if transcript.revision > 1 {
                items.append(Item(
                    label: "Revision",
                    value: "\(transcript.revision)",
                    help: "Earlier revisions are kept. Re-transcribing adds one "
                        + "rather than overwriting what you may have annotated."))
            }

            let speakers = recording.speakers ?? []
            items.append(Item(
                label: "Speakers",
                value: speakers.isEmpty
                    ? (transcript.didDiarize ? "None found" : "Not identified")
                    : "\(speakers.count)",
                help: transcript.didDiarize
                    ? ""
                    : "Speaker identification did not run on this transcript."))
        } else {
            items.append(Item(
                label: "Transcript",
                value: recording.status == .failed ? "Failed" : "None yet",
                inSummary: true))
        }

        if let audio = recording.audioFileName {
            items.append(Item(
                label: "Audio",
                value: audioDescription(recording, fileName: audio),
                help: audio))
        }

        if let warning = recording.warningMessage, !warning.isEmpty {
            items.append(Item(label: "Warning", value: warning))
        }
        if let error = recording.errorMessage, !error.isEmpty {
            items.append(Item(label: "Error", value: error))
        }
    }

    /// "2:14 · 5.8× faster than real time". The ratio is the number that
    /// actually says whether this machine can keep up.
    private func processing(_ processMs: Int, audioMs: Int) -> String {
        let time = TimeFormat.duration(ms: processMs)
        guard audioMs > 0, processMs > 0 else { return time }
        let ratio = Double(audioMs) / Double(processMs)
        return ratio >= 1
            ? String(format: "%@ · %.1f× faster than real time", time, ratio)
            : String(format: "%@ · %.1f× slower than real time", time, 1 / ratio)
    }

    private func audioDescription(_ recording: StoredRecording, fileName: String) -> String {
        var parts = ["\(recording.audioSampleRate / 1000) kHz"]
        if let url = recording.audioURL,
           let size = try? FileManager.default
               .attributesOfItem(atPath: url.path)[.size] as? Int64 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        } else {
            parts.append("file missing")
        }
        parts.append((fileName as NSString).pathExtension.uppercased())
        return parts.joined(separator: " · ")
    }
}
