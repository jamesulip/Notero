import Foundation

/// Knobs for the live path. Defaults are the measured ones, not guesses.
public struct SessionConfig: Sendable, Equatable, Codable {
    /// Trailing audio re-decoded every hop: the active, uncommitted region.
    public var contextMs: Int
    /// How often a decode is attempted.
    public var hopMs: Int
    /// Trailing silence that ends an utterance and triggers a final decode.
    public var silenceBoundaryMs: Int
    /// Passes that must agree before a token is committed.
    public var agreement: Int
    public var language: String
    /// Vocabulary hint. Names and jargon the model would otherwise mangle.
    public var prompt: String?
    /// Whether to run the neural VAD instead of the energy fallback.
    public var useNeuralVAD: Bool
    /// Already-committed audio kept in front of the active region on every
    /// decode, so Whisper never starts cold at a commit boundary.
    ///
    /// Context only: nothing in it can be committed again. The ring keeps it
    /// (`RingBuffer.preRollMs`), and `LocalAgreement` drops whatever the model
    /// re-transcribes from it by timestamp before agreement is even considered.
    public var preRollMs: Int
    /// Shorten the hop while decodes are fast.
    ///
    /// A 15 s window costs ~0.9 s, which is why a fixed 1.0 s hop drops two
    /// thirds of its hops (FINDINGS §6). Right after a boundary the window is
    /// a second or two long and decodes in a fraction of that, so the hop can
    /// safely shrink there and grow back as the window fills. The hop never
    /// goes below `minHopMs` or above `hopMs`, and never below 1.5x the last
    /// decode time -- so this cannot raise the drop rate. Off by default until
    /// the replay harness says otherwise.
    public var adaptiveHop: Bool
    public var minHopMs: Int

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
        useNeuralVAD: Bool = true,
        preRollMs: Int = 1_500,
        adaptiveHop: Bool = false,
        minHopMs: Int = 1_000
    ) {
        self.contextMs = contextMs
        self.hopMs = hopMs
        self.silenceBoundaryMs = silenceBoundaryMs
        self.agreement = agreement
        self.language = language
        self.prompt = prompt
        self.useNeuralVAD = useNeuralVAD
        self.preRollMs = preRollMs
        self.adaptiveHop = adaptiveHop
        self.minHopMs = minHopMs
    }
}

/// Counters for the live path. The headline ones are surfaced in the recording
/// footer's Stats popover, because every one of them was a bug that was
/// invisible until it was counted.
public struct SessionStats: Sendable, Equatable, Codable {
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
    /// Utterance ends that committed something.
    public var boundaries = 0
    /// Commits made without agreement because the window was about to slide.
    public var forcedCommits = 0
    /// Final decodes run because VAD reported trailing silence. Fewer than
    /// `boundaries` is normal: a hop already in flight often covers the
    /// utterance end and is used instead of a second decode.
    public var finalizations = 0
    /// Finalizations where speech resumed before the decode returned, so the
    /// remainder stayed provisional instead of being committed unagreed.
    public var finalizationsAbandoned = 0
    /// Tokens committed without agreement at a confirmed utterance boundary --
    /// the tail the final decode produced but no earlier pass had seen.
    public var unagreedTailCommits = 0
    /// Boundaries where the final decode returned nothing (or threw) and the
    /// previous hypothesis was flushed instead. Whisper refuses some windows
    /// deterministically (FINDINGS §2); if this climbs on real audio the
    /// flush is committing hallucinations and should become a drop.
    public var finalFlushOnEmpty = 0
    /// Tokens the model re-transcribed from the pre-roll that timestamps alone
    /// did not catch: boundary words with drifted timing, dropped by text.
    public var duplicatesDropped = 0
    /// Words timestamped past the audio the model was given -- decoded out of
    /// the 30 s padding, usually the last phrase said again -- and words placed
    /// in the silence after an utterance the VAD had already closed. Neither
    /// was spoken; both used to be committed.
    public var hallucinationsDropped = 0
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
