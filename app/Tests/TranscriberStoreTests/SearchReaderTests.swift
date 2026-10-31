import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A search runs off the main actor, on a context of its own (finding 16).
@MainActor
final class SearchReaderTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-reader-\(UUID().uuidString)")
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

    /// A recording with `rows` lines, every line containing the word "budget".
    @discardableResult
    private func seed(title: String, rows: Int, in context: ModelContext) throws -> StoredRecording {
        let recording = try RecordingStore.create(kind: .meeting, title: title, in: context)
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        context.insert(transcript)
        transcript.recording = recording
        for index in 0..<rows {
            let row = StoredSegment(index: index, startMs: index * 1_400, endMs: index * 1_400 + 1_300,
                                    text: "pag-usapan natin ang budget line \(index)")
            context.insert(row)
            row.transcript = transcript
        }
        try context.save()
        RecordingStore.reindex(recording)
        try context.save()
        return recording
    }

    func testTheReaderFindsWhatTheServiceFindsOnAnotherContext() async throws {
        let context = container.mainContext
        try seed(title: "Quarterly budget review", rows: 30, in: context)
        try seed(title: "Offsite", rows: 5, in: context)

        let direct = try SearchService.search("budget", in: ModelContext(container))
        let read = try await SearchReader(modelContainer: container).search("budget")

        XCTAssertFalse(read.isEmpty)
        XCTAssertEqual(read.map(\.id), direct.map(\.id))
        XCTAssertEqual(read.map(\.snippet), direct.map(\.snippet))
    }

    func testAFreshReaderSeesAnEditThatWasJustSaved() async throws {
        let context = container.mainContext
        let recording = try seed(title: "Weekly", rows: 3, in: context)
        _ = try await SearchReader(modelContainer: container).search("zebra")   // warms nothing it keeps

        recording.title = "Zebra planning"
        RecordingStore.reindex(recording)
        try context.save()

        let hits = try await SearchReader(modelContainer: container).search("zebra")
        XCTAssertTrue(hits.contains { $0.scope == .title })
    }

    /// The window has to keep moving while a long meeting is searched. A ticker
    /// on the main actor records the longest gap between its ticks.
    func testTheMainActorKeepsTickingWhileALongMeetingIsSearched() async throws {
        let context = container.mainContext
        for index in 0..<3 { try seed(title: "Long \(index)", rows: 6_000, in: context) }

        var longestGapMs = 0.0
        var running = true
        let ticker = Task { @MainActor in
            var last = ContinuousClock.now
            while running {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ContinuousClock.now
                let gap = now - last
                longestGapMs = max(longestGapMs,
                                   Double(gap.components.seconds) * 1000
                                   + Double(gap.components.attoseconds) / 1e15)
                last = now
            }
        }
        let started = ContinuousClock.now
        let hits = try await SearchReader(modelContainer: container).search("budget")
        let took = ContinuousClock.now - started
        running = false
        await ticker.value

        XCTAssertEqual(hits.count, 80, "the limit still applies")
        print("search of 6000-row meetings: \(took), longest main-actor gap \(Int(longestGapMs)) ms")
        XCTAssertLessThan(longestGapMs, 250, "the window must not stall for a search")
    }
}
