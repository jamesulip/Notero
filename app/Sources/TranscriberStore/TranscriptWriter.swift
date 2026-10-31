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
        guard let recording = try find(id) else { return }
        recording.applyCapturedAudio(fileName: fileName, sampleRate: sampleRate,
                                     durationMs: durationMs, waveform: waveform, lanes: lanes)
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

        syncSpeakers(roster, on: recording)
        recording.updatedAt = Date()
        RecordingStore.reindexOffMain(recording)
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
    ///
    /// The order is what keeps the transcript safe. The final rows are saved,
    /// complete, as the newest revision *beside* the open one, in one save.
    /// Only then does the open revision go. The old order deleted the partial
    /// rows and saved, then inserted the final rows and saved again, and a
    /// quit, a crash or a failed second save (a full disk, say) between the
    /// two left a transcript with nothing in it while the live rows were gone.
    /// Deleting by relationship also made the delete's save cost grow with the
    /// square of the rows (159 s for 15,000 rows, a six-hour meeting), where
    /// deleting by predicate costs 50 ms (finding 16).
    ///
    /// If the cleanup after the final save fails, the open revision stays as
    /// an older revision. That is clutter and not a loss.
    @discardableResult
    public func completeTranscript(
        _ transcriptId: UUID?, segments: [Segment], roster: [SpeakerLabel],
        modelId: String, language: String, processMs: Int, didDiarize: Bool,
        performanceJSON: String? = nil,
        for id: UUID
    ) throws -> Int {
        guard let transcriptId,
              let open = try findTranscript(transcriptId),
              let recording = open.recording
        else {
            return try storeTranscript(segments: segments, roster: roster, modelId: modelId,
                                       language: language, processMs: processMs,
                                       didDiarize: didDiarize,
                                       performanceJSON: performanceJSON, for: id)
        }

        let openRevision = open.revision
        let openId = open.id
        let final = StoredTranscript(
            revision: ((recording.transcripts ?? []).map(\.revision).max() ?? 0) + 1,
            modelId: modelId, language: language
        )
        final.processMs = processMs
        final.performanceJSON = performanceJSON
        final.didDiarize = didDiarize
        final.isComplete = true
        modelContext.insert(final)
        final.recording = recording
        insert(segments, into: final)

        syncSpeakers(roster, on: recording)
        recording.updatedAt = Date()
        RecordingStore.reindexOffMain(recording)
        try modelContext.save()

        // The final rows are safe. Now the partial ones go: by predicate, which
        // is one statement where a delete of each row is a walk of the
        // relationship for each row.
        do {
            try modelContext.delete(model: StoredSegment.self,
                                    where: #Predicate { $0.transcript?.id == openId })
            if let stale = try findTranscript(openId) { modelContext.delete(stale) }
            final.revision = openRevision
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
        return final.revision
    }

    /// Replaces the rows of the latest transcript that start inside a range
    /// with new rows, in place. For one turn decoded again on another model:
    /// a new revision for forty seconds of a four-hour meeting would copy
    /// every row and break every note that points at one.
    ///
    /// The rows are renumbered afterwards, so `index` stays the order.
    /// Returns how many rows went out.
    ///
    /// One save for the delete, the insert and the renumbering. Saving the
    /// delete first meant that a failure before the second save left the turn
    /// out of the transcript altogether, with the old text already gone.
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
        insert(segments, into: transcript)
        // The rows that stay and the rows that arrived, in time order. A row
        // that is only marked for deletion still comes back from a fetch.
        let kept = try TranscriptReader.segmentRows(ofTranscript: transcript.id, in: modelContext)
            .filter { !$0.isDeleted }
        for (index, row) in kept.enumerated() where row.index != index {
            row.index = index
        }
        recording.updatedAt = Date()
        RecordingStore.reindexOffMain(recording)
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
            // Inserted before it is linked. Linking an unmanaged row first
            // makes SwiftData update the transcript's `segments` for every
            // row already in it, so a batch of 250 took 4.5 s with 4000 rows
            // saved and the whole job grew quadratically; the other order
            // costs 35 ms for the same batch (finding 16).
            modelContext.insert(row)
            row.transcript = transcript
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
    ///
    /// A pass that found nothing (no spans and no roster) changes nothing and
    /// answers false. Applied literally it took the label off every line and
    /// deleted every name that a person had typed, and the only thing that had
    /// happened was that the voice detector found no speech.
    @discardableResult
    public func applySpeakers(spans: [SpeakerSpan], roster: [SpeakerLabel],
                              policy: SegmentPolicy = .default, for id: UUID) throws -> Bool {
        guard let recording = try find(id), let transcript = recording.transcript else { return false }
        guard !spans.isEmpty || !roster.isEmpty else { return false }
        // Labels are numbered by who speaks first, which can differ between two
        // runs over the same audio. Match the new speakers to the ones already
        // on the transcript so a name and a colour follow the voice, not the
        // number (see `SpeakerMatching`).
        let rows = transcript.orderedSegments
        let plan = speakerCarryPlan(rows: rows, recording: recording, spans: spans, roster: roster)
        let sorted = plan.relabel(spans).sorted { $0.startMs < $1.startMs }
        for row in rows {
            row.speakerId = SegmentMerger.dominantSpeaker(
                startMs: row.startMs, endMs: row.endMs,
                spans: sorted, minShare: policy.minSpeakerShare
            )?.speakerId
        }
        transcript.didDiarize = true
        syncSpeakers(plan.relabel(roster), on: recording)
        restoreColours(plan, on: recording)
        recording.updatedAt = Date()
        try modelContext.save()
        return true
    }

    /// Makes the roster rows match what the transcript uses, and leaves the
    /// names a person chose alone.
    ///
    /// An empty roster means no speaker identification ran (it is off in
    /// Settings, or a live transcript is being finished and identifies later),
    /// which says nothing about who was in the room. It used to delete every
    /// row, and Transcribe Again with identification off took every name with
    /// it, while the earlier revision still pointed at those labels.
    private func syncSpeakers(_ roster: [SpeakerLabel], on recording: StoredRecording) {
        guard !roster.isEmpty else { return }
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

extension StoredRecording {
    /// What a finished capture says about its file: the name, the rate, how
    /// long it ran, what it looks like and which lane each channel holds.
    ///
    /// One function for the writer and for the app's second try on the main
    /// context. When the writer failed, the lanes were left at their default,
    /// a single room channel, and a two-lane recording was then transcribed as
    /// one.
    public func applyCapturedAudio(fileName: String, sampleRate: Int, durationMs: Int,
                                   waveform: [Float]?, lanes: [CaptureLane]) {
        guard !fileName.isEmpty else { return }
        audioFileName = fileName
        if sampleRate > 0 { audioSampleRate = sampleRate }
        if !lanes.isEmpty { self.lanes = lanes }
        self.durationMs = durationMs
        if let waveform { self.waveform = waveform }
        updatedAt = Date()
    }
}
