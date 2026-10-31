import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// Where the store's actors run, and whether the main context still reads what
/// they saved (finding 32).
///
/// A `@ModelActor` runs a call on the thread of the caller. `AppState` is on the
/// main actor, so `await writer.completeTranscript(...)` was main-thread work and
/// froze the window for 6.5 s at 15,000 rows, however the writer had been made.
extension TranscriptWriter {
    func probeIsMainThread() -> Bool { Thread.isMainThread }
    func probeSearchText(of id: UUID) throws -> String? {
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.searchText
    }
}
extension TranscriptReader {
    func probeIsMainThread() -> Bool { Thread.isMainThread }
}
extension SearchReader {
    func probeIsMainThread() -> Bool { Thread.isMainThread }
}

@MainActor
final class WriterOffMainTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    /// On disk, as the app's store is: an in-memory store behaves differently.
    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-off-main-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let schema = Schema(TranscriberSchema.models)
        container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: scratch.appendingPathComponent("t.store"))
        ])
    }

    override func tearDown() async throws {
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    private func descriptor(_ id: UUID) -> FetchDescriptor<StoredRecording> {
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func segment(_ index: Int, _ text: String = "linya") -> Segment {
        Segment(index: index, startMs: index * 1_000, endMs: index * 1_000 + 900, text: "\(text) \(index)")
    }

    private static var cycles: Int {
        ProcessInfo.processInfo.environment["NOTERO_RAW_CYCLES"].flatMap(Int.init) ?? 120
    }

    // MARK: - Where they run

    /// Called from the main actor, which is what every view and `AppState`
    /// method does. With `@ModelActor` all three answered true.
    func testTheStoreActorsRunOffTheMainThreadWhenTheMainActorCallsThem() async throws {
        let writer = TranscriptWriter(modelContainer: container)
        let reader = TranscriptReader(modelContainer: container)
        let searcher = SearchReader(modelContainer: container)
        var onMain = ["writer": 0, "reader": 0, "searcher": 0]
        for _ in 0..<20 {
            if await writer.probeIsMainThread() { onMain["writer", default: 0] += 1 }
            if await reader.probeIsMainThread() { onMain["reader", default: 0] += 1 }
            if await searcher.probeIsMainThread() { onMain["searcher", default: 0] += 1 }
        }
        XCTAssertEqual(onMain, ["writer": 0, "reader": 0, "searcher": 0],
                       "calls from the main actor that ran on the main thread, out of 20")
    }

    // MARK: - The window while Stop saves

    /// The main actor ticks every 10 ms and reports its longest gap. `precondition`
    /// is what makes a gap of 0 mean something (QA: two earlier tests passed with a
    /// ticker that never ran).
    private func tick<T: Sendable>(
        during work: () async throws -> T
    ) async rethrows -> (value: T, longestGapMs: Double, ticks: Int) {
        let ticker = Task { @MainActor () -> (gapMs: Double, ticks: Int) in
            var longest = 0.0
            var ticks = 0
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ContinuousClock.now
                let gap = now - last
                longest = max(longest, Double(gap.components.seconds) * 1000
                              + Double(gap.components.attoseconds) / 1e15)
                last = now
                ticks += 1
            }
            return (longest, ticks)
        }
        // The ticker has to be running before the work starts.
        try? await Task.sleep(for: .milliseconds(60))
        let value = try await work()
        ticker.cancel()
        let (gap, ticks) = await ticker.value
        return (value, gap, ticks)
    }

    /// Stop on a long meeting: the live rows are in the store, and the final list
    /// replaces them. `NOTERO_STOP_ROWS` sets the length; 15,000 is a six-hour
    /// meeting and takes about 20 s here.
    func testTheWindowKeepsMovingWhileStopSavesALongTranscript() async throws {
        let rows = ProcessInfo.processInfo.environment["NOTERO_STOP_ROWS"].flatMap(Int.init) ?? 3_000
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let persister = LiveTranscriptPersister(writer: writer, recordingId: id, modelId: "turbo",
                                                language: "tl", flushIntervalMs: 0)
        await persister.open()
        let all = (0..<rows).map { segment($0) }
        var batch = 0
        while batch < rows {
            persister.append(Array(all[batch..<min(rows, batch + 250)]))
            await persister.drain()
            batch += 250
        }

        let result = try await tick {
            try await persister.complete(segments: all, processMs: 1)
        }
        print("Stop at \(rows) rows: completeTranscript ticked the main actor \(result.ticks) times, "
              + "longest main-actor gap \(Int(result.longestGapMs)) ms")
        XCTAssertGreaterThan(result.ticks, 5,
                             "the ticker has to have run during the save, or a gap of 0 means nothing")
        XCTAssertLessThan(result.longestGapMs, 400, "the window must not freeze for a save")

        let saved = try ModelContext(container).fetchCount(FetchDescriptor<StoredSegment>())
        XCTAssertEqual(saved, rows, "and the transcript is all there")
    }

    // MARK: - Read after write

    /// What the main context shows the moment `await writer.x()` returns, read the
    /// way `AppState` reads it: through a fetch (`recording(_:)`), which is also
    /// what a `@Query` does. The writer is off the main thread here, which the
    /// earlier measurement (300 of 300) did not cover: it ran the writer on the
    /// main thread. `NOTERO_RAW_CYCLES` raises the count.
    ///
    /// **A held object is a different matter, and it is the same with or without
    /// this change.** A `StoredRecording` that was fetched earlier is not updated
    /// by another context's save at all, however long the main actor waits (100
    /// of 100 checks, 200 ms each, with the writer on the main thread as well as
    /// off it); it takes a fetch on its own context. Nothing in `AppState` reads a
    /// held row after a write without fetching: `performStop` goes through
    /// `recording(_:)`. `heldObjectsNeedAFetchToSeeAnotherContextsSave` records the
    /// behaviour so that a new call site cannot assume otherwise.
    func testTheMainContextSeesWhatTheWriterSavedAsSoonAsTheCallReturns() async throws {
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let writer = TranscriptWriter(modelContainer: container)

        let openedRevision = try await writer.openPartialTranscript(modelId: "m", language: "tl", for: id)
        let openId = try XCTUnwrap(openedRevision)
        var stale: [String: Int] = [:]
        func check(_ name: String, _ ok: Bool) { if !ok { stale[name, default: 0] += 1 } }
        func recording() throws -> StoredRecording { try XCTUnwrap(try main.fetch(descriptor(id)).first) }

        var rows = 0
        for cycle in 0..<Self.cycles {
            let ms = 1_000 + cycle

            // attachAudio: what the whole-file pass of a two-lane recording reads.
            try await writer.attachAudio(fileName: "2026/11/a\(cycle).m4a", sampleRate: 48_000,
                                         durationMs: ms, waveform: [0.1, 0.2],
                                         lanes: [.room, .remote], for: id)
            let fetched = try recording()
            check("attachAudio", fetched.durationMs == ms
                  && fetched.audioFileName == "2026/11/a\(cycle).m4a" && fetched.lanes == [.room, .remote]
                  && fetched.audioSampleRate == 48_000 && fetched.waveform == [0.1, 0.2])
            let sidebar = try main.fetch(FetchDescriptor<StoredRecording>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            check("attachAudio, sidebar fetch", sidebar.first?.durationMs == ms)

            // updateStatus.
            let status: TranscriptionStatus = cycle % 2 == 0 ? .transcribing : .completed
            let failure: String? = cycle % 3 == 0 ? "e\(cycle)" : nil
            try await writer.updateStatus(status, progress: 0.5, error: failure, for: id)
            let afterStatus = try recording()
            check("updateStatus", afterStatus.status == status && afterStatus.errorMessage == failure)

            // setWarning.
            let warning: String? = cycle % 2 == 0 ? "w\(cycle)" : nil
            try await writer.setWarning(warning, for: id)
            check("setWarning", try recording().warningMessage == warning)

            // appendPartial: the rows and the relationship.
            try await writer.appendPartial([segment(rows)], to: openId)
            rows += 1
            check("appendPartial, row fetch", try TranscriptReader
                .segmentRows(ofTranscript: openId, in: main).count == rows)
            check("appendPartial, fetchCount", try main.fetchCount(FetchDescriptor<StoredSegment>()) == rows)
            check("appendPartial, relationship", try recording().transcript?.segments?.count == rows)
        }
        print("read-after-write through a fetch, \(Self.cycles) cycles, writer off the main thread, stale reads: \(stale)")
        XCTAssertEqual(stale, [:], "the main context did not see a save that had returned")
    }

    /// Characterisation, not a wish: a row held on the main context does not see
    /// another context's save until the main context fetches. The same on the old
    /// code, with the writer on the main thread. A fetch does refresh the held row.
    func testHeldObjectsNeedAFetchToSeeAnotherContextsSave() async throws {
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let writer = TranscriptWriter(modelContainer: container)
        let held = try XCTUnwrap(try main.fetch(descriptor(id)).first)
        var freshWithoutFetch = 0, freshAfterFetch = 0
        let cycles = 40
        for cycle in 0..<cycles {
            let status: TranscriptionStatus = cycle % 2 == 0 ? .transcribing : .completed
            try await writer.updateStatus(status, progress: 0.5, for: id)
            if held.status == status { freshWithoutFetch += 1 }
            _ = try main.fetch(descriptor(id))
            if held.status == status { freshAfterFetch += 1 }
        }
        print("held row after a writer save: fresh without a fetch \(freshWithoutFetch)/\(cycles), after a fetch \(freshAfterFetch)/\(cycles)")
        XCTAssertEqual(freshAfterFetch, cycles, "a fetch must bring a held row up to date")
    }

    /// `RecordingStore.refresh` is what `AppState` calls before it tells a view to
    /// re-read. A held recording, its transcripts and a held speaker, all fetched
    /// earlier, as the views hold them, must be current right after it.
    func testRefreshBringsHeldRowsUpToDateTheMomentTheWriterReturns() async throws {
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let writer = TranscriptWriter(modelContainer: container)
        try await writer.storeTranscript(
            segments: [segment(0)], roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 1)],
            modelId: "m", language: "tl", processMs: 1, didDiarize: false, for: id)
        let held = try XCTUnwrap(try main.fetch(descriptor(id)).first)
        let heldSpeaker = try XCTUnwrap(held.speakers?.first)
        var stale: [String: Int] = [:]
        func check(_ name: String, _ ok: Bool) { if !ok { stale[name, default: 0] += 1 } }
        var withoutRefreshFresh = 0

        for cycle in 0..<Self.cycles {
            let status: TranscriptionStatus = cycle % 2 == 0 ? .transcribing : .completed
            try await writer.updateStatus(status, progress: 0.5, for: id)
            if held.status == status { withoutRefreshFresh += 1 }
            RecordingStore.refresh(id, in: main)
            check("status", held.status == status)

            try await writer.applySpeakers(
                spans: [SpeakerSpan(speakerId: "S1", startMs: 0, endMs: 10_000)],
                roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 100 + cycle)], for: id)
            RecordingStore.refresh(id, in: main)
            check("speaker speechMs", heldSpeaker.speechMs == 100 + cycle)
            // The speakers are applied to the newest revision, which is a row the
            // main context has held since the refresh before this one.
            check("transcript didDiarize", held.transcript?.didDiarize == true)

            // A new revision: the held recording must list it.
            try await writer.storeTranscript(
                segments: [segment(0)], roster: [], modelId: "m\(cycle)", language: "tl",
                processMs: 1, didDiarize: false, for: id)
            RecordingStore.refresh(id, in: main)
            check("revisions listed", held.transcripts?.count == cycle + 2)
            check("newest revision is the new one", held.transcript?.modelId == "m\(cycle)")
        }
        print("refresh: \(Self.cycles) cycles, stale after refresh \(stale); without it the status was current "
              + "in \(withoutRefreshFresh) of \(Self.cycles)")
        XCTAssertEqual(stale, [:])
        XCTAssertLessThan(withoutRefreshFresh, Self.cycles,
                          "if a held row were current without a refresh, this call would be unnecessary")
    }

    /// The revision swap and the edits that follow a transcript: after each call
    /// the main context must show the new rows, the one transcript that remains
    /// and its flags.
    func testTheMainContextSeesTheRevisionSwapAndTheEditsThatFollow() async throws {
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let writer = TranscriptWriter(modelContainer: container)
        var stale: [String: Int] = [:]
        func check(_ name: String, _ ok: Bool) { if !ok { stale[name, default: 0] += 1 } }
        func recording() throws -> StoredRecording { try XCTUnwrap(try main.fetch(descriptor(id)).first) }

        for cycle in 0..<(Self.cycles / 2) {
            let open = try await writer.openPartialTranscript(modelId: "m", language: "tl", for: id)
            let openId = try XCTUnwrap(open)
            try await writer.appendPartial((0..<3).map { segment($0, "partial\(cycle)") }, to: openId)

            let finalRows = (0..<4).map { segment($0, "final\(cycle)") }
            let revision = try await writer.completeTranscript(
                openId, segments: finalRows, roster: [], modelId: "m", language: "tl",
                processMs: 1, didDiarize: false, for: id)
            // The open revision is gone and the final one took its number: one
            // transcript for each cycle so far, none of them the partial one.
            let afterComplete = try recording()
            check("complete, transcripts so far", afterComplete.transcripts?.count == cycle + 1)
            check("complete, the open revision is gone",
                  !(afterComplete.transcripts ?? []).contains { $0.id == openId })
            let latest = try XCTUnwrap(afterComplete.transcript)
            check("complete, newest is complete", latest.isComplete)
            check("complete, revision", latest.revision == revision)
            let latestId = latest.id
            check("complete, rows of the new revision", try TranscriptReader
                .segmentRows(ofTranscript: latestId, in: main).map(\.text) == finalRows.map(\.text))
            check("complete, the partial rows are gone", try TranscriptReader
                .segmentRows(ofTranscript: openId, in: main).isEmpty)

            // An edit to one turn, in place.
            let replacement = [Segment(index: 0, startMs: 0, endMs: 900, text: "edited\(cycle)")]
            try await writer.replaceSegments(fromMs: 0, toMs: 1_000, with: replacement, for: id)
            check("replaceSegments, first row", try TranscriptReader
                .segmentRows(ofTranscript: latestId, in: main).first?.text == "edited\(cycle)")

            // Speakers.
            let spans = [SpeakerSpan(speakerId: "S1", startMs: 0, endMs: 10_000)]
            try await writer.applySpeakers(spans: spans,
                                           roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 4_000)],
                                           for: id)
            let afterSpeakers = try recording()
            check("applySpeakers, labels on the rows", try TranscriptReader
                .segmentRows(ofTranscript: latestId, in: main).allSatisfy { $0.speakerId == "S1" })
            check("applySpeakers, roster", afterSpeakers.speakers?.count == 1)
            // A transcript row is its own object: read it through a fetch of it.
            var byId = FetchDescriptor<StoredTranscript>(predicate: #Predicate { $0.id == latestId })
            byId.fetchLimit = 1
            check("applySpeakers, didDiarize", try main.fetch(byId).first?.didDiarize == true)

            try await writer.finishTranscription(durationMs: 5_000 + cycle, waveform: nil, for: id)
            check("finishTranscription, duration", try recording().durationMs == 5_000 + cycle)
        }
        print("revision swap, \(Self.cycles / 2) cycles, writer off the main thread, stale reads: \(stale)")
        XCTAssertEqual(stale, [:], "the main context did not see a save that had returned")
    }

    /// The other direction: a name typed in the window and saved on the main
    /// context has to be what the writer indexes, or a rename is lost from search
    /// by the next save (the writer's context is long-lived).
    func testTheWriterIndexesTheTitleThatTheWindowJustSaved() async throws {
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let writer = TranscriptWriter(modelContainer: container)
        try await writer.setWarning("first", for: id)      // the writer's context loads the row now
        var stale = 0
        for cycle in 0..<Self.cycles {
            let recording = try XCTUnwrap(try main.fetch(descriptor(id)).first)
            recording.title = "Pulong \(cycle)"
            try main.save()
            try await writer.storeTranscript(segments: [segment(0)], roster: [], modelId: "m",
                                             language: "tl", processMs: 1, didDiarize: false, for: id)
            let indexed = try await writer.probeSearchText(of: id)
            if indexed?.contains("Pulong \(cycle)") != true { stale += 1 }
        }
        XCTAssertEqual(stale, 0, "the index was built from a title the window had already replaced")
    }
}
