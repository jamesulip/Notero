import XCTest
@testable import TranscriberCore

final class SearchTests: XCTestCase {

    func testTermsSplitOnWhitespaceAndKeepQuotedPhrases() {
        XCTAssertEqual(TextSearch.terms("september 15"), ["september", "15"])
        XCTAssertEqual(TextSearch.terms("\"launch date\" budget"),
                       ["launch date", "budget"])
    }

    func testSingleLetterNoiseIsDroppedButDigitsSurvive() {
        XCTAssertEqual(TextSearch.terms("a 5 budget"), ["5", "budget"])
    }

    func testMatchingIgnoresCaseAndDiacritics() {
        let ranges = TextSearch.ranges(of: "manana", in: "Sa mañana po tayo.")
        XCTAssertEqual(ranges.count, 1)
    }

    func testMatchAllRequiresEveryTerm() {
        let text = "Let's target September 15 for launch."
        XCTAssertNotNil(TextSearch.matchAll(["september", "launch"], in: text))
        XCTAssertNil(TextSearch.matchAll(["september", "budget"], in: text))
    }

    func testSnippetWindowsAroundTheMatchAndKeepsHighlightsAligned() {
        let text = String(repeating: "filler word ", count: 30)
            + "September 15 is the date. "
            + String(repeating: "more text ", count: 30)
        let matches = TextSearch.matchAll(["september"], in: text)!
        let snippet = TextSearch.snippet(text, matches: matches)

        XCTAssertTrue(snippet.text.count < text.count)
        XCTAssertTrue(snippet.text.hasPrefix("…"))
        XCTAssertTrue(snippet.text.hasSuffix("…"))
        // The rebased range must still cover the matched word, not drift.
        let highlighted = snippet.highlights.map { String(snippet.text[$0]) }
        XCTAssertEqual(highlighted.first?.lowercased(), "september")
    }

    func testSnippetOfShortTextIsTheWholeText() {
        let text = "Short line."
        let matches = TextSearch.matchAll(["short"], in: text)!
        XCTAssertEqual(TextSearch.snippet(text, matches: matches).text, text)
    }

    func testZeroWidthQueryCannotLoopForever() {
        XCTAssertTrue(TextSearch.ranges(of: "", in: "anything").isEmpty)
    }
}

final class BenchmarkMathTests: XCTestCase {

    private func run(_ tier: ModelTier, rtf: Double, failed: Bool = false) -> BenchmarkRun {
        BenchmarkRun(modelId: tier.defaultModelId, tier: tier, label: tier.label,
                     audioMs: 60_000, processMs: Int(60_000 * rtf),
                     failure: failed ? "boom" : nil)
    }

    func testRtfAndSpeedup() {
        let sample = run(.balanced, rtf: 0.25)
        XCTAssertEqual(sample.rtf, 0.25, accuracy: 0.0001)
        XCTAssertEqual(sample.speedup, 4, accuracy: 0.0001)
        XCTAssertTrue(sample.canKeepUpLive)
    }

    func testRecommendsTheSlowestTierThatStillKeepsUpLive() {
        // Slowest-that-keeps-up is the most accurate one inside the budget.
        let report = BenchmarkReport(
            runs: [run(.fast, rtf: 0.08), run(.balanced, rtf: 0.31),
                   run(.accurate, rtf: 1.4)],
            machine: "test", memoryGB: 16
        )
        XCTAssertEqual(report.recommendedTier, .balanced)
    }

    func testAccurateTierIsNeverRecommendedEvenWhenItKeepsUp() {
        // `accurate` re-decodes a 15 s window per hop; ModelTier declares it
        // unsuitable for live, so a fast measurement must not promote it.
        let report = BenchmarkReport(
            runs: [run(.fast, rtf: 0.08), run(.balanced, rtf: 0.12),
                   run(.accurate, rtf: 0.5)],
            machine: "test", memoryGB: 16
        )
        XCTAssertEqual(report.recommendedTier, .balanced)
    }

    func testFallsBackToTheFastestWhenNothingKeepsUp() {
        let report = BenchmarkReport(
            runs: [run(.balanced, rtf: 0.9), run(.accurate, rtf: 2.2)],
            machine: "test", memoryGB: 16
        )
        XCTAssertEqual(report.recommendedTier, .balanced)
    }

    func testFailedRunsAreNeverRecommended() {
        let report = BenchmarkReport(
            runs: [run(.fast, rtf: 0.05, failed: true), run(.balanced, rtf: 0.4)],
            machine: "test", memoryGB: 16
        )
        XCTAssertEqual(report.recommendedTier, .balanced)
    }

    func testFastestTierUsesMeasuredTimeRatherThanTierName() {
        let report = BenchmarkReport(
            runs: [run(.fast, rtf: 0.12), run(.balanced, rtf: 0.08),
                   run(.accurate, rtf: 0.5)],
            machine: "test", memoryGB: 16
        )
        XCTAssertEqual(report.fastestTier, .balanced)
    }

    func testWordErrorRateCountsSubstitutionsInsertionsAndDeletions() {
        XCTAssertEqual(WordErrorRate.score(reference: "isa dalawa tatlo",
                                           hypothesis: "isa dalawa tatlo"),
                       0, accuracy: 0.0001)
        XCTAssertEqual(WordErrorRate.score(reference: "isa dalawa tatlo",
                                           hypothesis: "isa dalawa apat"),
                       1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(WordErrorRate.score(reference: "isa dalawa",
                                           hypothesis: "isa"),
                       0.5, accuracy: 0.0001)
    }

    func testWordErrorRateHandlesAnEmptySideWithoutTrapping() {
        // An empty hypothesis is reachable, not degenerate: a run whose every
        // window was refused produces exactly this (FINDINGS 9). It used to
        // trap on a 1...0 range -- the CLI printed its "N windows never
        // decoded" warning and then crashed computing the WER of the damage.
        XCTAssertEqual(WordErrorRate.score(reference: "isa dalawa tatlo",
                                           hypothesis: ""),
                       1, accuracy: 0.0001)
        XCTAssertEqual(WordErrorRate.score(reference: "", hypothesis: "isa"),
                       1, accuracy: 0.0001)
        XCTAssertEqual(WordErrorRate.score(reference: "", hypothesis: ""),
                       0, accuracy: 0.0001)
        // Punctuation-only strings fold to empty word lists and take the
        // same guards.
        XCTAssertEqual(WordErrorRate.score(reference: "isa", hypothesis: "..."),
                       1, accuracy: 0.0001)
    }

    func testWordErrorRateIgnoresCasePunctuationAndDiacritics() {
        XCTAssertEqual(WordErrorRate.score(reference: "Mañana, po!",
                                           hypothesis: "manana po"),
                       0, accuracy: 0.0001)
    }

    func testAccurateTierIsNotOfferedForTheLivePath() {
        XCTAssertFalse(ModelTier.accurate.suitableForLive)
        XCTAssertTrue(ModelTier.balanced.suitableForLive)
    }
}

final class PCMSourceTests: XCTestCase {

    func testWindowsCoverEverythingExactlyOnce() {
        let source = ArrayPCM([Float](repeating: 0, count: Audio.sampleRate * 7))
        let windows = source.windows(ofMs: 2_000)
        XCTAssertEqual(windows.count, 4)
        XCTAssertEqual(windows.first?.lowerBound, 0)
        XCTAssertEqual(windows.last?.upperBound, source.sampleCount)
        XCTAssertEqual(windows.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) },
                       source.sampleCount)
    }

    func testSliceRequestsAreClampedRatherThanTrapping() {
        let source = ArrayPCM([0.1, 0.2, 0.3])
        XCTAssertEqual(source.floats(-5..<99).count, 3)
        XCTAssertTrue(source.floats(10..<20).isEmpty)
    }

    func testDurationFromSampleCount() {
        XCTAssertEqual(ArrayPCM([Float](repeating: 0, count: 32_000)).durationMs, 2_000)
    }
}
