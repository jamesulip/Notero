import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// What the queue leaves resident when a job ends, whichever way it ends.
///
/// The speaker models are about 200 MB on the Neural Engine, and `EngineHost`
/// promises to release them the moment no job needs them. The release used to
/// sit on the success path only (F13): a diarization that was cancelled, by the
/// user or by a recording, rethrew before it, and so did a failure in the second
/// lane after the first lane had diarized. The models then stayed until someone
/// pressed "Release the Models" in Settings.
///
/// No weights here: the engines are stand-ins that count what is loaded, handed
/// to the host through its test initializer.
final class QueueResidencyTests: XCTestCase {

    // MARK: - Stand-ins

    /// A recognizer with no model. Returns one word per window, or waits to be
    /// cancelled, as a Core ML call that cannot be interrupted does.
    private actor FakeRecognizer: SpeechRecognizing {
        private(set) var model: String?
        private(set) var calls = 0
        private let blocks: Bool
        init(blocks: Bool = false) { self.blocks = blocks }
        var loadedModel: String? { model }
        func load(model: String, progress: ProgressReport?) async throws { self.model = model }
        func unload() async { model = nil }
        func transcribe(_ request: ASRRequest) async throws -> ASROutput {
            calls += 1
            if blocks {
                while !Task.isCancelled { try await Task.sleep(for: .milliseconds(5)) }
                throw CancellationError()
            }
            let audioMs = request.samples.count * 1000 / Audio.sampleRate
            return ASROutput(tokens: [Token(text: " hola", startMs: 0, endMs: 400, confidence: 0.9)],
                             audioMs: audioMs, inferMs: 1)
        }
    }

    /// A diarizer that knows whether its models are resident.
    private actor FakeDiarizer: SpeakerDiarizing {
        enum Behavior { case answers, waitsForCancel }
        private(set) var loaded = false
        private(set) var prepares = 0
        private(set) var unloads = 0
        private(set) var entered = 0
        private var behavior: Behavior
        init(_ behavior: Behavior) { self.behavior = behavior }
        var isAvailable: Bool { loaded }
        func prepare(progress: ProgressReport?) async throws { loaded = true; prepares += 1 }
        func unload() async { loaded = false; unloads += 1 }
        func diarize(_ source: any PCMSource, speechRegions: [SpeechRegion]?,
                     mode: DiarizationMode, expectedSpeakers: Int?,
                     progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan] {
            guard loaded else { throw EngineError.modelNotLoaded }
            entered += 1
            switch behavior {
            case .answers:
                return [SpeakerSpan(speakerId: "S1", startMs: 0, endMs: 1000, quality: 1)]
            case .waitsForCancel:
                while !Task.isCancelled { try await Task.sleep(for: .milliseconds(5)) }
                throw CancellationError()
            }
        }
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    private struct Rig {
        let queue: TranscriptionQueue
        let diarizer: FakeDiarizer
        let recognizer: FakeRecognizer
        let log: Log
        let reader: Task<Void, Never>
    }

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-residency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func rig(diarizer behavior: FakeDiarizer.Behavior,
                     recognizerBlocks: Bool = false) -> Rig {
        let diarizer = FakeDiarizer(behavior)
        let recognizer = FakeRecognizer(blocks: recognizerBlocks)
        // `preferNeural: false` is the energy detector: no model to load.
        let host = EngineHost(
            modelsDirectory: scratch,
            asr: recognizer,
            vad: VADEngine(modelsDirectory: scratch, preferNeural: false),
            diarizer: diarizer)
        let queue = TranscriptionQueue(engines: host)
        let log = Log()
        let reader = Task {
            for await event in queue.events {
                switch event {
                case .finished: log.add("finished")
                case .failed(_, let message): log.add("failed:\(message)")
                case .stage(_, let status, _) where status == .diarizing: log.add("diarizing")
                default: break
                }
            }
        }
        return Rig(queue: queue, diarizer: diarizer, recognizer: recognizer, log: log, reader: reader)
    }

    /// A 16 kHz working copy of tone, loud enough for the energy detector.
    @discardableResult
    private func workingCopy(_ url: URL, seconds: Int = 6) throws -> URL {
        let writer = try WavWriter(url: url)
        let samples = (0..<(Audio.sampleRate * seconds)).map {
            Float(0.3 * sin(2 * Double.pi * 440 * Double($0) / Double(Audio.sampleRate)))
        }
        writer.write(PCM.data(from: samples))
        writer.close()
        return url
    }

    private func job(work: TranscriptionJob.Work = .full, lanes: [CaptureLane] = [.room],
                     expectedSpeakers: Int? = nil) throws -> TranscriptionJob {
        let cache = scratch.appendingPathComponent("\(UUID().uuidString).wav")
        try workingCopy(cache)
        return TranscriptionJob(id: UUID(), title: "residency", sourceURL: nil, cacheURL: cache,
                                modelId: "stand-in", language: "tl",
                                diarizationMode: .accurate, work: work,
                                discardCacheWhenDone: false,
                                expectedSpeakers: expectedSpeakers, lanes: lanes)
    }

    private func eventually(_ what: String, timeout: Double = 5,
                            _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { XCTFail("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - The speaker models do not outlive the job

    func testACompletedJobReleasesTheSpeakerModels() async throws {
        let rig = rig(diarizer: .answers)
        defer { rig.reader.cancel() }
        let job = try job()
        await rig.queue.enqueue(job)
        try await eventually("the job to finish") { rig.log.all.contains("finished") }

        let prepares = await rig.diarizer.prepares
        XCTAssertEqual(prepares, 1, "the job never reached diarization: \(rig.log.all)")
        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded, "a finished job left the speaker models resident")
    }

    func testACancelledDiarizationReleasesTheSpeakerModels() async throws {
        let rig = rig(diarizer: .waitsForCancel)
        defer { rig.reader.cancel() }
        let job = try job()
        await rig.queue.enqueue(job)
        try await eventually("diarization to start") { await rig.diarizer.entered == 1 }

        await rig.queue.cancel(job.id)
        try await eventually("the job to finish") { rig.log.all.contains("finished") }

        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded, "a cancelled diarization left ~200 MB resident (F13)")
    }

    func testACancelledDiarizeOnlyJobReleasesTheSpeakerModels() async throws {
        let rig = rig(diarizer: .waitsForCancel)
        defer { rig.reader.cancel() }
        let job = try job(work: .diarizeOnly)
        await rig.queue.enqueue(job)
        try await eventually("diarization to start") { await rig.diarizer.entered == 1 }

        await rig.queue.cancel(job.id)
        try await eventually("the job to finish") { rig.log.all.contains("finished") }

        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded, "a cancelled speaker-only job left ~200 MB resident")
    }

    func testALaneThatFailsAfterAnotherLaneDiarizedReleasesTheSpeakerModels() async throws {
        let rig = rig(diarizer: .answers)
        defer { rig.reader.cancel() }
        let job = try job(lanes: [.room, .remote])
        // The room lane has its copy. The remote lane has neither a copy nor an
        // original to rebuild one from, so the job fails after the room lane
        // has loaded the speaker models and used them.
        try workingCopy(AudioCache.url(besides: job.cacheURL, lane: .room))
        await rig.queue.enqueue(job)
        try await eventually("the job to finish") { rig.log.all.contains("finished") }

        XCTAssertTrue(rig.log.all.contains { $0.hasPrefix("failed:") },
                      "the remote lane was meant to fail: \(rig.log.all)")
        let prepares = await rig.diarizer.prepares
        XCTAssertGreaterThanOrEqual(prepares, 1, "the room lane never diarized: \(rig.log.all)")
        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded, "a failed two-lane job left the speaker models resident")
    }

    func testARecordingFindsTheSpeakerModelsReleasedWhenItStepsAJobAside() async throws {
        let rig = rig(diarizer: .waitsForCancel)
        defer { rig.reader.cancel() }
        let job = try job()
        await rig.queue.enqueue(job)
        try await eventually("diarization to start") { await rig.diarizer.entered == 1 }

        // The call returns when the job has stopped. The recording is about to
        // load its own model, so the job's 200 MB has to be gone by then.
        await rig.queue.setLiveActive(true)

        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded, "the recording started with the speaker models still resident")
    }

    func testACancelledDecodeNeverLoadedTheSpeakerModels() async throws {
        let rig = rig(diarizer: .answers, recognizerBlocks: true)
        defer { rig.reader.cancel() }
        let job = try job()
        await rig.queue.enqueue(job)
        try await eventually("the decode to start") { await rig.recognizer.calls >= 1 }

        await rig.queue.cancel(job.id)
        try await eventually("the job to finish") { rig.log.all.contains("finished") }

        let prepares = await rig.diarizer.prepares
        XCTAssertEqual(prepares, 0, "a job cancelled while decoding loaded the speaker models")
        let loaded = await rig.diarizer.loaded
        XCTAssertFalse(loaded)
    }
}
