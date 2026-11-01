import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// Committed live segments reach the store while the recording is going, in
/// batches, and the Stop path finishes the same revision.
@MainActor
final class LiveTranscriptPersisterTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func fetch(_ id: UUID) throws -> StoredRecording? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func segment(_ index: Int, _ text: String) -> Segment {
        Segment(index: index, startMs: index * 2_000, endMs: index * 2_000 + 1_800, text: text)
    }

    private func persister(for id: UUID, flushMs: Int = 20) -> LiveTranscriptPersister {
        LiveTranscriptPersister(writer: TranscriptWriter(modelContainer: container),
                                recordingId: id, modelId: "turbo", language: "tl",
                                flushIntervalMs: flushMs)
    }

    func testCommitsLandInOrderWhileRecordingAndCoalesceIntoBatches() async throws {
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let persister = persister(for: id)
        await persister.open()

        persister.append([segment(0, "So yung quotation")])
        persister.append([segment(1, "kailangan nating")])
        persister.append([segment(2, "i-send tomorrow.")])
        await persister.drain()

        let recording = try XCTUnwrap(try fetch(id))
        let transcript = try XCTUnwrap(recording.transcript)
        XCTAssertFalse(transcript.isComplete, "still recording")
        XCTAssertEqual(transcript.orderedSegments.map(\.text),
                       ["So yung quotation", "kailangan nating", "i-send tomorrow."])
        XCTAssertLessThan(persister.writes, 3, "three commits in 20 ms are not three saves")
        XCTAssertEqual(persister.failedWrites, 0)
    }

    func testCompletingReplacesTheLiveRowsAndClosesTheRevision() async throws {
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let persister = persister(for: id, flushMs: 60_000)
        await persister.open()
        persister.append([segment(0, "Una."), segment(1, "Pangalawa.")])

        // Stop: the final list is the same text plus the flushed tail, and
        // completion must not wait out the coalescing interval.
        let started = Date()
        let revision = try await persister.complete(
            segments: [segment(0, "Una."), segment(1, "Pangalawa."), segment(2, "Tapos.")],
            processMs: 1_000
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        let recording = try XCTUnwrap(try fetch(id))
        XCTAssertEqual(revision, 1, "completion finishes the open revision, not a new one")
        XCTAssertEqual(recording.transcripts?.count, 1)
        let transcript = try XCTUnwrap(recording.transcript)
        XCTAssertTrue(transcript.isComplete)
        XCTAssertEqual(transcript.orderedSegments.map(\.text), ["Una.", "Pangalawa.", "Tapos."])
        XCTAssertTrue(recording.searchText.contains("Tapos"), "reindexed at completion")

        // Nothing appended after Stop can reach the store.
        persister.append([segment(3, "Late.")])
        await persister.drain()
        XCTAssertEqual(try fetch(id)?.transcript?.orderedSegments.count, 3)
    }

    func testCompletingWithoutAnOpenRevisionStoresAFreshOne() async throws {
        // `open()` never ran, or failed: Stop still produces a transcript.
        let id = try RecordingStore.create(kind: .recording, in: container.mainContext).id
        let persister = persister(for: id)
        persister.append([segment(0, "Ignored until Stop.")])

        let revision = try await persister.complete(segments: [segment(0, "Buong.")], processMs: 5)

        XCTAssertEqual(revision, 1)
        let transcript = try XCTUnwrap(try fetch(id)?.transcript)
        XCTAssertTrue(transcript.isComplete)
        XCTAssertEqual(transcript.orderedSegments.map(\.text), ["Buong."])
    }
}

// MARK: - A store that will not take the rows (finding 16)

private struct BrokenWriter: LiveTranscriptWriting {
    struct Refused: LocalizedError { var errorDescription: String? { "the store refused the write" } }
    var failOpen = false
    var failAppend = false

    func openPartialTranscript(modelId: String, language: String, for id: UUID) async throws -> UUID? {
        if failOpen { throw Refused() }
        return UUID()
    }
    func appendPartial(_ segments: [Segment], to transcriptId: UUID) async throws {
        if failAppend { throw Refused() }
    }
    func completeTranscript(_ transcriptId: UUID?, segments: [Segment], roster: [SpeakerLabel],
                            modelId: String, language: String, processMs: Int, didDiarize: Bool,
                            performanceJSON: String?, for id: UUID) async throws -> Int { 1 }
}

private final class Notices {
    var sentences: [String] = []
}

@MainActor
final class LiveTranscriptPersisterDegradedTests: XCTestCase {

    private func segment(_ index: Int) -> Segment {
        Segment(index: index, startMs: index * 2_000, endMs: index * 2_000 + 1_800, text: "line \(index)")
    }

    private func persister(_ writer: BrokenWriter, notices: Notices) -> LiveTranscriptPersister {
        let persister = LiveTranscriptPersister(writer: writer, recordingId: UUID(), modelId: "turbo",
                                                language: "tl", flushIntervalMs: 0)
        persister.onDegraded = { notices.sentences.append($0) }
        return persister
    }

    func testAFailedOpenIsToldToThePersonOnceAndTheRecordingGoesOn() async {
        let notices = Notices()
        let persister = persister(BrokenWriter(failOpen: true), notices: notices)

        await persister.open()
        persister.append([segment(0)])
        await persister.drain()
        persister.append([segment(1)])
        await persister.drain()

        XCTAssertNil(persister.transcriptId)
        XCTAssertEqual(notices.sentences.count, 1, "told once, however many lines follow")
        XCTAssertTrue(notices.sentences[0].contains("the store refused the write"))
        XCTAssertTrue(notices.sentences[0].contains("not being saved"))
        XCTAssertTrue(notices.sentences[0].contains("Stop saves everything"),
                      "and says what is still safe")
    }

    func testAFailedBatchIsToldOnceNotOncePerBatch() async {
        let notices = Notices()
        let persister = persister(BrokenWriter(failAppend: true), notices: notices)
        await persister.open()

        for index in 0..<4 {
            persister.append([segment(index)])
            await persister.drain()
        }

        XCTAssertEqual(persister.failedWrites, 4)
        XCTAssertEqual(notices.sentences.count, 1)
        XCTAssertNotNil(persister.degradedReason)
    }

    func testAHealthyStoreIsNeverMentioned() async {
        let notices = Notices()
        let persister = persister(BrokenWriter(), notices: notices)
        await persister.open()
        persister.append([segment(0)])
        await persister.drain()

        XCTAssertTrue(notices.sentences.isEmpty)
        XCTAssertNil(persister.degradedReason)
        XCTAssertEqual(persister.writes, 1)
    }
}
