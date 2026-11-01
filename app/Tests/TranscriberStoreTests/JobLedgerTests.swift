import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A job that could not save its transcript is not "Complete" (finding 16).
@MainActor
final class JobLedgerTests: XCTestCase {

    private struct DiskTrouble: LocalizedError {
        var errorDescription: String? { "the disk is full" }
    }

    func testACompletedJobIsFailedWhenItsTranscriptWasNotSaved() async {
        let ledger = JobLedger()
        let id = UUID()
        let saved = await ledger.attempt(.transcript, for: id) { () async throws -> Int in
            throw DiskTrouble()
        }

        XCTAssertNil(saved)
        let outcome = ledger.outcome(of: .completed, for: id)
        XCTAssertEqual(outcome.status, .failed,
                       "the stage that follows must not paper over a transcript that was lost")
        XCTAssertTrue(outcome.errorMessage?.contains("the disk is full") ?? false)
        XCTAssertTrue(outcome.errorMessage?.contains("Transcribe Again") ?? false)
    }

    func testACleanJobCompletesAsBefore() async {
        let ledger = JobLedger()
        let id = UUID()
        let saved = await ledger.attempt(.transcript, for: id) { 7 }

        XCTAssertEqual(saved, 7)
        XCTAssertEqual(ledger.outcome(of: .completed, for: id),
                       JobLedger.Outcome(status: .completed, errorMessage: nil, warning: nil))
    }

    func testALostSpeakerLabelWarnsAndDoesNotFailTheTranscript() {
        let ledger = JobLedger()
        let id = UUID()
        ledger.record(.speakers, DiskTrouble(), for: id)

        let outcome = ledger.outcome(of: .completed, for: id)
        XCTAssertEqual(outcome.status, .completed, "the transcript itself saved")
        XCTAssertTrue(outcome.warning?.contains("speaker labels") ?? false)
        XCTAssertTrue(outcome.warning?.contains("Identify Speakers Again") ?? false)
    }

    func testALostTurnSaysThatTheOldTextStays() {
        let ledger = JobLedger()
        let id = UUID()
        ledger.record(.turn, DiskTrouble(), for: id)

        let outcome = ledger.outcome(of: .completed, for: id)
        XCTAssertEqual(outcome.status, .completed)
        XCTAssertTrue(outcome.warning?.contains("old text of that turn is still there") ?? false)
    }

    func testLostPartialBatchesMatterOnlyWhenTheJobDoesNotFinish() {
        let ledger = JobLedger()
        let id = UUID()
        for _ in 0..<40 { ledger.record(.partialRows, DiskTrouble(), for: id) }

        // The finished transcript replaces the partial rows, so a batch that
        // was lost on the way changes nothing.
        XCTAssertNil(ledger.outcome(of: .completed, for: id).warning)

        let cancelled = ledger.outcome(of: .cancelled, for: id)
        XCTAssertEqual(cancelled.status, .cancelled)
        let warning = cancelled.warning ?? ""
        XCTAssertTrue(warning.contains("40 batches"), "counted, not listed forty times: \(warning)")
        XCTAssertEqual(warning.components(separatedBy: "could not be saved").count - 1, 1,
                       "one sentence for forty failures")
    }

    func testAFailedStageWriteIsMentionedOnlyOnceTheJobHasEnded() {
        let ledger = JobLedger()
        let id = UUID()
        ledger.record(.status, DiskTrouble(), for: id)

        XCTAssertNil(ledger.outcome(of: .transcribing, for: id).warning,
                     "a stage write fails often during a long job; the next one fixes it")
        XCTAssertTrue(ledger.outcome(of: .completed, for: id).warning?
            .contains("could not record all of this job's details") ?? false)
    }

    func testANewJobStartsWithACleanAccount() {
        let ledger = JobLedger()
        let id = UUID()
        ledger.record(.transcript, DiskTrouble(), for: id)
        XCTAssertTrue(ledger.failed(.transcript, for: id))

        ledger.clear(id)

        XCTAssertFalse(ledger.failed(.transcript, for: id))
        XCTAssertEqual(ledger.outcome(of: .completed, for: id).status, .completed)
    }

    func testOneRecordingsFailuresAreNotAnotherRecordings() {
        let ledger = JobLedger()
        let broken = UUID(), fine = UUID()
        ledger.record(.transcript, DiskTrouble(), for: broken)

        XCTAssertEqual(ledger.outcome(of: .completed, for: fine).status, .completed)
        XCTAssertEqual(ledger.outcome(of: .completed, for: broken).status, .failed)
    }
}

extension JobLedgerTests {
    func testAFailedJobKeepsTheReasonTheQueueGave() {
        // The queue says `.failed(message)` and then `.stage(.failed)`. The
        // status write for the stage carried no message, and wrote an empty one
        // over the reason that had just been saved.
        let ledger = JobLedger()
        let id = UUID()
        ledger.noteFailure("the audio file for this recording is missing", for: id)

        let outcome = ledger.outcome(of: .failed, for: id)
        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.errorMessage, "the audio file for this recording is missing")
        XCTAssertNil(ledger.outcome(of: .transcribing, for: id).errorMessage,
                     "an earlier stage must not carry an old reason")
    }
}

extension JobLedgerTests {
    func testAVoidWriteReportsWhetherItWorked() async {
        let ledger = JobLedger()
        let id = UUID()
        let ok = await ledger.succeeded(.status, for: id) {}
        XCTAssertTrue(ok)
        XCTAssertFalse(ledger.failed(.status, for: id))

        let bad = await ledger.succeeded(.status, for: id) { throw DiskTrouble() }
        XCTAssertFalse(bad)
        XCTAssertTrue(ledger.failed(.status, for: id))
    }
}
