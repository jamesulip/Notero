import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The offline pass tries a refused window again on different audio before it
/// lets Whisper roll dice (FINDINGS 15).
///
/// The first 24.9 s of the Taglish fixture is refused at its first token by
/// every greedy decode. Whisper's own ladder then re-samples it, at random, and
/// returned good text on some runs and invented filler on others. The same
/// audio with 250 ms of silence in front of it passes greedy, deterministically.
final class PipelineDeterministicRetryTests: XCTestCase {

    private func source(seconds: Int) -> ArrayPCM {
        ArrayPCM([Float](repeating: 0.1, count: Audio.sampleRate * seconds))
    }

    private func window(_ start: Int, _ end: Int) -> SpeechRegion {
        SpeechRegion(startMs: start, endMs: end)
    }

    private let windowSamples = Audio.sampleRate * 25
    private static func leadSamples(_ ms: Int) -> Int { ms * Audio.sampleRate / 1000 }
    private func leadSamples(_ ms: Int) -> Int { Self.leadSamples(ms) }

    private static let invented = DecodeQuality(avgLogProb: -1.2, compressionRatio: 1.5,
                                                isRepetitive: false, isLowConfidence: true)

    /// What the dice return when they are rolled: plausible, wrong, and with
    /// nothing the backend's gates would catch.
    private static func filler(_ request: ASRRequest) -> ASROutput {
        ASROutput(tokens: [Token(text: " Thank", startMs: 0, endMs: 300),
                           Token(text: " you", startMs: 300, endMs: 600)],
                  audioMs: request.samples.count * 1000 / Audio.sampleRate, inferMs: 1,
                  detectedLanguage: "tl", quality: nil)
    }

    private static func words(_ request: ASRRequest, shiftedBy lead: Int) -> ASROutput {
        ASROutput(tokens: [Token(text: " kumusta", startMs: lead + 500, endMs: lead + 900, confidence: 0.9),
                           Token(text: " kayo", startMs: lead + 900, endMs: lead + 1_200, confidence: 0.9)],
                  audioMs: request.samples.count * 1000 / Audio.sampleRate, inferMs: 1,
                  detectedLanguage: "tl")
    }

    private static func refusal(_ request: ASRRequest) -> ASROutput {
        ASROutput(tokens: [], audioMs: request.samples.count * 1000 / Audio.sampleRate, inferMs: 1)
    }

    func testARefusedWindowGetsALeadInOfSilenceBeforeAnyRandomSampling() async throws {
        // Fails on the old pipeline, which sent the window to Whisper's
        // sampled ladder and took the filler it got back.
        let base = windowSamples
        let asr = FakeRecognizer(script: { request in
            guard request.sampling == .greedyOnly else { return Self.filler(request) }
            return request.samples.count == base
                ? Self.refusal(request)
                : Self.words(request, shiftedBy: 250)
        })
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 60), windows: [window(20_000, 45_000)],
            using: asr, language: "tl", prompt: nil
        )

        XCTAssertEqual(report.tokens.map(\.text), [" kumusta", " kayo"])
        XCTAssertEqual(report.tokens.first?.startMs, 20_500,
                       "the lead-in has to come back off the timestamps")
        XCTAssertEqual(report.tokens.last?.endMs, 21_200)
        XCTAssertEqual(report.retriedWindows, 1)
        XCTAssertEqual(report.droppedWindows, 0)
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.sampling), [.greedyOnly, .greedyOnly],
                       "nothing was sampled")
        XCTAssertEqual(calls.map(\.samples), [base, base + leadSamples(250)])
    }

    func testAGreedyDecodeThatPassesIsAcceptedAsItIs() async throws {
        // The path that already worked must not change: one greedy decode, no
        // lead-in, no sampling, and the words exactly as the recognizer gave them.
        let asr = FakeRecognizer()
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 40), windows: [window(0, 10_000)],
            using: asr, language: "tl", prompt: nil
        )
        XCTAssertEqual(report.tokens.count, 10)
        XCTAssertEqual(report.retriedWindows, 0)
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.sampling), [.greedyOnly])
        XCTAssertEqual(calls.map(\.samples), [Audio.sampleRate * 10])
    }

    func testWordsHeardInsideTheLeadInAreDiscardedBecauseItIsSilence() async throws {
        let base = windowSamples
        let asr = FakeRecognizer(script: { request in
            guard request.sampling == .greedyOnly else { return Self.filler(request) }
            guard request.samples.count > base else { return Self.refusal(request) }
            var out = Self.words(request, shiftedBy: 250)
            out.tokens.insert(Token(text: " Thank", startMs: 20, endMs: 240), at: 0)
            out.tokens.insert(Token(text: " you", startMs: 240, endMs: 400), at: 1)
            return out
        })
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 60), windows: [window(20_000, 45_000)],
            using: asr, language: "tl", prompt: nil
        )
        // " Thank" ended inside the silence; " you" straddles its end and stays.
        XCTAssertEqual(report.tokens.map(\.text), [" you", " kumusta", " kayo"])
        XCTAssertEqual(report.tokens.first?.startMs, 20_000)
    }

    func testLeadInsAreOnlyTriedWhenTheRefusalHadNoTextAtAll() async throws {
        // A decode that produced text and failed a gate is a hard window, not a
        // bad onset. It goes to the sampled ladder, as before, and does not
        // cost a second full decode.
        let asr = FakeRecognizer(script: { request in
            request.sampling == .greedyOnly
                ? ASROutput(tokens: [Token(text: " mumble", startMs: 0, endMs: 500)],
                            audioMs: 25_000, inferMs: 1, quality: Self.invented)
                : nil
        })
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 60), windows: [window(20_000, 45_000)],
            using: asr, language: "tl", prompt: nil
        )
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.sampling), [.greedyOnly, .resampleOnly])
        XCTAssertEqual(calls.map(\.samples), [windowSamples, windowSamples])
        XCTAssertEqual(report.droppedWindows, 0)
        XCTAssertFalse(report.tokens.isEmpty)
    }

    func testAGreedyRepetitionLoopIsNotAcceptedAndGoesToTheSampledLadder() async throws {
        // Whisper's repetition gate fails a greedy decode the same way: the
        // ladder would have moved on to a warmer attempt, and so does this.
        let loop = DecodeQuality(avgLogProb: -0.9, compressionRatio: 6.9,
                                 isRepetitive: true, isLowConfidence: false)
        let asr = FakeRecognizer(script: { request in
            request.sampling == .greedyOnly
                ? ASROutput(tokens: [Token(text: " Thank", startMs: 0, endMs: 300),
                                     Token(text: " you", startMs: 300, endMs: 600)],
                            audioMs: 25_000, inferMs: 1, quality: loop)
                : nil
        })
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 60), windows: [window(20_000, 45_000)],
            using: asr, language: "tl", prompt: nil
        )
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.sampling), [.greedyOnly, .resampleOnly],
                       "text that failed a gate is not a first-token refusal: no lead-in")
        XCTAssertFalse(report.tokens.contains { $0.text.contains("Thank") })
        XCTAssertEqual(report.droppedWindows, 0)
    }

    func testLeadInRetriesAreBoundedAndThenTheSampledLadderTakesOver() async throws {
        let base = windowSamples
        let asr = FakeRecognizer(script: { request in
            request.sampling == .greedyOnly ? Self.refusal(request) : nil
        })
        let report = try await OfflinePipeline.transcribe(
            source: source(seconds: 60), windows: [window(20_000, 45_000)],
            using: asr, language: "tl", prompt: nil
        )
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.sampling),
                       [.greedyOnly, .greedyOnly, .greedyOnly, .resampleOnly])
        XCTAssertEqual(calls.map(\.samples),
                       [base, base + leadSamples(250), base + leadSamples(450), base])
        XCTAssertEqual(report.droppedWindows, 0)
        XCTAssertEqual(report.retriedWindows, 0, "attempt 0 of the ladder is not a retry")
    }

    // MARK: - What the engine asks WhisperKit for

    private func temperatures(_ request: ASRRequest) -> [Float] {
        let s = WhisperEngine.sampling(for: request)
        return (0...s.fallbackCount).map { s.temperature + Float($0) * 0.2 }
    }

    func testTheStandardLadderIsUnchanged() {
        // temperatureFallbackCount = 2 + 2 * attempt (FINDINGS 2 and 9).
        for attempt in 0..<3 {
            let s = WhisperEngine.sampling(for: ASRRequest(samples: [], decodeAttempt: attempt))
            XCTAssertEqual(s.temperature, Float(attempt) * 0.2)
            XCTAssertEqual(s.fallbackCount, 2 + attempt * 2)
        }
    }

    func testGreedyThenResampleIsExactlyTheStandardLadderSplitInTwo() {
        let standard = temperatures(ASRRequest(samples: []))
        let greedy = temperatures(ASRRequest(samples: [], sampling: .greedyOnly))
        let resample = temperatures(ASRRequest(samples: [], sampling: .resampleOnly))
        XCTAssertEqual(greedy, [0])
        XCTAssertEqual(greedy + resample, standard)
        // From the second attempt on the ladder never started at zero.
        for attempt in 1..<3 {
            XCTAssertEqual(
                temperatures(ASRRequest(samples: [], decodeAttempt: attempt, sampling: .resampleOnly)),
                temperatures(ASRRequest(samples: [], decodeAttempt: attempt))
            )
        }
    }
}
