import Foundation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore
import UniformTypeIdentifiers

/// The live session from the tap on New Recording to the row it leaves behind,
/// and the question asked about a take that stopped almost at once.
extension AppState {

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
        live.decodeLive = settings.liveTranscription
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
        let decodedLive = live.decodeLive

        // A thrown decode is counted, not shown, during the session -- here is
        // where it has to surface. Without this, a backend that failed on
        // every hop produces a completed recording with an empty transcript.
        if decodedLive, result.stats.failedHops > 0 {
            let detail = result.stats.lastError.map { " Last error: \($0)" } ?? ""
            warnings[result.recordingId] = result.stats.hops == 0
                ? "Live transcription failed for this entire recording "
                  + "(\(result.stats.failedHops) decode errors).\(detail) "
                  + "The audio was saved -- use Transcribe Again to recover it."
                : "\(result.stats.failedHops) decode(s) failed during this "
                  + "recording, so some words may be missing.\(detail)"
        }

        if decodedLive {
            try? await writer.storeTranscript(
                segments: result.segments, roster: [], modelId: result.modelId,
                language: result.language, processMs: result.stats.totalInferMs,
                didDiarize: false, for: result.recordingId
            )
        }
        try? await writer.attachAudio(
            fileName: result.archiveFileName ?? "",
            sampleRate: result.archiveSampleRate,
            durationMs: result.durationMs,
            waveform: result.waveform.isEmpty ? nil : result.waveform,
            for: result.recordingId
        )

        if !decodedLive {
            // Capture-only session: the whole-file pass is the transcript.
            // The working copy it needs is the one the session just wrote.
            if let stored = recording(result.recordingId) {
                enqueueTranscription(stored, work: .full)
            }
        } else if settings.diarize {
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
                words: decodedLive
                    ? result.segments.reduce(0) {
                        $0 + $1.displayText.split(whereSeparator: \.isWhitespace).count
                    }
                    : nil
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
}
