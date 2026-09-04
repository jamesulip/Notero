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
        static let diarizationMode = "transcription.diarizationMode"
        /// Legacy Boolean, read once when upgrading from builds before the
        /// Off/Fast/Accurate choice existed.
        static let diarize = "transcription.diarize"
        static let neuralVAD = "transcription.neuralVAD"
        static let liveTranscription = "recording.live"
        static let keepWorkingCopy = "storage.keepWorkingCopy"
        static let inputGainDb = "recording.inputGainDb"
        static let roomMode = "recording.roomMode"
        static let benchmark = "benchmark.lastReport"
        static let inspectorShown = "ui.inspectorShown"
        static let clockTimestamps = "ui.clockTimestamps"
        static let hasSeenWelcome = "ui.hasSeenWelcome"
        static let automaticUpdateChecks = "updates.automatic"
        static let lastUpdateCheck = "updates.lastCheck"
        static let skippedUpdate = "updates.skipped"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tier = ModelTier(rawValue: defaults.string(forKey: Key.tier) ?? "") ?? .balanced
        language = defaults.string(forKey: Key.language) ?? LanguageCatalogue.defaultLanguage
        prompt = defaults.string(forKey: Key.prompt) ?? ""
        if let raw = defaults.string(forKey: Key.diarizationMode),
           let mode = DiarizationMode(rawValue: raw) {
            diarizationMode = mode
        } else {
            let legacy = defaults.object(forKey: Key.diarize) as? Bool ?? true
            diarizationMode = legacy ? .accurate : .off
        }
        neuralVAD = defaults.object(forKey: Key.neuralVAD) as? Bool ?? true
        liveTranscription = defaults.object(forKey: Key.liveTranscription) as? Bool ?? true
        keepWorkingCopy = defaults.object(forKey: Key.keepWorkingCopy) as? Bool ?? false
        overrides = defaults.dictionary(forKey: Key.overrides) as? [String: String] ?? [:]
        roomMode = defaults.object(forKey: Key.roomMode) as? Bool ?? false
        gainDb = InputGain.clampDb(
            defaults.object(forKey: Key.inputGainDb) as? Float ?? InputGain.defaultDb
        )
        inspectorShown = defaults.dictionary(forKey: Key.inspectorShown) as? [String: Bool] ?? [:]
        clockTimestamps = defaults.object(forKey: Key.clockTimestamps) as? Bool ?? false
        hasSeenWelcome = defaults.object(forKey: Key.hasSeenWelcome) as? Bool ?? false
        // Off until asked for. Every other thing this app does happens on this
        // Mac; a background request to GitHub is the one exception, so it is
        // the user who turns it on. The Check Now button always works.
        automaticUpdateChecks = defaults.object(forKey: Key.automaticUpdateChecks) as? Bool ?? false
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        skippedUpdate = defaults.string(forKey: Key.skippedUpdate)
    }

    // MARK: - Interface

    /// Show transcript times as time of day ("9:47:12 PM") rather than offsets.
    var clockTimestamps: Bool { didSet { defaults.set(clockTimestamps, forKey: Key.clockTimestamps) } }

    /// The first-run card has been dismissed.
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) } }

    /// Whether the meeting workspace is open, remembered per recording kind:
    /// meetings want it, plain recordings usually do not, and the choice
    /// used to reset every time a row was selected.
    private(set) var inspectorShown: [String: Bool] {
        didSet { defaults.set(inspectorShown, forKey: Key.inspectorShown) }
    }

    func inspectorShown(for kind: RecordingKind) -> Bool {
        inspectorShown[kind.rawValue] ?? (kind == .meeting)
    }

    func setInspectorShown(_ shown: Bool, for kind: RecordingKind) {
        inspectorShown[kind.rawValue] = shown
    }

    // MARK: - Updates

    /// Ask GitHub once a day whether there is a new release. See `Updater`.
    var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks) }
    }

    /// When the last check finished, successfully or not. Nil until the first.
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) }
    }

    /// A version the user answered "Skip" to. Not offered again; a newer one
    /// still is, because this holds one version and not a flag.
    var skippedUpdate: String? {
        didSet { defaults.set(skippedUpdate, forKey: Key.skippedUpdate) }
    }

    // MARK: - Transcription

    var tier: ModelTier { didSet { defaults.set(tier.rawValue, forKey: Key.tier) } }
    var language: String { didSet { defaults.set(language, forKey: Key.language) } }
    var prompt: String { didSet { defaults.set(prompt, forKey: Key.prompt) } }
    var diarizationMode: DiarizationMode {
        didSet { defaults.set(diarizationMode.rawValue, forKey: Key.diarizationMode) }
    }
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

    /// Per-tier model id override. Read-only in the app: the benchmark
    /// recommends a tier but does not persist one, so this is empty unless an
    /// earlier build wrote it. `modelId(for:)` falls back to the tier default.
    private(set) var overrides: [String: String] {
        didSet { defaults.set(overrides, forKey: Key.overrides) }
    }

    func modelId(for tier: ModelTier) -> String {
        overrides[tier.rawValue] ?? tier.defaultModelId
    }

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
