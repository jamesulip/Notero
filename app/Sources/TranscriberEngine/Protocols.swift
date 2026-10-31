import Foundation
import TranscriberCore

// The seam. Everything above this file talks to these three protocols and
// never to WhisperKit or FluidAudio directly, so replacing a backend is a new
// conformance plus one line in `EngineHost` -- not a rewrite of the UI.

// MARK: - Speech recognition

public struct ASRRequest: Sendable {
    /// 16 kHz mono, -1...1.
    public var samples: [Float]
    /// BCP-47-ish code, or `"auto"`. Forced Tagalog is the default everywhere
    /// upstream; auto-detect is offered but flagged, because on Taglish the
    /// decoder resolves elsewhere and starts translating.
    public var language: String
    public var prompt: String?
    public var wordTimestamps: Bool
    /// 0 for the first try, incremented when a window came back empty.
    ///
    /// Backends turn this into whatever nudge they have -- for Whisper, a
    /// warmer sampling temperature and more fallbacks. A window that decoded to
    /// nothing is not silence: VAD already said there was speech in it.
    public var decodeAttempt: Int
    public var sampling: Sampling

    /// How much of the backend's own temperature fallback a request may use.
    ///
    /// Whisper's fallback re-samples a window whose greedy decode failed a
    /// confidence gate, and the sampling is random: the same file decodes
    /// differently on each run (FINDINGS 15). The live path wants that ladder
    /// as it is. The offline pass can do better, because it can try again on
    /// different audio, so it takes the ladder apart.
    public enum Sampling: Sendable, Equatable {
        /// The backend's whole ladder: greedy first, then warmer retries.
        case standard
        /// Greedy only. A window whose greedy decode fails a gate comes back
        /// empty or flagged in `ASROutput.quality`, and is not re-sampled.
        case greedyOnly
        /// The ladder without its greedy first step, for a caller that has
        /// just run that step itself.
        case resampleOnly
    }

    public init(samples: [Float], language: String = LanguageCatalogue.defaultLanguage,
                prompt: String? = nil, wordTimestamps: Bool = true,
                decodeAttempt: Int = 0, sampling: Sampling = .standard) {
        self.samples = samples
        self.language = language
        self.prompt = prompt
        self.wordTimestamps = wordTimestamps
        self.decodeAttempt = decodeAttempt
        self.sampling = sampling
    }
}

/// How far a backend trusts one decode, for callers that can retry.
///
/// Mirrors the backend's own gates. Whisper returns the *last* attempt of its
/// ladder even when that attempt also failed them, so a window can come back
/// with text that the model itself had flagged as a repetition loop.
public struct DecodeQuality: Sendable, Equatable {
    /// Lowest mean token log-probability over the decoded segments.
    public var avgLogProb: Double
    /// Highest compression ratio over the decoded segments.
    public var compressionRatio: Double
    /// The text compresses like a loop ("Thank you. Thank you. ..."). The
    /// backend's repetition gate failed.
    public var isRepetitive: Bool
    /// The log-probability gate failed: the model was not confident.
    public var isLowConfidence: Bool

    public init(avgLogProb: Double, compressionRatio: Double,
                isRepetitive: Bool, isLowConfidence: Bool) {
        self.avgLogProb = avgLogProb
        self.compressionRatio = compressionRatio
        self.isRepetitive = isRepetitive
        self.isLowConfidence = isLowConfidence
    }

    /// Passed every gate the backend applies.
    public var passedGates: Bool { !isRepetitive && !isLowConfidence }
}

public struct ASROutput: Sendable {
    public var tokens: [Token]
    public var audioMs: Int
    public var inferMs: Int
    public var detectedLanguage: String?
    /// Mean token log-probability mapped to 0...1, when the backend reports one.
    public var confidence: Double?
    /// The backend's own verdict on the decode. Nil when it has none, which
    /// callers read as "passed".
    public var quality: DecodeQuality?

    public init(tokens: [Token], audioMs: Int, inferMs: Int,
                detectedLanguage: String? = nil, confidence: Double? = nil,
                quality: DecodeQuality? = nil) {
        self.tokens = tokens
        self.audioMs = audioMs
        self.inferMs = inferMs
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
        self.quality = quality
    }

    /// Real-time factor for this call. Below 1.0 means faster than the audio.
    public var rtf: Double { audioMs > 0 ? Double(inferMs) / Double(audioMs) : 0 }
}

/// Progress messages are plain strings on purpose: they go straight to a label,
/// and every backend phrases its stages differently.
public typealias ProgressReport = @Sendable (String, Double?) -> Void

public protocol SpeechRecognizing: Sendable {
    var loadedModel: String? { get async }

    func load(model: String, progress: ProgressReport?) async throws
    func unload() async
    func transcribe(_ request: ASRRequest) async throws -> ASROutput
}

// MARK: - Voice activity

public struct SpeechRegion: Equatable, Sendable {
    public var startMs: Int
    public var endMs: Int

    public init(startMs: Int, endMs: Int) {
        self.startMs = startMs
        self.endMs = endMs
    }

    public var durationMs: Int { max(0, endMs - startMs) }
}

/// What the live path needs per hop: is anyone talking, and has the utterance ended.
public struct VoiceActivityReading: Equatable, Sendable {
    public var isSpeech: Bool
    public var probability: Float
    public var trailingSilenceMs: Int
    public var speechMs: Int

    public init(isSpeech: Bool, probability: Float, trailingSilenceMs: Int, speechMs: Int) {
        self.isSpeech = isSpeech
        self.probability = probability
        self.trailingSilenceMs = trailingSilenceMs
        self.speechMs = speechMs
    }
}

public protocol VoiceActivityDetecting: Sendable {
    func prepare(progress: ProgressReport?) async throws
    /// Streaming. Samples arrive in capture-sized chunks; state is kept inside.
    func push(_ samples: [Float]) async throws -> VoiceActivityReading
    /// Clears the per-utterance speech tally after a boundary flush.
    func clearSpeechCounter() async
    func reset() async
    /// Offline. Used by the import path to skip silence before decoding.
    func regions(in samples: [Float]) async throws -> [SpeechRegion]
}

// MARK: - Diarization

public protocol SpeakerDiarizing: Sendable {
    var isAvailable: Bool { get async }
    func prepare(progress: ProgressReport?) async throws
    /// Whole-recording diarization. Returns spans on the session timeline.
    ///
    /// Takes a `PCMSource` rather than `[Float]` so the caller can hand over a
    /// memory-mapped file: two hours of 16 kHz audio is 460 MB as an array, and
    /// on a 16 GB machine already holding a 1.6 GB model that is the difference
    /// between running and swapping.
    ///
    /// `speechRegions` lets the backend skip long stretches VAD has already
    /// proved silent. Nil means no VAD information is available and the whole
    /// source must be processed. `mode` chooses whether the expensive per-turn
    /// embedding pass runs after the first speaker pass.
    ///
    /// `expectedSpeakers` is how many people the user says were in the room.
    /// A target for the clustering, never a cap; nil means no opinion.
    func diarize(_ source: any PCMSource,
                 speechRegions: [SpeechRegion]?,
                 mode: DiarizationMode,
                 expectedSpeakers: Int?,
                 progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan]
    func unload() async
}

// MARK: - Errors

public enum EngineError: LocalizedError, Sendable {
    case modelNotLoaded
    case backendUnavailable(String)
    case audioUnreadable(String)
    /// Audio could not be written to disk: the disk is full, or nearly.
    case cannotSaveAudio(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The model is not loaded yet."
        case .backendUnavailable(let why):
            return why
        case .audioUnreadable(let why):
            return "Could not read that audio: \(why)"
        case .cannotSaveAudio(let why):
            return "Could not save the audio: \(why)"
        }
    }
}
