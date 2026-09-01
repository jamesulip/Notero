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
    private(set) var calls: [(samples: Int, attempt: Int)] = []

    init(refuse: @escaping Refusal = { _, _ in false }) {
        self.refuse = refuse
    }

    var loadedModel: String? { "fake" }
    var isLoaded: Bool { true }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() {}

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
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
