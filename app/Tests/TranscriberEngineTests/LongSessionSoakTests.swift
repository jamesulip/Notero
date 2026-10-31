import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// Hours of audio through the real capture path, faster than real time.
///
/// `NOTERO_SOAK_HOURS` sets how long the session is; the default is six
/// simulated minutes so the ordinary run stays short. The numbers in the
/// findings come from 1, 3 and 6 hours of the same test.
///
/// What it checks, on the live path with a scripted device, recognizer and
/// voice detector (no microphone, no model):
///
/// - **One timeline.** A 20 ms beep sits every ten seconds of source time. Each
///   one is found again in the 16 kHz working copy -- the bytes the
///   transcript's clock counts -- and in the AAC archive, and must be where the
///   source put it after allowing for the pause (dropped) and the gap
///   (silence, so the wall clock holds). The archive's frame count must equal
///   the frames delivered, and the clock must agree with the copy.
/// - **Memory.** The footprint is sampled every five simulated minutes and a
///   line is fitted to the second half: the slope is the number to read, not a
///   single reading.
final class LongSessionSoakTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-soak-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    static var hours: Double {
        ProcessInfo.processInfo.environment["NOTERO_SOAK_HOURS"].flatMap(Double.init) ?? 0.1
    }

    /// Least-squares slope of `samples` (x in hours, y in MB), over the second
    /// half, so allocator warm-up is not read as growth.
    static func slope(_ samples: [(hours: Double, mb: Int)]) -> Double {
        let tail = Array(samples.suffix(max(2, samples.count / 2)))
        guard tail.count >= 2 else { return 0 }
        let n = Double(tail.count)
        let meanX = tail.map(\.hours).reduce(0, +) / n
        let meanY = tail.map { Double($0.mb) }.reduce(0, +) / n
        let covariance = tail.reduce(0.0) { $0 + ($1.hours - meanX) * (Double($1.mb) - meanY) }
        let variance = tail.reduce(0.0) { $0 + ($1.hours - meanX) * ($1.hours - meanX) }
        return variance > 0 ? covariance / variance : 0
    }

    // MARK: - The source

    /// Silence with a beep at every marker, in source frames.
    struct Source {
        let rate: Double
        let markerEveryFrames: Int
        let beepFrames: Int
        var position = 0

        init(rate: Double) {
            self.rate = rate
            self.markerEveryFrames = Int(10 * rate)
            self.beepFrames = Int(0.02 * rate)
        }

        func isMarker(_ frame: Int) -> Bool { frame % markerEveryFrames == 0 }

        mutating func buffer(frames: Int) -> AVAudioPCMBuffer {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            let channel = buffer.floatChannelData![0]
            for index in 0..<frames {
                let frame = position + index
                let sinceMarker = frame % markerEveryFrames
                if sinceMarker < beepFrames {
                    channel[index] = 0.8 * Float(sin(2 * Double.pi * 1_000 * Double(sinceMarker) / rate))
                } else {
                    channel[index] = 0
                }
            }
            position += frames
            return buffer
        }

        /// Skips time the device did not deliver.
        mutating func skip(_ frames: Int) { position += frames }
    }

    /// First sample at or after `from` whose magnitude passes the threshold.
    private func onset(in samples: [Float], from: Int = 0, threshold: Float = 0.3) -> Int? {
        for index in from..<samples.count where abs(samples[index]) > threshold { return index }
        return nil
    }

    // MARK: - The live path

    @MainActor
    func testALongSessionStaysOnOneTimelineAndDoesNotGrow() async throws {
        let rate = 48_000.0
        let frames = Int((rate * 0.085).rounded())
        let totalSeconds = Self.hours * 3_600
        let buffersPerSecond = rate / Double(frames)
        let totalBuffers = Int(totalSeconds * buffersPerSecond)

        let input = ScriptedInput(sampleRate: rate)
        let captureBox = Box<AudioCapture>()
        let session = LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: scratch)
        session.captureSource = .microphone
        session.requestMicrophoneAccess = { true }
        session.makeCapture = { source, uid in
            let capture = AudioCapture(source: source, microphoneUID: uid, makeInput: { _, _ in input })
            captureBox.value = capture
            return capture
        }
        session.decoderOverride = { config in
            LiveDecoder(config: config,
                        recognizer: OracleRecognizer(words: []),
                        vad: ScriptedVAD(speech: [0..<Int.max]))
        }

        let id = UUID()
        let archiveURL = scratch.appendingPathComponent("soak.m4a")
        try await session.start(recordingId: id, archiveFileName: "soak.m4a", archiveURL: archiveURL)
        let capture = try XCTUnwrap(captureBox.value)

        // One pause and one gap, in the middle.
        let pauseAt = Int(Double(totalBuffers) * 0.4)
        let pauseBuffers = Int(60 * buffersPerSecond)
        let gapAt = Int(Double(totalBuffers) * 0.6)
        let gapFrames = Int(90 * rate)

        // The producer is a thread of its own, as the audio callback is, and
        // the main actor stays free to ingest. Throttled to stay two seconds
        // ahead of the consumer at most, as real time does by itself.
        let progress = SoakProgress()
        let sampleEvery = Int(300 * buffersPerSecond)
        let perSecond = max(1, Int(buffersPerSecond.rounded()))
        let producer = Thread {
            var source = Source(rate: rate)
            for index in 0..<totalBuffers {
                if index == pauseAt { capture.isPaused = true }
                if index == pauseAt + pauseBuffers { capture.isPaused = false }
                let paused = index >= pauseAt && index < pauseAt + pauseBuffers
                if index == gapAt {
                    input.onGap?(gapFrames)
                    source.skip(gapFrames)            // the device lost this time
                    progress.record(frames: gapFrames, ms: Int(Double(gapFrames) / rate * 1000))
                }
                let first = source.position
                let buffer = source.buffer(frames: frames)
                input.deliver([.room: buffer])
                if paused {
                    progress.paused(frames: frames)
                } else {
                    var frame = first
                    while frame < first + frames {
                        if source.isMarker(frame) { progress.marker(sourceFrame: frame) }
                        frame = (frame / source.markerEveryFrames + 1) * source.markerEveryFrames
                    }
                    progress.record(frames: frames, ms: 85)
                }
                if (index + 1) % perSecond == 0 {
                    while progress.deliveredMs - progress.consumedMs > 2_000 { usleep(200) }
                }
                if (index + 1) % Int(30 * buffersPerSecond) == 0 { capture.settle() }
                if (index + 1) % sampleEvery == 0 {
                    progress.sample(hours: Double(index + 1) / buffersPerSecond / 3_600,
                                    mb: MemoryProbe.footprintMB())
                }
            }
            progress.finish()
        }
        producer.start()
        var maxLagMs = 0
        while !progress.finished {
            let consumed = session.currentMs
            progress.setConsumed(consumed)
            maxLagMs = max(maxLagMs, progress.deliveredMs - consumed)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let markers = progress.markers
        let memory = progress.memory
        let expectedRecordedFrames = progress.recordedFrames

        let stopped = await session.stop()
        let result = try XCTUnwrap(stopped)

        // The question recovery asks, on a file this long.
        let askedAt = Date()
        let status = AudioArchive.status(of: archiveURL)
        let statusMs = Int(Date().timeIntervalSince(askedAt) * 1000)
        guard case .playable(let archiveMs) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(Double(archiveMs), Double(result.durationMs), accuracy: 100)

        // MARK: Frames
        XCTAssertEqual(result.archiveSampleRate, Int(rate))
        let archiveFile = try AVAudioFile(forReading: archiveURL)
        XCTAssertEqual(Int(archiveFile.length), expectedRecordedFrames,
                       "the archive holds exactly the frames recorded")
        let copy = try MappedPCM(contentsOf: result.cacheURL)
        let expectedCopySamples = Double(expectedRecordedFrames) * 16_000 / rate
        XCTAssertEqual(Double(copy.sampleCount), expectedCopySamples, accuracy: 200,
                       "the working copy is the archive converted")
        XCTAssertEqual(Double(result.durationMs),
                       Double(expectedRecordedFrames) / rate * 1000, accuracy: 100)

        // MARK: Markers, in the working copy and in the archive
        var copyErrors: [Double] = []
        for marker in markers {
            let expectedMs = Double(marker.recordedFrame) / rate * 1000
            let center = Int(expectedMs * 16)
            let window = copy.floats(max(0, center - 3_200)..<(center + 3_200))
            guard let found = onset(in: window) else {
                XCTFail("marker at \(expectedMs / 1000) s not found in the working copy")
                continue
            }
            copyErrors.append(Double(max(0, center - 3_200) + found) / 16 - expectedMs)
        }
        // A sample of the archive: reading AAC at a position is the slow part.
        var archiveErrors: [Double] = []
        let stride = max(1, markers.count / 24)
        for marker in markers.enumerated().filter({ $0.offset % stride == 0 }).map(\.element) {
            let from = max(0, marker.recordedFrame - 4_800)
            archiveFile.framePosition = AVAudioFramePosition(from)
            let buffer = AVAudioPCMBuffer(pcmFormat: archiveFile.processingFormat,
                                          frameCapacity: 9_600)!
            try archiveFile.read(into: buffer, frameCount: 9_600)
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                    count: Int(buffer.frameLength)))
            guard let found = onset(in: samples) else {
                XCTFail("marker at frame \(marker.recordedFrame) not found in the archive")
                continue
            }
            archiveErrors.append(Double(from + found - marker.recordedFrame) / rate * 1000)
        }

        let copyMax = copyErrors.map(abs).max() ?? 0
        let archiveMax = archiveErrors.map(abs).max() ?? 0
        let slope = Self.slope(memory)
        let peak = memory.map(\.mb).max() ?? 0
        let summary = "[soak] \(Self.hours) h, \(markers.count) markers: working copy off by at most "
            + "\(String(format: "%.2f", copyMax)) ms (first \(String(format: "%.2f", copyErrors.first ?? 0)), "
            + "last \(String(format: "%.2f", copyErrors.last ?? 0))), archive off by at most "
            + "\(String(format: "%.2f", archiveMax)) ms over \(archiveErrors.count) probes; "
            + "footprint slope \(String(format: "%.1f", slope)) MB/h, peak \(peak) MB over "
            + "\(memory.count) samples; consumer lag at most \(maxLagMs) ms; "
            + "meter \(session.meter.count) bars, segments \(session.segments.count); "
            + "AudioArchive.status of the \(Self.hours) h file took \(statusMs) ms"
        print(summary)

        XCTAssertGreaterThan(markers.count, 0)
        XCTAssertLessThanOrEqual(copyMax, 3, "the 16 kHz copy keeps the source's clock")
        XCTAssertLessThanOrEqual(archiveMax, 25, "the archive keeps it to within an AAC frame")
        XCTAssertLessThanOrEqual(abs((copyErrors.last ?? 0) - (copyErrors.first ?? 0)), 1,
                                 "no drift between the first marker and the last")
        XCTAssertLessThanOrEqual(session.meter.count, 600, "the meter is bounded")
        XCTAssertLessThanOrEqual(maxLagMs, 3_000, "the ingest kept up")
        if Self.hours >= 1 {
            XCTAssertLessThan(slope, 20, "footprint grows by \(slope) MB per hour")
        }
    }

}

/// What the producer thread tells the test, and the consumer's position it
/// reads back.
private final class SoakProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _deliveredMs = 0
    private var _consumedMs = 0
    private var _recordedFrames = 0
    private var _pausedFrames = 0
    private var _markers: [(sourceFrame: Int, recordedFrame: Int)] = []
    private var _memory: [(hours: Double, mb: Int)] = []
    private var _finished = false

    var deliveredMs: Int { lock.withLock { _deliveredMs } }
    var consumedMs: Int { lock.withLock { _consumedMs } }
    var recordedFrames: Int { lock.withLock { _recordedFrames } }
    var markers: [(sourceFrame: Int, recordedFrame: Int)] { lock.withLock { _markers } }
    var memory: [(hours: Double, mb: Int)] { lock.withLock { _memory } }
    var finished: Bool { lock.withLock { _finished } }

    func setConsumed(_ ms: Int) { lock.withLock { _consumedMs = ms } }
    func finish() { lock.withLock { _finished = true } }
    func sample(hours: Double, mb: Int) { lock.withLock { _memory.append((hours, mb)) } }

    /// Frames that reached the recording.
    func record(frames: Int, ms: Int) {
        lock.withLock {
            _recordedFrames += frames
            _deliveredMs += ms
        }
    }

    /// Frames the pause dropped: the recording is that much shorter than the
    /// source.
    func paused(frames: Int) { lock.withLock { _pausedFrames += frames } }

    func marker(sourceFrame: Int) {
        lock.withLock { _markers.append((sourceFrame, sourceFrame - _pausedFrames)) }
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    var value: T? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - When the main actor falls behind

/// The audio callback hands each chunk to an unbounded `AsyncStream`, which the
/// main actor drains. A main actor that is blocked -- a modal dialog, a long
/// layout, a save -- does not stop the microphone, so the stream is the buffer.
/// This blocks the main actor on purpose while a producer thread delivers, and
/// reports what the backlog costs and whether anything is lost.
///
/// Unbounded is the right policy for a recording: the alternative to memory is
/// dropping audio, and dropped audio is gone. What has to be true is that the
/// backlog is small per minute, and that it all arrives, in order, when the
/// main actor is free again.
final class IngestStallTests: XCTestCase {

    /// Blocks the calling thread, which is the point. A separate function,
    /// because the compiler refuses a semaphore wait written in an async one.
    private static func block(until semaphore: DispatchSemaphore) { semaphore.wait() }

    @MainActor
    func testABlockedMainActorBuffersEveryChunkAndDrainsInOrder() async throws {
        let minutes = ProcessInfo.processInfo.environment["NOTERO_STALL_MINUTES"]
            .flatMap(Double.init) ?? 1
        let rate = 48_000.0
        let frames = Int((rate * 0.085).rounded())
        let buffers = Int(minutes * 60 / 0.085)

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-stall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        for lanes in [CaptureSource.microphone, .both] {
            let input = ScriptedInput(sampleRate: rate)
            let session = LiveSession(
                engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
                supportDirectory: scratch)
            session.decodeLive = false
            session.captureSource = lanes
            session.requestMicrophoneAccess = { true }
            session.requestSystemAudioAccess = { true }
            session.makeCapture = { source, uid in
                AudioCapture(source: source, microphoneUID: uid, makeInput: { _, _ in input })
            }
            try await session.start(recordingId: UUID(), archiveFileName: nil, archiveURL: nil)

            let delivered = DispatchSemaphore(value: 0)
            let baseline = MemoryProbe.footprintMB()
            let producer = Thread {
                var room = SineSource(rate: rate)
                var remote = SineSource(rate: rate, frequency: 660)
                for _ in 0..<buffers {
                    var chunk: [CaptureLane: AVAudioPCMBuffer] = [.room: room.buffer(frames: frames)]
                    if lanes == .both { chunk[.remote] = remote.buffer(frames: frames) }
                    input.deliver(chunk)
                }
                delivered.signal()
            }
            producer.start()
            // The main actor is not available: nothing is ingested until this
            // returns, however long the producer takes.
            Self.block(until: delivered)
            let backlogMB = MemoryProbe.footprintMB() - baseline
            XCTAssertEqual(session.currentMs, 0, "nothing was ingested while the main actor was blocked")

            let started = Date()
            let stopped = await session.stop()
            let drain = Date().timeIntervalSince(started)
            let result = try XCTUnwrap(stopped)

            let expectedMs = Double(buffers * frames) / rate * 1000
            XCTAssertEqual(Double(result.durationMs), expectedMs, accuracy: 200,
                           "every chunk arrived once the main actor was free")
            let perMinute = Double(backlogMB) / minutes
            print("[stall] \(lanes.lanes.count) lane(s), main actor blocked for \(minutes) min of audio: "
                  + "backlog \(backlogMB) MB (\(String(format: "%.1f", perMinute)) MB per minute), "
                  + "drained in \(String(format: "%.2f", drain)) s, "
                  + "ingested \(result.durationMs) of \(Int(expectedMs)) ms")
            XCTAssertLessThan(perMinute, Double(lanes.lanes.count) * 4,
                              "a minute of backlog costs a few MB, not tens")
        }
    }
}

// MARK: - Decoder state over hours

/// A recognizer that hears one word every 600 ms, inside the speech the
/// detector reports, at the absolute time the window's samples encode.
private actor PeriodicRecognizer: SpeechRecognizing {
    static let speechPeriodMs = 20_000
    static let speechMs = 18_800
    static let wordEveryMs = 600

    var loadedModel: String? { "periodic" }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() {}

    static func isSpeech(_ ms: Int) -> Bool { ms % speechPeriodMs < speechMs }

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        let start = OraclePCM.startMs(of: request.samples)
        let duration = request.samples.count / 16
        var tokens: [Token] = []
        var word = (start + Self.wordEveryMs - 1) / Self.wordEveryMs
        while word * Self.wordEveryMs + 400 <= start + duration {
            let at = word * Self.wordEveryMs
            if Self.isSpeech(at) && Self.isSpeech(at + 400) {
                tokens.append(Token(text: " w\(word)", startMs: at - start,
                                    endMs: at - start + 400, confidence: 0.9))
            }
            word += 1
        }
        return ASROutput(tokens: tokens, audioMs: duration, inferMs: 1,
                         detectedLanguage: request.language)
    }
}

private actor PeriodicVAD: VoiceActivityDetecting {
    private var leftover = 0
    private var framesSeen = 0
    private var speechMs = 0
    private var trailing = 0

    func prepare(progress: ProgressReport?) async throws {}
    func regions(in samples: [Float]) async throws -> [SpeechRegion] { [] }
    func clearSpeechCounter() { speechMs = 0 }
    func reset() { leftover = 0; framesSeen = 0; speechMs = 0; trailing = 0 }

    func push(_ samples: [Float]) async throws -> VoiceActivityReading {
        leftover += samples.count
        var speech = false
        while leftover >= EnergyVoiceActivity.frameSamples {
            let at = framesSeen * EnergyVoiceActivity.frameMs
            speech = PeriodicRecognizer.isSpeech(at)
            if speech { speechMs += EnergyVoiceActivity.frameMs; trailing = 0 } else { trailing += EnergyVoiceActivity.frameMs }
            framesSeen += 1
            leftover -= EnergyVoiceActivity.frameSamples
        }
        return VoiceActivityReading(isSpeech: speech, probability: speech ? 1 : 0,
                                    trailingSilenceMs: trailing, speechMs: speechMs)
    }
}

final class DecoderSoakTests: XCTestCase {

    /// Hours of speech with a pause every twenty seconds, through the live
    /// decoder: what it commits, what it drops, and whether its state grows.
    @MainActor
    func testTheDecoderDoesNotGrowOverHours() async throws {
        let hours = LongSessionSoakTests.hours
        let totalMs = Int(hours * 3_600_000)
        let chunkMs = 85
        let hopMs = SessionConfig().hopMs

        let decoder = LiveDecoder(config: SessionConfig(), recognizer: PeriodicRecognizer(),
                                  vad: PeriodicVAD())
        var committed = 0
        var lastEnd = 0
        decoder.onCommitted = { tokens in
            committed += tokens.count
            lastEnd = max(lastEnd, tokens.last?.endMs ?? 0)
        }

        var memory: [(hours: Double, mb: Int)] = []
        var atMs = 0
        var sinceHop = 0
        let sampleEveryMs = 300_000
        var nextSample = sampleEveryMs
        let began = Date()
        while atMs < totalMs {
            decoder.ingest(OraclePCM.data(fromMs: atMs, ms: chunkMs))
            atMs += chunkMs
            sinceHop += chunkMs
            if sinceHop >= hopMs {
                sinceHop = 0
                await decoder.drain()     // a recognizer that always finishes in time
            }
            if atMs >= nextSample {
                nextSample += sampleEveryMs
                memory.append((Double(atMs) / 3_600_000, MemoryProbe.footprintMB()))
            }
        }
        await decoder.finish()
        let wall = Date().timeIntervalSince(began)

        var expectedWords = 0
        var word = 0
        while word * PeriodicRecognizer.wordEveryMs + 400 <= totalMs {
            let at = word * PeriodicRecognizer.wordEveryMs
            if PeriodicRecognizer.isSpeech(at) && PeriodicRecognizer.isSpeech(at + 400) { expectedWords += 1 }
            word += 1
        }
        let stats = decoder.stats
        let slope = LongSessionSoakTests.slope(memory)
        print("[decoder] \(hours) h in \(String(format: "%.0f", wall)) s: committed \(committed) of "
              + "\(expectedWords) words, \(stats.hops) hops (\(stats.droppedHops) dropped, "
              + "\(stats.forcedCommits) forced, \(stats.boundaries) boundaries), "
              + "footprint slope \(String(format: "%.1f", slope)) MB/h, peak "
              + "\(memory.map(\.mb).max() ?? 0) MB over \(memory.count) samples")

        XCTAssertGreaterThan(Double(committed), Double(expectedWords) * 0.95,
                             "the live path keeps what was said")
        XCTAssertEqual(decoder.currentMs, atMs, accuracy: 1, "the decoder's clock is the audio's")
        XCTAssertLessThanOrEqual(lastEnd, atMs + 400, "no word is placed after the audio ends")
        if hours >= 1 { XCTAssertLessThan(slope, 20, "footprint grows by \(slope) MB per hour") }
    }
}
