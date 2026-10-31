import AVFoundation
import Darwin
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A kill in the first seconds of a recording (finding 33).
///
/// The archive is written as movie fragments, and until the first one is written
/// the file holds no index: a kill before it left an unreadable file. Measured on a
/// copy of an open archive, 0.5, 1.2, 2.5 and 4.5 s were all unreadable and 5.5 s was
/// readable (5.18 s of it). The writer now asks for a short first fragment.
final class ArchiveEarlyKillTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-early-kill-\(UUID().uuidString)")
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
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / rate))
        }
        return buffer
    }

    /// Seconds readable from a copy of the open file, which is what a kill leaves;
    /// polled, because the encoder hands bytes to the file system a moment after the
    /// writer accepted them. Nil when the copy cannot be opened.
    private func secondsAfterAKill(of url: URL, within timeout: TimeInterval = 3) -> Double? {
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

    private func opened(after seconds: Double, firstFragment: Double?) throws -> Double? {
        let url = scratch.appendingPathComponent("w-\(UUID().uuidString).m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       firstFragmentSeconds: firstFragment)
        var written = 0.0
        while written < seconds - 0.001 {
            let chunk = min(0.5, seconds - written)
            writer.write([.room: tone(seconds: chunk)])
            written += chunk
        }
        writer.settle()
        defer { writer.finish() }
        // A negative result is waited for less: it is the absence of a file that opens.
        return secondsAfterAKill(of: url, within: firstFragment == nil ? 1 : 3)
    }

    func testAKillAfterTheFirstSecondLeavesAReadableFile() throws {
        for seconds in [1.5, 2.5, 4.5] {
            let kept = try XCTUnwrap(try opened(after: seconds, firstFragment: ArchiveWriter.firstFragmentSeconds),
                                     "a kill \(seconds) s in left a file that does not open")
            XCTAssertGreaterThanOrEqual(kept, ArchiveWriter.firstFragmentSeconds - 0.05, "\(seconds) s")
            XCTAssertLessThanOrEqual(kept, seconds + 0.05)
        }
    }

    /// The comparison that makes the test above mean something: with no first
    /// fragment the same kills leave nothing.
    func testWithoutAFirstFragmentTheSameKillsLeaveNothing() throws {
        for seconds in [1.5, 2.5, 4.5] {
            let kept = try opened(after: seconds, firstFragment: nil)
            XCTAssertNil(kept, "a kill \(seconds) s in opened with \(kept ?? 0) s: the baseline moved, so the test above proves nothing")
        }
    }

    /// The cost, measured on the file: the same audio with and without.
    func testTheFirstFragmentCostsAFewHundredBytes() throws {
        var sizes: [String: Int] = [:]
        let arms: [(name: String, first: Double?)] = [("none", nil), ("first", ArchiveWriter.firstFragmentSeconds)]
        for arm in arms {
            let url = scratch.appendingPathComponent("size-\(arm.name).m4a")
            let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                           firstFragmentSeconds: arm.first)
            // Varied content, so that the encoder has something to spend its bits on.
            for second in 0..<120 {
                let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
                buffer.frameLength = 48_000
                var state: UInt64 = UInt64(second + 1) &* 0x9E37_79B9_7F4A_7C15
                let hertz = Double(200 + second * 7)
                let channel = buffer.floatChannelData![0]
                for index in 0..<48_000 {
                    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let bits = Int64(bitPattern: state >> 11)
                    let noise = Float(bits % 2_000) / 2_000_000
                    let phase = 2 * Double.pi * hertz * Double(index) / 48_000
                    channel[index] = noise + Float(0.2 * sin(phase))
                }
                let lanes: [CaptureLane: AVAudioPCMBuffer] = [.room: buffer]
                writer.write(lanes)
            }
            writer.finish()
            XCTAssertEqual(Int(try AVAudioFile(forReading: url).length), 120 * 48_000, "a clean close is exact")
            sizes[arm.name] = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }
        let without = try XCTUnwrap(sizes["none"])
        let with = try XCTUnwrap(sizes["first"])
        print("[early kill] 120 s of audio: \(without) bytes with no first fragment, \(with) with one at \(ArchiveWriter.firstFragmentSeconds) s (\(with - without) bytes)")
        XCTAssertLessThan(abs(with - without), 4_096, "one fragment header, not a change of encoder settings")
    }
}

// MARK: - Real kills

/// The writer in a process of its own, for `ArchiveEarlyKillTests`' real-kill test.
/// It does nothing unless the parent set the environment.
final class ArchiveKillChildTests: XCTestCase {
    func testWriteUntilKilled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["NOTERO_KILL_CHILD_DIR"] else {
            throw XCTSkip("only runs as the child of the real-kill test")
        }
        let first: Double? = environment["NOTERO_KILL_FIRST_FRAGMENT"].flatMap(Double.init)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("k.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000, lanes: [.room],
                                       firstFragmentSeconds: first)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let started = ContinuousClock.now
        var chunks = 0
        while chunks < 600 {                                        // 60 s at most
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
            buffer.frameLength = 4_800
            for index in 0..<4_800 {
                buffer.floatChannelData![0][index] = Float(0.5 * sin(2 * Double.pi * 440 * Double(chunks * 4_800 + index) / 48_000))
            }
            writer.write([.room: buffer])
            chunks += 1
            if chunks == 1 {
                FileManager.default.createFile(atPath: URL(fileURLWithPath: directory)
                    .appendingPathComponent("ready").path, contents: Data())
            }
            // Real time: the chunk is 0.1 s of audio.
            let due = started + .milliseconds(chunks * 100)
            let wait = due - ContinuousClock.now
            if wait > .zero {
                Thread.sleep(forTimeInterval: Double(wait.components.seconds)
                             + Double(wait.components.attoseconds) / 1e18)
            }
        }
        writer.finish()
    }
}

final class ArchiveRealKillTests: XCTestCase {

    /// One real child process, killed with SIGKILL `after` seconds of audio. Returns
    /// the seconds the file holds, or nil if it does not open.
    private func kill(after seconds: Double, firstFragment: Double?) throws -> Double? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-real-kill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        child.arguments = ["xctest", "-XCTest", "TranscriberEngineTests.ArchiveKillChildTests/testWriteUntilKilled",
                           Bundle(for: Self.self).bundlePath]
        var environment = ProcessInfo.processInfo.environment
        environment["NOTERO_KILL_CHILD_DIR"] = directory.path
        environment["NOTERO_KILL_FIRST_FRAGMENT"] = firstFragment.map { String($0) } ?? "none"
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()

        let ready = directory.appendingPathComponent("ready")
        let waitUntil = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: ready.path) {
            if Date() > waitUntil { child.terminate(); throw XCTSkip("the child never started writing") }
            Thread.sleep(forTimeInterval: 0.005)
        }
        Thread.sleep(forTimeInterval: seconds)
        Darwin.kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()

        guard let file = try? AVAudioFile(forReading: directory.appendingPathComponent("k.m4a")),
              file.length > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    /// Opt-in: each kill starts a process, and the whole takes a minute.
    /// `NOTERO_KILL_TESTS=1`; `NOTERO_KILL_COUNT` kills per arm, spread over 0.8-5.5 s.
    func testRealKillsInTheFirstFiveSeconds() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOTERO_KILL_TESTS"] == "1",
                          "set NOTERO_KILL_TESTS=1 to kill real processes")
        let count = ProcessInfo.processInfo.environment["NOTERO_KILL_COUNT"].flatMap(Int.init) ?? 4
        var rows: [String] = []
        var lost = [String: Int]()
        // Interleaved, so that anything slow in the machine hits both arms.
        for index in 0..<count {
            let seconds = 0.8 + (5.5 - 0.8) * Double(index) / Double(max(1, count - 1))
            for (name, first) in [("no first fragment", Double?.none), ("first fragment 1 s", 1.0)] {
                let kept = try kill(after: seconds, firstFragment: first)
                rows.append("\(name) killed at \(String(format: "%.1f", seconds)) s: "
                            + (kept.map { String(format: "%.2f s kept", $0) } ?? "UNREADABLE"))
                if kept == nil { lost[name, default: 0] += 1 }
            }
        }
        print("[real kill] " + rows.joined(separator: " | "))
        print("[real kill] unreadable of \(count): \(lost)")
        XCTAssertEqual(lost["first fragment 1 s", default: 0], rows.filter { $0.hasPrefix("first fragment 1 s killed at 0.") }.count,
                       "with a first fragment only a kill inside the first second may lose the file")
    }
}
