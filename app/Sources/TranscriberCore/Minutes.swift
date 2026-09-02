import Foundation

/// Turning a transcript into minutes: the prompt, and the guards on what comes
/// back.
///
/// Pure, and deliberately separate from whatever produces the text. The model
/// lives behind `MinutesGenerating` in the engine layer; everything here is
/// testable with a string literal and no subprocess.
///
/// The parsing half is the point. A summariser that invents a decision nobody
/// made, or pins a real one to the wrong minute, is worse than no summariser:
/// the whole reason meeting items carry a source timestamp is that a decision
/// written down stays checkable against what was actually said. So a returned
/// item keeps its source only if the timestamp lands inside a real segment,
/// and is dropped entirely if it cites audio that does not exist.
public enum Minutes {

    /// What one generation produced, before it is written to the store.
    public struct Draft: Equatable, Sendable {
        public var summary: String
        public var items: [MeetingItem]
        /// Items whose citation pointed at no real segment. Surfaced rather
        /// than hidden: it is the signal that the model is drifting.
        public var uncitedCount: Int

        public init(summary: String, items: [MeetingItem], uncitedCount: Int = 0) {
            self.summary = summary
            self.items = items
            self.uncitedCount = uncitedCount
        }

        public var isEmpty: Bool { summary.isEmpty && items.isEmpty }
    }

    public enum Failure: LocalizedError, Equatable {
        case noTranscript
        case noJSON(String)
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .noTranscript:
                return "This recording has no transcript yet."
            case .noJSON:
                return "The model did not return JSON."
            case .malformed(let detail):
                return "The model returned JSON that could not be read: \(detail)"
            }
        }

        /// The raw text, kept for the error sheet. A truncated echo of what
        /// actually came back is the only way to debug a bad generation.
        public var payload: String? {
            switch self {
            case .noJSON(let raw): return raw
            case .malformed, .noTranscript: return nil
            }
        }
    }

    // MARK: - Prompt

    /// The transcript as the model sees it: one line per speaker turn, each
    /// tagged with the millisecond it starts at.
    ///
    /// Milliseconds rather than `12:34`, because the model has to hand them
    /// back for the citation to be resolvable, and parsing a clock format out
    /// of a generated string is one more thing to get wrong.
    public static func transcript(of document: MeetingDocument) -> String {
        TranscriptGrouping.blocks(from: document.segments).map { block in
            let who = document.name(for: block.speakerId) ?? "Unknown"
            return "[\(block.startMs)] \(who): \(block.text)"
        }.joined(separator: "\n")
    }

    public static func prompt(for document: MeetingDocument) -> String {
        """
        You are writing the minutes of a meeting that has already been \
        transcribed. The transcript is code-switched Tagalog and English \
        (Taglish); write the minutes in English, but keep names, product names \
        and quoted phrases exactly as they were said.

        Return ONLY a JSON object, no prose and no code fence, of this shape:

        {
          "summary": "two to four sentences on what this meeting was about \
        and where it landed",
          "items": [
            {"kind": "keyPoint", "text": "...", "atMs": 12000, "owner": null}
          ]
        }

        "kind" is one of: keyPoint, decision, actionItem, question, followUp.
        "atMs" is the millisecond stamp of the turn the item came from, copied \
        from the [brackets] in the transcript below. Copy one that is actually \
        there; do not compute or estimate it.
        "owner" is the speaker responsible, for actionItem and followUp only, \
        otherwise null.

        Rules:
        - Only write down things that were actually said. Do not infer \
        decisions that were merely discussed, and do not invent action items \
        to make the list look complete.
        - An empty list is a correct answer when the meeting contained none of \
        that kind.
        - Keep each item to one sentence.

        Meeting: \(document.title)
        Duration: \(TimeFormat.duration(ms: document.durationMs))

        TRANSCRIPT
        \(transcript(of: document))
        """
    }

    // MARK: - Parsing

    private struct Wire: Decodable {
        struct Item: Decodable {
            var kind: String
            var text: String
            var atMs: Int?
            var owner: String?
        }
        var summary: String?
        var items: [Item]?
    }

    /// Pulls the JSON object out of whatever the model wrapped it in.
    ///
    /// Asking for "no code fence" works most of the time, which is not the
    /// same as always.
    static func extractJSON(_ raw: String) -> String? {
        guard let open = raw.firstIndex(of: "{"),
              let close = raw.lastIndex(of: "}"), open < close
        else { return nil }
        return String(raw[open...close])
    }

    public static func parse(_ raw: String, against segments: [Segment]) throws -> Draft {
        guard let json = extractJSON(raw) else { throw Failure.noJSON(raw) }
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: Data(json.utf8))
        } catch {
            throw Failure.malformed(error.localizedDescription)
        }

        var items: [MeetingItem] = []
        var uncited = 0
        for row in wire.items ?? [] {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let kind = MeetingItemKind(rawValue: row.kind) else { continue }

            let source = row.atMs.flatMap { cite($0, in: segments) }
            if row.atMs != nil && source == nil { uncited += 1 }

            let owner = kind.isCheckable
                ? row.owner?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                : nil

            items.append(MeetingItem(
                kind: kind,
                text: text,
                owner: owner,
                sourceSegmentId: source?.id,
                sourceMs: source?.startMs
            ))
        }

        return Draft(
            summary: (wire.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            items: items,
            uncitedCount: uncited
        )
    }

    /// The segment a citation points at, or nil if it points at nothing.
    ///
    /// Strict on purpose. Snapping a stray timestamp to the nearest segment
    /// would produce a note that looks sourced and seeks to the wrong moment,
    /// which is the one failure the source link exists to prevent. A citation
    /// that lands in a gap between segments -- silence -- is not a citation.
    static func cite(_ ms: Int, in segments: [Segment]) -> Segment? {
        guard let index = TranscriptGrouping.segmentIndex(at: ms, in: segments) else { return nil }
        let segment = segments[index]
        return ms < segment.endMs ? segment : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
