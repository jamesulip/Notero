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

        let drifted = [Token(text: " priority", startMs: end - 500, endMs: end + 700)]
        la.insert(drifted)
        la.insert(drifted)

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
