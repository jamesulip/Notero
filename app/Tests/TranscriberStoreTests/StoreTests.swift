import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

@MainActor
final class StoreTests: XCTestCase {

    /// The container has to outlive the context. `mainContext` is owned by the
    /// container, so `StoreContainer.ephemeral().mainContext` hands back a
    /// context whose owner is already being deallocated.
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        container.mainContext
    }

    private func seed(_ context: ModelContext, title: String = "Team Meeting")
    throws -> StoredRecording {
        let recording = try RecordingStore.create(kind: .meeting, title: title, in: context)
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        for (index, text) in ["Magandang araw po.", "Let's target September 15 for launch."]
            .enumerated() {
            let segment = StoredSegment(index: index, startMs: index * 4_000,
                                        endMs: index * 4_000 + 3_000, text: text,
                                        speakerId: index == 0 ? "S1" : "S2")
            segment.transcript = transcript
            context.insert(segment)
        }
        RecordingStore.syncSpeakers(
            [SpeakerLabel(id: "S1", displayName: "Juan", speechMs: 3_000),
             SpeakerLabel(id: "S2", displayName: "Maria", speechMs: 3_000)],
            on: recording, in: context
        )
        recording.durationMs = 8_000
        recording.status = .completed
        RecordingStore.reindex(recording)
        try context.save()
        return recording
    }

    // MARK: - History grouping

    func testHistoryGroupsByDay() throws {
        let now = Date()
        let calendar = Calendar.current
        let context = try makeContext()

        let today = try RecordingStore.create(kind: .recording, title: "Today", in: context, at: now)
        let yesterday = try RecordingStore.create(
            kind: .recording, title: "Yesterday", in: context,
            at: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let old = try RecordingStore.create(
            kind: .recording, title: "Old", in: context,
            at: calendar.date(byAdding: .day, value: -30, to: now)!
        )

        let sections = RecordingStore.group([old, today, yesterday], now: now)
        XCTAssertEqual(sections.map(\.bucket), [.today, .yesterday, .older])
        XCTAssertEqual(sections[0].items.first?.title, "Today")
    }

    func testFailedRecordingsAreGroupedForAttentionAheadOfTheDates() throws {
        let now = Date()
        let context = try makeContext()
        let fine = try RecordingStore.create(kind: .recording, title: "Fine", in: context, at: now)
        let broken = try RecordingStore.create(
            kind: .recording, title: "Broken", in: context,
            at: Calendar.current.date(byAdding: .day, value: -40, to: now)!
        )
        broken.status = .failed

        let sections = RecordingStore.group([fine, broken], now: now)
        XCTAssertEqual(sections.map(\.bucket), [.attention, .today])
        XCTAssertEqual(sections[0].items.map(\.title), ["Broken"],
                       "a failed row surfaces however old it is")
    }

    func testHistoryIsNewestFirstWithinASection() throws {
        // Midday, fixed. With `Date()` this passed all day and failed after
        // midnight: "an hour ago" crosses into yesterday, so the two recordings
        // land in different sections and the ordering being asserted here is
        // not the ordering under test.
        var parts = DateComponents()
        parts.year = 2026; parts.month = 8; parts.day = 30
        parts.hour = 12; parts.minute = 0
        let now = Calendar.current.date(from: parts)!

        let context = try makeContext()
        let older = try RecordingStore.create(kind: .recording, title: "Earlier",
                                              in: context, at: now.addingTimeInterval(-3_600))
        let newer = try RecordingStore.create(kind: .recording, title: "Later",
                                              in: context, at: now)
        let section = RecordingStore.group([older, newer], now: now).first
        XCTAssertEqual(section?.bucket, .today)
        XCTAssertEqual(section?.items.map(\.title), ["Later", "Earlier"])
    }

    // MARK: - Speakers

    func testRenamingASpeakerDoesNotTouchSegments() throws {
        let context = try makeContext()
        let recording = try seed(context)
        let speaker = (recording.speakers ?? []).first { $0.speakerId == "S1" }!

        try RecordingStore.rename(speaker, to: "Paolo", in: context)

        XCTAssertEqual(speaker.displayName, "Paolo")
        // Segments hold the diarizer label, so a rename is one row, not thousands.
        XCTAssertEqual(recording.transcript?.orderedSegments.first?.speakerId, "S1")
        XCTAssertEqual(RecordingStore.document(for: recording).name(for: "S1"), "Paolo")
    }

    func testBlankRenameFallsBackToTheDefaultName() throws {
        let context = try makeContext()
        let recording = try seed(context)
        let speaker = (recording.speakers ?? []).first { $0.speakerId == "S2" }!
        try RecordingStore.rename(speaker, to: "   ", in: context)
        XCTAssertEqual(speaker.displayName, "Speaker 2")
    }

    func testSyncSpeakersDropsLabelsTheNewTranscriptNoLongerUses() throws {
        let context = try makeContext()
        let recording = try seed(context)
        RecordingStore.syncSpeakers([SpeakerLabel(id: "S1", displayName: "Juan")],
                                    on: recording, in: context)
        try context.save()
        XCTAssertEqual((recording.speakers ?? []).map(\.speakerId), ["S1"])
    }

    // MARK: - Notes

    func testMeetingItemKeepsItsSourceSegment() throws {
        let context = try makeContext()
        let recording = try seed(context)
        let segment = recording.transcript!.orderedSegments[1]

        let item = try RecordingStore.addItem(.decision, text: "Launch September 15",
                                              source: segment, to: recording, in: context)

        XCTAssertEqual(item.sourceSegmentId, segment.id)
        XCTAssertEqual(item.sourceMs, segment.startMs)
        XCTAssertEqual(RecordingStore.items(.decision, of: recording).count, 1)
    }

    func testRetranscribingLeavesNotesIntactAsADanglingSource() throws {
        // Notes hold a plain id, not a relationship, so replacing the
        // transcript degrades a back-link to "no source" instead of cascading
        // the user's note away.
        let context = try makeContext()
        let recording = try seed(context)
        let segment = recording.transcript!.orderedSegments[1]
        let item = try RecordingStore.addItem(.decision, text: "Launch",
                                              source: segment, to: recording, in: context)

        let replacement = StoredTranscript(revision: 2, modelId: "large", language: "tl")
        replacement.recording = recording
        context.insert(replacement)
        for old in recording.transcripts?.first(where: { $0.revision == 1 })?.orderedSegments ?? [] {
            context.delete(old)
        }
        try context.save()

        XCTAssertEqual(recording.transcript?.revision, 2)
        XCTAssertNotNil(item.sourceSegmentId)
        XCTAssertEqual(item.text, "Launch")
    }

    func testNewestTranscriptWins() throws {
        let context = try makeContext()
        let recording = try seed(context)
        let second = StoredTranscript(revision: 2, modelId: "large-v3", language: "tl")
        second.recording = recording
        context.insert(second)
        try context.save()
        XCTAssertEqual(recording.transcript?.modelId, "large-v3")
    }

    // MARK: - Bookmarks

    func testBookmarksKeepTimestampsNotAudio() throws {
        let context = try makeContext()
        let recording = try seed(context)
        let bookmark = try RecordingStore.addBookmark(at: 5_400, to: recording, in: context)
        XCTAssertEqual(bookmark.atMs, 5_400)
        XCTAssertEqual(bookmark.displayLabel, "Bookmark at 0:05")
    }

    // MARK: - Search

    func testSearchFindsATranscriptLineAndPointsAtItsTimestamp() throws {
        let context = try makeContext()
        let recording = try seed(context)

        let hits = try SearchService.search("september 15", in: context)
        let transcriptHit = hits.first { $0.scope == .transcript }

        XCTAssertNotNil(transcriptHit)
        XCTAssertEqual(transcriptHit?.recordingId, recording.id)
        XCTAssertEqual(transcriptHit?.atMs, 4_000)
        XCTAssertNotNil(transcriptHit?.segmentId)
        XCTAssertFalse(transcriptHit?.highlights.isEmpty ?? true)
    }

    func testSearchAlsoCoversNotesAndBookmarkLabels() throws {
        let context = try makeContext()
        let recording = try seed(context)
        try RecordingStore.addItem(.actionItem, text: "Book the venue",
                                   to: recording, in: context)
        try RecordingStore.addBookmark(at: 1_000, label: "Venue chat",
                                       to: recording, in: context)
        RecordingStore.reindex(recording)
        try context.save()

        XCTAssertTrue(try SearchService.search("venue", in: context)
            .contains { $0.scope == .note })
        XCTAssertTrue(try SearchService.search("venue chat", in: context)
            .contains { $0.scope == .bookmark })
    }

    func testSearchIsCaseAndDiacriticInsensitive() throws {
        let context = try makeContext()
        _ = try seed(context, title: "Mañana Sync")
        XCTAssertFalse(try SearchService.search("manana", in: context).isEmpty)
    }

    func testSearchRequiresEveryTerm() throws {
        let context = try makeContext()
        _ = try seed(context)
        XCTAssertTrue(try SearchService.search("september budget", in: context).isEmpty)
    }

    func testEmptyQueryReturnsNothingRatherThanEverything() throws {
        let context = try makeContext()
        _ = try seed(context)
        XCTAssertTrue(try SearchService.search("   ", in: context).isEmpty)
    }

    // MARK: - Export payload

    func testDocumentFlattensTheWholeGraph() throws {
        let context = try makeContext()
        let recording = try seed(context)
        try RecordingStore.addBookmark(at: 2_000, label: "Intro", to: recording, in: context)
        try RecordingStore.addItem(.keyPoint, text: "Launch scope",
                                   to: recording, in: context)
        recording.summary = "Planning."
        try context.save()

        let document = RecordingStore.document(for: recording)
        XCTAssertEqual(document.title, "Team Meeting")
        XCTAssertEqual(document.segments.count, 2)
        XCTAssertEqual(document.speakers.count, 2)
        XCTAssertEqual(document.bookmarks.count, 1)
        XCTAssertEqual(document.items(.keyPoint).count, 1)
        XCTAssertEqual(document.summary, "Planning.")
        XCTAssertEqual(document.name(for: "S2"), "Maria")
    }

    func testDeletingARecordingCascadesToEverythingUnderIt() throws {
        let context = try makeContext()
        let recording = try seed(context)
        try RecordingStore.addBookmark(at: 1, to: recording, in: context)
        try RecordingStore.delete(recording, in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredRecording>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredSegment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredBookmark>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredSpeaker>()).isEmpty)
    }

    func testTagsAreReusedRatherThanDuplicated() throws {
        let context = try makeContext()
        let first = try RecordingStore.tag(named: "client", in: context)
        try context.save()
        let second = try RecordingStore.tag(named: " client ", in: context)
        XCTAssertIdentical(first, second)
    }
}
