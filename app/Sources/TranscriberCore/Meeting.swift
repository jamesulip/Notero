import Foundation

/// What a sidebar entry actually is.
public enum RecordingKind: String, Codable, CaseIterable, Sendable {
    /// Audio and a transcript. No meeting scaffolding.
    case recording
    /// A recording plus the meeting workspace: notes, decisions, actions.
    case meeting
    /// Text only. No audio, no transcript.
    case note

    public var label: String {
        switch self {
        case .recording: return "Recording"
        case .meeting: return "Meeting"
        case .note: return "Note"
        }
    }

    public var symbol: String {
        switch self {
        case .recording: return "waveform"
        case .meeting: return "person.2.wave.2"
        case .note: return "note.text"
        }
    }
}

/// Where a recording is in the pipeline.
///
/// Deliberately more granular than "working": the stages have very different
/// durations, and a progress bar that sits at "working" for eleven minutes of
/// diarization reads as a hang.
public enum TranscriptionStatus: String, Codable, CaseIterable, Sendable {
    case pending, preparing, transcribing, diarizing, finalizing, completed, cancelled, failed
    /// Live transcription in progress; the recording is still being captured.
    case recording

    public var label: String {
        switch self {
        case .pending: return "In queue"
        case .preparing: return "Preparation"
        case .recording: return "Recording"
        case .transcribing: return "Transcription"
        case .diarizing: return "Speaker identification"
        case .finalizing: return "Last step"
        case .completed: return "Complete"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }

    public var isTerminal: Bool { self == .completed || self == .cancelled || self == .failed }
    public var isBusy: Bool { !isTerminal && self != .pending }
}

/// A timestamp the user marked, by name.
public struct Bookmark: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var atMs: Int
    public var label: String
    public var createdAt: Date

    public init(id: UUID = UUID(), atMs: Int, label: String = "", createdAt: Date = Date()) {
        self.id = id
        self.atMs = atMs
        self.label = label
        self.createdAt = createdAt
    }

    /// What to show when the user bookmarked a moment without naming it.
    public var displayLabel: String {
        label.isEmpty ? "Bookmark at \(TimeFormat.short(ms: atMs))" : label
    }
}

/// The five structured note kinds in the meeting workspace.
///
/// V1 fills these by hand. They exist as typed rows rather than free text
/// precisely so a later extraction pass can write into the same shape instead
/// of requiring the notes to be re-modelled.
public enum MeetingItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case keyPoint, decision, actionItem, question, followUp

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .keyPoint: return "Key Point"
        case .decision: return "Decision"
        case .actionItem: return "Action Item"
        case .question: return "Question"
        case .followUp: return "Follow-up"
        }
    }

    public var plural: String {
        switch self {
        case .keyPoint: return "Key Points"
        case .decision: return "Decisions"
        case .actionItem: return "Action Items"
        case .question: return "Questions"
        case .followUp: return "Follow-ups"
        }
    }

    public var symbol: String {
        switch self {
        case .keyPoint: return "star"
        case .decision: return "checkmark.seal"
        case .actionItem: return "checklist"
        case .question: return "questionmark.circle"
        case .followUp: return "arrow.uturn.right"
        }
    }

    /// Only action items and follow-ups can be completed.
    public var isCheckable: Bool { self == .actionItem || self == .followUp }
}

public struct MeetingItem: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var kind: MeetingItemKind
    public var text: String
    public var isDone: Bool
    public var owner: String?
    public var dueDate: Date?
    /// The transcript segment this was pulled from, if any. Clicking the
    /// source is what makes a manual note auditable against the audio.
    public var sourceSegmentId: UUID?
    public var sourceMs: Int?
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: MeetingItemKind, text: String,
                isDone: Bool = false, owner: String? = nil, dueDate: Date? = nil,
                sourceSegmentId: UUID? = nil, sourceMs: Int? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isDone = isDone
        self.owner = owner
        self.dueDate = dueDate
        self.sourceSegmentId = sourceSegmentId
        self.sourceMs = sourceMs
        self.createdAt = createdAt
    }
}

/// The complete meeting: everything an export has to preserve.
///
/// A value type, built from the SwiftData graph at export time. Keeping it
/// separate is what lets the exporters be tested without a store.
public struct MeetingDocument: Sendable, Codable {
    public var id: UUID
    public var title: String
    public var kind: RecordingKind
    public var createdAt: Date
    public var durationMs: Int
    public var language: String
    public var modelId: String?
    public var audioFileName: String?
    public var status: TranscriptionStatus
    public var summary: String
    public var speakers: [SpeakerLabel]
    public var segments: [Segment]
    public var bookmarks: [Bookmark]
    public var items: [MeetingItem]
    public var tags: [String]

    public init(id: UUID, title: String, kind: RecordingKind, createdAt: Date,
                durationMs: Int, language: String, modelId: String? = nil,
                audioFileName: String? = nil, status: TranscriptionStatus = .completed,
                summary: String = "", speakers: [SpeakerLabel] = [],
                segments: [Segment] = [], bookmarks: [Bookmark] = [],
                items: [MeetingItem] = [], tags: [String] = []) {
        self.id = id
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.language = language
        self.modelId = modelId
        self.audioFileName = audioFileName
        self.status = status
        self.summary = summary
        self.speakers = speakers
        self.segments = segments
        self.bookmarks = bookmarks
        self.items = items
        self.tags = tags
    }

    public func items(_ kind: MeetingItemKind) -> [MeetingItem] {
        items.filter { $0.kind == kind }
    }

    /// Display name for a diarizer label, honouring any rename.
    public func name(for speakerId: String?) -> String? {
        guard let speakerId else { return nil }
        return speakers.first { $0.id == speakerId }?.displayName
            ?? SpeakerLabel.defaultName(for: speakerId)
    }
}
