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

final class MarkdownAndFilterExportTests: XCTestCase {

    private func document() -> MeetingDocument {
        MeetingDocument(
            id: UUID(), title: "Site Meeting", kind: .meeting,
            createdAt: Date(timeIntervalSince1970: 1_772_000_000),
            durationMs: 600_000, language: "tl", summary: "Agreed the launch date.",
            speakers: [SpeakerLabel(id: "S1", displayName: "Juan", speechMs: 8_000),
                       SpeakerLabel(id: "S2", displayName: "Maria", speechMs: 3_000)],
            segments: [
                Segment(index: 0, startMs: 1_000, endMs: 4_000, text: "Simulan na natin.", speakerId: "S1"),
                Segment(index: 1, startMs: 5_000, endMs: 8_000, text: "Sige po.", speakerId: "S2"),
                Segment(index: 2, startMs: 120_000, endMs: 125_000, text: "Launch on the 15th.", speakerId: "S1"),
                Segment(index: 3, startMs: 130_000, endMs: 132_000, text: "Noted.", speakerId: nil),
            ],
            bookmarks: [Bookmark(atMs: 121_000, label: "Launch date")],
            items: [
                MeetingItem(kind: .decision, text: "Launch on the 15th", sourceMs: 120_000),
                MeetingItem(kind: .actionItem, text: "Book the venue", owner: "Maria"),
            ]
        )
    }

    func testMarkdownPutsMinutesBeforeTheTranscript() {
        let text = Exporter.render(.markdown, document: document())
        XCTAssertTrue(text.hasPrefix("# Site Meeting\n"))
        XCTAssertTrue(text.contains("## Attendees\n- Juan"))
        XCTAssertTrue(text.contains("## Decisions\n- Launch on the 15th *(2:00)*"))
        XCTAssertTrue(text.contains("- [ ] Book the venue — Maria"))
        XCTAssertTrue(text.contains("**0:01 · Juan**"))
        let minutes = text.range(of: "## Decisions")!.lowerBound
        let transcript = text.range(of: "## Transcript")!.lowerBound
        XCTAssertLessThan(minutes, transcript)
    }

    func testFilteringBySpeakerDropsOtherAndUnattributedLines() {
        let text = Exporter.render(.txt, document: document(),
                                   options: ExportOptions(speakerIds: ["S2"]))
        XCTAssertTrue(text.contains("Sige po."))
        XCTAssertFalse(text.contains("Simulan"))
        XCTAssertFalse(text.contains("Noted."), "a line nobody is credited with is not Maria's")
    }

    func testFilteringByTimeRangeKeepsNotesWithoutATimestamp() {
        let filtered = ExportOptions(fromMs: 100_000, toMs: 126_000).apply(to: document())
        XCTAssertEqual(filtered.segments.map(\.text), ["Launch on the 15th."])
        XCTAssertEqual(filtered.bookmarks.count, 1)
        XCTAssertEqual(filtered.items.map(\.text), ["Launch on the 15th", "Book the venue"],
                       "the untimed action item stays; nothing says it is outside the range")
    }

    func testNoOptionsMeansTheDocumentIsUntouched() {
        let doc = document()
        XCTAssertEqual(ExportOptions.everything.apply(to: doc).segments.count, doc.segments.count)
        XCTAssertFalse(ExportOptions.everything.isFiltering)
    }
}

final class TimeParseTests: XCTestCase {
    func testClockReadingsParseToMilliseconds() {
        XCTAssertEqual(TimeFormat.parse("45"), 45_000)
        XCTAssertEqual(TimeFormat.parse("12:34"), 754_000)
        XCTAssertEqual(TimeFormat.parse("1:02:03"), 3_723_000)
        XCTAssertEqual(TimeFormat.parse(" 0:05 "), 5_000)
    }

    func testHalfTypedOrNonsenseIsNilNotZero() {
        XCTAssertNil(TimeFormat.parse(""))
        XCTAssertNil(TimeFormat.parse("12:"))
        XCTAssertNil(TimeFormat.parse("1:75"))
        XCTAssertNil(TimeFormat.parse("abc"))
        XCTAssertNil(TimeFormat.parse("1:2:3:4"))
    }
}

final class SpeakerInitialsTests: XCTestCase {
    func testInitialsTakeTheFirstTwoWords() {
        XCTAssertEqual(SpeakerLabel.initials(for: "Maria Santos"), "MS")
        XCTAssertEqual(SpeakerLabel.initials(for: "Juan"), "J")
        XCTAssertEqual(SpeakerLabel.initials(for: "Speaker 3"), "S3")
        XCTAssertEqual(SpeakerLabel.initials(for: "Ana Maria Cruz"), "AM")
        XCTAssertEqual(SpeakerLabel.initials(for: "  "), "")
    }

    func testTimeOfDayIsTheStartPlusTheOffset() {
        // Locale decides the rendering, so compare against the same formatter's
        // reading of the expected instant rather than a literal.
        let start = Date(timeIntervalSince1970: 1_772_000_000)
        let expected = DateFormatter()
        expected.timeStyle = .medium
        expected.dateStyle = .none
        XCTAssertEqual(TimeFormat.timeOfDay(ms: 90_000, start: start),
                       expected.string(from: start.addingTimeInterval(90)))
    }
}
