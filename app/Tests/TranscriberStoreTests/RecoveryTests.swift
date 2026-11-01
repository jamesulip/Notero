import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// What happens to work the last run did not finish.
///
/// A live session and the transcription queue both die with the process, so
/// any row still claiming to be `preparing`, `recording` or `transcribing` on
/// the next launch is describing a job that no longer exists. Those statuses
/// report `isTerminal == false`, which is what left two recordings in this
/// user's library stuck on `preparing` with no audio, no error and no way out.
@MainActor
final class RecoveryTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private var context: ModelContext { container.mainContext }

    private func recording(_ status: TranscriptionStatus,
                           audio: String? = nil) throws -> StoredRecording {
        let recording = try RecordingStore.create(kind: .recording, in: context)
        recording.status = status
        recording.audioFileName = audio
        try context.save()
        return recording
    }

    func testARecordingInterruptedBeforeCaptureFailsWithAnHonestReason() throws {
        // The real case: audioFileName was allocated, the model was still
        // loading, the app went away.
        let stranded = try recording(.preparing, audio: "2026/09/nothing.m4a")

        XCTAssertEqual(try RecordingStore.recoverInterrupted(in: context), 1)

        XCTAssertEqual(stranded.status, .failed)
        XCTAssertTrue(stranded.errorMessage?.contains("any audio was captured") ?? false,
                      "got: \(stranded.errorMessage ?? "nil")")
    }

    func testEveryNonTerminalStatusIsRecovered() throws {
        let stale = TranscriptionStatus.allCases.filter { !$0.isTerminal }
        XCTAssertFalse(stale.isEmpty)
        for status in stale { _ = try recording(status) }

        XCTAssertEqual(try RecordingStore.recoverInterrupted(in: context), stale.count)

        let all = try context.fetch(FetchDescriptor<StoredRecording>())
        XCTAssertTrue(all.allSatisfy(\.status.isTerminal),
                      "a non-terminal status survived recovery")
    }

    func testFinishedRecordingsAreLeftAlone() throws {
        let done = try recording(.completed)
        let cancelled = try recording(.cancelled)
        let failed = try recording(.failed)
        failed.errorMessage = "the original reason"

        XCTAssertEqual(try RecordingStore.recoverInterrupted(in: context), 0)

        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(failed.errorMessage, "the original reason",
                       "recovery must not overwrite a real failure")
    }

    func testNothingIsDeleted() throws {
        _ = try recording(.preparing)
        _ = try recording(.recording)

        try RecordingStore.recoverInterrupted(in: context)

        // A row with no audio is still a row the user made. Marking it failed
        // is honest; removing it silently is not.
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecording>()).count, 2)
    }

    func testAReadableTranscriptSurvivesAsCompleted() throws {
        // Quit during diarization: the transcript is intact and useful, so
        // failing the whole recording would throw away good work.
        let recording = try self.recording(.diarizing, audio: "2026/09/x.m4a")
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        try context.save()

        try RecordingStore.recoverInterrupted(in: context)

        XCTAssertEqual(recording.status, .completed)
        XCTAssertNil(recording.errorMessage)
    }

    func testAPartialTranscriptIsKeptButNotCalledComplete() throws {
        // Quit mid-decode: rows were appended per window and the job never
        // closed the revision. Calling that completed would pass off half a
        // meeting as the whole thing.
        let recording = try self.recording(.transcribing, audio: "2026/09/x.m4a")
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.isComplete = false
        transcript.recording = recording
        context.insert(transcript)
        let row = StoredSegment(index: 0, startMs: 0, endMs: 3_000, text: "Simula.")
        row.transcript = transcript
        context.insert(row)
        try context.save()

        try RecordingStore.recoverInterrupted(in: context)

        XCTAssertEqual(recording.status, .failed)
        XCTAssertTrue(recording.errorMessage?.contains("part-way") ?? false,
                      "got: \(recording.errorMessage ?? "nil")")
        XCTAssertEqual(recording.transcript?.orderedSegments.count, 1, "the rows stay")
        XCTAssertEqual(recording.transcript?.isComplete, false)
    }
}

extension RecoveryTests {
    func testAnInterruptedLiveRecordingKeepsItsCommittedLines() throws {
        // The live session writes committed lines as it goes. A crash
        // mid-meeting leaves those rows under an open revision on a row still
        // marked `recording`; they must survive, and the message must say so.
        let recording = try RecordingStore.create(kind: .meeting, in: context)
        recording.status = .recording
        recording.audioFileName = "2026/09/live.m4a"
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.isComplete = false
        transcript.recording = recording
        context.insert(transcript)
        for (index, text) in ["So yung quotation", "kailangan nating i-send tomorrow"].enumerated() {
            let row = StoredSegment(index: index, startMs: index * 2_000,
                                    endMs: index * 2_000 + 1_900, text: text)
            row.transcript = transcript
            context.insert(row)
        }
        try context.save()

        try RecordingStore.recoverInterrupted(in: context)

        XCTAssertEqual(recording.status, .failed)
        XCTAssertTrue(recording.errorMessage?.contains("Recording was interrupted") ?? false,
                      "got: \(recording.errorMessage ?? "nil")")
        XCTAssertEqual(recording.transcript?.orderedSegments.map(\.text),
                       ["So yung quotation", "kailangan nating i-send tomorrow"])
        XCTAssertEqual(recording.transcript?.isComplete, false)
    }
}

// MARK: - What survived (finding 16)

private let workingCopyOnly = RecordingStore.SurvivingAudio(archiveMs: nil, workingCopyMs: 2_700_000)
private let nothingLeft = RecordingStore.SurvivingAudio()

extension RecoveryTests {

    /// A recording that quit while it was recording: its AAC archive was never
    /// closed, so the file exists and does not open.
    private func quitWhileRecording(transcript rows: [String]? = nil) throws -> StoredRecording {
        let recording = try RecordingStore.create(kind: .meeting, in: context)
        recording.status = .recording
        recording.audioFileName = "2026/10/unclosed.m4a"
        if let rows {
            let transcript = StoredTranscript(modelId: "turbo", language: "tl")
            transcript.isComplete = false
            transcript.recording = recording
            context.insert(transcript)
            for (index, text) in rows.enumerated() {
                let row = StoredSegment(index: index, startMs: index * 2_000,
                                        endMs: index * 2_000 + 1_900, text: text)
                row.transcript = transcript
                context.insert(row)
            }
        }
        try context.save()
        return recording
    }

    func testAnUnclosedArchiveWithAWorkingCopySaysSoAndDoesNotPromiseThatItPlays() throws {
        let recording = try quitWhileRecording()

        try RecordingStore.recoverInterrupted(in: context) { _ in workingCopyOnly }

        XCTAssertEqual(recording.status, .failed)
        let message = recording.errorMessage ?? ""
        XCTAssertFalse(message.contains("The audio is here"),
                       "that sentence sent the user to a re-run on a file nothing can open: \(message)")
        XCTAssertTrue(message.contains("will not play"), message)
        XCTAssertTrue(message.contains("copy of the audio was kept"), message)
        XCTAssertTrue(message.contains("Transcribe Again"), message)
        XCTAssertEqual(recording.durationMs, 2_700_000,
                       "the length is written at Stop, which never came; the copy knows it")
    }

    func testAnUnclosedArchiveWithNothingElseAdmitsThatNothingSurvived() throws {
        let recording = try quitWhileRecording(transcript: ["So yung quotation"])

        try RecordingStore.recoverInterrupted(in: context) { _ in nothingLeft }

        let message = recording.errorMessage ?? ""
        XCTAssertTrue(message.contains("No audio survived"), message)
        XCTAssertFalse(message.contains("transcribe again to redo"),
                       "there is nothing left to redo it from: \(message)")
        XCTAssertEqual(recording.transcript?.orderedSegments.map(\.text), ["So yung quotation"],
                       "the saved lines are all that is left, and they stay")
    }

    func testAnInterruptedLiveRecordingWithAWorkingCopyStillOffersTheRedo() throws {
        let recording = try quitWhileRecording(transcript: ["Una.", "Pangalawa."])

        try RecordingStore.recoverInterrupted(in: context) { _ in workingCopyOnly }

        let message = recording.errorMessage ?? ""
        XCTAssertTrue(message.contains("Recording was interrupted"), message)
        XCTAssertTrue(message.contains("transcribe again to redo it from the audio"), message)
        XCTAssertTrue(message.contains("will not play"), message)
    }

    /// A two-lane recording that was killed: its working copy is the room and the
    /// call mixed, and the archive did not close. Transcribe Again will work from
    /// the copy, as one lane, and the message has to say that rather than promise
    /// the two sides apart (finding 33).
    func testATwoLaneRecordingWhoseArchiveDidNotCloseSaysItWillBeOneLane() throws {
        let recording = try quitWhileRecording()
        recording.lanes = [.room, .remote]
        try context.save()

        try RecordingStore.recoverInterrupted(in: context) { _ in workingCopyOnly }

        let message = recording.errorMessage ?? ""
        XCTAssertTrue(message.contains("Transcribe Again"), message)
        XCTAssertTrue(message.contains("which side"), "the cost of the mixed copy must be said: \(message)")
        XCTAssertEqual(recording.lanes, [.room, .remote], "recovery keeps what was recorded")
    }

    func testAOneLaneRecordingDoesNotGetTheTwoLaneSentence() throws {
        let recording = try quitWhileRecording()

        try RecordingStore.recoverInterrupted(in: context) { _ in workingCopyOnly }

        XCTAssertFalse((recording.errorMessage ?? "").contains("which side"))
    }

    /// A readable archive still has both channels: the lanes are kept.
    func testATwoLaneRecordingWhoseArchiveIsReadableKeepsTheOriginalPromise() throws {
        let recording = try quitWhileRecording()
        recording.lanes = [.room, .remote]
        try context.save()

        try RecordingStore.recoverInterrupted(in: context) {
            _ in RecordingStore.SurvivingAudio(archiveMs: 60_000, workingCopyMs: 60_000)
        }

        XCTAssertFalse((recording.errorMessage ?? "").contains("which side"))
        XCTAssertTrue((recording.errorMessage ?? "").contains("The audio is here"))
    }

    func testAReadableArchiveKeepsTheOriginalPromise() throws {
        let recording = try quitWhileRecording()

        try RecordingStore.recoverInterrupted(in: context) {
            _ in RecordingStore.SurvivingAudio(archiveMs: 60_000, workingCopyMs: 60_000)
        }

        XCTAssertEqual(recording.errorMessage,
                       "Interrupted before this was transcribed. The audio is here — transcribe it again.")
    }

    func testACompleteTranscriptOnAnUnplayableRecordingIsCompletedWithAWarning() throws {
        let recording = try RecordingStore.create(kind: .meeting, in: context)
        recording.status = .diarizing
        recording.audioFileName = "2026/10/unclosed.m4a"
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        try context.save()

        try RecordingStore.recoverInterrupted(in: context) { _ in workingCopyOnly }

        XCTAssertEqual(recording.status, .completed)
        XCTAssertTrue(recording.warningMessage?.contains("will not play") ?? false,
                      "the transcript is fine, but the player would fail on this file")
    }

    func testEveryBranchKeepsEveryRowAndTouchesNoOtherRecording() throws {
        // Recovery is not destructive: whatever branch a row takes, the
        // transcript rows, speakers, bookmarks and notes it had are all still
        // there afterwards, and an unrelated finished recording is not touched.
        let finished = try recording(.completed)
        finished.errorMessage = nil
        for status in TranscriptionStatus.allCases where !status.isTerminal {
            let row = try self.recording(status, audio: "2026/10/\(status.rawValue).m4a")
            let transcript = StoredTranscript(modelId: "turbo", language: "tl")
            transcript.isComplete = status == .diarizing
            transcript.recording = row
            context.insert(transcript)
            let segment = StoredSegment(index: 0, startMs: 0, endMs: 1_000, text: "line")
            segment.transcript = transcript
            context.insert(segment)
            let speaker = StoredSpeaker(speakerId: "S1", displayName: "Maria")
            speaker.recording = row
            context.insert(speaker)
            let bookmark = StoredBookmark(atMs: 500)
            bookmark.recording = row
            context.insert(bookmark)
            let note = StoredMeetingItem(kind: .keyPoint, text: "note")
            note.recording = row
            context.insert(note)
        }
        try context.save()
        let before = [
            try context.fetchCount(FetchDescriptor<StoredRecording>()),
            try context.fetchCount(FetchDescriptor<StoredTranscript>()),
            try context.fetchCount(FetchDescriptor<StoredSegment>()),
            try context.fetchCount(FetchDescriptor<StoredSpeaker>()),
            try context.fetchCount(FetchDescriptor<StoredBookmark>()),
            try context.fetchCount(FetchDescriptor<StoredMeetingItem>()),
        ]

        try RecordingStore.recoverInterrupted(in: context) { _ in nothingLeft }

        let after = [
            try context.fetchCount(FetchDescriptor<StoredRecording>()),
            try context.fetchCount(FetchDescriptor<StoredTranscript>()),
            try context.fetchCount(FetchDescriptor<StoredSegment>()),
            try context.fetchCount(FetchDescriptor<StoredSpeaker>()),
            try context.fetchCount(FetchDescriptor<StoredBookmark>()),
            try context.fetchCount(FetchDescriptor<StoredMeetingItem>()),
        ]
        XCTAssertEqual(before, after)
        XCTAssertEqual(finished.status, .completed)
        XCTAssertNil(finished.errorMessage)
    }

    func testARecordingStoppedBeforeItsStatusWasWrittenIsCompletedNotFailed() throws {
        // Stop completed the live transcript and then the app died before the
        // status moved off `recording`. The transcript is whole.
        let recording = try quitWhileRecording()
        let transcript = StoredTranscript(modelId: "turbo", language: "tl")
        transcript.recording = recording
        context.insert(transcript)
        try context.save()

        try RecordingStore.recoverInterrupted(in: context)

        XCTAssertEqual(recording.status, .completed)
    }

    func testAJobThatNeverOpenedATranscriptOffersTheAudioItStillHas() throws {
        let queued = try recording(.pending, audio: "2026/10/q.m4a")
        let running = try recording(.transcribing, audio: "2026/10/r.m4a")

        try RecordingStore.recoverInterrupted(in: context) { _ in
            RecordingStore.SurvivingAudio(archiveMs: 1_000)
        }

        for row in [queued, running] {
            XCTAssertEqual(row.status, .failed)
            XCTAssertTrue(row.errorMessage?.contains("The audio is here") ?? false)
        }
    }
}
