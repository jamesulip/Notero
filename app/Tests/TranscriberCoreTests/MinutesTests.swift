import XCTest
@testable import TranscriberCore

/// The guards on what the model hands back.
///
/// The prompt is not tested -- it is a string, and the model is not here. What
/// is tested is every way a generation can be wrong: fenced output, unknown
/// item kinds, empty text, and above all a citation pointing at audio that
/// does not exist.
final class MinutesTests: XCTestCase {

    private func segment(_ index: Int, _ start: Int, _ end: Int) -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: "line \(index)")
    }

    /// 0-2 s and 5-7 s of speech, with silence between and after.
    private var segments: [Segment] {
        [segment(0, 0, 2_000), segment(1, 5_000, 7_000)]
    }

    // MARK: - Extraction

    func testExtractsJSONFromACodeFence() {
        let raw = """
        Here are the minutes:
        ```json
        {"summary": "ok", "items": []}
        ```
        """
        XCTAssertEqual(Minutes.extractJSON(raw), #"{"summary": "ok", "items": []}"#)
    }

    func testMissingJSONIsAnError() {
        XCTAssertThrowsError(try Minutes.parse("I could not do that.", against: segments)) {
            guard case Minutes.Failure.noJSON = $0 else { return XCTFail("wrong error: \($0)") }
        }
    }

    func testMalformedJSONIsAnError() {
        XCTAssertThrowsError(try Minutes.parse("{\"items\": [ }", against: segments)) {
            guard case Minutes.Failure.malformed = $0 else { return XCTFail("wrong error: \($0)") }
        }
    }

    // MARK: - Citations

    func testCitationInsideASegmentResolvesToIt() {
        let cited = Minutes.cite(1_200, in: segments)
        XCTAssertEqual(cited?.index, 0)
    }

    func testCitationInSilenceResolvesToNothing() {
        // 3 s is between the two segments. Snapping it to the nearest one
        // would produce a note that looks sourced and seeks to the wrong
        // moment -- the single failure the source link exists to prevent.
        XCTAssertNil(Minutes.cite(3_000, in: segments))
    }

    func testCitationPastTheEndResolvesToNothing() {
        XCTAssertNil(Minutes.cite(90_000, in: segments))
    }

    func testCitationBeforeTheFirstSegmentResolvesToNothing() {
        XCTAssertNil(Minutes.cite(-1, in: [segment(0, 100, 2_000)]))
    }

    func testUncitedItemsAreKeptButCounted() throws {
        let raw = """
        {"summary": "s", "items": [
          {"kind": "decision", "text": "real", "atMs": 5_500},
          {"kind": "decision", "text": "invented", "atMs": 3000}
        ]}
        """.replacingOccurrences(of: "5_500", with: "5500")
        let draft = try Minutes.parse(raw, against: segments)

        XCTAssertEqual(draft.items.count, 2)
        XCTAssertEqual(draft.uncitedCount, 1)
        XCTAssertEqual(draft.items[0].sourceMs, 5_000)
        XCTAssertNil(draft.items[1].sourceMs)
        XCTAssertNil(draft.items[1].sourceSegmentId)
    }

    func testAnItemWithNoTimestampIsNotCountedAsUncited() throws {
        let raw = #"{"summary": "s", "items": [{"kind": "keyPoint", "text": "t"}]}"#
        let draft = try Minutes.parse(raw, against: segments)
        XCTAssertEqual(draft.uncitedCount, 0)
        XCTAssertNil(draft.items[0].sourceMs)
    }

    // MARK: - Item validation

    func testUnknownKindsAndEmptyTextAreDropped() throws {
        let raw = """
        {"summary": "s", "items": [
          {"kind": "actionItem", "text": "kept", "atMs": 100},
          {"kind": "risk", "text": "unknown kind", "atMs": 100},
          {"kind": "keyPoint", "text": "   ", "atMs": 100}
        ]}
        """
        let draft = try Minutes.parse(raw, against: segments)
        XCTAssertEqual(draft.items.map(\.text), ["kept"])
    }

    func testOwnerIsKeptOnlyWhereItMeansSomething() throws {
        let raw = """
        {"summary": "s", "items": [
          {"kind": "actionItem", "text": "a", "atMs": 100, "owner": "Maria"},
          {"kind": "keyPoint", "text": "k", "atMs": 100, "owner": "Maria"}
        ]}
        """
        let draft = try Minutes.parse(raw, against: segments)
        XCTAssertEqual(draft.items[0].owner, "Maria")
        XCTAssertNil(draft.items[1].owner, "only checkable kinds carry an owner")
    }

    func testSummaryIsTrimmedAndItemsMayBeAbsent() throws {
        let draft = try Minutes.parse(#"{"summary": "  done.  "}"#, against: segments)
        XCTAssertEqual(draft.summary, "done.")
        XCTAssertTrue(draft.items.isEmpty)
    }

    // MARK: - Prompt

    func testTranscriptCarriesResolvableTimestamps() {
        let document = MeetingDocument(
            id: UUID(), title: "t", kind: .meeting, createdAt: Date(),
            durationMs: 7_000, language: "tl", segments: segments
        )
        // Every stamp the model is shown must be one `cite` can resolve,
        // otherwise the prompt is asking for citations that cannot survive.
        for line in Minutes.transcript(of: document).split(separator: "\n") {
            let stamp = line.drop(while: { $0 != "[" }).dropFirst()
                .prefix(while: { $0 != "]" })
            let ms = try? XCTUnwrap(Int(stamp))
            XCTAssertNotNil(Minutes.cite(ms ?? -1, in: segments), "unresolvable: \(line)")
        }
    }
}
