import Synchronization
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A recognizer that can be told to refuse particular windows.
///
/// WhisperKit refuses a window by returning nothing at all, deterministically,
/// based on what the audio happens to be. That is not reproducible against the
/// real model, so it is modelled here: `refuse` decides, by sample count,
/// whether this call comes back empty.
actor FakeRecognizer: SpeechRecognizing {
    typealias Refusal = @Sendable (_ sampleCount: Int, _ attempt: Int) -> Bool

    private let refuse: Refusal
    private let callHook: @Sendable () async -> Void
    private(set) var calls: [(samples: Int, attempt: Int)] = []

    init(refuse: @escaping Refusal = { _, _ in false },
         callHook: @escaping @Sendable () async -> Void = {}) {
        self.refuse = refuse
        self.callHook = callHook
    }

    var loadedModel: String? { "fake" }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() {}

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        await callHook()
        calls.append((request.samples.count, request.decodeAttempt))
        let durationMs = request.samples.count * 1000 / Audio.sampleRate
        guard !refuse(request.samples.count, request.decodeAttempt) else {
            return ASROutput(tokens: [], audioMs: durationMs, inferMs: 1)
        }
        // One word per second of audio, window-relative, plus one hallucinated
        // word out in the 30-second padding that every caller must discard.
        var tokens: [Token] = []
        var at = 0
        while at + 1_000 <= durationMs {
            tokens.append(Token(text: "w\(at / 1_000) ", startMs: at, endMs: at + 900,
                                confidence: 0.9))
            at += 1_000
        }
        tokens.append(Token(text: "hallucinated ", startMs: 29_000, endMs: 29_900))
        return ASROutput(tokens: tokens, audioMs: durationMs, inferMs: 1,
                         detectedLanguage: "tl")
    }
}

private actor PipelineEventLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor BatchedVAD: VoiceActivityDetecting {
    let log: PipelineEventLog

    init(log: PipelineEventLog) { self.log = log }

    func prepare(progress: ProgressReport?) async throws {}
    func push(_ samples: [Float]) async throws -> VoiceActivityReading {
        VoiceActivityReading(isSpeech: false, probability: 0,
                             trailingSilenceMs: 0, speechMs: 0)
    }
    func clearSpeechCounter() {}
    func reset() {}

    func regions(in samples: [Float]) async throws -> [SpeechRegion] {
        await log.append("vad")
        let durationMs = Audio.samplesToMs(samples.count)
        return stride(from: 0, to: durationMs, by: 25_000).map {
            SpeechRegion(startMs: $0, endMs: min(durationMs, $0 + 25_000))
        }
    }
}

final class PipelineWindowTests: XCTestCase {

    private func region(_ start: Int, _ end: Int) -> SpeechRegion {
        SpeechRegion(startMs: start, endMs: end)
    }

    func testWindowsPackSeveralRegionsTogether() {
        let windows = OfflinePipeline.windows(
            for: [region(0, 5_000), region(6_000, 11_000), region(12_000, 17_000)],
            durationMs: 20_000
        )
        // All three fit inside one 28-second window, so one decode, not three.
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].startMs, 0)
        XCTAssertEqual(windows[0].endMs, 17_200)
    }

    func testWindowsBreakAtARegionBoundaryRatherThanMidSpeech() {
        // Two 20-second regions cannot share a 28-second window, so the break
        // has to land in the silence between them.
        let windows = OfflinePipeline.windows(
            for: [region(0, 20_000), region(21_000, 41_000)], durationMs: 45_000
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].endMs, 20_200)
        XCTAssertEqual(windows[1].startMs, 20_800)
    }

    func testNoWindowExceedsWhisperSReceptiveField() {
        let regions = (0..<12).map { region($0 * 9_000, $0 * 9_000 + 8_000) }
        let windows = OfflinePipeline.windows(for: regions, durationMs: 120_000)
        XCTAssertFalse(windows.isEmpty)
        for window in windows {
            XCTAssertLessThanOrEqual(window.durationMs, OfflinePipeline.maxWindowMs)
        }
    }

    func testAnUnbrokenMonologueIsCutAtTheWindowBoundary() {
        // 70 seconds with no pause: there is nowhere good to cut, so it is cut
        // at the ceiling rather than truncated.
        let windows = OfflinePipeline.windows(for: [region(0, 70_000)], durationMs: 70_000)
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.last?.endMs, 70_000)
        XCTAssertEqual(windows.first?.startMs, 0)
        // Contiguous: no audio falls between two windows.
        for pair in zip(windows, windows.dropFirst()) {
            XCTAssertEqual(pair.0.endMs, pair.1.startMs)
        }
    }

    func testWindowsAreEmptyWithoutSpeech() {
        XCTAssertTrue(OfflinePipeline.windows(for: [], durationMs: 60_000).isEmpty)
    }

    func testWindowsNeverRunPastTheEndOfTheAudio() {
        let windows = OfflinePipeline.windows(for: [region(0, 9_950)], durationMs: 10_000)
        XCTAssertEqual(windows.last?.endMs, 10_000)
    }

    // MARK: - Seam joining

    func testSeamJoinRepairsARegionSplitByAProcessingWindow() {
        let before = [region(0, 300_000)]
        let after = [region(300_000, 310_000), region(320_000, 330_000)]
        let joined = OfflinePipeline.joinAcrossSeam(before, after, at: 300_000)
        XCTAssertEqual(joined.count, 2)
        XCTAssertEqual(joined[0].endMs, 310_000)
    }

    func testSeamJoinLeavesTheDetectorSOwnBoundariesAlone() {
        // Both regions are well clear of the seam, so this is a real pause the
        // detector found -- and a real pause is exactly where a decode window
        // should be allowed to end.
        let before = [region(0, 290_000)]
        let after = [region(301_000, 310_000)]
        let joined = OfflinePipeline.joinAcrossSeam(before, after, at: 300_000)
        XCTAssertEqual(joined.count, 2)
    }
}

final class IncrementalFilePipelineTests: XCTestCase {
    func testFirstBatchIsDecodedBeforeTheSecondBatchIsScanned() async throws {
        let log = PipelineEventLog()
        let vad = BatchedVAD(log: log)
        let asr = FakeRecognizer(callHook: { await log.append("asr") })
        let source = ArrayPCM([Float](repeating: 0.1,
                                     count: Audio.sampleRate * 310))

        let report = try await OfflinePipeline.transcribeFile(
            source: source, using: vad, asr: asr,
            language: "tl", prompt: nil
        )

        let events = await log.values
        let firstASR = try XCTUnwrap(events.firstIndex(of: "asr"))
        let secondVAD = try XCTUnwrap(events.indices.filter { events[$0] == "vad" }.dropFirst().first)
        XCTAssertLessThan(firstASR, secondVAD)
        XCTAssertEqual(report.regions.count, 12, "the region crossing 5:00 is rejoined")
        XCTAssertEqual(report.regions.last?.endMs, 310_000)
        XCTAssertGreaterThan(report.windowCount, 1)
        XCTAssertFalse(report.decode.tokens.isEmpty)
    }
}

final class PipelineDecodeTests: XCTestCase {

    private func source(seconds: Int) -> ArrayPCM {
        ArrayPCM([Float](repeating: 0.1, count: Audio.sampleRate * seconds))
    }

    private func window(_ start: Int, _ end: Int) -> SpeechRegion {
        SpeechRegion(startMs: start, endMs: end)
    }

    func testPaddingHallucinationsAreDiscarded() async throws {
        let asr = FakeRecognizer()
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 10), windows: [window(0, 10_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertFalse(report.tokens.contains { $0.text.contains("hallucinated") })
        XCTAssertEqual(report.tokens.count, 10)
        XCTAssertEqual(report.droppedWindows, 0)
    }

    func testEachWindowReportsItsOwnWordsAsItFinishes() async throws {
        // The progressive path: the UI shows each window's words as they land,
        // so the batches must arrive in order and add up to the final report.
        let asr = FakeRecognizer()
        let batches = Mutex<[[Token]]>([])
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 30),
            windows: [window(0, 10_000), window(10_000, 20_000), window(20_000, 30_000)],
            using: asr, language: "tl", prompt: nil,
            onWindow: { tokens, _ in batches.withLock { $0.append(tokens) } }
        )
        let delivered = batches.withLock { $0 }
        XCTAssertEqual(delivered.count, 3)
        XCTAssertEqual(delivered.flatMap { $0 }, report.tokens)
        XCTAssertEqual(delivered[1].first?.startMs, 10_000)
    }

    func testTimingsAreRebasedOntoTheFileTimeline() async throws {
        let asr = FakeRecognizer()
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 30), windows: [window(20_000, 25_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertEqual(report.tokens.first?.startMs, 20_000)
        XCTAssertEqual(report.tokens.last?.startMs, 24_000)
    }

    func testOverlappingWindowsDoNotEmitTheSameWordTwice() async throws {
        // Windows overlap by `padMs` so onsets are not clipped. Without a floor
        // the words inside the overlap would appear in both.
        let asr = FakeRecognizer()
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 30),
            windows: [window(0, 10_000), window(9_800, 20_000)],
            using: asr, language: "tl", prompt: nil
        )
        let starts = report.tokens.map(\.startMs)
        XCTAssertEqual(Set(starts).count, starts.count, "a word was emitted twice")
        XCTAssertTrue(starts.sorted() == starts, "tokens must come back in order")
    }

    func testARefusedWindowIsRecoveredByWideningIt() async throws {
        // The real failure: one exact sample count comes back empty every time.
        let poison = Audio.sampleRate * 25
        let asr = FakeRecognizer { samples, _ in samples == poison }
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 40), windows: [window(0, 25_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertEqual(report.droppedWindows, 0)
        XCTAssertEqual(report.retriedWindows, 1)
        XCTAssertFalse(report.tokens.isEmpty)
        // Nothing from the widened margin leaks past the window it belongs to.
        XCTAssertTrue(report.tokens.allSatisfy { $0.startMs < 25_250 })
    }

    func testARefusedWindowIsRecoveredByHalvingItWhenWideningFails() async throws {
        // Every attempt at the full length and both widened lengths refuses;
        // only the halves are short enough to be accepted.
        let asr = FakeRecognizer { samples, _ in samples > Audio.sampleRate * 14 }
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 40), windows: [window(0, 24_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertEqual(report.droppedWindows, 0)
        XCTAssertEqual(report.retriedWindows, 1)
        XCTAssertFalse(report.tokens.isEmpty)
    }

    func testAWindowNothingCanDecodeIsReportedRatherThanSilentlyLost() async throws {
        let asr = FakeRecognizer { _, _ in true }
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 40), windows: [window(0, 24_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertTrue(report.tokens.isEmpty)
        // The point of the whole exercise: a short transcript must not be able
        // to pass for a complete one.
        XCTAssertEqual(report.droppedWindows, 1)
    }

    func testSplittingStopsBeforeItBecomesPointless() async throws {
        let asr = FakeRecognizer { _, _ in true }
        let before = await asr.calls.count
        _ = try await OfflinePipeline.transcribe(
            source: source(seconds: 20), windows: [window(0, 20_000)],
            using: asr, language: "tl", prompt: nil
        )
        let calls = await asr.calls.count - before
        // 3 attempts at each level, at most 2 levels of halving: bounded, not
        // an exponential storm of decodes on a file that simply cannot be read.
        XCTAssertLessThanOrEqual(calls, 3 + 2 * 3 + 4 * 3)
    }

    func testDecodeAttemptIsPassedThroughSoBackendsCanVaryTheirSampling() async throws {
        let asr = FakeRecognizer { _, attempt in attempt < 1 }
        _ = try await OfflinePipeline.transcribe(
            source: source(seconds: 20), windows: [window(0, 10_000)],
            using: asr, language: "tl", prompt: nil
        )
        let attempts = await asr.calls.map(\.attempt)
        XCTAssertEqual(attempts.prefix(2).map { $0 }, [0, 1])
    }

    func testTinyWindowsAreSkippedRatherThanDecoded() async throws {
        let asr = FakeRecognizer()
        let before = await asr.calls.count
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 10), windows: [window(0, 40)],
            using: asr, language: "tl", prompt: nil
        )
        let after = await asr.calls.count
        XCTAssertEqual(after, before)
        XCTAssertTrue(report.tokens.isEmpty)
    }
}

extension PipelineDecodeTests {
    func testEveryWindowReportsItsDetectedLanguage() async throws {
        // `detectedLanguage` is the first window's answer; the per-window list
        // is what shows auto-detect changing its mind mid-recording.
        let asr = FakeRecognizer()
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 40), windows: [window(0, 15_000), window(15_000, 30_000)],
            using: asr, language: "auto", prompt: nil
        )
        XCTAssertEqual(report.windowLanguages.count, 2)
        XCTAssertEqual(report.windowLanguages.compactMap { $0 }, ["tl", "tl"])
        XCTAssertEqual(report.detectedLanguage, "tl")
    }
}

/// One stretch decoded again: only words inside it come back, on the file's
/// timeline, and a quiet range is still decoded as one window.
final class RangeDecodeTests: XCTestCase {

    private actor SilentVAD: VoiceActivityDetecting {
        func prepare(progress: ProgressReport?) async throws {}
        func push(_ samples: [Float]) async throws -> VoiceActivityReading {
            VoiceActivityReading(isSpeech: false, probability: 0, trailingSilenceMs: 0, speechMs: 0)
        }
        func clearSpeechCounter() {}
        func reset() {}
        func regions(in samples: [Float]) async throws -> [SpeechRegion] { [] }
    }

    func testOnlyWordsInsideTheRangeComeBackOnTheFileTimeline() async throws {
        // Two minutes of audio; the fake says one word per second of window.
        let source = ArrayPCM([Float](repeating: 0.1, count: Audio.sampleRate * 120))
        let report = try await OfflinePipeline.transcribeRange(
            SpeechRegion(startMs: 60_000, endMs: 70_000),
            in: source, using: SilentVAD(), asr: FakeRecognizer(),
            language: "tl", prompt: nil
        )
        XCTAssertEqual(report.windowCount, 1, "a quiet range is decoded as one window")
        XCTAssertEqual(report.droppedWindows, 0)
        XCTAssertFalse(report.tokens.isEmpty)
        for token in report.tokens {
            // The first word may start in the 200 ms of padding before the
            // range, as the model stamps it; its midpoint is inside.
            XCTAssertGreaterThanOrEqual(token.startMs, 60_000 - OfflinePipeline.padMs)
            XCTAssertGreaterThanOrEqual((token.startMs + token.endMs) / 2, 60_000)
            XCTAssertLessThan(token.startMs, 70_000)
        }
        XCTAssertFalse(report.tokens.contains { $0.text.contains("hallucinated") })
    }

    /// The detector hears the turn start late. The decode must not.
    private actor LateVAD: VoiceActivityDetecting {
        func prepare(progress: ProgressReport?) async throws {}
        func push(_ samples: [Float]) async throws -> VoiceActivityReading {
            VoiceActivityReading(isSpeech: false, probability: 0, trailingSilenceMs: 0, speechMs: 0)
        }
        func clearSpeechCounter() {}
        func reset() {}
        func regions(in samples: [Float]) async throws -> [SpeechRegion] {
            let ms = samples.count * 1000 / Audio.sampleRate
            return [SpeechRegion(startMs: 3_000, endMs: ms - 2_000)]
        }
    }

    func testTheRangeEdgesAreTheDecodeEdgesWhateverTheDetectorHeard() async throws {
        let source = ArrayPCM([Float](repeating: 0.1, count: Audio.sampleRate * 120))
        let report = try await OfflinePipeline.transcribeRange(
            SpeechRegion(startMs: 60_000, endMs: 70_000),
            in: source, using: LateVAD(), asr: FakeRecognizer(),
            language: "tl", prompt: nil
        )
        let first = try XCTUnwrap(report.tokens.first)
        let last = try XCTUnwrap(report.tokens.last)
        // The fake speaks one word per second from the window's start, which
        // is 200 ms before the range: that first word is kept, because most
        // of it lies inside the range.
        XCTAssertEqual(first.startMs, 60_000 - OfflinePipeline.padMs, "the first word of the turn was decoded")
        XCTAssertGreaterThan(last.startMs, 68_000, "the last seconds of the turn were decoded")
    }

    func testAnEmptyRangeDecodesNothing() async throws {
        let source = ArrayPCM([Float](repeating: 0.1, count: Audio.sampleRate * 10))
        let report = try await OfflinePipeline.transcribeRange(
            SpeechRegion(startMs: 5_000, endMs: 5_000),
            in: source, using: SilentVAD(), asr: FakeRecognizer(),
            language: "tl", prompt: nil
        )
        XCTAssertEqual(report.windowCount, 0)
        XCTAssertTrue(report.tokens.isEmpty)
    }
}

final class TranscriptionQueueCancellationTests: XCTestCase {
    func testCancellingAQueuedJobEmitsCancelledAndFinished() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let queue = TranscriptionQueue(engines: EngineHost(modelsDirectory: scratch))
        // Hold the pump so this exercises cancellation before a task exists --
        // the path that used to remove the job silently and leave the UI stuck.
        await queue.setLiveActive(true)
        let id = UUID()
        await queue.enqueue(TranscriptionJob(
            id: id, title: "Queued", sourceURL: nil,
            cacheURL: scratch.appendingPathComponent("queued.wav"),
            modelId: "unused", language: "tl", discardCacheWhenDone: false
        ))
        await queue.cancel(id)

        var iterator = queue.events.makeAsyncIterator()
        var sawCancelled = false
        var sawFinished = false
        for _ in 0..<4 {
            switch await iterator.next() {
            case .stage(let eventId, let status, _) where eventId == id && status == .cancelled:
                sawCancelled = true
            case .finished(let eventId) where eventId == id:
                sawFinished = true
            default:
                break
            }
        }

        XCTAssertTrue(sawCancelled)
        XCTAssertTrue(sawFinished)
        let busy = await queue.isBusy
        XCTAssertFalse(busy)
    }
}
