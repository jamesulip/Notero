import Foundation

// Automatic notes: the pure half.
//
// An on-device language model reads the transcript in parts and writes a
// summary and typed notes into the same shape the user fills by hand --
// `MeetingItemKind` rows with a source timestamp. Nothing here calls a model.
// This file decides how the transcript is cut into parts that fit a small
// context window, how the model's answer is checked and resolved back to a
// transcript line, and how a draft is measured against the transcript and
// against hand-written notes. The backends are in TranscriberEngine.

// MARK: - Availability and errors

/// Whether a notes model can run on this Mac, and if not, why.
public enum NotesAvailability: Equatable, Sendable {
    case available
    /// The system framework is not on this version of macOS.
    case needsNewerMacOS
    case appleIntelligenceOff
    /// macOS is still downloading the system model.
    case modelNotReady
    case deviceNotEligible
    case unavailable(String)

    public var isAvailable: Bool { self == .available }

    /// What the app shows in place of the button.
    public var message: String {
        switch self {
        case .available:
            return "Ready."
        case .needsNewerMacOS:
            return "Automatic notes need macOS 26 or later."
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in System Settings to draft notes on this Mac."
        case .modelNotReady:
            return "macOS is still downloading the Apple Intelligence model. Try again later."
        case .deviceNotEligible:
            return "This Mac cannot run the Apple Intelligence model."
        case .unavailable(let why):
            return why
        }
    }
}

public enum NotesError: LocalizedError, Equatable, Sendable {
    case unavailable(NotesAvailability)
    /// One part did not fit the model's window even after it was halved
    /// down to a single line.
    case partTooLong
    /// The model's content filter refused a part.
    case contentRefused
    /// The model does not accept the language of the transcript. Measured on
    /// 2026-09-06: Apple's model refuses a part at 50 % Tagalog words and
    /// accepts it at 28 % (docs/FINDINGS.md, finding 13).
    case languageNotSupported
    case noTranscript
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return availability.message
        case .partTooLong:
            return "One part of the transcript is too long for the model, even as a single line."
        case .contentRefused:
            return "The model's content filter refused this part of the transcript."
        case .languageNotSupported:
            return "The model does not accept the language of this transcript. Apple's model "
                 + "refuses text that is mostly Tagalog."
        case .noTranscript:
            return "There is no transcript to read."
        case .failed(let why):
            return why
        }
    }
}

/// The language of the notes the model writes.
public enum NotesStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case english, asSpoken

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .english: return "English"
        case .asSpoken: return "As spoken"
        }
    }

    public var detail: String {
        switch self {
        case .english:
            return "The notes are in English, whatever language the speakers used."
        case .asSpoken:
            return "The notes use the same mix of languages that the speakers used."
        }
    }
}

// MARK: - The draft

/// What the model wrote for a recording, before the user has accepted any of
/// it. A value, so the review sheet can show it, the CLI can score it and a
/// test can build one.
public struct NotesDraft: Codable, Equatable, Sendable {
    public var summary: String
    public var items: [Item]
    /// Which backend and model wrote it.
    public var modelId: String
    public var style: NotesStyle
    /// How many parts the transcript was cut into.
    public var chunkCount: Int
    public var elapsedMs: Int
    /// Parts that were skipped, and why. Shown with the draft, never hidden.
    public var warnings: [String]

    public struct Item: Identifiable, Codable, Equatable, Sendable {
        public var id: UUID
        public var kind: MeetingItemKind
        public var text: String
        /// The transcript line the note came from, when the model named a
        /// timestamp inside the part it was reading. Nil when it did not: no
        /// back-link is better than a wrong one.
        public var sourceMs: Int?
        public var sourceSegmentId: UUID?

        public init(id: UUID = UUID(), kind: MeetingItemKind, text: String,
                    sourceMs: Int? = nil, sourceSegmentId: UUID? = nil) {
            self.id = id
            self.kind = kind
            self.text = text
            self.sourceMs = sourceMs
            self.sourceSegmentId = sourceSegmentId
        }
    }

    public init(summary: String, items: [Item], modelId: String, style: NotesStyle,
                chunkCount: Int, elapsedMs: Int = 0, warnings: [String] = []) {
        self.summary = summary
        self.items = items
        self.modelId = modelId
        self.style = style
        self.chunkCount = chunkCount
        self.elapsedMs = elapsedMs
        self.warnings = warnings
    }

    public func items(_ kind: MeetingItemKind) -> [Item] { items.filter { $0.kind == kind } }

    public var isEmpty: Bool { summary.isEmpty && items.isEmpty }

    /// The draft as Markdown, in the order of the minutes export: summary,
    /// then the five lists with the timestamp of each note. What the CLI
    /// prints.
    public func markdown(title: String) -> String {
        var lines = ["# \(title)", "", "*Draft by \(modelId), \(style.label.lowercased()), "
                     + "\(chunkCount) part\(chunkCount == 1 ? "" : "s"), \(TimeFormat.short(ms: elapsedMs))*", ""]
        for warning in warnings { lines.append("> \(warning)") }
        if !warnings.isEmpty { lines.append("") }
        if !summary.isEmpty {
            lines.append("## Summary")
            lines.append(summary)
            lines.append("")
        }
        for kind in MeetingItemKind.allCases {
            let rows = items(kind)
            guard !rows.isEmpty else { continue }
            lines.append("## \(kind.plural)")
            for item in rows {
                var row = kind.isCheckable ? "- [ ] " : "- "
                row += item.text
                if let at = item.sourceMs { row += " *(\(TimeFormat.short(ms: at)))*" }
                lines.append(row)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}

/// Where a draft is, for the pane and the row.
public struct NotesProgress: Equatable, Sendable {
    public enum Stage: Equatable, Sendable { case reading, summarizing }

    public var stage: Stage
    public var chunksDone: Int
    public var chunkCount: Int

    public init(stage: Stage, chunksDone: Int, chunkCount: Int) {
        self.stage = stage
        self.chunksDone = chunksDone
        self.chunkCount = chunkCount
    }

    /// Reading is nine tenths of the work; the summary is one call.
    public var fraction: Double {
        guard chunkCount > 0 else { return 0 }
        switch stage {
        case .reading: return 0.9 * Double(chunksDone) / Double(chunkCount)
        case .summarizing: return 0.95
        }
    }

    public var label: String {
        switch stage {
        case .reading: return "Part \(min(chunksDone + 1, chunkCount)) of \(chunkCount)"
        case .summarizing: return "Writing the summary"
        }
    }
}

// MARK: - Parts of the transcript

/// One stretch of the transcript, cut to fit a model's window, with the
/// line each timestamp points back to.
public struct NotesChunk: Equatable, Sendable {
    public var index: Int
    public var startMs: Int
    public var endMs: Int
    public var lines: [Line]

    /// One speaker turn, or one segment of a turn that was too long.
    public struct Line: Equatable, Sendable {
        public var startMs: Int
        public var segmentId: UUID
        public var speaker: String?
        public var text: String

        public init(startMs: Int, segmentId: UUID, speaker: String?, text: String) {
            self.startMs = startMs
            self.segmentId = segmentId
            self.speaker = speaker
            self.text = text
        }

        /// `[12:34]`, as the model sees it and is asked to copy it back.
        public var stamp: String { TimeFormat.short(ms: startMs) }

        public var rendered: String {
            "[\(stamp)] " + (speaker.map { "\($0): " } ?? "") + text
        }
    }

    public init(index: Int, lines: [Line], endMs: Int) {
        self.index = index
        self.lines = lines
        self.startMs = lines.first?.startMs ?? 0
        self.endMs = max(endMs, startMs)
    }

    /// The text the model reads: one line per turn.
    public var text: String { lines.map(\.rendered).joined(separator: "\n") }

    public var characterCount: Int {
        lines.reduce(0) { $0 + $1.rendered.count + 1 }
    }

    /// "12:34–18:02", for a warning about this part.
    public var span: String {
        "\(TimeFormat.short(ms: startMs))–\(TimeFormat.short(ms: endMs))"
    }
}

/// Cuts a transcript into parts that fit a small context window.
///
/// Apple's model has a window of 4,096 tokens for the instructions, the part
/// and the answer together. Tagalog costs more tokens per word than English,
/// so the budget is stated in characters and kept low. A part is never cut
/// inside a turn unless the turn alone is over budget.
public enum NotesChunker {

    /// About 1,400 tokens of Taglish. Leaves room for the instructions, the
    /// schema and an answer of ten notes.
    public static let defaultMaxCharacters = 5_000

    /// Turns longer than this are cut at segment boundaries first, so that a
    /// monologue does not become one 6,000-character line.
    public static let maxTurnMs = 30_000

    /// One line per turn, with the speaker's display name.
    public static func lines(from segments: [Segment], speakers: [SpeakerLabel],
                             maxCharacters: Int = defaultMaxCharacters) -> [NotesChunk.Line] {
        let names = Dictionary(speakers.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        func name(_ id: String?) -> String? {
            guard let id else { return nil }
            return names[id] ?? SpeakerLabel.defaultName(for: id)
        }
        var out: [NotesChunk.Line] = []
        for block in TranscriptGrouping.blocks(from: segments, maxBlockMs: maxTurnMs) {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.count + 24 <= maxCharacters {
                out.append(NotesChunk.Line(startMs: block.startMs, segmentId: block.id,
                                           speaker: name(block.speakerId), text: text))
            } else {
                // A turn over budget: one line per segment, so the packer can
                // cut between them.
                for segment in block.segments {
                    let piece = segment.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !piece.isEmpty else { continue }
                    out.append(NotesChunk.Line(startMs: segment.startMs, segmentId: segment.id,
                                               speaker: name(segment.speakerId), text: piece))
                }
            }
        }
        return out
    }

    /// Packs lines into parts of at most `maxCharacters`. A single line over
    /// the budget is a part of its own; `halves(of:)` cannot cut it further
    /// and the pipeline reports it.
    public static func chunks(lines: [NotesChunk.Line], endMs: Int,
                              maxCharacters: Int = defaultMaxCharacters) -> [NotesChunk] {
        var out: [NotesChunk] = []
        var bucket: [NotesChunk.Line] = []
        var count = 0

        func flush(next: NotesChunk.Line?) {
            guard !bucket.isEmpty else { return }
            out.append(NotesChunk(index: out.count, lines: bucket, endMs: next?.startMs ?? endMs))
            bucket.removeAll()
            count = 0
        }

        for line in lines {
            let cost = line.rendered.count + 1
            if !bucket.isEmpty, count + cost > maxCharacters { flush(next: line) }
            bucket.append(line)
            count += cost
        }
        flush(next: nil)
        return out
    }

    public static func chunks(from segments: [Segment], speakers: [SpeakerLabel],
                              maxCharacters: Int = defaultMaxCharacters) -> [NotesChunk] {
        let endMs = segments.map(\.endMs).max() ?? 0
        return chunks(lines: lines(from: segments, speakers: speakers, maxCharacters: maxCharacters),
                      endMs: endMs, maxCharacters: maxCharacters)
    }

    /// The part cut in two at a line boundary, for a retry after the model
    /// said the part was too long. Nil when it is one line already.
    public static func halves(of chunk: NotesChunk) -> [NotesChunk]? {
        guard chunk.lines.count >= 2 else { return nil }
        let middle = chunk.lines.count / 2
        let first = Array(chunk.lines[..<middle])
        let second = Array(chunk.lines[middle...])
        return [
            NotesChunk(index: chunk.index, lines: first, endMs: second[0].startMs),
            NotesChunk(index: chunk.index, lines: second, endMs: chunk.endMs),
        ]
    }
}

// MARK: - What the model says about one part

/// The model's answer for one part, as it came back and before it is checked.
public struct ChunkNotes: Equatable, Sendable {
    public var summary: String
    public var items: [Item]

    public struct Item: Equatable, Sendable {
        public var kind: MeetingItemKind
        public var text: String
        /// The timestamp as the model wrote it: "12:34", "[12:34]", "1:02:03".
        public var at: String?

        public init(kind: MeetingItemKind, text: String, at: String?) {
            self.kind = kind
            self.text = text
            self.at = at
        }
    }

    public init(summary: String, items: [Item]) {
        self.summary = summary
        self.items = items
    }

    /// Reads the JSON a text-only backend is asked for:
    ///
    ///     {"summary": "...", "items": [{"kind": "decision", "text": "...", "at": "12:34"}]}
    ///
    /// Tolerant of prose around the object and of a kind written as its label
    /// ("Action Item") rather than its raw value. Nil when there is no object
    /// to read, which the caller counts as a failed part.
    public static func parse(json text: String) -> ChunkNotes? {
        parseStrict(text) ?? parseLoose(text)
    }

    /// The object as valid JSON.
    static func parseStrict(_ text: String) -> ChunkNotes? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"),
              open < close else { return nil }
        let body = String(text[open...close])
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
                as? [String: Any]
        else { return nil }
        let summary = (object["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawItems = object["items"] as? [[String: Any]] ?? []
        return ChunkNotes(summary: summary, items: rawItems.compactMap(item(from:)))
    }

    /// The object as a small model writes it: the summary string and each
    /// item object read on their own, whatever the brackets around them.
    /// Measured on 2026-09-06, Qwen2.5-3B closed 8 of 14 answers with `}}}`
    /// and no `]`, and every one of them held usable items.
    static func parseLoose(_ text: String) -> ChunkNotes? {
        guard text.contains("\"summary\"") || text.contains("\"items\"") else { return nil }
        let summary = string(forKey: "summary", in: text) ?? ""
        var items: [Item] = []
        for object in matches(of: #"\{[^{}]*\}"#, in: text) {
            guard object.contains("\"text\""),
                  let data = object.data(using: .utf8),
                  let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let item = item(from: raw) else { continue }
            items.append(item)
        }
        guard !summary.isEmpty || !items.isEmpty else { return nil }
        return ChunkNotes(summary: summary, items: items)
    }

    static func item(from raw: [String: Any]) -> Item? {
        guard let text = raw["text"] as? String,
              let kind = kind(named: raw["kind"] as? String ?? "") else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let at = raw["at"] as? String ?? (raw["at"] as? NSNumber).map { TimeFormat.short(ms: $0.intValue * 1000) }
        return Item(kind: kind, text: trimmed, at: at)
    }

    /// The JSON string value after `"key":`, unescaped. Nil when there is none.
    static func string(forKey key: String, in text: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let data = String(text[range]).data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
        else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// "decision", "Decision", "action item", "actionItem", "action_item",
    /// "follow-up"... to the kind. Nil for anything else.
    public static func kind(named name: String) -> MeetingItemKind? {
        let key = name.lowercased().filter { $0.isLetter }
        for kind in MeetingItemKind.allCases {
            if kind.rawValue.lowercased() == key
                || kind.label.lowercased().filter({ $0.isLetter }) == key { return kind }
        }
        switch key {
        case "action", "task", "todo": return .actionItem
        case "followup", "follow": return .followUp
        case "key", "point", "keypoints", "note", "fact": return .keyPoint
        case "decided", "decisions", "agreement", "agreed": return .decision
        case "questions", "open", "openquestion": return .question
        default: return nil
        }
    }
}

// MARK: - Resolving and merging

/// Turns the model's answers into draft items with back-links, and merges
/// the answers for several parts into one list.
public enum NotesReducer {

    /// "12:34", "[12:34]", "1:02:03", "at 12:34" to milliseconds. Nil for
    /// anything that is not a clock reading.
    public static func parseStamp(_ text: String?) -> Int? {
        guard let text else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789:")
        let cleaned = text.unicodeScalars.filter { allowed.contains($0) }
        let candidate = String(String.UnicodeScalarView(cleaned))
        guard candidate.contains(":") else { return nil }
        return TimeFormat.parse(candidate)
    }

    /// Draft items for one part. An item keeps its back-link only when the
    /// timestamp the model wrote falls inside the part it was reading; the
    /// link then points at the line at or before that moment. A timestamp
    /// outside the part is a copy error, and the item goes in with no link.
    public static func resolve(_ notes: ChunkNotes, in chunk: NotesChunk) -> [NotesDraft.Item] {
        notes.items.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var draft = NotesDraft.Item(kind: item.kind, text: text)
            if let ms = parseStamp(item.at), ms >= chunk.startMs, ms <= chunk.endMs,
               let line = chunk.lines.last(where: { $0.startMs <= ms }) ?? chunk.lines.first {
                draft.sourceMs = line.startMs
                draft.sourceSegmentId = line.segmentId
            }
            return draft
        }
    }

    /// Drops a note that says what an earlier note already said. Two notes
    /// of the same kind are the same when they share most of their content
    /// words. The first one stays; it has the earlier timestamp.
    public static func dedupe(_ items: [NotesDraft.Item], threshold: Double = 0.7) -> [NotesDraft.Item] {
        var kept: [(item: NotesDraft.Item, words: Set<String>)] = []
        for item in items {
            let words = contentWords(item.text)
            let duplicate = kept.contains { previous in
                previous.item.kind == item.kind && similarity(previous.words, words) >= threshold
            }
            if !duplicate { kept.append((item, words)) }
        }
        return kept.map(\.item)
    }

    /// Jaccard over content words; 1 when both are empty.
    public static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 1 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    /// The words that carry meaning: lower-cased, letters and digits only,
    /// three characters or more, and not a function word in English or
    /// Tagalog.
    public static func contentWords(_ text: String) -> Set<String> {
        var out: Set<String> = []
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "'" }) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
            guard word.count >= 3, !stopWords.contains(word) else { continue }
            out.insert(word)
        }
        return out
    }

    static let stopWords: Set<String> = Set("""
    the and for that this with have from are was were will would can could should they them their
    there here what when where which who whom how why not but all any some also into onto about
    then than been being does did doing has had our you your his her its out over under after
    before because while just very more most much many such only same other another each both
    ang mga ito iyan iyon yan yun yung nito dito diyan doon hindi wala walang may mayroon meron
    kung kasi para pero tapos lang lamang din rin naman daw raw kaya dahil pwede puwede dapat
    baka siguro talaga medyo masyado lahat bawat ngayon kanina mamaya muna ulit pala nga kaso
    saka sana yata kapag habang bago hanggang mula tungkol ganito ganyan ganun ganon mas sobrang
    ako ikaw siya kami tayo kayo sila natin namin ninyo nila niya kita nyo kayong ating
    """.split(whereSeparator: \.isWhitespace).map(String.init))
}

// MARK: - Measurement

/// The checks the CLI reports and the tests assert. None of this decides
/// anything in the app; it is how a backend is measured before it is trusted.
public enum NotesScoring {

    /// How much of each note's content is in the transcript near its
    /// timestamp. A note whose words are not there is the model inventing.
    ///
    /// A note in English about Tagalog speech scores lower by construction:
    /// the words differ although the meaning is the same. Compare the two
    /// styles on the same transcript with that in mind.
    public struct Grounding: Codable, Equatable, Sendable {
        public var itemsScored: Int
        public var meanOverlap: Double
        /// Items whose overlap is under `threshold`.
        public var ungrounded: Int
        public static let threshold = 0.4

        public init(itemsScored: Int, meanOverlap: Double, ungrounded: Int) {
            self.itemsScored = itemsScored
            self.meanOverlap = meanOverlap
            self.ungrounded = ungrounded
        }
    }

    /// `windowMs` either side of the note's timestamp is what counts as
    /// "near". A note with no timestamp is checked against the whole
    /// transcript.
    public static func grounding(of items: [NotesDraft.Item], in segments: [Segment],
                                 windowMs: Int = 120_000) -> Grounding {
        let sorted = segments.sorted { $0.startMs < $1.startMs }
        let whole = NotesReducer.contentWords(sorted.map(\.displayText).joined(separator: " "))
        var overlaps: [Double] = []
        for item in items {
            let words = NotesReducer.contentWords(item.text)
            guard !words.isEmpty else { continue }
            let nearby: Set<String>
            if let at = item.sourceMs {
                let text = sorted
                    .filter { $0.endMs >= at - windowMs && $0.startMs <= at + windowMs }
                    .map(\.displayText).joined(separator: " ")
                nearby = NotesReducer.contentWords(text)
            } else {
                nearby = whole
            }
            overlaps.append(Double(words.intersection(nearby).count) / Double(words.count))
        }
        let mean = overlaps.isEmpty ? 0 : overlaps.reduce(0, +) / Double(overlaps.count)
        return Grounding(itemsScored: overlaps.count, meanOverlap: mean,
                         ungrounded: overlaps.filter { $0 < Grounding.threshold }.count)
    }

    /// Which language a text leans to, by a list of Tagalog function words
    /// and the hyphenated affixes of Taglish ("i-send", "nag-review"). A
    /// heuristic for one comparison: the transcript against the notes
    /// written from it. `eval/langscore.py` has the fuller version.
    public struct LanguageMix: Codable, Equatable, Sendable {
        public var words: Int
        public var tagalogShare: Double

        public init(words: Int, tagalogShare: Double) {
            self.words = words
            self.tagalogShare = tagalogShare
        }
    }

    public static func languageMix(of text: String) -> LanguageMix {
        var words = 0
        var tagalog = 0
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))
            guard !word.isEmpty else { continue }
            words += 1
            if tagalogWords.contains(word) || hasTagalogAffix(word) { tagalog += 1 }
        }
        return LanguageMix(words: words, tagalogShare: words > 0 ? Double(tagalog) / Double(words) : 0)
    }

    static func hasTagalogAffix(_ word: String) -> Bool {
        guard let dash = word.firstIndex(of: "-"), dash > word.startIndex, dash < word.index(before: word.endIndex)
        else { return false }
        return tagalogAffixes.contains(String(word[..<dash]))
    }

    static let tagalogAffixes: Set<String> = [
        "i", "na", "nag", "mag", "pa", "ma", "pina", "ipa", "ipina", "ka", "um", "in", "maka", "naka",
        "magpa", "nagpa", "pag", "pinag", "mapa", "napa", "pinaka", "mang", "maki", "naki", "pakiki",
        "nakiki", "makipag", "nakipag", "mai", "nai",
    ]

    /// Function words and everyday vocabulary. "at", "may", "no" and "so"
    /// are left out: they are Tagalog words that also occur in English
    /// notes, and here they would count against English.
    static let tagalogWords: Set<String> = Set("""
    ang ng mga sa na ay si ni kay kina nina ko mo niya namin natin ninyo nila ako ikaw ka siya kami
    tayo kayo sila ito iyan iyon yan yun yung nito niyan niyon dito diyan doon hindi oo opo wala
    walang mayroon meron kung kasi para pero tapos lang lamang din rin naman ba po ho daw raw kaya
    dahil kailangan pwede puwede dapat gusto ayaw baka siguro talaga sobra medyo masyado lahat bawat
    ilan marami konti kaunti isa dalawa tatlo apat lima ngayon kanina mamaya bukas kahapon araw gabi
    umaga hapon linggo buwan taon oras sandali muna ulit uli pala nga eh kaso saka sana yata pag
    kapag habang bago pagkatapos hanggang mula tungkol ganito ganyan ganoon ganun ganon mas pinaka
    sobrang gawa gawin ginawa gagawin sabi sinabi kita nakita makita tingin tingnan alam alamin
    kilala punta pumunta bili bumili kain kumain uwi bigay ibigay kuha kunin dala dalhin tawag usap
    hintay tulong trabaho pera bahay tao anak asawa kaibigan kasama kumpanya opisina tanong sagot
    problema ayos sige salamat pasensya tama mali totoo sarili ganda mahal mura malaki maliit
    mahaba maikli matagal mabilis mabagal madali mahirap luma marunong kayong nyo ating
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// How many hand-written notes the draft also has, and how many draft
    /// notes match a hand-written one. A match shares at least `threshold`
    /// of the hand-written note's content words.
    public struct Coverage: Codable, Equatable, Sendable {
        public var reference: Int
        public var covered: Int
        public var draft: Int
        public var matched: Int

        public init(reference: Int, covered: Int, draft: Int, matched: Int) {
            self.reference = reference
            self.covered = covered
            self.draft = draft
            self.matched = matched
        }
    }

    public static func coverage(reference: [MeetingItem], draft: [NotesDraft.Item],
                                threshold: Double = 0.5) -> Coverage {
        let referenceWords = reference.map { NotesReducer.contentWords($0.text) }
        let draftWords = draft.map { NotesReducer.contentWords($0.text) }
        var matched = Set<Int>()
        var covered = 0
        for words in referenceWords where !words.isEmpty {
            var hit = false
            for (index, candidate) in draftWords.enumerated() {
                let shared = Double(words.intersection(candidate).count) / Double(words.count)
                if shared >= threshold {
                    hit = true
                    matched.insert(index)
                }
            }
            if hit { covered += 1 }
        }
        return Coverage(reference: reference.count, covered: covered,
                        draft: draft.count, matched: matched.count)
    }
}

// MARK: - The prompt

/// What every backend tells its model. In one place so that the Swift
/// backends and the Python harness in `eval/` ask the same thing, and a
/// change to the wording is measured once.
public enum NotesPrompt {

    public static func instructions(style: NotesStyle) -> String {
        let language: String
        switch style {
        case .english:
            language = "Write the notes in English."
        case .asSpoken:
            language = "Write the notes in the same mix of languages that the speakers used."
        }
        return """
        You take notes for a meeting. The transcript is from a business meeting in the Philippines. \
        The speakers mix Tagalog and English. Each line starts with a timestamp in square brackets \
        and the name of the speaker. \(language) Write only what the transcript supports. Do not \
        invent a name, a number or a decision. Keep names, product names and numbers exactly as \
        written. A decision is something the group agreed. An action item is a task that one \
        person agreed to do. A question is one that was asked and not answered. A follow-up is \
        something to return to later. A key point is a fact or a position worth keeping.
        """
    }

    /// The request for one part, for a backend that returns text rather than
    /// a typed value. The answer is read by `ChunkNotes.parse(json:)`.
    public static func request(for chunk: NotesChunk) -> String {
        """
        Transcript, part \(chunk.index + 1):

        \(chunk.text)

        Answer with one JSON object and nothing else, in this form:
        {"summary": "two or three sentences on what this part was about", \
        "items": [{"kind": "keyPoint|decision|actionItem|question|followUp", \
        "text": "the note in one sentence", "at": "the timestamp of the line it comes from, copied exactly, for example 12:34"}]}
        Give at most ten items. Leave the list empty when this part has nothing worth keeping.
        """
    }

    /// The request for the whole-meeting summary from the summaries of the
    /// parts.
    public static func summaryRequest(partSummaries: [String], title: String) -> String {
        let numbered = partSummaries.enumerated()
            .map { "Part \($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
        return """
        These are the summaries of the parts of the meeting "\(title)", in order:

        \(numbered)

        Write one summary of the whole meeting in three to six sentences: what it was about, \
        what was decided, and what is still open. Answer with the summary only.
        """
    }
}
