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
        let failed = try recording(.failed)
        failed.errorMessage = "the original reason"

        XCTAssertEqual(try RecordingStore.recoverInterrupted(in: context), 0)

        XCTAssertEqual(done.status, .completed)
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
