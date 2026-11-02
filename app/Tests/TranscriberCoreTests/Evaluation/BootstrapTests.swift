import XCTest
@testable import TranscriberCore

final class BootstrapTests: XCTestCase {

    // MARK: - Helpers

    /// A unit with `errors` substitutions-or-insertions over a reference of `length`.
    private func unit(_ id: String, _ stratum: String, errors: Int, length: Int) -> BootstrapUnit {
        // Errors up to N are substitutions; any beyond are insertions, so N = 0 units can carry errors.
        let subs = min(errors, length)
        return BootstrapUnit(id: id, stratum: stratum,
                             counts: ErrorCounts(hits: length - subs, substitutions: subs,
                                                 insertions: errors - subs))
    }

    private func settings(seed: UInt64 = 7, resamples: Int = 200, level: Double = 0.95,
                          stratify: Bool = true, minimumUnits: Int = 2) -> BootstrapSettings {
        BootstrapSettings(resamples: resamples, seed: seed, confidenceLevel: level,
                          stratify: stratify, minimumUnits: minimumUnits)
    }

    /// A synthetic corpus with spread-out per-unit rates across three strata.
    private func syntheticUnits(_ count: Int = 120) -> [BootstrapUnit] {
        let strata = ["tagalog", "english", "code-switched"]
        return (0..<count).map { i in
            let length = 5 + (i * 7) % 13
            return unit("item/u\(i)", strata[i % 3], errors: (i * 5) % (length + 1), length: length)
        }
    }

    /// The seven-unit set of the cross-language known-answer tests.
    /// (stratum, errors, N); unit 2 has N = 0 and two insertions.
    private let knownAnswerSet: [(String, Int, Int)] = [
        ("tagalog", 2, 10), ("english", 3, 5), ("tagalog", 2, 0), ("code-switched", 4, 9),
        ("english", 0, 12), ("tagalog", 3, 6), ("code-switched", 2, 9),
    ]
    private let knownAnswerCandidateErrors = [1, 1, 2, 5, 3, 3, 2]

    private func knownAnswerUnits(errors: [Int]? = nil) -> [BootstrapUnit] {
        knownAnswerSet.enumerated().map { i, row in
            unit("u\(i)", row.0, errors: errors?[i] ?? row.1, length: row.2)
        }
    }

    // MARK: - Generator

    // Reference values computed independently with a ten-line Python
    // implementation of SplitMix64 (python3 -I, 64-bit masking):
    //   s = (s + 0x9E3779B97F4A7C15) & M; z = s
    //   z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M
    //   z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M; return z ^ (z >> 31)
    // The seed-0 values also match the published SplitMix64 reference output.
    func testSplitMix64KnownAnswerSeedZero() {
        var g = SeededGenerator(seed: 0)
        let expected: [UInt64] = [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F,
                                  0xF88B_B8A8_724C_81EC, 0x1B39_896A_51A8_749B]
        XCTAssertEqual((0..<5).map { _ in g.next() }, expected)
    }

    func testSplitMix64KnownAnswerOtherSeeds() {
        var g = SeededGenerator(seed: 20_261_102)
        XCTAssertEqual((0..<5).map { _ in g.next() },
                       [0x41DB_C988_592A_1D6C, 0xF7BF_417D_4CA9_7609, 0x97BD_A7A2_415B_89C7,
                        0x8CD3_8080_5D06_93C1, 0x5E9E_31A3_E31E_7A57])
        var h = SeededGenerator(seed: .max)
        XCTAssertEqual((0..<5).map { _ in h.next() },
                       [0xE4D9_7177_1B65_2C20, 0xE99F_F867_DBF6_82C9, 0x382F_F84C_B272_81E9,
                        0x6D1D_B36C_CBA9_82D2, 0xB4A0_472E_5780_69AE])
    }

    // Same Python reference: t = 2**64 % b; draw until r >= t; return r % b.
    func testNextIndexKnownAnswer() {
        var g = SeededGenerator(seed: 0)
        XCTAssertEqual((0..<12).map { _ in g.nextIndex(below: 3) }, [1, 0, 1, 1, 1, 0, 2, 2, 2, 2, 1, 1])
        var h = SeededGenerator(seed: 0)
        XCTAssertEqual((0..<6).map { _ in h.nextIndex(below: 1000) }, [535, 700, 679, 444, 747, 90])
    }

    func testNextIndexStaysInRangeAndCoversIt() {
        var g = SeededGenerator(seed: 42)
        for bound in [1, 2, 3, 7, 1000, Int.max] {
            for _ in 0..<2000 {
                let i = g.nextIndex(below: bound)
                XCTAssertTrue(i >= 0 && i < bound, "\(i) out of 0..<\(bound)")
            }
        }
        for _ in 0..<100 { XCTAssertEqual(g.nextIndex(below: 1), 0) }
        var hits = [0, 0, 0]
        for _ in 0..<3000 { hits[g.nextIndex(below: 3)] += 1 }
        XCTAssertTrue(hits.allSatisfy { $0 > 800 }, "uneven draws: \(hits)")
    }

    func testSameSeedSameSequence() {
        var a = SeededGenerator(seed: 99), b = SeededGenerator(seed: 99), c = SeededGenerator(seed: 100)
        let sa = (0..<50).map { _ in a.nextIndex(below: 17) }
        let sb = (0..<50).map { _ in b.nextIndex(below: 17) }
        let sc = (0..<50).map { _ in c.nextIndex(below: 17) }
        XCTAssertEqual(sa, sb)
        XCTAssertNotEqual(sa, sc)
    }

    // MARK: - Quantile

    // Python: statistics.quantiles([3,1,4,1,5,9,2,6], n=4, method='inclusive')
    // == [1.75, 3.5, 5.25] (type 7); n=40 gives 1.0 first and 8.475 last.
    func testQuantileIsType7() {
        let sorted = [3.0, 1, 4, 1, 5, 9, 2, 6].sorted()
        XCTAssertEqual(Bootstrap.quantile(sorted, 0.25)!, 1.75, accuracy: 1e-12)
        XCTAssertEqual(Bootstrap.quantile(sorted, 0.5)!, 3.5, accuracy: 1e-12)
        XCTAssertEqual(Bootstrap.quantile(sorted, 0.75)!, 5.25, accuracy: 1e-12)
        XCTAssertEqual(Bootstrap.quantile(sorted, 0.025)!, 1.0, accuracy: 1e-12)
        XCTAssertEqual(Bootstrap.quantile(sorted, 0.975)!, 8.475, accuracy: 1e-12)
        XCTAssertEqual(Bootstrap.quantile(sorted, 0), 1)
        XCTAssertEqual(Bootstrap.quantile(sorted, 1), 9)
        XCTAssertEqual(Bootstrap.quantile([4.5], 0.3), 4.5)
        XCTAssertNil(Bootstrap.quantile([], 0.5))
        XCTAssertNil(Bootstrap.quantile(sorted, 1.5))
    }

    // MARK: - Estimate

    func testPooledRateIsSumOfErrorsOverSumOfLengths() {
        let units = [unit("a", "x", errors: 1, length: 1), unit("b", "x", errors: 1, length: 99)]
        let e = Bootstrap.estimate(units: units, settings: settings())
        // Pooled 2/100, not the mean of per-unit rates (1 + 0.0101) / 2.
        XCTAssertEqual(e.rate, .available(0.02))
        XCTAssertEqual(e.units, 2)
        XCTAssertEqual(e.strata, ["x": 2])
        XCTAssertEqual(e.resamples, 200)
        XCTAssertEqual(e.seed, 7)
        XCTAssertTrue(e.stratified)
    }

    func testIdenticalUnitsGiveAZeroWidthInterval() {
        let units = (0..<10).map { unit("u\($0)", $0 % 2 == 0 ? "a" : "b", errors: 3, length: 12) }
        let e = Bootstrap.estimate(units: units, settings: settings())
        XCTAssertEqual(e.rate, .available(0.25))
        XCTAssertEqual(e.interval, .available(ConfidenceInterval(lower: 0.25, upper: 0.25, level: 0.95)))
    }

    func testSameSeedGivesTheSameBytes() throws {
        let units = syntheticUnits()
        let a = Bootstrap.estimate(units: units, settings: settings(seed: 1234, resamples: 500))
        let b = Bootstrap.estimate(units: units, settings: settings(seed: 1234, resamples: 500))
        XCTAssertEqual(a, b)
        XCTAssertEqual(try CanonicalJSON.encode(a), try CanonicalJSON.encode(b))
        let decoded = try JSONDecoder().decode(BootstrapEstimate.self, from: CanonicalJSON.encode(a))
        XCTAssertEqual(decoded, a)
    }

    func testDifferentSeedGivesADifferentInterval() {
        let units = syntheticUnits()
        let a = Bootstrap.estimate(units: units, settings: settings(seed: 1, resamples: 500))
        let b = Bootstrap.estimate(units: units, settings: settings(seed: 2, resamples: 500))
        XCTAssertEqual(a.rate, b.rate)
        XCTAssertNotNil(a.interval.value)
        XCTAssertNotEqual(a.interval, b.interval)
    }

    func testIntervalContainsThePointEstimate() throws {
        for stratify in [true, false] {
            let e = Bootstrap.estimate(units: syntheticUnits(), settings: settings(resamples: 1000, stratify: stratify))
            let rate = try XCTUnwrap(e.rate.value)
            let ci = try XCTUnwrap(e.interval.value)
            XCTAssertLessThan(ci.lower, rate)
            XCTAssertGreaterThan(ci.upper, rate)
            XCTAssertEqual(ci.level, 0.95)
            XCTAssertEqual(e.degenerateResamples, 0)
        }
    }

    func testTooFewUnitsLeavesTheIntervalUnavailable() {
        let units = [unit("a", "x", errors: 1, length: 4), unit("b", "x", errors: 0, length: 4)]
        let e = Bootstrap.estimate(units: units, settings: settings(minimumUnits: 3))
        XCTAssertEqual(e.rate, .available(0.125))
        XCTAssertNotNil(e.interval.unavailableReason)
        XCTAssertTrue(e.interval.unavailableReason!.contains("minimum"))
    }

    func testNoUnitsLeavesEverythingUnavailable() {
        let e = Bootstrap.estimate(units: [], settings: settings(minimumUnits: 0))
        XCTAssertFalse(e.rate.isAvailable)
        XCTAssertNil(e.interval.value)
        XCTAssertEqual(e.units, 0)
        XCTAssertEqual(e.strata, [:])
    }

    func testAllEmptyReferencesAreDegenerate() {
        let units = (0..<5).map { unit("u\($0)", "x", errors: 2, length: 0) }
        let e = Bootstrap.estimate(units: units, settings: settings(resamples: 50))
        XCTAssertFalse(e.rate.isAvailable)
        XCTAssertNil(e.interval.value)
        XCTAssertEqual(e.degenerateResamples, 50)
    }

    func testEmptyStratumIsNotAnEmptyKey() {
        let e = Bootstrap.estimate(units: [unit("a", "", errors: 1, length: 2), unit("b", "en", errors: 0, length: 2)],
                                   settings: settings())
        XCTAssertEqual(e.strata, [Bootstrap.emptyStratumKey: 1, "en": 1])
    }

    /// Stratum A is all rate 0 and stratum B all rate 1, every unit with N = 4.
    /// A stratified resample always draws 6 A and 4 B units, so its pooled rate
    /// is always 16/40; an unstratified one varies with the mix.
    func testStratifiedDrawsKeepEachStratumsCount() throws {
        let units = (0..<6).map { unit("a\($0)", "A", errors: 0, length: 4) }
            + (0..<4).map { unit("b\($0)", "B", errors: 4, length: 4) }
        let stratified = Bootstrap.estimate(units: units, settings: settings(resamples: 500))
        XCTAssertEqual(stratified.rate, .available(0.4))
        XCTAssertEqual(stratified.interval, .available(ConfidenceInterval(lower: 0.4, upper: 0.4, level: 0.95)))
        let plain = Bootstrap.estimate(units: units, settings: settings(resamples: 500, stratify: false))
        let ci = try XCTUnwrap(plain.interval.value)
        XCTAssertLessThan(ci.lower, 0.4)
        XCTAssertGreaterThan(ci.upper, 0.4)
        XCTAssertFalse(plain.stratified)
    }

    func testDrawGroupsAreSortedByteWiseInInputOrder() {
        let strata = ["tagalog", "english", "tagalog", "code-switched", "English", "english"]
        let groups = Bootstrap.drawGroups(strata: strata, stratify: true)
        // "English" < "code-switched" < "english" < "tagalog" by UTF-8 bytes.
        XCTAssertEqual(groups, [[4], [3], [1, 5], [0, 2]])
        XCTAssertEqual(Bootstrap.drawGroups(strata: strata, stratify: false), [Array(0..<6)])
        var g = SeededGenerator(seed: 3)
        var buffer: [Int] = []
        for _ in 0..<100 {
            Bootstrap.drawIndices(groups: groups, into: &buffer, using: &g)
            XCTAssertEqual(buffer.count, 6)
            XCTAssertEqual(buffer[0], 4)
            XCTAssertEqual(buffer[1], 3)
            XCTAssertTrue(buffer[2...3].allSatisfy { [1, 5].contains($0) })
            XCTAssertTrue(buffer[4...5].allSatisfy { [0, 2].contains($0) })
        }
    }

    // MARK: - Cross-language known answers

    // The whole contract (generator, index sampling, draw order, pooled rate,
    // type-7 quantiles) reimplemented independently in Python (python3 -I, no
    // numpy) on `knownAnswerSet`, 200 resamples, seed 7. The intervals must
    // match to the last bit: any change here is a change of method.
    func testEstimateMatchesTheIndependentReference() {
        let units = knownAnswerUnits()
        let stratified = Bootstrap.estimate(units: units, settings: settings())
        XCTAssertEqual(stratified.rate, .available(16.0 / 51.0))
        XCTAssertEqual(stratified.interval,
                       .available(ConfidenceInterval(lower: 0.1896551724137931, upper: 0.5588235294117647,
                                                     level: 0.95)))
        XCTAssertEqual(stratified.degenerateResamples, 0)
        let plain = Bootstrap.estimate(units: units, settings: settings(stratify: false))
        XCTAssertEqual(plain.interval,
                       .available(ConfidenceInterval(lower: 0.15712053571428572, upper: 0.5593266253869971,
                                                     level: 0.95)))
    }

    func testPairedMatchesTheIndependentReference() throws {
        let p = try Bootstrap.paired(baseline: knownAnswerUnits(),
                                     candidate: knownAnswerUnits(errors: knownAnswerCandidateErrors),
                                     settings: settings(level: 0.9))
        XCTAssertEqual(p.baselineInterval.value?.lower, 0.1935483870967742)
        XCTAssertEqual(p.baselineInterval.value?.upper, 0.4809090909090897)
        XCTAssertEqual(p.candidateInterval.value?.lower, 0.21804195804195803)
        XCTAssertEqual(p.candidateInterval.value?.upper, 0.47058823529411764)
        XCTAssertEqual(p.differenceInterval.value?.lower, -0.1045138888888889)
        XCTAssertEqual(p.differenceInterval.value?.upper, 0.12962962962962962)
        XCTAssertEqual(p.shareCandidateLower, .available(60.0 / 200.0))
        XCTAssertEqual(p.shareTied, .available(22.0 / 200.0))
        XCTAssertEqual(p.difference, .available(1.0 / 51.0))
    }

    // MARK: - Paired

    func testIdenticalSystemsTie() throws {
        let units = syntheticUnits()
        let p = try Bootstrap.paired(baseline: units, candidate: units, settings: settings(resamples: 300))
        XCTAssertEqual(p.difference, .available(0))
        XCTAssertEqual(p.differenceInterval, .available(ConfidenceInterval(lower: 0, upper: 0, level: 0.95)))
        XCTAssertEqual(p.shareTied, .available(1))
        XCTAssertEqual(p.shareCandidateLower, .available(0))
        XCTAssertEqual(p.baselineInterval, p.candidateInterval)
        XCTAssertEqual(p.baselineInterval, Bootstrap.estimate(units: units, settings: settings(resamples: 300)).interval,
                       "the baseline arm is the same resampling as estimate()")
    }

    func testACandidateBetterOnEveryUnitWinsEveryResample() throws {
        let baseline = (0..<40).map { unit("u\($0)", $0 % 2 == 0 ? "tl" : "en", errors: 3 + $0 % 4, length: 10) }
        let candidate = baseline.map { unit($0.id, $0.stratum, errors: $0.counts.errors - 1, length: 10) }
        let p = try Bootstrap.paired(baseline: baseline, candidate: candidate, settings: settings(resamples: 500))
        XCTAssertEqual(p.shareCandidateLower, .available(1))
        XCTAssertEqual(p.shareTied, .available(0))
        let d = try XCTUnwrap(p.differenceInterval.value)
        XCTAssertLessThan(d.upper, 0)
        XCTAssertEqual(try XCTUnwrap(p.difference.value), -0.1, accuracy: 1e-12)
    }

    func testMismatchedUnitsAreIncomparable() {
        let base = [unit("a", "tl", errors: 1, length: 5), unit("b", "en", errors: 2, length: 5)]
        let cases: [(String, [BootstrapUnit])] = [
            ("count", Array(base.prefix(1))),
            ("id order", [base[1], base[0]]),
            ("id", [base[0], unit("c", "en", errors: 2, length: 5)]),
            ("stratum", [base[0], unit("b", "tl", errors: 2, length: 5)]),
            ("reference length", [base[0], unit("b", "en", errors: 2, length: 6)]),
        ]
        for (label, candidate) in cases {
            XCTAssertThrowsError(try Bootstrap.paired(baseline: base, candidate: candidate, settings: settings()),
                                 label) { error in
                guard case EvaluationError.incomparable = error else {
                    return XCTFail("\(label): expected incomparable, got \(error)")
                }
            }
        }
        // Different errors over the same references are exactly what is compared.
        XCTAssertNoThrow(try Bootstrap.paired(baseline: base,
                                              candidate: [unit("a", "tl", errors: 0, length: 5),
                                                          unit("b", "en", errors: 5, length: 5)],
                                              settings: settings()))
    }

    func testPairedIsDeterministic() throws {
        let baseline = syntheticUnits()
        let candidate = baseline.enumerated().map { i, u in
            unit(u.id, u.stratum, errors: max(0, u.counts.errors + (i % 3) - 1), length: u.counts.referenceLength)
        }
        let a = try Bootstrap.paired(baseline: baseline, candidate: candidate, settings: settings(seed: 5))
        let b = try Bootstrap.paired(baseline: baseline, candidate: candidate, settings: settings(seed: 5))
        XCTAssertEqual(try CanonicalJSON.encode(a), try CanonicalJSON.encode(b))
        let c = try Bootstrap.paired(baseline: baseline, candidate: candidate, settings: settings(seed: 6))
        XCTAssertNotEqual(a.differenceInterval, c.differenceInterval)
        XCTAssertEqual(try JSONDecoder().decode(PairedComparison.self, from: CanonicalJSON.encode(a)), a)
    }

    func testPairedWithTooFewUnitsIsUnavailableButHasPointEstimates() throws {
        let one = [unit("a", "tl", errors: 1, length: 5)]
        let p = try Bootstrap.paired(baseline: one, candidate: one, settings: settings())
        XCTAssertEqual(p.difference, .available(0))
        XCTAssertNil(p.differenceInterval.value)
        XCTAssertFalse(p.shareTied.isAvailable)
    }

    // MARK: - Scale

    func testLargeCorpusCompletes() throws {
        let units = syntheticUnits(5_000)
        let e = Bootstrap.estimate(units: units, settings: settings(resamples: 2_000))
        XCTAssertNotNil(e.interval.value)
        let p = try Bootstrap.paired(baseline: units, candidate: units, settings: settings(resamples: 2_000))
        XCTAssertEqual(p.shareTied, .available(1))
    }
}
