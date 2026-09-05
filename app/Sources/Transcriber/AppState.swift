import Foundation
import Observation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore

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
///
/// The stored state and the small view-facing helpers are here. The larger
/// concerns each have a file: `AppState+Jobs` consumes the queue's events,
/// `AppState+Recording` runs the live session, `AppState+Library` imports,
/// re-runs and deletes, `AppState+Models` manages weights and memory. Members
/// those files reach are internal rather than private for that reason.
@Observable
final class AppState {

    let container: ModelContainer
    let settings: AppSettings
    let engines: EngineHost
    let queue: TranscriptionQueue
    let live: LiveSession
    let player = AudioPlayer()
    let writer: TranscriptWriter

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
    /// ⌘F on a recording: the transcript view opens its find bar and clears this.
    var findRequested = false
    var exportFormat: ExportFormat = .txt

    /// Keep the playing turn in view. Off the moment the user scrolls by hand,
    /// back on from the player bar or the "Follow playback" pill.
    var followPlayback = true

    /// ⌘[ and ⌘]: the transcript view moves the selection by this many turns.
    var turnStep: TurnStep?

    struct TurnStep: Equatable {
        let delta: Int
        let serial: Int
    }

    func stepTurn(_ delta: Int) {
        turnStep = TurnStep(delta: delta, serial: (turnStep?.serial ?? 0) + 1)
    }

    /// The speeds the player offers, in order.
    static let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    /// ⌥↑ and ⌥↓: one step along `playbackRates`.
    func adjustSpeed(_ direction: Int) {
        let rates = Self.playbackRates
        let current = rates.indices.min {
            abs(rates[$0] - player.rate) < abs(rates[$1] - player.rate)
        } ?? 1
        let next = min(rates.count - 1, max(0, current + direction))
        player.rate = rates[next]
    }

    /// A transcript timestamp the way the user asked to read it: an offset
    /// into the recording, or the time of day it was said.
    func timestamp(ms: Int, in recording: StoredRecording) -> String {
        settings.clockTimestamps
            ? TimeFormat.timeOfDay(ms: ms, start: recording.createdAt)
            : TimeFormat.short(ms: ms)
    }

    /// The transcript row the user last clicked. What ⌃⌘D and friends act on.
    var selectedSegmentId: UUID?

    /// A recording that stopped almost as soon as it started. Set on stop so
    /// the window can ask whether to keep it: the library had five of these
    /// under half a minute, each one a click-and-delete nobody got round to.
    var shortTake: ShortTake?

    struct ShortTake: Identifiable {
        let id: UUID
        let durationMs: Int
        /// Nil when nothing was decoded live, so there is no word count to give.
        let words: Int?
    }

    /// Download progress per model id, 0...1, while one runs.
    var modelDownloads: [String: Double] = [:]
    /// Bumped when a model arrives or goes, so views re-read the disk.
    var modelsRevision = 0

    /// Below this a take is asked about rather than kept silently.
    static let shortTakeMs = 10_000

    /// Width of the window's content, kept current by `ContentView`.
    ///
    /// The three columns cannot all have their way in a narrow window: the
    /// split view gives the sidebar and the inspector their widths and lets
    /// the transcript overflow, cropping the window at both edges. Below
    /// `inspectorNeedsWidth` the inspector folds away instead.
    var contentWidth: CGFloat = .infinity
    /// Sidebar at its ideal (268), a readable transcript (~450) and the
    /// inspector at its ideal (320), with slack for the dividers.
    static let inspectorNeedsWidth: CGFloat = 1_060
    var hasRoomForInspector: Bool { contentWidth >= Self.inspectorNeedsWidth }
    /// Sidebar at its minimum (200) plus a transcript column worth reading.
    /// Below this the sidebar folds and the detail has the window to itself;
    /// the toolbar toggle still brings it back on request.
    static let sidebarNeedsWidth: CGFloat = 800
    var isCompact: Bool { contentWidth < Self.sidebarNeedsWidth }

    /// Per-recording pipeline progress, keyed by recording id.
    var progress: [UUID: JobProgress] = [:]
    /// Per-recording notes about work that finished imperfectly.
    var warnings: [UUID: String] = [:]
    /// The recording the live session is working on, set the moment the user
    /// asks for one rather than when the first sample arrives. `live.recordingId`
    /// only exists once capture starts, which on a cold model is several
    /// seconds later -- and those are exactly the seconds the UI has to show
    /// something for.
    var activeRecordingId: UUID?

    var pump: Task<Void, Never>?
    var warmup: Task<Void, Never>?

    /// Jobs handed to the queue, kept until they finish: `.partial` events
    /// need the model and language the job was started with.
    var queuedJobs: [UUID: TranscriptionJob] = [:]
    /// The revision each running job is appending to, from its first window.
    var openTranscripts: [UUID: UUID] = [:]
    /// Writes the live session's committed lines as they land, so a crash
    /// mid-meeting keeps everything up to the last commit.
    var livePersister: LiveTranscriptPersister?
    /// When the current stage of each job began and the last estimate made
    /// from it. The estimate is smoothed against this.
    var stageClock: [UUID: StageClock] = [:]

    struct StageClock {
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
        _ = try? RecordingStore.recoverInterrupted(in: container.mainContext)
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

    /// Pending questions, asked one at a time.
    var duplicateImports: [DuplicateImport] = []

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

    func exportText(_ recording: StoredRecording, format: ExportFormat,
                    options: ExportOptions = .everything) -> String {
        Exporter.render(format, document: RecordingStore.document(for: recording),
                        options: options)
    }

    /// The transcript onto the clipboard, in the format the destination
    /// wants: plain text for a document, Markdown for chat and wikis.
    func copyTranscript(_ recording: StoredRecording, format: ExportFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportText(recording, format: format), forType: .string)
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

}
