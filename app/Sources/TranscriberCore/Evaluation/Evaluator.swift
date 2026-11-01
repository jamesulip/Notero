import Foundation

// Scoring one item: a reference, a hypothesis and a config in, an `ItemScore`
// out, the same bytes every time.
//
// The item is aligned once, as a whole, and that one alignment is projected
// onto the reference utterances. Aligning utterance by utterance would need a
// segmentation of the hypothesis that the system never produced, and would
// make the item WER depend on it; projecting keeps the item WER exactly the
// WER of the joined text, and the per-utterance counts sum to it.

// MARK: - Result types

/// The scores of one stratum: a language class, or overlap / no overlap.
public struct StratumScore: Codable, Sendable, Equatable {
    /// e.g. "tagalog", "code-switched", "overlap", "no-overlap".
    public var stratum: String
    public var utterances: Int
    public var words: ErrorCounts
    public var characters: ErrorCounts
    public var wer: MetricValue
    public var cer: MetricValue

    public init(stratum: String, utterances: Int, words: ErrorCounts, characters: ErrorCounts,
                wer: MetricValue, cer: MetricValue) {
        self.stratum = stratum
        self.utterances = utterances
        self.words = words
        self.characters = characters
        self.wer = wer
        self.cer = cer
    }
}

/// Errors attributed to reference words of one language.
public struct LanguageErrorCounts: Codable, Sendable, Equatable {
    public var referenceWords: Int
    public var hits: Int
    public var substitutions: Int
    public var deletions: Int
    /// (S + D) / referenceWords. Insertions have no reference word and are
    /// excluded; unavailable when referenceWords == 0.
    public var rate: MetricValue

    public init(referenceWords: Int, hits: Int, substitutions: Int, deletions: Int, rate: MetricValue) {
        self.referenceWords = referenceWords
        self.hits = hits
        self.substitutions = substitutions
        self.deletions = deletions
        self.rate = rate
    }

    init(hits: Int, substitutions: Int, deletions: Int) {
        let n = hits + substitutions + deletions
        self.init(referenceWords: n, hits: hits, substitutions: substitutions, deletions: deletions,
                  rate: .ratio(substitutions + deletions, n,
                               unavailable: "no reference words in this group"))
    }
}

public struct LanguageBreakdown: Codable, Sendable, Equatable {
    /// Keyed "tl", "en", "other" (only those present). Word language comes from
    /// languageSpans, or from a single-language utterance tag ("tl"/"fil" -> tl,
    /// "en" -> en, any other single code -> other).
    public var byLanguage: [String: LanguageErrorCounts]
    /// Reference words at a code-switch point (language differs from the
    /// previous word in the same utterance), from span-annotated utterances only.
    public var codeSwitchPoints: Measured<LanguageErrorCounts>
    /// The other words of span-annotated utterances, the first word included.
    public var nonSwitchPoints: Measured<LanguageErrorCounts>
    public var insertionsUnattributed: Int
    /// Reference words with no word-level language (mixed/unannotated utterances
    /// without spans, or spans that do not split at word boundaries).
    public var unattributedReferenceWords: Int

    public init(byLanguage: [String: LanguageErrorCounts], codeSwitchPoints: Measured<LanguageErrorCounts>,
                nonSwitchPoints: Measured<LanguageErrorCounts>, insertionsUnattributed: Int,
                unattributedReferenceWords: Int) {
        self.byLanguage = byLanguage
        self.codeSwitchPoints = codeSwitchPoints
        self.nonSwitchPoints = nonSwitchPoints
        self.insertionsUnattributed = insertionsUnattributed
        self.unattributedReferenceWords = unattributedReferenceWords
    }
}

/// A run of consecutive deleted reference words: the shape of a window that
/// never decoded, which a WER alone averages away.
public struct DeletionBurst: Codable, Sendable, Equatable {
    public var firstUtteranceId: String
    public var lastUtteranceId: String
    /// Index into the item's normalized reference words.
    public var referenceStartIndex: Int
    public var length: Int
    /// The normalized deleted words.
    public var words: [String]
    /// The first utterance's startMs, when it is timed.
    public var startMs: Int?
    /// The last utterance's endMs, when it is timed.
    public var endMs: Int?

    public init(firstUtteranceId: String, lastUtteranceId: String, referenceStartIndex: Int, length: Int,
                words: [String], startMs: Int?, endMs: Int?) {
        self.firstUtteranceId = firstUtteranceId
        self.lastUtteranceId = lastUtteranceId
        self.referenceStartIndex = referenceStartIndex
        self.length = length
        self.words = words
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct UtteranceScore: Codable, Sendable, Equatable {
    public var id: String
    public var languageClass: LanguageClass
    public var speaker: String?
    /// The annotation when there is one (it wins over the derivation).
    /// Otherwise true when a timed turn of another speaker intersects this
    /// one, false when timed with a speaker and nothing intersects, and nil
    /// when neither can be said.
    public var overlap: Bool?
    public var startMs: Int?
    public var endMs: Int?
    /// The utterance text, verbatim.
    public var rawReference: String
    public var normalizedReference: [String]
    /// The normalized hypothesis words the item alignment projected onto this utterance.
    public var assignedHypothesis: [String]
    public var words: ErrorCounts
    public var characters: ErrorCounts
    public var wer: MetricValue
    public var cer: MetricValue

    public init(id: String, languageClass: LanguageClass, speaker: String?, overlap: Bool?,
                startMs: Int?, endMs: Int?, rawReference: String, normalizedReference: [String],
                assignedHypothesis: [String], words: ErrorCounts, characters: ErrorCounts,
                wer: MetricValue, cer: MetricValue) {
        self.id = id
        self.languageClass = languageClass
        self.speaker = speaker
        self.overlap = overlap
        self.startMs = startMs
        self.endMs = endMs
        self.rawReference = rawReference
        self.normalizedReference = normalizedReference
        self.assignedHypothesis = assignedHypothesis
        self.words = words
        self.characters = characters
        self.wer = wer
        self.cer = cer
    }
}

public struct ItemScore: Codable, Sendable, Equatable {
    public var itemId: String
    /// The reference as supplied, verbatim: the file text of a plain-text
    /// reference (`sourceText`), otherwise the utterance texts joined by "\n".
    public var rawReference: String
    /// `hypothesis.text`, verbatim.
    public var rawHypothesis: String
    public var normalizedHypothesis: [String]
    /// From the whole-item word alignment.
    public var words: ErrorCounts
    /// The sum of the per-utterance character counts (see ``Evaluator``).
    public var characters: ErrorCounts
    public var wer: MetricValue
    public var cer: MetricValue
    public var utterances: Measured<[UtteranceScore]>
    /// Only the classes present, in `LanguageClass` order.
    public var byLanguageClass: [StratumScore]
    /// "overlap" and "no-overlap", both always present when available, and
    /// "unknown" for utterances that can be neither (untimed, no speaker),
    /// when there are any: so the strata always add up to the item.
    public var byOverlap: Measured<[StratumScore]>
    public var languageBreakdown: Measured<LanguageBreakdown>
    public var deletionBursts: Measured<[DeletionBurst]>
    public var missingSpeech: Measured<MissingSpeechReport>

    public init(itemId: String, rawReference: String, rawHypothesis: String, normalizedHypothesis: [String],
                words: ErrorCounts, characters: ErrorCounts, wer: MetricValue, cer: MetricValue,
                utterances: Measured<[UtteranceScore]>, byLanguageClass: [StratumScore],
                byOverlap: Measured<[StratumScore]>, languageBreakdown: Measured<LanguageBreakdown>,
                deletionBursts: Measured<[DeletionBurst]>, missingSpeech: Measured<MissingSpeechReport>) {
        self.itemId = itemId
        self.rawReference = rawReference
        self.rawHypothesis = rawHypothesis
        self.normalizedHypothesis = normalizedHypothesis
        self.words = words
        self.characters = characters
        self.wer = wer
        self.cer = cer
        self.utterances = utterances
        self.byLanguageClass = byLanguageClass
        self.byOverlap = byOverlap
        self.languageBreakdown = languageBreakdown
        self.deletionBursts = deletionBursts
        self.missingSpeech = missingSpeech
    }
}

// MARK: - Evaluator

/// Scores one item.
///
/// * Reference words: each utterance is tokenized on its own and the item's
///   words are their concatenation, so the item WER is the WER of the joined
///   text and every reference word knows its utterance. With language spans,
///   each span is tokenized on its own and its words take its language; if
///   those words do not concatenate to the utterance's own words (a span
///   boundary inside a word), the utterance's words are used and left without
///   a word-level language.
/// * Projection: a hit or substitution belongs to the utterance of its
///   reference word. An insertion belongs to the utterance of the nearest
///   preceding reference word in the path, or, before the first one, of the
///   first following one. With no reference words at all, insertions go to the
///   first utterance.
/// * CER: per utterance, the characters of its normalized words joined by
///   spaces against those of its assigned hypothesis words; the item figure is
///   the sum. Characters therefore never align across an utterance boundary.
public enum Evaluator {
    public static func score(reference: EvaluationReference, hypothesis: EvaluationHypothesis,
                             config: EvaluationConfig) -> ItemScore {
        score(reference: reference, hypothesis: hypothesis, config: config,
              maxAlignmentCells: Alignment.maxCellsForFullPath)
    }

    static func score(reference: EvaluationReference, hypothesis: EvaluationHypothesis,
                      config: EvaluationConfig, maxAlignmentCells: Int) -> ItemScore {
        let policy = config.scoring
        let hypWords = TextNormalizer.words(hypothesis.text, policy: policy)
        let missingSpeech = MissingSpeech.detect(reference: reference, words: hypothesis.words,
                                                 settings: config.missingSpeech)
        let utterances = reference.utterances.map { tokenize($0, policy: policy) }
        let refWords = utterances.flatMap(\.words)

        func item(words: ErrorCounts, characters: ErrorCounts, utteranceScores: Measured<[UtteranceScore]>,
                  byLanguageClass: [StratumScore], byOverlap: Measured<[StratumScore]>,
                  languageBreakdown: Measured<LanguageBreakdown>,
                  deletionBursts: Measured<[DeletionBurst]>) -> ItemScore {
            ItemScore(itemId: reference.itemId, rawReference: reference.sourceText ?? reference.rawText, rawHypothesis: hypothesis.text,
                      normalizedHypothesis: hypWords, words: words, characters: characters,
                      wer: words.rate, cer: characters.rate, utterances: utteranceScores,
                      byLanguageClass: byLanguageClass, byOverlap: byOverlap,
                      languageBreakdown: languageBreakdown, deletionBursts: deletionBursts,
                      missingSpeech: missingSpeech)
        }

        // Nothing to project onto: every hypothesis word is an insertion.
        if reference.utterances.isEmpty {
            let chars = hypWords.joined(separator: " ").count
            return item(words: ErrorCounts(insertions: hypWords.count),
                        characters: ErrorCounts(insertions: chars),
                        utteranceScores: .available([]), byLanguageClass: [],
                        byOverlap: .unavailable(reason: noOverlapReason),
                        languageBreakdown: .unavailable(reason: noLanguageReason),
                        deletionBursts: .available([]))
        }

        // Interned ids: the alignment compares integers, not strings.
        var interner = Interner<String>()
        let refIds = refWords.map { interner.id($0) }
        let hypIds = hypWords.map { interner.id($0) }

        guard let path = Alignment.path(reference: refIds, hypothesis: hypIds, maxCells: maxAlignmentCells) else {
            let reason = "the item is too long for a word alignment (\(refIds.count) x \(hypIds.count) cells)"
            // CER is per utterance and needs the word alignment to know which
            // hypothesis words belong to which utterance. Aligning the whole
            // item character by character instead would be a different metric
            // and, at this length, billions of cells. So no CER: the counts stay
            // zero and the rate says why, and the corpus CER then reports the
            // item as missing rather than pooling zeros.
            var scored = item(words: Alignment.counts(reference: refIds, hypothesis: hypIds),
                              characters: .zero,
                              utteranceScores: .unavailable(reason: reason), byLanguageClass: [],
                              byOverlap: .unavailable(reason: reason),
                              languageBreakdown: .unavailable(reason: reason),
                              deletionBursts: .unavailable(reason: reason))
            scored.cer = .unavailable(reason: reason)
            return scored
        }

        // Which utterance each reference word came from.
        var utteranceOfWord: [Int] = []
        utteranceOfWord.reserveCapacity(refWords.count)
        for (u, t) in utterances.enumerated() {
            utteranceOfWord.append(contentsOf: repeatElement(u, count: t.words.count))
        }

        // Projection.
        var stepsOf = [[AlignmentStep]](repeating: [], count: utterances.count)
        var leading: [AlignmentStep] = []
        var lastUtterance: Int?
        for step in path {
            if let r = step.referenceIndex {
                let u = utteranceOfWord[r]
                if !leading.isEmpty {
                    stepsOf[u].append(contentsOf: leading)
                    leading.removeAll()
                }
                stepsOf[u].append(step)
                lastUtterance = u
            } else if let u = lastUtterance {
                stepsOf[u].append(step)
            } else {
                leading.append(step)
            }
        }
        if !leading.isEmpty { stepsOf[0].append(contentsOf: leading) }

        let overlap = overlapFlags(reference)
        var charInterner = Interner<Character>()
        var scores: [UtteranceScore] = []
        scores.reserveCapacity(utterances.count)
        for (u, utterance) in reference.utterances.enumerated() {
            let steps = stepsOf[u]
            let assigned = steps.compactMap { $0.hypothesisIndex.map { hypWords[$0] } }
            let wordCounts = Alignment.counts(of: steps)
            let refChars = utterances[u].words.joined(separator: " ").map { charInterner.id($0) }
            let hypChars = assigned.joined(separator: " ").map { charInterner.id($0) }
            let charCounts = Alignment.counts(reference: refChars, hypothesis: hypChars)
            scores.append(UtteranceScore(
                id: utterance.id, languageClass: utterances[u].languageClass, speaker: utterance.speaker,
                overlap: overlap.flags[u], startMs: utterance.startMs, endMs: utterance.endMs,
                rawReference: utterance.text, normalizedReference: utterances[u].words,
                assignedHypothesis: assigned, words: wordCounts, characters: charCounts,
                wer: wordCounts.rate, cer: charCounts.rate))
        }

        let byLanguageClass = LanguageClass.allCases.compactMap { cls -> StratumScore? in
            let members = scores.filter { $0.languageClass == cls }
            return members.isEmpty ? nil : stratum(cls.rawValue, members)
        }
        let byOverlap: Measured<[StratumScore]> = overlap.available
            ? .available([stratum("overlap", scores.filter { $0.overlap == true }),
                          stratum("no-overlap", scores.filter { $0.overlap == false })]
                         + (scores.contains { $0.overlap == nil }
                            ? [stratum("unknown", scores.filter { $0.overlap == nil })] : []))
            : .unavailable(reason: noOverlapReason)

        return item(words: Alignment.counts(of: path),
                    characters: scores.reduce(ErrorCounts()) { $0 + $1.characters },
                    utteranceScores: .available(scores), byLanguageClass: byLanguageClass,
                    byOverlap: byOverlap,
                    languageBreakdown: languageBreakdown(path: path, utterances: utterances),
                    deletionBursts: .available(deletionBursts(path: path, refWords: refWords,
                                                              utteranceOfWord: utteranceOfWord,
                                                              reference: reference,
                                                              minWords: config.deletionBurstMinWords)))
    }

    static let noOverlapReason = "the reference has no overlap annotation and no timed speaker turns"
    static let noLanguageReason = "the reference has no language annotation"

    // MARK: Tokenizing utterances

    struct TokenizedUtterance {
        var words: [String]
        /// Per word "tl", "en" or "other"; nil entries have no word-level language.
        var languages: [String?]
        /// The words carry span languages, so code-switch points are defined.
        var spanAttributed: Bool
        var hasSpans: Bool
        /// A single-language `language` tag gave every word its language.
        var tagAttributed: Bool
        var languageClass: LanguageClass
    }

    /// "tl", "en" or "other" for a language code.
    static func languageKey(_ code: String) -> String {
        switch code.trimmingCharacters(in: .whitespaces).lowercased() {
        case "tl", "fil", "tagalog": return "tl"
        case "en", "english": return "en"
        default: return "other"
        }
    }

    static func languageClass(tag: String?) -> LanguageClass {
        guard let tag else { return .unannotated }
        switch tag.trimmingCharacters(in: .whitespaces).lowercased() {
        case "": return .unannotated
        case "tl", "fil", "tagalog": return .tagalog
        case "en", "english": return .english
        case "mixed", "taglish", "code-switched": return .codeSwitched
        default: return .other
        }
    }

    static func tokenize(_ u: ReferenceUtterance, policy: ScoringPolicy) -> TokenizedUtterance {
        let whole = TextNormalizer.words(u.text, policy: policy)
        if let spans = u.languageSpans, !spans.isEmpty {
            let perSpan = spans.map { (TextNormalizer.words($0.text, policy: policy), languageKey($0.language)) }
            // The class counts the languages of spans that hold words, so a
            // space or a comma tagged "en" does not make a line code-switched.
            let worded = perSpan.filter { !$0.0.isEmpty }
            let keys = Set((worded.isEmpty ? perSpan : worded).map(\.1))
            let cls: LanguageClass = keys.contains("tl") && keys.contains("en") ? .codeSwitched
                : keys == ["tl"] ? .tagalog : keys == ["en"] ? .english : .other
            let spanWords = perSpan.flatMap(\.0)
            if spanWords == whole {
                let languages = perSpan.flatMap { words, key in words.map { _ in Optional(key) } }
                return TokenizedUtterance(words: whole, languages: languages, spanAttributed: true,
                                          hasSpans: true, tagAttributed: false, languageClass: cls)
            }
            return TokenizedUtterance(words: whole, languages: whole.map { _ in nil }, spanAttributed: false,
                                      hasSpans: true, tagAttributed: false, languageClass: cls)
        }
        let cls = languageClass(tag: u.language)
        let key: String? = switch cls {
        case .tagalog: "tl"
        case .english: "en"
        case .other: "other"
        case .codeSwitched, .unannotated: nil
        }
        return TokenizedUtterance(words: whole, languages: whole.map { _ in key }, spanAttributed: false,
                                  hasSpans: false, tagAttributed: key != nil, languageClass: cls)
    }

    // MARK: Overlap

    struct OverlapFlags {
        var available: Bool
        var flags: [Bool?]
    }

    static func overlapFlags(_ reference: EvaluationReference) -> OverlapFlags {
        let us = reference.utterances
        let turns = us.indices.filter { us[$0].hasTimes && us[$0].speaker != nil }
        let available = us.contains { $0.overlap != nil } || turns.count >= 2

        // Sorted by start, a turn can only intersect later turns that start
        // before it ends, which keeps a long meeting far from n^2.
        let sorted = turns.sorted { (us[$0].startMs!, $0) < (us[$1].startMs!, $1) }
        var derived = [Bool](repeating: false, count: us.count)
        for (k, a) in sorted.enumerated() {
            var next = k + 1
            while next < sorted.count, us[sorted[next]].startMs! < us[a].endMs! {
                let b = sorted[next]
                if us[b].speaker != us[a].speaker {
                    derived[a] = true
                    derived[b] = true
                }
                next += 1
            }
        }

        let flags: [Bool?] = us.indices.map { i in
            if let annotated = us[i].overlap { return annotated }
            if derived[i] { return true }
            if available, us[i].hasTimes, us[i].speaker != nil { return false }
            return nil
        }
        return OverlapFlags(available: available, flags: flags)
    }

    // MARK: Strata, languages, bursts

    static func stratum(_ name: String, _ members: [UtteranceScore]) -> StratumScore {
        let words = members.reduce(ErrorCounts()) { $0 + $1.words }
        let chars = members.reduce(ErrorCounts()) { $0 + $1.characters }
        return StratumScore(stratum: name, utterances: members.count, words: words, characters: chars,
                            wer: words.rate, cer: chars.rate)
    }

    private struct Tally {
        var hits = 0, substitutions = 0, deletions = 0
        mutating func add(_ op: EditOperation) {
            switch op {
            case .match: hits += 1
            case .substitution: substitutions += 1
            case .deletion: deletions += 1
            case .insertion: break
            }
        }
        var counts: LanguageErrorCounts {
            LanguageErrorCounts(hits: hits, substitutions: substitutions, deletions: deletions)
        }
    }

    static func languageBreakdown(path: [AlignmentStep],
                                  utterances: [TokenizedUtterance]) -> Measured<LanguageBreakdown> {
        guard utterances.contains(where: { $0.hasSpans || $0.tagAttributed }) else {
            return .unavailable(reason: noLanguageReason)
        }
        let languages = utterances.flatMap(\.languages)
        // nil: not span-attributed; true: the word's language differs from the previous word's.
        var switchPoint: [Bool?] = []
        switchPoint.reserveCapacity(languages.count)
        for t in utterances {
            for k in t.words.indices {
                switchPoint.append(t.spanAttributed ? (k > 0 && t.languages[k] != t.languages[k - 1]) : nil)
            }
        }

        var byLanguage: [String: Tally] = [:]
        var switches = Tally(), others = Tally()
        var insertions = 0, unattributed = 0
        for step in path {
            guard let r = step.referenceIndex else { insertions += 1; continue }
            if let key = languages[r] {
                byLanguage[key, default: Tally()].add(step.operation)
            } else {
                unattributed += 1
            }
            switch switchPoint[r] {
            case true?: switches.add(step.operation)
            case false?: others.add(step.operation)
            case nil: break
            }
        }

        let hasSpans = utterances.contains { $0.hasSpans }
        let noSpans = "the reference has no word-level language spans"
        return .available(LanguageBreakdown(
            byLanguage: byLanguage.mapValues(\.counts),
            codeSwitchPoints: hasSpans ? .available(switches.counts) : .unavailable(reason: noSpans),
            nonSwitchPoints: hasSpans ? .available(others.counts) : .unavailable(reason: noSpans),
            insertionsUnattributed: insertions,
            unattributedReferenceWords: unattributed))
    }

    static func deletionBursts(path: [AlignmentStep], refWords: [String], utteranceOfWord: [Int],
                               reference: EvaluationReference, minWords: Int) -> [DeletionBurst] {
        var bursts: [DeletionBurst] = []
        var run: [Int] = []
        func close() {
            defer { run.removeAll() }
            guard let first = run.first, let last = run.last, run.count >= minWords else { return }
            let a = reference.utterances[utteranceOfWord[first]]
            let b = reference.utterances[utteranceOfWord[last]]
            bursts.append(DeletionBurst(firstUtteranceId: a.id, lastUtteranceId: b.id,
                                        referenceStartIndex: first, length: run.count,
                                        words: run.map { refWords[$0] },
                                        startMs: a.hasTimes ? a.startMs : nil,
                                        endMs: b.hasTimes ? b.endMs : nil))
        }
        for step in path {
            if step.operation == .deletion, let r = step.referenceIndex {
                run.append(r)
            } else {
                close()
            }
        }
        close()
        return bursts
    }
}

/// Dense integer ids for hashable values, in order of first appearance.
struct Interner<T: Hashable> {
    private var ids: [T: Int] = [:]

    mutating func id(_ value: T) -> Int {
        if let id = ids[value] { return id }
        let id = ids.count
        ids[value] = id
        return id
    }
}
