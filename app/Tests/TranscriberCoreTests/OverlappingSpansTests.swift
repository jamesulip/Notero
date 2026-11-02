import XCTest
@testable import TranscriberCore

/// An end-to-end diarizer (the experimental Nemotron 3 backend) returns spans of two
/// speakers that overlap in time, where the shipping backend rarely does. These pin
/// what the transcript does with them: word times never move, each line goes to the
/// speaker holding most of it, and names are still carried by overlap in time.
final class OverlappingSpansTests: XCTestCase {

    private func token(_ text: String, _ start: Int, _ end: Int) -> Token {
        Token(text: text, startMs: start, endMs: end)
    }

    private func span(_ id: String, _ start: Int, _ end: Int) -> SpeakerSpan {
        SpeakerSpan(speakerId: id, startMs: start, endMs: end)
    }

    func testOverlappingSpansNeverMoveWordTimesAndGiveEachLineItsDominantSpeaker() {
        let tokens = [token("Sige ", 0, 400), token("po ", 400, 900), token("ano ", 1_000, 1_400),
                      token("Oo ", 2_600, 2_900), token("tama ", 2_900, 3_300)]
        // N2 starts talking while N1 is still on; N1 holds the first words, N2 the last.
        let spans = [span("N1", 0, 2_000), span("N2", 1_200, 3_400)]
        let out = SegmentMerger.segments(from: tokens, spans: spans)

        XCTAssertEqual(out.map(\.speakerId), ["N1", "N2"])
        XCTAssertEqual(out.first?.startMs, 0)
        XCTAssertEqual(out.last?.endMs, 3_300)
        for segment in out {
            XCTAssertLessThan(segment.startMs, segment.endMs)
            let inside = tokens.filter { $0.startMs >= segment.startMs && $0.endMs <= segment.endMs }
            XCTAssertFalse(inside.isEmpty, "a segment's bounds are its own words' times")
        }
        XCTAssertEqual(out.map(\.startMs), out.map(\.startMs).sorted())
    }

    func testFullOverlapStillCreditsOneSpeakerWithTheWordsOwnTime() {
        // Two speakers active over the whole word: a tie at 100% each. The lower label is
        // credited (the share clears the minimum); the time is still the word's own.
        let winner = SegmentMerger.dominantSpeaker(
            startMs: 1_000, endMs: 2_000,
            spans: [span("N1", 0, 3_000), span("N2", 500, 2_500)], minShare: 0.34)
        XCTAssertEqual(winner?.speakerId, "N1")
        XCTAssertEqual(winner?.share, 1.0)
    }

    /// A tie goes to the lower label, whatever order the spans come in. Before, the
    /// winner came from `Dictionary` order, which changes between processes.
    func testATieIsBrokenByLabelNotByDictionaryOrder() {
        for order in [["B", "A", "C"], ["C", "B", "A"], ["A", "C", "B"]] {
            let spans = order.map { span($0, 0, 1_000) }
            for _ in 0..<50 {
                XCTAssertEqual(SegmentMerger.dominantSpeaker(
                    startMs: 0, endMs: 1_000, spans: spans, minShare: 0.34)?.speakerId, "A")
            }
        }
    }

    func testNormalizeKeepsOverlappingSpansAndTheirTimes() {
        let spans = [span("N2", 1_200, 3_400), span("N1", 0, 2_000)]
        let normalized = SegmentMerger.normalize(spans)
        XCTAssertEqual(normalized.roster.map(\.id), ["S1", "S2"])
        let times = normalized.spans.map { [$0.startMs, $0.endMs] }.sorted { $0[0] < $1[0] }
        XCTAssertEqual(times, [[0, 2_000], [1_200, 3_400]])
    }

    func testNamesCarryOverASwapWhenTheNewRunHasOverlap() {
        // The first run (no overlap) was renamed; the second run swaps the numbers
        // and marks two seconds of crosstalk. Each name still follows its voice.
        let old = [span("S1", 0, 10_000), span("S2", 10_000, 20_000), span("S1", 20_000, 30_000)]
        let new = [span("S2", 0, 10_500), span("S1", 9_500, 20_000), span("S2", 20_000, 30_000)]
        let carry = SpeakerMatching.carry(old: old, new: new, newOrder: ["S2", "S1"],
                                          named: ["S1", "S2"])
        XCTAssertEqual(carry.inherited, ["S2": "S1", "S1": "S2"])
        XCTAssertEqual(carry.kept, [])
    }
}
