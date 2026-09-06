import Foundation
import TranscriberCore

// Automatic notes: the backends and the pipeline over them.
//
// The fourth seam beside the three in `Protocols.swift`. Everything above
// talks to `NotesGenerating` and never to a model framework directly, so a
// second backend -- an MLX model for a language Apple's model refuses -- is
// a new conformance and one line where the app picks one.

// MARK: - The seam

/// A language model that writes notes from one part of a transcript.
public protocol NotesGenerating: Sendable {
    /// Shown with the draft, so the user knows what wrote it.
    var modelId: String { get }
    func availability() async -> NotesAvailability
    /// The summary and the notes for one part. Throws a `NotesError`; the
    /// pipeline knows what to do with `partTooLong` and `contentRefused`.
    func notes(for chunk: NotesChunk, style: NotesStyle) async throws -> ChunkNotes
    /// One summary of the meeting from the summaries of its parts.
    func summary(partSummaries: [String], title: String, style: NotesStyle) async throws -> String
}

/// Which backends this build and this Mac have.
public enum NotesEngines {

    /// Apple's system model, when this macOS has the framework. Nil on
    /// macOS 15, where nothing in this build can write notes. Whether the
    /// model can run is the engine's `availability()`, asked at use.
    public static func systemModel() -> (any NotesGenerating)? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return FoundationNotesEngine() }
        #endif
        return nil
    }
}

// MARK: - The pipeline

/// Reads the transcript part by part, resolves the answers to draft items
/// with back-links, and writes the summary. Backend-agnostic, so a test
/// drives it with a fake and the CLI with the real thing.
public enum NotesPipeline {

    public static func generate(
        segments: [Segment], speakers: [SpeakerLabel], title: String, style: NotesStyle,
        using engine: any NotesGenerating,
        maxCharacters: Int = NotesChunker.defaultMaxCharacters,
        progress: (@Sendable (NotesProgress) -> Void)? = nil
    ) async throws -> NotesDraft {
        guard !segments.isEmpty else { throw NotesError.noTranscript }
        let availability = await engine.availability()
        guard availability.isAvailable else { throw NotesError.unavailable(availability) }

        let started = Date()
        let chunks = NotesChunker.chunks(from: segments, speakers: speakers, maxCharacters: maxCharacters)
        guard !chunks.isEmpty else { throw NotesError.noTranscript }

        var items: [NotesDraft.Item] = []
        var summaries: [String] = []
        var warnings: [String] = []
        for (done, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progress?(NotesProgress(stage: .reading, chunksDone: done, chunkCount: chunks.count))
            let part = try await read(chunk, style: style, using: engine)
            items.append(contentsOf: part.items)
            summaries.append(contentsOf: part.summaries)
            warnings.append(contentsOf: part.warnings)
        }

        try Task.checkCancellation()
        progress?(NotesProgress(stage: .summarizing, chunksDone: chunks.count, chunkCount: chunks.count))
        let summary: String
        if summaries.count <= 1 {
            summary = summaries.first ?? ""
        } else {
            summary = try await summarize(summaries, title: title, style: style, using: engine)
        }

        return NotesDraft(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            items: NotesReducer.dedupe(items),
            modelId: engine.modelId,
            style: style,
            chunkCount: chunks.count,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
            warnings: warnings
        )
    }

    struct PartResult {
        var items: [NotesDraft.Item] = []
        var summaries: [String] = []
        var warnings: [String] = []
    }

    /// One part, with the two recoveries. Too long: the part is halved and
    /// each half read, down to a single line. Refused by the content filter:
    /// the part is skipped and the draft says so. A language refusal is not
    /// recovered: the rest of the transcript is in the same language, and a
    /// draft made from the parts that happened to pass would misrepresent the
    /// meeting.
    static func read(_ chunk: NotesChunk, style: NotesStyle,
                     using engine: any NotesGenerating) async throws -> PartResult {
        do {
            let notes = try await engine.notes(for: chunk, style: style)
            let summary = notes.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return PartResult(items: NotesReducer.resolve(notes, in: chunk),
                              summaries: summary.isEmpty ? [] : [summary])
        } catch NotesError.partTooLong {
            guard let halves = NotesChunker.halves(of: chunk) else {
                return PartResult(warnings: [
                    "Part \(chunk.index + 1) (\(chunk.span)) is one line that is too long for the model. It was skipped.",
                ])
            }
            var out = PartResult()
            for half in halves {
                try Task.checkCancellation()
                let result = try await read(half, style: style, using: engine)
                out.items.append(contentsOf: result.items)
                out.summaries.append(contentsOf: result.summaries)
                out.warnings.append(contentsOf: result.warnings)
            }
            return out
        } catch NotesError.contentRefused {
            return PartResult(warnings: [
                "The model's content filter refused part \(chunk.index + 1) (\(chunk.span)). It was skipped.",
            ])
        }
    }

    /// The whole-meeting summary. When the part summaries together are too
    /// long for one call, each half is summarized first and the two results
    /// are summarized together.
    static func summarize(_ summaries: [String], title: String, style: NotesStyle,
                          using engine: any NotesGenerating) async throws -> String {
        do {
            return try await engine.summary(partSummaries: summaries, title: title, style: style)
        } catch NotesError.partTooLong where summaries.count >= 2 {
            let middle = summaries.count / 2
            let first = try await summarize(Array(summaries[..<middle]), title: title, style: style, using: engine)
            let second = try await summarize(Array(summaries[middle...]), title: title, style: style, using: engine)
            return try await engine.summary(partSummaries: [first, second], title: title, style: style)
        }
    }
}

// MARK: - Apple's system model

#if canImport(FoundationModels)
import FoundationModels

/// The Apple Intelligence model through the Foundation Models framework:
/// on this Mac, free, and with guided generation so the answer is typed
/// rather than parsed.
///
/// It does not accept Tagalog. Measured on 2026-09-06 on a 93-minute Taglish
/// meeting: a part with 28 % Tagalog words was accepted, parts with 50 % and
/// 92 % were refused with `unsupportedLanguageOrLocale` before any
/// generation, and the guardrail setting made no difference (docs/FINDINGS.md,
/// finding 13). The pipeline reports that as `NotesError.languageNotSupported`.
@available(macOS 26, *)
public struct FoundationNotesEngine: NotesGenerating {

    public let modelId = "apple-foundation-model"

    public init() {}

    public func availability() async -> NotesAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable("The Apple Intelligence model is not available.")
            }
        }
    }

    public func notes(for chunk: NotesChunk, style: NotesStyle) async throws -> ChunkNotes {
        // A session per part: the framework keeps the whole conversation in
        // its window, and two parts in one session would overflow it.
        let session = LanguageModelSession(instructions: NotesPrompt.instructions(style: style))
        do {
            let response = try await session.respond(
                to: "Transcript, part \(chunk.index + 1):\n\n\(chunk.text)",
                generating: GeneratedNotes.self,
                options: GenerationOptions(temperature: 0.2)
            )
            return response.content.chunkNotes
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    public func summary(partSummaries: [String], title: String, style: NotesStyle) async throws -> String {
        let session = LanguageModelSession(instructions: NotesPrompt.instructions(style: style))
        do {
            let response = try await session.respond(
                to: NotesPrompt.summaryRequest(partSummaries: partSummaries, title: title),
                options: GenerationOptions(temperature: 0.2)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    static func map(_ error: LanguageModelSession.GenerationError) -> NotesError {
        switch error {
        case .exceededContextWindowSize: return .partTooLong
        case .guardrailViolation, .refusal: return .contentRefused
        case .unsupportedLanguageOrLocale: return .languageNotSupported
        case .assetsUnavailable: return .unavailable(.modelNotReady)
        default: return .failed(error.localizedDescription)
        }
    }
}

@available(macOS 26, *)
@Generable
private enum GeneratedKind: String {
    case keyPoint, decision, actionItem, question, followUp
}

@available(macOS 26, *)
@Generable
private struct GeneratedItem {
    @Guide(description: "keyPoint, decision, actionItem, question or followUp")
    var kind: GeneratedKind
    @Guide(description: "The note, in one sentence.")
    var text: String
    @Guide(description: "The timestamp in square brackets at the start of the transcript line this note comes from, copied exactly, for example 7:05 or 1:02:33")
    var at: String
}

@available(macOS 26, *)
@Generable
private struct GeneratedNotes {
    @Guide(description: "Two or three sentences on what this part of the meeting was about.")
    var summary: String
    @Guide(description: "The notes worth keeping from this part: decisions made, tasks someone agreed to do, open questions, things to follow up, and the key points. Only what the transcript supports. Empty when there is nothing worth keeping.", .count(0...10))
    var items: [GeneratedItem]

    var chunkNotes: ChunkNotes {
        ChunkNotes(summary: summary, items: items.map { item in
            ChunkNotes.Item(kind: MeetingItemKind(rawValue: item.kind.rawValue) ?? .keyPoint,
                            text: item.text, at: item.at)
        })
    }
}
#endif
