import Foundation
import Synchronization
import TranscriberCore

public struct TranscriptionJob: Sendable, Identifiable, Equatable {
    public enum Work: Sendable, Equatable {
        /// Decode the audio, then optionally identify speakers.
        case full
        /// Audio is already transcribed -- the live path did it. Only identify
        /// speakers and stamp them onto the segments that exist.
        case diarizeOnly
    }

    public var id: UUID
    public var title: String
    /// Original audio, used to rebuild the 16 kHz working copy if it is gone.
    public var sourceURL: URL?
    public var cacheURL: URL
    public var modelId: String
    public var language: String
    public var prompt: String?
    public var diarizationMode: DiarizationMode
    public var work: Work
    /// Delete the working copy when the job finishes. True for imports and
    /// finished recordings, false while the user is likely to re-run.
    public var discardCacheWhenDone: Bool
    /// High-pass the audio before the model sees it. Read from the setting at
    /// enqueue time rather than stored on the recording, so a meeting captured
    /// in the wrong mode is fixed by toggling and transcribing again.
    public var roomMode: Bool
    /// How many people the user says were in the room. A target for speaker
    /// clustering, never a cap. Nil when nobody said.
    public var expectedSpeakers: Int?

    public init(id: UUID, title: String, sourceURL: URL?, cacheURL: URL,
                modelId: String, language: String, prompt: String? = nil,
                diarizationMode: DiarizationMode = .accurate, work: Work = .full,
                discardCacheWhenDone: Bool = true, roomMode: Bool = false,
                expectedSpeakers: Int? = nil) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.cacheURL = cacheURL
        self.modelId = modelId
        self.language = language
        self.prompt = prompt
        self.diarizationMode = diarizationMode
        self.work = work
        self.discardCacheWhenDone = discardCacheWhenDone
        self.roomMode = roomMode
        self.expectedSpeakers = expectedSpeakers
    }

    public var diarize: Bool { diarizationMode.performsDiarization }
}

/// Wall-clock measurements for one whole-file job. Stored with the transcript
/// so future optimization is based on stage costs rather than guesses.
public struct TranscriptionMetrics: Sendable, Codable, Equatable {
    public var prepareMs = 0
    public var vadMs = 0
    public var decodeMs = 0
    public var diarizeMs = 0
    public var finalizeMs = 0
    public var totalMs = 0
    public var sourceDurationMs = 0
    public var speechWindowMs = 0
    public var windowCount = 0
    public var retriedWindows = 0
    public var droppedWindows = 0

    public init() {}
}

public struct TranscriptionPayload: Sendable {
    public var segments: [Segment]
    public var roster: [SpeakerLabel]
    public var durationMs: Int
    public var processMs: Int
    public var modelId: String
    public var language: String
    public var didDiarize: Bool
    public var waveform: [Float]
    public var metrics: TranscriptionMetrics
}

public enum JobEvent: Sendable {
    case queued(id: UUID, title: String)
    case stage(id: UUID, status: TranscriptionStatus, progress: Double)
    /// The working copy is ready: how long the audio is and what it looks
    /// like, ahead of any decoding. Lets the player and the "of 3:51:08" in
    /// the progress banner work while the transcript is still arriving.
    case prepared(id: UUID, durationMs: Int, waveform: [Float])
    /// Segments from one decoded window, in file order, ahead of the final
    /// pass. `coveredMs` is how far into the audio the decode has reached.
    case partial(id: UUID, segments: [Segment], coveredMs: Int)
    case transcribed(id: UUID, payload: TranscriptionPayload)
    case diarized(id: UUID, spans: [SpeakerSpan], roster: [SpeakerLabel])
    case failed(id: UUID, message: String)
    /// The job finished, but not intact. Surfaced rather than swallowed: a
    /// transcript missing a window looks merely short.
    case warning(id: UUID, message: String)
    case finished(id: UUID)
}

/// Serial background pipeline for everything that is not the live path.
///
/// Serial on purpose. Two decodes at once on an M2 Pro do not go twice as fast;
/// they contend for the same Neural Engine and both get slower, while peak
/// memory doubles. One job at a time, and none at all while a recording is in
/// progress.
public actor TranscriptionQueue {

    /// Several decode windows per persistence event. The transcript still
    /// appears progressively, while long files stop paying for one SQLite
    /// transaction per 28 seconds of audio.
    static let partialBatchWindows = 5
    static let partialBatchSegments = 250

    private struct PartialBatch {
        var nextIndex = 0
        var pending: [Segment] = []
        var windows = 0
        var coveredMs = 0
    }

    private let engines: EngineHost
    private var pending: [TranscriptionJob] = []
    private var running: (job: TranscriptionJob, task: Task<Void, Never>)?
    private var liveActive = false

    /// `nonisolated` so the UI can start consuming without an await hop just to
    /// reach the stream. `AsyncStream` is Sendable; so is its continuation.
    public nonisolated let events: AsyncStream<JobEvent>

    /// Also `nonisolated`, so a progress closure running on whatever thread the
    /// decoder is on can report without hopping onto this actor. Each report
    /// used to be wrapped in `Task { await emit(...) }`, which allocated a task
    /// per call and -- those tasks being unordered -- let progress arrive out of
    /// sequence, so the bar could jump backwards.
    private nonisolated let sink: AsyncStream<JobEvent>.Continuation

    public init(engines: EngineHost) {
        self.engines = engines
        var continuation: AsyncStream<JobEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        sink = continuation
    }

    // MARK: - Queue control

    public var isBusy: Bool { running != nil }

    public func enqueue(_ job: TranscriptionJob) {
        guard !pending.contains(where: { $0.id == job.id }),
              running?.job.id != job.id else { return }
        pending.append(job)
        sink.yield(.queued(id: job.id, title: job.title))
        sink.yield(.stage(id: job.id, status: .pending, progress: 0))
        pump()
    }

    public func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        if running?.job.id == id {
            running?.task.cancel()
        }
    }

    /// Holds the queue while a recording runs, and releases it afterwards.
    public func setLiveActive(_ active: Bool) {
        liveActive = active
        if !active { pump() }
    }

    private func pump() {
        guard running == nil, !liveActive, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        let task = Task { [weak self] in
            await self?.run(job)
            await self?.finish(job)
        }
        running = (job, task)
    }

    private func finish(_ job: TranscriptionJob) {
        running = nil
        sink.yield(.finished(id: job.id))
        pump()
    }

    private nonisolated func emit(_ event: JobEvent) {
        sink.yield(event)
    }

    // MARK: - The pipeline

    private func run(_ job: TranscriptionJob) async {
        let started = Date()
        var metrics = TranscriptionMetrics()
        do {
            emit(.stage(id: job.id, status: .preparing, progress: 0))

            let source = try await workingCopy(for: job)
            let waveform = WaveformAnalyzer.envelope(of: source)
            let durationMs = source.durationMs
            emit(.prepared(id: job.id, durationMs: durationMs, waveform: waveform))

            // What the model is given, which is not always what was recorded.
            // The waveform stays on `source` because the user is scrubbing the
            // audio they can hear, and diarization stays on it too: the band
            // this removes carries pitch, which is a speaker cue, and there is
            // no measurement here saying the trade is worth it for embeddings.
            let heard: any PCMSource = job.roomMode ? HighPassPCM(source) : source

            if job.work == .diarizeOnly {
                try await diarizeOnly(job, source: source)
                return
            }

            // The model, which may first have to arrive. A download reports
            // as the preparing stage with a fraction; the load itself does not.
            try await engines.loadModel(job.modelId) { _, fraction in
                if let fraction {
                    self.emit(.stage(id: job.id, status: .preparing, progress: fraction))
                }
            }
            metrics.prepareMs = Int(Date().timeIntervalSince(started) * 1000)
            metrics.sourceDurationMs = durationMs

            // Decode.
            emit(.stage(id: job.id, status: .transcribing, progress: 0))
            try? await engines.prepareVAD(progress: nil)

            let vad = await engines.voiceActivity
            let asr = await engines.recognizer
            let partial = Mutex(PartialBatch())
            let onWindow: @Sendable ([Token], SpeechRegion) -> Void = { tokens, window in
                    // Segmented per window rather than over everything so far:
                    // windows end in silence, so no segment straddles two of
                    // them, and the work stays proportional to the window.
                    let emission: (segments: [Segment], coveredMs: Int)? = partial.withLock { state in
                        let segments = SegmentMerger.segments(
                            from: tokens, startingAt: state.nextIndex
                        )
                        state.nextIndex += segments.count
                        state.pending.append(contentsOf: segments)
                        state.windows += 1
                        state.coveredMs = window.endMs

                        guard state.windows >= Self.partialBatchWindows
                                || state.pending.count >= Self.partialBatchSegments
                        else { return nil }
                        state.windows = 0
                        guard !state.pending.isEmpty else { return nil }
                        let batch = state.pending
                        state.pending.removeAll(keepingCapacity: true)
                        return (batch, state.coveredMs)
                    }
                    if let emission {
                        self.emit(.partial(id: job.id, segments: emission.segments,
                                           coveredMs: emission.coveredMs))
                    }
                }
            let fileDecoded: OfflinePipeline.FileDecodeReport
            do {
                fileDecoded = try await OfflinePipeline.transcribeFile(
                    source: heard, using: vad, asr: asr,
                    language: job.language, prompt: job.prompt,
                    progress: { fraction in
                        self.emit(.stage(id: job.id, status: .transcribing,
                                         progress: fraction))
                    },
                    onWindow: onWindow
                )
            } catch {
                // Cooperative cancellation returns here cleanly, so preserve
                // the last sub-batch instead of losing up to five decoded
                // windows merely because they had not reached the DB threshold.
                let tail: (segments: [Segment], coveredMs: Int)? = partial.withLock { state in
                    guard !state.pending.isEmpty else { return nil }
                    return (state.pending, state.coveredMs)
                }
                if let tail {
                    emit(.partial(id: job.id, segments: tail.segments,
                                  coveredMs: tail.coveredMs))
                }
                throw error
            }
            let regions = fileDecoded.regions
            let decoded = fileDecoded.decode
            metrics.vadMs = fileDecoded.vadMs
            metrics.decodeMs = fileDecoded.decodeMs
            metrics.windowCount = fileDecoded.windowCount
            metrics.speechWindowMs = fileDecoded.speechWindowMs
            metrics.retriedWindows = decoded.retriedWindows
            metrics.droppedWindows = decoded.droppedWindows
            if fileDecoded.windowCount == 0, durationMs > 0 {
                // Zero windows means VAD heard nothing anywhere -- which is
                // either a genuinely silent file or a misfiring detector.
                emit(.warning(id: job.id, message:
                    "No speech was detected anywhere in this audio, so the "
                    + "transcript is empty. If the recording is not silent, "
                    + "try transcribing again."))
            }
            let tail: (segments: [Segment], coveredMs: Int)? = partial.withLock { state in
                guard !state.pending.isEmpty else { return nil }
                let batch = state.pending
                state.pending.removeAll()
                return (batch, state.coveredMs)
            }
            if let tail {
                emit(.partial(id: job.id, segments: tail.segments, coveredMs: tail.coveredMs))
            }
            try Task.checkCancellation()
            if decoded.droppedWindows > 0 {
                emit(.warning(id: job.id, message:
                    "\(decoded.droppedWindows) window\(decoded.droppedWindows == 1 ? "" : "s") "
                    + "of speech could not be decoded and are missing from this transcript."))
            }

            // Identify speakers.
            var spans: [SpeakerSpan] = []
            var roster: [SpeakerLabel] = []
            var didDiarize = false
            if job.diarize {
                emit(.stage(id: job.id, status: .diarizing, progress: 0))
                let diarizeStarted = Date()
                do {
                    let raw: [SpeakerSpan]
                    if job.expectedSpeakers == 1 {
                        raw = [SpeakerSpan(speakerId: "S1", startMs: 0,
                                           endMs: durationMs, quality: 1)]
                        emit(.stage(id: job.id, status: .diarizing, progress: 1))
                    } else {
                        try await engines.prepareDiarizer(progress: nil)
                        raw = try await engines.diarize(
                            source, speechRegions: regions, mode: job.diarizationMode,
                            expectedSpeakers: job.expectedSpeakers
                        ) { fraction in
                            self.emit(.stage(id: job.id, status: .diarizing,
                                             progress: fraction))
                        }
                    }
                    let normalized = SegmentMerger.normalize(raw)
                    spans = normalized.spans
                    roster = normalized.roster
                    didDiarize = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A transcript without speaker labels is still a transcript.
                    // Losing the whole job over diarization would be worse --
                    // but silence is worse still: unlabelled segments render
                    // identically to a genuine one-speaker recording, so the
                    // user has to be told the labels are missing, not absent.
                    emit(.warning(id: job.id, message:
                        "Speaker identification failed: \(error.localizedDescription) "
                        + "The transcript is complete but has no speaker labels."))
                    emit(.stage(id: job.id, status: .finalizing, progress: 0))
                }
                await engines.releaseDiarizer()
                metrics.diarizeMs = Int(Date().timeIntervalSince(diarizeStarted) * 1000)
            }

            emit(.stage(id: job.id, status: .finalizing, progress: 0.5))
            let finalizeStarted = Date()
            let segments = SegmentMerger.segments(from: decoded.tokens, spans: spans)
            metrics.finalizeMs = Int(Date().timeIntervalSince(finalizeStarted) * 1000)
            metrics.totalMs = Int(Date().timeIntervalSince(started) * 1000)

            emit(.transcribed(id: job.id, payload: TranscriptionPayload(
                segments: segments,
                roster: roster,
                durationMs: durationMs,
                processMs: metrics.totalMs,
                modelId: job.modelId,
                language: decoded.detectedLanguage ?? job.language,
                didDiarize: didDiarize,
                waveform: waveform,
                metrics: metrics
            )))
            emit(.stage(id: job.id, status: .completed, progress: 1))
            if job.discardCacheWhenDone { try? FileManager.default.removeItem(at: job.cacheURL) }
        } catch is CancellationError {
            emit(.stage(id: job.id, status: .pending, progress: 0))
        } catch {
            emit(.failed(id: job.id, message: error.localizedDescription))
            emit(.stage(id: job.id, status: .failed, progress: 0))
        }
    }

    private func diarizeOnly(_ job: TranscriptionJob, source: MappedPCM) async throws {
        guard job.diarize else {
            emit(.stage(id: job.id, status: .completed, progress: 1))
            return
        }
        emit(.stage(id: job.id, status: .diarizing, progress: 0))
        do {
            let raw: [SpeakerSpan]
            if job.expectedSpeakers == 1 {
                raw = [SpeakerSpan(speakerId: "S1", startMs: 0,
                                   endMs: source.durationMs, quality: 1)]
                emit(.stage(id: job.id, status: .diarizing, progress: 1))
            } else {
                // A diarize-only job has no regions left from transcription,
                // so make the cheap VAD pass once and use it to avoid sending
                // long silences through both speaker models.
                try? await engines.prepareVAD(progress: nil)
                let vad = await engines.voiceActivity
                let regions = try await OfflinePipeline.speechRegions(in: source, using: vad)
                try await engines.prepareDiarizer(progress: nil)
                raw = try await engines.diarize(
                    source, speechRegions: regions, mode: job.diarizationMode,
                    expectedSpeakers: job.expectedSpeakers
                ) { fraction in
                    self.emit(.stage(id: job.id, status: .diarizing, progress: fraction))
                }
            }
            let normalized = SegmentMerger.normalize(raw)
            emit(.diarized(id: job.id, spans: normalized.spans, roster: normalized.roster))
            emit(.stage(id: job.id, status: .completed, progress: 1))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The live path already produced the transcript; only the speaker
            // pass failed. A warning on a completed job says exactly that --
            // emitting .failed here raised a "Transcription failed" alert for
            // a recording the same breath marked completed.
            emit(.warning(id: job.id, message:
                "Speaker identification failed: \(error.localizedDescription) "
                + "The transcript is complete but has no speaker labels."))
            emit(.stage(id: job.id, status: .completed, progress: 1))
        }
        await engines.releaseDiarizer()
        if job.discardCacheWhenDone { try? FileManager.default.removeItem(at: job.cacheURL) }
    }

    /// The 16 kHz working copy, rebuilt from the original if it has been
    /// cleaned up since the recording was made.
    private func workingCopy(for job: TranscriptionJob) async throws -> MappedPCM {
        if FileManager.default.fileExists(atPath: job.cacheURL.path),
           let mapped = try? MappedPCM(contentsOf: job.cacheURL), mapped.sampleCount > 0 {
            return mapped
        }
        guard let sourceURL = job.sourceURL else {
            throw EngineError.audioUnreadable("no audio to work from")
        }
        _ = try await AudioCache.build(from: sourceURL, to: job.cacheURL) { fraction in
            self.emit(.stage(id: job.id, status: .preparing, progress: fraction))
        }
        return try MappedPCM(contentsOf: job.cacheURL)
    }
}
