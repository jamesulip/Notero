import XCTest
@testable import TranscriberCore

final class ExportTests: XCTestCase {

    private func document(
        segments: [Segment],
        speakers: [SpeakerLabel] = [],
        bookmarks: [Bookmark] = [],
        items: [MeetingItem] = [],
        summary: String = ""
    ) -> MeetingDocument {
        MeetingDocument(
            id: UUID(), title: "Team Meeting", kind: .meeting,
            createdAt: Date(timeIntervalSince1970: 1_772_000_000),
            durationMs: 30_000, language: "tl", summary: summary,
            speakers: speakers, segments: segments, bookmarks: bookmarks, items: items
        )
    }

    private func segment(_ index: Int, _ text: String, _ start: Int, _ end: Int,
                         speaker: String? = nil, clean: String? = nil) -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: text,
                textClean: clean, speakerId: speaker)
    }

    // MARK: - Plain text

    func testTextGroupsConsecutiveTurnsUnderOneSpeakerHeading() {
        let doc = document(
            segments: [
                segment(0, "Magandang araw po.", 1_000, 3_000, speaker: "S1"),
                segment(1, "Simulan na natin.", 3_200, 5_000, speaker: "S1"),
                segment(2, "Sige po.", 5_500, 6_500, speaker: "S2"),
            ],
            speakers: [SpeakerLabel(id: "S1", displayName: "Juan"),
                       SpeakerLabel(id: "S2", displayName: "Maria")]
        )
        let text = Exporter.render(.txt, document: doc)
        XCTAssertTrue(text.contains("0:01  Juan"))
        XCTAssertTrue(text.contains("Magandang araw po. Simulan na natin."))
        XCTAssertTrue(text.contains("0:05  Maria"))
        // The rename must reach the export, not just the screen.
        XCTAssertFalse(text.contains("S1"))
    }

    func testTextKeepsTaglishExactlyAsTranscribed() {
        let line = "Okay, kailangan natin i-finalize yung proposal by Friday."
        let text = Exporter.render(.txt, document: document(
            segments: [segment(0, line, 0, 4_000)]
        ))
        XCTAssertTrue(text.contains(line))
    }

    func testTextIncludesNotesBookmarksAndOpenActionItems() {
        let doc = document(
            segments: [segment(0, "Launch on September 15.", 1_000, 3_000)],
            bookmarks: [Bookmark(atMs: 84_000, label: "Budget discussion")],
            items: [
                MeetingItem(kind: .decision, text: "Launch target September 15",
                            sourceMs: 1_000),
                MeetingItem(kind: .actionItem, text: "Draft the brief",
                            isDone: true, owner: "Maria"),
            ],
            summary: "Planning call."
        )
        let text = Exporter.render(.txt, document: doc)
        XCTAssertTrue(text.contains("SUMMARY"))
        XCTAssertTrue(text.contains("DECISIONS"))
        XCTAssertTrue(text.contains("- Launch target September 15  [0:01]"))
        XCTAssertTrue(text.contains("[x] Draft the brief (Maria)"))
        XCTAssertTrue(text.contains("1:24  Budget discussion"))
    }

    func testExportsPreferCleanedTextWhenPresent() {
        let text = Exporter.render(.txt, document: document(
            segments: [segment(0, "raw wrods", 0, 1_000, clean: "raw words")]
        ))
        XCTAssertTrue(text.contains("raw words"))
        XCTAssertFalse(text.contains("raw wrods"))
    }

    // MARK: - Subtitles

    func testSrtNumbersCuesFromOneAndUsesCommaMilliseconds() {
        let srt = Exporter.render(.srt, document: document(segments: [
            segment(0, "Una", 1_500, 2_400),
            segment(1, "Pangalawa", 2_400, 3_000),
        ]))
        XCTAssertTrue(srt.hasPrefix("1\n00:00:01,500 --> 00:00:02,400\nUna"))
        XCTAssertTrue(srt.contains("2\n00:00:02,400 --> 00:00:03,000\nPangalawa"))
    }

    func testSrtNeverEmitsOverlappingOrZeroLengthCues() {
        // Word timings shift between decode passes, so a later segment can
        // legitimately start before the previous one ended. Players reject that.
        let srt = Exporter.render(.srt, document: document(segments: [
            segment(0, "Una", 1_000, 2_000),
            segment(1, "Pangalawa", 1_900, 1_900),
        ]))
        XCTAssertTrue(srt.contains("00:00:02,000 --> 00:00:02,001"))
    }

    func testVttUsesVoiceSpansAndDottedMilliseconds() {
        let vtt = Exporter.render(.vtt, document: document(
            segments: [segment(0, "Magandang araw", 1_000, 2_000, speaker: "S1")],
            speakers: [SpeakerLabel(id: "S1", displayName: "Juan")]
        ))
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("00:00:01.000 --> 00:00:02.000"))
        XCTAssertTrue(vtt.contains("<v Juan>Magandang araw"))
    }

    func testSubtitlesSkipEmptySegments() {
        let srt = Exporter.render(.srt, document: document(segments: [
            segment(0, "   ", 0, 1_000),
            segment(1, "Totoo", 1_000, 2_000),
        ]))
        XCTAssertTrue(srt.hasPrefix("1\n"))
        XCTAssertFalse(srt.contains("2\n"))
    }

    // MARK: - JSON

    func testJsonRoundTripsTheWholeMeeting() throws {
        let doc = document(
            segments: [segment(0, "Magandang araw", 1_000, 2_000, speaker: "S1")],
            speakers: [SpeakerLabel(id: "S1", displayName: "Juan", speechMs: 1_000)],
            bookmarks: [Bookmark(atMs: 500, label: "Start")],
            items: [MeetingItem(kind: .question, text: "Sino ang mag-lead?")],
            summary: "Planning."
        )
        let json = Exporter.render(.json, document: doc)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(MeetingDocument.self, from: Data(json.utf8))

        XCTAssertEqual(back.title, doc.title)
        XCTAssertEqual(back.segments.first?.text, "Magandang araw")
        XCTAssertEqual(back.segments.first?.id, doc.segments.first?.id)
        XCTAssertEqual(back.speakers.first?.displayName, "Juan")
        XCTAssertEqual(back.bookmarks.first?.atMs, 500)
        XCTAssertEqual(back.items.first?.kind, .question)
        XCTAssertEqual(back.summary, "Planning.")
    }

    func testFilenameStripsPathSeparators() {
        let doc = document(segments: [])
        var named = doc
        named.title = "Client / Vendor: sync"
        XCTAssertEqual(Exporter.filename(for: named, format: .srt),
                       "Client - Vendor- sync.srt")
    }

    func testEmptyTranscriptStillExportsTheNotes() {
        let text = Exporter.render(.txt, document: document(
            segments: [], summary: "Nothing was recorded."
        ))
        XCTAssertTrue(text.contains("Nothing was recorded."))
        XCTAssertFalse(text.contains("TRANSCRIPT"))
    }
}
