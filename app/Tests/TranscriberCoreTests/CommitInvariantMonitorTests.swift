import XCTest
@testable import TranscriberCore

/// The monitor is the check that runs over every live replay of the latency
/// experiment, so it has to say "broken" for each way a transcript can break,
/// and nothing for a transcript that is fine.
final class CommitInvariantMonitorTests: XCTestCase {

    private func token(_ text: String, _ start: Int, _ end: Int) -> Token {
        Token(text: " " + text, startMs: start, endMs: end)
    }

    func testAnAppendOnlyStreamHoldsTheInvariant() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 300), token("ganda", 300, 700)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)
        let b = [token("ng", 700, 900)]
        monitor.observe(batch: b, decoderCommitted: a + b, audioMs: 2_000)
        monitor.finish(decoderCommitted: a + b, audioMs: 2_000)

        XCTAssertTrue(monitor.report.holds, "\(monitor.report.violations)")
        XCTAssertEqual(monitor.report.words, 3)
        XCTAssertEqual(monitor.report.batches, 2)
    }

    func testWordsThatTouchAreNotAnOverlap() {
        var monitor = CommitInvariantMonitor()
        let all = [token("a", 0, 300), token("b", 300, 600)]
        monitor.observe(batch: all, decoderCommitted: all, audioMs: 600)
        XCTAssertTrue(monitor.report.holds)
    }

    func testARewrittenWordIsCaught() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 300), token("ganda", 300, 700)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)
        // The decoder quietly changed the first word while appending a new one.
        let b = [token("ng", 700, 900)]
        monitor.observe(batch: b, decoderCommitted: [token("an", 0, 300), a[1]] + b, audioMs: 2_000)

        XCTAssertEqual(monitor.report.violations.map(\.kind), ["rewritten"])
    }

    func testADroppedWordIsCaughtWhetherOrNotTheCountFalls() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 300), token("ganda", 300, 700)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)
        // The first word vanished while a new one was appended: same count, different text.
        let b = [token("ng", 700, 900)]
        monitor.observe(batch: b, decoderCommitted: [a[1]] + b, audioMs: 2_000)
        XCTAssertEqual(monitor.report.violations.map(\.kind), ["rewritten"])

        // And the list shrank outright.
        var shrunk = CommitInvariantMonitor()
        shrunk.observe(batch: a, decoderCommitted: a, audioMs: 1_000)
        shrunk.observe(batch: b, decoderCommitted: b, audioMs: 2_000)
        XCTAssertEqual(shrunk.report.violations.map(\.kind), ["shrank"])
    }

    func testABatchTheDecoderNeverAppendedIsCaught() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 300)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 500)
        // Delivered twice: the consumer would show the word two times.
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)

        XCTAssertTrue(monitor.report.violations.contains { $0.kind == "shrank" || $0.kind == "batchMismatch" },
                      "\(monitor.report.violations)")
        XCTAssertFalse(monitor.report.holds)
    }

    func testAWordThatStartsBeforeThePreviousOneEndedIsCaught() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 400)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 500)
        let b = [token("ganda", 300, 700)]
        monitor.observe(batch: b, decoderCommitted: a + b, audioMs: 1_000)

        XCTAssertEqual(monitor.report.violations.map(\.kind), ["overlap"])
    }

    func testAWordTimestampedPastTheAudioIsCaught() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 1_200)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)

        XCTAssertEqual(monitor.report.violations.map(\.kind), ["pastAudio"])
    }

    func testAWordThatEndsBeforeItStartsIsCaughtAndAnEmptyWordIsOnlyCounted() {
        var monitor = CommitInvariantMonitor()
        let a = [Token(text: "  ", startMs: 100, endMs: 50)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 1_000)

        XCTAssertEqual(monitor.report.violations.map(\.kind), ["backwards"])
        XCTAssertEqual(monitor.report.emptyWords, 1)

        // An empty word that breaks nothing leaves the invariant standing.
        var fine = CommitInvariantMonitor()
        let b = [token("ang", 0, 300), Token(text: " ", startMs: 300, endMs: 320)]
        fine.observe(batch: b, decoderCommitted: b, audioMs: 1_000)
        XCTAssertTrue(fine.report.holds)
        XCTAssertEqual(fine.report.emptyWords, 1)
    }

    func testTheFinalListMustBeWhatWasDelivered() {
        var monitor = CommitInvariantMonitor()
        let a = [token("ang", 0, 300)]
        monitor.observe(batch: a, decoderCommitted: a, audioMs: 500)
        monitor.finish(decoderCommitted: a + [token("ganda", 300, 600)], audioMs: 1_000)

        XCTAssertEqual(monitor.report.violations.map(\.kind), ["finalMismatch"])
    }

    func testARepeatedBreakageIsCappedSoAReportStaysSmall() {
        var monitor = CommitInvariantMonitor()
        var all: [Token] = []
        for index in 0..<40 {
            // Every word overlaps the one before it.
            let word = token("w\(index)", index * 100, index * 100 + 300)
            monitor.observe(batch: [word], decoderCommitted: all + [word], audioMs: 100_000)
            all.append(word)
        }
        XCTAssertLessThanOrEqual(monitor.report.violations.count, 5)
        XCTAssertFalse(monitor.report.holds)
    }

    func testLocalAgreementOnlyEverProducesStreamsThatHoldTheInvariant() {
        // The policy in isolation, strict and head-tolerant, on hypotheses that disagree at
        // the head on every pass: whatever it commits, the monitor must accept.
        for tolerance in [0, 1, 3] {
            let la = LocalAgreement(agreement: 2, headTolerance: tolerance, headMinRun: 3)
            la.ceilingMs = 100_000
            var monitor = CommitInvariantMonitor()
            var clock = 0
            for pass in 0..<30 {
                let hypothesis = (0..<8).map { i in
                    token(i == 0 ? "h\(pass)" : "w\(pass / 2 * 8 + i)", clock + i * 300, clock + i * 300 + 280)
                }
                let newly = la.insert(hypothesis)
                if !newly.isEmpty {
                    monitor.observe(batch: newly, decoderCommitted: la.committed, audioMs: 100_000)
                }
                clock += 300
            }
            let tail = la.flush()
            if !tail.isEmpty { monitor.observe(batch: tail, decoderCommitted: la.committed, audioMs: 100_000) }
            monitor.finish(decoderCommitted: la.committed, audioMs: 100_000)
            XCTAssertTrue(monitor.report.holds, "tolerance \(tolerance): \(monitor.report.violations)")
        }
    }
}
