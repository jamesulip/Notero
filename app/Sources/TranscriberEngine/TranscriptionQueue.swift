import Foundation
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
    public var diarize: Bool
    public var work: Work
    /// Delete the working copy when the job finishes. True for imports and
    /// finished recordings, false while the user is likely to re-run.
    public var discardCacheWhenDone: Bool
    /// High-pass the audio before the model sees it. Read from the setting at
    /// enqueue time rather than stored on the recording, so a meeting captured
    /// in the wrong mode is fixed by toggling and transcribing again.
    public var roomMode: Bool

    public init(id: UUID, title: String, sourceURL: URL?, cacheURL: URL,
                modelId: String, language: String, prompt: String? = nil,
                diarize: Bool = true, work: Work = .full,
                discardCacheWhenDone: Bool = true, roomMode: Bool = false) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.cacheURL = cacheURL
        self.modelId = modelId
        self.language = language
        self.prompt = prompt
        self.diarize = diarize
        self.work = work
        self.discardCacheWhenDone = discardCacheWhenDone
        self.roomMode = roomMode
    }
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
}

public enum JobEvent: Sendable {
    case queued(id: UUID, title: String)
    case stage(id: UUID, status: TranscriptionStatus, progress: Double)
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

    private let engines: EngineHost
    private var pending: [TranscriptionJob] = []
    private var running: (job: TranscriptionJob, task: Task<Void, Never>)?
    private var continuation: AsyncStream<JobEvent>.Continuation?
    private var liveActive = false

    /// `nonisolated` so the UI can start consuming without an await hop just to
    /// reach the stream. `AsyncStream` is Sendable; the continuation stays inside.
    public nonisolated let events: AsyncStream<JobEvent>

    public init(engines: EngineHost) {
        self.engines = engines
        var sink: AsyncStream<JobEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { sink = $0 }
        continuation = sink
    }

    // MARK: - Queue control

    public var queuedCount: Int { pending.count }
    public var activeJob: TranscriptionJob? { running?.job }
    public var isBusy: Bool { running != nil }

    public func enqueue(_ job: TranscriptionJob) {
        guard !pending.contains(where: { $0.id == job.id }),
              running?.job.id != job.id else { return }
        pending.append(job)
        continuation?.yield(.queued(id: job.id, title: job.title))
        continuation?.yield(.stage(id: job.id, status: .pending, progress: 0))
        pump()
    }

    public func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        if running?.job.id == id {
            running?.task.cancel()
        }
    }

    public func cancelAll() {
        pending.removeAll()
        running?.task.cancel()
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
        continuation?.yield(.finished(id: job.id))
        pump()
    }

    private func emit(_ event: JobEvent) {
        continuation?.yield(event)
    }

    // MARK: - The pipeline

    private func run(_ job: TranscriptionJob) async {
        let started = Date()
        do {
            emit(.stage(id: job.id, status: .preparing, progress: 0))

            let source = try await workingCopy(for: job)
            let waveform = WaveformAnalyzer.envelope(of: source)
            let durationMs = source.durationMs

            // What the model is given, which is not always what was recorded.
            // The waveform stays on `source` because the user is scrubbing the
            // audio they can hear, and diarization stays on it too: the band
            // this removes carries pitch, which is a speaker cue, and there is
            // no measurement here saying the trade is worth it for embeddings.
            let heard: any PCMSource = job.roomMode ? HighPassPCM(source) : source

            if job.work == .diarizeOnly {
                try await diarizeOnly(job, source: source, durationMs: durationMs)
                return
            }

            // Decode.
            emit(.stage(id: job.id, status: .transcribing, progress: 0))
            try await engines.loadModel(job.modelId)
            try? await engines.prepareVAD(progress: nil)

            let vad = await engines.voiceActivity
            let asr = await engines.recognizer
            let regions = try await OfflinePipeline.speechRegions(in: heard, using: vad) { fraction in
                Task { await self.emit(.stage(id: job.id, status: .transcribing,
                                              progress: fraction * 0.1)) }
            }
            let windows = OfflinePipeline.windows(for: regions, durationMs: durationMs)
            if windows.isEmpty, durationMs > 0 {
                // Zero windows means VAD heard nothing anywhere -- which is
                // either a genuinely silent file or a misfiring detector (the
                // energy fallback's fixed threshold on a quiet recording).
                // Without this, the job completes with a green checkmark and
                // an empty transcript, indistinguishable from success.
                emit(.warning(id: job.id, message:
                    "No speech was detected anywhere in this audio, so the "
                    + "transcript is empty. If the recording is not silent, "
                    + "try transcribing again."))
            }

            let decoded = try await OfflinePipeline.transcribe(
                source: heard, windows: windows, using: asr,
                language: job.language, prompt: job.prompt
            ) { fraction in
                Task { await self.emit(.stage(id: job.id, status: .transcribing,
                                              progress: 0.1 + fraction * 0.9)) }
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
                do {
                    try await engines.prepareDiarizer(progress: nil)
                    let raw = try await engines.diarize(source) { fraction in
                        Task { await self.emit(.stage(id: job.id, status: .diarizing,
                                                      progress: fraction)) }
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
            }

            emit(.stage(id: job.id, status: .finalizing, progress: 0.5))
            let segments = SegmentMerger.segments(from: decoded.tokens, spans: spans)

            emit(.transcribed(id: job.id, payload: TranscriptionPayload(
                segments: segments,
                roster: roster,
                durationMs: durationMs,
                processMs: Int(Date().timeIntervalSince(started) * 1000),
                modelId: job.modelId,
                language: decoded.detectedLanguage ?? job.language,
                didDiarize: didDiarize,
                waveform: waveform
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

    private func diarizeOnly(_ job: TranscriptionJob, source: MappedPCM,
                             durationMs: Int) async throws {
        guard job.diarize else {
            emit(.stage(id: job.id, status: .completed, progress: 1))
            return
        }
        emit(.stage(id: job.id, status: .diarizing, progress: 0))
        do {
            try await engines.prepareDiarizer(progress: nil)
            let raw = try await engines.diarize(source) { fraction in
                Task { await self.emit(.stage(id: job.id, status: .diarizing, progress: fraction)) }
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
            Task { await self.emit(.stage(id: job.id, status: .preparing, progress: fraction)) }
        }
        return try MappedPCM(contentsOf: job.cacheURL)
    }
}
