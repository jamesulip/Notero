import XCTest
@testable import TranscriberCore

/// A seedable generator, so a failing scenario can be replayed from its seed.
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

/// The commit contract, checked against hundreds of random scripts instead of a
/// few hand-built ones: whatever the recognizer says, in whatever order and
/// however wrong, once a word is committed it never changes, never appears
/// twice, never moves, and the committed timeline only runs forward.
///
/// The recognizer here is a script: ground-truth words that every pass hears
/// with random dropped words, random substituted words, timing jitter and the
/// occasional empty pass, over windows that anchor to the last commit and
/// slide when the cap is reached, with forced commits and boundary flushes
/// mixed in. Each ground-truth word is `w<index>` and each substitute is
/// `x<n>`, unique, so a repeated or reordered commit is visible in the text.
final class CommitImmutabilityPropertyTests: XCTestCase {

    private struct Truth {
        var text: String
        var startMs: Int
        var endMs: Int
    }

    private func truth(_ rng: inout SplitMix64) -> (words: [Truth], endMs: Int) {
        var words: [Truth] = []
        var t = Int.random(in: 100...600, using: &rng)
        var index = 0
        let utterances = Int.random(in: 4...12, using: &rng)
        for _ in 0..<utterances {
            for _ in 0..<Int.random(in: 3...14, using: &rng) {
                let duration = Int.random(in: 140...600, using: &rng)
                words.append(Truth(text: "w\(index)", startMs: t, endMs: t + duration))
                index += 1
                t += duration + Int.random(in: 30...250, using: &rng)
            }
            t += Int.random(in: 300...2_500, using: &rng)   // a pause
        }
        return (words, t + 500)
    }

    /// What one pass hears of the window `windowStart..<windowEnd`, on the
    /// session timeline.
    private func hear(_ words: [Truth], windowStart: Int, windowEnd: Int,
                      substitutes: inout Int, rng: inout SplitMix64,
                      dropP: Double, substituteP: Double) -> [Token] {
        var heard: [Token] = []
        for word in words where word.endMs > windowStart && word.startMs < windowEnd {
            if rng.chance(dropP) { continue }
            var text = word.text
            if rng.chance(substituteP) { substitutes += 1; text = "x\(substitutes)" }
            // Jitter small enough that adjacent words keep their order.
            let start = Swift.max(windowStart, word.startMs + Int.random(in: -50...50, using: &rng))
            let end = Swift.min(windowEnd, word.endMs + Int.random(in: -50...50, using: &rng))
            heard.append(Token(text: " " + text, startMs: start, endMs: Swift.max(end, start + 1),
                               confidence: 0.9))
        }
        return heard
    }

    /// The invariants, after every operation. `seed` names the scenario.
    private func check(_ la: LocalAgreement, against before: [Token], seed: UInt64,
                       step: String, file: StaticString = #filePath, line: UInt = #line) {
        let now = la.committed
        let tag = "seed \(seed), \(step)"
        XCTAssertGreaterThanOrEqual(now.count, before.count, "committed text shrank: \(tag)",
                                    file: file, line: line)
        guard now.count >= before.count else { return }
        XCTAssertEqual(Array(now.prefix(before.count)), before,
                       "a committed token changed after it was committed: \(tag)",
                       file: file, line: line)
        for index in before.count..<now.count {
            let token = now[index]
            XCTAssertGreaterThanOrEqual(token.endMs, token.startMs, "inverted token: \(tag)",
                                        file: file, line: line)
            if index > 0 {
                XCTAssertGreaterThanOrEqual(token.startMs, now[index - 1].endMs,
                                            "committed timeline went backwards: \(tag)",
                                            file: file, line: line)
            }
        }
        let texts = now.map { $0.text.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(Set(texts).count, texts.count,
                       "a word was committed twice: \(tag): \(texts.joined(separator: " "))",
                       file: file, line: line)
        // Ground-truth words keep their order. A reordered commit is a rewrite.
        let indices = texts.compactMap { $0.hasPrefix("w") ? Int($0.dropFirst()) : nil }
        XCTAssertEqual(indices, indices.sorted(), "committed words out of order: \(tag)",
                       file: file, line: line)
    }

    func testRandomScriptsNeverRewriteReorderOrDuplicateCommittedText() {
        var scenariosWithCommits = 0
        var forcedScenarios = 0
        var committedWords = 0
        var headSkips = 0
        for seed in UInt64(1)...400 {
            var rng = SplitMix64(seed: seed)
            let (words, totalMs) = truth(&rng)
            let agreement = rng.chance(0.25) ? 3 : 2
            let dropP = Double.random(in: 0...0.15, using: &rng)
            let substituteP = Double.random(in: 0...0.25, using: &rng)
            // A third of the scripts run head-tolerant, which commits on weaker evidence
            // and so has the most to prove about immutability.
            let tolerance = agreement == 2 && rng.chance(0.4) ? Int.random(in: 1...3, using: &rng) : 0
            let la = LocalAgreement(agreement: agreement, headTolerance: tolerance, headMinRun: 3)
            var substitutes = 0
            var now = 0
            var forced = false

            while now < totalMs {
                // Irregular spacing: a slow decode or a dropped hop stretches it.
                now = Swift.min(totalMs, now + Int.random(in: 500...3_200, using: &rng))
                var windowStart = Swift.max(0, la.committedEndMs - 1_500)   // pre-roll
                if now - windowStart > 16_500 { windowStart = now - 16_500 }
                la.ceilingMs = now

                var before = la.committed
                if windowStart > la.committedEndMs {
                    if !la.forceCommit(before: windowStart).isEmpty { forced = true }
                    check(la, against: before, seed: seed, step: "forceCommit at \(now) ms")
                    before = la.committed
                }

                let heard: [Token]
                if rng.chance(0.04) {
                    heard = []                       // an empty pass
                } else {
                    heard = hear(words, windowStart: windowStart, windowEnd: now,
                                 substitutes: &substitutes, rng: &rng,
                                 dropP: dropP, substituteP: substituteP)
                }
                la.insert(heard)
                check(la, against: before, seed: seed, step: "insert at \(now) ms")
                before = la.committed

                if rng.chance(0.08) {
                    // A confirmed pause: the tail is committed, sometimes cut where speech ended.
                    let limit: Int? = rng.chance(0.5) ? Swift.max(0, now - 700) : nil
                    la.flush(notAfter: limit)
                    check(la, against: before, seed: seed, step: "flush at \(now) ms")
                }
            }
            let before = la.committed
            la.ceilingMs = totalMs
            la.flush()
            check(la, against: before, seed: seed, step: "final flush")

            headSkips += la.headSkips
            if !la.committed.isEmpty { scenariosWithCommits += 1 }
            if forced { forcedScenarios += 1 }
            committedWords += la.committed.count
        }
        // The property is only worth anything if the scripts exercised it.
        XCTAssertGreaterThanOrEqual(scenariosWithCommits, 380, "scripts did not commit anything")
        XCTAssertGreaterThanOrEqual(forcedScenarios, 20, "scripts never forced a commit")
        XCTAssertGreaterThan(committedWords, 10_000)
        XCTAssertGreaterThan(headSkips, 50, "the head-tolerant path was never exercised")
    }
}
