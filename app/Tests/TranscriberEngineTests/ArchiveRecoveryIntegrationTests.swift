import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The two halves of the recovery work meet here (audit F1).
///
/// The archive is written as movie fragments, so a recording that is killed
/// still opens (`ArchiveCrashTests`). The queue's rules about the 16 kHz working
/// copy (`WorkingCopyPolicy`) were written for an archive that does not open at
/// all. They must also hold for the archive that opens but stops short: the
/// last seconds before the kill are only in the working copy.
final class ArchiveRecoveryIntegrationTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func tone(seconds: Double, rate: Double = 48_000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            channel[index] = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / rate))
        }
        return buffer
    }

    /// What is on disk when the process dies with the writer still open: a
    /// copy of the file taken before any close, polled until the encoder has
    /// handed bytes to the file system.
    private func killedSnapshot(of url: URL) throws -> URL {
        let snapshot = scratch.appendingPathComponent("killed.m4a")
        let deadline = Date().addingTimeInterval(4)
        repeat {
            try? FileManager.default.removeItem(at: snapshot)
            try FileManager.default.copyItem(at: url, to: snapshot)
            if let file = try? AVAudioFile(forReading: snapshot), file.length > 0 { return snapshot }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail("the killed archive never opened")
        return snapshot
    }

    func testAKilledArchiveIsPlayableToTheQueueAndTheLongerWorkingCopyIsKept() async throws {
        let archive = scratch.appendingPathComponent("live.m4a")
        let writer = try ArchiveWriter(url: archive, sampleRate: 48_000, lanes: [.room])
        for _ in 0..<30 { writer.write([.room: try tone(seconds: 1)]) }
        writer.settle()
        let killed = try killedSnapshot(of: archive)

        // The working copy has all 40 s that were recorded; the archive, cut
        // short by the kill, has less.
        let copy = scratch.appendingPathComponent("copy.wav")
        let wav = try WavWriter(url: copy)
        wav.write(Data(count: 40 * Audio.sampleRate * Audio.bytesPerSample))
        wav.close()

        let queued = await ArchiveProbe.durationMs(of: killed)
        XCTAssertNotNil(queued, "the queue's reader must open an archive the recorder can")
        XCTAssertNotNil(ArchiveProbe.recordedDurationMs(of: killed),
                        "and so must the launch-time check")
        guard case .playable(let recorded) = AudioArchive.status(of: killed) else {
            return XCTFail("\(AudioArchive.status(of: killed))")
        }
        XCTAssertEqual(Double(recorded), Double(try XCTUnwrap(queued)), accuracy: 100,
                       "the two readers must agree on what the archive holds")

        let discard = await WorkingCopyPolicy.canDiscard(workingCopy: copy, archive: killed)
        XCTAssertFalse(discard, "the archive stops short of the working copy: keep the copy")
        writer.finish()
    }

    func testACleanlyClosedArchiveStillLetsTheWorkingCopyGo() async throws {
        let archive = scratch.appendingPathComponent("closed.m4a")
        let writer = try ArchiveWriter(url: archive, sampleRate: 48_000, lanes: [.room])
        for _ in 0..<20 { writer.write([.room: try tone(seconds: 1)]) }
        writer.finish()

        let copy = scratch.appendingPathComponent("copy.wav")
        let wav = try WavWriter(url: copy)
        wav.write(Data(count: 20 * Audio.sampleRate * Audio.bytesPerSample))
        wav.close()

        let discard = await WorkingCopyPolicy.canDiscard(workingCopy: copy, archive: archive)
        XCTAssertTrue(discard, "the archive holds everything: the copy is disposable, as before")
    }
}
