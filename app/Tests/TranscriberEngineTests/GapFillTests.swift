import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A long gap is silence to write, and writing it must not hold the capture
/// thread (finding 33).
///
/// A Mac that slept for ten minutes reports the whole sleep as one gap. With an
/// archive open, `fillGap` wrote it on the capture thread, a second at a time: 3.1 s
/// for one lane and 9.7 s for two in a debug build. A callback that takes seconds to
/// return is a callback the system starts dropping buffers behind.
final class GapFillTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-gapfill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func start(_ source: CaptureSource, rate: Double, sink: AudioSink,
                       archive: String? = "a.m4a") throws -> (AudioCapture, ScriptedInput) {
        let input = ScriptedInput(sampleRate: rate)
        let capture = AudioCapture(source: source, microphoneUID: nil, makeInput: { _, _ in input })
        try capture.start(archiveURL: archive.map { scratch.appendingPathComponent($0) }) { sink.receive($0) }
        return (capture, input)
    }

    private func constant(_ value: Float, frames: Int, rate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frames { channel[index] = value }
        return buffer
    }

    // MARK: - The capture thread

    /// How long the call that reports a ten-minute gap takes to return, with an
    /// archive open. `NOTERO_GAP_SECONDS` changes the gap.
    func testALongGapDoesNotHoldTheCaptureThread() throws {
        let rate = 48_000.0
        let gapSeconds = ProcessInfo.processInfo.environment["NOTERO_GAP_SECONDS"].flatMap(Double.init) ?? 600
        for source in [CaptureSource.microphone, .both] {
            let sink = AudioSink()
            sink.keep = false
            let (capture, input) = try start(source, rate: rate, sink: sink)
            var sine = SineSource(rate: rate)
            for _ in 0..<10 { input.deliver([.room: sine.buffer(frames: 4_080)]) }

            let began = Date()
            input.onGap?(Int(gapSeconds * rate))
            let held = Date().timeIntervalSince(began)
            let drainBegan = Date()
            let stopped = capture.stop()
            let drain = Date().timeIntervalSince(drainBegan)

            print("[gap] \(source.lanes.count) lane(s), \(Int(gapSeconds)) s gap, archive open: "
                  + "the capture thread was held \(String(format: "%.3f", held)) s; "
                  + "the fill finished \(String(format: "%.2f", drain)) s later, at stop")
            XCTAssertLessThan(held, 0.25, "\(source.lanes.count) lane(s): the capture thread was held for the fill")
            XCTAssertEqual(Int(stopped.frames), 10 * 4_080 + Int(gapSeconds * rate),
                           "the whole gap is in the archive")
        }
    }

    // MARK: - Alignment

    /// The sound that arrives straight after a gap must land after the silence,
    /// in both copies, even when it arrives while the fill is still being written.
    /// A fill that ran beside the callback, and not ahead of it, would put it first.
    func testAudioThatArrivesDuringTheFillStaysAfterTheSilence() throws {
        let rate = 48_000.0
        let sink = AudioSink()
        let (capture, input) = try start(.microphone, rate: rate, sink: sink)

        input.deliver([.room: constant(0.5, frames: Int(rate), rate: rate)])      // 0-1 s, loud
        input.onGap?(Int(60 * rate))                                              // 1-61 s, silence
        // Straight away, while the fill is still being written; and more behind it.
        input.deliver([.room: constant(0.5, frames: Int(rate), rate: rate)])      // 61-62 s, loud
        input.deliver([.room: constant(0.0, frames: Int(rate), rate: rate)])      // 62-63 s, quiet
        input.deliver([.room: constant(0.5, frames: Int(rate), rate: rate)])      // 63-64 s, loud
        let stopped = capture.stop()
        XCTAssertEqual(Int(stopped.frames), 64 * Int(rate))

        // The working copy: 16 kHz Int16.
        let samples = sink.pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(samples.count, 64 * 16_000, accuracy: 200)
        func level(_ from: Double, _ to: Double) -> Double {
            let slice = samples[Int(from * 16_000 + 400)..<Int(to * 16_000 - 400)]
            return slice.map { abs(Double($0)) }.reduce(0, +) / Double(slice.count) / 32_768
        }
        XCTAssertGreaterThan(level(0, 1), 0.3, "the first second is loud")
        XCTAssertLessThan(level(1, 61), 0.001, "the gap is silence")
        XCTAssertGreaterThan(level(61, 62), 0.3, "what came after the gap is after it")
        XCTAssertLessThan(level(62, 63), 0.001)
        XCTAssertGreaterThan(level(63, 64), 0.3)

        // The archive: the same, in AAC.
        let file = try AVAudioFile(forReading: scratch.appendingPathComponent("a.m4a"))
        XCTAssertEqual(Int(file.length), 64 * Int(rate))
        func archiveLevel(_ from: Double, _ to: Double) throws -> Double {
            let frames = AVAudioFrameCount((to - from - 0.2) * rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
            file.framePosition = AVAudioFramePosition((from + 0.1) * rate)
            try file.read(into: buffer, frameCount: frames)
            let channel = buffer.floatChannelData![0]
            var sum = 0.0
            for index in 0..<Int(buffer.frameLength) { sum += Double(abs(channel[index])) }
            return sum / Double(buffer.frameLength)
        }
        XCTAssertGreaterThan(try archiveLevel(0, 1), 0.3)
        XCTAssertLessThan(try archiveLevel(1, 61), 0.01)
        XCTAssertGreaterThan(try archiveLevel(61, 62), 0.3, "the archive puts it after the gap too")
        XCTAssertLessThan(try archiveLevel(62, 63), 0.01)
        XCTAssertGreaterThan(try archiveLevel(63, 64), 0.3)
    }

    /// The same with two lanes: a lane that is in the middle of its own gap has its
    /// silence written ahead of both lanes' later audio.
    func testTwoLanesStayTogetherAcrossAGap() throws {
        let rate = 48_000.0
        let sink = AudioSink()
        let (capture, input) = try start(.both, rate: rate, sink: sink)
        input.deliver([.room: constant(0.4, frames: Int(rate), rate: rate),
                       .remote: constant(0.4, frames: Int(rate), rate: rate)])
        input.onGap?(Int(20 * rate))
        input.deliver([.room: constant(0.4, frames: Int(rate), rate: rate),
                       .remote: constant(0.4, frames: Int(rate), rate: rate)])
        let stopped = capture.stop()
        XCTAssertEqual(Int(stopped.frames), 22 * Int(rate))

        let file = try AVAudioFile(forReading: scratch.appendingPathComponent("a.m4a"))
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_000)!
        for (position, loud) in [(0.5, true), (10.0, false), (21.5, true)] {
            file.framePosition = AVAudioFramePosition(position * rate)
            try file.read(into: buffer, frameCount: 8_000)
            for channel in 0..<2 {
                var sum = 0.0
                for index in 0..<Int(buffer.frameLength) { sum += Double(abs(buffer.floatChannelData![channel][index])) }
                let mean = sum / Double(buffer.frameLength)
                XCTAssertEqual(mean > 0.2, loud, "channel \(channel) at \(position) s: \(mean)")
            }
        }
    }
}
