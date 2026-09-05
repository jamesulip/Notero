import XCTest
@testable import TranscriberCore

final class PromptingTests: XCTestCase {

    func testNothingToSayIsNil() {
        XCTAssertNil(TranscriptionPrompt.compose(language: "tl", usePrimer: false, vocabulary: nil))
        XCTAssertNil(TranscriptionPrompt.compose(language: "tl", usePrimer: false, vocabulary: "  \n"))
        XCTAssertNil(TranscriptionPrompt.compose(language: "en", usePrimer: true, vocabulary: nil),
                     "English has no primer")
    }

    func testVocabularyAloneIsTrimmed() {
        XCTAssertEqual(TranscriptionPrompt.compose(language: "tl", usePrimer: false,
                                                   vocabulary: " Maria, Jose "),
                       "Maria, Jose")
    }

    func testPrimerComesFirst() throws {
        let primer = try XCTUnwrap(TranscriptionPrompt.primer(for: "tl"))
        let composed = try XCTUnwrap(TranscriptionPrompt.compose(language: "tl", usePrimer: true,
                                                                 vocabulary: "Maria"))
        XCTAssertTrue(composed.hasPrefix(primer))
        XCTAssertTrue(composed.hasSuffix(" Maria"))
    }

    /// The primer must not contain the content words of the synthetic fixture,
    /// or a measurement against that fixture would flatter it.
    func testPrimerDoesNotLeakTheFixture() throws {
        let primer = try XCTUnwrap(TranscriptionPrompt.primer(for: "tl")).lowercased()
        for word in ["attendance", "agenda", "timeline", "budget", "deployment", "staging",
                     "release", "quarter", "testing"] {
            XCTAssertFalse(primer.contains(word), "primer contains fixture word \(word)")
        }
    }
}
