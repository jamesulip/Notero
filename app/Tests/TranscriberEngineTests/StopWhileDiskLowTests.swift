import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// Stop after the disk ran low under a recording (finding 33): the whole path
/// from a live session to the result `AppState` saves, with the archive's disk
/// failing partway through.
@MainActor
final class StopWhileDiskLowTests: XCTestCase {

    private final class Disk: @unchecked Sendable {
        private let lock = NSLock()
        private var _free: Int64 = 50_000_000_000
        var free: Int64 {
            get { lock.withLock { _free } }
            set { lock.withLock { _free = newValue } }
        }
        var probe: DiskSpace { DiskSpace { [self] _ in free } }
    }

    func testStopAfterTheArchiveStoppedOnALowDiskKeepsTheRecordingWhole() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-stop-disk-low-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        let rate = 48_000.0
        let input = ScriptedInput(sampleRate: rate)
        let disk = Disk()
        let archiveURL = scratch.appendingPathComponent("low.m4a")
        let session = LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: scratch)
        session.decodeLive = false
        session.captureSource = .microphone
        session.requestMicrophoneAccess = { true }
        session.makeCapture = { source, uid in
            AudioCapture(source: source, microphoneUID: uid, makeInput: { _, _ in input },
                         makeArchive: { url, rate, lanes in
                             try ArchiveWriter(url: url, sampleRate: rate, lanes: lanes, disk: disk.probe)
                         })
        }
        try await session.start(recordingId: UUID(), archiveFileName: "low.m4a", archiveURL: archiveURL)

        // The disk runs low once the recording is under way. Twelve seconds of audio
        // go in; the archive's first look at the disk is due at five.
        disk.free = DiskSpace.reserveBytes - 1
        var sine = SineSource(rate: rate)
        for _ in 0..<141 { input.deliver([.room: sine.buffer(frames: 4_080)]) }     // 11.96 s
        let stopped = await session.stop()
        let result = try XCTUnwrap(stopped)

        // The recording is the length of the meeting: the working copy has all of it.
        XCTAssertEqual(Double(result.durationMs), 141 * 4_080 / rate * 1_000, accuracy: 150)
        XCTAssertTrue(result.notices.contains { if case .recordingNotSaved = $0 { true } else { false } },
                      "the person is told the audio stopped being saved: \(result.notices)")
        XCTAssertEqual(session.state, .ready)

        // The archive plays what was written before the disk ran low, and is shorter.
        guard case .playable(let archiveMs) = AudioArchive.status(of: archiveURL)
        else { return XCTFail("\(AudioArchive.status(of: archiveURL))") }
        XCTAssertLessThan(archiveMs, 6_000, "the archive stopped at the disk's first look")
        XCTAssertGreaterThan(archiveMs, 3_000)

        // So the working copy must be kept, whatever the setting says about it:
        // the archive cannot rebuild what it never held.
        let discard = await WorkingCopyPolicy.canDiscard(workingCopy: result.cacheURL, archive: archiveURL)
        XCTAssertFalse(discard, "a working copy that holds more than the archive is the only copy of the rest")
    }
}
