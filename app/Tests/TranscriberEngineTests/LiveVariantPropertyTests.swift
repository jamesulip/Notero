import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The latency experiment (`eval/live_latency.py`) varies one setting of the live
/// path at a time. Whatever it varies, committed text must only ever be appended
/// to, so each variant runs the commit-invariant monitor over random scripted
/// sessions (a recognizer that drops, substitutes and repeats words, pauses that do
/// and do not end an utterance, slow decodes that drop hops). The control is in the
/// list so a failure of the monitor itself shows on the production settings first.
@MainActor
final class LiveVariantPropertyTests: XCTestCase {

    private struct Variant {
        var name: String
        var config: SessionConfig
    }

    private func base(
        context: Int = 15_000, hop: Int = 1_500, silence: Int = 700, preRoll: Int = 1_500,
        adaptive: Bool = false, headTolerance: Int = 0, headMinRun: Int = 3
    ) -> SessionConfig {
        SessionConfig(contextMs: context, hopMs: hop, silenceBoundaryMs: silence, agreement: 2,
                      language: "tl", prompt: nil, useNeuralVAD: false, preRollMs: preRoll,
                      adaptiveHop: adaptive, minHopMs: 1_000,
                      headTolerance: headTolerance, headMinRun: headMinRun)
    }

    private var variants: [Variant] {
        [
            Variant(name: "control", config: base()),
            Variant(name: "head-tolerant 3/3", config: base(headTolerance: 3)),
            Variant(name: "head-tolerant 1/2", config: base(headTolerance: 1, headMinRun: 2)),
            Variant(name: "silence boundary 500", config: base(silence: 500)),
            Variant(name: "pre-roll 3000", config: base(preRoll: 3_000)),
            Variant(name: "pre-roll 0", config: base(preRoll: 0)),
            Variant(name: "hop 1250", config: base(hop: 1_250)),
            Variant(name: "adaptive hop", config: base(adaptive: true)),
            Variant(name: "context 12000", config: base(context: 12_000)),
            Variant(name: "context 6000", config: base(context: 6_000)),
        ]
    }

    private func script(seed: UInt64) -> (words: [SpokenWord], speech: [Range<Int>], pauses: [Range<Int>], totalMs: Int) {
        var rng = SplitMix64(seed: seed)
        var words: [SpokenWord] = []
        var speech: [Range<Int>] = []
        var pauses: [Range<Int>] = []
        var t = Int.random(in: 200...900, using: &rng)
        var index = 0
        for _ in 0..<Int.random(in: 3...6, using: &rng) {
            let start = t
            for _ in 0..<Int.random(in: 3...9, using: &rng) {
                let duration = Int.random(in: 160...520, using: &rng)
                words.append(SpokenWord(text: "w\(index)", startMs: t, endMs: t + duration))
                index += 1
                t += duration + Int.random(in: 40...200, using: &rng)
            }
            speech.append(start..<t)
            let pause = Int.random(in: 200...2_500, using: &rng)
            if pause >= 1_100 { pauses.append(t..<(t + pause)) }
            t += pause
        }
        return (words, speech, pauses, t + 1_500)
    }

    func testEveryVariantOnlyEverAppendsToCommittedText() async throws {
        for variant in variants {
            var committedWords = 0
            var boundaries = 0
            var hopsDropped = 0
            for seed in UInt64(1)...14 {
                var rng = SplitMix64(seed: seed &* 31)
                let scene = script(seed: seed)
                let asr = ChaosRecognizer(
                    words: scene.words, pauses: scene.pauses, seed: seed,
                    dropP: Double.random(in: 0...0.12, using: &rng),
                    substituteP: Double.random(in: 0...0.2, using: &rng),
                    emptyP: Double.random(in: 0...0.08, using: &rng),
                    phantomP: Double.random(in: 0.05...0.4, using: &rng))
                let vad = ScriptedVAD(speech: scene.speech)
                let decoder = LiveDecoder(config: variant.config, recognizer: asr, vad: vad)
                let recorder = LiveReplayRecorder(decoder: decoder, realtime: false)
                recorder.begin()

                var clock = 0
                while clock < scene.totalMs {
                    if rng.chance(0.06) {
                        await asr.hold()
                        for _ in 0..<Int.random(in: 4...22, using: &rng) where clock < scene.totalMs {
                            recorder.noteFed(clock + 100)
                            decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
                            clock += 100
                            await decoder.settleVAD()
                        }
                        await asr.release()
                        await decoder.drain()
                    } else {
                        recorder.noteFed(clock + 100)
                        decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
                        clock += 100
                        await decoder.drain()
                    }
                }
                await decoder.finish()
                let trace = recorder.finish()

                XCTAssertTrue(trace.invariants.holds,
                              "\(variant.name), seed \(seed): \(trace.invariants.violations)")
                XCTAssertEqual(trace.invariants.words, decoder.committed.count,
                               "\(variant.name), seed \(seed)")
                let ends = trace.commits.flatMap(\.wordEndMs)
                XCTAssertEqual(ends, decoder.committed.map(\.endMs), "\(variant.name), seed \(seed)")
                committedWords += decoder.committed.count
                boundaries += decoder.stats.boundaries
                hopsDropped += decoder.stats.droppedHops
            }
            // A property test that never reaches the interesting states proves nothing.
            XCTAssertGreaterThan(committedWords, 200, "\(variant.name) committed almost nothing")
            XCTAssertGreaterThan(boundaries, 10, "\(variant.name) never closed an utterance")
            XCTAssertGreaterThan(hopsDropped, 0, "\(variant.name) never dropped a hop")
        }
    }
}
