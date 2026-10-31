import AVFoundation
import Darwin
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// What a recording does when the disk fills up under it (FINDINGS §14).
///
/// Two failures, both measured before the fix on a 4 MB disk image: the
/// working-copy writer used the legacy `FileHandle.write(_:)`, which raises an
/// Objective-C exception on `ENOSPC` and took the whole app down; and the
/// archive writer swallowed its write errors, then could not write the MPEG-4
/// index, so the file could not be opened at all -- every minute of it lost.
///
/// A real full disk is not needed to reproduce either. `RLIMIT_FSIZE` makes
/// `write(2)` fail with `EFBIG` through exactly the same path, and an injected
/// `DiskSpace` stands in for a volume running low.
final class DiskFullTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-diskfull-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Working copy

    func testWavWriterSurvivesAFailedWriteAndKeepsWhatItWrote() throws {
        let url = scratch.appendingPathComponent("full.wav")
        let writer = try WavWriter(url: url, disk: .plenty)
        let failures = Counter()
        writer.onFailure = { _ in failures.increment() }

        let first = pcm(seconds: 1, value: 1_000)
        let second = pcm(seconds: 1, value: 2_000)
        // Room for the header and exactly two seconds; the third write fails
        // as a write to a full disk does. Before the fix this test did not
        // fail -- the process died with NSFileHandleOperationException.
        withFileSizeLimit(44 + UInt64(first.count + second.count)) {
            writer.write(first)
            writer.write(second)
            writer.write(pcm(seconds: 1, value: 3_000))
            writer.write(pcm(seconds: 1, value: 4_000))
        }
        writer.close()

        XCTAssertNotNil(writer.failure)
        XCTAssertEqual(failures.value, 1, "reported once, not once per buffer")
        XCTAssertEqual(writer.durationMs, 2_000)
        let mapped = try MappedPCM(contentsOf: url)
        XCTAssertEqual(mapped.sampleCount, 2 * Audio.sampleRate,
                       "what was written before the failure stays readable")
        XCTAssertEqual(mapped.floats(0..<1).first ?? 0, 1_000 / 32_768, accuracy: 1e-6)
        XCTAssertEqual(mapped.floats(Audio.sampleRate..<(Audio.sampleRate + 1)).first ?? 0,
                       2_000 / 32_768, accuracy: 1e-6)
    }

    func testWavWriterStopsBeforeTheDiskIsFull() throws {
        let url = scratch.appendingPathComponent("low.wav")
        let disk = FakeDisk(free: 50_000_000_000)
        let writer = try WavWriter(url: url, disk: disk.probe)
        let failures = Counter()
        writer.onFailure = { _ in failures.increment() }

        let interval = Double(DiskSpace.checkIntervalMs) / 1000
        writer.write(pcm(seconds: interval, value: 1_000))
        disk.free = DiskSpace.reserveBytes - 1
        // The next look at the disk is due one interval later. The buffer
        // that reaches it is not written, and nothing after it is.
        writer.write(pcm(seconds: interval, value: 2_000))
        writer.write(pcm(seconds: 1, value: 3_000))
        writer.close()

        XCTAssertTrue(writer.failure is DiskSpace.Low, "\(String(describing: writer.failure))")
        XCTAssertEqual(failures.value, 1)
        XCTAssertEqual(try MappedPCM(contentsOf: url).durationMs, DiskSpace.checkIntervalMs)
    }

    func testWavWriterRefusesToStartBelowTheReserve() {
        let url = scratch.appendingPathComponent("refused.wav")
        XCTAssertThrowsError(try WavWriter(url: url, disk: FakeDisk(free: 10_000_000).probe)) {
            XCTAssertTrue($0 is WavWriter.CannotWrite)
            XCTAssertTrue($0.localizedDescription.contains("almost full"), $0.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnUnreadableDiskDoesNotStopARecording() throws {
        let url = scratch.appendingPathComponent("unknown.wav")
        let writer = try WavWriter(url: url, disk: DiskSpace { _ in nil })
        writer.write(pcm(seconds: Double(DiskSpace.checkIntervalMs) / 1000 + 1, value: 1))
        writer.close()
        XCTAssertNil(writer.failure)
    }

    func testTheSystemProbeReadsTheVolume() throws {
        let free = try XCTUnwrap(DiskSpace.system.available(scratch.appendingPathComponent("x.wav")))
        XCTAssertGreaterThan(free, 0)
    }

    func testBuildingAWorkingCopyOnALowDiskThrowsRatherThanComingBackShort() async throws {
        let source = scratch.appendingPathComponent("source.m4a")
        try writeArchive(to: source, seconds: 12)
        // Enough to open the file; low by the first look while decoding.
        let disk = FakeDisk(free: 50_000_000_000)
        let destination = scratch.appendingPathComponent("copy.wav")
        let writerProbe = DiskSpace { url in
            defer { disk.free = DiskSpace.reserveBytes - 1 }
            return disk.free
        }
        do {
            _ = try await AudioCache.build(from: source, to: destination, channel: nil,
                                           progress: nil, disk: writerProbe)
            XCTFail("a working copy that stopped part way must not be returned as complete")
        } catch let error as EngineError {
            guard case .cannotSaveAudio = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: - Archive

    func testArchiveIsClosedPlayableWhenTheDiskRunsLow() throws {
        let url = scratch.appendingPathComponent("low.m4a")
        let disk = FakeDisk(free: 50_000_000_000)
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       disk: disk.probe)
        let failures = Counter()
        writer.onFailure = { _ in failures.increment() }
        disk.free = DiskSpace.reserveBytes - 1

        // The first look at the disk is due once five seconds have been
        // handed over; the buffer that reaches it is not written.
        for _ in 0..<8 {
            writer.write([.room: try tone(seconds: 1)])
        }
        writer.finish()

        XCTAssertTrue(writer.failure is DiskSpace.Low, "\(String(describing: writer.failure))")
        XCTAssertEqual(failures.value, 1)
        // The point of stopping early: the file was closed while it could be,
        // so it opens and plays the audio written before the disk ran low.
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(seconds, 4, accuracy: 0.2)
    }

    func testArchiveReportsAFailedWriteInsteadOfSwallowingIt() throws {
        let url = scratch.appendingPathComponent("full.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       disk: .plenty)
        let failures = Counter()
        writer.onFailure = { _ in failures.increment() }

        // AAC at 64 kbps is 8 KB a second; 16 KB fills in about two.
        try withFileSizeLimit(16_384) {
            for _ in 0..<10 {
                writer.write([.room: try tone(seconds: 1)])
            }
            writer.finish()
        }

        XCTAssertNotNil(writer.failure)
        XCTAssertEqual(failures.value, 1)
    }

    func testArchiveRefusesToStartBelowTheReserve() {
        let url = scratch.appendingPathComponent("refused.m4a")
        XCTAssertThrowsError(try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                               disk: FakeDisk(free: 1_000).probe)) {
            guard case EngineError.cannotSaveAudio = $0 else { return XCTFail("\($0)") }
        }
    }

    func testStorageNoticesSayWhatIsKept() {
        let why = DiskSpace.Low(availableBytes: 52_000_000).localizedDescription
        XCTAssertTrue(why.contains("almost full"))
        XCTAssertTrue(CaptureNotice.recordingNotSaved(why).message.contains(why))
        XCTAssertTrue(CaptureNotice.workingCopyNotSaved(why).message.contains("Transcribe Again"))
    }

    // MARK: - Helpers

    /// Runs `body` with every file this process writes capped at `bytes`.
    /// A write past the cap fails with `EFBIG`; the signal that would
    /// otherwise kill the process is ignored for the duration.
    private func withFileSizeLimit<T>(_ bytes: UInt64, _ body: () throws -> T) rethrows -> T {
        var saved = rlimit()
        getrlimit(RLIMIT_FSIZE, &saved)
        let previous = signal(SIGXFSZ, SIG_IGN)
        var limited = saved
        limited.rlim_cur = rlim_t(bytes)
        setrlimit(RLIMIT_FSIZE, &limited)
        defer {
            setrlimit(RLIMIT_FSIZE, &saved)
            signal(SIGXFSZ, previous)
        }
        return try body()
    }

    private func pcm(seconds: Double, value: Int16) -> Data {
        let samples = [Int16](repeating: value.littleEndian,
                              count: Int(seconds * Double(Audio.sampleRate)))
        return samples.withUnsafeBytes { Data($0) }
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

    private func writeArchive(to url: URL, seconds: Int) throws {
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       disk: .plenty)
        for _ in 0..<seconds {
            writer.write([.room: try tone(seconds: 1)])
        }
        writer.finish()
        XCTAssertNil(writer.failure)
    }
}

/// A volume whose free space a test sets.
private final class FakeDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var _free: Int64?

    init(free: Int64?) { _free = free }

    var free: Int64? {
        get { lock.withLock { _free } }
        set { lock.withLock { _free = newValue } }
    }

    var probe: DiskSpace { DiskSpace { [self] _ in free } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

private extension DiskSpace {
    static let plenty = DiskSpace { _ in 50_000_000_000 }
}
