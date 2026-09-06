import Foundation
import SwiftData
import TranscriberCore

/// Writes transcription results off the main actor.
///
/// A `@ModelActor` owns its own `ModelContext`, so a two-hour transcript can be
/// inserted a few thousand rows at a time without the UI waiting on it.
/// SwiftData merges the change into the main context and the views update.
@ModelActor
public actor TranscriptWriter {

    public func updateStatus(_ status: TranscriptionStatus, progress: Double = 0,
                             error: String? = nil, for id: UUID) throws {
        guard let recording = try find(id) else { return }
        recording.status = status
        recording.progress = progress
        recording.errorMessage = error
        recording.updatedAt = Date()
        try modelContext.save()
    }

    /// Records that the job finished imperfectly. Nil clears it, which a new
    /// job does before it starts.
    public func setWarning(_ message: String?, for id: UUID) throws {
        guard let recording = try find(id) else { return }
        recording.warningMessage = message
        try modelContext.save()
    }

    public func attachAudio(fileName: String, sampleRate: Int, durationMs: Int,
                            waveform: [Float]?, lanes: [CaptureLane] = [.room],
                            for id: UUID) throws {
        guard let recording = try find(id), !fileName.isEmpty else { return }
        recording.audioFileName = fileName
        if sampleRate > 0 { recording.audioSampleRate = sampleRate }
        if !lanes.isEmpty { recording.lanes = lanes }
        recording.durationMs = durationMs
        if let waveform { recording.waveform = waveform }
        recording.updatedAt = Date()
        try modelContext.save()
    }

    /// What a finished transcription knows: how long the audio turned out to
    /// be, and what it looks like. Deliberately not `attachAudio`: the file
    /// name and sample rate belong to whoever wrote the file, and a
    /// transcription pass must not be able to overwrite them.
    public func finishTranscription(durationMs: Int, waveform: [Float]?,
                                    for id: UUID) throws {
        guard let recording = try find(id) else { return }
        if durationMs > 0 { recording.durationMs = durationMs }
        if let waveform, !waveform.isEmpty { recording.waveform = waveform }
        recording.updatedAt = Date()
        try modelContext.save()
    }

    /// Replaces the transcript with a new revision.
    ///
    /// A revision rather than an edit: notes and action items hold segment ids,
    /// and re-transcribing with a different model would otherwise silently
    /// break every back-link the user made.
    @discardableResult
    public func storeTranscript(
        segments: [Segment], roster: [SpeakerLabel], modelId: String,
        language: String, processMs: Int, didDiarize: Bool,
        performanceJSON: String? = nil, for id: UUID
    ) throws -> Int {
        guard let recording = try find(id) else { return 0 }

        let revision = ((recording.transcripts ?? []).map(\.revision).max() ?? 0) + 1
        let transcript = StoredTranscript(revision: revision, modelId: modelId,
                                          language: language)
        transcript.processMs = processMs
        transcript.performanceJSON = performanceJSON
        transcript.didDiarize = didDiarize
        transcript.recording = recording
        modelContext.insert(transcript)
        insert(segments, into: transcript)

        SpeakerSync.apply(roster, to: recording, in: modelContext)
        recording.updatedAt = Date()
        SearchIndex.rebuild(recording)
        try modelContext.save()
        return revision
    }

    // MARK: - Progressive transcription

    /// Starts a revision that segments will be appended to while the job
    /// decodes. Returns its id; `appendPartial` and `completeTranscript` take
    /// it back, so a second job on the same recording can never append to the
    /// first job's revision.
    public func openPartialTranscript(modelId: String, language: String,
                                      for id: UUID) throws -> UUID? {
        guard let recording = try find(id) else { return nil }
        let revision = ((recording.transcripts ?? []).map(\.revision).max() ?? 0) + 1
        let transcript = StoredTranscript(revision: revision, modelId: modelId,
                                          language: language)
        transcript.isComplete = false
        transcript.recording = recording
        modelContext.insert(transcript)
        recording.updatedAt = Date()
        try modelContext.save()
        return transcript.id
    }

    /// One decoded window's worth of segments.
    ///
    /// No reindex here: the search text is rebuilt once at completion. Doing it
    /// per batch would walk every segment so far on every window.
    public func appendPartial(_ segments: [Segment], to transcriptId: UUID) throws {
        guard !segments.isEmpty, let transcript = try findTranscript(transcriptId) else { return }
        insert(segments, into: transcript)
        try modelContext.save()
    }

    /// Finishes a progressive transcript with the final segmentation.
    ///
    /// The final pass has the speaker spans and cuts segments at turns, which
    /// the partial rows could not. So the partial rows are replaced, not kept:
    /// a note lifted from a row during processing degrades to "no source" the
    /// same way it does after a re-transcription. With no open revision
    /// (nothing was decoded, or the job predates this path) it stores a new
    /// one as `storeTranscript` does.
    @discardableResult
    public func completeTranscript(
        _ transcriptId: UUID?, segments: [Segment], roster: [SpeakerLabel],
        modelId: String, language: String, processMs: Int, didDiarize: Bool,
        performanceJSON: String? = nil,
        for id: UUID
    ) throws -> Int {
        guard let transcriptId,
              let transcript = try findTranscript(transcriptId),
              let recording = transcript.recording
        else {
            return try storeTranscript(segments: segments, roster: roster, modelId: modelId,
                                       language: language, processMs: processMs,
                                       didDiarize: didDiarize,
                                       performanceJSON: performanceJSON, for: id)
        }

        for row in transcript.segments ?? [] { modelContext.delete(row) }
        // Saved before the inserts, so the relationship the reindex walks
        // holds only the final rows.
        try modelContext.save()

        insert(segments, into: transcript)
        transcript.modelId = modelId
        transcript.language = language
        transcript.processMs = processMs
        transcript.performanceJSON = performanceJSON
        transcript.didDiarize = didDiarize
        transcript.isComplete = true

        SpeakerSync.apply(roster, to: recording, in: modelContext)
        recording.updatedAt = Date()
        SearchIndex.rebuild(recording)
        try modelContext.save()
        return transcript.revision
    }

    /// Replaces the rows of the latest transcript that start inside a range
    /// with new rows, in place. For one turn decoded again on another model:
    /// a new revision for forty seconds of a four-hour meeting would copy
    /// every row and break every note that points at one.
    ///
    /// The rows are renumbered afterwards, so `index` stays the order.
    /// Returns how many rows went out.
    @discardableResult
    public func replaceSegments(fromMs: Int, toMs: Int, with segments: [Segment],
                                for id: UUID) throws -> Int {
        guard let recording = try find(id), let transcript = recording.transcript else { return 0 }
        let rows = try TranscriptReader.segmentRows(ofTranscript: transcript.id, in: modelContext)
        var removed = 0
        for row in rows where row.startMs >= fromMs && row.startMs < toMs {
            modelContext.delete(row)
            removed += 1
        }
        // Saved before the inserts, so the renumbering below walks only the
        // rows that stay.
        try modelContext.save()
        insert(segments, into: transcript)
        for (index, row) in try TranscriptReader.segmentRows(ofTranscript: transcript.id,
                                                              in: modelContext).enumerated() {
            row.index = index
        }
        recording.updatedAt = Date()
        SearchIndex.rebuild(recording)
        try modelContext.save()
        return removed
    }

    private func insert(_ segments: [Segment], into transcript: StoredTranscript) {
        for segment in segments {
            let row = StoredSegment(
                id: segment.id, index: segment.index, startMs: segment.startMs,
                endMs: segment.endMs, text: segment.text,
                textClean: segment.textClean, speakerId: segment.speakerId,
                confidence: segment.confidence
            )
            row.transcript = transcript
            modelContext.insert(row)
        }
    }

    private func findTranscript(_ id: UUID) throws -> StoredTranscript? {
        var descriptor = FetchDescriptor<StoredTranscript>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Stamps speakers onto an existing transcript after diarization finishes.
    public func applySpeakers(spans: [SpeakerSpan], roster: [SpeakerLabel],
                              policy: SegmentPolicy = .default, for id: UUID) throws {
        guard let recording = try find(id), let transcript = recording.transcript else { return }
        let sorted = spans.sorted { $0.startMs < $1.startMs }
        for row in transcript.orderedSegments {
            row.speakerId = SegmentMerger.dominantSpeaker(
                startMs: row.startMs, endMs: row.endMs,
                spans: sorted, minShare: policy.minSpeakerShare
            )?.speakerId
        }
        transcript.didDiarize = true
        SpeakerSync.apply(roster, to: recording, in: modelContext)
        recording.updatedAt = Date()
        try modelContext.save()
    }

    private func find(_ id: UUID) throws -> StoredRecording? {
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
