import Foundation

/// The human-readable form of an ``EvaluationReport`` or ``ComparisonReport``.
///
/// Deterministic like the JSON: fixed number formats, no clock, inputs in
/// manifest order. An unavailable figure prints as "unavailable" with its
/// reason, never as a blank or a zero.
public enum EvaluationMarkdown {

    public static func render(_ report: EvaluationReport) -> String {
        var out: [String] = []
        let c = report.corpus
        out.append("# ASR evaluation: \(cell(report.system.label))")
        out.append("")
        out.append("| | |")
        out.append("| --- | --- |")
        out.append("| Corpus | `\(cell(report.corpusId))` |")
        out.append("| Items scored | \(c.itemsScored) of \(c.itemsInManifest) |")
        out.append("| Configuration | `\(cell(report.config.id))` (schema \(report.config.schemaVersion)), fingerprint `\(report.configFingerprint.prefix(16))` |")
        out.append("| Scoring policy | `\(cell(report.config.scoring.id))` v\(report.config.scoring.version), fingerprint `\(report.scoringPolicyFingerprint.prefix(16))` |")
        out.append(contentsOf: provenanceRows(report.system, prefix: ""))
        out.append("")
        out.append("Policy: \(describe(report.config.scoring)).")
        out.append("")

        if !report.warnings.isEmpty {
            out.append("## Warnings")
            out.append("")
            for warning in report.warnings { out.append("- \(warning)") }
            out.append("")
        }

        out.append("## Accuracy")
        out.append("")
        out.append("| Metric | Value | \(percent(report.config.bootstrap.confidenceLevel)) interval | N | Sub | Del | Ins |")
        out.append("| --- | ---: | --- | ---: | ---: | ---: | ---: |")
        out.append("| WER | \(rate(c.wer)) | \(interval(c.werInterval)) | \(c.words.referenceLength) | \(c.words.substitutions) | \(c.words.deletions) | \(c.words.insertions) |")
        out.append("| CER | \(rate(c.cer)) | \(interval(c.cerInterval)) | \(c.characters.referenceLength) | \(c.characters.substitutions) | \(c.characters.deletions) | \(c.characters.insertions) |")
        out.append("")
        if let estimate = c.werInterval.value {
            out.append("Interval: \(estimate.method); \(estimate.resamples) resamples of \(estimate.units) \(report.config.bootstrap.unit.rawValue)s, seed \(estimate.seed)\(strataWording(estimate.stratified, report.config.bootstrap.unit))"
                       + (estimate.degenerateResamples > 0 ? ", \(estimate.degenerateResamples) resamples with no reference words left out" : "") + ".")
            out.append("")
        }

        out.append("### By utterance language")
        out.append("")
        if c.byLanguageClass.isEmpty {
            out.append("Unavailable: no utterance-level results.")
        } else {
            out.append(contentsOf: strataTable(c.byLanguageClass))
        }
        out.append("")

        out.append("### By word language")
        out.append("")
        switch c.languageBreakdown {
        case let .unavailable(reason):
            out.append("Unavailable: \(reason).")
        case let .available(b):
            out.append("Covers \(c.languageItems.count) of \(c.itemsScored) scored items: \(cell(c.languageItems.joined(separator: ", "))).")
            out.append("")
            out.append("Rates are (substitutions + deletions) / reference words of that language. Insertions have no reference word and are left out of them.")
            out.append("")
            out.append("| Words | Reference words | Hits | Sub | Del | (S+D)/N |")
            out.append("| --- | ---: | ---: | ---: | ---: | ---: |")
            for language in b.byLanguage.keys.sorted() {
                let l = b.byLanguage[language]!
                out.append("| \(cell(language)) | \(l.referenceWords) | \(l.hits) | \(l.substitutions) | \(l.deletions) | \(rate(l.rate)) |")
            }
            for (name, part) in [("at a code switch", b.codeSwitchPoints), ("not at a switch", b.nonSwitchPoints)] {
                if let l = part.value {
                    out.append("| \(name) | \(l.referenceWords) | \(l.hits) | \(l.substitutions) | \(l.deletions) | \(rate(l.rate)) |")
                } else {
                    out.append("| \(name) | unavailable: \(cell(part.unavailableReason ?? "")) | | | | |")
                }
            }
            out.append("")
            out.append("Insertions not attributed to a language: \(b.insertionsUnattributed). Reference words with no word-level language: \(b.unattributedReferenceWords).")
        }
        out.append("")

        out.append("### By speaker overlap")
        out.append("")
        switch c.byOverlap {
        case let .unavailable(reason): out.append("Unavailable: \(reason).")
        case let .available(strata):
            out.append("Covers \(c.overlapItems.count) of \(c.itemsScored) scored items: \(cell(c.overlapItems.joined(separator: ", "))). An utterance overlaps when the reference marks it so, or, with no mark, when its time intersects a turn of another speaker. \"unknown\" holds the utterances that have neither a mark nor a timed speaker turn.")
            out.append("")
            out.append(contentsOf: strataTable(strata))
        }
        out.append("")

        out.append("## Deletions and missing speech")
        out.append("")
        switch c.deletionBursts {
        case let .unavailable(reason):
            out.append("Deletion bursts: unavailable: \(reason).")
        case let .available(bursts):
            let deleted = bursts.reduce(0) { $0 + $1.length }
            out.append("Deletion bursts (at least \(report.config.deletionBurstMinWords) consecutive reference words deleted): \(bursts.count), \(deleted) words, \(c.words.deletions) deletions in all.")
            if !bursts.isEmpty {
                out.append("")
                out.append("| Item | First utterance | Words | Time | Deleted |")
                out.append("| --- | --- | ---: | --- | --- |")
                for item in report.items {
                    for burst in item.score.value?.deletionBursts.value ?? [] {
                        let time = burst.startMs.map { s in "\(seconds(s))–\(burst.endMs.map { seconds($0) } ?? "?")" } ?? "untimed"
                        out.append("| \(cell(item.itemId)) | \(cell(burst.firstUtteranceId)) | \(burst.length) | \(time) | \(cell(excerpt(burst.words))) |")
                    }
                }
            }
        }
        out.append("")
        switch c.missingSpeech {
        case let .unavailable(reason):
            out.append("Missing speech: unavailable: \(reason).")
        case let .available(m):
            out.append("Missing speech (reference regions of at least \(seconds(report.config.missingSpeech.minRegionMs)) with less than \(percent(report.config.missingSpeech.coverageThreshold)) covered by hypothesis words, padded \(report.config.missingSpeech.wordPaddingMs) ms): \(m.missingRegions) of \(m.checkedRegions) regions, \(seconds(m.missingSpeechMs)) of \(seconds(m.checkedSpeechMs)) checked speech (\(rate(m.missingShare))), in \(m.itemsChecked) item(s). Uncovered speech in all checked regions: \(seconds(m.uncoveredSpeechMs)).")
            let regions = report.items.flatMap { item in
                (item.score.value?.missingSpeech.value?.missingRegions ?? []).map { (item.itemId, $0) }
            }
            if !regions.isEmpty {
                out.append("")
                out.append("| Item | Region | Covered | Utterances |")
                out.append("| --- | --- | ---: | --- |")
                for (id, r) in regions {
                    out.append("| \(cell(id)) | \(seconds(r.startMs))–\(seconds(r.endMs)) | \(percent(r.coverage)) | \(cell(r.utteranceIds.joined(separator: ", "))) |")
                }
            }
        }
        out.append("")

        out.append("## Performance")
        out.append("")
        out.append("Four different figures. A smaller process footprint is not a smaller model: the model's Neural Engine memory is not in the footprint.")
        out.append("")
        out.append("| Item | Whole-file RTF (offline) | Live commit latency | Process peak footprint | Model residency |")
        out.append("| --- | --- | --- | --- | --- |")
        out.append("| **Corpus** | \(number(c.wholeFileRTF, "%.3f")) | | | |")
        for item in report.items {
            let p = item.performance
            // One reason for all four figures is printed once.
            let reasons = [p.wholeFileRTF.unavailableReason, p.liveCommitLatency.unavailableReason,
                           p.processPeakFootprintMB.unavailableReason, p.modelResidencyMB.unavailableReason]
            if let first = reasons[0], reasons.allSatisfy({ $0 == first }) {
                out.append("| \(cell(item.itemId)) | not measured: \(cell(first)) | — | — | — |")
                continue
            }
            let latency: String
            switch p.liveCommitLatency {
            case let .available(l): latency = String(format: "median %.0f ms, p95 %.0f ms, max %d ms (%@ clock, %d words)", l.medianMs, l.p95Ms, l.maxMs, l.clock, l.words)
            case let .unavailable(reason): latency = "unavailable: \(cell(reason))"
            }
            out.append("| \(cell(item.itemId)) | \(number(p.wholeFileRTF, "%.3f")) | \(latency) | \(number(p.processPeakFootprintMB, "%.0f MB")) | \(number(p.modelResidencyMB, "%.0f MB")) |")
        }
        out.append("")

        out.append("## Items")
        out.append("")
        out.append("| Item | Category | WER | CER | N | Sub | Del | Ins |")
        out.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for item in report.items {
            switch item.score {
            case let .unavailable(reason):
                out.append("| \(cell(item.itemId)) | \(cell(item.category ?? "")) | unavailable: \(cell(reason)) | | | | | |")
            case let .available(s):
                out.append("| \(cell(item.itemId)) | \(cell(item.category ?? "")) | \(rate(s.wer)) | \(rate(s.cer)) | \(s.words.referenceLength) | \(s.words.substitutions) | \(s.words.deletions) | \(s.words.insertions) |")
            }
        }
        out.append("")

        out.append("## Utterances")
        out.append("")
        out.append("| Item | Utterance | Language | Speaker | Overlap | Time | WER | CER | N | Sub | Del | Ins |")
        out.append("| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for item in report.items {
            guard let s = item.score.value else { continue }
            guard let utterances = s.utterances.value else {
                out.append("| \(cell(item.itemId)) | unavailable: \(cell(s.utterances.unavailableReason ?? "")) | | | | | | | | | | |")
                continue
            }
            for u in utterances {
                let time = u.startMs.map { "\(seconds($0))–\(seconds(u.endMs ?? $0))" } ?? ""
                let overlap = u.overlap.map { $0 ? "yes" : "no" } ?? ""
                out.append("| \(cell(item.itemId)) | \(cell(u.id)) | \(u.languageClass.rawValue) | \(cell(u.speaker ?? "")) | \(overlap) | \(time) | \(rate(u.wer)) | \(rate(u.cer)) | \(u.words.referenceLength) | \(u.words.substitutions) | \(u.words.deletions) | \(u.words.insertions) |")
            }
        }
        out.append("")
        out.append("The raw reference and hypothesis of each item are in the JSON report, unchanged.")
        return out.joined(separator: "\n") + "\n"
    }

    public static func render(_ report: ComparisonReport) -> String {
        var out: [String] = []
        out.append("# ASR comparison: \(cell(report.baseline.label)) → \(cell(report.candidate.label))")
        out.append("")
        out.append("| | |")
        out.append("| --- | --- |")
        out.append("| Corpus | `\(cell(report.corpusId))` |")
        out.append("| Configuration | `\(cell(report.config.id))`, fingerprint `\(report.configFingerprint.prefix(16))` |")
        out.append("| Scoring policy | `\(cell(report.config.scoring.id))` v\(report.config.scoring.version) |")
        out.append(contentsOf: provenanceRows(report.baseline, prefix: "Baseline "))
        out.append(contentsOf: provenanceRows(report.candidate, prefix: "Candidate "))
        out.append("")
        if !report.warnings.isEmpty {
            out.append("## Warnings")
            out.append("")
            for warning in report.warnings { out.append("- \(warning)") }
            out.append("")
        }
        out.append("Difference = candidate − baseline. Negative means fewer errors in the candidate. "
                   + "\"Candidate lower\" is the share of resamples in which the candidate's rate was lower: "
                   + "a description of the resamples, not a p-value.")
        out.append("")
        out.append("| Metric | Baseline | Candidate | Difference | \(percent(report.config.bootstrap.confidenceLevel)) interval of difference | Candidate lower | Tied | Units |")
        out.append("| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |")
        out.append(comparisonRow("WER", report.wer))
        out.append(comparisonRow("CER", report.cer))
        for stratum in report.werByLanguageClass.keys.sorted() {
            out.append(comparisonRow("WER, \(stratum)", report.werByLanguageClass[stratum]!))
        }
        out.append("")
        if let w = report.wer.value {
            out.append("Interval: \(w.method); \(w.resamples) paired resamples, seed \(w.seed)\(strataWording(w.stratified, report.config.bootstrap.unit)).")
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Pieces

    static func strataWording(_ stratified: Bool, _ unit: BootstrapSettings.Unit) -> String {
        guard stratified else { return "" }
        return unit == .utterance ? ", stratified by utterance language class"
            : ", stratified by manifest category"
    }

    static func comparisonRow(_ name: String, _ comparison: Measured<PairedComparison>) -> String {
        switch comparison {
        case let .unavailable(reason):
            return "| \(name) | unavailable: \(cell(reason)) | | | | | | |"
        case let .available(p):
            return "| \(name) | \(rate(p.baseline)) | \(rate(p.candidate)) | \(signedPoints(p.difference)) | \(signedInterval(p.differenceInterval)) | \(rate(p.shareCandidateLower)) | \(rate(p.shareTied)) | \(p.units) |"
        }
    }

    static func provenanceRows(_ p: RunProvenance, prefix: String) -> [String] {
        func show(_ m: Measured<String>) -> String {
            switch m {
            case let .available(v): return "`\(cell(v))`"
            case let .unavailable(reason): return "unavailable (\(cell(reason)))"
            }
        }
        var rows = [
            "| \(prefix)System | \(cell(p.label)) |",
            "| \(prefix)Model | \(show(p.modelId)) |",
            "| \(prefix)Model revision | \(show(p.modelRevision)) |",
            "| \(prefix)Build | \(show(p.toolVersion)) |",
        ]
        switch p.hardware {
        case let .available(h): rows.append("| \(prefix)Hardware | \(cell(h.machine)), \(h.memoryGB) GB |")
        case let .unavailable(reason): rows.append("| \(prefix)Hardware | unavailable (\(cell(reason))) |")
        }
        switch p.inference {
        case let .available(i):
            var parts = ["mode \(i.mode)", "language \(i.language)"]
            if let prompt = i.prompt { parts.append("prompt \"\(prompt)\"") }
            parts += i.settings.keys.sorted().map { "\($0) \(i.settings[$0]!)" }
            rows.append("| \(prefix)Inference | \(cell(parts.joined(separator: ", "))) |")
        case let .unavailable(reason):
            rows.append("| \(prefix)Inference | unavailable (\(cell(reason))) |")
        }
        return rows
    }

    static func strataTable(_ strata: [StratumScore]) -> [String] {
        var rows = ["| Stratum | Utterances | WER | CER | N | Sub | Del | Ins |",
                    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
        for s in strata {
            rows.append("| \(cell(s.stratum)) | \(s.utterances) | \(rate(s.wer)) | \(rate(s.cer)) | \(s.words.referenceLength) | \(s.words.substitutions) | \(s.words.deletions) | \(s.words.insertions) |")
        }
        return rows
    }

    static func describe(_ p: ScoringPolicy) -> String {
        var parts = ["Unicode \(p.unicodeForm.rawValue.uppercased())"]
        parts.append(p.caseFolding ? "case folded" : "case kept")
        parts.append(p.stripDiacritics ? "diacritics removed" : "diacritics kept")
        parts.append("punctuation \(p.punctuation == .remove ? "removed" : "kept as tokens")")
        parts.append(p.hyphens == .split ? "hyphens split words" : "intra-word hyphens kept")
        switch p.apostrophes {
        case .keepIntraWord: parts.append("intra-word apostrophes kept")
        case .split: parts.append("apostrophes split words")
        case .delete: parts.append("apostrophes deleted")
        }
        parts.append(p.contractions == .expand ? "contractions expanded (table v\(p.contractionTableVersion))" : "contractions as written")
        return parts.joined(separator: ", ")
    }

    static func rate(_ m: MetricValue) -> String {
        switch m {
        case let .available(v): return String(format: "%.2f%%", v * 100)
        case let .unavailable(reason): return "unavailable: \(cell(reason))"
        }
    }

    static func number(_ m: MetricValue, _ format: String) -> String {
        switch m {
        case let .available(v): return String(format: format, v)
        case let .unavailable(reason): return "unavailable: \(cell(reason))"
        }
    }

    static func signedPoints(_ m: MetricValue) -> String {
        switch m {
        case let .available(v): return String(format: "%+.2f pt", v * 100)
        case let .unavailable(reason): return "unavailable: \(cell(reason))"
        }
    }

    static func interval(_ m: Measured<BootstrapEstimate>) -> String {
        switch m {
        case let .unavailable(reason): return "unavailable: \(cell(reason))"
        case let .available(e):
            switch e.interval {
            case let .available(ci): return String(format: "%.2f%% to %.2f%%", ci.lower * 100, ci.upper * 100)
            case let .unavailable(reason): return "unavailable: \(cell(reason))"
            }
        }
    }

    static func signedInterval(_ m: Measured<ConfidenceInterval>) -> String {
        switch m {
        case let .available(ci): return String(format: "%+.2f to %+.2f pt", ci.lower * 100, ci.upper * 100)
        case let .unavailable(reason): return "unavailable: \(cell(reason))"
        }
    }

    static func percent(_ v: Double) -> String {
        let p = v * 100
        return p == p.rounded() ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p)
    }

    /// Milliseconds as seconds with two decimals: a region of 1.4 s must not print as "0:01".
    static func seconds(_ ms: Int) -> String {
        String(format: "%.2f s", Double(ms) / 1000)
    }

    static func excerpt(_ words: [String]) -> String {
        words.count <= 12 ? words.joined(separator: " ")
            : words.prefix(12).joined(separator: " ") + " … (+\(words.count - 12))"
    }

    /// Text safe inside a table cell.
    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
