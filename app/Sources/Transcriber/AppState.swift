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

    /// Per-recording pipeline progress, keyed by recording id.
    private(set) var progress: [UUID: JobProgress] = [:]
    /// Per-recording notes about work that finished imperfectly.
    private(set) var warnings: [UUID: String] = [:]
    private(set) var isPreparingModel = false
    private(set) var modelStatus = ""

    private var pump: Task<Void, Never>?

    struct JobProgress: Equatable {
        var status: TranscriptionStatus
        var fraction: Double
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

        case .stage(let id, let status, let fraction):
            progress[id] = JobProgress(status: status, fraction: fraction)
            try? await writer.updateStatus(status, progress: fraction, for: id)

        case .transcribed(let id, let payload):
            try? await writer.storeTranscript(
                segments: payload.segments, roster: payload.roster,
                modelId: payload.modelId, language: payload.language,
                processMs: payload.processMs, didDiarize: payload.didDiarize,
                for: id
            )
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
        }
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

    func beginRecording(_ recording: StoredRecording) async {
        guard !live.state.isBusy else { return }
        let id = recording.id
        let name = Paths.newRecordingName(id: id, ext: "m4a", on: recording.createdAt)
        recording.audioFileName = name
        recording.status = .preparing
        try? context.save()

        isPreparingModel = true
        modelStatus = "Loading model…"
        live.config = settings.sessionConfig
        live.inputGainDb = settings.inputGainDb
        live.isRoomMode = settings.roomMode
        await queue.setLiveActive(true)
        await engines.beginLive()
        await live.prepare(model: settings.liveModelId)
        isPreparingModel = false

        do {
            try await live.start(recordingId: id, archiveFileName: name,
                                 archiveURL: Paths.recordingURL(name))
            recording.status = .recording
            try? context.save()
        } catch {
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
        guard let result = await live.stop() else { return }
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
                discardCacheWhenDone: !settings.keepWorkingCopy
            )
            await queue.enqueue(job)
        } else {
            try? await writer.updateStatus(.completed, progress: 1, for: result.recordingId)
            if !settings.keepWorkingCopy {
                try? FileManager.default.removeItem(at: result.cacheURL)
            }
        }
        await queue.setLiveActive(false)
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

    func enqueueTranscription(_ recording: StoredRecording, work: TranscriptionJob.Work) {
        guard let name = recording.audioFileName else { return }
        warnings[recording.id] = nil
        let job = TranscriptionJob(
            id: recording.id,
            title: recording.title,
            sourceURL: Paths.recordingURL(name),
            cacheURL: AudioCache.url(for: recording.id, under: Paths.support),
            modelId: settings.offlineModelId,
            language: settings.language,
            prompt: settings.promptOrNil,
            diarize: settings.diarize,
            work: work,
            discardCacheWhenDone: !settings.keepWorkingCopy,
            roomMode: settings.roomMode
        )
        progress[recording.id] = JobProgress(status: .pending, fraction: 0)
        Task { await queue.enqueue(job) }
    }

    func retranscribe(_ recording: StoredRecording) {
        enqueueTranscription(recording, work: .full)
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
}
