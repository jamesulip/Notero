import Foundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// Gain plumbing on `LiveSession`, without a microphone.
///
/// The regression these pin cost a segfault on launch. `LiveSession` is
/// `@Observable`, so the macro rewrites stored properties into computed ones
/// backed by a private store. A `didSet` that clamps by re-assigning the
/// property therefore re-enters the macro-generated setter, which fires `didSet`
/// again, and the recursion runs until the stack guard page is hit --
/// EXC_BAD_ACCESS before the first window is drawn, not a wrong value.
///
/// A test that merely reads the property back is enough to catch it: the
/// recursive version cannot return at all.
@MainActor
final class InputGainSessionTests: XCTestCase {

    private func makeSession() -> LiveSession {
        // Neither models nor microphone are touched until `prepare`/`start`.
        LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: FileManager.default.temporaryDirectory
        )
    }

    func testDefaultsToUnity() {
        XCTAssertEqual(makeSession().inputGainDb, InputGain.defaultDb)
    }

    /// Assigning must terminate and round-trip. Recursion fails this by crashing.
    func testAssignmentReturnsAndRoundTrips() {
        let session = makeSession()
        session.inputGainDb = 12
        XCTAssertEqual(session.inputGainDb, 12)
    }

    func testRepeatedAssignmentIsStable() {
        let session = makeSession()
        for db in stride(from: Float(-12), through: 30, by: 1) {
            session.inputGainDb = db
            XCTAssertEqual(session.inputGainDb, db)
        }
    }

    func testOutOfRangeGainIsClamped() {
        let session = makeSession()
        session.inputGainDb = 500
        XCTAssertEqual(session.inputGainDb, InputGain.maxDb)
        session.inputGainDb = -500
        XCTAssertEqual(session.inputGainDb, InputGain.minDb)
    }

    /// The capture object applies gain per buffer, so the value set before a
    /// session starts has to survive to the tap rather than being reset to 0 dB.
    func testCaptureCarriesTheGain() throws {
        let capture = try XCTUnwrap(AudioCapture())
        capture.gainDb = 18
        XCTAssertEqual(capture.gainDb, 18, accuracy: 0.01)
        capture.gainDb = 0
        XCTAssertEqual(capture.gainDb, 0, accuracy: 0.01)
    }
}
