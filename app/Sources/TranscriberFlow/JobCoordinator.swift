import Foundation
import Observation
import TranscriberCore
import TranscriberEngine
import TranscriberStore

/// Per-recording progress of a job in the queue, as the views show it.
nonisolated public struct JobProgress: Equatable, Sendable {
    public var status: TranscriptionStatus
    public var fraction: Double
    /// Seconds left in this stage, once enough of it has run to say.
    public var remaining: TimeInterval?
    /// How far into the audio the decode has reached.
    public var coveredMs: Int

    public init(status: TranscriptionStatus, fraction: Double,
                remaining: TimeInterval? = nil, coveredMs: Int = 0) {
        self.status = status
        self.fraction = fraction
        self.remaining = remaining
        self.coveredMs = coveredMs
    }
}

/// The reduction from queue events to store writes and to the three values
/// the views read: progress, warnings and the transcript ticks.
///
/// This used to be a private method on the app state, with six bookkeeping
/// dictionaries beside it that the views read directly. No test reached the
/// method, and the dictionaries were the interface. Here the reduction owns
/// its state, the interface is three reads and three commands, and a test
/// feeds events and checks the store.
@Observable
public final class JobCoordinator {

    /// Per-recording pipeline progress, while a job runs.
    public private(set) var progress: [UUID: JobProgress] = [:]
    /// Per-recording notes about work that finished imperfectly, kept until a
    /// new job starts on the recording. Persisted on the row as well.
    public private(set) var warnings: [UUID: String] = [:]
    /// Bumped when a job writes rows into a recording's transcript: a batch
    /// of partial rows, the final rows, the speaker labels, a redone turn.
    /// The transcript view reads it instead of counting the rows.
    public private(set) var transcriptTicks: [UUID: Int] = [:]

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

    /// Called when a job leaves the queue, whatever became of it. The app
    /// reads the recording's own status to find out which. Set once, at
    /// launch; `AutoDraft` decides what happens next.
    public var onFinished: ((UUID) -> Void)?

    private let queue: TranscriptionQueue
    private let writer: TranscriptWriter
    private let now: @Sendable () -> Date
    private var pump: Task<Void, Never>?

    /// - Parameter now: the clock for the time-remaining estimate. Tests
    ///   pass their own.
    public init(queue: TranscriptionQueue, writer: TranscriptWriter,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.queue = queue
        self.writer = writer
        self.now = now
    }

    // MARK: - Reads

    public func progress(for id: UUID) -> JobProgress? { progress[id] }
    public func warning(for id: UUID) -> String? { warnings[id] }
    public func tick(for id: UUID) -> Int { transcriptTicks[id] ?? 0 }
    /// Whether a job is queued or running on the recording.
    public func isBusy(_ id: UUID) -> Bool { progress[id] != nil }

    // MARK: - Commands

    /// Starts consuming the queue's events. Once, at launch.
    public func start() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            guard let self else { return }
            for await event in self.queue.events {
                await self.handle(event)
            }
        }
    }

    /// Hands a job to the queue. The row shows "In queue" at once, and the
    /// warning from the previous job on the recording is cleared: the new
    /// job's own warnings are what the row will carry.
    public func enqueue(_ job: TranscriptionJob) {
        warnings[job.id] = nil
        progress[job.id] = JobProgress(status: .pending, fraction: 0)
        queuedJobs[job.id] = job
        Task { await queue.enqueue(job) }
    }

    public func cancel(_ id: UUID) {
        Task { await queue.cancel(id) }
    }

    /// A warning from outside the queue, such as the live session's. Added
    /// to what the recording already carries, never put in its place, and
    /// persisted so it survives a relaunch.
    public func addWarning(_ message: String, for id: UUID) async {
        let joined = Self.join(warnings[id], message)
        warnings[id] = joined
        try? await writer.setWarning(joined, for: id)
    }

    // MARK: - The reduction

    func handle(_ event: JobEvent) async {
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
            transcriptTicks[id, default: 0] += 1

        case .transcribed(let id, let payload):
            let performanceJSON = (try? JSONEncoder().encode(payload.metrics))
                .flatMap { String(data: $0, encoding: .utf8) }
            _ = try? await writer.completeTranscript(
                openTranscripts[id],
                segments: payload.segments, roster: payload.roster,
                modelId: payload.modelId, language: payload.language,
                processMs: payload.processMs, didDiarize: payload.didDiarize,
                performanceJSON: performanceJSON,
                for: id
            )
            openTranscripts[id] = nil
            try? await writer.finishTranscription(
                durationMs: payload.durationMs,
                waveform: payload.waveform.isEmpty ? nil : payload.waveform,
                for: id
            )
            transcriptTicks[id, default: 0] += 1

        case .rangeTranscribed(let id, let fromMs, let toMs, let segments, _):
            _ = try? await writer.replaceSegments(fromMs: fromMs, toMs: toMs, with: segments, for: id)
            transcriptTicks[id, default: 0] += 1

        case .diarized(let id, let spans, let roster):
            try? await writer.applySpeakers(spans: spans, roster: roster, for: id)
            transcriptTicks[id, default: 0] += 1

        case .failed(let id, let message):
            // No alert: a background job failing should not interrupt whatever
            // is on screen. The row's chip, the Needs Attention group and the
            // detail's empty state all carry the message.
            try? await writer.updateStatus(.failed, error: message, for: id)

        case .warning(let id, let message):
            // The transcript is usable but incomplete. Keyed to the recording
            // rather than thrown in an alert, and stored so it survives a
            // relaunch. Added to what the row already says rather than put in
            // its place: a microphone that was replaced during the recording
            // is still true after the transcription that followed it.
            let joined = Self.join(warnings[id], message)
            warnings[id] = joined
            try? await writer.setWarning(joined, for: id)

        case .finished(let id):
            progress[id] = nil
            stageClock[id] = nil
            queuedJobs[id] = nil
            openTranscripts[id] = nil
            // After the bookkeeping, so a handler that reads `isBusy` sees
            // the job gone rather than still running.
            onFinished?(id)
        }
    }

    /// The existing warning plus a new one, with a repeat dropped.
    private static func join(_ existing: String?, _ message: String) -> String {
        var parts: [String] = []
        for part in [existing, message].compactMap({ $0 }) where !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: " ")
    }

    /// Seconds left in the current stage, from how long the fraction done has
    /// taken so far. Nothing until 5 % is in, since a first window's timing
    /// says little; smoothed after that so one slow window does not swing the
    /// number by minutes.
    private func estimateRemaining(_ id: UUID, status: TranscriptionStatus,
                                   fraction: Double) -> TimeInterval? {
        guard status.isBusy else { stageClock[id] = nil; return nil }
        let now = now()
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
}
