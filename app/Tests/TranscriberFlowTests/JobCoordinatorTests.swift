import Foundation
import SwiftData
import XCTest
import TranscriberCore
import TranscriberEngine
import TranscriberStore
@testable import TranscriberFlow

/// The reduction from queue events to the store and to what the views read,
/// driven with events and checked against a real in-memory store.
@MainActor
final class JobCoordinatorTests: XCTestCase {

    private var container: ModelContainer!
    private var writer: TranscriptWriter!
    private var clock: Date!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
        writer = TranscriptWriter(modelContainer: container)
        clock = Date(timeIntervalSinceReferenceDate: 1_000)
    }

    override func tearDown() async throws {
        writer = nil
        container = nil
        try await super.tearDown()
    }

    private func makeCoordinator() -> JobCoordinator {
        let queue = TranscriptionQueue(engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")))
        let clockBox = ClockBox(self.clock)
        self.clockBox = clockBox
        return JobCoordinator(queue: queue, writer: writer) { clockBox.now }
    }

    private final class ClockBox: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
    private var clockBox: ClockBox!

    private func advance(_ seconds: TimeInterval) {
        clockBox.now = clockBox.now.addingTimeInterval(seconds)
    }

    private func recording() throws -> StoredRecording {
        try RecordingStore.create(kind: .recording, title: "Job", in: container.mainContext)
    }

    private func fresh(_ id: UUID) throws -> StoredRecording? {
        try ModelContext(container).fetch(FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private func job(_ id: UUID) -> TranscriptionJob {
        TranscriptionJob(id: id, title: "Job", sourceURL: nil,
                         cacheURL: URL(fileURLWithPath: "/tmp/x.wav"),
                         modelId: "model", language: "tl")
    }

    func testEnqueueShowsTheQueueAtOnceAndClearsTheOldWarning() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        await coordinator.addWarning("old", for: id)
        XCTAssertEqual(coordinator.warning(for: id), "old")

        coordinator.enqueue(job(id))
        XCTAssertEqual(coordinator.progress(for: id)?.status, .pending)
        XCTAssertTrue(coordinator.isBusy(id))
        XCTAssertNil(coordinator.warning(for: id))
    }

    /// The hook the automatic draft hangs on. It fires after the job's own
    /// bookkeeping, so a handler that asks `isBusy` is told the truth.
    func testFinishedCallsBackOnceTheJobIsNoLongerBusy() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        let seen = Box()
        coordinator.onFinished = { finished in seen.record(finished, busy: coordinator.isBusy(finished)) }

        coordinator.enqueue(job(id))
        XCTAssertTrue(coordinator.isBusy(id))
        XCTAssertTrue(seen.ids.isEmpty, "nothing yet")

        await coordinator.handle(.finished(id: id))
        XCTAssertEqual(seen.ids, [id])
        XCTAssertEqual(seen.busyWhenCalled, [false])
        XCTAssertFalse(coordinator.isBusy(id))
    }

    @MainActor
    final class Box {
        var ids: [UUID] = []
        var busyWhenCalled: [Bool] = []
        func record(_ id: UUID, busy: Bool) {
            ids.append(id)
            busyWhenCalled.append(busy)
        }
    }

    func testStageWritesTheStatusOnceAndTheFractionNever() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        await coordinator.handle(.queued(id: id, title: "Job"))
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0))
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0.4))

        XCTAssertEqual(coordinator.progress(for: id)?.fraction, 0.4)
        let row = try XCTUnwrap(try fresh(id))
        XCTAssertEqual(row.status, .transcribing)
        XCTAssertEqual(row.progress, 0, "only the stage change reaches the store")
    }

    func testPartialRowsThenTheFinalTranscriptReachTheStore() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        coordinator.enqueue(job(id))
        await coordinator.handle(.queued(id: id, title: "Job"))
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0))
        await coordinator.handle(.partial(id: id, segments: [
            Segment(index: 0, startMs: 0, endMs: 900, text: "una"),
            Segment(index: 1, startMs: 1_000, endMs: 1_900, text: "dalawa"),
        ], coveredMs: 2_000))

        XCTAssertEqual(coordinator.tick(for: id), 1)
        XCTAssertEqual(coordinator.progress(for: id)?.coveredMs, 2_000)
        var row = try XCTUnwrap(try fresh(id))
        XCTAssertEqual(row.transcript?.orderedSegments.map(\.text), ["una", "dalawa"])
        XCTAssertEqual(row.transcript?.isComplete, false)

        let payload = TranscriptionPayload(
            segments: [Segment(index: 0, startMs: 0, endMs: 1_900, text: "una dalawa", speakerId: "S1")],
            roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 1_900)],
            durationMs: 2_000, processMs: 50, modelId: "model", language: "tl",
            didDiarize: true, waveform: [0.5], metrics: TranscriptionMetrics()
        )
        await coordinator.handle(.transcribed(id: id, payload: payload))
        await coordinator.handle(.stage(id: id, status: .completed, progress: 1))
        await coordinator.handle(.finished(id: id))

        XCTAssertEqual(coordinator.tick(for: id), 2)
        XCTAssertNil(coordinator.progress(for: id), "finished clears the progress")
        XCTAssertFalse(coordinator.isBusy(id))
        row = try XCTUnwrap(try fresh(id))
        XCTAssertEqual(row.transcript?.orderedSegments.map(\.text), ["una dalawa"])
        XCTAssertEqual(row.transcript?.isComplete, true)
        XCTAssertEqual(row.transcript?.revision, 1, "the partial revision was completed, not replaced")
        XCTAssertEqual(row.speakers?.count, 1)
        XCTAssertEqual(row.durationMs, 2_000)
        XCTAssertEqual(row.status, .completed)
    }

    func testWarningsAccumulateWithoutRepeatsAndPersist() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        await coordinator.handle(.warning(id: id, message: "A window was dropped."))
        await coordinator.handle(.warning(id: id, message: "A window was dropped."))
        await coordinator.handle(.warning(id: id, message: "The microphone changed."))
        await coordinator.addWarning("Live decoding failed.", for: id)

        let expected = "A window was dropped. The microphone changed. Live decoding failed."
        XCTAssertEqual(coordinator.warning(for: id), expected)
        XCTAssertEqual(try fresh(id)?.warningMessage, expected)
    }

    func testFailureWritesTheMessageToTheRow() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        await coordinator.handle(.failed(id: id, message: "no audio"))
        let row = try XCTUnwrap(try fresh(id))
        XCTAssertEqual(row.status, .failed)
        XCTAssertEqual(row.errorMessage, "no audio")
    }

    func testTimeRemainingWaitsForFivePercentThenSmooths() async throws {
        let coordinator = makeCoordinator()
        let id = try recording().id
        await coordinator.handle(.queued(id: id, title: "Job"))
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0))
        XCTAssertNil(coordinator.progress(for: id)?.remaining, "the stage has only just begun")

        advance(10)
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0.5))
        XCTAssertEqual(coordinator.progress(for: id)?.remaining ?? -1, 10, accuracy: 0.01,
                       "half in ten seconds means ten more")

        advance(10)
        await coordinator.handle(.stage(id: id, status: .transcribing, progress: 0.75))
        // Raw: 20 s for 75 % leaves 6.67 s. Smoothed 70/30 against the 10 s.
        XCTAssertEqual(coordinator.progress(for: id)?.remaining ?? -1, 9.0, accuracy: 0.01)

        // A new stage starts its own clock.
        await coordinator.handle(.stage(id: id, status: .diarizing, progress: 0))
        XCTAssertNil(coordinator.progress(for: id)?.remaining)
    }

    func testARedoneTurnBumpsTheTickAndReplacesRows() async throws {
        let coordinator = makeCoordinator()
        let rec = try recording()
        let id = rec.id
        _ = try await writer.storeTranscript(
            segments: [Segment(index: 0, startMs: 0, endMs: 900, text: "a"),
                       Segment(index: 1, startMs: 5_000, endMs: 5_900, text: "bad"),
                       Segment(index: 2, startMs: 9_000, endMs: 9_900, text: "c")],
            roster: [], modelId: "m", language: "tl", processMs: 1, didDiarize: false, for: id
        )
        await coordinator.handle(.rangeTranscribed(
            id: id, fromMs: 5_000, toMs: 6_000,
            segments: [Segment(index: 0, startMs: 5_100, endMs: 5_800, text: "good")],
            modelId: "accurate"
        ))
        XCTAssertEqual(coordinator.tick(for: id), 1)
        XCTAssertEqual(try fresh(id)?.transcript?.orderedSegments.map(\.text), ["a", "good", "c"])
    }
}
