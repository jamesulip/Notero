import Foundation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
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

        live.config = settings.sessionConfig
        live.inputGainDb = settings.inputGainDb
        live.isRoomMode = settings.roomMode
        live.decodeLive = settings.liveTranscription
        live.captureSource = settings.captureSource
        live.microphoneUID = settings.microphoneUID

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
                // Said while the recording runs, once: until Stop these rows
                // are the only protection against a crash, so a person who
                // cannot have them has to know.
                persister.onDegraded = { [weak self] note in
                    guard let self else { return }
                    warnings[id] = [warnings[id], note].compactMap { $0 }.joined(separator: " ")
                }
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

    /// - Parameter quitting: the app is closing. Everything that makes the
    ///   recording whole still runs (the files close, the transcript is
    ///   saved), but the job that would follow does not start, because it
    ///   would die with the process.
    func stopRecording(quitting: Bool = false) async {
        let finished = await live.stop()
        live.onCommitted = nil
        let persister = livePersister
        livePersister = nil
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
            // The final list replaces the rows written during the recording,
            // through the same call the whole-file job uses; with no open
            // revision it stores a fresh one, as before.
            do {
                if let persister {
                    _ = try await persister.complete(segments: result.segments,
                                                     processMs: result.stats.totalInferMs)
                } else {
                    _ = try await writer.storeTranscript(
                        segments: result.segments, roster: [], modelId: result.modelId,
                        language: result.language, processMs: result.stats.totalInferMs,
                        didDiarize: false, for: result.recordingId
                    )
                }
            } catch {
                // Said, not swallowed: otherwise the recording reads as
                // complete while its transcript stops at the last line the
                // session happened to save, or is missing altogether.
                let saved = "The transcript could not be saved "
                    + "(\(error.localizedDescription)), so lines may be missing. "
                    + "The audio was saved -- use Transcribe Again to recover it."
                warnings[result.recordingId] = [warnings[result.recordingId], saved]
                    .compactMap { $0 }.joined(separator: " ")
            }
        }
        let attached = await ledger.succeeded(.status, for: result.recordingId) {
            try await writer.attachAudio(
                fileName: result.archiveFileName ?? "",
                sampleRate: result.archiveSampleRate,
                durationMs: result.durationMs,
                waveform: result.waveform.isEmpty ? nil : result.waveform,
                lanes: result.lanes,
                for: result.recordingId
            )
        }
        if !attached {
            // Without these a two-lane recording is transcribed as one, and the
            // library shows no length. The row the app holds is a second way
            // to the same store; only if that fails too is the person told.
            var saved = false
            if let row = recording(result.recordingId) {
                row.applyCapturedAudio(
                    fileName: result.archiveFileName ?? "", sampleRate: result.archiveSampleRate,
                    durationMs: result.durationMs,
                    waveform: result.waveform.isEmpty ? nil : result.waveform,
                    lanes: result.lanes)
                saved = (try? context.save()) != nil
            }
            if !saved {
                warnings[result.recordingId] = [
                    warnings[result.recordingId],
                    "The length and the channels of this recording could not be saved, "
                        + "so a recording of two lanes would be transcribed as one. "
                        + "Restart the app before you use Transcribe Again.",
                ].compactMap { $0 }.joined(separator: " ")
            }
        }

        // A two-lane recording always gets the whole-file pass, even when the
        // live decoder already produced a transcript. Live decoding runs on
        // the two lanes summed -- one stream, because that is what a live
        // transcript can afford -- so what it produced has no idea which side
        // of the meeting each line came from. Only the whole-file pass reads
        // the channels apart, and it is the better transcript in any case.
        let followUp = StopFollowUp.after(
            decodedLive: decodedLive, laneCount: result.lanes.count,
            diarizes: settings.diarizationMode.performsDiarization
        )
        if quitting, let closed = followUp.closedEarly {
            // The app is going away. A job started now would die with the
            // process and leave the row claiming work that never ran, so the
            // row says what is true and the next launch offers the re-run.
            try? await writer.updateStatus(
                closed.status, progress: closed.status == .completed ? 1 : 0,
                error: closed.errorMessage, for: result.recordingId
            )
            if let note = closed.warning {
                let combined = [warnings[result.recordingId], note]
                    .compactMap { $0 }.joined(separator: " ")
                warnings[result.recordingId] = combined
                // On the row too: this process is about to end.
                try? await writer.setWarning(combined, for: result.recordingId)
            }
        } else {
            switch followUp {
            case .wholeFile:
                // Capture-only session: the whole-file pass is the transcript.
                // The working copy it needs is the one the session just wrote.
                if let stored = recording(result.recordingId) {
                    enqueueTranscription(stored, work: .full)
                }
            case .speakersOnly:
                let job = TranscriptionJob(
                    id: result.recordingId,
                    title: recording(result.recordingId)?.title ?? "Recording",
                    sourceURL: result.archiveFileName.map { Paths.recordingURL($0) },
                    cacheURL: result.cacheURL,
                    modelId: result.modelId,
                    language: result.language,
                    diarizationMode: settings.diarizationMode,
                    work: .diarizeOnly,
                    discardCacheWhenDone: !settings.keepWorkingCopy,
                    expectedSpeakers: recording(result.recordingId)?.expectedSpeakers
                )
                queuedJobs[job.id] = job
                requestedJobs[job.id] = job
                await queue.enqueue(job)
            case .finished:
                let marked = await ledger.succeeded(.status, for: result.recordingId) {
                    try await writer.updateStatus(.completed, progress: 1, for: result.recordingId)
                }
                if !marked {
                    warnings[result.recordingId] = [
                        warnings[result.recordingId],
                        "The app could not record that this finished, so it may still look "
                            + "as if it is recording. Restart the app if it does.",
                    ].compactMap { $0 }.joined(separator: " ")
                }
                // Only when the archive can stand in for it: a recording file
                // that did not close, or that holds less than the copy, leaves
                // the copy as the only audio.
                if !settings.keepWorkingCopy,
                   await WorkingCopyPolicy.canDiscard(
                       workingCopy: result.cacheURL,
                       archive: result.archiveFileName.map { Paths.recordingURL($0) }) {
                    try? FileManager.default.removeItem(at: result.cacheURL)
                }
            }
        }
        // What changed under the recording: a microphone that was unplugged
        // and replaced, a default input that moved, an input that could not
        // be restarted. Kept with the recording, because the person reading
        // the transcript tomorrow has to know why the room goes quiet at 0:41.
        // After the enqueue above, which clears the row's warning for the job
        // it starts; the job's own warnings are added to this one, not put in
        // its place.
        if !result.notices.isEmpty {
            let changes = result.notices.map(\.message).joined(separator: " ")
            let combined = [warnings[result.recordingId], changes]
                .compactMap { $0 }.joined(separator: " ")
            warnings[result.recordingId] = combined
            try? await writer.setWarning(combined, for: result.recordingId)
        }
        await queue.setLiveActive(false)

        if !quitting, result.durationMs < Self.shortTakeMs {
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
