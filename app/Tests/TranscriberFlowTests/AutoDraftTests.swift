import XCTest
import TranscriberCore
@testable import TranscriberFlow

final class AutoDraftTests: XCTestCase {

    /// Every argument in the state where a draft should start. Each test
    /// below changes one of them.
    private func decide(
        enabled: Bool = true, hasModel: Bool = true, status: TranscriptionStatus = .completed,
        hasTranscript: Bool = true, isRecording: Bool = false, hasDraft: Bool = false
    ) -> AutoDraft.Decision {
        AutoDraft.decide(enabled: enabled, hasModel: hasModel, status: status,
                         hasTranscript: hasTranscript, isRecording: isRecording, hasDraft: hasDraft)
    }

    func testACompletedTranscriptionDrafts() {
        XCTAssertEqual(decide(), .draft)
        XCTAssertTrue(decide().isDraft)
    }

    func testTheSettingIsTheFirstGate() {
        XCTAssertEqual(decide(enabled: false), .skip(.turnedOff))
        // Off wins over every other reason, so a user who never turned this
        // on is never told the app skipped because of a recording.
        XCTAssertEqual(decide(enabled: false, hasModel: false, status: .failed,
                              hasTranscript: false, isRecording: true, hasDraft: true),
                       .skip(.turnedOff))
    }

    func testNoModelSkips() {
        XCTAssertEqual(decide(hasModel: false), .skip(.noModel))
    }

    /// The status the job left behind decides, not the fact that it ended.
    func testOnlyACompletedRecordingDrafts() {
        XCTAssertEqual(decide(status: .failed), .skip(.notComplete))
        XCTAssertEqual(decide(status: .cancelled), .skip(.notComplete))
        XCTAssertEqual(decide(status: .transcribing), .skip(.notComplete))
        XCTAssertEqual(decide(status: .recording), .skip(.notComplete))
    }

    func testASilentRecordingHasNothingToRead() {
        XCTAssertEqual(decide(hasTranscript: false), .skip(.noTranscript))
    }

    /// The rule this exists for: a two-minute draft must not take the GPU
    /// from a live decoder, whose dropped hops are missing words.
    func testARunningRecordingStopsTheDraft() {
        XCTAssertEqual(decide(isRecording: true), .skip(.recording))
    }

    func testADraftThatIsAlreadyThereIsNotRepeated() {
        XCTAssertEqual(decide(hasDraft: true), .skip(.busy))
    }
}
