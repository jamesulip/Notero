import Foundation
import Observation
import TranscriberCore

/// User preferences. Small enough to live in `UserDefaults`, and deliberately
/// not in the store: none of it is per-recording, and none of it is worth a
/// migration when it changes.
@Observable
final class AppSettings {

    enum Key {
        static let tier = "model.tier"
        static let overrides = "model.overrides"
        static let language = "transcription.language"
        static let prompt = "transcription.prompt"
        static let diarize = "transcription.diarize"
        static let neuralVAD = "transcription.neuralVAD"
        static let liveTranscription = "recording.live"
        static let keepWorkingCopy = "storage.keepWorkingCopy"
        static let inputGainDb = "recording.inputGainDb"
        static let roomMode = "recording.roomMode"
        static let benchmark = "benchmark.lastReport"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tier = ModelTier(rawValue: defaults.string(forKey: Key.tier) ?? "") ?? .balanced
        language = defaults.string(forKey: Key.language) ?? LanguageCatalogue.defaultLanguage
        prompt = defaults.string(forKey: Key.prompt) ?? ""
        diarize = defaults.object(forKey: Key.diarize) as? Bool ?? true
        neuralVAD = defaults.object(forKey: Key.neuralVAD) as? Bool ?? true
        liveTranscription = defaults.object(forKey: Key.liveTranscription) as? Bool ?? true
        keepWorkingCopy = defaults.object(forKey: Key.keepWorkingCopy) as? Bool ?? false
        overrides = defaults.dictionary(forKey: Key.overrides) as? [String: String] ?? [:]
        roomMode = defaults.object(forKey: Key.roomMode) as? Bool ?? false
        gainDb = InputGain.clampDb(
            defaults.object(forKey: Key.inputGainDb) as? Float ?? InputGain.defaultDb
        )
    }

    var tier: ModelTier { didSet { defaults.set(tier.rawValue, forKey: Key.tier) } }
    var language: String { didSet { defaults.set(language, forKey: Key.language) } }
    var prompt: String { didSet { defaults.set(prompt, forKey: Key.prompt) } }
    var diarize: Bool { didSet { defaults.set(diarize, forKey: Key.diarize) } }
    var neuralVAD: Bool { didSet { defaults.set(neuralVAD, forKey: Key.neuralVAD) } }
    var liveTranscription: Bool { didSet { defaults.set(liveTranscription, forKey: Key.liveTranscription) } }
    var keepWorkingCopy: Bool { didSet { defaults.set(keepWorkingCopy, forKey: Key.keepWorkingCopy) } }

    /// High-pass the audio before transcription. For a microphone picking up
    /// a room rather than a person; wrong for close-mic dictation.
    var roomMode: Bool { didSet { defaults.set(roomMode, forKey: Key.roomMode) } }

    /// Microphone boost in decibels. Clamped on the way in as well as in the
    /// slider, because a stale or hand-edited default must not be able to put
    /// 60 dB on the input.
    ///
    /// Computed over a private store, not a `didSet` that clamps in place: this
    /// class is `@Observable`, and re-assigning the property from inside its own
    /// `didSet` re-enters the macro-generated setter and recurses forever.
    private var gainDb: Float

    var inputGainDb: Float {
        get { gainDb }
        set {
            gainDb = InputGain.clampDb(newValue)
            defaults.set(gainDb, forKey: Key.inputGainDb)
        }
    }

    /// Per-tier model id, once the benchmark has found something better than
    /// the default mapping on this machine.
    private(set) var overrides: [String: String] {
        didSet { defaults.set(overrides, forKey: Key.overrides) }
    }

    func modelId(for tier: ModelTier) -> String {
        overrides[tier.rawValue] ?? tier.defaultModelId
    }

    func setModel(_ id: String, for tier: ModelTier) {
        overrides[tier.rawValue] = id
    }

    func resetOverrides() { overrides = [:] }

    /// The model used for the live path.
    ///
    /// `accurate` is refused here rather than in the picker: the tier is a
    /// perfectly good choice for re-transcribing a finished recording, it just
    /// cannot decode a 15 s window inside a 1.5 s hop, and silently falling
    /// back is better than a live session that commits nothing.
    var liveModelId: String {
        modelId(for: tier.suitableForLive ? tier : .balanced)
    }

    var offlineModelId: String { modelId(for: tier) }

    var promptOrNil: String? {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }

    var sessionConfig: SessionConfig {
        SessionConfig(language: language, prompt: promptOrNil, useNeuralVAD: neuralVAD)
    }

    // MARK: - Benchmark

    func saveBenchmark(_ report: BenchmarkReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: Key.benchmark)
    }

    func loadBenchmark() -> BenchmarkReport? {
        guard let data = defaults.data(forKey: Key.benchmark) else { return nil }
        return try? JSONDecoder().decode(BenchmarkReport.self, from: data)
    }
}
