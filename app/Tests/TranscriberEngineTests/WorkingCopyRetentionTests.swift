import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The 16 kHz working copy is deleted after a job only when the archive can
/// rebuild it (finding 16). After a quit or crash under a recording the
/// archive is an unclosed AAC file that nothing opens, and the working copy is
/// the only audio there is. The recovery message tells the user to transcribe
/// again, and that job used to delete the copy when it finished.
final class WorkingCopyRetentionTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-retention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Fixtures

    /// A 16 kHz working copy of `seconds` of tone.
    @discardableResult
    private func workingCopy(_ name: String, seconds: Int) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        let writer = try WavWriter(url: url)
        let samples = (0..<(Audio.sampleRate * seconds)).map {
            Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / Double(Audio.sampleRate)))
        }
        writer.write(PCM.data(from: samples))
        writer.close()
        return url
    }

    /// A real AAC archive, closed properly.
    private func archive(_ name: String, seconds: Double) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            channel[index] = Float(0.4 * sin(2 * Double.pi * 440 * Double(index) / rate))
        }
        let writer = try ArchiveWriter(url: url, sampleRate: rate, lanes: [.room])
        writer.write([.room: buffer])
        writer.finish()
        return url
    }

    /// An archive that never closed. `AVAudioFile` writes the index when it is
    /// released, and until then the file is a header and a placeholder, which is
    /// what a killed process leaves behind. Holding the writer open reproduces
    /// that without killing the test process.
    private func withUnclosedArchive(_ name: String, seconds: Double,
                                     _ body: (URL) async throws -> Void) async throws {
        let url = scratch.appendingPathComponent(name)
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            channel[index] = Float(0.4 * sin(2 * Double.pi * 440 * Double(index) / rate))
        }
        let open = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
        try open.write(from: buffer)
        try await body(url)
        withExtendedLifetime(open) {}
    }

    private func job(cache: URL, source: URL?, discard: Bool = true) -> TranscriptionJob {
        // Speaker pass for one speaker needs no model, so the real queue runs
        // the real discard rule without weights.
        TranscriptionJob(id: UUID(), title: "t", sourceURL: source, cacheURL: cache,
                         modelId: "unused", language: "tl", diarizationMode: .accurate,
                         work: .diarizeOnly, discardCacheWhenDone: discard, expectedSpeakers: 1)
    }

    private func run(_ job: TranscriptionJob,
                     archiveMs: Int?) async -> [JobEvent] {
        let queue = TranscriptionQueue(engines: EngineHost(modelsDirectory: scratch),
                                       archiveProbe: { _ in archiveMs })
        await queue.enqueue(job)
        var events: [JobEvent] = []
        for await event in queue.events {
            events.append(event)
            if case .finished(let id) = event, id == job.id { break }
        }
        return events
    }

    private func completed(_ events: [JobEvent]) -> Bool {
        events.contains {
            if case .stage(_, let status, _) = $0 { return status == .completed }
            return false
        }
    }

    // MARK: - The queue

    func testAWorkingCopyIsDeletedWhenTheArchiveCanRebuildIt() async throws {
        let cache = try workingCopy("a.wav", seconds: 3)
        let events = await run(job(cache: cache, source: scratch.appendingPathComponent("a.m4a")),
                               archiveMs: 3_000)
        XCTAssertTrue(completed(events))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path),
                       "the archive holds everything, so the copy is disposable")
    }

    func testAWorkingCopyIsKeptWhenTheArchiveCannotBeRead() async throws {
        let cache = try workingCopy("b.wav", seconds: 3)
        let events = await run(job(cache: cache, source: scratch.appendingPathComponent("b.m4a")),
                               archiveMs: nil)
        XCTAssertTrue(completed(events))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path),
                      "an unreadable archive cannot rebuild the copy, and the copy is the audio")
    }

    func testAWorkingCopyIsKeptWhenTheArchiveHoldsLessAudio() async throws {
        let cache = try workingCopy("c.wav", seconds: 10)
        let events = await run(job(cache: cache, source: scratch.appendingPathComponent("c.m4a")),
                               archiveMs: 4_000)
        XCTAssertTrue(completed(events))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path),
                      "deleting it would lose the six seconds that only the copy has")
    }

    func testAWorkingCopyWithNoArchiveBehindItIsKept() async throws {
        let cache = try workingCopy("d.wav", seconds: 3)
        let events = await run(job(cache: cache, source: nil), archiveMs: nil)
        XCTAssertTrue(completed(events))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testAWorkingCopyTheUserAskedToKeepIsKept() async throws {
        let cache = try workingCopy("e.wav", seconds: 3)
        let events = await run(job(cache: cache, source: scratch.appendingPathComponent("e.m4a"),
                                   discard: false), archiveMs: 3_000)
        XCTAssertTrue(completed(events))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    // MARK: - A working copy cut short

    func testAWorkingCopyShorterThanItsArchiveIsBuiltAgainBeforeTheJobUsesIt() async throws {
        // A writer that stopped on a low disk leaves a short copy. The job used
        // to trust it, transcribe it, and delete it.
        let source = try workingCopy("long-source.wav", seconds: 20)
        let cache = try workingCopy("short.wav", seconds: 5)
        let queue = TranscriptionQueue(engines: EngineHost(modelsDirectory: scratch))
        let job = job(cache: cache, source: source, discard: false)
        await queue.enqueue(job)
        for await event in queue.events {
            if case .finished(let id) = event, id == job.id { break }
        }

        let after = try MappedPCM(contentsOf: cache)
        XCTAssertEqual(after.durationMs, 20_000, accuracy: 300,
                       "the 5 s copy was replaced from the 20 s archive")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: cache.appendingPathExtension("rebuilt").path), "no scratch file is left")
    }

    func testAnArchiveThatIsShorterThanTheCopyNeverReplacesIt() async throws {
        let source = try workingCopy("short-source.wav", seconds: 5)
        let cache = try workingCopy("long.wav", seconds: 20)
        let queue = TranscriptionQueue(engines: EngineHost(modelsDirectory: scratch))
        let job = job(cache: cache, source: source, discard: true)
        await queue.enqueue(job)
        for await event in queue.events {
            if case .finished(let id) = event, id == job.id { break }
        }

        XCTAssertEqual(try MappedPCM(contentsOf: cache).durationMs, 20_000, accuracy: 50)
    }

    // MARK: - The probes

    func testTheProbesReadAGoodArchive() async throws {
        let url = try archive("good.m4a", seconds: 3)
        let async = await ArchiveProbe.durationMs(of: url)
        XCTAssertEqual(try XCTUnwrap(async), 3_000, accuracy: 200)
        XCTAssertEqual(try XCTUnwrap(ArchiveProbe.recordedDurationMs(of: url)), 3_000, accuracy: 200)
    }

    func testTheProbesRefuseAnArchiveThatNeverClosed() async throws {
        try await withUnclosedArchive("cut.m4a", seconds: 3) { url in
            let size = try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            XCTAssertGreaterThan(size, 0,
                                 "the file exists and has a size, which is what makes it misleading")
            let async = await ArchiveProbe.durationMs(of: url)
            XCTAssertNil(async)
            XCTAssertNil(ArchiveProbe.recordedDurationMs(of: url))
        }
    }

    func testTheToleranceRulesAtTheirEdges() {
        XCTAssertTrue(WorkingCopyPolicy.archiveCovers(archiveMs: 60_000, workingCopyMs: 60_000))
        XCTAssertTrue(WorkingCopyPolicy.archiveCovers(archiveMs: 60_000, workingCopyMs: 61_500),
                      "codec padding is not a loss")
        XCTAssertFalse(WorkingCopyPolicy.archiveCovers(archiveMs: 60_000, workingCopyMs: 70_000))
        XCTAssertFalse(WorkingCopyPolicy.archiveCovers(archiveMs: nil, workingCopyMs: 1))
        // Long recordings: the allowance does not grow with the length. At a
        // share of the length, a working copy 72 s longer than a two-hour
        // archive counted as covered and was deleted.
        let twoHours = 2 * 60 * 60 * 1000
        XCTAssertFalse(WorkingCopyPolicy.archiveCovers(archiveMs: twoHours,
                                                       workingCopyMs: twoHours + 72_000),
                       "audio the archive does not hold must keep its working copy")
        XCTAssertFalse(WorkingCopyPolicy.archiveCovers(archiveMs: twoHours,
                                                       workingCopyMs: twoHours + 5_000))
        XCTAssertTrue(WorkingCopyPolicy.archiveCovers(archiveMs: twoHours,
                                                      workingCopyMs: twoHours + 500))
        XCTAssertTrue(WorkingCopyPolicy.isTruncated(workingCopyMs: twoHours - 72_000,
                                                    archiveMs: twoHours))
        XCTAssertTrue(WorkingCopyPolicy.isTruncated(workingCopyMs: 5_000, archiveMs: 20_000))
        XCTAssertFalse(WorkingCopyPolicy.isTruncated(workingCopyMs: 19_000, archiveMs: 20_000))
        XCTAssertFalse(WorkingCopyPolicy.isTruncated(workingCopyMs: 5_000, archiveMs: nil),
                       "an unreadable archive says nothing about the copy")
    }
}
