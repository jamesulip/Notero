import XCTest
@testable import TranscriberCore

final class MeetingNotesTests: XCTestCase {

    private func segment(_ index: Int, _ start: Int, _ end: Int, _ text: String,
                         speaker: String? = "S1") -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: text, speakerId: speaker)
    }

    private let roster = [SpeakerLabel(id: "S1", displayName: "Juan"),
                          SpeakerLabel(id: "S2", displayName: "Maria")]

    /// A meeting of alternating turns, `count` segments of ~40 characters.
    private func meeting(_ count: Int) -> [Segment] {
        (0..<count).map { i in
            segment(i, i * 5_000, i * 5_000 + 4_000,
                    "Line \(i) tungkol sa product taxonomy at flowchart.",
                    speaker: i % 2 == 0 ? "S1" : "S2")
        }
    }

    // MARK: - Chunker

    func testLinesCarryTheSpeakerNameAndTheStamp() {
        let lines = NotesChunker.lines(from: meeting(2), speakers: roster)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].speaker, "Juan")
        XCTAssertEqual(lines[1].speaker, "Maria")
        XCTAssertEqual(lines[0].rendered, "[0:00] Juan: Line 0 tungkol sa product taxonomy at flowchart.")
        XCTAssertEqual(lines[1].stamp, "0:05")
    }

    func testAnUnnamedSpeakerGetsTheDefaultNameAndNoSpeakerGetsNone() {
        let lines = NotesChunker.lines(from: [
            segment(0, 0, 1_000, "Hello", speaker: "S7"),
            segment(1, 5_000, 6_000, "Hello again", speaker: nil),
        ], speakers: [])
        XCTAssertEqual(lines[0].speaker, "Speaker 7")
        XCTAssertNil(lines[1].speaker)
        XCTAssertEqual(lines[1].rendered, "[0:05] Hello again")
    }

    func testChunksStayUnderTheBudgetAndCoverEveryLine() {
        let segments = meeting(40)
        let chunks = NotesChunker.chunks(from: segments, speakers: roster, maxCharacters: 300)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.characterCount, 300, "part \(chunk.index) over budget")
        }
        let rendered = chunks.flatMap(\.lines).map(\.text)
        XCTAssertEqual(rendered.count, 40)
        XCTAssertEqual(Set(chunks.flatMap(\.lines).map(\.segmentId)), Set(segments.map(\.id)))
        // Indexed in order, and each part ends where the next begins.
        XCTAssertEqual(chunks.map(\.index), Array(0..<chunks.count))
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(a.endMs, b.startMs)
        }
        XCTAssertEqual(chunks.last?.endMs, segments.last?.endMs)
    }

    func testATurnOverTheBudgetIsCutAtSegmentBoundaries() {
        // Ten segments from one speaker with no gap: one 500-character turn.
        let segments = (0..<10).map { i in
            segment(i, i * 2_000, i * 2_000 + 1_900, String(repeating: "salita ", count: 7))
        }
        let chunks = NotesChunker.chunks(from: segments, speakers: roster, maxCharacters: 200)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks { XCTAssertLessThanOrEqual(chunk.characterCount, 200) }
        XCTAssertEqual(chunks.flatMap(\.lines).count, 10, "one line per segment once the turn is over budget")
    }

    func testHalvesCutAtALineAndRefuseASingleLine() {
        let chunks = NotesChunker.chunks(from: meeting(6), speakers: roster, maxCharacters: 10_000)
        XCTAssertEqual(chunks.count, 1)
        let halves = NotesChunker.halves(of: chunks[0])!
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].lines.count, 3)
        XCTAssertEqual(halves[1].lines.count, 3)
        XCTAssertEqual(halves[0].endMs, halves[1].startMs)
        XCTAssertEqual(halves[1].endMs, chunks[0].endMs)

        let single = NotesChunk(index: 0, lines: [chunks[0].lines[0]], endMs: 4_000)
        XCTAssertNil(NotesChunker.halves(of: single))
    }

    // MARK: - Parsing what the model said

    func testParseReadsTheObjectOutOfProseAndAcceptsLabelsAsKinds() {
        let text = """
        Here are the notes:
        {"summary": "Taxonomy was discussed.", "items": [
          {"kind": "Action Item", "text": "Maria to send the sheet.", "at": "[12:34]"},
          {"kind": "decision", "text": "Colour is an attribute.", "at": "13:02"},
          {"kind": "follow-up", "text": "Review on Thursday.", "at": 800},
          {"kind": "nonsense", "text": "dropped"},
          {"kind": "question", "text": "   "}
        ]}
        Hope this helps.
        """
        let notes = ChunkNotes.parse(json: text)!
        XCTAssertEqual(notes.summary, "Taxonomy was discussed.")
        XCTAssertEqual(notes.items.map(\.kind), [.actionItem, .decision, .followUp])
        XCTAssertEqual(notes.items[0].at, "[12:34]")
        XCTAssertEqual(notes.items[2].at, "13:20", "a bare number is read as seconds")
    }

    func testParseReturnsNilWithoutAnObject() {
        XCTAssertNil(ChunkNotes.parse(json: "I cannot do that."))
        XCTAssertNil(ChunkNotes.parse(json: "{not json}"))
    }

    func testParseReadsAnAnswerWithBrokenBrackets() {
        // What Qwen2.5-3B wrote on 8 of 14 parts: the items array is never
        // closed, and the object ends with three braces.
        let text = """
        {"summary": "The team discusses \\"groupings\\".", "items": [{"kind": "keyPoint", "text": "One", "at": "6:42"}, \
        {"kind": "decision", "text": "Two", "at": "7:05"}}}
        """
        let notes = ChunkNotes.parse(json: text)!
        XCTAssertEqual(notes.summary, "The team discusses \"groupings\".")
        XCTAssertEqual(notes.items.map(\.text), ["One", "Two"])
        XCTAssertEqual(notes.items.map(\.kind), [.keyPoint, .decision])
        XCTAssertEqual(notes.items[1].at, "7:05")
    }

    func testKindNames() {
        XCTAssertEqual(ChunkNotes.kind(named: "actionItem"), .actionItem)
        XCTAssertEqual(ChunkNotes.kind(named: "action_item"), .actionItem)
        XCTAssertEqual(ChunkNotes.kind(named: "Key Point"), .keyPoint)
        XCTAssertEqual(ChunkNotes.kind(named: "Follow-up"), .followUp)
        XCTAssertEqual(ChunkNotes.kind(named: "task"), .actionItem)
        XCTAssertNil(ChunkNotes.kind(named: "remark"))
    }

    func testParseStamp() {
        XCTAssertEqual(NotesReducer.parseStamp("12:34"), 754_000)
        XCTAssertEqual(NotesReducer.parseStamp("[12:34]"), 754_000)
        XCTAssertEqual(NotesReducer.parseStamp("at 1:02:03"), 3_723_000)
        XCTAssertEqual(NotesReducer.parseStamp("07:05"), 425_000)
        XCTAssertNil(NotesReducer.parseStamp("later"))
        XCTAssertNil(NotesReducer.parseStamp("12:99"))
        XCTAssertNil(NotesReducer.parseStamp(nil))
    }

    // MARK: - Resolving

    func testResolveLinksAStampInsideThePartToTheLineAtOrBeforeIt() {
        let segments = meeting(6) // lines at 0:00, 0:05, 0:10, 0:15, 0:20, 0:25
        let chunk = NotesChunker.chunks(from: segments, speakers: roster)[0]
        let notes = ChunkNotes(summary: "", items: [
            ChunkNotes.Item(kind: .decision, text: "Inside, exact", at: "0:10"),
            ChunkNotes.Item(kind: .decision, text: "Inside, between lines", at: "0:17"),
            ChunkNotes.Item(kind: .keyPoint, text: "Outside the part", at: "45:00"),
            ChunkNotes.Item(kind: .question, text: "No stamp", at: nil),
            ChunkNotes.Item(kind: .question, text: "  ", at: "0:05"),
        ])
        let items = NotesReducer.resolve(notes, in: chunk)
        XCTAssertEqual(items.count, 4, "the empty note is dropped")
        XCTAssertEqual(items[0].sourceMs, 10_000)
        XCTAssertEqual(items[0].sourceSegmentId, segments[2].id)
        XCTAssertEqual(items[1].sourceMs, 15_000)
        XCTAssertNil(items[2].sourceMs, "a stamp outside the part is a copy error, not a link")
        XCTAssertNil(items[3].sourceMs)
    }

    func testDedupeDropsARestatementOfTheSameKindOnly() {
        let items = [
            NotesDraft.Item(kind: .decision, text: "Paint colour goes in attributes, not variants.", sourceMs: 1_000),
            NotesDraft.Item(kind: .decision, text: "Paint colour goes in the attributes and not in the variants.", sourceMs: 9_000),
            NotesDraft.Item(kind: .keyPoint, text: "Paint colour goes in attributes, not variants.", sourceMs: 2_000),
            NotesDraft.Item(kind: .decision, text: "Version sits above variant.", sourceMs: 3_000),
        ]
        let kept = NotesReducer.dedupe(items)
        XCTAssertEqual(kept.map(\.sourceMs), [1_000, 2_000, 3_000])
    }

    func testContentWordsDropFunctionWordsInBothLanguages() {
        let words = NotesReducer.contentWords("Ang product taxonomy ay tungkol sa mga variants, and the colour is an attribute.")
        XCTAssertEqual(words, ["product", "taxonomy", "variants", "colour", "attribute"])
    }

    // MARK: - Measurement

    func testGroundingSeparatesANoteFromTheTranscriptFromAnInventedOne() {
        let segments = [
            segment(0, 0, 4_000, "Paint colour goes in attributes kasi every colour costs the same."),
            segment(1, 5_000, 9_000, "Version is its own level above variant."),
            segment(2, 600_000, 604_000, "Maria will send the link bukas."),
        ]
        let grounded = NotesDraft.Item(kind: .decision, text: "Paint colour goes in attributes because every colour costs the same.", sourceMs: 0)
        let invented = NotesDraft.Item(kind: .decision, text: "The budget was approved by the finance committee.", sourceMs: 0)
        let farAway = NotesDraft.Item(kind: .actionItem, text: "Maria sends the link.", sourceMs: 0)

        let score = NotesScoring.grounding(of: [grounded, invented, farAway], in: segments, windowMs: 60_000)
        XCTAssertEqual(score.itemsScored, 3)
        XCTAssertEqual(score.ungrounded, 2, "the invented note and the note whose words are ten minutes away")

        let alone = NotesScoring.grounding(of: [grounded], in: segments)
        XCTAssertEqual(alone.meanOverlap, 1, accuracy: 0.001)

        let unlinked = NotesDraft.Item(kind: .actionItem, text: "Maria sends the link.")
        XCTAssertEqual(NotesScoring.grounding(of: [unlinked], in: segments).ungrounded, 0,
                       "with no timestamp the whole transcript counts")
    }

    func testLanguageMixLeansTheRightWay() {
        let tagalog = NotesScoring.languageMix(of: "Sige, mag-start na tayo. Na-send ko na yung email kahapon pero hindi pa na-approve.")
        let english = NotesScoring.languageMix(of: "The group agreed to review the taxonomy on Thursday and send the sheet to Maria.")
        XCTAssertGreaterThan(tagalog.tagalogShare, 0.5)
        XCTAssertLessThan(english.tagalogShare, 0.1)
        XCTAssertEqual(english.words, 15)
    }

    func testCoverageCountsHandWrittenNotesTheDraftAlsoHas() {
        let reference = [
            MeetingItem(kind: .decision, text: "Paint color goes in attributes, not variants, because every color costs the same."),
            MeetingItem(kind: .followUp, text: "The sub-modules will be worked on Thursday."),
            MeetingItem(kind: .actionItem, text: "Send Maria the link and confirm with him."),
        ]
        let draft = [
            NotesDraft.Item(kind: .decision, text: "Paint color is an attribute rather than a variant since every color costs the same."),
            NotesDraft.Item(kind: .keyPoint, text: "The backbone is shared by everyone."),
        ]
        let coverage = NotesScoring.coverage(reference: reference, draft: draft)
        XCTAssertEqual(coverage.reference, 3)
        XCTAssertEqual(coverage.covered, 1)
        XCTAssertEqual(coverage.draft, 2)
        XCTAssertEqual(coverage.matched, 1)
    }

    // MARK: - Prompt

    func testPromptNamesTheStyleAndThePart() {
        XCTAssertTrue(NotesPrompt.instructions(style: .english).contains("in English"))
        XCTAssertTrue(NotesPrompt.instructions(style: .asSpoken).contains("same mix of languages"))
        let chunk = NotesChunker.chunks(from: meeting(2), speakers: roster)[0]
        let request = NotesPrompt.request(for: chunk)
        XCTAssertTrue(request.contains("part 1"))
        XCTAssertTrue(request.contains("[0:05] Maria:"))
        XCTAssertTrue(request.contains("\"items\""))
        let summary = NotesPrompt.summaryRequest(partSummaries: ["A", "B"], title: "Taxonomy")
        XCTAssertTrue(summary.contains("Part 2: B"))
        XCTAssertTrue(summary.contains("\"Taxonomy\""))
    }

    func testProgressLabelsAndFraction() {
        let reading = NotesProgress(stage: .reading, chunksDone: 2, chunkCount: 10)
        XCTAssertEqual(reading.label, "Part 3 of 10")
        XCTAssertEqual(reading.fraction, 0.18, accuracy: 0.001)
        let last = NotesProgress(stage: .reading, chunksDone: 10, chunkCount: 10)
        XCTAssertEqual(last.label, "Part 10 of 10")
        let summarizing = NotesProgress(stage: .summarizing, chunksDone: 10, chunkCount: 10)
        XCTAssertEqual(summarizing.label, "Writing the summary")
        XCTAssertEqual(summarizing.fraction, 0.95)
    }
}
