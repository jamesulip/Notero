import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, markdown, srt, vtt, json

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        default: return rawValue
        }
    }

    public var label: String {
        switch self {
        case .txt: return "Plain Text"
        case .markdown: return "Markdown Minutes"
        case .srt: return "SubRip (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .json: return "JSON"
        }
    }

    public var detail: String {
        switch self {
        case .txt: return "The transcript with speaker labels, and the meeting notes."
        case .markdown: return "Minutes with headings, attendees, action items with "
            + "checkboxes, and the transcript. It pastes into email, chat and wikis."
        case .srt: return "Subtitle cues for video editors."
        case .vtt: return "Subtitle cues for web players."
        case .json: return "Everything: the segments, the speakers, the bookmarks and the notes."
        }
    }
}

/// What to leave out of an export. Empty means everything.
///
/// A two-hour meeting is often exported for one person's part of it, or for
/// the half hour a decision was argued. Filtering here, at export, keeps the
/// stored transcript whole.
public struct ExportOptions: Sendable, Equatable {
    /// Only these speakers' lines. Nil keeps every line, attributed or not.
    public var speakerIds: Set<String>?
    /// Only lines starting at or after this point.
    public var fromMs: Int?
    /// Only lines starting before this point.
    public var toMs: Int?

    public init(speakerIds: Set<String>? = nil, fromMs: Int? = nil, toMs: Int? = nil) {
        self.speakerIds = speakerIds
        self.fromMs = fromMs
        self.toMs = toMs
    }

    public static let everything = ExportOptions()

    public var isFiltering: Bool { speakerIds != nil || fromMs != nil || toMs != nil }

    /// The document with only what the options keep. Bookmarks and notes
    /// with a timestamp follow the time range; notes with none are kept.
    public func apply(to document: MeetingDocument) -> MeetingDocument {
        guard isFiltering else { return document }
        var out = document
        out.segments = document.segments.filter { segment in
            if let speakerIds, !(segment.speakerId.map(speakerIds.contains) ?? false) { return false }
            return inRange(segment.startMs)
        }
        out.bookmarks = document.bookmarks.filter { inRange($0.atMs) }
        out.items = document.items.filter { $0.sourceMs.map(inRange) ?? true }
        if let speakerIds {
            out.speakers = document.speakers.filter { speakerIds.contains($0.id) }
        }
        return out
    }

    private func inRange(_ ms: Int) -> Bool {
        if let fromMs, ms < fromMs { return false }
        if let toMs, ms >= toMs { return false }
        return true
    }
}

/// Renders a `MeetingDocument`. Pure: no store, no file system, no clock.
public enum Exporter {

    public static func render(_ format: ExportFormat, document: MeetingDocument,
                              options: ExportOptions = .everything) -> String {
        let document = options.apply(to: document)
        switch format {
        case .txt: return txt(document)
        case .markdown: return markdown(document)
        case .srt: return srt(document)
        case .vtt: return vtt(document)
        case .json: return json(document)
        }
    }

    public static func filename(for document: MeetingDocument, format: ExportFormat) -> String {
        let safe = document.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = safe.isEmpty ? "Transcript" : safe
        return "\(stem).\(format.fileExtension)"
    }

    // MARK: - Plain text

    static func txt(_ document: MeetingDocument) -> String {
        var lines: [String] = [document.title]
        lines.append(Self.longDate.string(from: document.createdAt))
        if document.durationMs > 0 {
            lines.append("Duration: \(TimeFormat.duration(ms: document.durationMs))")
        }
        lines.append("")

        if !document.summary.isEmpty {
            lines.append("SUMMARY")
            lines.append(document.summary)
            lines.append("")
        }

        for kind in MeetingItemKind.allCases {
            let items = document.items(kind)
            guard !items.isEmpty else { continue }
            lines.append(kind.plural.uppercased())
            for item in items {
                var row = kind.isCheckable ? (item.isDone ? "[x] " : "[ ] ") : "- "
                row += item.text
                if let owner = item.owner, !owner.isEmpty { row += " (\(owner))" }
                if let at = item.sourceMs { row += "  [\(TimeFormat.short(ms: at))]" }
                lines.append(row)
            }
            lines.append("")
        }

        if !document.bookmarks.isEmpty {
            lines.append("BOOKMARKS")
            for bookmark in document.bookmarks.sorted(by: { $0.atMs < $1.atMs }) {
                lines.append("\(TimeFormat.short(ms: bookmark.atMs))  \(bookmark.displayLabel)")
            }
            lines.append("")
        }

        guard !document.segments.isEmpty else {
            return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        }

        lines.append("TRANSCRIPT")
        lines.append("")
        for block in TranscriptGrouping.blocks(from: document.segments) {
            if let name = document.name(for: block.speakerId) {
                lines.append("\(TimeFormat.short(ms: block.startMs))  \(name)")
            } else {
                lines.append(TimeFormat.short(ms: block.startMs))
            }
            lines.append(block.text)
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    // MARK: - Markdown

    /// Minutes first, transcript last: the reader of a pasted export wants
    /// the decisions before the two hours that produced them.
    static func markdown(_ document: MeetingDocument) -> String {
        var lines: [String] = ["# \(document.title)"]
        var facts = [Self.longDate.string(from: document.createdAt)]
        if document.durationMs > 0 { facts.append(TimeFormat.duration(ms: document.durationMs)) }
        if document.speakers.count > 1 { facts.append("\(document.speakers.count) speakers") }
        lines.append("*\(facts.joined(separator: " · "))*")
        lines.append("")

        if !document.speakers.isEmpty {
            lines.append("## Attendees")
            for speaker in document.speakers.sorted(by: { $0.speechMs > $1.speechMs }) {
                lines.append(speaker.speechMs > 0
                    ? "- \(speaker.displayName) (\(TimeFormat.coarse(ms: speaker.speechMs)))"
                    : "- \(speaker.displayName)")
            }
            lines.append("")
        }

        if !document.summary.isEmpty {
            lines.append("## Summary")
            lines.append(document.summary)
            lines.append("")
        }

        for kind in MeetingItemKind.allCases {
            let items = document.items(kind)
            guard !items.isEmpty else { continue }
            lines.append("## \(kind.plural)")
            for item in items {
                var row = kind.isCheckable ? (item.isDone ? "- [x] " : "- [ ] ") : "- "
                row += item.text
                if let owner = item.owner, !owner.isEmpty { row += " — \(owner)" }
                if let at = item.sourceMs { row += " *(\(TimeFormat.short(ms: at)))*" }
                lines.append(row)
            }
            lines.append("")
        }

        if !document.bookmarks.isEmpty {
            lines.append("## Bookmarks")
            for bookmark in document.bookmarks.sorted(by: { $0.atMs < $1.atMs }) {
                lines.append("- **\(TimeFormat.short(ms: bookmark.atMs))** \(bookmark.displayLabel)")
            }
            lines.append("")
        }

        if !document.segments.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            for block in TranscriptGrouping.blocks(from: document.segments) {
                let stamp = TimeFormat.short(ms: block.startMs)
                if let name = document.name(for: block.speakerId) {
                    lines.append("**\(stamp) · \(name)**  ")
                } else {
                    lines.append("**\(stamp)**  ")
                }
                lines.append(block.text)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    // MARK: - Subtitles

    static func srt(_ document: MeetingDocument) -> String {
        cues(document).enumerated().map { index, cue in
            """
            \(index + 1)
            \(TimeFormat.cue(ms: cue.startMs, comma: true)) --> \(TimeFormat.cue(ms: cue.endMs, comma: true))
            \(cue.speaker.map { "\($0): " } ?? "")\(cue.text)

            """
        }.joined(separator: "\n")
    }

    static func vtt(_ document: MeetingDocument) -> String {
        var lines = ["WEBVTT", ""]
        for cue in cues(document) {
            lines.append("\(TimeFormat.cue(ms: cue.startMs, comma: false)) --> \(TimeFormat.cue(ms: cue.endMs, comma: false))")
            // WebVTT has a voice span for exactly this.
            lines.append(cue.speaker.map { "<v \($0)>\(cue.text)" } ?? cue.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    struct Cue {
        var startMs: Int
        var endMs: Int
        var text: String
        var speaker: String?
    }

    /// Subtitle cues must be ordered and must not overlap, which stored
    /// segments are not guaranteed to be: word timings shift between decode
    /// passes and a later segment can start a millisecond before the previous
    /// one ended. Clamped here rather than in storage, so the transcript keeps
    /// the timings the model actually produced.
    static func cues(_ document: MeetingDocument) -> [Cue] {
        var out: [Cue] = []
        var floor = 0
        for segment in document.segments.sorted(by: { $0.startMs < $1.startMs }) {
            let text = segment.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = max(segment.startMs, floor)
            // A zero-length cue is legal but invisible in most players.
            let end = max(segment.endMs, start + 1)
            out.append(Cue(startMs: start, endMs: end, text: text,
                           speaker: document.name(for: segment.speakerId)))
            floor = end
        }
        return out
    }

    // MARK: - JSON

    static func json(_ document: MeetingDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document),
              let text = String(data: data, encoding: .utf8) else { return "{}\n" }
        return text + "\n"
    }

    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
