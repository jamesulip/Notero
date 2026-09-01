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

    public func updateDuration(_ durationMs: Int, for id: UUID) throws {
        guard let recording = try find(id) else { return }
        recording.durationMs = durationMs
        try modelContext.save()
    }

    public func attachAudio(fileName: String, sampleRate: Int, durationMs: Int,
                            waveform: [Float]?, for id: UUID) throws {
        guard let recording = try find(id), !fileName.isEmpty else { return }
        recording.audioFileName = fileName
        if sampleRate > 0 { recording.audioSampleRate = sampleRate }
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

    public func setWaveform(_ waveform: [Float], for id: UUID) throws {
        guard let recording = try find(id) else { return }
        recording.waveform = waveform
        try modelContext.save()
    }

    public func setTitle(_ title: String, for id: UUID) throws {
        guard let recording = try find(id) else { return }
        recording.title = title
        recording.updatedAt = Date()
        RecordingStore.reindexOffMain(recording)
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
        language: String, processMs: Int, didDiarize: Bool, for id: UUID
    ) throws -> Int {
        guard let recording = try find(id) else { return 0 }

        let revision = ((recording.transcripts ?? []).map(\.revision).max() ?? 0) + 1
        let transcript = StoredTranscript(revision: revision, modelId: modelId,
                                          language: language)
        transcript.processMs = processMs
        transcript.didDiarize = didDiarize
        transcript.recording = recording
        modelContext.insert(transcript)

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

        syncSpeakers(roster, on: recording)
        recording.updatedAt = Date()
        RecordingStore.reindexOffMain(recording)
        try modelContext.save()
        return revision
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
        syncSpeakers(roster, on: recording)
        recording.updatedAt = Date()
        try modelContext.save()
    }

    private func syncSpeakers(_ roster: [SpeakerLabel], on recording: StoredRecording) {
        var existing = Dictionary(
            (recording.speakers ?? []).map { ($0.speakerId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (offset, label) in roster.enumerated() {
            if let row = existing.removeValue(forKey: label.id) {
                row.speechMs = label.speechMs
                row.colorIndex = offset
            } else {
                let row = StoredSpeaker(speakerId: label.id,
                                        displayName: label.displayName,
                                        speechMs: label.speechMs,
                                        colorIndex: offset)
                row.recording = recording
                modelContext.insert(row)
            }
        }
        for orphan in existing.values { modelContext.delete(orphan) }
    }

    private func find(_ id: UUID) throws -> StoredRecording? {
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

extension RecordingStore {
    /// The same flattening as `reindex`, callable from the writer actor.
    ///
    /// `RecordingStore` is main-actor because it is the UI's entry point; the
    /// background writer needs this one operation and nothing else from it.
    nonisolated static func reindexOffMain(_ recording: StoredRecording) {
        var parts = [recording.title, recording.summary, recording.body]
        parts.append(contentsOf: (recording.transcript?.orderedSegments ?? []).map(\.displayText))
        parts.append(contentsOf: (recording.items ?? []).map(\.text))
        parts.append(contentsOf: (recording.bookmarks ?? []).map(\.label))
        recording.searchText = parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
