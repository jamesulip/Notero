import XCTest
@testable import TranscriberCore

/// The live path's defaults are measured results (FINDINGS 5, 6, 11, 27), not
/// suggestions. A change to one of them should be a decision with a number
/// behind it, so it fails here first.
final class SessionConfigDefaultsTests: XCTestCase {

    func testTheShippedDefaultsAreTheMeasuredOnes() {
        let config = SessionConfig()
        XCTAssertEqual(config.hopMs, 1_500)
        XCTAssertEqual(config.contextMs, 15_000)
        XCTAssertEqual(config.silenceBoundaryMs, 700)
        XCTAssertEqual(config.preRollMs, 1_500)
        XCTAssertEqual(config.agreement, 2)
        XCTAssertFalse(config.adaptiveHop)
        XCTAssertEqual(config.headTolerance, 3)
        XCTAssertEqual(config.headMinRun, 3)
    }

    func testHeadToleranceZeroIsStrictAgreementAndNeverCommitsAnUnagreedHead() {
        let la = LocalAgreement(agreement: 2, headTolerance: 0, headMinRun: 3)
        la.insert([Token(text: "dens", startMs: 0, endMs: 300), Token(text: " ok", startMs: 300, endMs: 600),
                   Token(text: " kai", startMs: 600, endMs: 900), Token(text: " muhang", startMs: 900, endMs: 1_200)])
        la.insert([Token(text: "s", startMs: 0, endMs: 300), Token(text: " ok", startMs: 300, endMs: 600),
                   Token(text: " kai", startMs: 600, endMs: 900), Token(text: " muhang", startMs: 900, endMs: 1_200)])
        XCTAssertEqual(la.committedText, "")
        XCTAssertEqual(la.headSkips, 0)
    }
}
