import Foundation

// A corpus, one system run over it, and the report that comes out.
//
// `Evaluator` scores one recording. This file pools recordings into a corpus
// figure, attaches the bootstrap intervals and the record of what produced
// the hypotheses, and compares two systems over the same corpus. It reads no
// files: the CLI loads the manifest, references and hypotheses and hands them
// in, so everything here is testable from strings.

// MARK: - Manifest

/// The list of recordings a corpus is made of.
///
/// Two forms are read. The legacy form is the array that `eval/manifest.json`
/// and the app's corrections export already write:
/// `[{"id", "audio", "ref", "category"}]`. The versioned form wraps it:
/// `{"schemaVersion": 1, "corpusId": "...", "items": [...]}`. Paths are
/// relative to the manifest. The legacy form has no corpus id, so one is made
/// from a hash of the manifest bytes: the same file is the same corpus.
public struct CorpusManifest: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public struct Item: Codable, Sendable, Equatable {
        public var id: String
        public var audio: String?
        /// The reference file: `.json` (an ``EvaluationReference``) or any other
        /// extension, read as plain text with one utterance per line.
        public var ref: String?
        /// "tagalog", "english" or "mixed", as `eval/score.py` reads it.
        public var category: String?

        public init(id: String, audio: String? = nil, ref: String? = nil, category: String? = nil) {
            self.id = id
            self.audio = audio
            self.ref = ref
            self.category = category
        }
    }

    public var corpusId: String
    public var items: [Item]

    public init(corpusId: String, items: [Item]) {
        self.corpusId = corpusId
        self.items = items
    }

    private struct Versioned: Codable {
        var schemaVersion: Int
        var corpusId: String
        var items: [Item]
    }

    /// Parses either form. `corpusId` overrides the id in, or derived from, the file.
    public static func parse(_ data: Data, corpusId override: String? = nil) throws -> CorpusManifest {
        let manifest: CorpusManifest
        if let items = try? JSONDecoder().decode([Item].self, from: data) {
            let hash = CanonicalJSON.sha256Hex(data)
            manifest = CorpusManifest(corpusId: "manifest-sha256:\(hash.prefix(16))", items: items)
        } else {
            let versioned = try JSONDecoder().decode(Versioned.self, from: data)
            guard versioned.schemaVersion == currentSchemaVersion else {
                throw EvaluationError.unsupportedSchema(kind: "corpus manifest", found: versioned.schemaVersion,
                                                        supported: currentSchemaVersion)
            }
            manifest = CorpusManifest(corpusId: versioned.corpusId, items: versioned.items)
        }
        var seen = Set<String>()
        for item in manifest.items where !seen.insert(item.id).inserted {
            throw EvaluationError.invalidInput("item id \(item.id) appears twice in the manifest")
        }
        guard let override else { return manifest }
        return CorpusManifest(corpusId: override, items: manifest.items)
    }

    /// The utterance language a manifest category stands for, used for a
    /// plain-text reference whose lines carry no language of their own.
    public static func utteranceLanguage(forCategory category: String?) -> String? {
        switch category?.lowercased() {
        case "tagalog", "filipino", "tl", "fil": return "tl"
        case "english", "en": return "en"
        case "mixed", "taglish", "code-switched": return "mixed"
        default: return nil
        }
    }

    /// A plain-text reference, with the manifest category applied to every
    /// line as its utterance language. An annotation the manifest makes, not
    /// one the scorer guesses; with no category the lines stay unannotated.
    public static func plainTextReference(_ text: String, item: Item) -> EvaluationReference {
        var reference = EvaluationReference.plainText(text, itemId: item.id)
        if let language = utteranceLanguage(forCategory: item.category) {
            for index in reference.utterances.indices {
                reference.utterances[index].language = language
            }
        }
        return reference
    }
}

// MARK: - Provenance

/// The machine a run was made on.
public struct HardwareInfo: Codable, Sendable, Equatable {
    /// e.g. "Mac14,12 · 12 cores · macOS 26.6".
    public var machine: String
    public var memoryGB: Int

    public init(machine: String, memoryGB: Int) {
        self.machine = machine
        self.memoryGB = memoryGB
    }
}

/// How the hypotheses were decoded.
public struct InferenceSettings: Codable, Sendable, Equatable {
    /// "offline", "live", "live-realtime", or "external" for text from elsewhere.
    public var mode: String
    public var language: String
    public var prompt: String?
    /// Anything else that decides the output: hop, context, diarization mode…
    /// A dictionary so a new setting needs no schema change; encoded with sorted keys.
    public var settings: [String: String]

    public init(mode: String, language: String, prompt: String? = nil, settings: [String: String] = [:]) {
        self.mode = mode
        self.language = language
        self.prompt = prompt
        self.settings = settings
    }
}

/// What produced a set of hypotheses. Each field is explicitly unavailable
/// when the inputs did not say, never guessed.
public struct RunProvenance: Codable, Sendable, Equatable {
    /// A name for the system in the report, e.g. "balanced @ 8c47d2c".
    public var label: String
    public var modelId: Measured<String>
    /// The model's source revision: the Hugging Face commit of the downloaded
    /// files, when the local download cache records one.
    public var modelRevision: Measured<String>
    public var hardware: Measured<HardwareInfo>
    public var inference: Measured<InferenceSettings>
    /// The build that decoded, e.g. a git commit, when the caller supplies it.
    public var toolVersion: Measured<String>

    public init(label: String,
                modelId: Measured<String> = .unavailable(reason: "not recorded"),
                modelRevision: Measured<String> = .unavailable(reason: "not recorded"),
                hardware: Measured<HardwareInfo> = .unavailable(reason: "not recorded"),
                inference: Measured<InferenceSettings> = .unavailable(reason: "not recorded"),
                toolVersion: Measured<String> = .unavailable(reason: "not recorded")) {
        self.label = label
        self.modelId = modelId
        self.modelRevision = modelRevision
        self.hardware = hardware
        self.inference = inference
        self.toolVersion = toolVersion
    }
}

// MARK: - Performance, kept apart

/// Order statistics of a latency distribution.
public struct LatencyFigures: Codable, Sendable, Equatable {
    /// What the latency is measured against: "audio fed" or "wall".
    public var clock: String
    public var words: Int
    public var medianMs: Double
    public var p95Ms: Double
    public var maxMs: Int

    public init(clock: String, words: Int, medianMs: Double, p95Ms: Double, maxMs: Int) {
        self.clock = clock
        self.words = words
        self.medianMs = medianMs
        self.p95Ms = p95Ms
        self.maxMs = maxMs
    }
}

/// Four figures that are often confused, each under its own name, each
/// unavailable when the run did not measure it (docs/BENCHMARKS.md, "Which
/// number is which").
public struct PerformanceSummary: Codable, Sendable, Equatable {
    /// Offline decode wall time over audio length. Not available for a live
    /// replay, whose RTF is a different number.
    public var wholeFileRTF: MetricValue
    /// Live replay only: how far behind the audio a committed word trails.
    public var liveCommitLatency: Measured<LatencyFigures>
    /// The highest `phys_footprint` of the decoding process. One process's
    /// pages; **the model's Neural Engine memory is not in it.**
    public var processPeakFootprintMB: MetricValue
    /// Neural Engine memory the loaded model added to the process. The figure
    /// for a model's memory.
    public var modelResidencyMB: MetricValue
    /// The two terms of `wholeFileRTF`, so a corpus can pool them as total
    /// decode time over total audio rather than average the ratios.
    public var offlineDecodeMs: Int?
    public var audioMs: Int?

    public init(wholeFileRTF: MetricValue, liveCommitLatency: Measured<LatencyFigures>,
                processPeakFootprintMB: MetricValue, modelResidencyMB: MetricValue,
                offlineDecodeMs: Int? = nil, audioMs: Int? = nil) {
        self.wholeFileRTF = wholeFileRTF
        self.liveCommitLatency = liveCommitLatency
        self.processPeakFootprintMB = processPeakFootprintMB
        self.modelResidencyMB = modelResidencyMB
        self.offlineDecodeMs = offlineDecodeMs
        self.audioMs = audioMs
    }

    /// For text whose decode was not measured.
    public static func notMeasured(_ reason: String) -> PerformanceSummary {
        PerformanceSummary(wholeFileRTF: .unavailable(reason: reason),
                           liveCommitLatency: .unavailable(reason: reason),
                           processPeakFootprintMB: .unavailable(reason: reason),
                           modelResidencyMB: .unavailable(reason: reason))
    }
}

// MARK: - Inputs

/// One manifest item with what could be loaded for it. A nil reference or
/// hypothesis carries the reason it is missing.
public struct CorpusItemInput: Sendable {
    public var item: CorpusManifest.Item
    public var reference: Result<EvaluationReference, EvaluationInputMissing>
    public var hypothesis: Result<EvaluationHypothesis, EvaluationInputMissing>
    public var performance: PerformanceSummary

    public init(item: CorpusManifest.Item,
                reference: Result<EvaluationReference, EvaluationInputMissing>,
                hypothesis: Result<EvaluationHypothesis, EvaluationInputMissing>,
                performance: PerformanceSummary = .notMeasured("no run measurements were supplied")) {
        self.item = item
        self.reference = reference
        self.hypothesis = hypothesis
        self.performance = performance
    }
}

/// Why an input is not there, in words a report can print.
public struct EvaluationInputMissing: Error, Sendable, Equatable {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }
}

// MARK: - Results

public struct CorpusItemResult: Codable, Sendable, Equatable {
    public var itemId: String
    public var category: String?
    public var score: Measured<ItemScore>
    public var performance: PerformanceSummary
}

/// Missing-speech figures pooled over the items that could be checked.
public struct PooledMissingSpeech: Codable, Sendable, Equatable {
    public var itemsChecked: Int
    public var checkedRegions: Int
    public var checkedSpeechMs: Int
    public var uncoveredSpeechMs: Int
    public var missingRegions: Int
    public var missingSpeechMs: Int
    public var missingShare: MetricValue
}

public struct CorpusSummary: Codable, Sendable, Equatable {
    public var itemsInManifest: Int
    public var itemsScored: Int
    public var words: ErrorCounts
    public var wer: MetricValue
    public var werInterval: Measured<BootstrapEstimate>
    public var characters: ErrorCounts
    public var cer: MetricValue
    public var cerInterval: Measured<BootstrapEstimate>
    public var byLanguageClass: [StratumScore]
    /// Pooled over the items whose reference annotates overlap; `overlapItems` lists them.
    public var byOverlap: Measured<[StratumScore]>
    public var overlapItems: [String]
    /// Pooled over the items whose reference annotates language; `languageItems` lists them.
    public var languageBreakdown: Measured<LanguageBreakdown>
    public var languageItems: [String]
    public var deletionBursts: Measured<[DeletionBurst]>
    public var missingSpeech: Measured<PooledMissingSpeech>
    /// Offline whole-file RTF pooled as total decode time over total audio,
    /// only when every scored item measured it.
    public var wholeFileRTF: MetricValue
}

/// The result of scoring one system over one corpus.
public struct EvaluationReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var kind: String
    public var corpusId: String
    public var config: EvaluationConfig
    public var configFingerprint: String
    public var scoringPolicyFingerprint: String
    public var system: RunProvenance
    public var corpus: CorpusSummary
    public var items: [CorpusItemResult]
    public var warnings: [String]
}

/// Two systems over the same corpus, under the same configuration.
public struct ComparisonReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var kind: String
    public var corpusId: String
    public var config: EvaluationConfig
    public var configFingerprint: String
    public var baseline: RunProvenance
    public var candidate: RunProvenance
    public var baselineWER: MetricValue
    public var candidateWER: MetricValue
    public var wer: Measured<PairedComparison>
    public var cer: Measured<PairedComparison>
    /// One paired comparison per utterance language class present.
    public var werByLanguageClass: [String: Measured<PairedComparison>]
    public var warnings: [String]
}

// MARK: - Scoring a corpus

public enum CorpusEvaluation {

    /// Scores every item and pools the results. The same inputs give the same
    /// report, byte for byte: there is no clock and no randomness outside the
    /// seeded bootstrap.
    public static func evaluate(corpusId: String, inputs: [CorpusItemInput], system: RunProvenance,
                                config: EvaluationConfig) -> EvaluationReport {
        var warnings: [String] = []
        let items: [CorpusItemResult] = inputs.map { input in
            let score: Measured<ItemScore>
            switch (input.reference, input.hypothesis) {
            case let (.failure(missing), _):
                score = .unavailable(reason: "no reference: \(missing.reason)")
            case let (_, .failure(missing)):
                score = .unavailable(reason: "no hypothesis: \(missing.reason)")
            case let (.success(reference), .success(hypothesis)):
                score = .available(Evaluator.score(reference: reference, hypothesis: hypothesis, config: config))
            }
            return CorpusItemResult(itemId: input.item.id, category: input.item.category,
                                    score: score, performance: input.performance)
        }

        let unscored = items.filter { $0.score.value == nil }
        if !unscored.isEmpty {
            warnings.append("\(unscored.count) of \(items.count) items could not be scored and are not in "
                            + "the corpus figures: " + unscored.map(\.itemId).joined(separator: ", "))
        }
        let summary = summarize(items: items, config: config, warnings: &warnings)
        return EvaluationReport(
            schemaVersion: EvaluationReport.currentSchemaVersion,
            kind: "notero-asr-evaluation",
            corpusId: corpusId, config: config,
            configFingerprint: config.fingerprint,
            scoringPolicyFingerprint: config.scoring.fingerprint,
            system: system, corpus: summary, items: items, warnings: warnings)
    }

    static func summarize(items: [CorpusItemResult], config: EvaluationConfig,
                          warnings: inout [String]) -> CorpusSummary {
        let scored = items.compactMap(\.score.value)

        let words = scored.reduce(ErrorCounts.zero) { $0 + $1.words }
        let wer: MetricValue = scored.isEmpty
            ? .unavailable(reason: "no item could be scored")
            : words.rate

        // CER only when every scored item has one: pooling the rest would hide
        // the missing item inside the figure.
        let noCER = scored.filter { !$0.cer.isAvailable && $0.words.referenceLength > 0 }
        let characters = scored.reduce(ErrorCounts.zero) { $0 + $1.characters }
        let cer: MetricValue
        if scored.isEmpty {
            cer = .unavailable(reason: "no item could be scored")
        } else if !noCER.isEmpty {
            cer = .unavailable(reason: "no CER for " + noCER.map(\.itemId).joined(separator: ", "))
        } else {
            cer = characters.rate
        }

        // Strata pooled over items, from the utterances.
        let allUtterances = scored.compactMap(\.utterances.value).flatMap { $0 }
        let missingUtterances = scored.filter { $0.utterances.value == nil }
        var byClass: [StratumScore] = []
        if missingUtterances.isEmpty {
            for languageClass in LanguageClass.allCases {
                let members = allUtterances.filter { $0.languageClass == languageClass }
                if !members.isEmpty { byClass.append(stratum(languageClass.rawValue, members)) }
            }
        } else {
            warnings.append("no utterance-level results for " + missingUtterances.map(\.itemId).joined(separator: ", ")
                            + "; the corpus has no language-class strata, and the overlap strata leave them out")
        }

        // Breakdowns that need annotation pool the items that have it, and say
        // which: an annotated subset is still a measurement of that subset.
        let byOverlap = pooledOverlap(scored)
        let overlapItems = scored.filter { $0.byOverlap.value != nil }.map(\.itemId)
        let languageBreakdown = pooledLanguage(scored)
        let languageItems = scored.filter { $0.languageBreakdown.value != nil }.map(\.itemId)
        for (what, covered) in [("overlap", overlapItems), ("word-language", languageItems)]
            where !covered.isEmpty && covered.count < scored.count {
            warnings.append("the \(what) breakdown covers \(covered.count) of \(scored.count) scored items; "
                            + "the others have no \(what) annotation")
        }
        let bursts = pooled(scored.map(\.deletionBursts), what: "deletion bursts")
        let missingSpeech = pooledMissingSpeech(scored)

        let categories = Dictionary(uniqueKeysWithValues: items.map { ($0.itemId, $0.category) })
        let werInterval = interval(scored, categories: categories, config: config, characters: false,
                                   warnings: &warnings)
        let cerInterval: Measured<BootstrapEstimate> = cer.isAvailable
            ? interval(scored, categories: categories, config: config, characters: true, warnings: &warnings)
            : .unavailable(reason: "the corpus CER is unavailable")

        // Pooled as total decode time over total audio, and only when every
        // scored item measured both: a figure over some of the items would
        // read as the corpus's.
        let measured = items.filter { $0.score.value != nil }.map(\.performance)
        let wholeFileRTF: MetricValue
        if measured.isEmpty {
            wholeFileRTF = .unavailable(reason: "no item could be scored")
        } else if measured.contains(where: { $0.offlineDecodeMs == nil || $0.audioMs == nil }) {
            wholeFileRTF = .unavailable(reason: "an offline decode time was not measured for every scored item")
        } else {
            wholeFileRTF = .ratio(measured.reduce(0) { $0 + ($1.offlineDecodeMs ?? 0) },
                                  measured.reduce(0) { $0 + ($1.audioMs ?? 0) },
                                  unavailable: "the scored items have no audio")
        }

        return CorpusSummary(
            itemsInManifest: items.count, itemsScored: scored.count,
            words: words, wer: wer, werInterval: werInterval,
            characters: characters, cer: cer, cerInterval: cerInterval,
            byLanguageClass: byClass, byOverlap: byOverlap, overlapItems: overlapItems,
            languageBreakdown: languageBreakdown, languageItems: languageItems, deletionBursts: bursts,
            missingSpeech: missingSpeech, wholeFileRTF: wholeFileRTF)
    }

    // MARK: Bootstrap units

    /// The units the bootstrap resamples, or why there are none.
    ///
    /// `.utterance`: every utterance of every scored item, stratum = its
    /// language class. `.item`: one unit per scored item, stratum = the
    /// manifest category (or "unannotated").
    public static func bootstrapUnits(_ scored: [ItemScore], categories: [String: String?] = [:],
                                      unit: BootstrapSettings.Unit,
                                      characters: Bool) -> Measured<[BootstrapUnit]> {
        switch unit {
        case .item:
            return .available(scored.map { item in
                let category = categories[item.itemId].flatMap { $0 } ?? LanguageClass.unannotated.rawValue
                return BootstrapUnit(id: item.itemId, stratum: category,
                                     counts: characters ? item.characters : item.words)
            })
        case .utterance:
            var units: [BootstrapUnit] = []
            for item in scored {
                guard let utterances = item.utterances.value else {
                    return .unavailable(reason: "item \(item.itemId) has no utterance-level results "
                                        + "(\(item.utterances.unavailableReason ?? "unknown"))")
                }
                for u in utterances {
                    units.append(BootstrapUnit(id: "\(item.itemId)/\(u.id)", stratum: u.languageClass.rawValue,
                                               counts: characters ? u.characters : u.words))
                }
            }
            return .available(units)
        }
    }

    static func interval(_ scored: [ItemScore], categories: [String: String?], config: EvaluationConfig,
                         characters: Bool, warnings: inout [String]) -> Measured<BootstrapEstimate> {
        guard !scored.isEmpty else { return .unavailable(reason: "no item could be scored") }
        switch bootstrapUnits(scored, categories: categories, unit: config.bootstrap.unit, characters: characters) {
        case let .unavailable(reason):
            return .unavailable(reason: reason)
        case let .available(units):
            if !characters, units.count < 30 {
                warnings.append("the bootstrap resamples \(units.count) \(config.bootstrap.unit.rawValue)s; "
                                + "below about 30 the interval is rough and tends to be too narrow")
            }
            if !characters, config.bootstrap.unit == .utterance, scored.count < 5 {
                warnings.append("utterances from \(scored.count) recording(s) are resampled as if independent; "
                                + "utterances of one recording share speaker, room and microphone, so the "
                                + "interval understates the variation between recordings")
            }
            return .available(Bootstrap.estimate(units: units, settings: config.bootstrap))
        }
    }

    // MARK: Pooling

    static func stratum(_ name: String, _ members: [UtteranceScore]) -> StratumScore {
        let words = members.reduce(ErrorCounts.zero) { $0 + $1.words }
        let chars = members.reduce(ErrorCounts.zero) { $0 + $1.characters }
        return StratumScore(stratum: name, utterances: members.count, words: words, characters: chars,
                            wer: words.rate, cer: chars.rate)
    }

    static func pooledOverlap(_ scored: [ItemScore]) -> Measured<[StratumScore]> {
        guard !scored.isEmpty else { return .unavailable(reason: "no item could be scored") }
        let available = scored.compactMap(\.byOverlap.value)
        guard !available.isEmpty else {
            return .unavailable(reason: scored.first?.byOverlap.unavailableReason ?? "no overlap annotation")
        }
        var merged: [String: (Int, ErrorCounts, ErrorCounts)] = [:]
        var order: [String] = []
        for strata in available {
            for s in strata {
                if merged[s.stratum] == nil { order.append(s.stratum) }
                let prior = merged[s.stratum] ?? (0, .zero, .zero)
                merged[s.stratum] = (prior.0 + s.utterances, prior.1 + s.words, prior.2 + s.characters)
            }
        }
        return .available(order.map { name in
            let (n, w, c) = merged[name]!
            return StratumScore(stratum: name, utterances: n, words: w, characters: c, wer: w.rate, cer: c.rate)
        })
    }

    static func pooledLanguage(_ scored: [ItemScore]) -> Measured<LanguageBreakdown> {
        guard !scored.isEmpty else { return .unavailable(reason: "no item could be scored") }
        let available = scored.compactMap(\.languageBreakdown.value)
        guard !available.isEmpty else {
            return .unavailable(reason: scored.first?.languageBreakdown.unavailableReason
                                ?? "the reference has no language annotation")
        }
        var byLanguage: [String: LanguageErrorCounts] = [:]
        for breakdown in available {
            for (language, counts) in breakdown.byLanguage {
                byLanguage[language] = add(byLanguage[language], counts)
            }
        }
        func pool(_ parts: [Measured<LanguageErrorCounts>], what: String) -> Measured<LanguageErrorCounts> {
            let values = parts.compactMap(\.value)
            guard !values.isEmpty else {
                return .unavailable(reason: "no item has word-level language spans for \(what)")
            }
            return .available(values.dropFirst().reduce(values[0]) { add($0, $1) })
        }
        return .available(LanguageBreakdown(
            byLanguage: byLanguage,
            codeSwitchPoints: pool(available.map(\.codeSwitchPoints), what: "code-switch points"),
            nonSwitchPoints: pool(available.map(\.nonSwitchPoints), what: "non-switch points"),
            insertionsUnattributed: available.reduce(0) { $0 + $1.insertionsUnattributed },
            unattributedReferenceWords: available.reduce(0) { $0 + $1.unattributedReferenceWords }))
    }

    static func add(_ a: LanguageErrorCounts?, _ b: LanguageErrorCounts) -> LanguageErrorCounts {
        let n = (a?.referenceWords ?? 0) + b.referenceWords
        let s = (a?.substitutions ?? 0) + b.substitutions
        let d = (a?.deletions ?? 0) + b.deletions
        return LanguageErrorCounts(referenceWords: n, hits: (a?.hits ?? 0) + b.hits, substitutions: s,
                                   deletions: d,
                                   rate: .ratio(s + d, n, unavailable: "no reference words in this language"))
    }

    static func pooled<T>(_ parts: [Measured<[T]>], what: String) -> Measured<[T]> {
        guard !parts.isEmpty else { return .unavailable(reason: "no item could be scored") }
        var all: [T] = []
        for part in parts {
            guard let value = part.value else {
                return .unavailable(reason: "\(what) unavailable for an item: \(part.unavailableReason ?? "")")
            }
            all.append(contentsOf: value)
        }
        return .available(all)
    }

    static func pooledMissingSpeech(_ scored: [ItemScore]) -> Measured<PooledMissingSpeech> {
        guard !scored.isEmpty else { return .unavailable(reason: "no item could be scored") }
        let reports = scored.compactMap(\.missingSpeech.value)
        guard !reports.isEmpty else {
            return .unavailable(reason: scored.first?.missingSpeech.unavailableReason
                                ?? "no item has reference timestamps and hypothesis word timestamps")
        }
        let checked = reports.reduce(0) { $0 + $1.checkedSpeechMs }
        let missingMs = reports.reduce(0) { $0 + $1.missingRegions.reduce(0) { $0 + $1.endMs - $1.startMs } }
        return .available(PooledMissingSpeech(
            itemsChecked: reports.count,
            checkedRegions: reports.reduce(0) { $0 + $1.checkedRegions },
            checkedSpeechMs: checked,
            uncoveredSpeechMs: reports.reduce(0) { $0 + $1.uncoveredSpeechMs },
            missingRegions: reports.reduce(0) { $0 + $1.missingRegions.count },
            missingSpeechMs: missingMs,
            missingShare: .ratio(missingMs, checked, unavailable: "no reference speech region was long enough to check")))
    }

    // MARK: Comparing two systems

    /// A paired comparison of two reports over the same corpus.
    ///
    /// Throws `.incomparable` when the corpus, the configuration or the set
    /// of scored items differs: a difference between two numbers made on
    /// different material or under different rules is not a comparison.
    public static func compare(baseline: EvaluationReport, candidate: EvaluationReport) throws -> ComparisonReport {
        guard baseline.corpusId == candidate.corpusId else {
            throw EvaluationError.incomparable("corpus \(baseline.corpusId) against \(candidate.corpusId)")
        }
        guard baseline.configFingerprint == candidate.configFingerprint else {
            throw EvaluationError.incomparable("the two reports were scored under different configurations")
        }
        let baseIds = baseline.items.filter { $0.score.value != nil }.map(\.itemId)
        let candIds = candidate.items.filter { $0.score.value != nil }.map(\.itemId)
        guard baseIds == candIds else {
            throw EvaluationError.incomparable("the scored items differ: "
                                               + Set(baseIds).symmetricDifference(candIds).sorted().joined(separator: ", "))
        }
        let config = baseline.config
        var warnings: [String] = []
        let baseScored = baseline.items.compactMap(\.score.value)
        let candScored = candidate.items.compactMap(\.score.value)
        for (b, c) in zip(baseScored, candScored) where b.rawReference != c.rawReference {
            throw EvaluationError.incomparable("item \(b.itemId) has a different reference in the two reports")
        }
        let categories = Dictionary(uniqueKeysWithValues: baseline.items.map { ($0.itemId, $0.category) })

        func paired(characters: Bool, filter: ((BootstrapUnit) -> Bool)? = nil) throws -> Measured<PairedComparison> {
            let b = bootstrapUnits(baseScored, categories: categories, unit: config.bootstrap.unit, characters: characters)
            let c = bootstrapUnits(candScored, categories: categories, unit: config.bootstrap.unit, characters: characters)
            guard var bu = b.value, var cu = c.value else {
                return .unavailable(reason: b.unavailableReason ?? c.unavailableReason ?? "no units")
            }
            if let filter {
                bu = bu.filter(filter)
                cu = cu.filter(filter)
            }
            return .available(try Bootstrap.paired(baseline: bu, candidate: cu, settings: config.bootstrap))
        }

        let wer = try paired(characters: false)
        let cer: Measured<PairedComparison> = (baseline.corpus.cer.isAvailable && candidate.corpus.cer.isAvailable)
            ? try paired(characters: true)
            : .unavailable(reason: "a corpus CER is unavailable")

        var byClass: [String: Measured<PairedComparison>] = [:]
        if config.bootstrap.unit == .utterance {
            for stratum in baseline.corpus.byLanguageClass.map(\.stratum) {
                byClass[stratum] = try paired(characters: false) { $0.stratum == stratum }
            }
        }
        if let units = wer.value?.units, units < 30 {
            warnings.append("the comparison resamples \(units) units; below about 30 the interval is rough")
        }
        return ComparisonReport(
            schemaVersion: ComparisonReport.currentSchemaVersion,
            kind: "notero-asr-comparison",
            corpusId: baseline.corpusId, config: config, configFingerprint: baseline.configFingerprint,
            baseline: baseline.system, candidate: candidate.system,
            baselineWER: baseline.corpus.wer, candidateWER: candidate.corpus.wer,
            wer: wer, cer: cer, werByLanguageClass: byClass, warnings: warnings)
    }
}
