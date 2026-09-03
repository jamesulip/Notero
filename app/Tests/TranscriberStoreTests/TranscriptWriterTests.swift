import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// The progressive path through the writer: a revision opened before decoding
/// finishes, segments appended per window, then replaced by the final pass.
@MainActor
final class TranscriptWriterTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    /// Read back through a fresh context, so the test sees what is in the
    /// store and not what the main context happens to have cached.
    private func fetch(_ id: UUID) throws -> StoredRecording? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func segment(_ index: Int, _ text: String, speaker: String? = nil) -> Segment {
        Segment(index: index, startMs: index * 5_000, endMs: index * 5_000 + 4_000,
                text: text, speakerId: speaker)
    }

    func testSegmentsAppearWhileTheJobIsStillRunning() async throws {
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)

        let open = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let transcriptId = try XCTUnwrap(open)
        try await writer.appendPartial([segment(0, "Una.")], to: transcriptId)
        try await writer.appendPartial([segment(1, "Pangalawa.")], to: transcriptId)

        let recording = try XCTUnwrap(try fetch(id))
        let transcript = try XCTUnwrap(recording.transcript)
        XCTAssertFalse(transcript.isComplete)
        XCTAssertEqual(transcript.orderedSegments.map(\.text), ["Una.", "Pangalawa."])
    }

    func testCompletingReplacesThePartialRowsWithTheFinalPass() async throws {
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let open = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let transcriptId = try XCTUnwrap(open)
        try await writer.appendPartial([segment(0, "Una."), segment(1, "Pangalawa.")],
                                       to: transcriptId)

        // The final pass has speakers and may cut differently.
        let final = [segment(0, "Una.", speaker: "S1"), segment(1, "Pangalawa.", speaker: "S2")]
        let revision = try await writer.completeTranscript(
            transcriptId, segments: final,
            roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 4_000),
                     SpeakerLabel(id: "S2", displayName: "Speaker 2", speechMs: 4_000)],
            modelId: "turbo", language: "tl", processMs: 1_000, didDiarize: true, for: id
        )

        let recording = try XCTUnwrap(try fetch(id))
        XCTAssertEqual(revision, 1, "completion finishes the open revision, not a new one")
        XCTAssertEqual(recording.transcripts?.count, 1)
        let transcript = try XCTUnwrap(recording.transcript)
        XCTAssertTrue(transcript.isComplete)
        XCTAssertEqual(transcript.orderedSegments.count, 2, "partial rows must not linger")
        XCTAssertEqual(transcript.orderedSegments.map(\.speakerId), ["S1", "S2"])
        XCTAssertEqual(recording.speakers?.count, 2)
        XCTAssertTrue(recording.searchText.contains("Pangalawa"), "reindexed at completion")
    }

    func testCompletingWithNothingOpenStoresANewRevision() async throws {
        // A job that decoded no windows, or the live path: same call, no id.
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)

        let revision = try await writer.completeTranscript(
            nil, segments: [segment(0, "Solo.")], roster: [],
            modelId: "turbo", language: "tl", processMs: 10, didDiarize: false, for: id
        )

        let recording = try XCTUnwrap(try fetch(id))
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(recording.transcript?.isComplete, true)
        XCTAssertEqual(recording.transcript?.orderedSegments.map(\.text), ["Solo."])
    }

    func testASecondJobOpensItsOwnRevision() async throws {
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)

        let firstOpen = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let first = try XCTUnwrap(firstOpen)
        try await writer.appendPartial([segment(0, "Interrupted.")], to: first)
        // Job one dies here; job two starts over.
        let secondOpen = try await writer.openPartialTranscript(modelId: "large", language: "tl", for: id)
        let second = try XCTUnwrap(secondOpen)
        try await writer.appendPartial([segment(0, "Again.")], to: second)

        let recording = try XCTUnwrap(try fetch(id))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(recording.transcripts?.count, 2)
        XCTAssertEqual(recording.transcript?.revision, 2)
        XCTAssertEqual(recording.transcript?.orderedSegments.map(\.text), ["Again."])
    }
}
