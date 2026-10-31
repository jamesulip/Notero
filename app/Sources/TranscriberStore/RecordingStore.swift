import Foundation
import SwiftData
import TranscriberCore

/// Reads and writes the recording graph from the UI.
///
/// Free functions over a context rather than an object owning one: SwiftData
/// hands views their context through the environment, and a second one would
/// mean two identity maps for the same rows.
@MainActor
public enum RecordingStore {

    // MARK: - Creating

    @discardableResult
    public static func create(
        kind: RecordingKind, title: String? = nil, in context: ModelContext,
        at date: Date = Date()
    ) throws -> StoredRecording {
        let recording = StoredRecording(
            title: title ?? defaultTitle(for: kind, at: date),
            kind: kind,
            createdAt: date
        )
        recording.status = kind == .note ? .completed : .pending
        context.insert(recording)
        try context.save()
        return recording
    }

    public static func defaultTitle(for kind: RecordingKind, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        return "\(kind.label) \(formatter.string(from: date))"
    }

    // MARK: - Deleting

    /// Removes the row and the audio behind it.
    ///
    /// The file is deleted first: a cascade that succeeds while the unlink
    /// fails leaves an orphan nothing will ever reference again, and those
    /// accumulate at ~115 MB an hour.
    public static func delete(_ recording: StoredRecording, in context: ModelContext) throws {
        if let url = recording.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        context.delete(recording)
        try context.save()
    }

    // MARK: - Seeing another context's save

    /// Brings the main context's copy of one recording up to date with what the
    /// writer has saved, now.
    ///
    /// A row held on the main context does not see another context's save until
    /// the main context fetches it: measured, 0 of 40 held rows were current after
    /// `await writer.updateStatus(...)`, however long the main actor waited, and 40
    /// of 40 after a fetch. A `@Query` that is on screen does the fetch itself, a few
    /// milliseconds after the save (at most 11 ms in 180 saves), so a view catches up
    /// without help; what this closes is the gap between the writer returning and
    /// that fetch, which was zero when the writer ran on the main thread and is not
    /// now (finding 32). Called before the app tells a view to re-read, so that the
    /// view reads the rows that were saved and not the ones before.
    ///
    /// Three small fetches, none of them of the segments: the recording, its
    /// transcripts (a transcript is its own object, and `completeTranscript`
    /// replaces one) and its speakers.
    public static func refresh(_ id: UUID, in context: ModelContext) {
        var recording = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        recording.fetchLimit = 1
        _ = try? context.fetch(recording)
        _ = try? context.fetch(FetchDescriptor<StoredTranscript>(
            predicate: #Predicate { $0.recording?.id == id }))
        _ = try? context.fetch(FetchDescriptor<StoredSpeaker>(
            predicate: #Predicate { $0.recording?.id == id }))
    }

    // MARK: - Recovery

    /// What is still on disk for a recording whose session ended without a
    /// goodbye.
    ///
    /// `hasAudio` only says that a file with the right name exists. An AAC
    /// archive is readable once its index is written at close, and a recording
    /// that ended in a quit or a crash leaves a file that exists, has a size
    /// and does not open (finding 16). The 16 kHz working copy is written
    /// differently and survives. The recovery message has to say which of the
    /// two is true, or it sends the user to a re-run that cannot work.
    public struct SurvivingAudio: Equatable, Sendable {
        /// How long the recording file is, when it opens. Nil when it is
        /// missing or does not open.
        public var archiveMs: Int?
        /// How long the working copy is, when one is on disk.
        public var workingCopyMs: Int?

        public init(archiveMs: Int? = nil, workingCopyMs: Int? = nil) {
            self.archiveMs = archiveMs
            self.workingCopyMs = workingCopyMs
        }

        public var archivePlays: Bool { archiveMs != nil }
        public var canTranscribe: Bool { archivePlays || workingCopyMs != nil }
        public var durationMs: Int { max(archiveMs ?? 0, workingCopyMs ?? 0) }
    }

    /// The answer when nobody can look inside the files: a file with the
    /// right name is taken to be intact, as before.
    public static func assumeIntact(_ recording: StoredRecording) -> SurvivingAudio {
        SurvivingAudio(archiveMs: recording.hasAudio ? max(1, recording.durationMs) : nil)
    }

    /// What a recovered row says about the audio, beyond what it says about
    /// the transcript. Empty when the recording file opens.
    ///
    /// A recording of two lanes is a different promise when its file did not close.
    /// The copy that was kept is the room and the call mixed, so it can be
    /// transcribed, but as one: the lines will not say which side they came from.
    static func audioClause(_ audio: SurvivingAudio, lanes: [CaptureLane] = [.room]) -> String {
        if audio.archivePlays { return "" }
        if audio.workingCopyMs != nil {
            let mixed = lanes.count > 1
                ? " It holds the room and the call mixed, so the transcript will not say "
                    + "which side each line came from."
                : ""
            return " The recording file was never closed, so it will not play, "
                + "but a copy of the audio was kept and can be transcribed." + mixed
        }
        return " No audio survived, so it cannot be transcribed again."
    }

    /// Resolves work that a previous run left unfinished.
    ///
    /// Statuses like `preparing`, `recording` and `transcribing` describe a job
    /// held by a live session or the queue. Neither survives a quit, so on the
    /// next launch those rows describe work that no longer exists -- and
    /// because they report `isTerminal == false`, the UI waits on them
    /// indefinitely. A recording quit during the 9-11 s model load (284 s on a
    /// cold CoreML compile) is left with no audio, no error and no way out.
    ///
    /// Called once at launch, before anything reads the store.
    ///
    /// Nothing is deleted. A row that captured no audio is still a row the user
    /// made, and silently removing it would be worse than showing that it
    /// failed.
    ///
    /// `audio` says what is on disk for a row. The messages promise a re-run
    /// only when one can work: a recording whose archive never closed has no
    /// audio to play, and its working copy is all that a re-run can read.
    @discardableResult
    public static func recoverInterrupted(
        in context: ModelContext,
        audio: (@MainActor (StoredRecording) -> SurvivingAudio)? = nil
    ) throws -> Int {
        let audio = audio ?? { assumeIntact($0) }
        let descriptor = FetchDescriptor<StoredRecording>()
        let stale = try context.fetch(descriptor).filter { !$0.status.isTerminal }
        guard !stale.isEmpty else { return 0 }

        for recording in stale {
            let wasRecording = recording.status == .recording
            let surviving = audio(recording)
            let clause = audioClause(surviving, lanes: recording.lanes)
            if recording.durationMs == 0, surviving.durationMs > 0 {
                // The length is written at Stop, which never came.
                recording.durationMs = surviving.durationMs
            }
            if let transcript = recording.transcript, transcript.isComplete {
                // The transcript exists and is readable; only the stage after
                // it was lost. Re-running diarization is a menu item away.
                recording.status = .completed
                recording.progress = 1
                if recording.audioFileName != nil, !surviving.archivePlays,
                   recording.warningMessage == nil {
                    recording.warningMessage = clause.trimmingCharacters(in: .whitespaces)
                }
            } else if recording.transcript != nil, wasRecording {
                // The live session was writing committed lines as it went and
                // the app died mid-recording. Those lines are kept; the
                // working copy the session was also writing is what
                // Transcribe Again reads, so the rest is recoverable.
                recording.status = .failed
                recording.errorMessage = "Recording was interrupted. The transcript up to "
                    + "the last line saved is kept"
                    + (surviving.canTranscribe
                       ? " — transcribe again to redo it from the audio." : ".")
                    + clause
            } else if recording.transcript != nil {
                // A job quit part-way through decoding. The rows it wrote are
                // kept and shown; the label says they are not the whole thing.
                recording.status = .failed
                recording.errorMessage = "Interrupted part-way through transcription. "
                    + "What was transcribed so far is kept"
                    + (surviving.canTranscribe ? " — transcribe again for the rest." : ".")
                    + clause
            } else if surviving.archivePlays {
                recording.status = .failed
                recording.errorMessage = "Interrupted before this was transcribed. "
                    + "The audio is here — transcribe it again."
            } else if surviving.workingCopyMs != nil {
                recording.status = .failed
                recording.errorMessage = "Interrupted before this was transcribed."
                    + clause + " Use Transcribe Again to get the text."
            } else {
                recording.status = .failed
                recording.errorMessage = "Interrupted before any audio was captured, "
                    + "so there is nothing to recover."
            }
            recording.updatedAt = Date()
        }
        try context.save()
        return stale.count
    }

    // MARK: - History

    public enum HistoryBucket: String, CaseIterable, Identifiable, Sendable {
        /// Failed rows, whatever their date. Above the dated groups so a
        /// recording that needs a retry or a delete is not buried under
        /// "Older" where nobody scrolls.
        case attention
        case today, yesterday, thisWeek, older

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .attention: return "Needs Attention"
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .thisWeek: return "Earlier This Week"
            case .older: return "Older"
            }
        }
    }

    public static func bucket(for date: Date, now: Date = Date(),
                              calendar: Calendar = .current) -> HistoryBucket {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date > weekAgo { return .thisWeek }
        return .older
    }

    /// Groups newest-first into Needs Attention / Today / Yesterday / Earlier
    /// This Week / Older. Failed recordings go to the first group regardless
    /// of when they were made.
    public static func group(_ recordings: [StoredRecording], now: Date = Date())
    -> [(bucket: HistoryBucket, items: [StoredRecording])] {
        let sorted = recordings.sorted { $0.createdAt > $1.createdAt }
        var buckets: [HistoryBucket: [StoredRecording]] = [:]
        for recording in sorted {
            let key: HistoryBucket = recording.status == .failed
                ? .attention
                : bucket(for: recording.createdAt, now: now)
            buckets[key, default: []].append(recording)
        }
        return HistoryBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return (bucket, items)
        }
    }

    // MARK: - Speakers

    /// Ensures a `StoredSpeaker` row exists for every label the diarizer used,
    /// leaving names the user already chose alone.
    public static func syncSpeakers(_ roster: [SpeakerLabel],
                                    on recording: StoredRecording,
                                    in context: ModelContext) {
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
                context.insert(row)
            }
        }
        // Labels no longer produced by the current transcript: drop them, or a
        // re-run with fewer speakers leaves ghosts in the roster.
        for orphan in existing.values { context.delete(orphan) }
    }

    public static func rename(_ speaker: StoredSpeaker, to name: String,
                              in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speaker.displayName = trimmed.isEmpty
            ? SpeakerLabel.defaultName(for: speaker.speakerId)
            : trimmed
        speaker.recording?.updatedAt = Date()
        try context.save()
    }

    /// Folds one speaker into another: every line credited to `speaker` is
    /// re-credited to `target`, the talk time moves with it, and the row goes.
    ///
    /// The repair for a diarizer that heard fourteen voices in a six-person
    /// room. Segments hold the diarizer's label, so this rewrites them; a
    /// later "Identify Speakers Again" starts from a fresh roster and the
    /// merge would have to be made again, which is the honest outcome.
    public static func merge(_ speaker: StoredSpeaker, into target: StoredSpeaker,
                             in context: ModelContext) throws {
        guard speaker !== target, speaker.speakerId != target.speakerId,
              let recording = target.recording else { return }
        for row in recording.transcript?.orderedSegments ?? []
        where row.speakerId == speaker.speakerId {
            row.speakerId = target.speakerId
        }
        target.speechMs += speaker.speechMs
        context.delete(speaker)
        recording.updatedAt = Date()
        try context.save()
    }

    /// Re-credits lines to a speaker (or to nobody), moving their duration
    /// between the talk-time totals so the Speakers pane stays honest.
    public static func assign(_ segments: [StoredSegment], to speaker: StoredSpeaker?,
                              on recording: StoredRecording, in context: ModelContext) throws {
        let roster = recording.speakers ?? []
        for row in segments {
            guard row.speakerId != speaker?.speakerId else { continue }
            let duration = max(0, row.endMs - row.startMs)
            if let previous = roster.first(where: { $0.speakerId == row.speakerId }) {
                previous.speechMs = max(0, previous.speechMs - duration)
            }
            row.speakerId = speaker?.speakerId
            speaker?.speechMs += duration
        }
        recording.updatedAt = Date()
        try context.save()
    }

    /// A speaker the diarizer did not find, numbered after the last it did.
    @discardableResult
    public static func addSpeaker(named name: String? = nil, to recording: StoredRecording,
                                  in context: ModelContext) throws -> StoredSpeaker {
        let existing = recording.speakers ?? []
        let next = (existing.compactMap { Int($0.speakerId.filter(\.isNumber)) }.max() ?? 0) + 1
        let id = "S\(next)"
        let speaker = StoredSpeaker(
            speakerId: id,
            displayName: name ?? SpeakerLabel.defaultName(for: id),
            speechMs: 0,
            colorIndex: (existing.map(\.colorIndex).max() ?? -1) + 1
        )
        speaker.recording = recording
        context.insert(speaker)
        recording.updatedAt = Date()
        try context.save()
        return speaker
    }

    // MARK: - Bookmarks and notes

    @discardableResult
    public static func addBookmark(at ms: Int, label: String = "",
                                   to recording: StoredRecording,
                                   in context: ModelContext) throws -> StoredBookmark {
        let bookmark = StoredBookmark(atMs: ms, label: label)
        bookmark.recording = recording
        context.insert(bookmark)
        recording.updatedAt = Date()
        try context.save()
        return bookmark
    }

    @discardableResult
    public static func addItem(_ kind: MeetingItemKind, text: String,
                               source: StoredSegment? = nil,
                               to recording: StoredRecording,
                               in context: ModelContext) throws -> StoredMeetingItem {
        let order = (recording.items ?? []).filter { $0.kind == kind }.count
        let item = StoredMeetingItem(
            kind: kind,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            order: order,
            sourceSegmentId: source?.id,
            sourceMs: source?.startMs
        )
        item.recording = recording
        context.insert(item)
        recording.updatedAt = Date()
        try context.save()
        return item
    }

    public static func items(_ kind: MeetingItemKind,
                             of recording: StoredRecording) -> [StoredMeetingItem] {
        (recording.items ?? [])
            .filter { $0.kind == kind }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    // MARK: - Tags

    public static func tag(named name: String, in context: ModelContext) throws -> StoredTag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<StoredTag>(
            predicate: #Predicate { $0.name == trimmed }
        )
        if let existing = try context.fetch(descriptor).first { return existing }
        let tag = StoredTag(name: trimmed, colorIndex: abs(trimmed.hashValue) % 8)
        context.insert(tag)
        return tag
    }

    // MARK: - Export payload

    /// Flattens the graph into the value type the exporters consume.
    public static func document(for recording: StoredRecording) -> MeetingDocument {
        let transcript = recording.transcript
        let audio = recording.audioFileName
        let segments = (transcript?.orderedSegments ?? []).map { row in
            Segment(
                id: row.id,
                index: row.index,
                startMs: row.startMs,
                endMs: row.endMs,
                text: row.text,
                textClean: row.textClean,
                speakerId: row.speakerId,
                confidence: row.confidence,
                audio: audio.map {
                    AudioReference(recordingId: recording.id, fileName: $0,
                                   offsetMs: row.startMs)
                }
            )
        }
        return MeetingDocument(
            id: recording.id,
            title: recording.title,
            kind: recording.kind,
            createdAt: recording.createdAt,
            durationMs: recording.durationMs,
            language: transcript?.language ?? LanguageCatalogue.defaultLanguage,
            modelId: transcript?.modelId,
            audioFileName: audio,
            status: recording.status,
            summary: recording.summary,
            speakers: (recording.speakers ?? [])
                .sorted { $0.colorIndex < $1.colorIndex }
                .map { SpeakerLabel(id: $0.speakerId, displayName: $0.displayName,
                                    speechMs: $0.speechMs) },
            segments: segments,
            bookmarks: (recording.bookmarks ?? [])
                .sorted { $0.atMs < $1.atMs }
                .map { Bookmark(id: $0.id, atMs: $0.atMs, label: $0.label,
                                createdAt: $0.createdAt) },
            items: MeetingItemKind.allCases.flatMap { kind in
                items(kind, of: recording).map { row in
                    MeetingItem(id: row.id, kind: row.kind, text: row.text,
                                isDone: row.isDone, owner: row.owner,
                                dueDate: row.dueDate,
                                sourceSegmentId: row.sourceSegmentId,
                                sourceMs: row.sourceMs, createdAt: row.createdAt)
                }
            },
            tags: (recording.tags ?? []).map(\.name).sorted()
        )
    }

    /// Rebuilds the flattened search text. Called after any transcript or note edit.
    public static func reindex(_ recording: StoredRecording) {
        var parts = [recording.title, recording.summary, recording.body]
        parts.append(contentsOf: (recording.transcript?.orderedSegments ?? []).map(\.displayText))
        parts.append(contentsOf: (recording.items ?? []).map(\.text))
        parts.append(contentsOf: (recording.bookmarks ?? []).map(\.label))
        recording.searchText = parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
