import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A seedable generator, so a failing scenario can be replayed from its seed.
/// (Also in TranscriberCoreTests; test targets cannot share a file.)
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

/// A recognizer that is wrong in random, repeatable ways: drops words, swaps a
/// word for one nobody said, jitters every timing, answers nothing, and
/// sometimes says the last word again, out of the 30 s padding or out of a long
/// pause, which is what Whisper does (FINDINGS 11, 12). The ground truth is
/// `w<n>` and substitutes are `x<n>`, all unique, so a word committed twice,
/// out of order, or read out of silence shows in the text: a phantom repeats a
/// real word, and a repeated word is a duplicate.
actor ChaosRecognizer: SpeechRecognizing {
    private var rng: SplitMix64
    private let words: [SpokenWord]
    /// Pauses long enough for the VAD to confirm, where the model may repeat the last word.
    private let pauses: [Range<Int>]
    private let dropP: Double
    private let substituteP: Double
    private let emptyP: Double
    private let phantomP: Double
    private var substitutes = 0
    private(set) var calls = 0

    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(words: [SpokenWord], pauses: [Range<Int>], seed: UInt64, dropP: Double,
         substituteP: Double, emptyP: Double, phantomP: Double) {
        self.words = words
        self.pauses = pauses
        self.rng = SplitMix64(seed: seed &* 7919)
        self.dropP = dropP
        self.substituteP = substituteP
        self.emptyP = emptyP
        self.phantomP = phantomP
    }

    var loadedModel: String? { "chaos" }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() {}

    func hold() { held = true }
    func release() {
        held = false
        let resumed = waiters
        waiters = []
        for waiter in resumed { waiter.resume() }
    }

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        let startMs = OraclePCM.startMs(of: request.samples)
        let durationMs = request.samples.count / 16
        calls += 1
        if held { await withCheckedContinuation { waiters.append($0) } }

        var tokens: [Token] = []
        if !rng.chance(emptyP) {
            for word in words where word.endMs > startMs && word.startMs < startMs + durationMs {
                if rng.chance(dropP) { continue }
                var text = word.text
                if rng.chance(substituteP) { substitutes += 1; text = "x\(substitutes)" }
                let start = Swift.max(0, word.startMs - startMs + Int.random(in: -50...50, using: &rng))
                let end = Swift.min(durationMs, word.endMs - startMs + Int.random(in: -50...50, using: &rng))
                tokens.append(Token(text: " " + text, startMs: start,
                                    endMs: Swift.max(end, start + 1), confidence: 0.9))
            }
            // The last word, said again out of the padding past the audio.
            if rng.chance(phantomP), let last = tokens.last {
                tokens.append(Token(text: last.text, startMs: durationMs + 4_000,
                                    endMs: durationMs + 4_400, confidence: 0.9))
            }
            // And out of a pause: the word before it, repeated inside the silence.
            for pause in pauses where rng.chance(phantomP) {
                let start = pause.lowerBound + 400 - startMs
                guard start >= 0, start + 100 < durationMs,
                      let spoken = words.last(where: { $0.endMs <= pause.lowerBound }),
                      spoken.endMs > startMs else { continue }
                tokens.append(Token(text: " " + spoken.text, startMs: start,
                                    endMs: Swift.min(durationMs, start + 400), confidence: 0.9))
            }
        }
        return ASROutput(tokens: tokens, audioMs: durationMs, inferMs: 1,
                         detectedLanguage: request.language)
    }
}

/// The commit contract through the whole live schedule: hops, dropped hops,
/// finalization, abandoned finalization, forced commits, the final flush. For
/// each of many random scripts, the committed text at every step is the
/// previous committed text plus new words at the end; no word appears twice or
/// out of order; nothing from the padding is committed; and what the decoder
/// delivered to its consumer is exactly what it holds.
@MainActor
final class LiveDecoderPropertyTests: XCTestCase {

    private func check(_ committed: [Token], against before: [Token], seed: UInt64, step: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let tag = "seed \(seed), \(step)"
        guard committed.count >= before.count else {
            XCTFail("committed text shrank: \(tag)", file: file, line: line)
            return
        }
        XCTAssertEqual(Array(committed.prefix(before.count)), before,
                       "a committed token changed after it was committed: \(tag)",
                       file: file, line: line)
        for index in max(1, before.count)..<max(1, committed.count) {
            XCTAssertGreaterThanOrEqual(committed[index].startMs, committed[index - 1].endMs,
                                        "committed timeline went backwards: \(tag)",
                                        file: file, line: line)
        }
        let texts = committed.map { $0.text.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(Set(texts).count, texts.count,
                       "a word was committed twice: \(tag): \(texts.joined(separator: " "))",
                       file: file, line: line)
        let indices = texts.compactMap { $0.hasPrefix("w") ? Int($0.dropFirst()) : nil }
        XCTAssertEqual(indices, indices.sorted(), "committed words out of order: \(tag)",
                       file: file, line: line)
    }

    func testRandomScriptsNeverRewriteReorderOrDuplicateCommittedText() async throws {
        var totals = SessionStats()
        var committedWords = 0
        var scenariosThatCommitted = 0

        for seed in UInt64(1)...60 {
            var rng = SplitMix64(seed: seed)
            // Utterances of 3-9 words, 0.2-2.5 s apart: some pauses end an utterance, some do not.
            var words: [SpokenWord] = []
            var utterances: [(range: Range<Int>, pause: Int, muted: Bool)] = []
            var t = Int.random(in: 200...900, using: &rng)
            var index = 0
            for _ in 0..<Int.random(in: 3...6, using: &rng) {
                let utteranceStart = t
                for _ in 0..<Int.random(in: 3...9, using: &rng) {
                    let duration = Int.random(in: 160...520, using: &rng)
                    words.append(SpokenWord(text: "w\(index)", startMs: t, endMs: t + duration))
                    index += 1
                    t += duration + Int.random(in: 40...200, using: &rng)
                }
                let pause = Int.random(in: 200...2_500, using: &rng)
                // A long stretch in which nobody speaks but the voice detector still hears
                // speech (a cough, a keyboard, a room): hops decode the same words again and
                // again, which is where a phantom at the end of every pass can be agreed on.
                utterances.append((utteranceStart..<t, pause, pause >= 2_000 && rng.chance(0.6)))
                t += pause
            }
            var speech: [Range<Int>] = []
            var pauses: [Range<Int>] = []
            for (k, u) in utterances.enumerated() {
                if k > 0, utterances[k - 1].muted, let last = speech.last {
                    speech[speech.count - 1] = last.lowerBound..<u.range.upperBound
                } else {
                    speech.append(u.range)
                }
                if u.pause >= 1_100, !u.muted { pauses.append(u.range.upperBound..<(u.range.upperBound + u.pause)) }
            }
            let totalMs = t + 1_500

            // One script in four hears everything correctly and always reads a phantom:
            // consecutive passes then agree on whatever is unfiltered, so a filter that
            // stops working commits a duplicate instead of hiding behind disagreement.
            let clean = seed % 4 == 0
            let asr = ChaosRecognizer(
                words: words, pauses: pauses, seed: seed,
                dropP: clean ? 0 : Double.random(in: 0...0.12, using: &rng),
                substituteP: clean ? 0 : Double.random(in: 0...0.2, using: &rng),
                emptyP: clean ? 0 : Double.random(in: 0...0.08, using: &rng),
                phantomP: clean ? 1 : Double.random(in: 0.05...0.4, using: &rng))
            let vad = ScriptedVAD(speech: speech)
            let config = SessionConfig(contextMs: rng.chance(0.3) ? 6_000 : 15_000, hopMs: 1_500,
                                       silenceBoundaryMs: 700, agreement: 2, language: "tl",
                                       prompt: nil, useNeuralVAD: false, preRollMs: 1_500,
                                       adaptiveHop: false, minHopMs: 1_000,
                                       headTolerance: rng.chance(0.5) ? Int.random(in: 1...3, using: &rng) : 0,
                                       headMinRun: 3)
            let decoder = LiveDecoder(config: config, recognizer: asr, vad: vad)
            var delivered: [Token] = []
            decoder.onCommitted = { delivered += $0 }

            var clock = 0
            var snapshot: [Token] = []
            while clock < totalMs {
                if rng.chance(0.06) {
                    // A slow decode: hold the model across several chunks, so hops
                    // are dropped and a finalization may have to wait or be abandoned.
                    await asr.hold()
                    for _ in 0..<Int.random(in: 4...22, using: &rng) where clock < totalMs {
                        decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
                        clock += 100
                        await decoder.settleVAD()
                        check(decoder.committed, against: snapshot, seed: seed, step: "held, \(clock) ms")
                        snapshot = decoder.committed
                    }
                    await asr.release()
                    await decoder.drain()
                } else {
                    decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
                    clock += 100
                    await decoder.drain()
                }
                check(decoder.committed, against: snapshot, seed: seed, step: "\(clock) ms")
                snapshot = decoder.committed
            }
            await decoder.finish()
            check(decoder.committed, against: snapshot, seed: seed, step: "finish")

            XCTAssertEqual(delivered, decoder.committed,
                           "what was delivered is not what the decoder holds: seed \(seed)")
            XCTAssertLessThanOrEqual(decoder.committed.last?.endMs ?? 0, decoder.currentMs,
                                     "a word was timestamped past the audio received: seed \(seed)")

            let s = decoder.stats
            totals.hops += s.hops
            totals.droppedHops += s.droppedHops
            totals.forcedCommits += s.forcedCommits
            totals.boundaries += s.boundaries
            totals.finalizationsAbandoned += s.finalizationsAbandoned
            totals.unagreedTailCommits += s.unagreedTailCommits
            totals.hallucinationsDropped += s.hallucinationsDropped
            totals.emptyResults += s.emptyResults
            committedWords += decoder.committed.count
            if !decoder.committed.isEmpty { scenariosThatCommitted += 1 }
        }

        // A property test that never reaches the interesting states proves nothing.
        XCTAssertGreaterThanOrEqual(scenariosThatCommitted, 56)
        XCTAssertGreaterThan(committedWords, 1_200)
        XCTAssertGreaterThan(totals.droppedHops, 20, "scripts never dropped a hop")
        XCTAssertGreaterThan(totals.forcedCommits, 0, "scripts never forced a commit")
        XCTAssertGreaterThan(totals.boundaries, 50, "scripts never closed an utterance")
        XCTAssertGreaterThan(totals.finalizationsAbandoned, 0, "scripts never abandoned a finalization")
        XCTAssertGreaterThan(totals.unagreedTailCommits, 0, "scripts never committed a tail")
        XCTAssertGreaterThan(totals.hallucinationsDropped, 50, "scripts never offered a phantom")
        XCTAssertGreaterThan(totals.emptyResults, 0, "scripts never returned an empty pass")
    }
}
