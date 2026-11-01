import Foundation
import Testing
import TranscriberCore
@testable import TranscriberEngine

/// The benchmark's own instruments. A number that goes into docs/BENCHMARKS.md
/// is only as good as the code that produced it, so the arithmetic is pinned
/// here with values small enough to check by hand.
@Suite("Run metrics")
struct RunMetricsTests {

    // MARK: order statistics

    @Test("Percentiles interpolate linearly, as numpy and eval/bench_runs.py do")
    func percentiles() {
        let values: [Double] = [10, 20, 30, 40]
        #expect(RunStats.percentile(values, 0) == 10)
        #expect(RunStats.percentile(values, 1) == 40)
        #expect(RunStats.percentile(values, 0.5) == 25)
        // position 0.95 * 3 = 2.85 -> 30 + 0.85 * 10
        #expect(abs((RunStats.percentile(values, 0.95) ?? 0) - 38.5) < 1e-9)
        #expect(RunStats.percentile([7], 0.95) == 7)
        #expect(RunStats.percentile([], 0.5) == nil)
        // Order of the input must not matter.
        #expect(RunStats.percentile([40, 10, 30, 20], 0.5) == 25)
    }

    // MARK: commit latency

    @Test("Commit latency is the clock at commit minus the word's end")
    func commitLatency() throws {
        var tracker = CommitLatencyTracker()
        #expect(tracker.summary == nil)
        tracker.record([Token(text: " a", startMs: 0, endMs: 1_000),
                        Token(text: " b", startMs: 1_000, endMs: 2_000)], atMs: 3_000)
        tracker.record([Token(text: " c", startMs: 2_000, endMs: 4_000)], atMs: 7_000)
        let summary = try #require(tracker.summary)
        // Latencies: 2000, 1000, 3000.
        #expect(summary.words == 3)
        #expect(summary.minMs == 1_000)
        #expect(summary.maxMs == 3_000)
        #expect(summary.medianMs == 2_000)
        #expect(summary.meanMs == 2_000)
        #expect(summary.aheadOfAudio == 0)
    }

    @Test("A word that ends after the audio fed so far is counted, not hidden")
    func wordAheadOfAudio() throws {
        var tracker = CommitLatencyTracker()
        tracker.record([Token(text: " x", startMs: 0, endMs: 5_500)], atMs: 5_000)
        let summary = try #require(tracker.summary)
        #expect(summary.aheadOfAudio == 1)
        #expect(summary.minMs == -500)
    }

    // MARK: per-decode timing

    @Test("Per-decode summary keeps the per-call distribution that totals hide")
    func decodeTimingSummary() throws {
        let samples = [
            DecodeSample(audioMs: 10_000, inferMs: 500, wallMs: 600),
            DecodeSample(audioMs: 10_000, inferMs: 700, wallMs: 800),
            DecodeSample(audioMs: 10_000, inferMs: 3_000, wallMs: 3_100),
        ]
        let summary = try #require(DecodeTimingSummary(samples: samples))
        #expect(summary.calls == 3)
        #expect(summary.maxInferMs == 3_000)
        #expect(summary.maxWallMs == 3_100)
        #expect(summary.medianInferMs == 700)
        // 4200 ms of inference over 30000 ms of audio.
        #expect(abs(summary.inferRtf - 0.14) < 1e-9)
        // 4500 ms of wall time over the same audio: wall exceeds infer.
        #expect(abs(summary.wallRtf - 0.15) < 1e-9)
        #expect(summary.wallRtf > summary.inferRtf)
        #expect(DecodeTimingSummary(samples: []) == nil)
    }

    @Test("The recorder forwards every call unchanged and times each one")
    func timedRecognizerForwards() async throws {
        let inner = SlowRecognizer(delayMs: 40, inferMs: 25)
        let timed = TimedRecognizer(wrapping: inner)
        #expect(await timed.loadedModel == "slow")

        let request = ASRRequest(samples: [Float](repeating: 0, count: 16_000 * 3),
                                 language: "tl", prompt: nil, wordTimestamps: true)
        let first = try await timed.transcribe(request)
        let second = try await timed.transcribe(request)

        // Forwarded, not altered.
        #expect(first.audioMs == 3_000)
        #expect(first.inferMs == 25)
        #expect(first.tokens == second.tokens)
        #expect(await inner.callCount == 2)

        let samples = await timed.samples
        #expect(samples.count == 2)
        for sample in samples {
            #expect(sample.audioMs == 3_000)
            #expect(sample.inferMs == 25)
            // The wall clock saw the 40 ms the model's own number leaves out.
            #expect(sample.wallMs >= 35, "wall \(sample.wallMs) ms")
        }
        let summary = try #require(await timed.summary)
        #expect(summary.calls == 2)
        #expect(summary.wallRtf > summary.inferRtf)
    }

    @Test("A failing decode is passed through and is not recorded as a sample")
    func timedRecognizerPropagatesFailure() async {
        let timed = TimedRecognizer(wrapping: SlowRecognizer(delayMs: 0, inferMs: 1, fails: true))
        let request = ASRRequest(samples: [Float](repeating: 0, count: 16_000),
                                 language: "tl", prompt: nil, wordTimestamps: true)
        await #expect(throws: (any Error).self) { try await timed.transcribe(request) }
        #expect(await timed.samples.isEmpty)
    }

    // MARK: memory

    @Test("A snapshot sees a 192 MB heap allocation, and the peak never trails the current footprint")
    func memorySnapshotTracksDirtyHeap() {
        let before = MemorySnapshot.current(stage: "before")
        #expect(before.physFootprintMB > 0, "task_info failed")
        #expect(before.lifetimePeakFootprintMB >= before.physFootprintMB - 1)

        // Touch every page: untouched anonymous pages are not in the footprint.
        let count = 192 * 1024 * 1024
        var heap = [UInt8](repeating: 0, count: count)
        for index in stride(from: 0, to: count, by: 4096) { heap[index] = 1 }
        let during = MemorySnapshot.current(stage: "during")
        #expect(heap[4096] == 1)   // keeps the allocation alive past the snapshot
        #expect(during.physFootprintMB - before.physFootprintMB >= 150,
                "grew \(during.physFootprintMB - before.physFootprintMB) MB")
        #expect(during.lifetimePeakFootprintMB >= during.physFootprintMB - 1)
        #expect(during.stage == "during")
    }

    @Test("Neural memory is reported apart from the footprint and never negative")
    func neuralMemoryIsSeparate() {
        let snapshot = MemorySnapshot.current(stage: "now")
        // This test process loads no model, so it owns no Neural Engine memory
        // to speak of; the point is that the fields exist, are sane, and the
        // peak never trails the current value.
        #expect(snapshot.neuralMB >= 0)
        #expect(snapshot.neuralPeakMB >= snapshot.neuralMB)
    }

    @Test("A snapshot round-trips through the JSON the CLI writes")
    func memorySnapshotCodable() throws {
        let snapshot = MemorySnapshot(stage: "afterModelLoad", physFootprintMB: 300,
                                      lifetimePeakFootprintMB: 410, residentMB: 900,
                                      internalMB: 200, externalMB: 700, compressedMB: 5,
                                      neuralMB: 1_581, neuralPeakMB: 1_581)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(MemorySnapshot.self, from: data) == snapshot)
    }
}

/// A recognizer with a fixed, visible cost and no model.
private actor SlowRecognizer: SpeechRecognizing {
    let delayMs: Int
    let inferMs: Int
    let fails: Bool
    private(set) var callCount = 0

    init(delayMs: Int, inferMs: Int, fails: Bool = false) {
        self.delayMs = delayMs
        self.inferMs = inferMs
        self.fails = fails
    }

    var loadedModel: String? { "slow" }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() async {}

    struct Failure: Error {}

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        callCount += 1
        try await Task.sleep(for: .milliseconds(delayMs))
        if fails { throw Failure() }
        return ASROutput(tokens: [Token(text: " hi", startMs: 0, endMs: 500)],
                         audioMs: request.samples.count * 1000 / 16_000, inferMs: inferMs)
    }
}
