import XCTest
@testable import TranscriberCore

/// Ported from the Python suite, including every regression found there.
/// The property that matters most is the negative one: committed text must
/// never change.
final class LocalAgreementTests: XCTestCase {

    /// "a b c" -> three tokens 300 ms apart starting at `start`.
    private func toks(_ spec: String, start: Int = 0, step: Int = 300) -> [Token] {
        spec.split(separator: " ").enumerated().map { index, word in
            let t0 = start + index * step
            let prefix = (index > 0 || start > 0) ? " " : ""
            return Token(text: prefix + word, startMs: t0, endMs: t0 + step)
        }
    }

    func testNothingCommitsOnTheFirstPass() {
        let la = LocalAgreement(agreement: 2)
        XCTAssertTrue(la.insert(toks("kumusta ka na")).isEmpty)
        XCTAssertEqual(la.committedText, "")
        XCTAssertEqual(la.partial, "kumusta ka na")
    }

    func testAgreeingPrefixCommits() {
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("kumusta ka na"))
        la.insert(toks("kumusta ka na kaibigan"))
        XCTAssertEqual(la.committedText, "kumusta ka na")
        XCTAssertEqual(la.partial, "kaibigan")
    }

    func testDisagreementBlocksTheCommit() {
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("kumusta ka na"))
        la.insert(toks("kumusta ba na"))
        XCTAssertEqual(la.committedText, "kumusta")
    }

    func testCasingAndPunctuationDoNotBlockCommits() {
        // Whisper varies these between passes on identical audio.
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("kumusta ka na"))
        la.insert(toks("Kumusta, ka na!"))
        let stripped = la.committedText.lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
        XCTAssertEqual(stripped, "kumusta ka na")
    }

    func testThreePassAgreementNeedsThree() {
        let la = LocalAgreement(agreement: 3)
        la.insert(toks("magandang umaga"))
        la.insert(toks("magandang umaga"))
        XCTAssertEqual(la.committedText, "")
        la.insert(toks("magandang umaga"))
        XCTAssertEqual(la.committedText, "magandang umaga")
    }

    func testCommittedTextIsNeverRewritten() {
        let la = LocalAgreement(agreement: 2)
        let passes = [
            "ang problema kasi",
            "ang problema kasi hindi",
            "ang problema kasi hindi pa",
            "ang PROBLEMA kasi hindi pa tapos",
            "ang problema kasi hindi pa tapos yung",
        ]
        var seen = ""
        for pass in passes {
            la.insert(toks(pass))
            XCTAssertTrue(la.committedText.hasPrefix(seen),
                          "committed text was rewritten: \(seen) -> \(la.committedText)")
            seen = la.committedText
        }
        XCTAssertEqual(seen, "ang problema kasi hindi pa tapos")
    }

    func testFlushCommitsTheTail() {
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("sige next topic"))
        XCTAssertEqual(la.committedText, "")
        la.flush()
        XCTAssertEqual(la.committedText, "sige next topic")
        XCTAssertEqual(la.partial, "")
    }

    func testAlreadyCommittedAudioIsNotRecommitted() {
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("una pangalawa"))
        la.insert(toks("una pangalawa"))
        XCTAssertEqual(la.committedText, "una pangalawa")
        la.insert(toks("una pangalawa panghuli"))
        la.insert(toks("una pangalawa panghuli"))
        XCTAssertEqual(la.committedText, "una pangalawa panghuli")
    }

    func testCommittedTimelineNeverGoesBackwards() {
        // Reproduces a segment starting at 45.4 s emitted after one ending at 45.9 s.
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("kailangan natin", start: 44_000))
        la.insert(toks("kailangan natin", start: 44_000))
        let end = la.committedEndMs

        // A start that bled 100 ms into the previous word: a real next word
        // with drifted timing, to be kept and clamped rather than dropped.
        let drifted = [Token(text: " priority", startMs: end - 100, endMs: end + 700)]
        la.insert(drifted)
        la.insert(drifted)

        XCTAssertTrue(la.committedText.hasSuffix("priority"), "got: \(la.committedText)")
        for (earlier, later) in zip(la.committed, la.committed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.startMs, earlier.endMs,
                                        "timeline went backwards")
        }
    }

    func testNothingIsTimestampedPastTheAudioReceived() {
        // Reproduces a segment that ended at 71 s in a 57 s recording.
        let la = LocalAgreement(agreement: 2)
        la.ceilingMs = 57_000
        let overlapping = (0..<40).map {
            Token(text: " w\($0)", startMs: 56_000 + $0 * 10, endMs: 56_500 + $0 * 10)
        }
        la.insert(overlapping)
        la.insert(overlapping)
        la.flush()
        XCTAssertFalse(la.committed.isEmpty)
        XCTAssertLessThanOrEqual(la.committed.map(\.endMs).max() ?? 0, 57_000)
    }

    func testForceCommitUnsticksAPermanentStall() {
        let la = LocalAgreement(agreement: 2)
        la.insert([Token(text: " kalo", startMs: 0, endMs: 900),
                   Token(text: " ka", startMs: 900, endMs: 1800)])
        la.insert([Token(text: " kumusta", startMs: 0, endMs: 900),
                   Token(text: " kayong", startMs: 900, endMs: 1800)])
        XCTAssertEqual(la.committedText, "")

        let forced = la.forceCommit(before: 900)
        XCTAssertFalse(forced.isEmpty)
        XCTAssertEqual(la.committedText, "kumusta")
        XCTAssertEqual(la.committedEndMs, 900)
    }

    func testForceCommitIsANoopWhenNothingIsOldEnough() {
        let la = LocalAgreement(agreement: 2)
        la.insert([Token(text: " mamaya", startMs: 5_000, endMs: 6_000)])
        XCTAssertTrue(la.forceCommit(before: 1_000).isEmpty)
        XCTAssertEqual(la.committedText, "")
    }

    func testForceCommitDoesNotDuplicateAlreadyCommittedWords() {
        // Reproduces duplicated phrases seen under load.
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("gusto ko lang"))
        la.insert(toks("gusto ko lang"))
        XCTAssertEqual(la.committedText, "gusto ko lang")

        la.insert(toks("gusto ko lang i confirm"))
        let forced = la.forceCommit(before: 1_500)
        XCTAssertFalse(forced.joinedText.contains("gusto"),
                       "re-committed already-committed words: \(forced.joinedText)")
    }
}

/// The commit boundary with a pre-roll in front of every window.
///
/// Whisper re-reads the last second and a half of committed audio on every
/// pass and may segment it however it likes. Timestamps drop the bulk of it;
/// these are the boundary cases where timing alone is not enough, and the
/// cases where a timing rule must *not* fire on a genuinely new word.
extension LocalAgreementTests {

    /// Commits `spec` outright: two agreeing passes.
    private func commit(_ la: LocalAgreement, _ spec: String, start: Int = 0, step: Int = 300) {
        la.insert(toks(spec, start: start, step: step))
        la.insert(toks(spec, start: start, step: step))
    }

    private func word(_ text: String, _ start: Int, _ end: Int, confidence: Double? = nil) -> Token {
        Token(text: " " + text, startMs: start, endMs: end, confidence: confidence)
    }

    func testPreRollReDecodeDoesNotDuplicateTheBoundaryWords() {
        // The case from the request: a commit lands mid-sentence and the next
        // window starts 1.5 s earlier, re-reading everything already committed
        // with slightly different timing.
        let la = LocalAgreement(agreement: 2)
        commit(la, "So yung quotation kailangan nating")
        XCTAssertEqual(la.committedText, "So yung quotation kailangan nating")
        XCTAssertEqual(la.committedEndMs, 1_500)

        let reread = [
            word("So", 10, 290), word("yung", 290, 610), word("quotation", 610, 880),
            word("kailangan", 880, 1_190), word("nating", 1_190, 1_560),
            word("i-send", 1_560, 1_900), word("tomorrow", 1_900, 2_300),
        ]
        la.insert(reread)
        // Second pass: same words, timings jittered the other way.
        la.insert([
            word("so", 0, 300), word("yung", 300, 600), word("quotation", 600, 900),
            word("kailangan", 900, 1_230), word("nating", 1_230, 1_520),
            word("i-send", 1_520, 1_880), word("tomorrow", 1_880, 2_310),
        ])

        XCTAssertEqual(la.committedText, "So yung quotation kailangan nating i-send tomorrow")
        XCTAssertEqual(la.partial, "")
    }

    func testTwoBoundaryWordsDriftedPastTheCommitAreBothDropped() {
        // Timestamps cannot tell the second one from new speech; text can.
        let la = LocalAgreement(agreement: 2)
        commit(la, "kailangan nating", start: 4_400)
        XCTAssertEqual(la.committedEndMs, 5_000)

        let drifted = [word("kailangan", 4_400, 5_010), word("nating", 5_010, 5_300),
                       word("i-send", 5_300, 5_600)]
        la.insert(drifted)
        la.insert(drifted)

        XCTAssertEqual(la.committedText, "kailangan nating i-send")
        XCTAssertEqual(la.duplicatesDropped, 4, "two rescues per pass")
    }

    func testAReSegmentedPreRollWordIsDroppedByTiming() {
        // The model merged the committed word with what follows. Whatever it
        // is called, it starts where the committed word started.
        let la = LocalAgreement(agreement: 2)
        commit(la, "kailangan nating", start: 4_400)

        let merged = [word("kailangang", 4_400, 5_100), word("i-send", 5_100, 5_400)]
        la.insert(merged)
        la.insert(merged)

        XCTAssertEqual(la.committedText, "kailangan nating i-send")
    }

    func testAShortNewWordWhoseStartBledEarlyIsKept() {
        // 150 ms function word, timestamped 100 ms before the previous word
        // ended. A plain midpoint test would drop it on every pass, so it
        // could never commit; anchoring on the previous word keeps it.
        let la = LocalAgreement(agreement: 2)
        commit(la, "sabi ko")
        XCTAssertEqual(la.committedEndMs, 600)

        let next = [word("na", 500, 650), word("pupunta", 650, 1_000)]
        la.insert(next)
        la.insert(next)

        XCTAssertEqual(la.committedText, "sabi ko na pupunta")
    }

    func testTheSameWordJustPastTheAnchorIsDroppedByText() {
        let la = LocalAgreement(agreement: 2)
        commit(la, "sabi ko")

        // Starts after the anchor (450) so timing keeps it; text catches it.
        let reread = [word("ko", 480, 700), word("na", 700, 900)]
        la.insert(reread)
        la.insert(reread)

        XCTAssertEqual(la.committedText, "sabi ko na")
    }

    func testAGenuineRepeatPastTheSlackIsKept() {
        // "hindi... hindi" -- the second one starts well after the boundary.
        let la = LocalAgreement(agreement: 2)
        commit(la, "hindi")
        XCTAssertEqual(la.committedEndMs, 300)

        let again = [word("hindi", 600, 900)]
        la.insert(again)
        la.insert(again)

        XCTAssertEqual(la.committedText, "hindi hindi")
    }

    func testFlushCanStopAtWhereSpeechEnded() {
        let la = LocalAgreement(agreement: 2)
        la.insert(toks("sige na po"))
        // The VAD heard speech end at 600 ms; "po" was read out of the silence.
        let flushed = la.flush(notAfter: 600)
        XCTAssertEqual(flushed.joinedText, "sige na")
        XCTAssertEqual(la.committedText, "sige na")
        XCTAssertEqual(la.partial, "")
    }

    func testConfidenceSurvivesTheCommit() {
        let la = LocalAgreement(agreement: 2)
        let sure = [word("sige", 0, 300, confidence: 0.8), word("na", 300, 500, confidence: 0.6)]
        la.insert(sure)
        la.insert(sure)
        XCTAssertEqual(la.committed.map(\.confidence), [0.8, 0.6])
    }
}
