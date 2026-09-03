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
}

/// The live path: capture -> ring buffer -> VAD -> ASR -> commit -> UI.
///
/// The design contract this exists to keep is that committed text never
/// changes. Provisional text at the tail may be rewritten on the next pass;
/// once a word has been agreed by two consecutive windows it is frozen, and
/// everything below -- segment ids, note back-links, bookmarks -- can depend on
/// that.
@MainActor
@Observable
public final class LiveSession {

    public enum State: Equatable, Sendable {
        case idle
        case preparing(String)
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
            case .preparing(let what): return what
            case .ready: return "Ready"
            case .recording: return "Recording"
            case .finishing: return "Finishing"
            case .failed(let why): return why
            }
        }
    }

    // Observable state
    public private(set) var state: State = .idle
    public private(set) var segments: [Segment] = []
    public private(set) var partial = ""
    public private(set) var elapsedMs = 0
    public private(set) var level: Float = 0
    public private(set) var meter: [Float] = []
    public private(set) var stats = SessionStats()
    public private(set) var vadBackend = "energy"
    public private(set) var recordingId: UUID?

    public var config = SessionConfig()
    public var isMuted = false { didSet { capture?.isMuted = isMuted } }

    /// Whether to decode while recording. Off, the session only captures --
    /// archive and working copy -- and the whole-file pass runs at stop. That
    /// pass is the better transcript anyway, and a two-hour meeting with no
    /// model running keeps the machine cool and the fan quiet at the table.
    public var decodeLive = true

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
    private var ring = RingBuffer()
    private var commit = LocalAgreement()

    private var archiveFileName: String?
    private var modelId = ModelCatalogue.defaultModel
    private var msSinceHop = 0
    private var hopInFlight = false
    private var vadInFlight = false
    private var vadPending: [Float] = []
    private var lastReading = VoiceActivityReading(isSpeech: false, probability: 0,
                                                   trailingSilenceMs: 0, speechMs: 0)
    private var nextIndex = 0
    private var meterCountdown = 0

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
        state = .preparing("Loading model…")
        do {
            try await engines.prepareForLive(model: model) { [weak self] message, _ in
                Task { @MainActor in
                    guard let self, case .preparing = self.state else { return }
                    self.state = .preparing(message)
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
        guard await requestMicrophone() else {
            state = .failed("Microphone access denied. Enable it in System Settings › "
                          + "Privacy & Security › Microphone.")
            throw EngineError.backendUnavailable("microphone access denied")
        }

        recordingId = id
        self.archiveFileName = archiveFileName
        segments = []
        partial = ""
        stats = SessionStats()
        elapsedMs = 0
        meter = []
        nextIndex = 0
        msSinceHop = 0
        hopInFlight = false
        vadInFlight = false
        vadPending = []
        ring = RingBuffer(contextMs: config.contextMs)
        commit = LocalAgreement(agreement: config.agreement)
        await engines.resetVAD()

        let cacheURL = AudioCache.url(for: id, under: supportDirectory)
        // Thrown straight through: `WavWriter.CannotWrite` names the path and
        // the reason, and replacing it with a generic string here is what made
        // this undiagnosable in the first place.
        let cache = try WavWriter(url: cacheURL)
        self.cache = cache

        guard let capture = AudioCapture() else {
            // Close the writer opened above, or its file keeps a zero-length
            // RIFF header until something else happens to overwrite it.
            cache.close()
            self.cache = nil
            throw EngineError.backendUnavailable("Could not open the audio engine.")
        }
        capture.isMuted = isMuted
        capture.gainDb = inputGainDb
        capture.isRoomMode = isRoomMode
        self.capture = capture

        do {
            try capture.start(archiveURL: archiveURL) { [weak self] chunk in
                Task { @MainActor in self?.ingest(chunk) }
            }
        } catch {
            self.capture = nil
            cache.close()
            self.cache = nil
            state = .failed(error.localizedDescription)
            throw error
        }
        state = .recording
    }

    /// Stops capture, flushes the provisional tail and returns what to persist.
    public func stop() async -> LiveSessionResult? {
        guard let capture, let id = recordingId else { return nil }
        state = .finishing

        let archive = capture.stop()
        self.capture = nil

        // Nothing more is coming, so the provisional tail is as final as it gets.
        commit.ceilingMs = ring.totalMs
        emit(commit.flush())
        partial = ""

        cache?.close()
        let cacheURL = AudioCache.url(for: id, under: supportDirectory)
        cache = nil

        let durationMs = archive.sampleRate > 0
            ? Int(Double(archive.frames) / Double(archive.sampleRate) * 1000)
            : ring.totalMs
        elapsedMs = max(durationMs, ring.totalMs)

        let waveform = (try? MappedPCM(contentsOf: cacheURL))
            .map { WaveformAnalyzer.envelope(of: $0) } ?? []

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
            language: config.language
        )
        recordingId = nil
        state = .ready
        return result
    }

    /// The moment to bookmark. Reading it from the ring buffer rather than a
    /// wall clock keeps it on the same timeline as the transcript.
    public var currentMs: Int { ring.totalMs }

    // MARK: - Live path

    private func ingest(_ chunk: CapturedAudio) {
        guard state.isRecording else { return }
        level = chunk.peak
        ring.push(chunk.pcm)
        cache?.write(chunk.pcm)
        elapsedMs = ring.totalMs
        msSinceHop += Audio.bytesToMs(chunk.pcm.count)

        // One meter bar per ~100 ms, or the view redraws faster than anyone can
        // see and the array churns for nothing.
        meterCountdown += Audio.bytesToMs(chunk.pcm.count)
        if meterCountdown >= 100 {
            meterCountdown = 0
            meter = WaveformAnalyzer.appending(chunk.peak, to: meter)
        }

        guard decodeLive else { return }

        vadPending.append(contentsOf: PCM.floats(from: chunk.pcm))
        if !vadInFlight, vadPending.count >= 4096 {
            vadInFlight = true
            let batch = vadPending
            vadPending = []
            Task { await pumpVAD(batch) }
        }

        guard msSinceHop >= config.hopMs else { return }
        msSinceHop = 0

        // A stale partial is worse than a missing one: if the previous hop is
        // still decoding, drop this one rather than queueing behind it.
        guard !hopInFlight else {
            stats.droppedHops += 1
            return
        }
        if lastReading.trailingSilenceMs >= config.silenceBoundaryMs {
            boundary()
            return
        }
        hopInFlight = true
        Task { await runHop() }
    }

    private func pumpVAD(_ samples: [Float]) async {
        defer { vadInFlight = false }
        if let reading = try? await engines.pushVAD(samples) { lastReading = reading }
    }

    /// Trailing silence ends a segment: flush the tail, then stop decoding.
    private func boundary() {
        commit.ceilingMs = ring.totalMs
        let tail = commit.flush()
        if !tail.isEmpty {
            stats.boundaries += 1
            ring.trim(to: commit.committedEndMs)
            emit(tail)
            partial = ""
            Task { await engines.clearVADSpeechCounter() }
            return
        }
        // Nobody talking and nothing pending: skip inference entirely.
        stats.skippedSilent += 1
    }

    private func runHop() async {
        defer { hopInFlight = false }

        let (window, windowStartMs) = ring.window()
        guard !window.isEmpty else { return }
        commit.ceilingMs = ring.totalMs

        // The window has slid past the last commit, so audio at its head is
        // about to be discarded unagreed. Commit it now, or the next hypothesis
        // starts at a different word and prefixes stop aligning for good --
        // permanently, not until the next pause.
        if windowStartMs > commit.committedEndMs {
            let forced = commit.forceCommit(before: windowStartMs)
            if !forced.isEmpty {
                stats.forcedCommits += 1
                emit(forced)
            }
        }

        let output: ASROutput
        do {
            output = try await engines.transcribe(ASRRequest(
                samples: PCM.floats(from: window),
                language: config.language,
                prompt: config.prompt,
                wordTimestamps: true
            ))
        } catch {
            stats.failedHops += 1
            stats.lastError = error.localizedDescription
            return
        }

        stats.hops += 1
        stats.totalAudioMs += output.audioMs
        stats.totalInferMs += output.inferMs
        stats.peakMemoryMB = max(stats.peakMemoryMB, MemoryProbe.footprintMB())

        guard !output.tokens.isEmpty else {
            // Not silence: a decode threshold tripped. Worth counting, since it
            // is otherwise indistinguishable from nobody speaking.
            stats.emptyResults += 1
            return
        }

        // Window-relative timings become absolute, so segments, exports and
        // diarization all share one timeline.
        let absolute = output.tokens.map {
            Token(text: $0.text,
                  startMs: windowStartMs + $0.startMs,
                  endMs: windowStartMs + $0.endMs,
                  confidence: $0.confidence)
        }
        let newly = commit.insert(absolute)
        if !newly.isEmpty {
            ring.trim(to: commit.committedEndMs)
            emit(newly)
        }
        partial = commit.partial
    }

    private func emit(_ tokens: [Token]) {
        let text = tokens.joinedText
        guard !text.isEmpty, let first = tokens.first, let last = tokens.last else { return }
        var reference: AudioReference?
        if let id = recordingId, let name = archiveFileName {
            reference = AudioReference(recordingId: id, fileName: name, offsetMs: first.startMs)
        }
        segments.append(Segment(
            index: nextIndex,
            startMs: first.startMs,
            endMs: max(last.endMs, first.startMs + 1),
            text: text,
            confidence: tokens.meanConfidence,
            audio: reference
        ))
        nextIndex += 1
    }

    private func requestMicrophone() async -> Bool {
        await MicrophoneAccess.request() == .granted
    }
}
