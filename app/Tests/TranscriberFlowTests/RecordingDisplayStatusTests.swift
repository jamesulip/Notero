import XCTest
import TranscriberCore
@testable import TranscriberFlow

final class RecordingDisplayStatusTests: XCTestCase {

    private func make(status: TranscriptionStatus = .completed, progress: JobProgress? = nil,
                      isLive: Bool = false, isPaused: Bool = false, warning: String? = nil,
                      hasAudio: Bool = true, error: String? = nil) -> RecordingDisplayStatus {
        RecordingDisplayStatus.make(status: status, progress: progress, isLive: isLive,
                                    isPaused: isPaused, warning: warning, hasAudio: hasAudio,
                                    errorMessage: error)
    }

    func testAJobInProgressShowsItsChipAndACancelButton() {
        let display = make(status: .transcribing,
                           progress: JobProgress(status: .transcribing, fraction: 0.4, remaining: 90))
        XCTAssertEqual(display.chip, .init(status: .transcribing, fraction: 0.4, remaining: 90))
        XCTAssertEqual(display.action, .cancel)
        XCTAssertTrue(display.isBusy)
        XCTAssertEqual(display.emptyState.title, "Work in progress")
        XCTAssertEqual(display.emptyState.detail,
                       "Transcription · \(TimeFormat.remaining(seconds: 90)) left")
    }

    func testTheLiveSessionIsBusyWithNoActionAndPausedHasNoChip() {
        let recording = make(status: .recording, isLive: true)
        XCTAssertEqual(recording.chip?.status, .recording)
        XCTAssertNil(recording.action)
        XCTAssertTrue(recording.isBusy)
        XCTAssertFalse(recording.isPaused)

        let paused = make(status: .recording, isLive: true, isPaused: true)
        XCTAssertNil(paused.chip, "the row shows Paused in the chip's place")
        XCTAssertTrue(paused.isPaused)
        XCTAssertTrue(paused.isBusy)
    }

    func testFailedOffersRetryOnlyWhenThereIsAudio() {
        let withAudio = make(status: .failed, hasAudio: true, error: "The model refused a window.")
        XCTAssertEqual(withAudio.action, .retry)
        XCTAssertEqual(withAudio.emptyState.title, "Transcription failed")
        XCTAssertEqual(withAudio.emptyState.detail, "The model refused a window.")

        let noAudio = make(status: .failed, hasAudio: false)
        XCTAssertNil(noAudio.action)
        XCTAssertEqual(noAudio.emptyState.title, "The recording stopped early")
        XCTAssertTrue(noAudio.emptyState.detail.contains("captured no audio"))
    }

    func testCancelledOffersTranscribe() {
        let display = make(status: .cancelled)
        XCTAssertEqual(display.chip?.status, .cancelled)
        XCTAssertEqual(display.action, .transcribe)
        XCTAssertEqual(display.emptyState.symbol, "xmark.circle")
    }

    func testCompleteIsQuietWithTranscribeAgain() {
        let display = make(status: .completed)
        XCTAssertNil(display.chip)
        XCTAssertEqual(display.action, .transcribeAgain)
        XCTAssertFalse(display.isBusy)
        XCTAssertNil(display.warning)
        XCTAssertEqual(display.emptyState.title, "No transcript yet")
    }

    func testTheWarningComesThroughFromOneSourceAndBlankIsNone() {
        XCTAssertEqual(make(warning: "A window was dropped.").warning, "A window was dropped.")
        XCTAssertNil(make(warning: "").warning)
        // A warning does not change the action: the recording is complete.
        XCTAssertEqual(make(warning: "x").action, .transcribeAgain)
    }

    func testAPendingRowWithNoJobStillShowsItsStoredChip() {
        // An import that has not reached the queue yet, or a row a relaunch
        // found pending: the stored status is shown until the queue reports.
        let display = make(status: .pending)
        XCTAssertEqual(display.chip?.status, .pending)
        XCTAssertFalse(display.isBusy)
    }
}
