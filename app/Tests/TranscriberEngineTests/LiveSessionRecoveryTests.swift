import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A live session that failed must be usable again (audit F2).
///
/// `.failed` was set by a refused microphone, a model that would not load and
/// a capture that would not start, and nothing ever left it: `prepare` only ran
/// from `.idle` or `.ready`, and `start` then threw the old failure's text.
/// One denied prompt, fixed in System Settings a minute later, left every
/// recording in that app run failing with the first reason until a relaunch.
@MainActor
final class LiveSessionRecoveryTests: XCTestCase {

    /// A fresh directory, removed when the test ends. Made on demand: this
    /// class is main-actor isolated and XCTest's set-up hooks are not.
    private lazy var scratch: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-live-recovery-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()

    /// A session that captures only: no model, so no weights are needed.
    private func makeSession(input: @escaping @Sendable () -> ScriptedInput) -> LiveSession {
        let session = LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: scratch)
        session.decodeLive = false
        session.captureSource = .microphone
        session.requestMicrophoneAccess = { true }
        session.makeCapture = { source, uid in
            AudioCapture(source: source, microphoneUID: uid,
                         makeInput: { _, _ in input() })
        }
        return session
    }

    private func archive(_ name: String) -> URL { scratch.appendingPathComponent(name) }

    func testARecordingStartsAgainAfterTheMicrophoneWasRefused() async throws {
        let session = makeSession { ScriptedInput(sampleRate: 48_000) }
        session.requestMicrophoneAccess = { false }

        do {
            try await session.start(recordingId: UUID(), archiveFileName: "a.m4a",
                                    archiveURL: archive("a.m4a"))
            XCTFail("a refused microphone must not start a recording")
        } catch {}
        guard case .failed = session.state else { return XCTFail("\(session.state)") }

        // The user fixes it in System Settings and tries again.
        session.requestMicrophoneAccess = { true }
        try await session.start(recordingId: UUID(), archiveFileName: "b.m4a",
                                archiveURL: archive("b.m4a"))
        XCTAssertEqual(session.state, .recording)
        let result = await session.stop()
        XCTAssertNotNil(result)
    }

    func testARecordingStartsAgainAfterTheCaptureCouldNotStart() async throws {
        struct Unplugged: Error {}
        let broken = ScriptedInput(sampleRate: 48_000)
        broken.startError = Unplugged()
        let working = ScriptedInput(sampleRate: 48_000)
        let next = Next([broken, working])
        let session = makeSession { next.take() }

        do {
            try await session.start(recordingId: UUID(), archiveFileName: "a.m4a",
                                    archiveURL: archive("a.m4a"))
            XCTFail("a capture that cannot start must not start a recording")
        } catch {}
        guard case .failed = session.state else { return XCTFail("\(session.state)") }

        try await session.start(recordingId: UUID(), archiveFileName: "b.m4a",
                                archiveURL: archive("b.m4a"))
        XCTAssertEqual(session.state, .recording)
        let result = await session.stop()
        XCTAssertNotNil(result)
    }

    func testAFailedStartLeavesNothingBehindForTheNextOne() async throws {
        // The failed attempt's archive must not survive as an empty file that
        // reads as a recording, and its id must not stay the live one.
        struct Unplugged: Error {}
        let broken = ScriptedInput(sampleRate: 48_000)
        broken.startError = Unplugged()
        let session = makeSession { broken }
        let url = archive("failed.m4a")
        do {
            try await session.start(recordingId: UUID(), archiveFileName: "failed.m4a",
                                    archiveURL: url)
            XCTFail("expected a failure")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(session.recordingId)
    }
}

/// Hands out scripted inputs in order, one per capture that is built.
private final class Next: @unchecked Sendable {
    private let lock = NSLock()
    private var inputs: [ScriptedInput]
    init(_ inputs: [ScriptedInput]) { self.inputs = inputs }
    func take() -> ScriptedInput {
        lock.withLock { inputs.count > 1 ? inputs.removeFirst() : inputs[0] }
    }
}
