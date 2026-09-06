import Foundation
import TranscriberCore
import TranscriberEngine

// `transcribe --notes FILE.json`: a draft of the notes for a recording the
// app exported as JSON, through the same pipeline and the same backend the
// app uses, plus the measurement the app does not make: how much of each
// note is in the transcript, which language the notes lean to, and how many
// of the hand-written notes in the export the draft also found.
//
// The reference is whatever notes the export carries. A meeting with notes
// written by hand is therefore a scored pair with no extra work.

/// One run, machine-readable. `eval/notes_eval.py` writes the same fields
/// for a candidate model, so the two can be put side by side.
struct NotesRunReport: Codable {
    var document: String
    var model: String
    var style: NotesStyle
    var durationMs: Int
    var chunkCount: Int
    var elapsedMs: Int
    var items: [String: Int]
    var itemsTotal: Int
    var withSource: Int
    var grounding: NotesScoring.Grounding
    var transcriptLanguage: NotesScoring.LanguageMix
    var notesLanguage: NotesScoring.LanguageMix
    var coverage: NotesScoring.Coverage
    var warnings: [String]
    var draft: NotesDraft
}

func runNotes(documentURL: URL, style: NotesStyle, maxCharacters: Int,
              output: URL?, json: URL?) async -> Never {
    let document: MeetingDocument
    do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        document = try decoder.decode(MeetingDocument.self, from: Data(contentsOf: documentURL))
    } catch {
        log("error: could not read \(documentURL.path) as a JSON export: \(error.localizedDescription)")
        exit(1)
    }
    guard let engine = NotesEngines.systemModel() else {
        log("error: \(NotesAvailability.needsNewerMacOS.message)")
        exit(1)
    }
    let availability = await engine.availability()
    guard availability.isAvailable else {
        log("error: \(availability.message)")
        exit(1)
    }

    let transcriptText = document.segments.map(\.displayText).joined(separator: " ")
    let transcriptMix = NotesScoring.languageMix(of: transcriptText)
    log("document: \(document.title), \(TimeFormat.short(ms: document.durationMs)), "
        + "\(document.segments.count) segments, \(document.items.count) hand-written notes, "
        + "\(Int(transcriptMix.tagalogShare * 100)) % Tagalog words")
    log("model: \(engine.modelId), style: \(style.rawValue), \(maxCharacters) characters per part")

    let draft: NotesDraft
    do {
        draft = try await NotesPipeline.generate(
            segments: document.segments, speakers: document.speakers, title: document.title,
            style: style, using: engine, maxCharacters: maxCharacters
        ) { progress in log("  \(progress.label)") }
    } catch {
        log("error: \(error.localizedDescription)")
        exit(1)
    }

    let rendered = draft.markdown(title: document.title)
    if let output {
        do {
            try rendered.write(to: output, atomically: true, encoding: .utf8)
            log("wrote \(output.path)")
        } catch {
            log("error: could not write \(output.path): \(error.localizedDescription)")
            exit(1)
        }
    } else {
        print(rendered)
    }

    let grounding = NotesScoring.grounding(of: draft.items, in: document.segments)
    let notesMix = NotesScoring.languageMix(of: ([draft.summary] + draft.items.map(\.text)).joined(separator: " "))
    let coverage = NotesScoring.coverage(reference: document.items, draft: draft.items)
    log("draft: \(draft.items.count) notes (\(draft.items.filter { $0.sourceMs != nil }.count) with a line) "
        + "and a summary of \(draft.summary.count) characters, from \(draft.chunkCount) parts in "
        + "\(TimeFormat.short(ms: draft.elapsedMs))")
    log(String(format: "grounding: mean overlap %.2f, %d of %d notes under %.1f",
               grounding.meanOverlap, grounding.ungrounded, grounding.itemsScored,
               NotesScoring.Grounding.threshold))
    log("language: transcript \(Int(transcriptMix.tagalogShare * 100)) % Tagalog words, "
        + "notes \(Int(notesMix.tagalogShare * 100)) %")
    if coverage.reference > 0 {
        log("coverage: \(coverage.covered) of \(coverage.reference) hand-written notes are in the draft; "
            + "\(coverage.matched) of \(coverage.draft) draft notes match a hand-written one")
    }
    for warning in draft.warnings { log("  WARNING \(warning)") }

    if let json {
        let report = NotesRunReport(
            document: document.title, model: engine.modelId, style: style,
            durationMs: document.durationMs, chunkCount: draft.chunkCount, elapsedMs: draft.elapsedMs,
            items: Dictionary(uniqueKeysWithValues: MeetingItemKind.allCases.map { ($0.rawValue, draft.items($0).count) }),
            itemsTotal: draft.items.count,
            withSource: draft.items.filter { $0.sourceMs != nil }.count,
            grounding: grounding, transcriptLanguage: transcriptMix, notesLanguage: notesMix,
            coverage: coverage, warnings: draft.warnings, draft: draft
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: json.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(report).write(to: json)
            log("wrote \(json.path)")
        } catch {
            log("error: could not write \(json.path): \(error.localizedDescription)")
            exit(1)
        }
    }
    exit(0)
}
