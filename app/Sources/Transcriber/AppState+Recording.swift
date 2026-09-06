import Foundation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberFlow
import TranscriberStore

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

    /// The recording is under way and paused: the clock and the file stand
    /// still until Resume.
    var isPaused: Bool { isRecording && live.isPaused }

    /// ⇧⌘P, the Pause button and the toolbar. Nothing to do outside a recording.
    func togglePause() {
        guard isRecording else { return }
        live.isPaused.toggle()
    }

    func beginRecording(_ recording: StoredRecording) async {
        // A launch warmup may still be loading the model. Waiting for it is the
        // point -- the `isBusy` guard below would otherwise drop the recording
        // silently, which is a worse first second than a slow one.
        await warmup?.value
        guard !live.state.isBusy else {
            alert = AppAlert(
                title: "A recording is already under way",
                message: "Wait for the current one to finish, or stop it first, "
                       + "before starting another."
            )
            return
        }
        let id = recording.id
        activeRecordingId = id
        let name = Paths.newRecordingName(id: id, ext: "m4a", on: recording.createdAt)
        recording.audioFileName = name
        recording.status = .preparing
        try? context.save()

        live.configure(settings.liveConfiguration)

        // The tap is global -- it has to be, or it stops delivering whenever
        // this app is the only thing playing -- so anything Notero plays goes
        // into the recording. Stopping playback is cheaper than the
        // alternative, and nobody wants last week's meeting inside this one.
        if settings.captureSource.usesSystemAudio, player.isPlaying {
            player.pause()
        }
        await queue.setLiveActive(true)
        await engines.beginLive()
        await live.prepare(model: settings.liveModelId)

        do {
            try await live.start(recordingId: id, archiveFileName: name,
                                 archiveURL: Paths.recordingURL(name))
            recording.status = .recording
            try? context.save()
            if live.decodeLive {
                // Committed lines go to the store as they are committed, not
                // at Stop. The revision opened here is the one Stop completes.
                let persister = LiveTranscriptPersister(
                    writer: writer, recordingId: id,
                    modelId: settings.liveModelId, language: settings.language
                )
                await persister.open()
                live.onCommitted = { [weak persister] segments in
                    persister?.append(segments)
                }
                livePersister = persister
            }
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

    /// Stops the session and carries out the plan for what it left behind.
    /// The decisions are `StopPlan.make`; this method is the awaits.
    func stopRecording() async {
        let finished = await live.stop()
        live.onCommitted = nil
        let persister = livePersister
        livePersister = nil
        activeRecordingId = nil
        guard let result = finished else { return }
        await engines.endLive()
        let id = result.recordingId

        let plan = StopPlan.make(
            result: result, decodedLive: live.decodeLive, hadPersister: persister != nil,
            diarizationMode: settings.diarizationMode, keepWorkingCopy: settings.keepWorkingCopy,
            shortTakeMs: Self.shortTakeMs
        )

        // A thrown decode is counted, not shown, during the session -- here is
        // where it surfaces. Without it, a backend that failed on every hop
        // produces a completed recording with an empty transcript.
        if let warning = plan.liveFailureWarning {
            await jobs.addWarning(warning, for: id)
        }

        switch plan.transcript {
        case .completePersister:
            // The final list replaces the rows written during the recording,
            // through the same call the whole-file job uses.
            _ = try? await persister?.complete(segments: result.segments,
                                               processMs: result.stats.totalInferMs)
        case .storeFresh:
            _ = try? await writer.storeTranscript(
                segments: result.segments, roster: [], modelId: result.modelId,
                language: result.language, processMs: result.stats.totalInferMs,
                didDiarize: false, for: id
            )
        case .none:
            break
        }
        try? await writer.attachAudio(
            fileName: result.archiveFileName ?? "",
            sampleRate: result.archiveSampleRate,
            durationMs: result.durationMs,
            waveform: result.waveform.isEmpty ? nil : result.waveform,
            lanes: result.lanes,
            for: id
        )

        switch plan.followUp {
        case .fullTranscription:
            // The working copy the pass needs is the one the session wrote.
            if let stored = recording(id) {
                enqueueTranscription(stored, work: .full)
            }
        case .diarizeOnly(let mode):
            jobs.enqueue(TranscriptionJob(
                id: id,
                title: recording(id)?.title ?? "Recording",
                sourceURL: result.archiveFileName.map { Paths.recordingURL($0) },
                cacheURL: result.cacheURL,
                modelId: result.modelId,
                language: result.language,
                diarizationMode: mode,
                work: .diarizeOnly,
                discardCacheWhenDone: !settings.keepWorkingCopy,
                expectedSpeakers: recording(id)?.expectedSpeakers
            ))
        case .markCompleted(let discardCache):
            try? await writer.updateStatus(.completed, progress: 1, for: id)
            if discardCache {
                try? FileManager.default.removeItem(at: result.cacheURL)
            }
        }

        // What changed under the recording, kept with it: the person who reads
        // the transcript tomorrow has to know why the room goes quiet at 0:41.
        // After the enqueue, which clears the warning for the job it starts.
        if let notices = plan.noticesWarning {
            await jobs.addWarning(notices, for: id)
        }
        await queue.setLiveActive(false)

        if let take = plan.shortTake {
            shortTake = ShortTake(id: id, durationMs: take.durationMs, words: take.words)
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
