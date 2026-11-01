import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// Closing the recording file must not be able to freeze Stop, and the length the
/// archive reports must be what it holds (finding 33).
///
/// Stop ended in `ArchiveWriter.finish()`: a queue wait and then a bare semaphore
/// wait on `finishWriting`, on the main actor. The quit gate's 30 s timer is a
/// main-actor task, so an encoder that never answered froze Stop and the timer
/// together. An independent probe with a 0.1 s timeout and a stop that blocked the
/// main thread for 1.5 s got its reply after 1.51 s.

/// An archive whose `finish()` hangs until a test lets it go (or `ceiling` runs
/// out, so that a run against the old code ends). Stands in for a hung encoder.
final class StallingArchive: ArchiveWriting, @unchecked Sendable {
    let fileFormat: AVAudioFormat
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var _frames: AVAudioFramePosition = 0
    private var _enteredFinish = false
    private var _finished = false
    private let ceiling: TimeInterval

    init(rate: Double, ceiling: TimeInterval = 4) {
        self.fileFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        self.ceiling = ceiling
    }

    var frameCount: AVAudioFramePosition { lock.withLock { _frames } }
    var failure: (any Error)? { nil }
    var onFailure: (@Sendable (any Error) -> Void)? {
        get { nil }
        set {}
    }
    var enteredFinish: Bool { lock.withLock { _enteredFinish } }
    var finished: Bool { lock.withLock { _finished } }

    func write(_ buffers: [CaptureLane: AVAudioPCMBuffer]) {
        let count = buffers.values.map(\.frameLength).min() ?? 0
        lock.withLock { _frames += AVAudioFramePosition(count) }
    }

    func finish() {
        lock.withLock { _enteredFinish = true }
        _ = release.wait(timeout: .now() + ceiling)
        lock.withLock { _finished = true }
    }

    func settle() {}
    func letGo() { release.signal() }
}

final class ArchiveCloseTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-archive-close-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
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

    private func seconds(since start: Date) -> Double { Date().timeIntervalSince(start) }

    // MARK: - The wait is bounded

    func testStopGivesUpOnAHungArchiveAtTheTimeoutAndTheCloseCarriesOn() throws {
        let rate = 48_000.0
        let input = ScriptedInput(sampleRate: rate)
        let stall = StallingArchive(rate: rate)
        let capture = AudioCapture(source: .microphone, microphoneUID: nil,
                                   makeInput: { _, _ in input },
                                   makeArchive: { _, _, _ in stall })
        try capture.start(archiveURL: scratch.appendingPathComponent("a.m4a")) { _ in }
        var sine = SineSource(rate: rate)
        for _ in 0..<20 { input.deliver([.room: sine.buffer(frames: 4_080)]) }

        let began = Date()
        let stopped = capture.stop(closeWithin: 0.3)
        let took = seconds(since: began)

        XCTAssertTrue(stall.enteredFinish,
                      "the archive's close has to have started and be hanging, or the wait proves nothing")
        XCTAssertFalse(stopped.closed, "the archive did not close in time and Stop must say so")
        XCTAssertGreaterThanOrEqual(took, 0.25, "it waited for the close")
        XCTAssertLessThan(took, 2, "and then it gave up")
        XCTAssertEqual(Int(stopped.frames), 20 * 4_080, "what was handed over is what is reported")

        // The close is not abandoned: once the encoder answers, the file is finished.
        stall.letGo()
        let deadline = Date().addingTimeInterval(5)
        while !stall.finished && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(stall.finished, "the close must still complete when the encoder gets round to it")
    }

    func testACleanStopStillClosesTheFileAndReportsEveryFrame() throws {
        let rate = 48_000.0
        let input = ScriptedInput(sampleRate: rate)
        let capture = AudioCapture(source: .microphone, microphoneUID: nil, makeInput: { _, _ in input })
        let url = scratch.appendingPathComponent("clean.m4a")
        try capture.start(archiveURL: url) { _ in }
        var sine = SineSource(rate: rate)
        for _ in 0..<80 { input.deliver([.room: sine.buffer(frames: 4_080)]) }

        let stopped = capture.stop(closeWithin: 10)

        XCTAssertTrue(stopped.closed)
        XCTAssertEqual(Int(stopped.frames), 80 * 4_080)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Int(file.length), 80 * 4_080, "a clean close holds exactly the frames written (finding 17)")
    }

    // MARK: - The limits themselves

    /// QA mutated each of these to a hundred times its value and nothing failed: every
    /// test shortens the timeout, so the shipped number was never looked at. Stop waits
    /// 10 s for the archive, inside the quit gate's 30 s, so a quit gets its answer from
    /// here; the writer gives up on a thread that has not answered in 30 s.
    @MainActor
    func testTheShippedCloseLimitsStayInsideTheQuitGate() {
        let session = LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: scratch)
        XCTAssertEqual(session.archiveCloseTimeout, 10)
        XCTAssertLessThan(session.archiveCloseTimeout, 30, "the quit gate's own timeout")
        XCTAssertEqual(ArchiveWriter.closeLimit, 30)
    }

    // MARK: - The main actor stays free

    /// A stop on the main actor with an archive that hangs. The main actor ticks
    /// every 10 ms; `ticks` is the precondition that makes a short gap mean something.
    @MainActor
    func testAHungArchiveDoesNotFreezeTheMainActorAtStop() async throws {
        let rate = 48_000.0
        let input = ScriptedInput(sampleRate: rate)
        let stall = StallingArchive(rate: rate, ceiling: 3)
        let session = LiveSession(
            engines: EngineHost(modelsDirectory: URL(fileURLWithPath: "/nonexistent")),
            supportDirectory: scratch)
        session.decodeLive = false
        session.captureSource = .microphone
        session.requestMicrophoneAccess = { true }
        session.archiveCloseTimeout = 0.5
        session.makeCapture = { source, uid in
            AudioCapture(source: source, microphoneUID: uid, makeInput: { _, _ in input },
                         makeArchive: { _, _, _ in stall })
        }
        try await session.start(recordingId: UUID(), archiveFileName: "a.m4a",
                                archiveURL: scratch.appendingPathComponent("a.m4a"))
        var sine = SineSource(rate: rate)
        for _ in 0..<40 { input.deliver([.room: sine.buffer(frames: 4_080)]) }

        let ticker = Task { @MainActor () -> (gapMs: Double, ticks: Int) in
            var longest = 0.0
            var ticks = 0
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ContinuousClock.now
                let gap = now - last
                longest = max(longest, Double(gap.components.seconds) * 1000
                              + Double(gap.components.attoseconds) / 1e15)
                last = now
                ticks += 1
            }
            return (longest, ticks)
        }
        try await Task.sleep(for: .milliseconds(60))

        let began = Date()
        let stopped = await session.stop()
        let took = seconds(since: began)
        ticker.cancel()
        let (gapMs, ticks) = await ticker.value
        stall.letGo()

        let result = try XCTUnwrap(stopped)
        print("stop with a hung archive: returned after \(String(format: "%.2f", took)) s, "
              + "main actor ticked \(ticks) times, longest gap \(Int(gapMs)) ms")
        XCTAssertTrue(stall.enteredFinish, "the archive has to have hung for this to mean anything")
        XCTAssertGreaterThan(ticks, 10, "the ticker has to have run during the stop")
        XCTAssertLessThan(gapMs, 250, "the main actor must not wait for the encoder")
        XCTAssertGreaterThanOrEqual(took, 0.45)
        XCTAssertLessThan(took, 2.5, "Stop answers at its own timeout, not the encoder's")
        XCTAssertTrue(result.notices.contains { if case .archiveNotClosed = $0 { true } else { false } },
                      "the person is told the file did not close in time: \(result.notices)")
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(result.durationMs, 40 * 4_080 * 1_000 / 48_000, "the recording is still its full length")
    }

    // MARK: - What the archive says it holds

    private final class Disk: @unchecked Sendable {
        private let lock = NSLock()
        private var _free: Int64 = 50_000_000_000
        var free: Int64 {
            get { lock.withLock { _free } }
            set { lock.withLock { _free = newValue } }
        }
        var probe: DiskSpace { DiskSpace { [self] _ in free } }
    }

    /// 60 s were handed over; the disk ran low at the first look, five seconds in. The
    /// file holds 4 s and reported 60.
    func testAfterADiskLowStopTheArchiveReportsWhatItHolds() throws {
        let url = scratch.appendingPathComponent("low.m4a")
        let disk = Disk()
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room], disk: disk.probe)
        disk.free = DiskSpace.reserveBytes - 1
        for _ in 0..<60 { writer.write([.room: tone(seconds: 1)]) }
        writer.finish()

        XCTAssertTrue(writer.failure is DiskSpace.Low, "\(String(describing: writer.failure))")
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Int(writer.frameCount), Int(file.length),
                       "the archive reported \(writer.frameCount) frames and the file holds \(file.length)")
        XCTAssertLessThan(Double(file.length) / 48_000, 10, "the file is the short one: the disk stopped it early")
    }

    func testAfterAFailedWriteTheArchiveReportsWhatItHolds() throws {
        let url = scratch.appendingPathComponent("full.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       disk: DiskSpace { _ in 50_000_000_000 })
        var saved = rlimit()
        getrlimit(RLIMIT_FSIZE, &saved)
        let previous = signal(SIGXFSZ, SIG_IGN)
        var limited = saved
        limited.rlim_cur = 16_384
        setrlimit(RLIMIT_FSIZE, &limited)
        for _ in 0..<30 { writer.write([.room: tone(seconds: 1)]) }
        writer.finish()
        setrlimit(RLIMIT_FSIZE, &saved)
        signal(SIGXFSZ, previous)

        XCTAssertNotNil(writer.failure, "the write has to have failed for this to mean anything")
        let held = (try? AVAudioFile(forReading: url)).map { Int($0.length) } ?? 0
        XCTAssertLessThanOrEqual(Int(writer.frameCount), 30 * 48_000)
        XCTAssertEqual(Int(writer.frameCount), held,
                       "the archive reported \(writer.frameCount) frames and the file holds \(held)")
    }

    func testACleanCloseStillReportsEveryFrameHandedOver() throws {
        for (rate, lanes) in [(48_000.0, [CaptureLane.room]), (44_100.0, [.room, .remote]), (16_000.0, [.room])] {
            let url = scratch.appendingPathComponent("exact-\(Int(rate))-\(lanes.count).m4a")
            let writer = try ArchiveWriter(url: url, sampleRate: rate, lanes: lanes)
            var written = 0
            for size in [1_021, 4_096, 3_749, 777, 12_345, 8_192] {
                let buffer = tone(seconds: Double(size) / rate, rate: rate)
                writer.write(Dictionary(uniqueKeysWithValues: lanes.map { ($0, buffer) }))
                written += Int(buffer.frameLength)
            }
            writer.finish()
            XCTAssertEqual(Int(writer.frameCount), written)
            XCTAssertEqual(Int(try AVAudioFile(forReading: url).length), written)
            XCTAssertNil(writer.failure)
        }
    }

    /// A buffer that arrives after the close is neither counted nor written.
    func testABufferAfterTheCloseIsNotCounted() throws {
        let url = scratch.appendingPathComponent("late.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room])
        for _ in 0..<5 { writer.write([.room: tone(seconds: 1)]) }
        writer.finish()
        let before = writer.frameCount
        writer.write([.room: tone(seconds: 1)])
        XCTAssertEqual(writer.frameCount, before, "a late callback must not lengthen what the file holds")
        XCTAssertEqual(Int(try AVAudioFile(forReading: url).length), Int(before))
    }
}
