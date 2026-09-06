import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The pipeline over a scripted backend: what it does with the two
/// recoverable errors, the one that is not, cancellation and progress.
final class NotesPipelineTests: XCTestCase {

    /// Answers by part index, and records what it was asked.
    actor ScriptedEngine: NotesGenerating {
        nonisolated let modelId = "fake"
        var availabilityValue: NotesAvailability = .available
        /// Part index -> error to throw the first `n` times it is asked.
        var failures: [Int: (error: NotesError, times: Int)] = [:]
        /// Every chunk the engine was handed, in order.
        var asked: [NotesChunk] = []
        var summaryCalls: [[String]] = []
        var summaryTooLongAbove = Int.max

        func set(availability: NotesAvailability) { availabilityValue = availability }
        func fail(part: Int, with error: NotesError, times: Int = 1) { failures[part] = (error, times) }
        func setSummaryTooLongAbove(_ count: Int) { summaryTooLongAbove = count }

        func availability() async -> NotesAvailability { availabilityValue }

        func notes(for chunk: NotesChunk, style: NotesStyle) async throws -> ChunkNotes {
            asked.append(chunk)
            if let failure = failures[chunk.index], failure.times > 0 {
                failures[chunk.index] = (failure.error, failure.times - 1)
                throw failure.error
            }
            // One decision per part, pointing at the part's first line. The
            // text names the line, so two parts' decisions do not read as
            // one restated and get merged by the reducer.
            let first = chunk.lines[0]
            return ChunkNotes(summary: "Part \(chunk.index) from \(first.stamp).", items: [
                ChunkNotes.Item(kind: .decision, text: "Agreed on line\(chunk.startMs) of the taxonomy", at: first.stamp),
                ChunkNotes.Item(kind: .keyPoint, text: "Point with no stamp", at: nil),
            ])
        }

        func summary(partSummaries: [String], title: String, style: NotesStyle) async throws -> String {
            summaryCalls.append(partSummaries)
            if partSummaries.count > summaryTooLongAbove { throw NotesError.partTooLong }
            return "Summary of \(partSummaries.count) parts of \(title)."
        }
    }

    private func meeting(_ count: Int) -> [Segment] {
        (0..<count).map { i in
            Segment(index: i, startMs: i * 5_000, endMs: i * 5_000 + 4_000,
                    text: "Line \(i) tungkol sa product taxonomy at flowchart.",
                    speakerId: i % 2 == 0 ? "S1" : "S2")
        }
    }

    private let roster = [SpeakerLabel(id: "S1", displayName: "Juan"),
                          SpeakerLabel(id: "S2", displayName: "Maria")]

    func testReadsEveryPartResolvesLinksAndSummarizesOnce() async throws {
        let engine = ScriptedEngine()
        let progressBox = ProgressBox()
        let draft = try await NotesPipeline.generate(
            segments: meeting(40), speakers: roster, title: "Taxonomy", style: .english,
            using: engine, maxCharacters: 400
        ) { progressBox.append($0) }

        let asked = await engine.asked
        XCTAssertGreaterThan(asked.count, 2)
        XCTAssertEqual(draft.chunkCount, asked.count)
        XCTAssertEqual(draft.modelId, "fake")
        XCTAssertEqual(draft.style, .english)
        XCTAssertTrue(draft.warnings.isEmpty)

        // One decision per part with a link, and the unlinked key point kept
        // once: the parts all said "Point with no stamp".
        let decisions = draft.items(.decision)
        XCTAssertEqual(decisions.count, asked.count)
        XCTAssertEqual(decisions.map(\.sourceMs), asked.map(\.startMs))
        XCTAssertEqual(decisions.map(\.sourceSegmentId), asked.map { $0.lines[0].segmentId })
        XCTAssertEqual(draft.items(.keyPoint).count, 1)

        let summaries = await engine.summaryCalls
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].count, asked.count)
        XCTAssertEqual(draft.summary, "Summary of \(asked.count) parts of Taxonomy.")

        let seen = progressBox.values
        XCTAssertEqual(seen.first, NotesProgress(stage: .reading, chunksDone: 0, chunkCount: asked.count))
        XCTAssertEqual(seen.last?.stage, .summarizing)
        XCTAssertEqual(seen.filter { $0.stage == .reading }.count, asked.count)
    }

    func testOnePartUsesItsOwnSummaryWithNoSecondCall() async throws {
        let engine = ScriptedEngine()
        let draft = try await NotesPipeline.generate(
            segments: meeting(4), speakers: roster, title: "Short", style: .asSpoken, using: engine)
        XCTAssertEqual(draft.chunkCount, 1)
        XCTAssertEqual(draft.summary, "Part 0 from 0:00.")
        let calls = await engine.summaryCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testAPartThatIsTooLongIsHalvedAndBothHalvesRead() async throws {
        let engine = ScriptedEngine()
        await engine.fail(part: 0, with: .partTooLong)
        let draft = try await NotesPipeline.generate(
            segments: meeting(8), speakers: roster, title: "Long", style: .english, using: engine)

        let asked = await engine.asked
        XCTAssertEqual(asked.count, 3, "the whole part, then its two halves")
        XCTAssertEqual(asked[1].lines.count, 4)
        XCTAssertEqual(asked[2].lines.count, 4)
        XCTAssertEqual(asked[1].endMs, asked[2].startMs)
        XCTAssertEqual(draft.items(.decision).map(\.sourceMs), [0, 20_000])
        XCTAssertTrue(draft.warnings.isEmpty)
        XCTAssertEqual(draft.chunkCount, 1, "the halves are retries, not parts")
    }

    func testASingleLineThatIsTooLongIsSkippedWithAWarning() async throws {
        let engine = ScriptedEngine()
        await engine.fail(part: 0, with: .partTooLong, times: 10)
        let draft = try await NotesPipeline.generate(
            segments: meeting(1), speakers: roster, title: "One line", style: .english, using: engine)
        XCTAssertTrue(draft.items.isEmpty)
        XCTAssertEqual(draft.warnings.count, 1)
        XCTAssertTrue(draft.warnings[0].contains("too long"))
    }

    func testARefusedPartIsSkippedAndTheRestIsKept() async throws {
        let engine = ScriptedEngine()
        await engine.fail(part: 1, with: .contentRefused)
        let draft = try await NotesPipeline.generate(
            segments: meeting(40), speakers: roster, title: "Refused", style: .english,
            using: engine, maxCharacters: 400)
        XCTAssertEqual(draft.warnings.count, 1)
        XCTAssertTrue(draft.warnings[0].contains("refused part 2"))
        XCTAssertEqual(draft.items(.decision).count, draft.chunkCount - 1)
    }

    func testALanguageRefusalStopsTheDraft() async throws {
        let engine = ScriptedEngine()
        await engine.fail(part: 1, with: .languageNotSupported)
        do {
            _ = try await NotesPipeline.generate(
                segments: meeting(40), speakers: roster, title: "Tagalog", style: .english,
                using: engine, maxCharacters: 400)
            XCTFail("expected a throw")
        } catch let error as NotesError {
            XCTAssertEqual(error, .languageNotSupported)
        }
    }

    func testAnUnavailableModelThrowsBeforeAnyPartIsRead() async throws {
        let engine = ScriptedEngine()
        await engine.set(availability: .appleIntelligenceOff)
        do {
            _ = try await NotesPipeline.generate(
                segments: meeting(4), speakers: roster, title: "Off", style: .english, using: engine)
            XCTFail("expected a throw")
        } catch let error as NotesError {
            XCTAssertEqual(error, .unavailable(.appleIntelligenceOff))
        }
        let asked = await engine.asked
        XCTAssertTrue(asked.isEmpty)
    }

    func testAnEmptyTranscriptThrows() async throws {
        do {
            _ = try await NotesPipeline.generate(
                segments: [], speakers: [], title: "Empty", style: .english, using: ScriptedEngine())
            XCTFail("expected a throw")
        } catch let error as NotesError {
            XCTAssertEqual(error, .noTranscript)
        }
    }

    func testTooManySummariesAreFolded() async throws {
        let engine = ScriptedEngine()
        await engine.setSummaryTooLongAbove(3)
        let draft = try await NotesPipeline.generate(
            segments: meeting(60), speakers: roster, title: "Folded", style: .english,
            using: engine, maxCharacters: 400)
        let calls = await engine.summaryCalls
        XCTAssertGreaterThan(draft.chunkCount, 3)
        XCTAssertEqual(calls[0].count, draft.chunkCount, "the first call tries everything")
        XCTAssertEqual(calls.last?.count, 2, "the last call joins the two halves")
        XCTAssertEqual(draft.summary, "Summary of 2 parts of Folded.")
    }

    func testCancellationStopsBetweenParts() async throws {
        let engine = SlowEngine()
        let segments = meeting(40)
        let speakers = roster
        let task = Task {
            try await NotesPipeline.generate(
                segments: segments, speakers: speakers, title: "Slow", style: .english,
                using: engine, maxCharacters: 400)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }
    }

    /// Takes a while per part, so a cancel lands mid-way.
    actor SlowEngine: NotesGenerating {
        nonisolated let modelId = "slow"
        func availability() async -> NotesAvailability { .available }
        func notes(for chunk: NotesChunk, style: NotesStyle) async throws -> ChunkNotes {
            try await Task.sleep(for: .milliseconds(30))
            return ChunkNotes(summary: "s", items: [])
        }
        func summary(partSummaries: [String], title: String, style: NotesStyle) async throws -> String { "s" }
    }

    final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [NotesProgress] = []
        func append(_ value: NotesProgress) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [NotesProgress] { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
