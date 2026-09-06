import Foundation
import SwiftData
import TranscriberCore

/// Writing an accepted draft into the recording.
extension RecordingStore {

    /// Adds the accepted items as typed rows with their back-links, after the
    /// rows of the same kind the recording already has, and replaces the
    /// summary when one is given. Nil leaves the summary as it is: a summary
    /// the user wrote is never overwritten without the user asking.
    @discardableResult
    public static func apply(_ items: [NotesDraft.Item], summary: String?,
                             to recording: StoredRecording, in context: ModelContext) throws -> Int {
        var next: [MeetingItemKind: Int] = [:]
        for row in recording.items ?? [] {
            next[row.kind] = max(next[row.kind] ?? 0, row.order + 1)
        }
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let order = next[item.kind] ?? 0
            next[item.kind] = order + 1
            let row = StoredMeetingItem(kind: item.kind, text: text, order: order,
                                        sourceSegmentId: item.sourceSegmentId,
                                        sourceMs: item.sourceMs)
            row.recording = recording
            context.insert(row)
        }
        if let summary {
            recording.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        recording.updatedAt = Date()
        SearchIndex.rebuild(recording)
        try context.save()
        return items.count
    }
}
