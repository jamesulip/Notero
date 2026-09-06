import AVFoundation
import Foundation
import Observation
import TranscriberCore

/// What a finished live session hands back for persisting.
public struct LiveSessionResult: Sendable {
    public var recordingId: UUID
    public var segments: [Segment]
    public var durationMs: Int
    public var archiveFileName: String?
    public var archiveSampleRate: Int
    public var cacheURL: URL
    public var waveform: [Float]
    public var stats: SessionStats
    public var modelId: String
    public var language: String
    /// One per channel of the archive, in channel order.
    public var lanes: [CaptureLane]
    /// What changed under the recording, in order: a replaced microphone, a
    /// moved default input, a capture that could not be restarted.
    public var notices: [CaptureNotice]
}

/// The live path: capture -> working copy -> `LiveDecoder` -> commit -> UI.
///
/// The design contract this exists to keep is that committed text never
/// changes. Provisional text at the tail may be rewritten on the next pass;
/// once a word has been agreed by two consecutive windows it is frozen, and
/// everything below -- segment ids, note back-links, bookmarks -- can depend on
/// that.
///
/// This class owns the microphone, the working copy, the meter and the
/// observable state. Everything between a chunk of audio and a committed token
/// -- the ring buffer, the VAD, the hop schedule, LocalAgreement and
/// finalization -- lives in `LiveDecoder`, where it can be tested without
/// either a microphone or a model.
@MainActor
@Observable
public final class LiveSession {

    public enum State: Equatable, Sendable {
        case idle
        /// What is happening and, when it can be measured, how far along:
        /// a download has a fraction, a model load does not.
        case preparing(String, Double?)
        case ready
        case recording
        case finishing
        case failed(String)

        public var isRecording: Bool { self == .recording }

        /// True whenever a session is underway in any form. The guard that
        /// stops a second "New Recording" has to use this, not `isRecording`:
        /// the model load takes seconds (minutes cold), and during all of it
        /// the state is `.preparing` -- a second start slipping through then
        /// leaves a phantom failed recording behind.
        public var isBusy: Bool {
            switch self {
            case .preparing, .recording, .finishing: return true
            case .idle, .ready, .failed: return false
            }
        }
        public var label: String {
            switch self {
            case .idle: return "Idle"
            case .preparing(let what, _): return what
            case .ready: return "Ready"
            case .recording: return "Recording"
            case .finishing: return "Finishing"
            case .failed(let why): return why
            }
        }

        /// 0...1 while something measurable is under way, else nil.
        public var fraction: Double? {
            if case .preparing(_, let fraction) = self { return fraction }
            return nil
        }
    }

    // Observable state
    public private(set) var state: State = .idle
    public private(set) var segments: [Segment] = []
    public private(set) var partial = ""
    public private(set) var elapsedMs = 0
    public private(set) var level: Float = 0
    /// Per-lane levels, so a two-lane recording can show which side is
    /// talking. Empty for a one-lane session, where `level` says it all.
    public private(set) var laneLevels: [CaptureLane: Float] = [:]
    public private(set) var meter: [Float] = []
    /// Device changes during this recording, oldest first. The recording
    /// screen shows the latest one; Stop keeps them all with the recording.
    public private(set) var notices: [CaptureNotice] = []
    public private(set) var stats = SessionStats()
    public private(set) var vadBackend = "energy"
    public private(set) var recordingId: UUID?

    public var config = SessionConfig()
    public var isMuted = false { didSet { capture?.isMuted = isMuted } }

    /// Paused: the clock, the file and the live text all stop, and resume
    /// continues on the same timeline with no gap. Refer to
    /// `AudioCapture.isPaused`. Cleared at `start` and at `stop`, so a
    /// recording never begins paused because the last one ended that way.
    public var isPaused = false {
        didSet {
            capture?.isPaused = isPaused
            if isPaused {
                // The meter would otherwise hold the last level for the
                // length of the break.
                level = 0
                laneLevels = [:]
            }
        }
    }

    /// Which lanes to record. Read at `start`; changing it mid-session does
    /// nothing, because the archive's channel count is fixed when the file is
    /// created.
    public var captureSource: CaptureSource = .default

    /// Which microphone, by UID, or nil to follow the system default.
    public var microphoneUID: String?

    /// Whether to decode while recording. Off, the session only captures --
    /// archive and working copy -- and the whole-file pass runs at stop. That
    /// pass is the better transcript anyway, and a two-hour meeting with no
    /// model running keeps the machine cool and the fan quiet at the table.
    public var decodeLive = true

    /// Called with each batch of newly committed segments, in order, as soon
    /// as they are committed -- during the recording, not at Stop. This is how
    /// committed text reaches disk while the meeting is still going; the
    /// segments are also appended to `segments` for the UI.
    public var onCommitted: (([Segment]) -> Void)?

    /// Microphone boost in decibels, live-adjustable while recording.
    ///
    /// Computed over a private store rather than a stored property with a
    /// `didSet` that clamps in place: this class is `@Observable`, so the macro
    /// rewrites stored properties into computed ones, and assigning to the
    /// property inside its own `didSet` re-enters the setter and recurses until
    /// the stack overflows.
    private var gainDb: Float = InputGain.defaultDb

    public var inputGainDb: Float {
        get { gainDb }
        set {
            gainDb = InputGain.clampDb(newValue)
            capture?.gainDb = gainDb
        }
    }

    /// High-pass the audio the model is given. Live-adjustable, and it only
    /// affects the transcription copy -- the archive keeps the full band.
    public var isRoomMode = false { didSet { capture?.isRoomMode = isRoomMode } }

    private let engines: EngineHost
    private let supportDirectory: URL

    private var capture: AudioCapture?
    private var cache: WavWriter?
    private var decoder: LiveDecoder?
    /// One FIFO consumer replaces one unstructured main-actor task per audio
    /// callback. Besides reducing scheduling churn, `stop()` can now drain it
    /// explicitly before it closes the cache and finalizes the decoder.
    private var audioSink: AsyncStream<CapturedAudio>.Continuation?
    private var ingestTask: Task<Void, Never>?

    /// The lanes this session is recording, fixed at `start`.
    private var lanes: [CaptureLane] = [CaptureLane.room]

    private var archiveFileName: String?
    private var modelId = ModelCatalogue.defaultModel
    private var ingestedBytes = 0
    private var nextIndex = 0
    private var meterCountdown = 0
    private var meterPeak: Float = 0

    /// Milliseconds of audio per meter bar. One bar per 100 ms; faster and the
    /// view redraws more often than anyone can see, and the array churns for
    /// nothing.
    private static let meterIntervalMs = 100

    public init(engines: EngineHost, supportDirectory: URL) {
        self.engines = engines
        self.supportDirectory = supportDirectory
    }

    // MARK: - Preparation

    /// Loads the model and the VAD ahead of the first recording, so hitting
    /// record does not sit on a 20-second model load.
    public func prepare(model: String) async {
        guard state == .idle || state == .ready else { return }
        modelId = model
        // Nothing to load for a capture-only session; the offline job loads
        // the model when it runs.
        guard decodeLive else { state = .ready; return }
        state = .preparing("Loading model…", nil)
        do {
            try await engines.prepareForLive(model: model) { [weak self] message, fraction in
                Task { @MainActor in
                    guard let self, case .preparing = self.state else { return }
                    self.state = .preparing(message, fraction)
                }
            }
            vadBackend = await engines.vadBackendName
            state = .ready
        } catch {
            state = .failed("Could not load the model: \(error.localizedDescription)")
        }
    }

    // MARK: - Session

    public func start(recordingId id: UUID, archiveFileName: String?,
                      archiveURL: URL?) async throws {
        guard !state.isRecording else { return }
        // `.ready` from a capture-only prepare has no model behind it, so
        // when live decoding is wanted the check is on the model, not the state.
        let loaded = await engines.loadedModel
        if !(state == .ready && (!decodeLive || loaded == modelId)) {
            await prepare(model: modelId)
        }
        guard case .ready = state else {
            throw EngineError.backendUnavailable(state.label)
        }
        if captureSource.usesMicrophone, await !requestMicrophone() {
            state = .failed("Microphone access denied. Enable it in System Settings › "
                          + "Privacy & Security › Microphone.")
            throw EngineError.backendUnavailable("microphone access denied")
        }
        if captureSource.usesSystemAudio {
            // Asked before the capture starts rather than left to fail during
            // it. A refused system tap does not error and does not record
            // silence -- Core Audio reports success and never delivers a
            // sample -- so a session started without this permission looks
            // exactly like a call where nobody spoke.
            let access = await SystemAudioAccess.request()
            guard access.mightWork else {
                state = .failed(SystemAudioTap.TapError.notPermitted.localizedDescription)
                throw EngineError.backendUnavailable("system audio access denied")
            }
        }

        recordingId = id
        self.archiveFileName = archiveFileName
        isPaused = false
        segments = []
        partial = ""
        lanes = captureSource.lanes
        laneLevels = [:]
        notices = []
        stats = SessionStats()
        elapsedMs = 0
        meter = []
        nextIndex = 0
        ingestedBytes = 0
        meterCountdown = 0
        meterPeak = 0
        await engines.resetVAD()

        if decodeLive {
            let decoder = LiveDecoder(config: config,
                                      recognizer: await engines.recognizer,
                                      vad: await engines.voiceActivity)
            decoder.onCommitted = { [weak self] tokens in self?.emit(tokens) }
            decoder.onPartial = { [weak self] text in self?.partial = text }
            self.decoder = decoder
        } else {
            decoder = nil
        }

        let cacheURL = AudioCache.url(for: id, under: supportDirectory)
        // Thrown straight through: `WavWriter.CannotWrite` names the path and
        // the reason, and replacing it with a generic string here is what made
        // this undiagnosable in the first place.
        let cache = try WavWriter(url: cacheURL)
        self.cache = cache

        guard let capture = AudioCapture(source: captureSource,
                                         microphoneUID: microphoneUID) else {
            // Close the writer opened above, or its file keeps a zero-length
            // RIFF header until something else happens to overwrite it.
            cache.close()
            self.cache = nil
            throw EngineError.backendUnavailable("Could not open the audio engine.")
        }
        capture.isMuted = isMuted
        capture.gainDb = inputGainDb
        capture.isRoomMode = isRoomMode
        capture.onNotice = { [weak self] notice in
            Task { @MainActor in self?.notices.append(notice) }
        }
        self.capture = capture

        var continuation: AsyncStream<CapturedAudio>.Continuation!
        let audio = AsyncStream<CapturedAudio>(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        audioSink = continuation
        ingestTask = Task { [weak self] in
            for await chunk in audio {
                guard let self else { return }
                self.ingest(chunk)
            }
        }

        do {
            try capture.start(archiveURL: archiveURL) { [continuation] chunk in
                continuation.yield(chunk)
            }
        } catch {
            continuation.finish()
            ingestTask?.cancel()
            ingestTask = nil
            audioSink = nil
            self.capture = nil
            cache.close()
            self.cache = nil
            state = .failed(error.localizedDescription)
            throw error
        }
        state = .recording
    }

    /// Stops capture, lets the decoder finish what it was doing, commits the
    /// provisional tail and returns what to persist.
    public func stop() async -> LiveSessionResult? {
        guard let capture, let id = recordingId else { return nil }
        state = .finishing

        let archive = capture.stop()
        self.capture = nil

        // `removeTap` can race the final callback. Close the stream only after
        // capture stops, then wait until every yielded chunk has reached the
        // cache and decoder before finalizing either one.
        audioSink?.finish()
        audioSink = nil
        await ingestTask?.value
        ingestTask = nil

        // Nothing more is coming. The decoder drains its in-flight pass, hears
        // the tail once more, and commits what is left -- through the same
        // callbacks as every other commit, so nothing lands after the result
        // below is built.
        if let decoder {
            await decoder.finish()
            stats = decoder.stats
        }
        partial = ""
        decoder = nil

        cache?.close()
        let cacheURL = AudioCache.url(for: id, under: supportDirectory)
        cache = nil

        let ingestedMs = Audio.bytesToMs(ingestedBytes)
        let durationMs = archive.sampleRate > 0
            ? Int(Double(archive.frames) / Double(archive.sampleRate) * 1000)
            : ingestedMs
        elapsedMs = max(durationMs, ingestedMs)

        // A long recording contains millions of samples. The 600-bucket result
        // is small, but producing it still scans the whole file and must not
        // freeze the window while the session is finishing.
        let waveform = await Task.detached(priority: .utility) {
            (try? MappedPCM(contentsOf: cacheURL))
                .map { WaveformAnalyzer.envelope(of: $0) } ?? []
        }.value

        let result = LiveSessionResult(
            recordingId: id,
            segments: segments,
            durationMs: elapsedMs,
            archiveFileName: archiveFileName,
            archiveSampleRate: archive.sampleRate,
            cacheURL: cacheURL,
            waveform: waveform,
            stats: stats,
            modelId: modelId,
            language: config.language,
            lanes: lanes,
            notices: notices
        )
        recordingId = nil
        isPaused = false
        state = .ready
        return result
    }

    /// The moment to bookmark. Counted from the audio received rather than a
    /// wall clock, so it stays on the same timeline as the transcript.
    public var currentMs: Int { Audio.bytesToMs(ingestedBytes) }

    // MARK: - Live path

    private func ingest(_ chunk: CapturedAudio) {
        // Stop switches to `.finishing` before it closes the capture stream;
        // chunks already yielded by the audio tap are still part of the file.
        guard state.isRecording || state == .finishing else { return }
        level = chunk.peak
        if lanes.count > 1 { laneLevels = chunk.peaks }
        cache?.writeAsync(chunk.pcm)
        ingestedBytes += chunk.pcm.count
        elapsedMs = Audio.bytesToMs(ingestedBytes)

        // The loudest chunk of the interval, not whichever chunk happened to
        // land on it. The tap delivers ~85 ms at a time against a 100 ms bar,
        // so taking the arriving peak dropped one chunk in two -- and with it
        // any clip that fell in the discarded half.
        meterPeak = max(meterPeak, chunk.peak)
        meterCountdown += Audio.bytesToMs(chunk.pcm.count)
        if meterCountdown >= Self.meterIntervalMs {
            // Carrying the remainder rather than zeroing it. Zeroing threw away
            // 85 of every 185 ms, which stretched the bars to one per 170 ms
            // and put the meter's history on a different clock from the audio.
            meterCountdown %= Self.meterIntervalMs
            meter = WaveformAnalyzer.appending(meterPeak, to: meter)
            meterPeak = 0
        }

        guard let decoder else { return }
        decoder.ingest(chunk.pcm)
        stats = decoder.stats
    }

    private func emit(_ tokens: [Token]) {
        let text = tokens.joinedText
        guard !text.isEmpty, let first = tokens.first, let last = tokens.last else { return }
        var reference: AudioReference?
        if let id = recordingId, let name = archiveFileName {
            reference = AudioReference(recordingId: id, fileName: name, offsetMs: first.startMs)
        }
        let segment = Segment(
            index: nextIndex,
            startMs: first.startMs,
            endMs: max(last.endMs, first.startMs + 1),
            text: text,
            confidence: tokens.meanConfidence,
            audio: reference
        )
        segments.append(segment)
        nextIndex += 1
        if let decoder { stats = decoder.stats }
        onCommitted?([segment])
    }

    private func requestMicrophone() async -> Bool {
        await MicrophoneAccess.request() == .granted
    }
}
