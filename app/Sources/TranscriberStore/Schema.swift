import Foundation
import SwiftData
import TranscriberCore

// Persistence entities carry a `Stored` prefix throughout.
//
// The app imports this module alongside TranscriberCore, whose value types use
// the obvious names -- `Segment`, `Bookmark`, `MeetingItem`. Without the prefix
// half of them would collide and every use site would need qualifying. The two
// layers are different things anyway: these are mutable reference types owned
// by a context, those are immutable snapshots that cross actor boundaries.

@Model
public final class StoredRecording {
    #Unique<StoredRecording>([\.id])
    #Index<StoredRecording>([\.createdAt], [\.kindRaw])

    public var id: UUID = UUID()
    public var title: String = ""
    public var kindRaw: String = RecordingKind.recording.rawValue
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var durationMs: Int = 0
    public var isFavorite: Bool = false

    /// Path relative to `Paths.recordings`, e.g. `2026/08/<uuid>.m4a`.
    /// Nil for a text-only note.
    public var audioFileName: String?
    /// Sample rate the file was written at. The inference copy is always
    /// 16 kHz; this is the archival rate and it is not the same number.
    public var audioSampleRate: Int = 48_000

    public var statusRaw: String = TranscriptionStatus.pending.rawValue
    /// 0...1 within the current stage. Stage comes from `status`.
    public var progress: Double = 0
    public var errorMessage: String?

    /// How many people the user says were in the room, for speaker
    /// identification to aim at. Nil until they say.
    public var expectedSpeakers: Int?

    /// Meeting summary, hand-written in v1.
    public var summary: String = ""
    /// Body text for a plain note, and scratch notes on a recording.
    public var body: String = ""

    /// Peak envelope, ~600 buckets, cached so the waveform draws instantly
    /// instead of re-reading a 200 MB file on every selection.
    public var waveform: [Float]?

    /// Everything searchable, flattened. Redundant with the segments on
    /// purpose: it turns "find September 15" into one string scan per
    /// recording instead of a join across tens of thousands of segment rows.
    public var searchText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \StoredTranscript.recording)
    public var transcripts: [StoredTranscript]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredSpeaker.recording)
    public var speakers: [StoredSpeaker]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredBookmark.recording)
    public var bookmarks: [StoredBookmark]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredMeetingItem.recording)
    public var items: [StoredMeetingItem]? = []

    @Relationship(inverse: \StoredTag.recordings)
    public var tags: [StoredTag]? = []

    public init(id: UUID = UUID(), title: String, kind: RecordingKind,
                createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var kind: RecordingKind {
        get { RecordingKind(rawValue: kindRaw) ?? .recording }
        set { kindRaw = newValue.rawValue }
    }

    public var status: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// The newest transcript. Re-transcribing with a different model adds a
    /// revision rather than destroying the one the user may have annotated.
    public var transcript: StoredTranscript? {
        (transcripts ?? []).max { $0.revision < $1.revision }
    }

    public var audioURL: URL? {
        audioFileName.map { Paths.recordingURL($0) }
    }

    public var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

@Model
public final class StoredTranscript {
    public var id: UUID = UUID()
    /// 1 for the first pass, incremented on every re-transcription.
    public var revision: Int = 1
    public var modelId: String = ""
    public var language: String = LanguageCatalogue.defaultLanguage
    public var createdAt: Date = Date.now
    /// Wall-clock cost of producing it. Feeds the benchmark panel.
    public var processMs: Int = 0
    public var didDiarize: Bool = false
    /// False while a whole-file job is still appending segments, and left
    /// false if that job fails or is cancelled part-way: a partial transcript
    /// is kept and labelled rather than thrown away.
    public var isComplete: Bool = true

    public var recording: StoredRecording?

    @Relationship(deleteRule: .cascade, inverse: \StoredSegment.transcript)
    public var segments: [StoredSegment]? = []

    public init(id: UUID = UUID(), revision: Int = 1, modelId: String,
                language: String) {
        self.id = id
        self.revision = revision
        self.modelId = modelId
        self.language = language
    }

    /// Deleted rows drop out at once rather than at the next save: a line the
    /// user just removed must not reappear in the reindex or the export that
    /// follows in the same breath.
    public var orderedSegments: [StoredSegment] {
        (segments ?? []).filter { !$0.isDeleted }.sorted { $0.startMs < $1.startMs }
    }
}

@Model
public final class StoredSegment {
    #Index<StoredSegment>([\.startMs])

    public var id: UUID = UUID()
    public var index: Int = 0
    public var startMs: Int = 0
    public var endMs: Int = 0
    public var text: String = ""
    public var textClean: String?
    /// Diarizer label (`S1`), never a display name. Renaming a speaker must
    /// not require rewriting every segment.
    public var speakerId: String?
    public var confidence: Double?

    public var transcript: StoredTranscript?

    public init(id: UUID = UUID(), index: Int, startMs: Int, endMs: Int,
                text: String, textClean: String? = nil, speakerId: String? = nil,
                confidence: Double? = nil) {
        self.id = id
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.textClean = textClean
        self.speakerId = speakerId
        self.confidence = confidence
    }

    public var displayText: String { textClean ?? text }
}

@Model
public final class StoredSpeaker {
    public var id: UUID = UUID()
    /// The diarizer label this row names.
    public var speakerId: String = ""
    public var displayName: String = ""
    public var speechMs: Int = 0
    public var colorIndex: Int = 0

    public var recording: StoredRecording?

    public init(id: UUID = UUID(), speakerId: String, displayName: String,
                speechMs: Int = 0, colorIndex: Int = 0) {
        self.id = id
        self.speakerId = speakerId
        self.displayName = displayName
        self.speechMs = speechMs
        self.colorIndex = colorIndex
    }
}

@Model
public final class StoredBookmark {
    public var id: UUID = UUID()
    public var atMs: Int = 0
    public var label: String = ""
    public var createdAt: Date = Date.now

    public var recording: StoredRecording?

    public init(id: UUID = UUID(), atMs: Int, label: String = "",
                createdAt: Date = Date()) {
        self.id = id
        self.atMs = atMs
        self.label = label
        self.createdAt = createdAt
    }

    public var displayLabel: String {
        label.isEmpty ? "Bookmark at \(TimeFormat.short(ms: atMs))" : label
    }
}

@Model
public final class StoredMeetingItem {
    public var id: UUID = UUID()
    public var kindRaw: String = MeetingItemKind.keyPoint.rawValue
    public var text: String = ""
    public var isDone: Bool = false
    public var owner: String?
    public var dueDate: Date?
    public var createdAt: Date = Date.now
    public var order: Int = 0

    /// Back-link to the transcript segment this was lifted from. Stored as a
    /// plain id rather than a relationship: re-transcribing replaces the
    /// segment rows, and a dangling id degrades to "no source" while a broken
    /// relationship would take the note with it.
    public var sourceSegmentId: UUID?
    public var sourceMs: Int?

    public var recording: StoredRecording?

    public init(id: UUID = UUID(), kind: MeetingItemKind, text: String,
                order: Int = 0, sourceSegmentId: UUID? = nil, sourceMs: Int? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.text = text
        self.order = order
        self.sourceSegmentId = sourceSegmentId
        self.sourceMs = sourceMs
    }

    public var kind: MeetingItemKind {
        get { MeetingItemKind(rawValue: kindRaw) ?? .keyPoint }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
public final class StoredTag {
    #Unique<StoredTag>([\.name])

    public var name: String = ""
    public var colorIndex: Int = 0
    public var recordings: [StoredRecording]? = []

    public init(name: String, colorIndex: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
    }
}

public enum TranscriberSchema {
    public static let models: [any PersistentModel.Type] = [
        StoredRecording.self,
        StoredTranscript.self,
        StoredSegment.self,
        StoredSpeaker.self,
        StoredBookmark.self,
        StoredMeetingItem.self,
        StoredTag.self,
    ]
}
