import XCTest
@testable import TranscriberCore

final class ReferenceSetTests: XCTestCase {

    private func segment(_ index: Int, _ text: String, clean: String? = nil) -> Segment {
        Segment(index: index, startMs: index * 3_000, endMs: index * 3_000 + 2_500,
                text: text, textClean: clean)
    }

    func testOnlyARealEditCountsAsACorrection() {
        XCTAssertFalse(ReferenceSet.isCorrected(segment(0, "Sige na")))
        XCTAssertFalse(ReferenceSet.isCorrected(segment(0, "Sige na", clean: "Sige na ")),
                       "an edit that restored the raw text is not a correction")
        XCTAssertTrue(ReferenceSet.isCorrected(segment(0, "Sigue na", clean: "Sige na")))
        XCTAssertFalse(ReferenceSet.hasCorrections([segment(0, "a"), segment(1, "b")]))
        XCTAssertTrue(ReferenceSet.hasCorrections([segment(0, "a"), segment(1, "b", clean: "c")]))
    }

    func testReferenceIsTheWholeTranscriptWithEditsApplied() {
        let rows = [segment(0, "Kumusta kayong lahat."),
                    segment(1, "Bisa report ni Maria", clean: "Base sa report ni Maria"),
                    segment(2, "  ")]
        XCTAssertEqual(ReferenceSet.referenceText(rows),
                       "Kumusta kayong lahat.\nBase sa report ni Maria\n")
        XCTAssertEqual(ReferenceSet.rawText(rows),
                       "Kumusta kayong lahat.\nBisa report ni Maria\n")
    }

    func testEditsTableHoldsTheCorrectedRowsOnly() {
        let rows = [segment(0, "ok"),
                    segment(1, "Bisa\treport", clean: "Base sa report")]
        XCTAssertEqual(ReferenceSet.editsTSV(rows),
                       "startMs\traw\tcorrected\n3000\tBisa report\tBase sa report\n")
    }

    func testSummaryScoresRawAgainstTheCorrections() {
        let rows = [segment(0, "Kumusta kayong lahat"),
                    segment(1, "Bisa report ni Maria", clean: "Base sa report ni Maria")]
        let summary = ReferenceSet.summary(title: "Standup", durationMs: 6_000, segments: rows)
        XCTAssertEqual(summary.segments, 2)
        XCTAssertEqual(summary.correctedSegments, 1)
        XCTAssertEqual(summary.referenceWords, 8)
        // "Bisa" -> "Base" is one substitution and "sa" one insertion in the
        // reference: two edits over eight reference words.
        XCTAssertEqual(summary.rawWER, 0.25, accuracy: 0.001)
    }

    func testManifestKeepsTheKeysTheHarnessReads() throws {
        let entry = ReferenceSet.Entry(id: "abc", audio: "audio/abc.m4a", ref: "refs/abc.txt",
                                       raw: "raw/abc.txt", edits: "edits/abc.tsv",
                                       title: "Standup", durationMs: 1_000)
        let data = try ReferenceSet.manifestJSON([entry])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0]["id"] as? String, "abc")
        XCTAssertEqual(decoded[0]["audio"] as? String, "audio/abc.m4a")
        XCTAssertEqual(decoded[0]["ref"] as? String, "refs/abc.txt")
        XCTAssertEqual(decoded[0]["category"] as? String, "own")
    }

    func testSummaryMarkdownPoolsByReferenceWords() {
        let table = ReferenceSet.summaryMarkdown([
            ReferenceSet.Summary(title: "A | B", durationMs: 60_000, segments: 10,
                                 correctedSegments: 2, referenceWords: 100, rawWER: 0.10),
            ReferenceSet.Summary(title: "C", durationMs: 60_000, segments: 10,
                                 correctedSegments: 1, referenceWords: 300, rawWER: 0.30),
        ])
        XCTAssertTrue(table.contains("| A / B |"), "a pipe in a title must not break the table")
        XCTAssertTrue(table.contains("| **All** | | | | 400 | **25.0%** |"))
    }
}
