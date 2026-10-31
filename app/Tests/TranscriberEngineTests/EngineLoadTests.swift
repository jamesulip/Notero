import Synchronization
import XCTest
import WhisperKit
@testable import TranscriberEngine

/// Loading a model takes seconds to minutes and the engine is re-entered at
/// every await, so two callers can ask for the same 1.6 GB model while the
/// first is still loading it. The launch warm-up and a Dock-drop import can.
final class EngineLoadTests: XCTestCase {

    /// Holds every load open until the test lets it finish.
    private actor Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var started: [String] = []
        private(set) var finished: [String] = []
        private(set) var running = 0
        private(set) var peakRunning = 0
        var failing: Set<String> = []
        /// How many of the next loads end in a CancellationError, as a load whose
        /// caller was cancelled does.
        private var cancellations = 0

        func setFailing(_ models: Set<String>) { failing = models }
        func cancelNextLoads(_ count: Int) { cancellations = count }

        func enter(_ model: String) async throws {
            started.append(model)
            running += 1
            peakRunning = max(peakRunning, running)
            if !open { await withCheckedContinuation { waiters.append($0) } }
            running -= 1
            finished.append(model)
            if cancellations > 0 {
                cancellations -= 1
                throw CancellationError()
            }
            if failing.contains(model) { throw EngineError.backendUnavailable("no \(model)") }
        }

        func release() {
            open = true
            let parked = waiters
            waiters = []
            for waiter in parked { waiter.resume() }
        }

        func close() { open = false }
    }

    private func engine(_ gate: Gate) -> WhisperEngine {
        WhisperEngine(modelsDirectory: FileManager.default.temporaryDirectory) { model, _, _ in
            try await gate.enter(model)
            // A real WhisperKit, built without weights: `load: false` and
            // `download: false` touch neither the disk nor the network.
            return try await WhisperKit(WhisperKitConfig(verbose: false, load: false, download: false))
        }
    }

    /// Lets a call get as far as parking behind the load in progress. Bounded:
    /// on code that does not park it, the test still ends, and fails.
    private func park(_ engine: WhisperEngine, waiters: Int) async {
        for _ in 0..<2_000 {
            if await engine.waitingLoads >= waiters { return }
            await Task.yield()
        }
    }

    private func waitUntilStarted(_ gate: Gate, _ count: Int) async {
        for _ in 0..<2_000 {
            if await gate.started.count >= count { return }
            await Task.yield()
        }
    }

    func testTwoCallsForTheSameModelShareOneLoad() async throws {
        let gate = Gate()
        let engine = engine(gate)
        let readyReports = Mutex<[String]>([])

        async let first: Void = engine.load(model: "m", progress: nil)
        await waitUntilStarted(gate, 1)
        async let second: Void = engine.load(model: "m") { message, _ in
            readyReports.withLock { $0.append(message) }
        }
        await park(engine, waiters: 1)
        await gate.release()
        try await first
        try await second

        let started = await gate.started
        XCTAssertEqual(started, ["m"], "the second call started a second load of the same model")
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "m")
        XCTAssertEqual(readyReports.withLock { $0 }, ["Ready"],
                       "a caller that waited still hears that the model is ready")
    }

    func testACallForAnotherModelWaitsItsTurnAndWins() async throws {
        let gate = Gate()
        let engine = engine(gate)

        async let first: Void = engine.load(model: "a", progress: nil)
        await waitUntilStarted(gate, 1)
        async let second: Void = engine.load(model: "b", progress: nil)
        await park(engine, waiters: 1)
        await gate.release()
        try await first
        try await second

        let (started, peak) = await (gate.started, gate.peakRunning)
        XCTAssertEqual(started, ["a", "b"])
        XCTAssertEqual(peak, 1, "two loads ran at once")
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "b", "the last model asked for is the one that is loaded")
    }

    func testAnAlreadyLoadedModelIsNotLoadedAgain() async throws {
        let gate = Gate()
        await gate.release()
        let engine = engine(gate)
        try await engine.load(model: "m", progress: nil)
        try await engine.load(model: "m", progress: nil)
        let started = await gate.started
        XCTAssertEqual(started, ["m"])
    }

    func testAFailedLoadFailsEveryCallerAndLeavesTheWorkingModelInPlace() async throws {
        let gate = Gate()
        let engine = engine(gate)
        await gate.release()
        try await engine.load(model: "good", progress: nil)

        await gate.close()
        await gate.setFailing(["bad"])
        async let first: Void = engine.load(model: "bad", progress: nil)
        await waitUntilStarted(gate, 2)
        async let second: Void = engine.load(model: "bad", progress: nil)
        await park(engine, waiters: 1)
        await gate.release()

        var failures = 0
        do { try await first } catch { failures += 1 }
        do { try await second } catch { failures += 1 }
        XCTAssertEqual(failures, 2)
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "good")

        // And the next attempt is a fresh one, not a replay of the failure.
        await gate.setFailing([])
        try await engine.load(model: "bad", progress: nil)
        let nowLoaded = await engine.loadedModel
        XCTAssertEqual(nowLoaded, "bad")
    }

    // MARK: - Cancellation and release while a load is in flight

    /// What a caller saw, written from the task that made the call.
    private actor Outcome {
        enum Result { case done, cancelled, failed(String) }
        private(set) var result: Result?
        func set(_ result: Result) { self.result = result }
    }

    private func call(_ engine: WhisperEngine, model: String, into outcome: Outcome) -> Task<Void, Never> {
        Task {
            do {
                try await engine.load(model: model, progress: nil)
                await outcome.set(.done)
            } catch is CancellationError {
                await outcome.set(.cancelled)
            } catch {
                await outcome.set(.failed("\(error)"))
            }
        }
    }

    private func eventually(_ what: String, timeout: Double = 2,
                            _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { XCTFail("timed out waiting for \(what)"); return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// N2. A job parked behind a load is cancelled when a recording steps it
    /// aside, and `setLiveActive` waits for the job to end. A waiter that stayed
    /// parked until the load finished held the Record button for as long as the
    /// load took, which for a first compile is minutes.
    func testACancelledWaiterLeavesWithoutWaitingForTheLoad() async throws {
        let gate = Gate()
        let engine = engine(gate)

        let owner = Outcome()
        let ownerTask = call(engine, model: "m", into: owner)
        await waitUntilStarted(gate, 1)
        let waiter = Outcome()
        let waiterTask = call(engine, model: "m", into: waiter)
        await park(engine, waiters: 1)
        let parked = await engine.waitingLoads
        XCTAssertEqual(parked, 1, "the second call never parked behind the load")

        waiterTask.cancel()
        let left = await eventually("the cancelled waiter to leave") { await waiter.result != nil }
        let finishedWhileWaiting = await gate.finished
        XCTAssertEqual(finishedWhileWaiting, [], "the load ended first, so this proves nothing")
        if left, case .cancelled? = await waiter.result {} else if left {
            XCTFail("a cancelled waiter should end as cancelled, not \(String(describing: await waiter.result))")
        }
        let stillParked = await engine.waitingLoads
        XCTAssertEqual(stillParked, 0)

        // The load itself was not touched: it finishes and the engine has the model.
        await gate.release()
        await ownerTask.value
        await waiterTask.value
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "m")
        if case .done? = await owner.result {} else { XCTFail("the owner's load should have finished") }
    }

    /// N2, second half. The owner's CancellationError belongs to the owner. A
    /// waiter that was not cancelled took it as its own, so a job that merely
    /// shared a load with a cancelled one ended as cancelled.
    func testAWaiterThatWasNotCancelledLoadsForItselfWhenTheOwnerIsCancelled() async throws {
        let gate = Gate()
        let engine = engine(gate)
        await gate.cancelNextLoads(1)

        let owner = Outcome()
        let ownerTask = call(engine, model: "m", into: owner)
        await waitUntilStarted(gate, 1)
        let waiter = Outcome()
        let waiterTask = call(engine, model: "m", into: waiter)
        await park(engine, waiters: 1)
        await gate.release()
        await ownerTask.value
        await waiterTask.value

        if case .cancelled? = await owner.result {} else {
            XCTFail("the owner's load was meant to end cancelled: \(String(describing: await owner.result))")
        }
        if case .done? = await waiter.result {} else {
            XCTFail("a waiter that was not cancelled inherited the owner's cancellation: "
                    + "\(String(describing: await waiter.result))")
        }
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "m", "the waiter should have loaded the model itself")
        let started = await gate.started
        XCTAssertEqual(started, ["m", "m"])
    }

    /// A model that was released while a switch was loading stays released when
    /// the switch fails. The failure used to put the old model back, so "release
    /// the models" did nothing for the one that mattered, and removing a model
    /// whose files were just deleted brought it back in memory.
    func testAFailedSwitchDoesNotBringBackAModelThatWasReleasedMeanwhile() async throws {
        let gate = Gate()
        let engine = engine(gate)
        await gate.release()
        try await engine.load(model: "good", progress: nil)
        let before = await engine.loadedModel
        XCTAssertEqual(before, "good")

        await gate.close()
        await gate.setFailing(["bad"])
        let outcome = Outcome()
        let task = call(engine, model: "bad", into: outcome)
        await waitUntilStarted(gate, 2)
        await engine.unload()
        await gate.release()
        await task.value

        if case .failed? = await outcome.result {} else {
            XCTFail("the switch was meant to fail: \(String(describing: await outcome.result))")
        }
        let loaded = await engine.loadedModel
        XCTAssertNil(loaded, "a failed switch put back a model that was released while it loaded")
    }

    /// A caller that is already cancelled does not start a 1.6 GB load.
    func testACancelledCallerDoesNotStartALoad() async throws {
        let gate = Gate()
        await gate.release()
        let engine = engine(gate)

        let outcome = Outcome()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await engine.load(model: "m", progress: nil)
                await outcome.set(.done)
            } catch is CancellationError {
                await outcome.set(.cancelled)
            } catch {
                await outcome.set(.failed("\(error)"))
            }
        }
        await task.value

        let started = await gate.started
        XCTAssertEqual(started, [], "a cancelled caller started a load")
        if case .cancelled? = await outcome.result {} else {
            XCTFail("expected cancelled, got \(String(describing: await outcome.result))")
        }
    }

    // MARK: - A switch holds one model at a time

    private final class Weak: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [WeakRef] = []
        struct WeakRef { weak var kit: WhisperKit? }
        func add(_ kit: WhisperKit) { lock.withLock { items.append(WeakRef(kit: kit)) } }
        func alive(_ index: Int) -> Bool { lock.withLock { index < items.count && items[index].kit != nil } }
        var count: Int { lock.withLock { items.count } }
    }

    /// Releasing the model a switch replaces before the new one loads is what
    /// keeps the Neural Engine at one model's memory during the switch (2458 MB
    /// at the peak of Balanced to Fast when both were held, 1580 MB alone).
    func testTheReplacedModelIsReleasedBeforeTheNewOneLoads() async throws {
        let gate = Gate()
        await gate.release()
        let built = Weak()
        let firstAliveWhileSecondLoads = Mutex<Bool?>(nil)
        let engine = WhisperEngine(modelsDirectory: FileManager.default.temporaryDirectory) { model, _, _ in
            if model == "b" { firstAliveWhileSecondLoads.withLock { $0 = built.alive(0) } }
            try await gate.enter(model)
            let kit = try await WhisperKit(WhisperKitConfig(verbose: false, load: false, download: false))
            built.add(kit)
            return kit
        }
        try await engine.load(model: "a", progress: nil)
        XCTAssertEqual(built.count, 1)
        XCTAssertTrue(built.alive(0), "the first model should be loaded now")

        await gate.close()
        let outcome = Outcome()
        let task = call(engine, model: "b", into: outcome)
        await waitUntilStarted(gate, 2)
        let whileLoading = await engine.loadedModel
        XCTAssertNil(whileLoading, "nothing is loaded while a switch loads, and the engine should say so")
        await gate.release()
        await task.value

        let alive = firstAliveWhileSecondLoads.withLock { $0 }
        XCTAssertEqual(alive, false, "the model being replaced was still resident while the new one loaded")
        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "b")
    }

    /// The cost of that: a failed switch loads the old model again, once.
    func testAFailedSwitchLoadsTheOldModelAgain() async throws {
        let gate = Gate()
        await gate.release()
        let engine = engine(gate)
        try await engine.load(model: "good", progress: nil)

        await gate.setFailing(["bad"])
        do { try await engine.load(model: "bad", progress: nil); XCTFail("the switch was meant to fail") }
        catch {}

        let loaded = await engine.loadedModel
        XCTAssertEqual(loaded, "good", "a failed switch left no model")
        let started = await gate.started
        XCTAssertEqual(started, ["good", "bad", "good"])
    }
}
