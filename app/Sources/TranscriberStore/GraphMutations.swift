import Foundation
import SwiftData
import TranscriberCore

// Two mutations of the recording graph that both sides of the actor seam
// make: the main-actor store when the user edits, and the writer actor when a
// job finishes. Each used to exist twice, byte for byte, once per isolation.
// A fix to either had to be made twice. They are `nonisolated` and take the
// context they work on, so each caller runs them on its own actor.

/// The roster: one `StoredSpeaker` row per label the diarizer produced, names
/// the user chose left alone, labels the transcript no longer uses removed.
public enum SpeakerSync {

    /// Ensures a row exists for every label in `roster`, updates the talk time
    /// and the colour of the rows that stay, and deletes the rows for labels
    /// that are gone. A re-run with fewer speakers would otherwise leave
    /// ghosts in the roster.
    nonisolated public static func apply(_ roster: [SpeakerLabel],
                                         to recording: StoredRecording,
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
        for orphan in existing.values { context.delete(orphan) }
    }
}

/// The flattened text that search reads: title, summary, notes, every
/// transcript line as displayed, every item and every bookmark label.
public enum SearchIndex {

    /// Rebuilds `searchText`. Called after any edit to the transcript or the
    /// notes, and once when a job finishes. It reads the transcript through
    /// the same indexed fetch as everything else.
    nonisolated public static func rebuild(_ recording: StoredRecording) {
        var parts = [recording.title, recording.summary, recording.body]
        parts.append(contentsOf: (recording.transcript?.orderedSegments ?? []).map(\.displayText))
        parts.append(contentsOf: (recording.items ?? []).map(\.text))
        parts.append(contentsOf: (recording.bookmarks ?? []).map(\.label))
        recording.searchText = parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
