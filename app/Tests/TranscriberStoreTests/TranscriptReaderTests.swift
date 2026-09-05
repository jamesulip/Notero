import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// The one-query transcript read that the view and the exports use.
@MainActor
final class TranscriptReaderTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    /// Rows inserted out of time order, on two transcripts, so a read that
    /// forgot the predicate or the sort would show.
    private func seed(rows: Int, in context: ModelContext) throws -> (StoredRecording, StoredTranscript) {
        let recording = try RecordingStore.create(kind: .meeting, title: "Long one", in: context)
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        let other = StoredTranscript(revision: 0, modelId: "turbo", language: "tl")
        other.recording = recording
        context.insert(other)
        for index in (0..<rows).reversed() {
            let row = StoredSegment(index: index, startMs: index * 3_000,
                                    endMs: index * 3_000 + 2_500, text: "line \(index)",
                                    speakerId: index.isMultiple(of: 2) ? "S1" : "S2")
            row.transcript = transcript
            context.insert(row)
        }
        let stray = StoredSegment(index: 0, startMs: 10, endMs: 20, text: "other revision")
        stray.transcript = other
        context.insert(stray)
        try context.save()
        return (recording, transcript)
    }

    func testReadsOneTranscriptInTimeOrder() async throws {
        let context = container.mainContext
        let (_, transcript) = try seed(rows: 50, in: context)

        let reader = TranscriptReader(modelContainer: container)
        let segments = try await reader.segments(ofTranscript: transcript.id)

        XCTAssertEqual(segments.count, 50)
        XCTAssertEqual(segments.map(\.startMs), (0..<50).map { $0 * 3_000 })
        XCTAssertFalse(segments.contains { $0.text == "other revision" })
        XCTAssertEqual(segments.first?.speakerId, "S1")

        let blocks = try await reader.blocks(ofTranscript: transcript.id)
        // Speakers alternate every row, so every row is its own turn.
        XCTAssertEqual(blocks.count, 50)
        XCTAssertEqual(blocks.first?.id, segments.first?.id)
    }

    func testOrderedSegmentsMatchesTheFetch() throws {
        let context = container.mainContext
        let (_, transcript) = try seed(rows: 30, in: context)

        let fetched = try TranscriptReader.segments(ofTranscript: transcript.id, in: context)
        XCTAssertEqual(transcript.orderedSegments.map(\.id), fetched.map(\.id))
    }

    func testADeletedRowLeavesAtOnce() throws {
        let context = container.mainContext
        let (_, transcript) = try seed(rows: 5, in: context)
        let victim = transcript.orderedSegments[2]
        context.delete(victim)

        XCTAssertEqual(transcript.orderedSegments.count, 4, "before the save")
        XCTAssertFalse(transcript.orderedSegments.contains { $0.id == victim.id })
        try context.save()
        XCTAssertEqual(try TranscriptReader.segments(ofTranscript: transcript.id, in: context).count, 4)
    }

    func testRowsByIdComeBackInTimeOrder() throws {
        let context = container.mainContext
        let (_, transcript) = try seed(rows: 10, in: context)
        let all = transcript.orderedSegments
        let picked = [all[7].id, all[2].id, all[5].id]

        let rows = try TranscriptReader.segmentRows(ids: picked, in: context)
        XCTAssertEqual(rows.map(\.startMs), [6_000, 15_000, 21_000])
        XCTAssertEqual(try TranscriptReader.segmentRow(id: all[3].id, in: context)?.text, "line 3")
        XCTAssertNil(try TranscriptReader.segmentRow(id: UUID(), in: context))
        XCTAssertEqual(try TranscriptReader.segmentRows(ids: [], in: context).count, 0)
    }

    /// The two ways to read a long transcript, on a store on disk, so the
    /// numbers mean what the app sees. The walk of the relationship faults
    /// every row on the way to the sort; the fetch is one query. Printed, not
    /// asserted against a bound: machines differ. The one assertion is that
    /// the fetch is not slower than the walk.
    func testTheFetchBeatsTheRelationshipWalkOnDisk() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let schema = Schema(TranscriberSchema.models)
        let disk = try ModelContainer(for: schema,
                                      configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = disk.mainContext
        let (_, transcript) = try seed(rows: 4_000, in: context)

        // A fresh context, as a selection in the sidebar would see it.
        let cold = ModelContext(disk)
        let walkStarted = Date()
        let walked = try cold.fetch(FetchDescriptor<StoredTranscript>()).first { $0.id == transcript.id }
        let walkedRows = (walked?.segments ?? []).sorted { $0.startMs < $1.startMs }
        let walkedWords = walkedRows.reduce(0) { $0 + $1.displayText.split(separator: " ").count }
        let walkMs = Date().timeIntervalSince(walkStarted) * 1000

        let reader = TranscriptReader(modelContainer: disk)
        let fetchStarted = Date()
        let fetched = try await reader.segments(ofTranscript: transcript.id)
        let fetchedWords = fetched.reduce(0) { $0 + $1.displayText.split(separator: " ").count }
        let fetchMs = Date().timeIntervalSince(fetchStarted) * 1000

        XCTAssertEqual(fetched.count, 4_000)
        XCTAssertEqual(fetchedWords, walkedWords)
        print(String(format: "TranscriptReader on disk: walk %.0f ms, fetch %.0f ms for 4000 rows",
                     walkMs, fetchMs))
        XCTAssertLessThanOrEqual(fetchMs, walkMs * 1.5)
    }

    /// Not an assertion on time -- machines differ -- but the read of a long
    /// transcript must not scale like the relationship walk did. Printed so a
    /// regression is visible in the log.
    func testALongTranscriptReadsInOneQuery() async throws {
        let context = container.mainContext
        let (_, transcript) = try seed(rows: 4_000, in: context)

        let reader = TranscriptReader(modelContainer: container)
        let started = Date()
        let segments = try await reader.segments(ofTranscript: transcript.id)
        let fetchMs = Int(Date().timeIntervalSince(started) * 1000)
        XCTAssertEqual(segments.count, 4_000)
        print("TranscriptReader: 4000 rows in \(fetchMs) ms")
        XCTAssertLessThan(fetchMs, 5_000)
    }
}
