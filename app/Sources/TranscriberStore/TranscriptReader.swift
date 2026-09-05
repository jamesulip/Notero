import Foundation
import SwiftData
import TranscriberCore

/// Reads a transcript's rows as value types, off the main actor.
///
/// Walking `StoredTranscript.segments` costs one round trip to SQLite for
/// each row, because every row comes back as a fault and the sort fires them
/// all. A four-hour meeting has four thousand rows, thus a selection in the
/// sidebar paid four thousand fetches on the main thread before the first
/// line could draw. One fetch with a predicate and a sort descriptor returns
/// the same rows in one query, in order, and a `@ModelActor` runs it on its
/// own context so the window never waits for it.
///
/// Make a new reader for each read. A long-lived context keeps the row values
/// it has already loaded, and a fetch does not refresh them, thus an edit
/// saved on the main context could be read back stale.
@ModelActor
public actor TranscriptReader {

    /// The rows of one transcript, in time order.
    public func segments(ofTranscript id: UUID) throws -> [Segment] {
        try Self.segments(ofTranscript: id, in: modelContext)
    }

    /// The rows grouped into speaker turns, ready for the transcript view.
    public func blocks(ofTranscript id: UUID) throws -> [TranscriptBlock] {
        TranscriptGrouping.blocks(from: try segments(ofTranscript: id))
    }

    /// The same fetch on any context, for a caller that is already on the
    /// main actor and must answer at once.
    public static func segments(ofTranscript id: UUID, in context: ModelContext) throws -> [Segment] {
        try segmentRows(ofTranscript: id, in: context).map(Segment.init)
    }

    /// The stored rows themselves, in time order, for a caller that must
    /// change them.
    public static func segmentRows(ofTranscript id: UUID, in context: ModelContext) throws -> [StoredSegment] {
        let descriptor = FetchDescriptor<StoredSegment>(
            predicate: #Predicate { $0.transcript?.id == id },
            sortBy: [SortDescriptor(\.startMs)]
        )
        return try context.fetch(descriptor)
    }

    /// The stored rows with these ids, in time order.
    public static func segmentRows(ids: [UUID], in context: ModelContext) throws -> [StoredSegment] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<StoredSegment>(
            predicate: #Predicate { ids.contains($0.id) },
            sortBy: [SortDescriptor(\.startMs)]
        )
        return try context.fetch(descriptor)
    }

    /// One stored row, or nil.
    public static func segmentRow(id: UUID, in context: ModelContext) throws -> StoredSegment? {
        var descriptor = FetchDescriptor<StoredSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

public extension Segment {
    /// The value form of a stored row.
    init(_ row: StoredSegment) {
        self.init(id: row.id, index: row.index, startMs: row.startMs, endMs: row.endMs,
                  text: row.text, textClean: row.textClean, speakerId: row.speakerId,
                  confidence: row.confidence)
    }
}
