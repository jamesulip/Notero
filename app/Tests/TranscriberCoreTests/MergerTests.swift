import XCTest
@testable import TranscriberCore

final class SegmentMergerTests: XCTestCase {

    private func token(_ text: String, _ start: Int, _ end: Int,
                       confidence: Double? = nil) -> Token {
        Token(text: text, startMs: start, endMs: end, confidence: confidence)
    }

    private func span(_ id: String, _ start: Int, _ end: Int) -> SpeakerSpan {
        SpeakerSpan(speakerId: id, startMs: start, endMs: end)
    }

    // MARK: - Attribution

    func testDominantSpeakerPicksTheLargestOverlap() {
        let spans = [span("S1", 0, 1_000), span("S2", 1_000, 4_000)]
        let winner = SegmentMerger.dominantSpeaker(
            startMs: 800, endMs: 2_000, spans: spans, minShare: 0.34
        )
        XCTAssertEqual(winner?.speakerId, "S2")
    }

    func testAbstainsWhenNoSpeakerHoldsEnoughOfTheSegment() {
        // A segment straddling a turn with a long unattributed gap in the
        // middle: guessing here would put words in the wrong mouth.
        let spans = [span("S1", 0, 300), span("S2", 5_700, 6_000)]
        let winner = SegmentMerger.dominantSpeaker(
            startMs: 0, endMs: 6_000, spans: spans, minShare: 0.34
        )
        XCTAssertNil(winner)
    }

    func testAttributeLeavesSegmentsAloneWithoutSpans() {
        let segments = [Segment(index: 0, startMs: 0, endMs: 1_000, text: "hi",
                                speakerId: "kept")]
        XCTAssertEqual(SegmentMerger.attribute(segments, to: []).first?.speakerId, "kept")
    }

    // MARK: - Building segments

    func testSplitsOnSpeakerChange() {
        let tokens = [token("Magandang ", 0, 400), token("araw ", 400, 900),
                      token("Sige ", 1_000, 1_400), token("po", 1_400, 1_800)]
        let spans = [span("A", 0, 950), span("B", 950, 2_000)]
        let out = SegmentMerger.segments(from: tokens, spans: spans)

        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].speakerId, "A")
        XCTAssertEqual(out[0].text, "Magandang araw")
        XCTAssertEqual(out[1].speakerId, "B")
        XCTAssertEqual(out[1].text, "Sige po")
    }

    func testSplitsOnALongPause() {
        let tokens = [token("Una", 0, 500), token(" pangalawa", 3_000, 3_500)]
        let out = SegmentMerger.segments(from: tokens)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].startMs, 0)
        XCTAssertEqual(out[1].startMs, 3_000)
    }

    func testDoesNotSplitOnAnUnattributedWordBetweenTwoOfTheSameSpeaker() {
        // Diarizer boundaries and Whisper word boundaries disagree by a few
        // hundred milliseconds routinely. A gap in the middle of a sentence is
        // an artefact, not a turn.
        let tokens = [token("isa ", 0, 400), token("dalawa ", 500, 900),
                      token("tatlo", 1_000, 1_400)]
        let spans = [span("A", 0, 450), span("A", 950, 1_500)]
        let out = SegmentMerger.segments(from: tokens, spans: spans)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].speakerId, "A")
    }

    func testCutsAtSentenceEndOnceLongEnough() {
        let tokens = [token("Tapos", 0, 700), token(" na.", 700, 1_400),
                      token(" Susunod", 1_500, 2_100)]
        let out = SegmentMerger.segments(from: tokens)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out[0].text.hasSuffix("na."))
    }

    func testRespectsTheHardSegmentCeiling() {
        let tokens = (0..<60).map { token("wordwordword ", $0 * 500, $0 * 500 + 480) }
        let out = SegmentMerger.segments(from: tokens)
        XCTAssertTrue(out.count > 1)
        XCTAssertTrue(out.allSatisfy { $0.durationMs <= SegmentPolicy.default.maxSegmentMs + 500 })
    }

    func testSegmentsCarryConfidenceAndSequentialIndices() {
        let tokens = [token("isa ", 0, 400, confidence: 0.9),
                      token("dalawa", 400, 900, confidence: 0.7)]
        let out = SegmentMerger.segments(from: tokens, startingAt: 7)
        XCTAssertEqual(out[0].index, 7)
        XCTAssertEqual(out[0].confidence ?? 0, 0.8, accuracy: 0.0001)
    }

    func testSegmentsCarryAnAudioReferenceAtTheirOwnStart() {
        let reference = AudioReference(recordingId: UUID(), fileName: "2026/08/x.m4a",
                                       offsetMs: 0)
        let tokens = [token("isa ", 0, 400), token(" dalawa", 5_000, 5_400)]
        let out = SegmentMerger.segments(from: tokens, audio: reference)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1].audio?.offsetMs, 5_000)
        XCTAssertEqual(out[1].audio?.fileName, "2026/08/x.m4a")
    }

    // MARK: - Roster

    func testNormalizeRenumbersByFirstAppearance() {
        // The backend numbers speakers by cluster index, which can put whoever
        // opened the meeting at "Speaker 4".
        let raw = [span("speaker_7", 5_000, 6_000), span("speaker_2", 0, 4_000)]
        let (spans, roster) = SegmentMerger.normalize(raw)

        XCTAssertEqual(spans.first?.speakerId, "S1")
        XCTAssertEqual(spans.first?.startMs, 0)
        XCTAssertEqual(roster.map(\.id), ["S1", "S2"])
        XCTAssertEqual(roster.map(\.displayName), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(roster[0].speechMs, 4_000)
    }

    func testDefaultSpeakerNameHandlesBackendLabelStyles() {
        XCTAssertEqual(SpeakerLabel.defaultName(for: "S3"), "Speaker 3")
        XCTAssertEqual(SpeakerLabel.defaultName(for: "unknown"), "unknown")
    }
}

final class GroupingTests: XCTestCase {

    private func segment(_ index: Int, _ start: Int, _ end: Int,
                         _ speaker: String?) -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: "w\(index)",
                speakerId: speaker)
    }

    func testBlocksBreakOnSpeakerChange() {
        let blocks = TranscriptGrouping.blocks(from: [
            segment(0, 0, 1_000, "A"), segment(1, 1_000, 2_000, "A"),
            segment(2, 2_000, 3_000, "B"),
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].text, "w0 w1")
        XCTAssertEqual(blocks[1].speakerId, "B")
    }

    func testBlocksBreakOnALongGapEvenForOneSpeaker() {
        let blocks = TranscriptGrouping.blocks(from: [
            segment(0, 0, 1_000, "A"), segment(1, 9_000, 10_000, "A"),
        ])
        XCTAssertEqual(blocks.count, 2)
    }

    func testSegmentIndexAtFindsTheRowPlayingNow() {
        let segments = (0..<200).map { segment($0, $0 * 1_000, $0 * 1_000 + 900, nil) }
        XCTAssertEqual(TranscriptGrouping.segmentIndex(at: 150_400, in: segments), 150)
        // Between rows, the last one that has started.
        XCTAssertEqual(TranscriptGrouping.segmentIndex(at: 150_950, in: segments), 150)
        XCTAssertNil(TranscriptGrouping.segmentIndex(at: -5, in: segments))
    }
}
