import Foundation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore

/// Consuming the transcription queue: progress, partial and final transcripts,
/// warnings, and the time-remaining estimate.
extension AppState {

    // MARK: - Job events

    func startPump() {
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

        case .diarized(let id, let spans, let roster):
            try? await writer.applySpeakers(spans: spans, roster: roster, for: id)

        case .failed(let id, let message):
            // No alert: a background job failing should not interrupt whatever
            // is on screen. The row's chip, the Needs Attention group and the
            // detail's empty state all carry the message.
            try? await writer.updateStatus(.failed, error: message, for: id)

        case .warning(let id, let message):
            // The transcript is usable but incomplete. Keyed to the recording
            // rather than thrown in an alert, and stored so it survives a
            // relaunch.
            warnings[id] = message
            try? await writer.setWarning(message, for: id)

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
}
