import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// The writer replaces rows without a moment in which the transcript is empty,
/// and appends at a cost that does not grow with the rows already saved
/// (finding 16).
@MainActor
final class TranscriptWriterSafetyTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-safety-\(UUID().uuidString)")
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

    private func segment(_ index: Int, _ text: String = "line", speaker: String? = nil) -> Segment {
        Segment(index: index, startMs: index * 1_400, endMs: index * 1_400 + 1_300,
                text: "\(text) \(index)", speakerId: speaker)
    }

    /// What a different process would see in the store right now.
    private func rowCount(inRange range: Range<Int>? = nil) throws -> Int {
        try Self.rowCount(in: container, inRange: range)
    }

    private nonisolated static func rowCount(in container: ModelContainer,
                                             inRange range: Range<Int>? = nil) throws -> Int {
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<StoredSegment>())
        guard let range else { return rows.count }
        return rows.filter { range.contains($0.startMs) }.count
    }

    /// Runs `body` and calls `check` at every save boundary the writer
    /// crosses. A quit lands on one of them.
    private func atEverySave(_ check: @escaping @Sendable () throws -> Void,
                             during body: () async throws -> Void) async throws -> Int {
        let saves = Counter()
        let failures = Failures()
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { _ in
            saves.increment()
            do { try check() } catch { failures.record(error) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try await body()
        if let first = failures.first { throw first }
        return saves.value
    }

    // MARK: - No moment with nothing in the transcript

    func testCompletingNeverLeavesTheStoreWithoutTheTranscript() async throws {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let opened = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let open = try XCTUnwrap(opened)
        try await writer.appendPartial((0..<6).map { segment($0, "partial") }, to: open)
        let final = (0..<8).map { segment($0, "final", speaker: "S1") }

        let container = self.container!
        let saves = try await atEverySave({
            // The live rows must not go before the final rows are in.
            let rows = try Self.rowCount(in: container)
            if rows < 8 {
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "a save left \(rows) rows in the store while the transcript was being finished"])
            }
        }, during: {
            try await writer.completeTranscript(
                open, segments: final, roster: [], modelId: "turbo", language: "tl",
                processMs: 1, didDiarize: false, for: id)
        })

        XCTAssertGreaterThanOrEqual(saves, 1)
        let fresh = ModelContext(container)
        let recording = try XCTUnwrap(try fresh.fetch(FetchDescriptor<StoredRecording>()).first)
        XCTAssertEqual(recording.transcripts?.count, 1, "the partial revision is gone afterwards")
        XCTAssertEqual(recording.transcript?.revision, 1)
        XCTAssertEqual(recording.transcript?.isComplete, true)
        XCTAssertEqual(recording.transcript?.orderedSegments.map(\.text).first, "final 0")
        XCTAssertEqual(try rowCount(), 8, "no partial row is left over")
    }

    func testReplacingATurnNeverLeavesTheStoreWithoutIt() async throws {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        try await writer.storeTranscript(
            segments: (0..<10).map { segment($0, "old") }, roster: [], modelId: "turbo",
            language: "tl", processMs: 1, didDiarize: false, for: id)
        // The turn is rows 3 and 4: 4,200 ms up to 7,000 ms.
        let turn = 4_200..<7_000

        let container = self.container!
        _ = try await atEverySave({
            if try Self.rowCount(in: container, inRange: turn) == 0 {
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "a save left the turn with no rows at all"])
            }
        }, during: {
            try await writer.replaceSegments(
                fromMs: 4_200, toMs: 7_000,
                with: [Segment(index: 0, startMs: 4_300, endMs: 6_800, text: "new text")],
                for: id)
        })

        let texts = try await TranscriptReader(modelContainer: container).segments(
            ofTranscript: try XCTUnwrap(
                ModelContext(container).fetch(FetchDescriptor<StoredTranscript>()).first?.id)
        ).map(\.text)
        XCTAssertEqual(texts.count, 9)
        XCTAssertTrue(texts.contains("new text"))
        XCTAssertFalse(texts.contains("old 3"))
    }

    // MARK: - Cost

    /// Time for one call, in seconds.
    private func seconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await body()
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    func testFinishingALongTranscriptTakesSecondsNotMinutes() async throws {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let opened = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let open = try XCTUnwrap(opened)
        let rows = 4_000
        for n in 0..<(rows / 250) {
            try await writer.appendPartial((n * 250..<(n + 1) * 250).map { segment($0, "partial") }, to: open)
        }

        let took = try await seconds {
            try await writer.completeTranscript(
                open, segments: (0..<rows).map { segment($0, "final", speaker: "S1") }, roster: [],
                modelId: "turbo", language: "tl", processMs: 1, didDiarize: false, for: id)
        }

        // Deleting 4,000 rows one by one and saving took 15 s here; the cost
        // grows with the square of the rows, and was 159 s at 15,000.
        print("complete with \(rows) rows: \(Int(took * 1000)) ms")
        XCTAssertLessThan(took, 5)
        XCTAssertEqual(try rowCount(), rows)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []
    func record(_ error: any Error) { lock.withLock { errors.append(error) } }
    var first: (any Error)? { lock.withLock { errors.first } }
}
