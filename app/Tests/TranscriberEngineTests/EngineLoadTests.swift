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

        func setFailing(_ models: Set<String>) { failing = models }

        func enter(_ model: String) async throws {
            started.append(model)
            running += 1
            peakRunning = max(peakRunning, running)
            if !open { await withCheckedContinuation { waiters.append($0) } }
            running -= 1
            finished.append(model)
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
}
