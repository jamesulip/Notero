import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// The two graph mutations that the main-actor store and the writer actor
/// share. Both callers must get the same result from the same input.
@MainActor
final class GraphMutationsTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func roster(_ ids: [String]) -> [SpeakerLabel] {
        ids.enumerated().map { SpeakerLabel(id: $1, displayName: "Person \($0 + 1)", speechMs: ($0 + 1) * 1_000) }
    }

    func testSyncKeepsRenamedRowsAndDropsOrphans() throws {
        let context = container.mainContext
        let recording = try RecordingStore.create(kind: .meeting, in: context)
        SpeakerSync.apply(roster(["S1", "S2", "S3"]), to: recording, in: context)
        try context.save()
        let s2 = try XCTUnwrap((recording.speakers ?? []).first { $0.speakerId == "S2" })
        s2.displayName = "Maria"

        // A second pass without S3 and with S2 first.
        SpeakerSync.apply(roster(["S2", "S1"]), to: recording, in: context)
        try context.save()

        let rows = (recording.speakers ?? []).sorted { $0.colorIndex < $1.colorIndex }
        XCTAssertEqual(rows.map(\.speakerId), ["S2", "S1"], "colours follow roster order")
        XCTAssertEqual(rows.first?.displayName, "Maria", "the user's name survives")
        XCTAssertEqual(rows.first?.speechMs, 1_000, "talk time follows the new roster")
        XCTAssertFalse(rows.contains { $0.speakerId == "S3" }, "the orphan is gone")
    }

    func testTheWriterAndTheStoreProduceTheSameRoster() async throws {
        let context = container.mainContext
        let viaStore = try RecordingStore.create(kind: .meeting, title: "store", in: context)
        RecordingStore.syncSpeakers(roster(["S1", "S2"]), on: viaStore, in: context)
        try context.save()

        let viaWriter = try RecordingStore.create(kind: .meeting, title: "writer", in: context)
        let writer = TranscriptWriter(modelContainer: container)
        _ = try await writer.storeTranscript(
            segments: [Segment(index: 0, startMs: 0, endMs: 1_000, text: "hello", speakerId: "S1")],
            roster: roster(["S1", "S2"]), modelId: "m", language: "tl",
            processMs: 1, didDiarize: true, for: viaWriter.id
        )

        let fresh = ModelContext(container)
        let all = try fresh.fetch(FetchDescriptor<StoredRecording>())
        let a = try XCTUnwrap(all.first { $0.title == "store" })
        let b = try XCTUnwrap(all.first { $0.title == "writer" })
        let shape: (StoredRecording) -> [(String, Int, Int)] = { recording in
            (recording.speakers ?? []).sorted { $0.colorIndex < $1.colorIndex }
                .map { ($0.speakerId, $0.colorIndex, $0.speechMs) }
        }
        XCTAssertEqual(shape(a).map(\.0), shape(b).map(\.0))
        XCTAssertEqual(shape(a).map(\.1), shape(b).map(\.1))
        XCTAssertEqual(shape(a).map(\.2), shape(b).map(\.2))
        XCTAssertTrue(b.searchText.contains("hello"), "the writer rebuilt the index")
    }

    func testSearchIndexFlattensEverySource() throws {
        let context = container.mainContext
        let recording = try RecordingStore.create(kind: .meeting, title: "Budget", in: context)
        recording.summary = "Q4 plan"
        recording.body = "scratch"
        let transcript = StoredTranscript(modelId: "m", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        let row = StoredSegment(index: 0, startMs: 0, endMs: 900, text: "raw text", textClean: "clean text")
        row.transcript = transcript
        context.insert(row)
        _ = try RecordingStore.addItem(.decision, text: "ship it", to: recording, in: context)
        _ = try RecordingStore.addBookmark(at: 100, label: "important", to: recording, in: context)
        try context.save()

        SearchIndex.rebuild(recording)
        let lines = recording.searchText.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["Budget", "Q4 plan", "scratch", "clean text", "ship it", "important"])
        XCTAssertFalse(recording.searchText.contains("raw text"), "the edit is what search sees")
    }
}
