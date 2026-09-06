import Foundation
import Observation
import TranscriberCore
import TranscriberEngine

/// How much of the app is on show.
///
/// Simple is the default. It has one button to record, one place to drop a
/// file, the transcript and the notes. Advanced adds the model tiers, the
/// audio controls, the benchmark, the decode statistics and the revision menu.
/// Both modes use the same store and the same pipeline; the switch changes
/// what the window shows and nothing else.
enum InterfaceMode: String, CaseIterable, Identifiable {
    case simple, advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .simple:
            return "Record, drop a file, read the transcript, write notes. "
                 + "The app selects the model and the audio settings."
        case .advanced:
            return "Adds the model tiers, the audio controls, the benchmark, "
                 + "the decode statistics and the transcript revisions."
        }
    }
}

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
        static let captureSource = "recording.captureSource"
        /// Nil means "follow the system default input", which is a different
        /// thing from "the device that is default today".
        static let microphoneUID = "recording.microphoneUID"
        static let benchmark = "benchmark.lastReport"
        static let inspectorShown = "ui.inspectorShown"
        static let clockTimestamps = "ui.clockTimestamps"
        static let hasSeenWelcome = "ui.hasSeenWelcome"
        static let interfaceMode = "ui.interfaceMode"
        static let menuBarItem = "ui.menuBarItem"
        static let notesStyle = "notes.style"
        static let autoDraftNotes = "notes.auto"
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
        // Off unless asked for. The whole-file pass after the recording is the
        // better transcript, and a meeting with no model running keeps the
        // Mac cool and quiet at the table. Nothing loads at launch either.
        liveTranscription = defaults.object(forKey: Key.liveTranscription) as? Bool ?? false
        keepWorkingCopy = defaults.object(forKey: Key.keepWorkingCopy) as? Bool ?? false
        overrides = defaults.dictionary(forKey: Key.overrides) as? [String: String] ?? [:]
        roomMode = defaults.object(forKey: Key.roomMode) as? Bool ?? false
        captureSource = CaptureSource(rawValue: defaults.string(forKey: Key.captureSource) ?? "")
            ?? .default
        microphoneUID = defaults.string(forKey: Key.microphoneUID)
        gainDb = InputGain.clampDb(
            defaults.object(forKey: Key.inputGainDb) as? Float ?? InputGain.defaultDb
        )
        inspectorShown = defaults.dictionary(forKey: Key.inspectorShown) as? [String: Bool] ?? [:]
        clockTimestamps = defaults.object(forKey: Key.clockTimestamps) as? Bool ?? false
        hasSeenWelcome = defaults.object(forKey: Key.hasSeenWelcome) as? Bool ?? false
        interfaceMode = InterfaceMode(rawValue: defaults.string(forKey: Key.interfaceMode) ?? "")
            ?? .simple
        menuBarItem = defaults.object(forKey: Key.menuBarItem) as? Bool ?? true
        notesStyle = NotesStyle(rawValue: defaults.string(forKey: Key.notesStyle) ?? "") ?? .english
        autoDraftNotes = defaults.object(forKey: Key.autoDraftNotes) as? Bool ?? false
    }

    // MARK: - Interface

    /// Simple or Advanced. Refer to `InterfaceMode`.
    var interfaceMode: InterfaceMode {
        didSet { defaults.set(interfaceMode.rawValue, forKey: Key.interfaceMode) }
    }

    var isAdvanced: Bool {
        get { interfaceMode == .advanced }
        set { interfaceMode = newValue ? .advanced : .simple }
    }

    /// The Notero item in the menu bar, with the global shortcuts. Change it
    /// through `AppState.setMenuBarItem`, which also registers the shortcuts.
    var menuBarItem: Bool { didSet { defaults.set(menuBarItem, forKey: Key.menuBarItem) } }

    /// Show transcript times as time of day ("9:47:12 PM") rather than offsets.
    var clockTimestamps: Bool { didSet { defaults.set(clockTimestamps, forKey: Key.clockTimestamps) } }

    /// The language the notes model writes in. English by default: the one
    /// hand-written set of notes in the library is English with Taglish
    /// quotes, and that is what the drafts are measured against.
    var notesStyle: NotesStyle { didSet { defaults.set(notesStyle.rawValue, forKey: Key.notesStyle) } }

    /// Draft the notes as soon as a transcription finishes, with no button.
    ///
    /// Off unless asked for, as live text is: it is a minute or two of the
    /// chip after every recording. It never runs during a recording -- refer
    /// to `AutoDraft`.
    var autoDraftNotes: Bool { didSet { defaults.set(autoDraftNotes, forKey: Key.autoDraftNotes) } }

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

    /// Which lanes a recording captures.
    var captureSource: CaptureSource {
        didSet { defaults.set(captureSource.rawValue, forKey: Key.captureSource) }
    }

    /// The chosen microphone by UID, or nil to follow the system default.
    var microphoneUID: String? {
        didSet { defaults.set(microphoneUID, forKey: Key.microphoneUID) }
    }

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

    /// What the decoder is told before each window: the names and terms the
    /// user typed, and nothing else. The Taglish style primer in
    /// `TranscriptionPrompt` is measured through the CLI only: on the live
    /// path it made the model repeat the primer instead of the room
    /// (docs/FINDINGS.md, finding 12), so the app never sends it.
    var promptOrNil: String? {
        TranscriptionPrompt.compose(language: language, usePrimer: false, vocabulary: prompt)
    }

    var sessionConfig: SessionConfig {
        SessionConfig(language: language, prompt: promptOrNil, useNeuralVAD: neuralVAD)
    }

    /// Everything the live session reads from Settings, in one value. The one
    /// place the six fields meet; the session takes it whole.
    var liveConfiguration: LiveConfiguration {
        LiveConfiguration(session: sessionConfig, decodeLive: liveTranscription,
                          captureSource: captureSource, microphoneUID: microphoneUID,
                          inputGainDb: inputGainDb, isRoomMode: roomMode)
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
