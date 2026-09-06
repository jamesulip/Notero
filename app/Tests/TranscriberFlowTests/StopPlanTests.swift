import XCTest
import TranscriberCore
import TranscriberEngine
@testable import TranscriberFlow

final class StopPlanTests: XCTestCase {

    private func result(durationMs: Int = 60_000, lanes: [CaptureLane] = [.room],
                        segments: [Segment] = [], stats: SessionStats = SessionStats(),
                        notices: [CaptureNotice] = []) -> LiveSessionResult {
        LiveSessionResult(recordingId: UUID(), segments: segments, durationMs: durationMs,
                          archiveFileName: "a.m4a", archiveSampleRate: 48_000,
                          cacheURL: URL(fileURLWithPath: "/tmp/c.wav"), waveform: [],
                          stats: stats, modelId: "m", language: "tl", lanes: lanes,
                          notices: notices)
    }

    private func plan(_ result: LiveSessionResult, decodedLive: Bool = true, hadPersister: Bool = true,
                      diarization: DiarizationMode = .accurate, keep: Bool = false) -> StopPlan {
        StopPlan.make(result: result, decodedLive: decodedLive, hadPersister: hadPersister,
                      diarizationMode: diarization, keepWorkingCopy: keep, shortTakeMs: 10_000)
    }

    func testCaptureOnlyGetsTheWholeFilePassAndNoLiveTranscript() {
        let plan = plan(result(), decodedLive: false, hadPersister: false)
        XCTAssertEqual(plan.transcript, .none)
        XCTAssertEqual(plan.followUp, .fullTranscription)
        XCTAssertNil(plan.liveFailureWarning)
    }

    func testLiveWithSpeakersCompletesThePersisterThenIdentifiesSpeakers() {
        let plan = plan(result(), diarization: .fast)
        XCTAssertEqual(plan.transcript, .completePersister)
        XCTAssertEqual(plan.followUp, .diarizeOnly(.fast))
    }

    func testLiveWithoutAPersisterStoresAFreshRevision() {
        XCTAssertEqual(plan(result(), hadPersister: false).transcript, .storeFresh)
    }

    func testLiveWithoutSpeakersIsDoneAndDropsTheWorkingCopyUnlessKept() {
        XCTAssertEqual(plan(result(), diarization: .off).followUp, .markCompleted(discardCache: true))
        XCTAssertEqual(plan(result(), diarization: .off, keep: true).followUp,
                       .markCompleted(discardCache: false))
    }

    func testTwoLanesAlwaysGetTheWholeFilePass() {
        let plan = plan(result(lanes: [.room, .remote]), diarization: .off)
        XCTAssertEqual(plan.transcript, .completePersister, "the live lines are kept meanwhile")
        XCTAssertEqual(plan.followUp, .fullTranscription)
    }

    func testFailedHopsBecomeAWarningWithTheDistinctionBetweenSomeAndAll() {
        var some = SessionStats()
        some.hops = 10
        some.failedHops = 2
        some.lastError = "boom"
        let partial = plan(result(stats: some))
        XCTAssertEqual(partial.liveFailureWarning,
                       "2 decode(s) failed during this recording, so some words may be missing. Last error: boom")

        var all = SessionStats()
        all.failedHops = 5
        let total = plan(result(stats: all))
        XCTAssertTrue(total.liveFailureWarning?.hasPrefix("Live transcription failed for this entire recording (5 decode errors).") == true)

        XCTAssertNil(plan(result(stats: all), decodedLive: false).liveFailureWarning,
                     "a capture-only session has no decodes to fail")
    }

    func testNoticesJoinInOrder() {
        let plan = plan(result(notices: [.microphoneChanged(now: "AirPods"), .microphoneLost("AirPods")]))
        let text = plan.noticesWarning ?? ""
        XCTAssertTrue(text.hasPrefix("The default input changed."))
        XCTAssertTrue(text.contains("no other microphone is connected"))
        XCTAssertNil(self.plan(result()).noticesWarning)
    }

    func testAShortTakeIsQuestionedWithItsWordCountOnlyWhenDecodedLive() {
        let segments = [Segment(index: 0, startMs: 0, endMs: 900, text: "sige na"),
                        Segment(index: 1, startMs: 1_000, endMs: 1_900, text: "ulit")]
        let live = plan(result(durationMs: 4_000, segments: segments))
        XCTAssertEqual(live.shortTake, .init(durationMs: 4_000, words: 3))

        let captureOnly = plan(result(durationMs: 4_000, segments: segments), decodedLive: false)
        XCTAssertEqual(captureOnly.shortTake, .init(durationMs: 4_000, words: nil))

        XCTAssertNil(plan(result(durationMs: 10_000)).shortTake, "at the threshold it is kept quietly")
    }
}
