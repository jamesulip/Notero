import XCTest
import TranscriberCore
@testable import TranscriberStore

final class StopFollowUpTests: XCTestCase {

    func testACaptureOnlyRecordingNeedsTheWholeFilePass() {
        XCTAssertEqual(StopFollowUp.after(decodedLive: false, laneCount: 1, diarizes: true), .wholeFile)
        XCTAssertEqual(StopFollowUp.after(decodedLive: false, laneCount: 1, diarizes: false), .wholeFile)
    }

    func testTwoLanesAlwaysNeedTheWholeFilePassEvenAfterALiveTranscript() {
        XCTAssertEqual(StopFollowUp.after(decodedLive: true, laneCount: 2, diarizes: false), .wholeFile)
    }

    func testALiveTranscriptNeedsOnlyTheSpeakersOrNothing() {
        XCTAssertEqual(StopFollowUp.after(decodedLive: true, laneCount: 1, diarizes: true), .speakersOnly)
        XCTAssertEqual(StopFollowUp.after(decodedLive: true, laneCount: 1, diarizes: false), .finished)
    }

    func testAQuitBeforeTheWholeFilePassLeavesARowThatSaysSo() throws {
        let closed = try XCTUnwrap(StopFollowUp.wholeFile.closedEarly)
        XCTAssertEqual(closed.status, .failed, "Needs Attention, with Transcribe Again at hand")
        XCTAssertTrue(closed.errorMessage?.contains("not been transcribed") ?? false)
        XCTAssertTrue(closed.status.isTerminal, "a row nothing will ever finish must not read as busy")
    }

    func testAQuitBeforeSpeakerIdentificationKeepsTheCompleteTranscript() throws {
        let closed = try XCTUnwrap(StopFollowUp.speakersOnly.closedEarly)
        XCTAssertEqual(closed.status, .completed)
        XCTAssertNil(closed.errorMessage)
        XCTAssertTrue(closed.warning?.contains("Identify Speakers Again") ?? false)
    }

    func testNothingIsLeftOverWhenNothingWasToRun() {
        XCTAssertNil(StopFollowUp.finished.closedEarly)
    }
}
