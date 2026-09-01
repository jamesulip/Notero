import Foundation

/// Knobs for the live path. Defaults are the measured ones, not guesses.
public struct SessionConfig: Sendable, Equatable, Codable {
    /// Trailing audio re-decoded every hop.
    public var contextMs: Int
    /// How often a decode is attempted.
    public var hopMs: Int
    /// Trailing silence that ends an utterance and flushes the tail.
    public var silenceBoundaryMs: Int
    /// Passes that must agree before a token is committed.
    public var agreement: Int
    public var language: String
    /// Vocabulary hint. Names and jargon the model would otherwise mangle.
    public var prompt: String?
    /// Whether to run the neural VAD instead of the energy fallback.
    public var useNeuralVAD: Bool

    public init(
        contextMs: Int = 15_000,
        // A 15 s window costs ~0.9 s to decode, so a 1.0 s hop drops two thirds
        // of hops and consecutive passes stop being consecutive -- which is
        // exactly what LocalAgreement needs. 1.5 s landed live accuracy within
        // ~1.6 points of the offline ceiling; 1.0 s was 14 points off, and
        // 2.0 s was worse again because the buffer outruns agreement and starts
        // forcing commits instead of earning them.
        hopMs: Int = 1_500,
        silenceBoundaryMs: Int = 700,
        agreement: Int = 2,
        language: String = LanguageCatalogue.defaultLanguage,
        prompt: String? = nil,
        useNeuralVAD: Bool = true
    ) {
        self.contextMs = contextMs
        self.hopMs = hopMs
        self.silenceBoundaryMs = silenceBoundaryMs
        self.agreement = agreement
        self.language = language
        self.prompt = prompt
        self.useNeuralVAD = useNeuralVAD
    }
}

/// Counters for the live path. Surfaced in the benchmark panel, because every
/// one of them was a bug that was invisible until it was counted.
public struct SessionStats: Sendable, Equatable {
    public init() {}

    public var hops = 0
    /// Hops skipped because VAD heard nothing. Whisper hallucinates on silence.
    public var skippedSilent = 0
    /// Hops discarded because the previous decode was still running.
    public var droppedHops = 0
    /// Decodes that returned nothing despite audio being present.
    public var emptyResults = 0
    /// Decodes that threw. Counted separately from `emptyResults` because a
    /// thrown error is a broken backend, not a tripped threshold -- and a
    /// session whose every hop throws would otherwise end looking like a
    /// session where nobody spoke.
    public var failedHops = 0
    /// The most recent decode error, for surfacing when `failedHops` is high.
    public var lastError: String?
    public var boundaries = 0
    /// Commits made without agreement because the window was about to slide.
    public var forcedCommits = 0
    public var totalAudioMs = 0
    public var totalInferMs = 0
    public var peakMemoryMB = 0

    public var meanRtf: Double {
        totalAudioMs > 0 ? Double(totalInferMs) / Double(totalAudioMs) : 0
    }

    /// Share of hops that produced nothing usable.
    public var lossRate: Double {
        let attempted = hops + droppedHops + failedHops
        guard attempted > 0 else { return 0 }
        return Double(droppedHops + emptyResults + failedHops) / Double(attempted)
    }
}
