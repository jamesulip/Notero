import XCTest
@testable import TranscriberCore

final class BlockLookupTests: XCTestCase {

    private func segment(_ index: Int, _ start: Int, _ end: Int, speaker: String? = "S1") -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: "line \(index)", speakerId: speaker)
    }

    func testBlockIndexFindsTheBlockUnderThePlayhead() {
        let blocks = TranscriptGrouping.blocks(from: [
            segment(0, 0, 4_000), segment(1, 4_200, 8_000),      // one turn, S1
            segment(2, 9_000, 12_000, speaker: "S2"),            // second turn
            segment(3, 20_000, 24_000),                          // third, after a gap
        ])
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(TranscriptGrouping.blockIndex(at: 0, in: blocks), 0)
        XCTAssertEqual(TranscriptGrouping.blockIndex(at: 7_999, in: blocks), 0)
        XCTAssertEqual(TranscriptGrouping.blockIndex(at: 10_000, in: blocks), 1)
        XCTAssertEqual(TranscriptGrouping.blockIndex(at: 21_000, in: blocks), 2)
    }

    func testBlockIndexIsNilInAGapAndPastTheEnd() {
        // The follower must not drag the view to the previous turn during a
        // long silence, nor to the last turn once playback has run past it.
        let blocks = TranscriptGrouping.blocks(from: [
            segment(0, 0, 4_000), segment(1, 20_000, 24_000),
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertNil(TranscriptGrouping.blockIndex(at: 10_000, in: blocks))
        XCTAssertNil(TranscriptGrouping.blockIndex(at: 30_000, in: blocks))
        XCTAssertNil(TranscriptGrouping.blockIndex(at: 0, in: []))
    }

    func testAnEditedLineIsWhatTheBlockShows() {
        var edited = segment(0, 0, 4_000)
        edited.textClean = "corrected"
        let blocks = TranscriptGrouping.blocks(from: [edited, segment(1, 4_200, 8_000)])
        XCTAssertEqual(blocks.first?.text, "corrected line 1")
    }
}
