import Foundation

// Confidence intervals for corpus error rates, and paired comparisons of two
// systems on the same references.
//
// The whole point is that an interval is reproducible: the same units, the
// same settings and the same seed give the same bytes on every machine and
// every Swift release. So nothing here touches the standard library's random
// algorithms, the system generator or the clock. The generator, the index
// sampling, the draw order and the quantile rule are all written out below and
// pinned by known-answer tests; changing any of them changes published
// intervals and must be treated as a change of method.

// MARK: - Generator

/// SplitMix64 (Steele, Lea and Flood, 2014). Deterministic across machines and
/// Swift versions: its output is a fixed function of the seed, defined here,
/// not by the standard library.
///
/// Chosen over the stdlib generators because those are either unseeded
/// (`SystemRandomNumberGenerator`) or unspecified; SplitMix64 is tiny, well
/// studied, passes BigCrush, and has reference values anyone can recompute.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0..<upperBound` by rejection sampling, implemented here —
    /// NOT `Int.random(in:using:)`, whose algorithm is a stdlib detail that may
    /// change between Swift releases and would change every interval.
    ///
    /// Draws are rejected below `2^64 mod upperBound`, so the accepted range is
    /// an exact multiple of `upperBound` and `r % upperBound` is unbiased. The
    /// rejection rate is below `upperBound / 2^64`, i.e. negligible for any
    /// realistic unit count, but it is part of the contract: a rejected draw
    /// consumes a generator output.
    public mutating func nextIndex(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "nextIndex(below:) needs a positive bound")
        let bound = UInt64(upperBound)
        let threshold = (0 &- bound) % bound
        while true {
            let r = next()
            if r >= threshold { return Int(r % bound) }
        }
    }
}

// MARK: - Inputs and results

/// One resampling unit: an utterance or a whole item, with its edit counts.
public struct BootstrapUnit: Codable, Sendable, Equatable {
    /// e.g. "itemId/utteranceId". Used to check that two systems were scored
    /// on the same units in the same order.
    public var id: String
    /// e.g. a ``LanguageClass`` raw value. The stratum of the stratified bootstrap.
    public var stratum: String
    public var counts: ErrorCounts

    public init(id: String, stratum: String, counts: ErrorCounts) {
        self.id = id
        self.stratum = stratum
        self.counts = counts
    }
}

public struct ConfidenceInterval: Codable, Sendable, Equatable {
    public var lower: Double
    public var upper: Double
    /// The nominal coverage, e.g. 0.95.
    public var level: Double

    public init(lower: Double, upper: Double, level: Double) {
        self.lower = lower
        self.upper = upper
        self.level = level
    }
}

/// A corpus error rate and its bootstrap interval.
public struct BootstrapEstimate: Codable, Sendable, Equatable {
    /// Pooled ΣE/ΣN over all units: the corpus rate, not a mean of per-unit rates.
    public var rate: MetricValue
    public var interval: Measured<ConfidenceInterval>
    public var units: Int
    /// Units per stratum. A unit with an empty stratum is counted under
    /// ``Bootstrap/emptyStratumKey`` so that no key is the empty string.
    public var strata: [String: Int]
    public var resamples: Int
    /// Resamples whose ΣN == 0. Their rate is undefined, so they are excluded
    /// from the quantiles and counted here instead.
    public var degenerateResamples: Int
    public var seed: UInt64
    public var stratified: Bool
    public var method: String
}

/// Two systems on the same references, compared resample by resample.
public struct PairedComparison: Codable, Sendable, Equatable {
    public var baseline: MetricValue
    public var candidate: MetricValue
    /// candidate − baseline (negative = candidate has fewer errors).
    public var difference: MetricValue
    public var baselineInterval: Measured<ConfidenceInterval>
    public var candidateInterval: Measured<ConfidenceInterval>
    public var differenceInterval: Measured<ConfidenceInterval>
    /// Share of valid resamples in which the candidate's rate is strictly lower. Descriptive, not a p-value.
    public var shareCandidateLower: MetricValue
    /// Share of valid resamples in which the two rates are equal.
    public var shareTied: MetricValue
    public var units: Int
    public var strata: [String: Int]
    public var resamples: Int
    public var degenerateResamples: Int
    public var seed: UInt64
    public var stratified: Bool
    public var method: String
}

// MARK: - Bootstrap

/// The percentile bootstrap of a pooled error rate.
///
/// **Reproducibility contract.** For a given list of units and settings, the
/// result is a fixed function of the following, all defined in this file:
///
///  1. The generator: ``SeededGenerator`` (SplitMix64) seeded with `settings.seed`,
///     one generator for the whole run.
///  2. Index sampling: ``SeededGenerator/nextIndex(below:)``.
///  3. Draw order. Per resample, in resample order:
///     * stratified: strata sorted by the UTF-8 bytes of their names; within
///       each stratum, exactly that stratum's unit count draws, each an index
///       into that stratum's units in input order;
///     * unstratified: `units.count` draws, each an index into all units in
///       input order.
///  4. The statistic: ΣE/ΣN of the drawn units, summed as integers and divided
///     once. A resample with ΣN == 0 is degenerate and excluded.
///  5. The interval: Hyndman–Fan type 7 quantiles (``quantile(_:_:)``) at
///     α/2 and 1 − α/2 of the sorted valid statistics, α = 1 − level.
///
/// Changing any of these changes intervals and is a change of method.
///
/// **Small samples.** With few units (say, under 30) the percentile interval
/// undercovers: the resamples cannot vary more than the handful of units
/// does, and the interval is too narrow. It is still computed; the report is
/// where the caveat is shown.
public enum Bootstrap {
    public static let method = "percentile bootstrap of the pooled rate ΣE/ΣN, type-7 quantiles, SplitMix64"

    /// The `strata` key of units whose stratum is the empty string.
    public static let emptyStratumKey = "(none)"

    /// Hyndman–Fan type 7 (linear interpolation between order statistics; the
    /// default of numpy and R, and of `eval/benchstats.py`). `sortedValues`
    /// must be sorted ascending. Nil for an empty sample or a `q` outside [0, 1].
    public static func quantile(_ sortedValues: [Double], _ q: Double) -> Double? {
        guard !sortedValues.isEmpty, q >= 0, q <= 1 else { return nil }
        let position = q * Double(sortedValues.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sortedValues.count - 1)
        let fraction = position - Double(lower)
        return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * fraction
    }

    /// Corpus error rate with a percentile interval.
    ///
    /// The interval is unavailable, with a reason, when there are fewer units
    /// than `settings.minimumUnits`, when the point estimate is unavailable
    /// (ΣN == 0), or when every resample is degenerate. Fewer than ~30 units:
    /// see the small-sample note on ``Bootstrap``.
    public static func estimate(units: [BootstrapUnit], settings: BootstrapSettings) -> BootstrapEstimate {
        let totalErrors = units.reduce(0) { $0 + $1.counts.errors }
        let totalLength = units.reduce(0) { $0 + $1.counts.referenceLength }
        let rate = pointRate(errors: totalErrors, length: totalLength, unitCount: units.count)

        let run = resample(errors: [units.map(\.counts.errors)],
                           lengths: units.map(\.counts.referenceLength),
                           strata: units.map(\.stratum), settings: settings)

        let interval: Measured<ConfidenceInterval>
        if let reason = intervalUnavailableReason(point: rate, unitCount: units.count,
                                                  settings: settings, run: run) {
            interval = .unavailable(reason: reason)
        } else {
            let statistics = zip(run.errors[0], run.lengths).map { Double($0) / Double($1) }
            interval = percentileInterval(statistics, level: settings.confidenceLevel)
        }

        return BootstrapEstimate(rate: rate, interval: interval, units: units.count,
                                 strata: strataCounts(units), resamples: settings.resamples,
                                 degenerateResamples: run.degenerate, seed: settings.seed,
                                 stratified: settings.stratify, method: method)
    }

    /// Paired bootstrap: ONE set of resampled unit indices per resample, applied to both systems.
    /// Throws EvaluationError.incomparable when the two unit lists differ in count, in id order,
    /// in stratum, or in referenceLength for any unit (same references are required).
    ///
    /// Pairing is what makes the comparison sharp: the variation between
    /// utterances, which dwarfs the difference between systems, is the same in
    /// both arms of every resample and cancels in the difference.
    public static func paired(baseline: [BootstrapUnit], candidate: [BootstrapUnit],
                              settings: BootstrapSettings) throws -> PairedComparison {
        guard baseline.count == candidate.count else {
            throw EvaluationError.incomparable(
                "the baseline has \(baseline.count) units and the candidate \(candidate.count)")
        }
        for (index, (b, c)) in zip(baseline, candidate).enumerated() {
            guard b.id == c.id else {
                throw EvaluationError.incomparable(
                    "unit \(index) is \(b.id) in the baseline and \(c.id) in the candidate")
            }
            guard b.stratum == c.stratum else {
                throw EvaluationError.incomparable(
                    "unit \(b.id) is in stratum \(b.stratum) in the baseline and \(c.stratum) in the candidate")
            }
            guard b.counts.referenceLength == c.counts.referenceLength else {
                throw EvaluationError.incomparable(
                    "unit \(b.id) has a reference of \(b.counts.referenceLength) units in the baseline "
                        + "and \(c.counts.referenceLength) in the candidate; the references differ")
            }
        }

        let lengths = baseline.map(\.counts.referenceLength)
        let totalLength = lengths.reduce(0, +)
        let baselineErrors = baseline.reduce(0) { $0 + $1.counts.errors }
        let candidateErrors = candidate.reduce(0) { $0 + $1.counts.errors }
        let baselineRate = pointRate(errors: baselineErrors, length: totalLength, unitCount: baseline.count)
        let candidateRate = pointRate(errors: candidateErrors, length: totalLength, unitCount: candidate.count)
        // Over the shared ΣN, as one division, so identical systems give exactly 0.
        let difference = pointRate(errors: candidateErrors - baselineErrors, length: totalLength,
                                   unitCount: baseline.count)

        let run = resample(errors: [baseline.map(\.counts.errors), candidate.map(\.counts.errors)],
                           lengths: lengths, strata: baseline.map(\.stratum), settings: settings)

        var baselineInterval: Measured<ConfidenceInterval>
        var candidateInterval: Measured<ConfidenceInterval>
        var differenceInterval: Measured<ConfidenceInterval>
        var shareLower: MetricValue
        var shareTied: MetricValue
        if let reason = intervalUnavailableReason(point: baselineRate, unitCount: baseline.count,
                                                  settings: settings, run: run) {
            baselineInterval = .unavailable(reason: reason)
            candidateInterval = .unavailable(reason: reason)
            differenceInterval = .unavailable(reason: reason)
            shareLower = .unavailable(reason: reason)
            shareTied = .unavailable(reason: reason)
        } else {
            let b = run.errors[0], c = run.errors[1], n = run.lengths
            var baselineStats: [Double] = [], candidateStats: [Double] = [], differenceStats: [Double] = []
            baselineStats.reserveCapacity(n.count)
            candidateStats.reserveCapacity(n.count)
            differenceStats.reserveCapacity(n.count)
            var lower = 0, tied = 0
            for i in n.indices {
                let length = Double(n[i])
                baselineStats.append(Double(b[i]) / length)
                candidateStats.append(Double(c[i]) / length)
                differenceStats.append(Double(c[i] - b[i]) / length)
                // ΣN is shared, so comparing error counts compares rates,
                // exactly and without floating-point ties.
                if c[i] < b[i] { lower += 1 } else if c[i] == b[i] { tied += 1 }
            }
            baselineInterval = percentileInterval(baselineStats, level: settings.confidenceLevel)
            candidateInterval = percentileInterval(candidateStats, level: settings.confidenceLevel)
            differenceInterval = percentileInterval(differenceStats, level: settings.confidenceLevel)
            shareLower = .available(Double(lower) / Double(n.count))
            shareTied = .available(Double(tied) / Double(n.count))
        }

        return PairedComparison(baseline: baselineRate, candidate: candidateRate, difference: difference,
                                baselineInterval: baselineInterval, candidateInterval: candidateInterval,
                                differenceInterval: differenceInterval, shareCandidateLower: shareLower,
                                shareTied: shareTied, units: baseline.count, strata: strataCounts(baseline),
                                resamples: settings.resamples, degenerateResamples: run.degenerate,
                                seed: settings.seed, stratified: settings.stratify, method: method)
    }

    // MARK: - Internals

    /// The sums of each valid resample, in resample order.
    struct Run {
        /// `errors[system][k]`: ΣE of system `system` in the k-th valid resample.
        var errors: [[Int]]
        /// ΣN of the k-th valid resample (always > 0).
        var lengths: [Int]
        var degenerate: Int
        /// False when resampling was skipped (too few units, bad settings).
        var ran: Bool
    }

    /// The groups to draw from, in draw order: one group per stratum sorted by
    /// the UTF-8 bytes of its name, or a single group of all units. Each group
    /// lists unit indices in input order.
    static func drawGroups(strata: [String], stratify: Bool) -> [[Int]] {
        guard stratify else { return strata.isEmpty ? [] : [Array(strata.indices)] }
        var byName: [String: [Int]] = [:]
        for (index, name) in strata.enumerated() { byName[name, default: []].append(index) }
        // Byte-wise rather than `String <`, which compares canonically
        // equivalent strings as equal and so is not a total order on bytes.
        let names = byName.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return names.map { byName[$0]! }
    }

    /// Fills `buffer` with one resample's unit indices, in the contract's draw order.
    static func drawIndices(groups: [[Int]], into buffer: inout [Int], using generator: inout SeededGenerator) {
        buffer.removeAll(keepingCapacity: true)
        for group in groups {
            for _ in 0..<group.count {
                buffer.append(group[generator.nextIndex(below: group.count)])
            }
        }
    }

    /// Runs `settings.resamples` resamples, applying each one's indices to
    /// every system in `errors`.
    static func resample(errors: [[Int]], lengths: [Int], strata: [String],
                         settings: BootstrapSettings) -> Run {
        let systems = errors.count
        guard !lengths.isEmpty, lengths.count >= settings.minimumUnits, settings.resamples > 0,
              settings.confidenceLevel > 0, settings.confidenceLevel < 1 else {
            return Run(errors: Array(repeating: [], count: systems), lengths: [], degenerate: 0, ran: false)
        }
        let groups = drawGroups(strata: strata, stratify: settings.stratify)
        var generator = SeededGenerator(seed: settings.seed)
        var indices: [Int] = []
        indices.reserveCapacity(lengths.count)
        var run = Run(errors: Array(repeating: [], count: systems), lengths: [], degenerate: 0, ran: true)
        var sums = [Int](repeating: 0, count: systems)
        for _ in 0..<settings.resamples {
            drawIndices(groups: groups, into: &indices, using: &generator)
            var length = 0
            for s in 0..<systems { sums[s] = 0 }
            for index in indices {
                length += lengths[index]
                for s in 0..<systems { sums[s] += errors[s][index] }
            }
            guard length > 0 else {
                run.degenerate += 1
                continue
            }
            run.lengths.append(length)
            for s in 0..<systems { run.errors[s].append(sums[s]) }
        }
        return run
    }

    private static func pointRate(errors: Int, length: Int, unitCount: Int) -> MetricValue {
        if unitCount == 0 { return .unavailable(reason: "there are no units") }
        return .ratio(errors, length, unavailable: "the units have no reference units to score against")
    }

    /// Why no interval can be given, in the order a reader would want to know.
    private static func intervalUnavailableReason(point: MetricValue, unitCount: Int,
                                                  settings: BootstrapSettings, run: Run) -> String? {
        if case let .unavailable(reason) = point { return "the point estimate is unavailable: \(reason)" }
        if unitCount < settings.minimumUnits {
            return "\(unitCount) unit\(unitCount == 1 ? "" : "s") (fewer than the minimum of \(settings.minimumUnits) for an interval)"
        }
        if settings.resamples <= 0 { return "no resamples were requested" }
        if !(settings.confidenceLevel > 0 && settings.confidenceLevel < 1) {
            return "the confidence level \(settings.confidenceLevel) is not between 0 and 1"
        }
        if !run.ran || run.lengths.isEmpty {
            return "every one of the \(settings.resamples) resamples had an empty reference"
        }
        return nil
    }

    private static func percentileInterval(_ statistics: [Double], level: Double) -> Measured<ConfidenceInterval> {
        let sorted = statistics.sorted()
        let alpha = 1 - level
        guard let lower = quantile(sorted, alpha / 2), let upper = quantile(sorted, 1 - alpha / 2) else {
            return .unavailable(reason: "no valid resamples")
        }
        return .available(ConfidenceInterval(lower: lower, upper: upper, level: level))
    }

    private static func strataCounts(_ units: [BootstrapUnit]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for unit in units { counts[unit.stratum.isEmpty ? emptyStratumKey : unit.stratum, default: 0] += 1 }
        return counts
    }
}
