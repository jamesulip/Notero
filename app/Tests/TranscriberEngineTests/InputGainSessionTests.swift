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

    /// One value carries every setting the session reads. A caller cannot
    /// forget a field, which is how the launch warm-up once prepared a
    /// session with four of six.
    func testConfigureSetsEveryField() {
        let session = makeSession()
        let configuration = LiveConfiguration(
            session: SessionConfig(hopMs: 1_200, language: "en"),
            decodeLive: false, captureSource: .both, microphoneUID: "mic-42",
            inputGainDb: 9, isRoomMode: true
        )
        session.configure(configuration)
        XCTAssertEqual(session.config.hopMs, 1_200)
        XCTAssertEqual(session.config.language, "en")
        XCTAssertFalse(session.decodeLive)
        XCTAssertEqual(session.captureSource, .both)
        XCTAssertEqual(session.microphoneUID, "mic-42")
        XCTAssertEqual(session.inputGainDb, 9)
        XCTAssertTrue(session.isRoomMode)

        // The default value is the app's default too.
        session.configure(LiveConfiguration())
        XCTAssertTrue(session.decodeLive)
        XCTAssertEqual(session.captureSource, .default)
        XCTAssertNil(session.microphoneUID)
        XCTAssertEqual(session.inputGainDb, InputGain.defaultDb)
    }

    /// Pause is a flag the audio callback reads per buffer, like gain. A
    /// session that ends paused must not leave the next one paused.
    func testPauseRoundTripsAndClearsTheMeter() throws {
        let session = makeSession()
        XCTAssertFalse(session.isPaused)
        session.isPaused = true
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.level, 0)
        XCTAssertTrue(session.laneLevels.isEmpty)
        session.isPaused = false
        XCTAssertFalse(session.isPaused)

        let capture = try XCTUnwrap(AudioCapture())
        XCTAssertFalse(capture.isPaused)
        capture.isPaused = true
        XCTAssertTrue(capture.isPaused)
        capture.isMuted = true
        XCTAssertTrue(capture.isMuted, "mute and pause are separate switches")
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
