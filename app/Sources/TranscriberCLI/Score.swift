import Foundation
import TranscriberCore
import TranscriberEngine

// `transcribe --score`: the evaluation framework over saved hypotheses.
//
// No audio, no model, no network. It reads a manifest, the references it
// names and one hypothesis per item -- the `--json` report of an earlier
// `transcribe` run, or plain text from anywhere -- and writes a JSON and a
// Markdown report. With `--compare` it scores a second set of hypotheses over
// the same references and adds a paired bootstrap comparison.
//
//   transcribe --score eval/manifest.json --hypotheses runs/base [--label base]
//              [--compare runs/cand --compare-label cand]
//              [--eval-config config.json | --policy notero-standard]
//              [--corpus-id ID] [--model-revision REV] [--build SHA] --out-dir DIR

/// The configuration a run scores under: the file, if given, else the
/// default, with `--policy` replacing the scoring rules.
func loadEvaluationConfig(_ options: Options) -> EvaluationConfig {
    var config = EvaluationConfig.default
    if let url = options.evalConfig {
        do {
            config = try EvaluationConfig.load(from: Data(contentsOf: url))
        } catch {
            log("error: could not read the evaluation config \(url.path): \(briefly(error))")
            exit(2)
        }
    }
    if let id = options.policy {
        guard let policy = ScoringPolicy.preset(named: id) else {
            log("error: no scoring policy \(id); known: "
                + ScoringPolicy.presets.map(\.id).joined(separator: ", "))
            exit(2)
        }
        config.scoring = policy
    }
    return config
}

/// Why an input could not be used, in words that do not change with the
/// machine: no absolute path, no localized system message. A report must be
/// the same bytes from another clone, another user or another OS language.
func briefly(_ error: Error) -> String {
    switch error {
    case let error as EvaluationError:
        return error.description
    case let DecodingError.dataCorrupted(context):
        return "malformed JSON (\(context.debugDescription))"
    case let DecodingError.keyNotFound(key, _):
        return "malformed JSON (no key \"\(key.stringValue)\")"
    case let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context):
        return "malformed JSON (wrong type at \(context.codingPath.map(\.stringValue).joined(separator: ".")))"
    default:
        return "could not be read"
    }
}

/// A reference file: `.json` is an `EvaluationReference`, anything else is
/// plain text with one utterance per line. `name` is how a reason refers to
/// the file: its path as the manifest wrote it.
/// `checkItemId`: a manifest pairs ids, so a JSON reference for another item
/// is an error there; a single `--audio` run has no id to check against.
func loadReference(_ url: URL, name: String, item: CorpusManifest.Item,
                   checkItemId: Bool = true) -> Result<EvaluationReference, EvaluationInputMissing> {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .failure(EvaluationInputMissing("no reference file \(name)"))
    }
    do {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "json" {
            let reference = try EvaluationReference.load(json: data)
            guard !checkItemId || reference.itemId == item.id else {
                return .failure(EvaluationInputMissing(
                    "the reference \(name) is for item \(reference.itemId), not \(item.id)"))
            }
            return .success(reference)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(EvaluationInputMissing("the reference \(name) is not UTF-8"))
        }
        return .success(CorpusManifest.plainTextReference(text, item: item))
    } catch {
        return .failure(EvaluationInputMissing("the reference \(name): \(briefly(error))"))
    }
}

/// The four performance figures of one run, each only when the run measured it.
func performanceSummary(mode: String, decodeMs: Int, durationMs: Int,
                        commitLatency: CommitLatencySummary?, commitLatencyWall: CommitLatencySummary?,
                        memory: [MemorySnapshot]?) -> PerformanceSummary {
    let offline = mode == "offline"
    let rtf: MetricValue = offline
        ? .ratio(decodeMs, durationMs, unavailable: "the audio has no duration")
        : .unavailable(reason: "a \(mode) replay has no whole-file RTF; its replay RTF is a different number")

    let latency: Measured<LatencyFigures>
    // Under real-time pacing the wall clock includes what the machine costs,
    // which is what a person waits for; with every decode awaited only the
    // audio clock means anything.
    if let wall = commitLatencyWall, mode == "live-realtime" {
        latency = .available(LatencyFigures(clock: "wall", words: wall.words, medianMs: wall.medianMs,
                                            p95Ms: wall.p95Ms, maxMs: wall.maxMs))
    } else if let fed = commitLatency, mode.hasPrefix("live") {
        latency = .available(LatencyFigures(clock: "audio fed", words: fed.words, medianMs: fed.medianMs,
                                            p95Ms: fed.p95Ms, maxMs: fed.maxMs))
    } else if mode.hasPrefix("live") {
        latency = .unavailable(reason: "the live replay committed no words")
    } else {
        latency = .unavailable(reason: "an offline run has no commit latency")
    }

    let peak = memory?.map(\.lifetimePeakFootprintMB).max() ?? 0
    let footprint: MetricValue = peak > 0
        ? .available(Double(peak))
        : .unavailable(reason: "the run recorded no memory snapshots")
    let before = memory?.first { $0.stage == "beforeModelLoad" }?.neuralMB
    let after = memory?.first { $0.stage == "afterModelLoad" }?.neuralMB
    let residency: MetricValue
    if let before, let after, after > before {
        residency = .available(Double(after - before))
    } else {
        residency = .unavailable(reason: "the kernel reported no Neural Engine memory for the model load")
    }
    return PerformanceSummary(wholeFileRTF: rtf, liveCommitLatency: latency,
                              processPeakFootprintMB: footprint, modelResidencyMB: residency,
                              offlineDecodeMs: offline ? decodeMs : nil,
                              audioMs: offline ? durationMs : nil)
}

func performanceSummary(of report: RunReport) -> PerformanceSummary {
    performanceSummary(mode: report.mode, decodeMs: report.decodeMs, durationMs: report.durationMs,
                       commitLatency: report.commitLatency, commitLatencyWall: report.commitLatencyWall,
                       memory: report.memory)
}

func writeOrExit(_ data: Data, to url: URL) {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        log("wrote \(url.path)")
    } catch {
        log("error: could not write \(url.path): \(error.localizedDescription)")
        exit(1)
    }
}

func writeReport<T: Encodable>(_ value: T, markdown: String, json jsonURL: URL?, markdown mdURL: URL?) {
    if let jsonURL {
        do {
            var data = try CanonicalJSON.encodePretty(value)
            data.append(contentsOf: Array("\n".utf8))
            writeOrExit(data, to: jsonURL)
        } catch {
            log("error: could not encode the report: \(error)")
            exit(1)
        }
    }
    if let mdURL { writeOrExit(Data(markdown.utf8), to: mdURL) }
}

func describeScore(_ report: EvaluationReport) -> String {
    let c = report.corpus
    func pct(_ m: MetricValue) -> String { m.value.map { String(format: "%.2f%%", $0 * 100) } ?? "unavailable" }
    var line = "\(report.system.label): WER \(pct(c.wer))"
    if let ci = c.werInterval.value?.interval.value {
        line += String(format: " [%.2f%%, %.2f%%]", ci.lower * 100, ci.upper * 100)
    }
    line += " (S \(c.words.substitutions) D \(c.words.deletions) I \(c.words.insertions) N \(c.words.referenceLength)), "
        + "CER \(pct(c.cer)), \(c.itemsScored)/\(c.itemsInManifest) items"
    return line
}

/// Scores one directory of hypotheses over the manifest.
func scoreSystem(manifest: CorpusManifest, base: URL, hypotheses dir: URL, label: String?,
                 options: Options, config: EvaluationConfig) -> EvaluationReport {
    var runReports: [RunReport] = []
    let inputs: [CorpusItemInput] = manifest.items.map { item in
        let reference: Result<EvaluationReference, EvaluationInputMissing> = item.ref.map {
            loadReference(base.appendingPathComponent($0), name: $0, item: item)
        } ?? .failure(EvaluationInputMissing("the manifest names no reference for \(item.id)"))

        let jsonURL = dir.appendingPathComponent("\(item.id).json")
        let textURL = dir.appendingPathComponent("\(item.id).txt")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            do {
                let run = try JSONDecoder().decode(RunReport.self, from: Data(contentsOf: jsonURL))
                runReports.append(run)
                return CorpusItemInput(item: item, reference: reference,
                                       hypothesis: .success(EvaluationHypothesis(text: run.transcript, words: run.words)),
                                       performance: performanceSummary(of: run))
            } catch {
                return CorpusItemInput(item: item, reference: reference,
                                       hypothesis: .failure(EvaluationInputMissing(
                                           "\(jsonURL.lastPathComponent) is not a transcribe report: \(briefly(error))")))
            }
        }
        if let text = try? String(contentsOf: textURL, encoding: .utf8) {
            return CorpusItemInput(item: item, reference: reference,
                                   hypothesis: .success(EvaluationHypothesis(text: text)),
                                   performance: .notMeasured("a plain-text hypothesis carries no run measurements"))
        }
        return CorpusItemInput(item: item, reference: reference,
                               hypothesis: .failure(EvaluationInputMissing(
                                   "no \(item.id).json or \(item.id).txt in the hypothesis folder \(dir.lastPathComponent)")))
    }

    // What produced the hypotheses: the flags first, then what every report agrees on.
    // A field counts only when every item's hypothesis is a report that
    // records it, and all of them record the same value.
    let everyItemHasAReport = runReports.count == manifest.items.count
    func agreed(_ values: [String]) -> Measured<String> {
        guard !runReports.isEmpty else { return .unavailable(reason: "the hypotheses are plain text") }
        guard everyItemHasAReport else {
            return .unavailable(reason: "not every item's hypothesis is a transcribe report")
        }
        guard values.count == runReports.count else {
            return .unavailable(reason: "not recorded by every hypothesis report")
        }
        let distinct = Set(values)
        guard distinct.count == 1 else {
            return .unavailable(reason: "the hypothesis reports disagree: " + distinct.sorted().joined(separator: ", "))
        }
        return .available(distinct.first!)
    }
    func missingProvenanceReason(_ otherwise: String) -> String {
        if runReports.isEmpty { return "the hypotheses are plain text" }
        if !everyItemHasAReport { return "not every item's hypothesis is a transcribe report" }
        return otherwise
    }
    let fromReports = runReports.compactMap(\.provenance)
    let modelId: Measured<String> = options.modelId.map { .available($0) } ?? agreed(runReports.map(\.model))
    let revision: Measured<String> = options.modelRevision.map { .available($0) }
        ?? agreed(fromReports.compactMap(\.modelRevision.value))
    let hardware: Measured<HardwareInfo> = {
        let all = fromReports.compactMap(\.hardware.value)
        guard everyItemHasAReport, !all.isEmpty, all.count == runReports.count,
              all.allSatisfy({ $0 == all[0] }) else {
            return .unavailable(reason: missingProvenanceReason("not recorded the same way by every hypothesis report"))
        }
        return .available(all[0])
    }()
    let inference: Measured<InferenceSettings> = {
        let all = fromReports.compactMap(\.inference.value)
        guard everyItemHasAReport, !all.isEmpty, all.count == runReports.count,
              all.allSatisfy({ $0 == all[0] }) else {
            return .unavailable(reason: missingProvenanceReason("not the same for every hypothesis report"))
        }
        return .available(all[0])
    }()
    let build: Measured<String> = options.build.map { .available($0) }
        ?? agreed(fromReports.compactMap(\.toolVersion.value))
    let system = RunProvenance(label: label ?? dir.lastPathComponent, modelId: modelId, modelRevision: revision,
                               hardware: hardware, inference: inference, toolVersion: build)
    return CorpusEvaluation.evaluate(corpusId: manifest.corpusId, inputs: inputs, system: system, config: config)
}

func runScore(_ options: Options) -> Never {
    guard let manifestURL = options.score else { exit(2) }
    guard let hypotheses = options.hypotheses else {
        log("error: --score needs --hypotheses DIR (see --help)")
        exit(2)
    }
    let config = loadEvaluationConfig(options)
    let manifest: CorpusManifest
    do {
        manifest = try CorpusManifest.parse(Data(contentsOf: manifestURL), corpusId: options.corpusId)
    } catch {
        log("error: could not read the manifest \(manifestURL.path): \(error)")
        exit(2)
    }
    let base = manifestURL.deletingLastPathComponent()
    log("corpus \(manifest.corpusId): \(manifest.items.count) items; config \(config.id), "
        + "policy \(config.scoring.id) v\(config.scoring.version)")

    let baseline = scoreSystem(manifest: manifest, base: base, hypotheses: hypotheses, label: options.label,
                               options: options, config: config)
    for warning in baseline.warnings { log("  warning: \(warning)") }
    log(describeScore(baseline))
    let out = options.outDir

    guard let candidateDir = options.compare else {
        writeReport(baseline, markdown: EvaluationMarkdown.render(baseline),
                    json: out?.appendingPathComponent("report.json"),
                    markdown: out?.appendingPathComponent("report.md"))
        if out == nil { print(EvaluationMarkdown.render(baseline)) }
        exit(exitStatus(baseline))
    }

    let candidate = scoreSystem(manifest: manifest, base: base, hypotheses: candidateDir,
                                label: options.compareLabel, options: options, config: config)
    for warning in candidate.warnings { log("  warning: \(warning)") }
    log(describeScore(candidate))
    let comparison: ComparisonReport
    do {
        comparison = try CorpusEvaluation.compare(baseline: baseline, candidate: candidate)
    } catch {
        log("error: \(error)")
        exit(1)
    }
    if let p = comparison.wer.value, let d = p.difference.value {
        var line = String(format: "WER difference %+.2f pt", d * 100)
        if let ci = p.differenceInterval.value {
            line += String(format: " [%+.2f, %+.2f]", ci.lower * 100, ci.upper * 100)
        }
        log(line + ", candidate lower in " + (p.shareCandidateLower.value.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable")
            + " of resamples")
    } else {
        log("WER comparison unavailable: \(comparison.wer.unavailableReason ?? "")")
    }
    writeReport(baseline, markdown: EvaluationMarkdown.render(baseline),
                json: out?.appendingPathComponent("baseline.json"),
                markdown: out?.appendingPathComponent("baseline.md"))
    writeReport(candidate, markdown: EvaluationMarkdown.render(candidate),
                json: out?.appendingPathComponent("candidate.json"),
                markdown: out?.appendingPathComponent("candidate.md"))
    writeReport(comparison, markdown: EvaluationMarkdown.render(comparison),
                json: out?.appendingPathComponent("comparison.json"),
                markdown: out?.appendingPathComponent("comparison.md"))
    if out == nil { print(EvaluationMarkdown.render(comparison)) }
    exit(max(exitStatus(baseline), exitStatus(candidate)))
}

/// 3 when no item could be scored: the report is written and says why, but a
/// script must not read "nothing measured" as success.
func exitStatus(_ report: EvaluationReport) -> Int32 {
    if report.corpus.itemsScored == 0 {
        log("error: no item of \(report.system.label) could be scored")
        return 3
    }
    return 0
}
