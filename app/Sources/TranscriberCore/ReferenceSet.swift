import Foundation

/// Corrected transcripts as a reference set for the evaluation harness.
///
/// Every edit a person makes is stored beside the raw model text
/// (`Segment.text` against `Segment.textClean`). A recording with edits is
/// therefore a scored pair: the raw text is the hypothesis, the edited text
/// is the reference, and the audio is on disk. The project had no real Taglish
/// references before this: the synthetic clip and one 25-second excerpt. The
/// folder this describes is what `eval/compare_language.py --manifest` reads,
/// so each tuning decision can be measured on the user's own meetings.
///
/// The reference is the whole transcript with the edits applied, and not the
/// edited lines alone. A line the person left alone is a line they accepted.
public enum ReferenceSet {

    /// One recording in `manifest.json`. The keys `id`, `audio`, `ref` and
    /// `category` are what the harness reads; the rest is for the reader.
    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        public var audio: String
        public var ref: String
        public var category: String
        public var raw: String
        public var edits: String
        public var title: String
        public var durationMs: Int

        public init(id: String, audio: String, ref: String, category: String = "own",
                    raw: String, edits: String, title: String, durationMs: Int) {
            self.id = id
            self.audio = audio
            self.ref = ref
            self.category = category
            self.raw = raw
            self.edits = edits
            self.title = title
            self.durationMs = durationMs
        }
    }

    /// One recording in `summary.md`, with the number that needs no decode:
    /// the raw model text scored against the corrections.
    public struct Summary: Equatable, Sendable {
        public var title: String
        public var durationMs: Int
        public var segments: Int
        public var correctedSegments: Int
        public var referenceWords: Int
        public var rawWER: Double
    }

    /// A row counts as corrected when the edit differs from the raw text. An
    /// edit that restored the raw text is not a correction.
    public static func isCorrected(_ segment: Segment) -> Bool {
        guard let clean = segment.textClean else { return false }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
            != segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hasCorrections(_ segments: [Segment]) -> Bool {
        segments.contains(where: isCorrected)
    }

    /// The transcript with the edits applied, one row per line.
    public static func referenceText(_ segments: [Segment]) -> String {
        lines(segments.map(\.displayText))
    }

    /// The transcript as the model wrote it, one row per line.
    public static func rawText(_ segments: [Segment]) -> String {
        lines(segments.map(\.text))
    }

    /// The corrected rows only, as tab-separated `startMs`, raw, corrected.
    /// For a reader who wants to see what kind of error the model makes.
    public static func editsTSV(_ segments: [Segment]) -> String {
        var out = ["startMs\traw\tcorrected"]
        for segment in segments.sorted(by: { $0.startMs < $1.startMs }) where isCorrected(segment) {
            out.append([String(segment.startMs), flat(segment.text), flat(segment.textClean ?? "")]
                .joined(separator: "\t"))
        }
        return out.joined(separator: "\n") + "\n"
    }

    public static func summary(title: String, durationMs: Int, segments: [Segment]) -> Summary {
        let reference = referenceText(segments)
        return Summary(
            title: title,
            durationMs: durationMs,
            segments: segments.count,
            correctedSegments: segments.filter(isCorrected).count,
            referenceWords: WordErrorRate.words(reference).count,
            rawWER: WordErrorRate.score(reference: reference, hypothesis: rawText(segments))
        )
    }

    public static func manifestJSON(_ entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    /// The table a reader opens first. The pooled row weights each recording
    /// by its reference words, as the harness does.
    public static func summaryMarkdown(_ summaries: [Summary]) -> String {
        var out = [
            "# Corrections as references",
            "",
            "Raw WER is the model text scored against your corrections, with no new decode.",
            "",
            "| Recording | Length | Rows | Corrected rows | Reference words | Raw WER |",
            "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
        var words = 0
        var errors = 0.0
        for summary in summaries {
            out.append("| \(summary.title.replacingOccurrences(of: "|", with: "/")) "
                       + "| \(TimeFormat.duration(ms: summary.durationMs)) "
                       + "| \(summary.segments) | \(summary.correctedSegments) "
                       + "| \(summary.referenceWords) "
                       + "| \(String(format: "%.1f%%", summary.rawWER * 100)) |")
            words += summary.referenceWords
            errors += summary.rawWER * Double(summary.referenceWords)
        }
        if words > 0 {
            out.append("| **All** | | | | \(words) | **\(String(format: "%.1f%%", errors / Double(words) * 100))** |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// What to run. Written into the folder so the reader does not have to
    /// find the documentation first.
    public static func readme(count: Int) -> String {
        """
        # Reference set from your corrections

        \(count) recording\(count == 1 ? "" : "s") with corrected lines. For each one:

        - `audio/<id>.<ext>`: a copy of the recording.
        - `refs/<id>.txt`: the transcript with your edits applied, one row per line. The reference.
        - `raw/<id>.txt`: the transcript as the model wrote it, one row per line.
        - `edits/<id>.tsv`: the corrected rows only, with the raw text beside each.

        `manifest.json` lists the pairs for the evaluation harness. `summary.md` scores the raw
        text against your corrections, with no new decode.

        To score a configuration against these references, from the repository root:

            python3 eval/compare_language.py --manifest <this folder>/manifest.json \\
                --bin app/.build/release/transcribe --models models --arms tl

        These files hold real meetings. Do not attach them to a public issue.
        """
    }

    private static func lines(_ rows: [String]) -> String {
        rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") + "\n"
    }

    private static func flat(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
