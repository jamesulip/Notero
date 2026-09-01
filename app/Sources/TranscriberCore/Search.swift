import Foundation

/// Where a hit came from. Notes and transcript both match; the sidebar shows which.
public enum SearchScope: String, Sendable, Codable, CaseIterable {
    case transcript, note, title, bookmark

    public var label: String {
        switch self {
        case .transcript: return "Transcript"
        case .note: return "Notes"
        case .title: return "Title"
        case .bookmark: return "Bookmark"
        }
    }
}

public struct SearchHit: Identifiable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var recordingTitle: String
    public var recordingDate: Date
    public var scope: SearchScope
    /// Where in the audio to jump. Nil for a note with no source segment.
    public var atMs: Int?
    /// The segment to select on arrival, when there is one.
    public var segmentId: UUID?
    public var snippet: String
    /// Ranges within `snippet` to highlight. Indices into `snippet`, not the source.
    public var highlights: [Range<String.Index>]

    public init(id: UUID, recordingId: UUID, recordingTitle: String,
                recordingDate: Date, scope: SearchScope, atMs: Int?,
                segmentId: UUID?, snippet: String,
                highlights: [Range<String.Index>]) {
        self.id = id
        self.recordingId = recordingId
        self.recordingTitle = recordingTitle
        self.recordingDate = recordingDate
        self.scope = scope
        self.atMs = atMs
        self.segmentId = segmentId
        self.snippet = snippet
        self.highlights = highlights
    }
}

/// Full-text matching. No embeddings, no index build, no model.
///
/// Case- and diacritic-insensitive through Foundation rather than by folding
/// the text first: folding would give ranges into a normalized copy, and every
/// one would have to be mapped back to highlight the original. Foundation
/// searches insensitively and returns ranges into the string you passed.
public enum TextSearch {

    /// Query terms. Quoted runs stay together as a phrase.
    public static func terms(_ query: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for character in query {
            if character == "\"" {
                inQuotes.toggle()
                if !inQuotes, !current.isEmpty { out.append(current); current = "" }
            } else if character.isWhitespace, !inQuotes {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.filter { $0.count >= 2 || $0.allSatisfy(\.isNumber) }
    }

    public static func ranges(of term: String, in text: String,
                             limit: Int = 12) -> [Range<String.Index>] {
        guard !term.isEmpty, !text.isEmpty else { return [] }
        var out: [Range<String.Index>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex, out.count < limit {
            guard let found = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: cursor..<text.endIndex
            ) else { break }
            out.append(found)
            // Guard against a zero-width match looping forever.
            cursor = found.upperBound > found.lowerBound
                ? found.upperBound
                : text.index(after: found.lowerBound)
        }
        return out
    }

    /// All terms must appear. Returns every term's ranges, ordered, or nil if
    /// any term is missing.
    public static func matchAll(_ terms: [String], in text: String) -> [Range<String.Index>]? {
        guard !terms.isEmpty else { return nil }
        var all: [Range<String.Index>] = []
        for term in terms {
            let found = ranges(of: term, in: text)
            if found.isEmpty { return nil }
            all.append(contentsOf: found)
        }
        return all.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// A window of `text` around the first match, with the ranges rebased into it.
    public static func snippet(
        _ text: String, matches: [Range<String.Index>], context: Int = 48
    ) -> (text: String, highlights: [Range<String.Index>]) {
        guard let first = matches.first else { return (text, []) }

        let lower = text.index(first.lowerBound, offsetBy: -context,
                               limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(first.upperBound, offsetBy: context,
                               limitedBy: text.endIndex) ?? text.endIndex
        // Do not cut mid-word: back off to whitespace on each side when we are
        // not already at the ends of the string.
        let start = lower == text.startIndex ? lower : (nextBoundary(text, from: lower, forward: true) ?? lower)
        let end = upper == text.endIndex ? upper : (nextBoundary(text, from: upper, forward: false) ?? upper)
        guard start < end else { return (text, matches) }

        var window = String(text[start..<end])
        var prefixLength = 0
        if start > text.startIndex { window = "…" + window; prefixLength = 1 }
        if end < text.endIndex { window += "…" }

        // Rebase by offset. Cheaper and less fragile than re-searching, which
        // could land on a different occurrence inside the window.
        let base = text.distance(from: text.startIndex, to: start) - prefixLength
        var rebased: [Range<String.Index>] = []
        for match in matches {
            let lowerOffset = text.distance(from: text.startIndex, to: match.lowerBound) - base
            let upperOffset = text.distance(from: text.startIndex, to: match.upperBound) - base
            guard lowerOffset >= 0, upperOffset <= window.count, lowerOffset < upperOffset else { continue }
            let low = window.index(window.startIndex, offsetBy: lowerOffset)
            let high = window.index(window.startIndex, offsetBy: upperOffset)
            rebased.append(low..<high)
        }
        return (window, rebased)
    }

    private static func nextBoundary(_ text: String, from index: String.Index,
                                     forward: Bool) -> String.Index? {
        var cursor = index
        var steps = 0
        while steps < 24 {
            if forward {
                guard cursor < text.endIndex else { return text.endIndex }
                if text[cursor].isWhitespace { return text.index(after: cursor) }
                cursor = text.index(after: cursor)
            } else {
                guard cursor > text.startIndex else { return text.startIndex }
                let previous = text.index(before: cursor)
                if text[previous].isWhitespace { return previous }
                cursor = previous
            }
            steps += 1
        }
        return nil
    }
}
