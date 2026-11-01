import Foundation

// Turning text into the units that are scored.
//
// A WER is only comparable to another WER made with the same tokenizer, so
// every rule here is a setting of a versioned `ScoringPolicy` and none is
// implicit. `ScoringPolicy.standard` reproduces `eval/score.py`'s `normalize`,
// the scorer behind the documented baseline tables, and the parity tests hold
// it to that on real Taglish strings.

/// The built-in contraction tables, by version.
///
/// A table only ever grows a new version; an existing version is never edited,
/// because a score made with "table 1" has to mean the same thing next year.
///
/// Besides the table, version 1 has one rule: a word ending in the Tagalog
/// enclitic `'y` ("ako'y", "siya'y", "ito'y") becomes the stem followed by
/// "ay". It is a rule and not a list because any noun or pronoun can take it.
///
/// Possessive `'s` and the ambiguous `'d` ("I'd" = would or had) are left out
/// on purpose: expanding them would guess.
public enum ContractionTable {
    public static let currentVersion = 1

    /// The table of `version`, lower-case keys to lower-case expansions, or nil
    /// for a version this build does not know. With nil the normalizer leaves
    /// the text unexpanded (and skips the `'y` rule). `EvaluationConfig.validate`
    /// does not reject an unknown version: the policy fingerprint already
    /// records it, so a report made with it cannot pass for a version-1 score.
    public static func table(version: Int) -> [String: String]? {
        version == 1 ? version1 : nil
    }

    static func hasEncliticRule(version: Int) -> Bool { version == 1 }

    private static let version1: [String: String] = [
        // English negations.
        "don't": "do not", "doesn't": "does not", "didn't": "did not",
        "isn't": "is not", "aren't": "are not", "wasn't": "was not", "weren't": "were not",
        "haven't": "have not", "hasn't": "has not", "hadn't": "had not",
        "won't": "will not", "can't": "can not", "couldn't": "could not",
        "wouldn't": "would not", "shouldn't": "should not",
        // English pronoun + verb.
        "i'm": "i am",
        "you're": "you are", "we're": "we are", "they're": "they are",
        "it's": "it is", "that's": "that is", "what's": "what is", "there's": "there is",
        "i'll": "i will", "you'll": "you will", "we'll": "we will", "they'll": "they will",
        "i've": "i have", "you've": "you have", "we've": "we have", "they've": "they have",
        // Tagalog clipped forms, with and without the apostrophe: Whisper
        // and most people write "yung" and "di", and an expansion that only
        // knew "'yung" would turn a correct "yung" into a substitution.
        // "'to" (ito) is left out: bare "to" is the English word, and a
        // quoted "'to be'" is not Tagalog.
        "'di": "hindi", "di": "hindi", "'wag": "huwag", "wag": "huwag",
        "'yan": "iyan", "yan": "iyan", "'yun": "iyon", "yun": "iyon",
        "'yon": "iyon", "yon": "iyon", "'yung": "iyong", "yung": "iyong",
    ]
}

/// Applies a ``ScoringPolicy`` to text, in the six steps its doc comment fixes.
///
/// The input is never modified; scoring works on the copy this returns.
///
/// Choices worth knowing:
///
///  * Case folding is `String.lowercased()`: full Unicode lower-case mapping,
///    independent of the user's locale (so "İ" becomes "i̇", not a Turkish "i").
///  * `unicodeForm == .none` applies no normalization. That loses less than it
///    sounds: Swift compares `String` and `Character` by canonical
///    equivalence, so an NFC "é" and an NFD "é" are already the same token.
///    What NFKC adds is compatibility folding: full-width "ＡＢＣ" is "abc"
///    and the ligature "ﬁ" is "fi".
///  * Word characters are scalars in the Unicode general categories L*, M* and
///    N*. A combining mark extends the word it follows; a mark with nothing to
///    attach to (after a space or a punctuation character) is not a word.
///  * Whitespace and the invisible format and control characters (zero-width
///    space, zero-width joiner, ...) separate words and are never tokens, even
///    when punctuation is kept.
///  * U+2010 and U+2011 are hyphens, scored as "-". En and em dashes are
///    punctuation.
///  * With punctuation kept, each punctuation scalar is a token of its own, so
///    an emoji written as several scalars is several tokens.
///
/// Where `.standard` differs from `eval/score.py` (all deliberate, all rare in
/// meeting transcripts, all pinned by tests):
///
///  * Underscore: Python's `\w` keeps it inside a word ("foo_bar"); here it is
///    punctuation ("foo", "bar").
///  * Combining marks that survive NFKC, such as the tilde of Tagalog "ng̃":
///    Python's `\w` has no marks, so it splits "ng̃a" into "ng", "a"; here it
///    stays one word, which is the point of scoring orthography at all.
///  * U+02BC and the backtick: step 2 makes them apostrophes, as the policy
///    says; `score.py` only maps U+2018/U+2019.
///  * Greek final sigma: Python lower-cases word-final "Σ" to "ς", Swift to "σ".
public enum TextNormalizer {
    /// Normalized word tokens under `policy`, following the 6 steps in
    /// ``ScoringPolicy``'s doc comment.
    public static func words(_ text: String, policy: ScoringPolicy) -> [String] {
        var s = unicodeNormalized(text, policy.unicodeForm)                        // 1
        s = straightenedApostrophes(s)                                            // 2
        if policy.caseFolding { s = s.lowercased() }                              // 3
        if policy.contractions == .expand {                                       // 4
            s = expandedContractions(s, tableVersion: policy.contractionTableVersion)
        }
        if policy.stripDiacritics {                                               // 5
            s = s.folding(options: .diacriticInsensitive, locale: nil)
        }
        return tokens(s, policy: policy)                                          // 6
    }

    /// Units for CER: `words(text, policy)` joined by single spaces, as
    /// grapheme clusters, so "ñ" is one unit whether it was written as one
    /// scalar or two.
    public static func characters(_ text: String, policy: ScoringPolicy) -> [Character] {
        Array(words(text, policy: policy).joined(separator: " "))
    }

    // MARK: - Steps 1 and 2

    static func unicodeNormalized(_ text: String, _ form: ScoringPolicy.UnicodeForm) -> String {
        switch form {
        case .none: return text
        case .nfc: return text.precomposedStringWithCanonicalMapping
        case .nfd: return text.decomposedStringWithCanonicalMapping
        case .nfkc: return text.precomposedStringWithCompatibilityMapping
        case .nfkd: return text.decomposedStringWithCompatibilityMapping
        }
    }

    private static let apostropheLike: Set<UInt32> = [0x2019, 0x2018, 0x02BC, 0x0060, 0x00B4]

    /// Scalar by scalar, not Character by Character: a curly apostrophe right
    /// after a letter must not be swallowed into that letter's cluster.
    static func straightenedApostrophes(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            out.append(apostropheLike.contains(scalar.value) ? "'" : scalar)
        }
        return String(out)
    }

    // MARK: - Step 4

    /// Expands contractions word by word, keeping the whitespace between words
    /// as it was. A word is matched after stripping punctuation around it
    /// ("(don't," matches "don't"), and an expansion is written in lower case
    /// whether or not the policy folds case.
    static func expandedContractions(_ text: String, tableVersion: Int) -> String {
        guard let table = ContractionTable.table(version: tableVersion) else { return text }
        let enclitic = ContractionTable.hasEncliticRule(version: tableVersion)
        var out = ""
        var word = String.UnicodeScalarView()
        func flush() {
            guard !word.isEmpty else { return }
            out += expandedWord(String(word), table: table, enclitic: enclitic)
            word = String.UnicodeScalarView()
        }
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                flush()
                out.unicodeScalars.append(scalar)
            } else {
                word.append(scalar)
            }
        }
        flush()
        return out
    }

    private static func expandedWord(_ word: String, table: [String: String], enclitic: Bool) -> String {
        let scalars = Array(word.unicodeScalars)
        // Leading punctuation is stripped but a leading apostrophe is kept,
        // because it is part of the clipped Tagalog forms ("'di", "'yung").
        var start = 0
        while start < scalars.count, !isWordScalar(scalars[start]), scalars[start] != "'" { start += 1 }
        var end = scalars.count
        while end > start, !isWordScalar(scalars[end - 1]) { end -= 1 }
        guard start < end else { return word }

        let prefix = String(String.UnicodeScalarView(scalars[..<start]))
        let suffix = String(String.UnicodeScalarView(scalars[end...]))
        let core = String(String.UnicodeScalarView(scalars[start..<end]))
        let key = core.lowercased()

        if let expansion = table[key] { return prefix + expansion + suffix }
        // A quoting apostrophe in front of an English contraction: "'don't".
        if key.hasPrefix("'"), let expansion = table[String(key.dropFirst())] {
            return prefix + expansion + suffix
        }
        if enclitic, key.hasSuffix("'y") {
            let stem = Array(scalars[start..<(end - 2)])
            if let last = stem.last, isWordScalar(last) {
                return prefix + String(String.UnicodeScalarView(stem)) + " ay" + suffix
            }
        }
        return word
    }

    // MARK: - Step 6

    private enum ScalarClass { case word, mark, apostrophe, hyphen, separator, punctuation }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch classify(scalar) {
        case .word, .mark: return true
        default: return false
        }
    }

    private static func classify(_ scalar: Unicode.Scalar) -> ScalarClass {
        switch scalar.value {
        case 0x27: return .apostrophe
        case 0x2D, 0x2010, 0x2011: return .hyphen
        default: break
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return .word
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return .mark
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format,
             .surrogate, .privateUse, .unassigned:
            return .separator
        default:
            return scalar.properties.isWhitespace ? .separator : .punctuation
        }
    }

    private enum Role { case word, separator, punctuation, attachToPunctuation }

    static func tokens(_ text: String, policy: ScoringPolicy) -> [String] {
        var scalars = Array(text.unicodeScalars)
        if policy.apostrophes == .delete { scalars.removeAll { $0 == "'" } }
        let classes = scalars.map(classify)
        let keepPunctuation = policy.punctuation == .keep

        // Roles in one left-to-right pass. A mark joins what precedes it; an
        // apostrophe or hyphen is part of a word only between two word
        // characters of the input, as `(?<!\w)'|'(?!\w)` decides in score.py.
        var roles = [Role](repeating: .separator, count: scalars.count)
        for k in scalars.indices {
            switch classes[k] {
            case .word:
                roles[k] = .word
            case .mark:
                if k > 0, roles[k - 1] == .word {
                    roles[k] = .word
                } else if k > 0, keepPunctuation, roles[k - 1] == .punctuation || roles[k - 1] == .attachToPunctuation {
                    roles[k] = .attachToPunctuation
                } else {
                    roles[k] = .separator
                }
            case .apostrophe, .hyphen:
                let policyKeeps = classes[k] == .apostrophe
                    ? policy.apostrophes == .keepIntraWord
                    : policy.hyphens == .keepIntraWord
                let intraWord = k > 0 && roles[k - 1] == .word
                    && k + 1 < scalars.count && isWordScalarIntraWord(classes[k + 1])
                if policyKeeps && intraWord {
                    roles[k] = .word
                } else {
                    roles[k] = keepPunctuation ? .punctuation : .separator
                }
            case .punctuation:
                roles[k] = keepPunctuation ? .punctuation : .separator
            case .separator:
                roles[k] = .separator
            }
        }

        var result: [String] = []
        var current = String.UnicodeScalarView()
        var currentIsWord = false
        func flush() {
            if !current.isEmpty { result.append(String(current)) }
            current = String.UnicodeScalarView()
        }
        for k in scalars.indices {
            switch roles[k] {
            case .word:
                if !currentIsWord { flush() }
                currentIsWord = true
                current.append(classes[k] == .hyphen ? "-" : scalars[k])
            case .punctuation:
                flush()
                currentIsWord = false
                current.append(scalars[k])
            case .attachToPunctuation:
                current.append(scalars[k])
            case .separator:
                flush()
                currentIsWord = false
            }
        }
        flush()
        return result
    }

    /// The character after an apostrophe or hyphen: a mark there has no base
    /// (the apostrophe is not one), so only a letter or number continues a word.
    private static func isWordScalarIntraWord(_ c: ScalarClass) -> Bool { c == .word }
}
