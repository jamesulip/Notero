import XCTest
@testable import TranscriberCore

final class TextNormalizerTests: XCTestCase {

    private func words(_ text: String, _ policy: ScoringPolicy = .standard) -> [String] {
        TextNormalizer.words(text, policy: policy)
    }

    /// Scalars, not `String` ==: Swift's == forgives NFC against NFD, and
    /// parity means the same code points `score.py` prints.
    private func scalars(_ tokens: [String]) -> [[UInt32]] {
        tokens.map { $0.unicodeScalars.map(\.value) }
    }

    // MARK: - Parity with eval/score.py

    /// Expected values produced by running `eval/score.py`'s `normalize` with
    /// python3 3.x, `python3 -I` with eval/ on sys.path, on each input below
    /// and printing the result as Swift literals (non-ASCII as \u{...}). Do not
    /// edit them by hand: regenerate them from score.py.
    static let scorePyNormalize: [(String, [String])] = [
        ("Kumusta kayong lahat?", ["kumusta", "kayong", "lahat"]),
        ("Sige, i-send mo na yung report bukas.", ["sige", "i", "send", "mo", "na", "yung", "report", "bukas"]),
        ("Nag-review ako ng code kahapon, okay na.", ["nag", "review", "ako", "ng", "code", "kahapon", "okay", "na"]),
        ("I don't think it's ready \u{2014} let's wait.", ["i", "don't", "think", "it's", "ready", "let's", "wait"]),
        ("Ako\u{2019}y pupunta sa \u{2018}mall\u{2019} mamaya.", ["ako'y", "pupunta", "sa", "mall", "mamaya"]),
        ("'Di ko alam, 'yung file ba?", ["di", "ko", "alam", "yung", "file", "ba"]),
        ("Ang galing!!! 100% sure ako.", ["ang", "galing", "100", "sure", "ako"]),
        ("Caf\u{E9}, ni\u{F1}o, at se\u{F1}ora.", ["caf\u{E9}", "ni\u{F1}o", "at", "se\u{F1}ora"]),
        ("Cafe\u{301} ni\u{F1}o", ["caf\u{E9}", "ni\u{F1}o"]),
        ("\u{FF21}\u{FF22}\u{FF23} \u{FF46}\u{FF49}\u{FF4C}\u{FF45}", ["abc", "file"]),
        ("\u{FB01}nal na \u{2019}to", ["final", "na", "to"]),
        ("Meeting @ 3:30pm (sharp) #standup", ["meeting", "3", "30pm", "sharp", "standup"]),
        ("email: juan@example.com / www.notero.ph", ["email", "juan", "example", "com", "www", "notero", "ph"]),
        ("Okay \u{1F44D} salamat \u{1F64F}\u{1F3FD} po", ["okay", "salamat", "po"]),
        ("zero\u{200B}width space at zero\u{200D}joiner", ["zero", "width", "space", "at", "zero", "joiner"]),
        ("ISANG LIBO'T ISA", ["isang", "libo't", "isa"]),
        ("rock 'n' roll", ["rock", "n", "roll"]),
        ("o'clock' at 'quoted'", ["o'clock", "at", "quoted"]),
        ("nasa ika-3 floor tayo", ["nasa", "ika", "3", "floor", "tayo"]),
        ("  multiple   spaces\tand\nnewlines  ", ["multiple", "spaces", "and", "newlines"]),
        ("", []),
        ("...!?", []),
        ("PAGKAKAISA ng Pilipinas, 2026", ["pagkakaisa", "ng", "pilipinas", "2026"]),
        ("x\u{B2} and \u{BD} cup", ["x2", "and", "1", "2", "cup"]),
        ("\u{D1} \u{DC} \u{D6} \u{C0}\u{C9}\u{CE}", ["\u{F1}", "\u{FC}", "\u{F6}", "\u{E0}\u{E9}\u{EE}"]),
        ("tab\tseparated\u{A0}nbsp", ["tab", "separated", "nbsp"]),
    ]

    func testStandardMatchesScorePyNormalize() {
        for (input, expected) in Self.scorePyNormalize {
            XCTAssertEqual(scalars(words(input)), scalars(expected), "input: \(input.debugDescription)")
        }
    }

    /// The documented divergences from score.py, with what score.py gives
    /// (produced the same way as above) next to what the policy gives.
    func testDocumentedDivergencesFromScorePy() {
        // score.py: ["foo_bar", "baz"] -- Python's \w includes the underscore.
        XCTAssertEqual(words("foo_bar baz"), ["foo", "bar", "baz"])
        // score.py: ["mga", "ng", "a", "bata"] -- Python's \w has no combining marks.
        XCTAssertEqual(scalars(words("mga ng\u{303}a bata")), scalars(["mga", "ng\u{303}a", "bata"]))
        // score.py: ["don", "t"] -- score.py does not map the backtick.
        XCTAssertEqual(words("don`t"), ["don't"])
        // score.py: ["ako\u{2BC}y"] -- step 2 maps U+02BC to an apostrophe.
        XCTAssertEqual(words("ako\u{2BC}y"), ["ako'y"])
        // score.py: ["don", "t"] -- NFKC turns U+00B4 into a space and a
        // combining acute, so step 2 never sees it; the orphan mark is dropped.
        XCTAssertEqual(words("don\u{B4}t"), ["don", "t"])
    }

    // MARK: - Presets

    func testKeepHyphensKeepsIntraWordHyphens() {
        XCTAssertEqual(words("Sige, i-send mo na.", .keepHyphens), ["sige", "i-send", "mo", "na"])
        XCTAssertEqual(words("Nag-review ako.", .keepHyphens), ["nag-review", "ako"])
        XCTAssertEqual(words("-edge- and ika--3", .keepHyphens), ["edge", "and", "ika", "3"])
        XCTAssertEqual(words("nag\u{2011}review", .keepHyphens), ["nag-review"], "a non-breaking hyphen scores as -")
        XCTAssertEqual(words("nag\u{2013}review", .keepHyphens), ["nag", "review"], "an en dash is punctuation")
        XCTAssertEqual(words("Nag-review ako."), ["nag", "review", "ako"])
    }

    static let legacyInputs = [
        "Kumusta kayong lahat?", "Sige, i-send mo na yung report bukas.",
        "I don't think it's ready \u{2014} let's wait.", "Ako\u{2019}y pupunta sa \u{2018}mall\u{2019}.",
        "Café, niño, at señora.", "Cafe\u{301} ni\u{F1}o", "Meeting @ 3:30pm (sharp) #standup",
        "Okay \u{1F44D} salamat po", "ISANG LIBO'T ISA", "x\u{B2} and \u{BD} cup", "", "...!?",
        "  multiple   spaces\tand\nnewlines  ", "Ñ Ü Ö ÀÉÎ", "foo_bar baz",
    ]

    func testLegacyCLIMatchesWordErrorRateWords() {
        for input in Self.legacyInputs {
            XCTAssertEqual(words(input, .legacyCLI), WordErrorRate.words(input), "input: \(input.debugDescription)")
        }
    }

    func testLegacyCLIRateMatchesWordErrorRateScore() {
        let pairs = [
            ("Sige, i-send mo na yung report.", "sige send mo na po yung report"),
            ("Café niño at señora", "cafe nino at senyora"),
            ("I don't know", "i dont know"),
            ("isa dalawa tatlo", ""),
            ("Okay na 'to.", "okay na to talaga"),
        ]
        for (ref, hyp) in pairs {
            let r = words(ref, .legacyCLI), h = words(hyp, .legacyCLI)
            let counts = Alignment.counts(reference: r, hypothesis: h)
            XCTAssertGreaterThan(counts.referenceLength, 0)
            XCTAssertEqual(Double(counts.errors) / Double(counts.referenceLength),
                           WordErrorRate.score(reference: ref, hypothesis: hyp), accuracy: 1e-12, ref)
        }
    }

    // MARK: - Unicode

    func testNFCAndNFDGiveTheSameTokens() {
        for policy in [ScoringPolicy.standard, ScoringPolicy(id: "nfc", unicodeForm: .nfc),
                       ScoringPolicy(id: "none", unicodeForm: .none)] {
            XCTAssertEqual(words("caf\u{E9} ni\u{F1}o", policy), words("cafe\u{301} nin\u{303}o", policy))
            XCTAssertEqual(words("cafe\u{301}", policy).count, 1)
        }
    }

    func testCompatibilityCharactersFoldOnlyUnderNFKC() {
        XCTAssertEqual(words("\u{FF21}\u{FF22}\u{FF23} \u{FB01}le"), ["abc", "file"])
        let nfc = ScoringPolicy(id: "nfc", unicodeForm: .nfc)
        XCTAssertNotEqual(words("\u{FF21}\u{FF22}\u{FF23}", nfc), ["abc"])
        XCTAssertNotEqual(words("\u{FB01}le", nfc), ["file"])
    }

    func testCurlyAndStraightApostrophesAgree() {
        for apostrophe in ["'", "\u{2019}", "\u{2018}", "\u{2BC}", "`"] {
            XCTAssertEqual(words("don\(apostrophe)t ako\(apostrophe)y"), ["don't", "ako'y"], apostrophe)
        }
    }

    func testEmojiAndSymbolsAreRemoved() {
        XCTAssertEqual(words("ok \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} na \u{2764}\u{FE0F} ₱500 © ™"),
                       ["ok", "na", "500", "tm"])
    }

    func testZeroWidthCharactersSeparate() {
        XCTAssertEqual(words("a\u{200B}b c\u{200D}d e\u{FEFF}f"), ["a", "b", "c", "d", "e", "f"])
    }

    func testTagalogTildeStaysOneToken() {
        let tokens = words("Mañana ang mg\u{303}a NG\u{303}AYON")
        XCTAssertEqual(tokens.count, 4)
        XCTAssertEqual(scalars([tokens[2]]), scalars(["mg\u{303}a"]))
        XCTAssertEqual(scalars([tokens[3]]), scalars(["ng\u{303}ayon"]))
    }

    func testDottedCapitalIDoesNotTrap() {
        XCTAssertEqual(words("İstanbul İ"), ["i\u{307}stanbul", "i\u{307}"])
        XCTAssertEqual(words("İstanbul", .legacyCLI), ["istanbul"])
    }

    func testStripDiacritics() {
        let policy = ScoringPolicy(id: "strip", stripDiacritics: true)
        XCTAssertEqual(words("Niño señora mg\u{303}a", policy), ["nino", "senora", "mga"])
    }

    // MARK: - Policies

    func testApostrophePolicies() {
        XCTAssertEqual(words("don't 'yung' x'", .standard), ["don't", "yung", "x"])
        XCTAssertEqual(words("don't 'yung'", ScoringPolicy(id: "s", apostrophes: .split)), ["don", "t", "yung"])
        XCTAssertEqual(words("don't 'yung'", ScoringPolicy(id: "d", apostrophes: .delete)), ["dont", "yung"])
    }

    func testKeepPunctuationMakesEachMarkAToken() {
        let policy = ScoringPolicy(id: "p", punctuation: .keep)
        XCTAssertEqual(words("Oo, sige! 'di ba?", policy), ["oo", ",", "sige", "!", "'", "di", "ba", "?"])
        XCTAssertEqual(words("a\u{200B}b  c", policy), ["a", "b", "c"], "invisible characters are never tokens")
    }

    func testNoCaseFolding() {
        XCTAssertEqual(words("Sige Na", ScoringPolicy(id: "c", caseFolding: false)), ["Sige", "Na"])
    }

    func testCharactersAreWordsJoinedBySpaces() {
        XCTAssertEqual(TextNormalizer.characters("  Ni\u{F1}o,  na!", policy: .standard),
                       Array("niño na"))
        XCTAssertEqual(TextNormalizer.characters("nin\u{303}o", policy: .standard).count, 4)
        XCTAssertEqual(TextNormalizer.characters("", policy: .standard), [])
    }

    // MARK: - Contractions

    func testContractionTableVersions() {
        XCTAssertEqual(ContractionTable.currentVersion, 1)
        XCTAssertEqual(ContractionTable.table(version: 1)?["won't"], "will not")
        XCTAssertNil(ContractionTable.table(version: 2))
    }

    func testExpandContractions() {
        let p = ScoringPolicy.expandContractions
        XCTAssertEqual(words("I don't think it's ready, we're late.", p),
                       ["i", "do", "not", "think", "it", "is", "ready", "we", "are", "late"])
        XCTAssertEqual(words("Won't, can't (I'm) they've", p),
                       ["will", "not", "can", "not", "i", "am", "they", "have"])
        XCTAssertEqual(words("'Di ko alam, \u{2018}yung file. 'Wag na 'to", p),
                       ["hindi", "ko", "alam", "iyong", "file", "huwag", "na", "to"])
        // The forms ASR writes expand the same way as the apostrophe forms, so
        // expansion never turns a correct word into an error.
        XCTAssertEqual(words("Medyo mahaba 'yung function, 'di ko alam.", p),
                       words("medyo mahaba yung function di ko alam", p))
        XCTAssertEqual(words("I said 'to be or not'", p), ["i", "said", "to", "be", "or", "not"],
                       "a quoted English 'to' is not the Tagalog 'ito'")
        XCTAssertEqual(words("Ako\u{2019}y pupunta; siya'y, ito'y tayo'y", p),
                       ["ako", "ay", "pupunta", "siya", "ay", "ito", "ay", "tayo", "ay"])
        XCTAssertEqual(words("ako'y", p), words("ako ay", p))
        XCTAssertEqual(words("John's 'y I'd", p), ["john's", "y", "i'd"], "possessives and 'd are left alone")
        XCTAssertEqual(words("Don't", ScoringPolicy(id: "nc", caseFolding: false, contractions: .expand)),
                       ["do", "not"], "an expansion is written in lower case")
        XCTAssertEqual(words("don't", ScoringPolicy(id: "v9", contractions: .expand, contractionTableVersion: 9)),
                       ["don't"], "an unknown table version expands nothing")
        XCTAssertEqual(words("ako'y don't"), ["ako'y", "don't"], "standard keeps contractions")
    }
}
