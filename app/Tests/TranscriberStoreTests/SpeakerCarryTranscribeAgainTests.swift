import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A name follows its voice through Transcribe Again, on both ways the writer
/// stores a new revision: a whole transcript at once, and a job that appended
/// partial rows and then completed.
@MainActor
final class SpeakerCarryTranscribeAgainTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-again-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let schema = Schema(TranscriberSchema.models)
        container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: scratch.appendingPathComponent("t.store"))
        ])
    }

    override func tearDown() async throws {
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    private func lines(_ labels: [String?], text: String) -> [Segment] {
        labels.enumerated().map {
            Segment(index: $0.offset, startMs: $0.offset * 5_000, endMs: $0.offset * 5_000 + 4_000,
                    text: "\(text) \($0.offset)", speakerId: $0.element)
        }
    }

    private func roster(_ labels: [String?]) -> [SpeakerLabel] {
        var seen: [String] = []
        for case let label? in labels where !seen.contains(label) { seen.append(label) }
        return seen.map { SpeakerLabel(id: $0, displayName: SpeakerLabel.defaultName(for: $0),
                                       speechMs: 12_000) }
    }

    private func seededAndRenamed() async throws -> (id: UUID, writer: TranscriptWriter) {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let first: [String?] = ["S1", "S2", "S1", "S2", "S1", "S2"]
        try await writer.storeTranscript(segments: lines(first, text: "first"), roster: roster(first),
                                         modelId: "turbo", language: "en", processMs: 1,
                                         didDiarize: true, for: id)
        let context = container.mainContext
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let s1 = try XCTUnwrap(try context.fetch(descriptor).first?.speakers?
            .first { $0.speakerId == "S1" })
        try RecordingStore.rename(s1, to: "Maria", in: context)
        return (id, writer)
    }

    private func namesOnLines(_ id: UUID) throws -> [String?] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let recording = try XCTUnwrap(try context.fetch(descriptor).first)
        let names = Dictionary((recording.speakers ?? []).map { ($0.speakerId, $0.displayName) },
                               uniquingKeysWith: { first, _ in first })
        return (recording.transcript?.orderedSegments ?? []).map { $0.speakerId.flatMap { names[$0] } }
    }

    func testAWholeNewTranscriptKeepsTheNameOnTheVoice() async throws {
        let (id, writer) = try await seededAndRenamed()
        let again: [String?] = ["S2", "S1", "S2", "S1", "S2", "S1"]   // Maria's opener dropped, numbering flipped

        try await writer.storeTranscript(segments: lines(again, text: "again"), roster: roster(again),
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: true, for: id)

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Speaker 2"])
    }

    func testAJobThatAppendedPartialRowsKeepsTheNameOnTheVoiceWhenItCompletes() async throws {
        let (id, writer) = try await seededAndRenamed()
        let open = try await writer.openPartialTranscript(modelId: "large", language: "en", for: id)
        try await writer.appendPartial(lines([nil, nil, nil], text: "partial"), to: try XCTUnwrap(open))
        let again: [String?] = ["S2", "S1", "S2", "S1", "S2", "S1"]

        try await writer.completeTranscript(open, segments: lines(again, text: "again"),
                                            roster: roster(again), modelId: "large", language: "en",
                                            processMs: 1, didDiarize: true, for: id)

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Speaker 2"])
    }
}
