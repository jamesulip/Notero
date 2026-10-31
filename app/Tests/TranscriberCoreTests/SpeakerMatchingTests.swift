import XCTest
@testable import TranscriberCore

/// Which new speaker is which old one, on hand-built timelines.
///
/// Every number is a duration in milliseconds on a made-up timeline, so nothing
/// here depends on a model, a clock or the machine.
final class SpeakerMatchingTests: XCTestCase {

    private func span(_ label: String, _ startMs: Int, _ endMs: Int) -> SpeakerSpan {
        SpeakerSpan(speakerId: label, startMs: startMs, endMs: endMs)
    }

    /// One 10 s turn per entry, back to back from zero.
    private func turns(_ labels: [String], length: Int = 10_000) -> [SpeakerSpan] {
        labels.enumerated().map { span($1, $0 * length, ($0 + 1) * length) }
    }

    private func match(_ old: [SpeakerSpan], _ new: [SpeakerSpan]) -> [String: String] {
        SpeakerMatching.match(old: old, new: new)
    }

    // MARK: - The five cases

    func testSwappedLabelsAreMatchedAcrossAndNotByName() {
        let old = turns(["S1", "S2", "S1", "S2", "S1", "S2"])
        let new = turns(["S2", "S1", "S2", "S1", "S2", "S1"])
        XCTAssertEqual(match(old, new), ["S1": "S2", "S2": "S1"])
    }

    func testASpeakerThatDisappearedHasNoHeirAndTheOthersKeepTheirs() {
        // S2 never speaks in the new run, and Ana, who was S3, is numbered S2.
        let old = turns(["S1", "S2", "S3", "S1", "S2", "S3"])
        let new = [span("S1", 0, 10_000), span("S2", 20_000, 30_000),
                   span("S1", 30_000, 40_000), span("S2", 50_000, 60_000)]
        XCTAssertEqual(match(old, new), ["S1": "S1", "S2": "S3"])
    }

    func testANewSpeakerHasNoPredecessor() {
        let old = turns(["S1", "S2", "S1", "S2"]) + [span("S1", 40_000, 41_000)]
        let new = turns(["S1", "S2", "S1", "S2", "S3", "S3"])
        let matched = match(old, new)
        XCTAssertEqual(matched, ["S1": "S1", "S2": "S2"])
        XCTAssertNil(matched["S3"])
    }

    func testTwoSpeakersFusedEvenlyAreNotMatchedToEither() {
        // Maria and Juan trade equal turns; the new run calls both of them S1.
        // Ana, in the second half, is matched.
        let old = turns(["S1", "S2", "S1", "S2", "S3", "S3"])
        let new = [span("S1", 0, 40_000), span("S2", 40_000, 60_000)]
        let matched = match(old, new)
        XCTAssertEqual(matched, ["S2": "S3"])
    }

    func testTwoSpeakersFusedUnevenlyGoToTheOneThatIsMostOfIt() {
        // Maria 60 s, Juan 20 s: three to one, the fused speaker is Maria.
        let old = [span("S1", 0, 60_000), span("S2", 60_000, 80_000), span("S3", 80_000, 120_000)]
        let new = [span("S1", 0, 80_000), span("S2", 80_000, 120_000)]
        XCTAssertEqual(match(old, new), ["S1": "S1", "S2": "S3"])
    }

    func testOneSpeakerSplitEvenlyIsNotMatchedToEitherHalf() {
        let old = [span("S1", 0, 40_000), span("S2", 40_000, 80_000)]
        let new = [span("S1", 0, 20_000), span("S3", 20_000, 40_000), span("S2", 40_000, 80_000)]
        XCTAssertEqual(match(old, new), ["S2": "S2"])
    }

    func testOneSpeakerSplitUnevenlyGoesToTheLargerHalf() {
        let old = [span("S1", 0, 40_000), span("S2", 40_000, 80_000)]
        let new = [span("S1", 0, 30_000), span("S3", 30_000, 40_000), span("S2", 40_000, 80_000)]
        XCTAssertEqual(match(old, new), ["S1": "S1", "S2": "S2"])
    }

    // MARK: - Where it must say nothing

    func testAnUnchangedRunMatchesEachSpeakerToItself() {
        let layout = turns(["S1", "S2", "S3", "S1", "S2", "S3"])
        XCTAssertEqual(match(layout, layout), ["S1": "S1", "S2": "S2", "S3": "S3"])
    }

    func testNothingToMatchAgainstMatchesNothing() {
        XCTAssertEqual(match([], turns(["S1", "S2"])), [:])
        XCTAssertEqual(match(turns(["S1", "S2"]), []), [:])
        XCTAssertEqual(match([], []), [:])
    }

    func testARunOnAnotherPartOfTheTimelineMatchesNothing() {
        // Same audio shifted by an hour: no overlap, so no evidence, so no carry.
        let old = turns(["S1", "S2", "S1", "S2"])
        let new = old.map { span($0.speakerId, $0.startMs + 3_600_000, $0.endMs + 3_600_000) }
        XCTAssertEqual(match(old, new), [:])
    }

    func testAShiftedRunThatOnlyHalfOverlapsMatchesNothingRatherThanGuessing() {
        // Shifted by one turn and a half: each new turn straddles two old turns
        // of different speakers, so every pair is a tie.
        let old = turns(["S1", "S2", "S1", "S2", "S1", "S2"])
        let new = old.map { span($0.speakerId, $0.startMs + 5_000, $0.endMs + 5_000) }
        XCTAssertEqual(match(old, new), [:])
    }

    func testOverlapUnderTheMinimumIsNoise() {
        // Two speakers that are 1.5 s long and identical: coverage is complete
        // and nobody competes, so only the absolute minimum can say no. A
        // 1.5 s match is a single backchannel, which is not enough to hand a
        // person's name to a speaker.
        let old = [span("S1", 0, 1_500), span("S2", 10_000, 30_000)]
        let new = [span("S1", 0, 1_500), span("S2", 10_000, 30_000)]
        XCTAssertEqual(match(old, new), ["S2": "S2"], "1.5 s is under the 2 s minimum")
        XCTAssertEqual(SpeakerMatching.match(
            old: old, new: new, policy: .init(minOverlapMs: 1_000, dominance: 2, minCoverage: 0.1)),
            ["S1": "S1", "S2": "S2"], "the minimum is a policy, not a constant")
        XCTAssertEqual(SpeakerMatching.overlaps(old: [span("S1", 0, 10_000)],
                                                new: [span("S1", 8_100, 18_000)])["S1"]?["S1"], 1_900)
    }

    func testAGlancingOverlapWithAnotherwiseUncontestedSpeakerDoesNotMatch() {
        // New S1 is 100 s and shares 30 s with the old S1, which is also 100 s:
        // nobody else competes, and it is still not the same speaker.
        let old = [span("S1", 0, 100_000)]
        let new = [span("S1", 70_000, 170_000)]
        XCTAssertEqual(match(old, new), [:])
        // Whereas a speaker that is mostly inside the other is matched: it can
        // be a short speaker that the long one swallowed.
        XCTAssertEqual(match(old, [span("S1", 70_000, 100_000)]), ["S1": "S1"])
    }

    func testATieNeverMatchesEvenWhenThePolicyAsksForADominanceOfOne() {
        let old = [span("S1", 0, 20_000), span("S2", 20_000, 40_000)]
        let new = [span("S1", 0, 40_000)]
        let policy = SpeakerMatching.Policy(minOverlapMs: 1_000, dominance: 1.0, minCoverage: 0.1)
        XCTAssertEqual(SpeakerMatching.match(old: old, new: new, policy: policy), [:])
    }

    func testAMarginJustUnderTheDominanceIsAmbiguousAndJustOverIsNot() {
        // Old S1 is 20 s; the new speaker holds 20 s of it and 10 s of S2: 2.0x.
        let old = [span("S1", 0, 20_000), span("S2", 20_000, 30_000)]
        XCTAssertEqual(match(old, [span("S9", 0, 30_000)]), ["S9": "S1"], "exactly 2x matches")
        let closer = [span("S1", 0, 20_000), span("S2", 20_000, 31_000)]
        XCTAssertEqual(match(closer, [span("S9", 0, 31_000)]), [:], "20 s against 11 s is under 2x")
    }

    // MARK: - Arithmetic

    func testSimultaneousNewSpansAreBothCredited() {
        let old = [span("S1", 0, 10_000)]
        let new = [span("S1", 0, 10_000), span("S2", 2_000, 6_000)]
        let overlap = SpeakerMatching.overlaps(old: old, new: new)
        XCTAssertEqual(overlap["S1"]?["S1"], 10_000)
        XCTAssertEqual(overlap["S1"]?["S2"], 4_000)
    }

    func testALongSpanDoesNotHideTheShortOnesThatStartInsideIt() {
        // The first new span outlasts the next two. A pointer walk that moves
        // on once a span ends before the old one starts would never see S2.
        let new = [span("S1", 0, 100_000), span("S2", 10_000, 12_000), span("S2", 50_000, 52_000)]
        let overlap = SpeakerMatching.overlaps(old: [span("S9", 10_000, 12_000)], new: new)
        XCTAssertEqual(overlap["S9"]?["S1"], 2_000)
        XCTAssertEqual(overlap["S9"]?["S2"], 2_000)
        let late = SpeakerMatching.overlaps(old: [span("S9", 51_000, 70_000)], new: new)
        XCTAssertEqual(late["S9"]?["S1"], 19_000)
        XCTAssertEqual(late["S9"]?["S2"], 1_000)
    }

    func testEmptyAndInvertedSpansCarryNoWeight() {
        let old = [span("S1", 0, 10_000), span("S2", 5_000, 5_000), span("S3", 9_000, 2_000)]
        let new = [span("S1", 0, 10_000), span("S2", 5_000, 5_000)]
        XCTAssertEqual(match(old, new), ["S1": "S1"])
    }

    func testTheOrderOfTheInputDoesNotChangeTheAnswer() {
        let old = turns(["S1", "S2", "S3", "S1", "S2", "S3", "S1"])
        let new = turns(["S3", "S1", "S2", "S3", "S1", "S2", "S3"])
        let expected = match(old, new)
        XCTAssertEqual(expected, ["S3": "S1", "S1": "S2", "S2": "S3"])
        for seed in 0..<20 {
            var rng = SplitMix(seed: UInt64(seed))
            XCTAssertEqual(match(old.shuffled(using: &rng), new.shuffled(using: &rng)), expected)
        }
    }

    // MARK: - Labels

    func testAnInheritingSpeakerTakesItsPredecessorsLabelAndASwapIsAPermutation() {
        let final = SpeakerMatching.finalLabels(newOrder: ["S1", "S2"],
                                                inherited: ["S1": "S2", "S2": "S1"])
        XCTAssertEqual(final, ["S1": "S2", "S2": "S1"])
    }

    func testAFirstRunKeepsTheLabelsItCameWith() {
        let final = SpeakerMatching.finalLabels(newOrder: ["S1", "S2", "S3"], inherited: [:])
        XCTAssertEqual(final, ["S1": "S1", "S2": "S2", "S3": "S3"])
    }

    func testAnUnmatchedSpeakerWhoseLabelIsTakenGetsTheLowestFreeNumber() {
        // New S1 and S2 inherit S2 and S3. New S3 wants S3, which is taken.
        let final = SpeakerMatching.finalLabels(newOrder: ["S1", "S2", "S3"],
                                                inherited: ["S1": "S2", "S2": "S3"])
        XCTAssertEqual(final, ["S1": "S2", "S2": "S3", "S3": "S1"])
    }

    func testAReservedLabelIsNeverHandedToSomeoneElse() {
        // A named speaker, S1, has no heir. The new S1 must not become S1.
        let final = SpeakerMatching.finalLabels(newOrder: ["S1", "S2"], inherited: [:],
                                                reserved: ["S1"])
        XCTAssertEqual(final["S2"], "S2", "a free label is kept")
        XCTAssertEqual(final["S1"], "S3", "the lowest free number, past the reserved one and S2")
    }

    func testEveryNewSpeakerGetsADistinctLabel() {
        for seed in 0..<50 {
            var rng = SplitMix(seed: UInt64(seed))
            let order = (1...6).map { "S\($0)" }
            var inherited: [String: String] = [:]
            var olds = (1...8).map { "S\($0)" }.shuffled(using: &rng)
            for label in order where Bool.random(using: &rng) { inherited[label] = olds.removeFirst() }
            let reserved = Set(olds.prefix(Int.random(in: 0...3, using: &rng)))
            let final = SpeakerMatching.finalLabels(newOrder: order, inherited: inherited,
                                                    reserved: reserved)
            XCTAssertEqual(Set(final.values).count, order.count, "seed \(seed): \(final)")
            XCTAssertTrue(Set(final.values).isDisjoint(with:
                reserved.subtracting(Set(inherited.values))), "seed \(seed) reused a reserved label")
        }
    }

    func testLabelsOfALaneKeepTheirPrefix() {
        XCTAssertEqual(SpeakerMatching.freeLabel(like: "room-S1", taken: ["room-S1", "room-S2"]),
                       "room-S3")
        XCTAssertEqual(SpeakerMatching.freeLabel(like: "S9", taken: []), "S1")
        XCTAssertEqual(SpeakerMatching.freeLabel(like: "remote", taken: ["remote1"]), "remote2")
    }

    // MARK: - The whole carry

    func testANamedSpeakerNobodyInheritedIsKeptAndItsLabelReserved() {
        // Maria (S1) and Juan (S2) fuse in the new run, Ana (S3) is S2 there.
        let old = turns(["S1", "S2", "S1", "S2", "S3", "S3"])
        let new = [span("S1", 0, 40_000), span("S2", 40_000, 60_000)]
        let carry = SpeakerMatching.carry(old: old, new: new, newOrder: ["S1", "S2"],
                                          named: ["S1", "S2", "S3"])
        XCTAssertEqual(carry.inherited, ["S2": "S3"])
        XCTAssertEqual(carry.kept, ["S1", "S2"], "both names stay")
        XCTAssertEqual(carry.label(for: "S2"), "S3")
        XCTAssertEqual(carry.label(for: "S1"), "S4",
                       "S1 and S2 are reserved, S3 is Ana's: the fused speaker is S4")
    }

    func testAnUnnamedSpeakerNobodyInheritedIsNotKept() {
        let old = turns(["S1", "S2", "S1", "S2"])
        let new = [span("S1", 0, 40_000)]
        let carry = SpeakerMatching.carry(old: old, new: new, newOrder: ["S1"], named: [])
        XCTAssertEqual(carry.kept, [])
        XCTAssertEqual(carry.label(for: "S1"), "S1", "nothing to protect, so the new label stands")
    }

    func testALabelTheCarryNeverHeardOfStaysAsItIs() {
        let carry = SpeakerMatching.carry(old: [], new: [], newOrder: [], named: [])
        XCTAssertEqual(carry.label(for: "S7"), "S7")
    }

    // MARK: - Properties over many layouts

    /// People, in a fixed truth; a run is the truth seen through a numbering.
    private struct Layout {
        var truth: [Int]            // who speaks each turn, by person
        var length: Int
        func spans(numbering: [Int: String], dropping: Set<Int> = [], fusing: [Int: Int] = [:]) -> [SpeakerSpan] {
            truth.enumerated().compactMap { index, person in
                guard !dropping.contains(index) else { return nil }
                let seen = fusing[person] ?? person
                return SpeakerSpan(speakerId: numbering[seen] ?? "S?", startMs: index * length,
                                   endMs: (index + 1) * length - 500)
            }
        }
    }

    private func randomLayout(_ rng: inout SplitMix, people: Int, turns count: Int) -> Layout {
        var truth: [Int] = []
        for _ in 0..<count {
            var next = Int.random(in: 0..<people, using: &rng)
            if next == truth.last { next = (next + 1) % people }
            truth.append(next)
        }
        return Layout(truth: truth, length: Int.random(in: 4_000...12_000, using: &rng))
    }

    private func numbering(for people: Int, _ rng: inout SplitMix) -> [Int: String] {
        let labels = (1...people).map { "S\($0)" }.shuffled(using: &rng)
        return Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($0.offset, $0.element) })
    }

    func testAnyRenumberingOfTheSamePeopleIsRecoveredExactly() {
        for seed in 0..<200 {
            var rng = SplitMix(seed: UInt64(seed) &+ 1_000)
            let people = Int.random(in: 2...7, using: &rng)
            let layout = randomLayout(&rng, people: people, turns: Int.random(in: 24...60, using: &rng))
            let first = numbering(for: people, &rng)
            let second = numbering(for: people, &rng)
            // Some turns are lost on each side, but never so many that a person vanishes.
            let lostOld = Set((0..<layout.truth.count).filter { _ in Int.random(in: 0..<10, using: &rng) == 0 })
            let lostNew = Set((0..<layout.truth.count).filter { _ in Int.random(in: 0..<10, using: &rng) == 0 })
            let old = layout.spans(numbering: first, dropping: lostOld)
            let new = layout.spans(numbering: second, dropping: lostNew)

            let matched = match(old, new)
            let present = Set(layout.truth)
            for (newLabel, oldLabel) in matched {
                let newPerson = second.first { $0.value == newLabel }!.key
                let oldPerson = first.first { $0.value == oldLabel }!.key
                XCTAssertEqual(newPerson, oldPerson, "seed \(seed): \(newLabel) was matched to \(oldLabel)")
            }
            // Each person speaks a few times in 24+ turns, so each must be found
            // unless chance made one of them rare.
            let counts = Dictionary(grouping: layout.truth, by: { $0 }).mapValues(\.count)
            for person in present where (counts[person] ?? 0) >= 4 {
                XCTAssertNotNil(matched[second[person]!],
                                "seed \(seed): person \(person) with \(counts[person]!) turns was not matched")
            }
        }
    }

    func testAFusedPairIsNeverMatchedToTheMinorityVoice() {
        for seed in 0..<200 {
            var rng = SplitMix(seed: UInt64(seed) &+ 9_000)
            let people = Int.random(in: 3...6, using: &rng)
            let layout = randomLayout(&rng, people: people, turns: 40)
            let first = numbering(for: people, &rng)
            let second = numbering(for: people, &rng)
            // The new run hears person 1 as person 0.
            let new = layout.spans(numbering: second, fusing: [1: 0])
            let old = layout.spans(numbering: first)

            let matched = match(old, new)
            let fusedLabel = second[0]!
            if let heir = matched[fusedLabel] {
                let zero = layout.truth.filter { $0 == 0 }.count
                let one = layout.truth.filter { $0 == 1 }.count
                let heirPerson = first.first { $0.value == heir }!.key
                XCTAssertTrue(heirPerson == 0 || heirPerson == 1)
                // Only a clear majority may inherit, and it must be the majority.
                XCTAssertGreaterThanOrEqual(max(zero, one), 2 * min(zero, one),
                                            "seed \(seed): 0 has \(zero) turns, 1 has \(one)")
                XCTAssertEqual(heirPerson, zero >= one ? 0 : 1, "seed \(seed)")
            }
            for (newLabel, oldLabel) in matched where newLabel != fusedLabel {
                let newPerson = second.first { $0.value == newLabel }!.key
                let oldPerson = first.first { $0.value == oldLabel }!.key
                XCTAssertEqual(newPerson, oldPerson, "seed \(seed)")
            }
        }
    }
}

/// A seedable generator, so the properties above are the same run to run.
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
