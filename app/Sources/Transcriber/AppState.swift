import Foundation
import Observation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore
import UniformTypeIdentifiers

/// Where the detail pane is pointing.
enum Route: Hashable {
    case recording(UUID)
    case search
    case benchmark
}

/// The one object the views share.
///
/// It owns the engines and the queue, and it is the only place that knows both
/// the store and the pipeline. Views get SwiftData through the environment and
/// everything else through here.
@Observable
final class AppState {

    let container: ModelContainer
    let settings: AppSettings
    let engines: EngineHost
    let queue: TranscriptionQueue
    let live: LiveSession
    let player = AudioPlayer()
    private let writer: TranscriptWriter

    /// Sidebar selection. Nil is the empty state.
    var route: Route?
    var searchText = ""
    /// Set when a search result or a note back-link asks the transcript to
    /// scroll somewhere.
    var pendingScrollTarget: UUID?
    var alert: AppAlert?

    /// Sheet and panel triggers the menu bar drives.
    var isImporting = false
    var isExporting = false
    var focusSearch = false
    var exportFormat: ExportFormat = .txt

    /// The transcript row the user last clicked. What ⌃⌘D and friends act on.
    var selectedSegmentId: UUID?

    /// A recording that stopped almost as soon as it started. Set on stop so
    /// the window can ask whether to keep it: the library had five of these
    /// under half a minute, each one a click-and-delete nobody got round to.
    var shortTake: ShortTake?

    struct ShortTake: Identifiable {
        let id: UUID
        let durationMs: Int
        let words: Int
    }

    /// Below this a take is asked about rather than kept silently.
    static let shortTakeMs = 10_000

    /// Per-recording pipeline progress, keyed by recording id.
    private(set) var progress: [UUID: JobProgress] = [:]
    /// Per-recording notes about work that finished imperfectly.
    private(set) var warnings: [UUID: String] = [:]
    /// The recording the live session is working on, set the moment the user
    /// asks for one rather than when the first sample arrives. `live.recordingId`
    /// only exists once capture starts, which on a cold model is several
    /// seconds later -- and those are exactly the seconds the UI has to show
    /// something for.
    private(set) var activeRecordingId: UUID?

    private var pump: Task<Void, Never>?
    private var warmup: Task<Void, Never>?

    /// Jobs handed to the queue, kept until they finish: `.partial` events
    /// need the model and language the job was started with.
    private var queuedJobs: [UUID: TranscriptionJob] = [:]
    /// The revision each running job is appending to, from its first window.
    private var openTranscripts: [UUID: UUID] = [:]
    /// When the current stage of each job began and the last estimate made
    /// from it. The estimate is smoothed against this.
    private var stageClock: [UUID: StageClock] = [:]

    private struct StageClock {
        var status: TranscriptionStatus
        var since: Date
        var remaining: TimeInterval?
    }

    struct JobProgress: Equatable {
        var status: TranscriptionStatus
        var fraction: Double
        /// Seconds left in this stage, once enough of it has run to say.
        var remaining: TimeInterval?
        /// How far into the audio the decode has reached.
        var coveredMs: Int = 0
    }

    struct AppAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    init(container: ModelContainer, settings: AppSettings = AppSettings()) {
        self.container = container
        self.settings = settings
        let engines = EngineHost(modelsDirectory: Paths.models,
                                 preferNeuralVAD: settings.neuralVAD)
        self.engines = engines
        self.queue = TranscriptionQueue(engines: engines)
        self.live = LiveSession(engines: engines, supportDirectory: Paths.support)
        self.writer = TranscriptWriter(modelContainer: container)
        live.config = settings.sessionConfig
        live.inputGainDb = settings.inputGainDb
        live.isRoomMode = settings.roomMode
        // Before any view reads the store: the live session and the queue did
        // not survive the last quit, so anything they still claim to be working
        // on is stranded.
        try? RecordingStore.recoverInterrupted(in: container.mainContext)
        startPump()
    }

    /// Persists the gain and pushes it to a session already running, so moving
    /// the slider mid-recording is audible immediately rather than at the next
    /// recording.
    func setInputGain(_ db: Float) {
        settings.inputGainDb = db
        live.inputGainDb = settings.inputGainDb
    }

    /// Persists room mode and pushes it to a running session, so the toggle is
    /// audible in the live transcript rather than only in the next recording.
    func setRoomMode(_ on: Bool) {
        settings.roomMode = on
        live.isRoomMode = on
    }

    var context: ModelContext { container.mainContext }

    // MARK: - Job events

    private func startPump() {
        pump = Task { [weak self] in
            guard let self else { return }
            for await event in self.queue.events {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: JobEvent) async {
        switch event {
        case .queued(let id, _):
            progress[id] = JobProgress(status: .pending, fraction: 0)
            openTranscripts[id] = nil
            stageClock[id] = nil

        case .stage(let id, let status, let fraction):
            let previous = progress[id]
            progress[id] = JobProgress(
                status: status, fraction: fraction,
                remaining: estimateRemaining(id, status: status, fraction: fraction),
                coveredMs: previous?.coveredMs ?? 0
            )
            // The store needs the stage, not every fraction of it. Persisting
            // the fraction meant a fetch and a SQLite save per progress tick --
            // tens of thousands of transactions for one long recording, for a
            // number nothing ever reads back.
            if previous?.status != status {
                try? await writer.updateStatus(status, progress: fraction, for: id)
            }

        case .prepared(let id, let durationMs, let waveform):
            try? await writer.finishTranscription(
                durationMs: durationMs,
                waveform: waveform.isEmpty ? nil : waveform,
                for: id
            )

        case .partial(let id, let segments, let coveredMs):
            guard let job = queuedJobs[id] else { break }
            if openTranscripts[id] == nil {
                openTranscripts[id] = try? await writer.openPartialTranscript(
                    modelId: job.modelId, language: job.language, for: id
                )
            }
            if let transcriptId = openTranscripts[id] {
                try? await writer.appendPartial(segments, to: transcriptId)
            }
            progress[id]?.coveredMs = coveredMs

        case .transcribed(let id, let payload):
            try? await writer.completeTranscript(
                openTranscripts[id],
                segments: payload.segments, roster: payload.roster,
                modelId: payload.modelId, language: payload.language,
                processMs: payload.processMs, didDiarize: payload.didDiarize,
                for: id
            )
            openTranscripts[id] = nil
            try? await writer.finishTranscription(
                durationMs: payload.durationMs,
                waveform: payload.waveform.isEmpty ? nil : payload.waveform,
                for: id
            )

        case .diarized(let id, let spans, let roster):
            try? await writer.applySpeakers(spans: spans, roster: roster, for: id)

        case .failed(let id, let message):
            try? await writer.updateStatus(.failed, error: message, for: id)
            alert = AppAlert(title: "Transcription failed", message: message)

        case .warning(let id, let message):
            // The transcript is usable but incomplete. Keyed to the recording
            // rather than thrown in an alert, so it stays visible for this
            // app run. (In-memory only: surviving a relaunch would need a
            // column on StoredRecording.)
            warnings[id] = message

        case .finished(let id):
            progress[id] = nil
            stageClock[id] = nil
            queuedJobs[id] = nil
            openTranscripts[id] = nil
        }
    }

    /// Seconds left in the current stage, from how long the fraction done has
    /// taken so far. Nothing until 5 % is in, since a first window's timing
    /// says little; smoothed after that so one slow window does not swing the
    /// number by minutes.
    private func estimateRemaining(_ id: UUID, status: TranscriptionStatus,
                                   fraction: Double) -> TimeInterval? {
        guard status.isBusy else { stageClock[id] = nil; return nil }
        let now = Date()
        guard var clock = stageClock[id], clock.status == status else {
            stageClock[id] = StageClock(status: status, since: now, remaining: nil)
            return nil
        }
        guard fraction >= 0.05, fraction < 1 else { return clock.remaining }
        let elapsed = now.timeIntervalSince(clock.since)
        let raw = elapsed / fraction * (1 - fraction)
        clock.remaining = clock.remaining.map { $0 * 0.7 + raw * 0.3 } ?? raw
        stageClock[id] = clock
        return clock.remaining
    }

    // MARK: - Lookup

    func recording(_ id: UUID) -> StoredRecording? {
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    var selectedRecording: StoredRecording? {
        guard case .recording(let id) = route else { return nil }
        return recording(id)
    }

    // MARK: - Creating

    @discardableResult
    func newItem(_ kind: RecordingKind) -> StoredRecording? {
        do {
            let recording = try RecordingStore.create(kind: kind, in: context)
            route = .recording(recording.id)
            if kind != .note { Task { await beginRecording(recording) } }
            return recording
        } catch {
            alert = AppAlert(title: "Could not create that", message: error.localizedDescription)
            return nil
        }
    }

    // MARK: - Live recording

    var isRecording: Bool { live.state.isRecording }

    /// True from the tap on New Recording until the session ends, model load
    /// included. What the UI has to switch on: `isRecording` is false for the
    /// whole preparing phase, so anything gated on it leaves those seconds
    /// looking like a hang.
    var isLiveBusy: Bool { live.state.isBusy }

    /// Whether this recording is the one the live session is busy with, in any
    /// phase.
    func isLive(_ id: UUID) -> Bool { activeRecordingId == id && isLiveBusy }

    func beginRecording(_ recording: StoredRecording) async {
        // A launch warmup may still be loading the model. Waiting for it is the
        // point -- the `isBusy` guard below would otherwise drop the recording
        // silently, which is a worse first second than a slow one.
        await warmup?.value
        guard !live.state.isBusy else { return }
        let id = recording.id
        activeRecordingId = id
        let name = Paths.newRecordingName(id: id, ext: "m4a", on: recording.createdAt)
        recording.audioFileName = name
        recording.status = .preparing
        try? context.save()

        live.config = settings.sessionConfig
        live.inputGainDb = settings.inputGainDb
        live.isRoomMode = settings.roomMode
        await queue.setLiveActive(true)
        await engines.beginLive()
        await live.prepare(model: settings.liveModelId)

        do {
            try await live.start(recordingId: id, archiveFileName: name,
                                 archiveURL: Paths.recordingURL(name))
            recording.status = .recording
            try? context.save()
        } catch {
            activeRecordingId = nil
            recording.status = .failed
            recording.errorMessage = error.localizedDescription
            try? context.save()
            await engines.endLive()
            await queue.setLiveActive(false)
            alert = AppAlert(title: "Could not start recording",
                             message: error.localizedDescription)
        }
    }

    func stopRecording() async {
        let finished = await live.stop()
        activeRecordingId = nil
        guard let result = finished else { return }
        await engines.endLive()

        // A thrown decode is counted, not shown, during the session -- here is
        // where it has to surface. Without this, a backend that failed on
        // every hop produces a completed recording with an empty transcript.
        if result.stats.failedHops > 0 {
            let detail = result.stats.lastError.map { " Last error: \($0)" } ?? ""
            warnings[result.recordingId] = result.stats.hops == 0
                ? "Live transcription failed for this entire recording "
                  + "(\(result.stats.failedHops) decode errors).\(detail) "
                  + "The audio was saved -- use Transcribe Again to recover it."
                : "\(result.stats.failedHops) decode(s) failed during this "
                  + "recording, so some words may be missing.\(detail)"
        }

        try? await writer.storeTranscript(
            segments: result.segments, roster: [], modelId: result.modelId,
            language: result.language, processMs: result.stats.totalInferMs,
            didDiarize: false, for: result.recordingId
        )
        try? await writer.attachAudio(
            fileName: result.archiveFileName ?? "",
            sampleRate: result.archiveSampleRate,
            durationMs: result.durationMs,
            waveform: result.waveform.isEmpty ? nil : result.waveform,
            for: result.recordingId
        )

        if settings.diarize {
            let job = TranscriptionJob(
                id: result.recordingId,
                title: recording(result.recordingId)?.title ?? "Recording",
                sourceURL: result.archiveFileName.map { Paths.recordingURL($0) },
                cacheURL: result.cacheURL,
                modelId: result.modelId,
                language: result.language,
                diarize: true,
                work: .diarizeOnly,
                discardCacheWhenDone: !settings.keepWorkingCopy,
                expectedSpeakers: recording(result.recordingId)?.expectedSpeakers
            )
            queuedJobs[job.id] = job
            await queue.enqueue(job)
        } else {
            try? await writer.updateStatus(.completed, progress: 1, for: result.recordingId)
            if !settings.keepWorkingCopy {
                try? FileManager.default.removeItem(at: result.cacheURL)
            }
        }
        await queue.setLiveActive(false)

        if result.durationMs < Self.shortTakeMs {
            shortTake = ShortTake(
                id: result.recordingId,
                durationMs: result.durationMs,
                words: result.segments.reduce(0) {
                    $0 + $1.displayText.split(whereSeparator: \.isWhitespace).count
                }
            )
        }
    }

    /// The answer to the short-take question. Discarding is a full delete:
    /// audio, row, and any speaker job the stop just queued.
    func resolveShortTake(keep: Bool) {
        defer { shortTake = nil }
        guard !keep, let take = shortTake, let recording = recording(take.id) else { return }
        delete(recording)
    }

    /// ⌘B. Works while recording and while playing back.
    @discardableResult
    func addBookmark(label: String = "") -> Bool {
        guard let recording = selectedRecording else { return false }
        let ms = isRecording ? live.currentMs : player.currentMs
        do {
            try RecordingStore.addBookmark(at: ms, label: label, to: recording, in: context)
            return true
        } catch {
            alert = AppAlert(title: "Could not add bookmark", message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Importing

    static let importableTypes: [UTType] = [
        .audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie,
    ]

    func importFiles(_ urls: [URL]) {
        for url in urls { importFile(url) }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let recording = try RecordingStore.create(
                kind: .recording,
                title: url.deletingPathExtension().lastPathComponent,
                in: context
            )
            // Copied into the library rather than referenced: a file the user
            // moves or deletes would otherwise take the recording's audio with
            // it, and there is no way to notice until playback fails.
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let name = Paths.newRecordingName(id: recording.id, ext: ext)
            let destination = Paths.recordingURL(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)

            recording.audioFileName = name
            recording.status = .pending
            try context.save()

            enqueueTranscription(recording, work: .full)
            route = .recording(recording.id)
        } catch {
            alert = AppAlert(title: "Could not import \(url.lastPathComponent)",
                             message: error.localizedDescription)
        }
    }

    func enqueueTranscription(_ recording: StoredRecording, work: TranscriptionJob.Work,
                              modelId: String? = nil, diarize: Bool? = nil) {
        guard let name = recording.audioFileName else { return }
        warnings[recording.id] = nil
        let job = TranscriptionJob(
            id: recording.id,
            title: recording.title,
            sourceURL: Paths.recordingURL(name),
            cacheURL: AudioCache.url(for: recording.id, under: Paths.support),
            modelId: modelId ?? settings.offlineModelId,
            language: settings.language,
            prompt: settings.promptOrNil,
            diarize: diarize ?? settings.diarize,
            work: work,
            discardCacheWhenDone: !settings.keepWorkingCopy,
            roomMode: settings.roomMode,
            expectedSpeakers: recording.expectedSpeakers
        )
        progress[recording.id] = JobProgress(status: .pending, fraction: 0)
        queuedJobs[recording.id] = job
        Task { await queue.enqueue(job) }
    }

    /// Decode again, optionally on a named tier. Nil means the tier Settings
    /// holds -- but the menu always names one, because "again" with the same
    /// model is rarely what anyone re-transcribing a meeting wants.
    func retranscribe(_ recording: StoredRecording, tier: ModelTier? = nil) {
        enqueueTranscription(recording, work: .full,
                             modelId: tier.map { settings.modelId(for: $0) })
    }

    /// Speaker identification only, over the transcript that exists. Forced on
    /// regardless of the setting: asking for it is the setting.
    func rediarize(_ recording: StoredRecording) {
        enqueueTranscription(recording, work: .diarizeOnly, diarize: true)
    }

    func cancelJob(_ id: UUID) {
        Task { await queue.cancel(id) }
    }

    // MARK: - Deleting

    func delete(_ recording: StoredRecording) {
        let id = recording.id
        Task { await queue.cancel(id) }
        AudioCache.discard(id, under: Paths.support)
        if case .recording(id) = route { route = nil }
        if player.loadedURL == recording.audioURL { player.unload() }
        do {
            try RecordingStore.delete(recording, in: context)
        } catch {
            alert = AppAlert(title: "Could not delete", message: error.localizedDescription)
        }
    }

    func delete(_ recordings: [StoredRecording]) {
        for recording in recordings { delete(recording) }
    }

    // MARK: - Meeting items

    /// Turns the selected transcript row into a typed note, keeping the
    /// back-link. This is the whole point of the manual workspace: a decision
    /// the user wrote down stays auditable against the audio it came from.
    func addSelectionAsItem(_ kind: MeetingItemKind) {
        guard let recording = selectedRecording,
              let segmentId = selectedSegmentId,
              let segment = (recording.transcript?.orderedSegments ?? [])
                  .first(where: { $0.id == segmentId })
        else { return }
        do {
            try RecordingStore.addItem(kind, text: segment.displayText,
                                       source: segment, to: recording, in: context)
            RecordingStore.reindex(recording)
            try context.save()
        } catch {
            alert = AppAlert(title: "Could not add that note", message: error.localizedDescription)
        }
    }

    // MARK: - Export

    func exportText(_ recording: StoredRecording, format: ExportFormat) -> String {
        Exporter.render(format, document: RecordingStore.document(for: recording))
    }

    // MARK: - Playback

    /// Loads the recording's audio and seeks. The one entry point for every
    /// "jump to this moment" in the app, so transcript clicks, bookmarks,
    /// search results and note back-links all behave identically.
    func seek(to ms: Int, in recording: StoredRecording, play: Bool = false) {
        guard let url = recording.audioURL else { return }
        if player.loadedURL != url { _ = player.load(url) }
        player.seek(toMs: ms)
        if play, !player.isPlaying { player.play() }
    }

    func open(_ hit: SearchHit) {
        route = .recording(hit.recordingId)
        pendingScrollTarget = hit.segmentId
        if let ms = hit.atMs, let recording = recording(hit.recordingId) {
            seek(to: ms, in: recording)
        }
    }

    // MARK: - Memory

    /// Called when the app is idle. Releasing the diarizer between recordings
    /// is 200 MB back on a machine that is going to want it for the model.
    func releaseIdleModels() {
        guard !isRecording else { return }
        Task { await engines.releaseDiarizer() }
    }

    /// Loads the live model before anything asks for it, so hitting record does
    /// not sit on a cold load.
    ///
    /// Only for a model already on disk: warming one that is not would start a
    /// 1.6 GB download at launch that nobody asked for.
    func warmUpEngines() {
        guard warmup == nil, live.state == .idle else { return }
        guard ModelCatalogue.isDownloaded(settings.liveModelId,
                                          modelsDirectory: Paths.models) else { return }
        warmup = Task { [weak self] in
            guard let self else { return }
            await live.prepare(model: settings.liveModelId)
        }
    }
}
