import Foundation
import SwiftData
import TranscriberCore

@MainActor
public enum SearchService {

    /// Two passes on purpose.
    ///
    /// SwiftData narrows to the recordings whose flattened text contains the
    /// rarest-looking term -- one predicate, no joins. Everything after that is
    /// in memory over a handful of rows, which is where the per-segment
    /// timestamps and the highlight ranges come from. Running the fine pass as
    /// a predicate instead would mean fetching every segment in the store.
    public static func search(_ query: String, in context: ModelContext,
                              limit: Int = 80) throws -> [SearchHit] {
        let terms = TextSearch.terms(query)
        guard !terms.isEmpty else { return [] }

        // Longest term is the most selective; it is also the cheapest guess
        // available without keeping term frequencies.
        let anchor = terms.max { $0.count < $1.count } ?? terms[0]
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.searchText.localizedStandardContains(anchor) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 400

        var hits: [SearchHit] = []
        for recording in try context.fetch(descriptor) {
            hits.append(contentsOf: matches(in: recording, terms: terms))
            if hits.count >= limit { break }
        }
        return Array(hits.prefix(limit))
    }

    static func matches(in recording: StoredRecording, terms: [String]) -> [SearchHit] {
        var out: [SearchHit] = []

        func add(scope: SearchScope, id: UUID, text: String, atMs: Int?,
                 segmentId: UUID?) {
            guard let matches = TextSearch.matchAll(terms, in: text) else { return }
            let snippet = TextSearch.snippet(text, matches: matches)
            out.append(SearchHit(
                id: id, recordingId: recording.id, recordingTitle: recording.title,
                recordingDate: recording.createdAt, scope: scope, atMs: atMs,
                segmentId: segmentId, snippet: snippet.text,
                highlights: snippet.highlights
            ))
        }

        add(scope: .title, id: recording.id, text: recording.title,
            atMs: nil, segmentId: nil)

        for segment in recording.transcript?.orderedSegments ?? [] {
            add(scope: .transcript, id: segment.id, text: segment.displayText,
                atMs: segment.startMs, segmentId: segment.id)
        }
        if !recording.summary.isEmpty {
            add(scope: .note, id: recording.id, text: recording.summary,
                atMs: nil, segmentId: nil)
        }
        if !recording.body.isEmpty {
            add(scope: .note, id: recording.id, text: recording.body,
                atMs: nil, segmentId: nil)
        }
        for item in recording.items ?? [] {
            add(scope: .note, id: item.id, text: item.text,
                atMs: item.sourceMs, segmentId: item.sourceSegmentId)
        }
        for bookmark in recording.bookmarks ?? [] where !bookmark.label.isEmpty {
            add(scope: .bookmark, id: bookmark.id, text: bookmark.label,
                atMs: bookmark.atMs, segmentId: nil)
        }
        return out
    }
}
