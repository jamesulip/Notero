import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// What an archive looks like when the process dies mid-recording
/// (finding 16, audit F1).
///
/// A killed process, a crash, a power cut and a force quit all leave the same
/// thing on disk: the bytes that were written before the end, and no close. A
/// file that is only readable after a close is lost in all four cases.
/// Measured with a real SIGKILL: an `AVAudioFile` m4a came back from `afinfo`
/// as `AudioFileOpenURL failed` and from `ffprobe` as `moov atom not found`,
/// with every second of the recording in the file and none of it readable.
///
/// A test cannot kill itself and then read the result, but it does not need to.
/// Copying the file while the writer is still open captures exactly the state a
/// kill at that instant leaves: the bytes already handed to the kernel, nothing
/// that is still in the writer's memory.
final class ArchiveCrashTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-archive-crash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// The state a kill leaves, as seconds of readable audio, or nil when the
    /// file cannot be opened at all. Polled, because the encoder hands the
    /// bytes to the file system a moment after the writer has accepted them.
    private func secondsAfterAKill(of url: URL, within timeout: TimeInterval = 4) -> Double? {
        let snapshot = scratch.appendingPathComponent("killed-\(UUID().uuidString).m4a")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            try? FileManager.default.removeItem(at: snapshot)
            try? FileManager.default.copyItem(at: url, to: snapshot)
            if let file = try? AVAudioFile(forReading: snapshot), file.length > 0 {
                return Double(file.length) / file.fileFormat.sampleRate
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return nil
    }

    private func tone(seconds: Double, rate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            channel[index] = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / rate))
        }
        return buffer
    }

    func testArchiveIsReadableWhileTheRecordingIsStillOpen() throws {
        let url = scratch.appendingPathComponent("live.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
        // Thirty seconds, one second at a time, as a recording delivers it.
        for _ in 0..<30 { writer.write([.room: tone(seconds: 1)]) }
        writer.settle()

        let seconds = try XCTUnwrap(
            secondsAfterAKill(of: url),
            "a recording that is killed with no close must still open; this one lost all 30 s")
        // Bounded loss: the tail of the recording that had not been flushed yet,
        // never the whole of it.
        XCTAssertGreaterThanOrEqual(seconds, 30 - 12)
        XCTAssertLessThanOrEqual(seconds, 30.2)
        writer.finish()
    }

    func testAKillOfATwoLaneRecordingKeepsBothChannels() throws {
        let url = scratch.appendingPathComponent("both.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room, .remote])
        let room = tone(seconds: 1)
        let remote = tone(seconds: 1)
        for _ in 0..<12 { writer.write([.room: room, .remote: remote]) }
        writer.settle()

        let snapshot = scratch.appendingPathComponent("both-killed.m4a")
        var channels = 0
        let deadline = Date().addingTimeInterval(4)
        repeat {
            try? FileManager.default.removeItem(at: snapshot)
            try? FileManager.default.copyItem(at: url, to: snapshot)
            channels = Int((try? AVAudioFile(forReading: snapshot))?.fileFormat.channelCount ?? 0)
            if channels > 0 { break }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTAssertEqual(channels, 2)
        writer.finish()
    }

    // MARK: - A clean close keeps every frame

    func testACleanCloseHoldsExactlyTheFramesThatWereWritten() throws {
        // The fragmented file must not trade accuracy for survivability: the
        // archive's length is what the transcript's clock is read against.
        for (rate, channels) in [(8_000.0, 1), (16_000.0, 1), (16_000.0, 2), (24_000.0, 1),
                                 (44_100.0, 1), (48_000.0, 1), (48_000.0, 2)] {
            let lanes: [CaptureLane] = channels == 1 ? [.room] : [.room, .remote]
            let url = scratch.appendingPathComponent("exact-\(Int(rate))-\(channels).m4a")
            let writer = try ArchiveWriter(url: url, sampleRate: rate, lanes: lanes)
            // Odd buffer sizes on purpose: nothing may depend on a buffer
            // dividing a fragment, or the AAC frame size, evenly.
            var written = 0
            for size in [1_021, 4_096, 3_749, 8_192, 777, 4_080, 12_345] where written < Int(rate * 12) {
                let source = tone(seconds: Double(size) / rate, rate: rate)
                var frames: [CaptureLane: AVAudioPCMBuffer] = [:]
                for lane in lanes { frames[lane] = source }
                writer.write(frames)
                written += Int(source.frameLength)
            }
            writer.finish()
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(Int(file.length), written, "\(Int(rate)) Hz, \(channels) ch")
            XCTAssertEqual(Int(writer.frameCount), written)
            XCTAssertNil(writer.failure)
        }
    }

    func testTheContentIsTheSignalThatWasWritten() throws {
        // Length alone would pass a file of silence. Read the tone back.
        let url = scratch.appendingPathComponent("content.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
        for _ in 0..<6 { writer.write([.room: tone(seconds: 1)]) }
        writer.finish()
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: 48_000))
        file.framePosition = 3 * 48_000
        try file.read(into: buffer, frameCount: 48_000)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        XCTAssertEqual(Double(rms), 0.5 / 2.0.squareRoot(), accuracy: 0.03, "a 0.5 sine has RMS 0.354")
    }

    // MARK: - Ways out of a recording

    func testARecordingThatCapturedNothingLeavesNoFileBehind() throws {
        let url = scratch.appendingPathComponent("empty.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
        writer.finish()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "a recording that failed to start must not look like one")
    }

    func testLettingGoOfTheWriterStillClosesTheFile() throws {
        let url = scratch.appendingPathComponent("dropped.m4a")
        var writer: ArchiveWriter? = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
        for _ in 0..<7 { writer?.write([.room: tone(seconds: 1)]) }
        writer = nil
        var status = ArchiveStatus.missing
        let deadline = Date().addingTimeInterval(5)
        repeat {
            status = AudioArchive.status(of: url)
            // Readable early, from the fragments already written; the close
            // is what brings it to the full length.
            if case .playable(let ms) = status, ms >= 7_000 - 50 { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        guard case .playable(let ms) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(Double(ms), 7_000, accuracy: 50, "every buffer that was accepted is written")
    }

    func testARateTheEncoderCannotTakeIsRefusedWithAnError() {
        // `AVAssetWriterInput` raises an Objective-C exception for these, which
        // Swift cannot catch and which ends the process.
        for rate in [88_200.0, 96_000, 192_000] {
            let url = scratch.appendingPathComponent("rate-\(Int(rate)).m4a")
            XCTAssertThrowsError(try ArchiveWriter(url: url, sampleRate: rate, lanes: [.room]),
                                 "\(Int(rate)) Hz")
        }
    }

    func testARestartUnderTheSameNameReplacesTheFile() throws {
        let url = scratch.appendingPathComponent("again.m4a")
        for _ in 0..<2 {
            let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
            writer.write([.room: tone(seconds: 1)])
            writer.finish()
        }
        XCTAssertEqual(AudioArchive.status(of: url), .playable(durationMs: 1_000))
    }

    // MARK: - The question the recovery path asks

    func testStatusSaysPlayableUnreadableOrMissing() throws {
        let good = scratch.appendingPathComponent("good.m4a")
        let writer = try ArchiveWriter(url: good, sampleRate: 48_000, lanes: [.room])
        writer.write([.room: tone(seconds: 2)])
        writer.finish()
        XCTAssertEqual(AudioArchive.status(of: good), .playable(durationMs: 2_000))

        XCTAssertEqual(AudioArchive.status(of: scratch.appendingPathComponent("none.m4a")),
                       .missing)

        // What an archive written before this change looks like after a kill:
        // a plain MPEG-4 file whose index was never written.
        let legacy = scratch.appendingPathComponent("legacy.m4a")
        let file = try AVAudioFile(forWriting: legacy, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        for _ in 0..<5 { try file.write(from: tone(seconds: 1)) }
        let killed = scratch.appendingPathComponent("legacy-killed.m4a")
        try FileManager.default.copyItem(at: legacy, to: killed)
        guard case .unreadable = AudioArchive.status(of: killed) else {
            return XCTFail("\(AudioArchive.status(of: killed))")
        }
        // A file with nothing in it is not a recording.
        let hollow = scratch.appendingPathComponent("hollow.m4a")
        FileManager.default.createFile(atPath: hollow.path, contents: Data())
        guard case .unreadable = AudioArchive.status(of: hollow) else {
            return XCTFail("\(AudioArchive.status(of: hollow))")
        }
    }
}
