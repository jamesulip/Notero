import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A batch of progressive rows costs about the same late in a long job as it
/// did at the start (finding 16).
@MainActor
final class TranscriptWriterAppendCostTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-append-\(UUID().uuidString)")
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

    private func segment(_ index: Int) -> Segment {
        Segment(index: index, startMs: index * 1_400, endMs: index * 1_400 + 1_300,
                text: "line \(index)")
    }

    private func seconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await body()
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    func testAppendingToALongTranscriptCostsAboutWhatAppendingToAnEmptyOneDoes() async throws {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let opened = try await writer.openPartialTranscript(modelId: "turbo", language: "tl", for: id)
        let open = try XCTUnwrap(opened)
        func batch(_ n: Int) -> [Segment] { (n * 250..<(n + 1) * 250).map { segment($0) } }

        let first = try await seconds { try await writer.appendPartial(batch(0), to: open) }
        for n in 1..<12 { try await writer.appendPartial(batch(n), to: open) }
        let late = try await seconds { try await writer.appendPartial(batch(12), to: open) }

        // With 3,000 rows saved, one batch took 2.3 s against 40 ms for the
        // first, because every row linked before it was inserted made SwiftData
        // rework the transcript's whole `segments` list.
        print("append: first batch \(Int(first * 1000)) ms, batch 13 \(Int(late * 1000)) ms")
        XCTAssertLessThan(late, max(0.5, first * 12),
                          "a batch late in a long job must not cost more than the first")
    }
}
