import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// Scheduling in the queue, with no models: a stand-in for the pipeline that a
/// test controls decides how long each run lasts.
final class TranscriptionQueueSchedulingTests: XCTestCase {

    /// The pipeline, as the test needs it. A run loops until it is cancelled,
    /// then waits for the test to let it unwind, as a Core ML call does.
    private final class FakePipeline: @unchecked Sendable {
        private let lock = NSLock()
        private var _runs: [String] = []          // model id of each run, in order
        private var _sawCancel = 0
        private var _hold = false
        private var _finishOnStart = false

        var runs: [String] { lock.withLock { _runs } }
        var sawCancel: Int { lock.withLock { _sawCancel } }
        /// Cancelled runs wait here until released.
        var holdUnwind: Bool {
            get { lock.withLock { _hold } }
            set { lock.withLock { _hold = newValue } }
        }
        /// Runs complete at once instead of waiting to be cancelled.
        var finishOnStart: Bool {
            get { lock.withLock { _finishOnStart } }
            set { lock.withLock { _finishOnStart = newValue } }
        }

        func run(_ job: TranscriptionJob, emit: @Sendable (JobEvent) -> Void) async -> JobEnd {
            lock.withLock { _runs.append(job.modelId) }
            emit(.stage(id: job.id, status: .transcribing, progress: 0.1))
            if finishOnStart {
                emit(.stage(id: job.id, status: .completed, progress: 1))
                return .finished
            }
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            lock.withLock { _sawCancel += 1 }
            while holdUnwind { try? await Task.sleep(for: .milliseconds(5)) }
            return .cancelled
        }
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    private struct Rig {
        let queue: TranscriptionQueue
        let pipeline: FakePipeline
        let log: Log
        let reader: Task<Void, Never>
    }

    private func rig() -> Rig {
        let pipeline = FakePipeline()
        let queue = TranscriptionQueue(
            engines: EngineHost(modelsDirectory: FileManager.default.temporaryDirectory),
            archiveProbe: nil,
            runner: { job, emit in await pipeline.run(job, emit: emit) })
        let log = Log()
        let reader = Task {
            for await event in queue.events {
                switch event {
                case .queued(_, let title): log.add("queued:\(title)")
                case .stage(_, let status, _) where status != .transcribing:
                    log.add("stage:\(status.rawValue)")
                case .finished: log.add("finished")
                default: break
                }
            }
        }
        return Rig(queue: queue, pipeline: pipeline, log: log, reader: reader)
    }

    private func job(_ title: String, id: UUID = UUID(), model: String? = nil) -> TranscriptionJob {
        TranscriptionJob(id: id, title: title, sourceURL: nil,
                         cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(title).wav"),
                         modelId: model ?? title, language: "tl", discardCacheWhenDone: false)
    }

    private func eventually(_ what: String, timeout: Double = 3,
                            _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - A recording starts while a job runs

    func testARunningJobStepsAsideForARecordingAndStartsOverAfterIt() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        await rig.queue.enqueue(job("A"))
        try await eventually("A to start") { rig.pipeline.runs == ["A"] }

        await rig.queue.setLiveActive(true)

        // The call returns when the job has stopped, so the recording can load
        // its own model without the job decoding on it.
        let busy = await rig.queue.isBusy
        XCTAssertFalse(busy, "the recording must not start while the job still decodes")
        XCTAssertEqual(rig.pipeline.sawCancel, 1)
        try await eventually("the requeue") { rig.log.all.filter { $0 == "queued:A" }.count == 2 }
        XCTAssertFalse(rig.log.all.contains("stage:cancelled"),
                       "the user cancelled nothing: \(rig.log.all)")
        XCTAssertFalse(rig.log.all.contains("finished"), "the job is not over: \(rig.log.all)")
        XCTAssertEqual(rig.pipeline.runs, ["A"], "nothing runs during the recording")

        rig.pipeline.finishOnStart = true
        await rig.queue.setLiveActive(false)
        try await eventually("the second run") { rig.pipeline.runs == ["A", "A"] }
        try await eventually("the end") { rig.log.all.last == "finished" }
        XCTAssertEqual(rig.log.all.filter { $0 == "finished" }.count, 1)
    }

    func testAJobQueuedDuringARecordingWaitsForIt() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        rig.pipeline.finishOnStart = true
        await rig.queue.setLiveActive(true)
        await rig.queue.enqueue(job("B"))

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(rig.pipeline.runs, [], "no background decode while recording")

        await rig.queue.setLiveActive(false)
        try await eventually("B to run") { rig.pipeline.runs == ["B"] }
    }

    func testCancellingAJobThatWaitsForARecordingEndsItForGood() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        let a = job("A")
        await rig.queue.enqueue(a)
        try await eventually("A to start") { rig.pipeline.runs == ["A"] }
        await rig.queue.setLiveActive(true)

        await rig.queue.cancel(a.id)

        try await eventually("the end") { rig.log.all.last == "finished" }
        XCTAssertTrue(rig.log.all.contains("stage:cancelled"))
        rig.pipeline.finishOnStart = true
        await rig.queue.setLiveActive(false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(rig.pipeline.runs, ["A"], "a cancelled job must not start again")
    }

    func testACancelWhileTheJobSteppingAsideUnwindsWinsOverTheRequeue() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        let a = job("A")
        await rig.queue.enqueue(a)
        try await eventually("A to start") { rig.pipeline.runs == ["A"] }
        rig.pipeline.holdUnwind = true

        let live = Task { await rig.queue.setLiveActive(true) }
        try await eventually("the run to see its cancel") { rig.pipeline.sawCancel == 1 }
        await rig.queue.cancel(a.id)
        rig.pipeline.holdUnwind = false
        await live.value

        try await eventually("the end") { rig.log.all.last == "finished" }
        XCTAssertEqual(rig.log.all.filter { $0 == "queued:A" }.count, 1,
                       "the cancelled job was queued again: \(rig.log.all)")
    }

    // MARK: - A request while a cancelled run unwinds

    func testARequestWhileACancelledRunUnwindsIsNotDropped() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        let id = UUID()
        await rig.queue.enqueue(job("first", id: id))
        try await eventually("the first run") { rig.pipeline.runs == ["first"] }
        rig.pipeline.holdUnwind = true

        await rig.queue.cancel(id)
        try await eventually("the cancel to be seen") { rig.pipeline.sawCancel == 1 }
        // The user asks again while the first run is still coming down.
        await rig.queue.enqueue(job("second", id: id))
        rig.pipeline.finishOnStart = true
        rig.pipeline.holdUnwind = false

        try await eventually("the second run") { rig.pipeline.runs == ["first", "second"] }
        try await eventually("the end") { rig.log.all.filter { $0 == "finished" }.count == 2 }

        let log = rig.log.all
        let firstFinished = try XCTUnwrap(log.firstIndex(of: "finished"))
        let secondQueued = try XCTUnwrap(log.firstIndex(of: "queued:second"))
        XCTAssertLessThan(firstFinished, secondQueued,
                          "the old run's `.finished` must not land after the new request set its row up: \(log)")
    }

    func testARepeatedRequestForARunningJobIsStillIgnored() async throws {
        let rig = rig()
        defer { rig.reader.cancel() }
        let id = UUID()
        await rig.queue.enqueue(job("first", id: id))
        try await eventually("the first run") { rig.pipeline.runs == ["first"] }

        await rig.queue.enqueue(job("again", id: id))   // not cancelled: a double click

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(rig.pipeline.runs, ["first"])
        XCTAssertEqual(rig.log.all.filter { $0.hasPrefix("queued") }, ["queued:first"])
        await rig.queue.cancel(id)
    }
}
