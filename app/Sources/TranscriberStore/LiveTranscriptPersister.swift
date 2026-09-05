import Foundation
import TranscriberCore

/// Writes committed live segments to the store while the recording is still
/// going, so a crash loses the provisional tail and nothing else.
///
/// Committed text never changes -- that is the live path's contract -- which
/// is what makes an append-only write safe here. Partial text is never
/// written; it is rewritten every pass and belongs on screen only.
///
/// The audio and decode path only ever appends to an array. Everything that
/// touches SQLite happens on the writer actor, one batch at a time, at most
/// once per `flushIntervalMs`: the lesson from the whole-file path is that a
/// save per segment is thousands of transactions for a number nobody reads
/// back. At Stop, `complete` replaces the partial rows with the final list
/// through the same call the whole-file job uses, so the transcript that
/// results is indistinguishable from one written all at once.
@MainActor
public final class LiveTranscriptPersister {

    public static let defaultFlushIntervalMs = 1_000

    private let writer: TranscriptWriter
    private let recordingId: UUID
    private let modelId: String
    private let language: String
    private let flushIntervalMs: Int

    /// The open revision. Nil until `open()` succeeds; `complete` copes with
    /// nil by storing a fresh revision, exactly as a job that decoded no
    /// windows does.
    public private(set) var transcriptId: UUID?
    /// Batches written and batches that failed. A failed batch is not
    /// retried: Stop writes the whole transcript regardless, so the worst
    /// case is a row missing between a crash and that Stop.
    public private(set) var writes = 0
    public private(set) var failedWrites = 0

    private var pending: [Segment] = []
    private var flushTask: Task<Void, Never>?
    private var closed = false

    public init(writer: TranscriptWriter, recordingId: UUID, modelId: String,
                language: String, flushIntervalMs: Int = defaultFlushIntervalMs) {
        self.writer = writer
        self.recordingId = recordingId
        self.modelId = modelId
        self.language = language
        self.flushIntervalMs = max(0, flushIntervalMs)
    }

    /// Opens the revision segments will be appended to.
    public func open() async {
        guard transcriptId == nil, !closed else { return }
        transcriptId = try? await writer.openPartialTranscript(
            modelId: modelId, language: language, for: recordingId
        )
    }

    /// Queues segments for the next flush. Returns at once.
    public func append(_ segments: [Segment]) {
        guard !closed, !segments.isEmpty else { return }
        pending.append(contentsOf: segments)
        scheduleFlush()
    }

    /// Waits until everything queued so far is on disk.
    public func drain() async {
        while let task = flushTask {
            await task.value
        }
        await flushPending()
    }

    /// Finishes the revision with the final segmentation, replacing the
    /// partial rows. Anything still queued is written first so the order of
    /// operations on the row set is the same as the whole-file job's.
    @discardableResult
    public func complete(segments: [Segment], processMs: Int,
                         didDiarize: Bool = false) async throws -> Int {
        closed = true
        // The coalescing sleep is what a flush is usually waiting on; nobody
        // stopping a recording should wait a second for it.
        flushTask?.cancel()
        await drain()
        pending = []
        return try await writer.completeTranscript(
            transcriptId, segments: segments, roster: [], modelId: modelId,
            language: language, processMs: processMs, didDiarize: didDiarize,
            for: recordingId
        )
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            if flushIntervalMs > 0 {
                try? await Task.sleep(for: .milliseconds(flushIntervalMs))
            }
            await flushPending()
            flushTask = nil
            if !pending.isEmpty { scheduleFlush() }
        }
    }

    private func flushPending() async {
        guard !pending.isEmpty else { return }
        guard let transcriptId else {
            // No revision to append to: `open()` failed or never ran. Stop
            // writes the whole transcript regardless, so the queue is dropped
            // rather than rescheduled forever.
            pending = []
            return
        }
        let batch = pending
        pending = []
        do {
            try await writer.appendPartial(batch, to: transcriptId)
            writes += 1
        } catch {
            failedWrites += 1
        }
    }
}
