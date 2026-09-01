import Foundation

/// Where a segment's audio actually lives.
///
/// Carried on the segment rather than looked up through a parent, so a search
/// hit or a note back-link can seek to audio knowing only the segment.
public struct AudioReference: Hashable, Sendable, Codable {
    /// The recording this audio belongs to.
    public var recordingId: UUID
    /// File name relative to the recordings root. Not an absolute path: the
    /// container moves between machines and app-sandbox rewrites, the name does not.
    public var fileName: String
    /// Offset of the segment inside that file. Equal to `startMs` for a
    /// single-file recording, and deliberately separate so a transcript
    /// assembled from several imports can still point at the right one.
    public var offsetMs: Int

    public init(recordingId: UUID, fileName: String, offsetMs: Int) {
        self.recordingId = recordingId
        self.fileName = fileName
        self.offsetMs = offsetMs
    }
}

/// One line of transcript.
///
/// `text` is what the model produced and is never rewritten -- Taglish stays
/// Taglish. `textClean` is an optional parallel field for a future cleanup
/// pass; exports prefer it when present, so adding one later changes the data
/// and not the renderers.
public struct Segment: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    /// Ordinal within its transcript. Stable, and what SRT cue numbers use.
    public var index: Int
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var textClean: String?
    /// Diarizer label (`S1`, `S2`...), not a display name. Nil until
    /// diarization runs, and nil forever on single-speaker recordings.
    public var speakerId: String?
    /// Mean token log-probability mapped to 0...1, when the backend reports it.
    public var confidence: Double?
    public var audio: AudioReference?

    public init(
        id: UUID = UUID(),
        index: Int,
        startMs: Int,
        endMs: Int,
        text: String,
        textClean: String? = nil,
        speakerId: String? = nil,
        confidence: Double? = nil,
        audio: AudioReference? = nil
    ) {
        self.id = id
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.textClean = textClean
        self.speakerId = speakerId
        self.confidence = confidence
        self.audio = audio
    }

    /// Cleaned text when it exists, raw otherwise. Everything user-facing uses this.
    public var displayText: String { textClean ?? text }

    public var durationMs: Int { max(0, endMs - startMs) }

    public func contains(ms: Int) -> Bool { ms >= startMs && ms < max(endMs, startMs + 1) }
}

/// A stretch of audio attributed to one speaker by the diarizer.
public struct SpeakerSpan: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var speakerId: String
    public var startMs: Int
    public var endMs: Int
    /// Diarizer's own confidence in the attribution, 0...1 when reported.
    public var quality: Double?

    public init(id: UUID = UUID(), speakerId: String, startMs: Int, endMs: Int,
                quality: Double? = nil) {
        self.id = id
        self.speakerId = speakerId
        self.startMs = startMs
        self.endMs = endMs
        self.quality = quality
    }

    public var durationMs: Int { max(0, endMs - startMs) }

    /// Milliseconds shared with `other`. The merger scores on this.
    public func overlapMs(startMs otherStart: Int, endMs otherEnd: Int) -> Int {
        max(0, min(endMs, otherEnd) - max(startMs, otherStart))
    }
}

/// A speaker as the user sees them: a diarizer label plus whatever they renamed it to.
public struct SpeakerLabel: Identifiable, Equatable, Sendable, Codable {
    public var id: String          // the diarizer label, e.g. "S1"
    public var displayName: String // "Speaker 1" until renamed to "Juan"
    public var speechMs: Int

    public init(id: String, displayName: String, speechMs: Int = 0) {
        self.id = id
        self.displayName = displayName
        self.speechMs = speechMs
    }

    /// "S1" -> "Speaker 1". The fallback when nobody has renamed anything.
    ///
    /// Backends label speakers inconsistently -- "1", "speaker_0", "S3" -- so
    /// the engine normalizes to `S<n>`, 1-based, before anything here sees it.
    public static func defaultName(for speakerId: String) -> String {
        let digits = String(speakerId.filter(\.isNumber))
        if let number = Int(digits), number > 0 { return "Speaker \(number)" }
        return speakerId
    }
}
