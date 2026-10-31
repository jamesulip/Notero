import XCTest
@testable import TranscriberStore

/// A quit under a recording must stop the recording first: an AAC archive that
/// was never closed does not open (finding 16).
@MainActor
final class QuitGateTests: XCTestCase {

    /// A stop that a test finishes by hand.
    @MainActor private final class Stopper {
        var calls = 0
        var recording = true
        private var continuation: CheckedContinuation<Void, Never>?

        func stop() async {
            calls += 1
            await withCheckedContinuation { continuation = $0 }
            recording = false
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testQuitsAtOnceWhenNothingIsRecording() async {
        let stopper = Stopper()
        stopper.recording = false
        let gate = QuitGate(isRecording: { stopper.recording }, stop: { await stopper.stop() })

        var replies = 0
        let decision = gate.requestQuit { replies += 1 }

        XCTAssertEqual(decision, .quitNow)
        XCTAssertEqual(stopper.calls, 0, "nothing to stop")
        XCTAssertEqual(replies, 0, "the reply belongs to a wait")
    }

    func testAQuitDuringARecordingWaitsForTheStop() async {
        let stopper = Stopper()
        let gate = QuitGate(isRecording: { stopper.recording }, stop: { await stopper.stop() })

        var replies = 0
        let decision = gate.requestQuit { replies += 1 }
        await settle()

        XCTAssertEqual(decision, .wait)
        XCTAssertEqual(stopper.calls, 1)
        XCTAssertEqual(replies, 0, "the app must not quit while the files are still open")

        stopper.release()
        await settle()

        XCTAssertEqual(replies, 1, "the quit is released once the stop returned")
    }

    func testASecondQuitDuringTheStopJoinsItAndDoesNotStopTwice() async {
        let stopper = Stopper()
        let gate = QuitGate(isRecording: { stopper.recording }, stop: { await stopper.stop() })

        var replies = 0
        XCTAssertEqual(gate.requestQuit { replies += 1 }, .wait)
        await settle()
        XCTAssertEqual(gate.requestQuit { replies += 1 }, .wait)
        await settle()
        XCTAssertEqual(stopper.calls, 1)

        stopper.release()
        await settle()

        XCTAssertEqual(replies, 2, "each waiting request is answered exactly once")
    }

    func testAStopThatNeverReturnsDoesNotKeepTheAppOpenForever() async throws {
        let stopper = Stopper()
        let gate = QuitGate(timeout: .milliseconds(50),
                            isRecording: { stopper.recording }, stop: { await stopper.stop() })

        var replies = 0
        XCTAssertEqual(gate.requestQuit { replies += 1 }, .wait)
        XCTAssertEqual(replies, 0)

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(replies, 1, "after the timeout the quit goes ahead")
        // A late finish of the stop must not answer a second time.
        stopper.release()
        await settle()
        XCTAssertEqual(replies, 1)
    }
}
