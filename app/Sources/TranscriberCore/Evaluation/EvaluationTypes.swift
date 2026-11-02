import Foundation
import CryptoKit

// The shared vocabulary of the evaluation framework.
//
// Everything in `Evaluation/` is pure logic: no audio, no model, no network. A
// score is a function of three inputs -- a reference, a hypothesis and an
// `EvaluationConfig` -- and the same three inputs give the same bytes out. That
// is the property the framework exists for, and the tests hold it.
//
// Two rules run through every type here:
//
//   * Raw text is kept verbatim. Normalization makes a *copy* to score; the
//     reference and hypothesis the caller supplied are reported unchanged.
//   * A metric that needs ground truth that is not there is `.unavailable`
//     with a reason. It is never 0, never 1, and never quietly left out.

// MARK: - Errors

public enum EvaluationError: Error, Equatable, CustomStringConvertible {
    /// A config, reference or report written by a schema this build does not read.
    case unsupportedSchema(kind: String, found: Int, supported: Int)
    /// Input that is well-formed JSON and still wrong, e.g. language spans that
    /// do not add up to the utterance text.
    case invalidInput(String)
    /// Two runs that cannot be compared: different corpus, items or policy.
    case incomparable(String)

    public var description: String {
        switch self {
        case let .unsupportedSchema(kind, found, supported):
            return "\(kind) schema version \(found) is not supported (this build reads \(supported))"
        case let .invalidInput(message): return "invalid input: \(message)"
        case let .incomparable(message): return "cannot compare: \(message)"
        }
    }
}

// MARK: - A value or an explicit absence

/// A number the evaluator measured, or a statement of why it could not.
///
/// Encoded as `{"status":"available","value":0.25}` or
/// `{"status":"unavailable","reason":"..."}`, so a reader of the JSON cannot
/// mistake a missing metric for a zero.
public enum MetricValue: Codable, Sendable, Equatable {
    case available(Double)
    case unavailable(reason: String)

    public var value: Double? {
        if case let .available(v) = self { return v }
        return nil
    }

    public var isAvailable: Bool { value != nil }

    public var unavailableReason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }

    /// `numerator / denominator`, or unavailable when the denominator is zero.
    public static func ratio(_ numerator: Int, _ denominator: Int, unavailable reason: String) -> MetricValue {
        denominator > 0 ? .available(Double(numerator) / Double(denominator)) : .unavailable(reason: reason)
    }

    private enum CodingKeys: String, CodingKey { case status, value, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "available": self = .available(try c.decode(Double.self, forKey: .value))
        case "unavailable": self = .unavailable(reason: try c.decode(String.self, forKey: .reason))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .status, in: c,
                                                   debugDescription: "unknown status \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .available(v):
            try c.encode("available", forKey: .status)
            try c.encode(v, forKey: .value)
        case let .unavailable(reason):
            try c.encode("unavailable", forKey: .status)
            try c.encode(reason, forKey: .reason)
        }
    }
}

/// A whole result section that was computed, or a statement of why not.
/// Encoded as `{"status":"available","value":{...}}` or
/// `{"status":"unavailable","reason":"..."}`, as ``MetricValue`` is.
public enum Measured<T> {
    case available(T)
    case unavailable(reason: String)

    public var value: T? {
        if case let .available(v) = self { return v }
        return nil
    }

    public var unavailableReason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }

    public func map<U>(_ transform: (T) -> U) -> Measured<U> {
        switch self {
        case let .available(v): return .available(transform(v))
        case let .unavailable(reason): return .unavailable(reason: reason)
        }
    }
}

extension Measured: Sendable where T: Sendable {}
extension Measured: Equatable where T: Equatable {}

extension Measured: Codable where T: Codable {
    private enum CodingKeys: String, CodingKey { case status, value, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "available": self = .available(try c.decode(T.self, forKey: .value))
        case "unavailable": self = .unavailable(reason: try c.decode(String.self, forKey: .reason))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .status, in: c,
                                                   debugDescription: "unknown status \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .available(v):
            try c.encode("available", forKey: .status)
            try c.encode(v, forKey: .value)
        case let .unavailable(reason):
            try c.encode("unavailable", forKey: .status)
            try c.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Edit counts

/// The outcome of aligning a reference to a hypothesis, in units (words or
/// characters). `rate` is (S + D + I) / N, where N is the reference length.
public struct ErrorCounts: Codable, Sendable, Equatable {
    public var hits: Int
    public var substitutions: Int
    public var deletions: Int
    public var insertions: Int

    public init(hits: Int = 0, substitutions: Int = 0, deletions: Int = 0, insertions: Int = 0) {
        self.hits = hits
        self.substitutions = substitutions
        self.deletions = deletions
        self.insertions = insertions
    }

    public static let zero = ErrorCounts()

    /// N: every reference unit is a hit, a substitution or a deletion.
    public var referenceLength: Int { hits + substitutions + deletions }
    /// Every hypothesis unit is a hit, a substitution or an insertion.
    public var hypothesisLength: Int { hits + substitutions + insertions }
    public var errors: Int { substitutions + deletions + insertions }

    /// Unavailable when the reference is empty: an error rate over zero words
    /// is undefined, and reporting 0 or 1 for it would invent a number.
    public var rate: MetricValue {
        .ratio(errors, referenceLength, unavailable: "the reference has no units to score against")
    }

    public static func + (lhs: ErrorCounts, rhs: ErrorCounts) -> ErrorCounts {
        ErrorCounts(hits: lhs.hits + rhs.hits,
                    substitutions: lhs.substitutions + rhs.substitutions,
                    deletions: lhs.deletions + rhs.deletions,
                    insertions: lhs.insertions + rhs.insertions)
    }

    public static func += (lhs: inout ErrorCounts, rhs: ErrorCounts) { lhs = lhs + rhs }

    // The derived figures are written out too, so a reader of the JSON does
    // not have to recompute them, and are ignored on the way back in.
    private enum CodingKeys: String, CodingKey {
        case hits, substitutions, deletions, insertions, referenceLength, hypothesisLength, errors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hits: try c.decode(Int.self, forKey: .hits),
                  substitutions: try c.decode(Int.self, forKey: .substitutions),
                  deletions: try c.decode(Int.self, forKey: .deletions),
                  insertions: try c.decode(Int.self, forKey: .insertions))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hits, forKey: .hits)
        try c.encode(substitutions, forKey: .substitutions)
        try c.encode(deletions, forKey: .deletions)
        try c.encode(insertions, forKey: .insertions)
        try c.encode(referenceLength, forKey: .referenceLength)
        try c.encode(hypothesisLength, forKey: .hypothesisLength)
        try c.encode(errors, forKey: .errors)
    }
}

// MARK: - Scoring policy

/// How text is turned into the units that are scored. Versioned: a policy is
/// identified by `id` and `version`, and its `fingerprint` changes when any
/// setting does, so two numbers made under different rules cannot be mistaken
/// for one another.
///
/// The steps run in this fixed order (``TextNormalizer`` implements them):
///
///  1. Unicode normalization (`unicodeForm`).
///  2. Apostrophe-like characters (U+2019, U+2018, U+02BC, U+0060, U+00B4) become U+0027.
///     Under NFKC and NFKD, U+00B4 has already become a space and a combining
///     acute in step 1, so it separates words there instead.
///  3. Case folding (`caseFolding`).
///  4. Contraction expansion (`contractions`), on whitespace-separated words.
///  5. Diacritic removal (`stripDiacritics`).
///  6. Tokenization: word characters are Unicode letters, marks and numbers;
///     apostrophes and hyphens follow their policies; everything else is
///     punctuation and follows `punctuation`.
public struct ScoringPolicy: Codable, Sendable, Equatable {
    public enum UnicodeForm: String, Codable, Sendable { case none, nfc, nfd, nfkc, nfkd }
    /// `remove`: punctuation separates words and is not scored.
    /// `keep`: each punctuation character is a token of its own.
    public enum PunctuationPolicy: String, Codable, Sendable { case remove, keep }
    /// `split`: "i-send" is two words. `keepIntraWord`: it is one; a hyphen at a
    /// word edge is still dropped.
    public enum HyphenPolicy: String, Codable, Sendable { case split, keepIntraWord }
    /// `keepIntraWord`: "don't" stays one word, a leading or trailing apostrophe
    /// is dropped. `split`: the apostrophe separates ("don", "t"), as the
    /// legacy CLI scorer does. `delete`: the character is removed ("dont").
    public enum ApostrophePolicy: String, Codable, Sendable { case keepIntraWord, split, delete }
    /// `keep`: contractions are scored as written. `expand`: both sides are
    /// expanded with the built-in table of `contractionTableVersion`
    /// (``ContractionTable``), so "ako'y" and "ako ay" score as the same words.
    public enum ContractionPolicy: String, Codable, Sendable { case keep, expand }

    public var id: String
    public var version: Int
    public var unicodeForm: UnicodeForm
    public var caseFolding: Bool
    public var stripDiacritics: Bool
    public var punctuation: PunctuationPolicy
    public var hyphens: HyphenPolicy
    public var apostrophes: ApostrophePolicy
    public var contractions: ContractionPolicy
    public var contractionTableVersion: Int

    public init(id: String, version: Int = 1, unicodeForm: UnicodeForm = .nfkc,
                caseFolding: Bool = true, stripDiacritics: Bool = false,
                punctuation: PunctuationPolicy = .remove, hyphens: HyphenPolicy = .split,
                apostrophes: ApostrophePolicy = .keepIntraWord,
                contractions: ContractionPolicy = .keep, contractionTableVersion: Int = 1) {
        self.id = id
        self.version = version
        self.unicodeForm = unicodeForm
        self.caseFolding = caseFolding
        self.stripDiacritics = stripDiacritics
        self.punctuation = punctuation
        self.hyphens = hyphens
        self.apostrophes = apostrophes
        self.contractions = contractions
        self.contractionTableVersion = contractionTableVersion
    }

    /// The default. The same rules as `eval/score.py`, which produced the
    /// 2026-11-01 baseline tables: NFKC, lower case, punctuation removed,
    /// hyphens split, intra-word apostrophes kept, diacritics kept.
    public static let standard = ScoringPolicy(id: "notero-standard")

    /// As `standard`, but "i-send" stays one word, as in `eval/langscore.py`.
    /// Not an exact copy of that scorer: it treats an en dash as a hyphen and
    /// U+2010 as a separator, where this policy does the opposite.
    public static let keepHyphens = ScoringPolicy(id: "notero-keep-hyphens", hyphens: .keepIntraWord)

    /// The rules of `WordErrorRate.words`, the CLI's legacy scorer: lower case,
    /// diacritics removed, every non-alphanumeric character a separator.
    public static let legacyCLI = ScoringPolicy(id: "notero-legacy-cli", unicodeForm: .none,
                                                stripDiacritics: true, apostrophes: .split)

    /// `standard` with contractions expanded on both sides.
    public static let expandContractions = ScoringPolicy(id: "notero-expand-contractions",
                                                         contractions: .expand)

    public static let presets: [ScoringPolicy] = [.standard, .keepHyphens, .legacyCLI, .expandContractions]

    public static func preset(named id: String) -> ScoringPolicy? {
        presets.first { $0.id == id }
    }

    /// SHA-256 of the canonical JSON of this policy, hex. Changes with any setting.
    public var fingerprint: String { CanonicalJSON.fingerprint(self) }
}

// MARK: - Evaluation configuration

/// Everything that decides a score, in one versioned file.
///
/// The JSON form is what `transcribe --score --config FILE` reads. A file with
/// a `schemaVersion` this build does not know is rejected, not guessed at.
public struct EvaluationConfig: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// A name for this configuration, e.g. "notero-eval-v1". Recorded in every report.
    public var id: String
    public var scoring: ScoringPolicy
    public var bootstrap: BootstrapSettings
    public var missingSpeech: MissingSpeechSettings
    /// A run of at least this many consecutive deleted reference words is
    /// reported as a deletion burst: the shape of a window that never decoded.
    public var deletionBurstMinWords: Int

    public init(schemaVersion: Int = EvaluationConfig.currentSchemaVersion,
                id: String = "notero-eval-v1",
                scoring: ScoringPolicy = .standard,
                bootstrap: BootstrapSettings = BootstrapSettings(),
                missingSpeech: MissingSpeechSettings = MissingSpeechSettings(),
                deletionBurstMinWords: Int = 3) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.scoring = scoring
        self.bootstrap = bootstrap
        self.missingSpeech = missingSpeech
        self.deletionBurstMinWords = deletionBurstMinWords
    }

    public static let `default` = EvaluationConfig()

    /// Decodes and validates a config. Rejects an unknown schema version and
    /// settings that cannot produce a meaningful result.
    public static func load(from data: Data) throws -> EvaluationConfig {
        let config = try JSONDecoder().decode(EvaluationConfig.self, from: data)
        try config.validate()
        return config
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EvaluationError.unsupportedSchema(kind: "evaluation config", found: schemaVersion,
                                                    supported: Self.currentSchemaVersion)
        }
        guard bootstrap.resamples > 0 else {
            throw EvaluationError.invalidInput("bootstrap.resamples must be positive")
        }
        guard bootstrap.confidenceLevel > 0, bootstrap.confidenceLevel < 1 else {
            throw EvaluationError.invalidInput("bootstrap.confidenceLevel must be between 0 and 1")
        }
        guard missingSpeech.coverageThreshold >= 0, missingSpeech.coverageThreshold <= 1 else {
            throw EvaluationError.invalidInput("missingSpeech.coverageThreshold must be between 0 and 1")
        }
        guard missingSpeech.minRegionMs >= 0, missingSpeech.wordPaddingMs >= 0 else {
            throw EvaluationError.invalidInput("missingSpeech durations must not be negative")
        }
        guard deletionBurstMinWords > 0 else {
            throw EvaluationError.invalidInput("deletionBurstMinWords must be positive")
        }
    }

    /// Canonical JSON: sorted keys, so the same config is the same bytes.
    public func canonicalJSON() throws -> Data { try CanonicalJSON.encode(self) }

    public var fingerprint: String { CanonicalJSON.fingerprint(self) }
}

/// Settings of the paired bootstrap (``Bootstrap``).
public struct BootstrapSettings: Codable, Sendable, Equatable {
    /// What one resampled unit is. `utterance` needs a reference with more
    /// than one utterance; `item` resamples whole recordings.
    public enum Unit: String, Codable, Sendable { case utterance, item }

    public var resamples: Int
    /// The seed of the generator. The same seed and the same inputs give the
    /// same interval, on every machine.
    public var seed: UInt64
    public var confidenceLevel: Double
    public var unit: Unit
    /// Resample inside each stratum (the utterance language class), so every
    /// resample keeps the corpus's mix of Tagalog, English and code-switched speech.
    public var stratify: Bool
    /// Below this many units an interval is reported as unavailable.
    public var minimumUnits: Int

    public init(resamples: Int = 2000, seed: UInt64 = 20_261_102, confidenceLevel: Double = 0.95,
                unit: Unit = .utterance, stratify: Bool = true, minimumUnits: Int = 2) {
        self.resamples = resamples
        self.seed = seed
        self.confidenceLevel = confidenceLevel
        self.unit = unit
        self.stratify = stratify
        self.minimumUnits = minimumUnits
    }
}

/// Settings of the missing-speech check (``MissingSpeech``).
public struct MissingSpeechSettings: Codable, Sendable, Equatable {
    /// Reference regions shorter than this are not checked.
    public var minRegionMs: Int
    /// A region whose share covered by hypothesis words is below this is missing.
    public var coverageThreshold: Double
    /// Each hypothesis word's interval is widened by this much on each side,
    /// because word timestamps are approximate.
    public var wordPaddingMs: Int

    public init(minRegionMs: Int = 1000, coverageThreshold: Double = 0.2, wordPaddingMs: Int = 200) {
        self.minRegionMs = minRegionMs
        self.coverageThreshold = coverageThreshold
        self.wordPaddingMs = wordPaddingMs
    }
}

// MARK: - References and hypotheses

/// The utterance-level language of a reference line, the stratum of the
/// stratified results and of the stratified bootstrap.
public enum LanguageClass: String, Codable, Sendable, CaseIterable, Comparable {
    case tagalog
    case english
    case codeSwitched = "code-switched"
    case other
    /// The reference says nothing about language.
    case unannotated

    public static func < (lhs: LanguageClass, rhs: LanguageClass) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A piece of an utterance in one language. The spans of an utterance, in
/// order, concatenate to its `text` exactly.
public struct LanguageSpan: Codable, Sendable, Equatable {
    public var text: String
    /// "tl" (or "fil"), "en", or any other code, which counts as other.
    public var language: String

    public init(text: String, language: String) {
        self.text = text
        self.language = language
    }
}

/// One line of a reference transcript.
public struct ReferenceUtterance: Codable, Sendable, Equatable {
    public var id: String
    /// Verbatim, as transcribed. Never modified by scoring.
    public var text: String
    /// Where the line is in the audio, when the reference says so.
    public var startMs: Int?
    public var endMs: Int?
    public var speaker: String?
    /// The annotator marked this line as overlapping another speaker.
    public var overlap: Bool?
    /// Utterance-level language: "tl"/"fil", "en", "mixed" (code-switched), or other.
    public var language: String?
    /// Word-level language, when annotated. Takes precedence over `language`.
    public var languageSpans: [LanguageSpan]?

    public init(id: String, text: String, startMs: Int? = nil, endMs: Int? = nil,
                speaker: String? = nil, overlap: Bool? = nil, language: String? = nil,
                languageSpans: [LanguageSpan]? = nil) {
        self.id = id
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.speaker = speaker
        self.overlap = overlap
        self.language = language
        self.languageSpans = languageSpans
    }

    public var hasTimes: Bool {
        guard let startMs, let endMs else { return false }
        return endMs > startMs
    }
}

/// The ground truth for one recording.
///
/// Two forms are read: this JSON (`schemaVersion`, `itemId`, `utterances`),
/// which can carry times, speakers, overlap and language; and a plain UTF-8
/// text file, one utterance per non-empty line, which carries none of them.
/// A metric that needs what the reference lacks is reported as unavailable.
public struct EvaluationReference: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var itemId: String
    public var utterances: [ReferenceUtterance]
    /// The file text of a plain-text reference, byte for byte (line endings,
    /// blank lines and all), so the report can show exactly what was supplied.
    /// Nil for the JSON form, whose utterance texts are the verbatim record.
    public var sourceText: String?

    public init(schemaVersion: Int = EvaluationReference.currentSchemaVersion,
                itemId: String, utterances: [ReferenceUtterance], sourceText: String? = nil) {
        self.schemaVersion = schemaVersion
        self.itemId = itemId
        self.utterances = utterances
        self.sourceText = sourceText
    }

    /// One utterance per non-empty line, ids "line-1", "line-2", … counting
    /// every line of the file, so an id points at the line it came from.
    /// The line text is kept verbatim, including surrounding whitespace.
    public static func plainText(_ text: String, itemId: String) -> EvaluationReference {
        var utterances: [ReferenceUtterance] = []
        var number = 0
        text.enumerateLines { line, _ in
            number += 1
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                utterances.append(ReferenceUtterance(id: "line-\(number)", text: line))
            }
        }
        return EvaluationReference(itemId: itemId, utterances: utterances, sourceText: text)
    }

    /// Decodes and validates the JSON form.
    public static func load(json data: Data) throws -> EvaluationReference {
        let reference = try JSONDecoder().decode(EvaluationReference.self, from: data)
        try reference.validate()
        return reference
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw EvaluationError.unsupportedSchema(kind: "evaluation reference", found: schemaVersion,
                                                    supported: Self.currentSchemaVersion)
        }
        var seen = Set<String>()
        for u in utterances {
            guard seen.insert(u.id).inserted else {
                throw EvaluationError.invalidInput("utterance id \(u.id) appears twice in \(itemId)")
            }
            if let s = u.startMs, let e = u.endMs, e < s {
                throw EvaluationError.invalidInput("utterance \(u.id) ends before it starts")
            }
            if (u.startMs == nil) != (u.endMs == nil) {
                throw EvaluationError.invalidInput("utterance \(u.id) has only one of startMs and endMs")
            }
            if let spans = u.languageSpans, spans.map(\.text).joined() != u.text {
                throw EvaluationError.invalidInput(
                    "the language spans of utterance \(u.id) do not concatenate to its text")
            }
        }
    }

    /// The whole reference as one string, utterances joined by newlines.
    public var rawText: String { utterances.map(\.text).joined(separator: "\n") }
}

/// What a system produced for one recording.
public struct EvaluationHypothesis: Codable, Sendable, Equatable {
    /// Verbatim system output. Never modified by scoring.
    public var text: String
    /// Timestamped words, when the system produced them. Needed for the
    /// missing-speech check; scoring itself reads `text`.
    public var words: [Token]?

    public init(text: String, words: [Token]? = nil) {
        self.text = text
        self.words = words
    }
}

// MARK: - Canonical JSON

/// Sorted keys and no pretty-printing, so the same value is the same bytes.
public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Pretty-printed and sorted, for files a person reads. Still deterministic.
    public static func encodePretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func fingerprint<T: Encodable>(_ value: T) -> String {
        // Encoding a plain value type of strings, numbers and booleans does
        // not fail; if it ever did, the fingerprint says so rather than crash.
        guard let data = try? encode(value) else { return "unencodable" }
        return sha256Hex(data)
    }

    /// SHA-256 of raw bytes, lower-case hex.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
