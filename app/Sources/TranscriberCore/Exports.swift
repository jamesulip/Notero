import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt, srt, vtt, json

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public var label: String {
        switch self {
        case .txt: return "Plain Text"
        case .srt: return "SubRip (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .json: return "JSON"
        }
    }

    public var detail: String {
        switch self {
        case .txt: return "Speaker-labelled transcript and the meeting notes."
        case .srt: return "Subtitle cues for video editors."
        case .vtt: return "Subtitle cues for web players."
        case .json: return "Everything: segments, speakers, bookmarks, notes."
        }
    }
}

/// Renders a `MeetingDocument`. Pure: no store, no file system, no clock.
public enum Exporter {

    public static func render(_ format: ExportFormat, document: MeetingDocument) -> String {
        switch format {
        case .txt: return txt(document)
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
