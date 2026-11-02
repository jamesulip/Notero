import XCTest
@testable import TranscriberCore

final class MissingSpeechTests: XCTestCase {

    private let settings = MissingSpeechSettings(minRegionMs: 1000, coverageThreshold: 0.2, wordPaddingMs: 200)

    private func reference(_ utterances: [ReferenceUtterance]) -> EvaluationReference {
        EvaluationReference(itemId: "item", utterances: utterances)
    }

    private func word(_ start: Int, _ end: Int) -> Token { Token(text: "w", startMs: start, endMs: end) }

    func testUnavailableWithoutWordTimesOrReferenceTimes() {
        let timed = reference([ReferenceUtterance(id: "a", text: "x", startMs: 0, endMs: 2000)])
        XCTAssertEqual(MissingSpeech.detect(reference: timed, words: nil, settings: settings).unavailableReason,
                       "the hypothesis has no word timestamps")
        let untimed = reference([ReferenceUtterance(id: "a", text: "x")])
        XCTAssertEqual(MissingSpeech.detect(reference: untimed, words: [], settings: settings).unavailableReason,
                       "the reference has no timestamps")
    }

    func testEmptyWordsMarkEveryCheckedRegionMissing() throws {
        let ref = reference([
            ReferenceUtterance(id: "a", text: "x", startMs: 0, endMs: 2000),
            ReferenceUtterance(id: "b", text: "y", startMs: 5000, endMs: 5500),   // too short to check
            ReferenceUtterance(id: "c", text: "z", startMs: 8000, endMs: 10000),
        ])
        let report = try XCTUnwrap(MissingSpeech.detect(reference: ref, words: [], settings: settings).value)
        XCTAssertEqual(report.checkedRegions, 2)
        XCTAssertEqual(report.checkedSpeechMs, 4000)
        XCTAssertEqual(report.uncoveredSpeechMs, 4000)
        XCTAssertEqual(report.missingRegions.map(\.utteranceIds), [["a"], ["c"]])
        XCTAssertEqual(report.missingRegions.map(\.coverage), [0, 0])
        XCTAssertEqual(report.missingShare, .available(1))
    }

    func testRegionsMergeAndCoverageIsPadded() throws {
        // b is listed first but starts later; overlapping a and touching c.
        let ref = reference([
            ReferenceUtterance(id: "b", text: "y", startMs: 1500, endMs: 3000, speaker: "B"),
            ReferenceUtterance(id: "a", text: "x", startMs: 0, endMs: 2000, speaker: "A"),
            ReferenceUtterance(id: "c", text: "z", startMs: 3000, endMs: 4000),
            ReferenceUtterance(id: "d", text: "w", startMs: 10000, endMs: 12000),
            ReferenceUtterance(id: "untimed", text: "v"),
        ])
        // Covers 0...600 and 3800...4200 (clipped to the region) of region 0...4000,
        // and 10800...11200 of region 10000...12000.
        let words = [word(100, 400), word(4000, 4000), word(11000, 11000)]
        let report = try XCTUnwrap(MissingSpeech.detect(reference: ref, words: words, settings: settings).value)
        XCTAssertEqual(report.checkedRegions, 2)
        XCTAssertEqual(report.checkedSpeechMs, 6000)
        // Region 1: 4000 - (600 + 200) = 3200 uncovered; region 2: 2000 - 400 = 1600.
        XCTAssertEqual(report.uncoveredSpeechMs, 4800)
        // 800 / 4000 = 0.2 is not below the threshold; 400 / 2000 = 0.2 neither.
        XCTAssertEqual(report.missingRegions, [])
        XCTAssertEqual(report.missingShare, .available(0))

        let strict = MissingSpeechSettings(minRegionMs: 1000, coverageThreshold: 0.25, wordPaddingMs: 200)
        let strictReport = try XCTUnwrap(MissingSpeech.detect(reference: ref, words: words, settings: strict).value)
        XCTAssertEqual(strictReport.missingRegions.map(\.utteranceIds), [["b", "a", "c"], ["d"]],
                       "ids are in reference order")
        XCTAssertEqual(strictReport.missingRegions.map(\.coverage), [0.2, 0.2])
        XCTAssertEqual(strictReport.missingShare, .available(1))
    }

    func testPaddingClampsAtZero() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "x", startMs: 0, endMs: 1000)])
        let half = MissingSpeechSettings(minRegionMs: 1000, coverageThreshold: 0.5, wordPaddingMs: 200)
        let report = try XCTUnwrap(MissingSpeech.detect(reference: ref, words: [word(50, 100)],
                                                        settings: half).value)
        // Coverage 0...300, not -150...300.
        XCTAssertEqual(report.uncoveredSpeechMs, 700)
        XCTAssertEqual(report.missingRegions.first?.coverage, 0.3)
    }

    func testNothingLongEnoughToCheck() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "x", startMs: 0, endMs: 500)])
        let report = try XCTUnwrap(MissingSpeech.detect(reference: ref, words: [], settings: settings).value)
        XCTAssertEqual(report.checkedRegions, 0)
        XCTAssertFalse(report.missingShare.isAvailable)
    }
}
