import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The path from a device buffer to the archive and the working-copy bytes, run
/// with a scripted device: sample alignment across rates, pause, mute, gaps and
/// the two hand-offs that run concurrently.
///
/// The invariant everything here protects is that the archive, the 16 kHz copy
/// and the transcript's clock are one timeline. `LiveSession` counts the copy's
/// bytes as the clock and the archive's frames as the length, so a buffer that
/// is written to one and not the other, or written twice, moves every later
/// timestamp.
final class CaptureTimelineTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-timeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A capture on a scripted device, started and ready for `input.deliver`.
    private func startCapture(rate: Double, source: CaptureSource = .microphone,
                              archive: String? = "a.m4a",
                              sink: AudioSink) throws -> (AudioCapture, ScriptedInput) {
        let input = ScriptedInput(sampleRate: rate)
        let capture = AudioCapture(source: source, microphoneUID: nil,
                                   makeInput: { _, _ in input })
        try capture.start(archiveURL: archive.map { scratch.appendingPathComponent($0) }) {
            sink.receive($0)
        }
        return (capture, input)
    }

    /// Buffers of about 85 ms, the size the tap delivers.
    private func bufferFrames(_ rate: Double) -> Int { Int((rate * 0.085).rounded()) }

    // MARK: - Alignment across rates

    func testTheWorkingCopyTracksTheArchiveAtEveryRate() throws {
        // 8 to 48 kHz covers a telephone headset to a studio interface. Over
        // ten minutes of 85 ms buffers the copy must hold what the archive
        // holds, converted: the difference is the converter's fixed latency,
        // and it must not grow with the length of the recording.
        for rate in [8_000.0, 16_000, 24_000, 44_100, 48_000] {
            let sink = AudioSink()
            sink.keep = false
            let (capture, input) = try startCapture(rate: rate, sink: sink)
            var sine = SineSource(rate: rate)
            let frames = bufferFrames(rate)
            let buffers = Int(600 / 0.085)
            var lag: [Int] = []
            for index in 0..<buffers {
                input.deliver([.room: sine.buffer(frames: frames)])
                if index == buffers / 10 || index == buffers - 1 {
                    let expected = Double(sine.framesProduced) * 16_000 / rate
                    lag.append(Int(expected) - sink.totalBytes / 2)
                }
            }
            let stopped = capture.stop()
            XCTAssertEqual(Int(stopped.frames), sine.framesProduced,
                           "\(Int(rate)) Hz: the archive holds every frame delivered")
            XCTAssertEqual(stopped.sampleRate, Int(rate))
            // Lag at 10% and at the end. Equal means no drift.
            XCTAssertLessThanOrEqual(abs(lag[1] - lag[0]), 2, "\(Int(rate)) Hz drifted: \(lag)")
            XCTAssertLessThan(abs(lag[1]), 40, "\(Int(rate)) Hz: \(lag)")
        }
    }

    func testTheSignalIsNotShiftedByTheConversion() throws {
        // Length can agree while the content is displaced. Cross-correlate the
        // 16 kHz copy against a 16 kHz reference of the same sine.
        let rate = 44_100.0
        let sink = AudioSink()
        let (capture, input) = try startCapture(rate: rate, archive: nil, sink: sink)
        var sine = SineSource(rate: rate, frequency: 300, amplitude: 0.5)
        for _ in 0..<Int(30 / 0.085) { input.deliver([.room: sine.buffer(frames: bufferFrames(rate))]) }
        capture.stop()

        let samples = sink.pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        // Best alignment of the copy against sin(2*pi*300*n/16000), searched
        // over +/-40 samples, away from the edges.
        var bestShift = 0
        var bestScore = -Double.infinity
        for shift in -40...40 {
            var score = 0.0
            for n in 16_000..<(16_000 + 8_000) {
                let reference = sin(2 * Double.pi * 300 * Double(n + shift) / 16_000)
                score += Double(samples[n]) / 32_768 * reference
            }
            if score > bestScore { bestScore = score; bestShift = shift }
        }
        XCTAssertLessThanOrEqual(abs(bestShift), 40 * 0 + 32, "offset \(bestShift) samples")
        print("[timeline] 44.1 kHz copy is displaced by \(bestShift) samples at 16 kHz")
    }

    // MARK: - Pause and mute

    func testPauseTakesTheTimeOutOfEveryCopyAndResumeContinuesWithoutAGap() throws {
        let rate = 48_000.0
        let sink = AudioSink()
        let (capture, input) = try startCapture(rate: rate, sink: sink)
        var sine = SineSource(rate: rate)
        let frames = bufferFrames(rate)

        for _ in 0..<20 { input.deliver([.room: sine.buffer(frames: frames)]) }
        capture.isPaused = true
        for _ in 0..<50 { input.deliver([.room: sine.buffer(frames: frames)]) }
        // The input keeps running through a pause; a gap during it is part of it.
        input.onGap?(48_000)
        capture.isPaused = false
        for _ in 0..<20 { input.deliver([.room: sine.buffer(frames: frames)]) }
        let stopped = capture.stop()

        XCTAssertEqual(Int(stopped.frames), 40 * frames, "40 buffers were recorded, 50 were paused")
        XCTAssertEqual(sink.bytes / 2, Int(Double(40 * frames) * 16_000 / rate), accuracy: 40)
    }

    func testMuteWritesSilenceAndKeepsTheClock() throws {
        let rate = 16_000.0
        let sink = AudioSink()
        let (capture, input) = try startCapture(rate: rate, archive: nil, sink: sink)
        var sine = SineSource(rate: rate)
        capture.isMuted = true
        for _ in 0..<10 { input.deliver([.room: sine.buffer(frames: 1_360)]) }
        capture.stop()
        XCTAssertEqual(sink.bytes / 2, 13_600)
        XCTAssertTrue(sink.pcm.allSatisfy { $0 == 0 }, "muted audio is zeros, not dropped")
    }

    // MARK: - Gaps

    func testAGapIsWrittenAsSilenceInBothCopiesAtTheRightLength() throws {
        let rate = 48_000.0
        let sink = AudioSink()
        let (capture, input) = try startCapture(rate: rate, sink: sink)
        var sine = SineSource(rate: rate)
        let frames = bufferFrames(rate)
        for _ in 0..<10 { input.deliver([.room: sine.buffer(frames: frames)]) }
        input.onGap?(2 * 48_000)            // two seconds lost to a device change
        for _ in 0..<10 { input.deliver([.room: sine.buffer(frames: frames)]) }
        let stopped = capture.stop()

        XCTAssertEqual(Int(stopped.frames), 20 * frames + 2 * 48_000)
        XCTAssertEqual(sink.bytes / 2, Int(Double(20 * frames + 96_000) / 3), accuracy: 40)
    }

    func testALongGapIsNotAllocatedAsOneBuffer() throws {
        // A Mac that sleeps in the middle of a meeting comes back with the
        // whole sleep as one gap. Writing it as one buffer is the length of the
        // sleep in float samples, per lane, in one allocation. Measured on the
        // unsliced code, one hour at 48 kHz raised the footprint by 770 MB and
        // produced a single 115 MB chunk; ten minutes, used here to keep the
        // test short, is 115 MB of float for the same defect.
        let rate = 48_000.0
        let sink = AudioSink()
        sink.keep = false
        let (capture, input) = try startCapture(rate: rate, archive: nil, sink: sink)

        let baseline = MemoryProbe.footprintMB()
        let peak = Peak()
        let watcher = Thread {
            while !peak.stopped {
                peak.note(MemoryProbe.footprintMB())
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        watcher.start()
        input.onGap?(Int(600 * rate))       // ten minutes
        peak.stop()
        let stopped = capture.stop()

        XCTAssertEqual(Int(stopped.frames), 0, "no archive on this run")
        XCTAssertEqual(sink.totalBytes / 2, Int(600 * 16_000.0), accuracy: 64,
                       "the whole gap reaches the working copy")
        XCTAssertLessThanOrEqual(sink.largestChunk, 16_000 * 2 * 2,
                                 "no chunk bigger than two seconds of 16 kHz audio")
        let growth = peak.value - baseline
        print("[timeline] ten minute gap: footprint grew by \(growth) MB at the peak")
        XCTAssertLessThan(growth, 60, "ten minutes of silence must not cost ten minutes of memory")
    }
}

extension CaptureTimelineTests {

    /// The audio thread, the controls and `stop()` all touch the same capture.
    /// Run under `swift test --sanitize=thread` this is the check on the lock
    /// discipline; without it, it still proves a late callback after `stop()`
    /// and a stop in the middle of a stream do not crash or lose the archive.
    func testTheCallbackTheControlsAndStopCanRunAtOnce() throws {
        let rate = 48_000.0
        let sink = AudioSink()
        sink.keep = false
        let (capture, input) = try startCapture(rate: rate, source: .both, sink: sink)
        let frames = bufferFrames(rate)

        let done = DispatchSemaphore(value: 0)
        let delivered = Counter()
        let producer = Thread {
            var room = SineSource(rate: rate)
            var remote = SineSource(rate: rate, frequency: 660)
            // Buffers keep arriving after `stop()` returns, as a real input's
            // last callback can.
            for index in 0..<1_200 {
                input.deliver([.room: room.buffer(frames: frames),
                               .remote: remote.buffer(frames: frames)])
                delivered.increment()
                if index % 200 == 100 { input.onGap?(4_800) }
            }
            done.signal()
        }
        producer.start()

        var toggles = 0
        while delivered.value < 600 {
            capture.isMuted.toggle()
            capture.isRoomMode.toggle()
            capture.gainDb = Float(toggles % 12)
            if toggles % 7 == 0 { capture.isPaused.toggle() }
            toggles += 1
            Thread.sleep(forTimeInterval: 0.0005)
        }
        capture.isPaused = false
        let stopped = capture.stop()                 // in the middle of the stream
        XCTAssertGreaterThan(stopped.frames, 0)
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)

        // Stopping again is harmless, and what was written still opens.
        capture.stop()
        guard case .playable = AudioArchive.status(of: scratch.appendingPathComponent("a.m4a"))
        else { return XCTFail("the archive of a stop in mid-stream must open") }
        XCTAssertGreaterThan(toggles, 10)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

private final class Peak: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    private var _stopped = false
    var value: Int { lock.withLock { _value } }
    var stopped: Bool { lock.withLock { _stopped } }
    func note(_ mb: Int) { lock.withLock { _value = max(_value, mb) } }
    func stop() { lock.withLock { _stopped = true } }
}
