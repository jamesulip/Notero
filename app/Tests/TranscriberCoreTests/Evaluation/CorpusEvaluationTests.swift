import XCTest
@testable import TranscriberCore

/// The corpus layer: manifests, pooling, explicit absence, comparison, and
/// the property the framework exists for -- the same inputs give the same bytes.
final class CorpusEvaluationTests: XCTestCase {

    private let config = EvaluationConfig.default
    private let system = RunProvenance(label: "test system", modelId: .available("model-a"))

    private func reference(_ id: String, _ lines: [String], language: String? = nil) -> EvaluationReference {
        EvaluationReference(itemId: id, utterances: lines.enumerated().map {
            ReferenceUtterance(id: "u\($0.offset + 1)", text: $0.element, language: language)
        })
    }

    private func input(_ id: String, ref: EvaluationReference?, hyp: String?, category: String? = nil,
                       performance: PerformanceSummary = .notMeasured("not measured in this test")) -> CorpusItemInput {
        CorpusItemInput(item: CorpusManifest.Item(id: id, ref: ref == nil ? nil : "\(id).json", category: category),
                        reference: ref.map { .success($0) } ?? .failure(EvaluationInputMissing("no reference file")),
                        hypothesis: hyp.map { .success(EvaluationHypothesis(text: $0)) }
                            ?? .failure(EvaluationInputMissing("no hypothesis file")),
                        performance: performance)
    }

    /// A NaN or infinity formatted by `String(format:)`, as a whole word
    /// ("unannotated" contains "nan" and is fine).
    private func containsNaN(_ text: String) -> Bool {
        text.range(of: #"(?i)(?<![a-z])(nan|inf)(?![a-z])"#, options: .regularExpression) != nil
    }

    private var corpus: [CorpusItemInput] {
        [input("a", ref: reference("a", ["kumusta ka na", "ayos lang ako"], language: "tl"),
               hyp: "kumusta ka ayos lang ako"),
         input("b", ref: reference("b", ["let us start the meeting", "okay sige tara na"]),
               hyp: "let's start the meeting okay sige tara")]
    }

    // MARK: Manifest

    func testTheLegacyManifestGetsAnIdFromItsBytes() throws {
        let data = Data(#"[{"id":"clip","audio":"a.wav","ref":"r.txt","category":"mixed"}]"#.utf8)
        let first = try CorpusManifest.parse(data)
        let second = try CorpusManifest.parse(data)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.corpusId.hasPrefix("manifest-sha256:"))
        XCTAssertEqual(first.items, [CorpusManifest.Item(id: "clip", audio: "a.wav", ref: "r.txt", category: "mixed")])
        let other = try CorpusManifest.parse(Data(#"[{"id":"clip2","ref":"r.txt"}]"#.utf8))
        XCTAssertNotEqual(first.corpusId, other.corpusId)
        XCTAssertEqual(try CorpusManifest.parse(data, corpusId: "named").corpusId, "named")
    }

    func testTheRepositoryManifestStillParses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eval/manifest.json")
        let manifest = try CorpusManifest.parse(Data(contentsOf: url))
        XCTAssertEqual(manifest.items.map(\.id), ["synthetic-taglish", "meeting01"])
    }

    func testAVersionedManifestIsReadAndAnUnknownVersionIsRejected() throws {
        let v1 = Data(#"{"schemaVersion":1,"corpusId":"c1","items":[{"id":"x","ref":"x.txt"}]}"#.utf8)
        XCTAssertEqual(try CorpusManifest.parse(v1).corpusId, "c1")
        let v9 = Data(#"{"schemaVersion":9,"corpusId":"c1","items":[]}"#.utf8)
        XCTAssertThrowsError(try CorpusManifest.parse(v9)) {
            XCTAssertEqual($0 as? EvaluationError,
                           .unsupportedSchema(kind: "corpus manifest", found: 9, supported: 1))
        }
    }

    func testADuplicateItemIdIsRejected() {
        let data = Data(#"[{"id":"x","ref":"a.txt"},{"id":"x","ref":"b.txt"}]"#.utf8)
        XCTAssertThrowsError(try CorpusManifest.parse(data))
    }

    func testTheCategoryOfAPlainTextReferenceBecomesItsLinesLanguage() {
        let item = CorpusManifest.Item(id: "x", category: "tagalog")
        let ref = CorpusManifest.plainTextReference("isa\n\ndalawa\n", item: item)
        XCTAssertEqual(ref.utterances.map(\.language), ["tl", "tl"])
        let plain = CorpusManifest.plainTextReference("isa\n", item: CorpusManifest.Item(id: "x"))
        XCTAssertEqual(plain.utterances.map(\.language), [nil])
    }

    func testAnUnknownConfigVersionIsRejected() throws {
        var config = EvaluationConfig.default
        config.schemaVersion = 2
        let data = try CanonicalJSON.encode(config)
        XCTAssertThrowsError(try EvaluationConfig.load(from: data)) {
            XCTAssertEqual($0 as? EvaluationError,
                           .unsupportedSchema(kind: "evaluation config", found: 2, supported: 1))
        }
        XCTAssertEqual(try EvaluationConfig.load(from: CanonicalJSON.encode(EvaluationConfig.default)), .default)
    }

    func testTheCommittedConfigIsTheDefault() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eval/evaluation-config.v1.json")
        XCTAssertEqual(try EvaluationConfig.load(from: Data(contentsOf: url)), .default,
                       "regenerate it with `transcribe --print-eval-config`, and say why in the changelog")
    }

    func testTheFingerprintChangesWithEverySettingThatDecidesAScore() {
        var changed = EvaluationConfig.default
        changed.scoring.hyphens = .keepIntraWord
        XCTAssertNotEqual(changed.fingerprint, EvaluationConfig.default.fingerprint)
        XCTAssertNotEqual(changed.scoring.fingerprint, EvaluationConfig.default.scoring.fingerprint)
        var seeded = EvaluationConfig.default
        seeded.bootstrap.seed = 1
        XCTAssertNotEqual(seeded.fingerprint, EvaluationConfig.default.fingerprint)
        XCTAssertEqual(seeded.scoring.fingerprint, EvaluationConfig.default.scoring.fingerprint)
    }

    // MARK: Determinism and raw text

    func testTheSameInputsGiveTheSameBytes() throws {
        let one = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        let two = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        XCTAssertEqual(try CanonicalJSON.encodePretty(one), try CanonicalJSON.encodePretty(two))
        XCTAssertEqual(EvaluationMarkdown.render(one), EvaluationMarkdown.render(two))
        let comparison = try CorpusEvaluation.compare(baseline: one, candidate: two)
        XCTAssertEqual(try CanonicalJSON.encode(comparison),
                       try CanonicalJSON.encode(CorpusEvaluation.compare(baseline: one, candidate: two)))
    }

    func testTheReportRoundTripsThroughJSON() throws {
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        let decoded = try JSONDecoder().decode(EvaluationReport.self, from: CanonicalJSON.encode(report))
        XCTAssertEqual(decoded, report)
    }

    func testRawTranscriptsReachTheReportUnchanged() throws {
        // NFD, odd spacing, punctuation, curly apostrophe: none of it may be
        // normalized in the raw fields, only in the copies that are scored.
        let rawRef = "  Mañana  ’yung\u{0301} REVIEW, okay?\t"
        let rawHyp = "man\u{0303}ana yung   review…\n"
        let ref = EvaluationReference(itemId: "x", utterances: [ReferenceUtterance(id: "u", text: rawRef)])
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: [input("x", ref: ref, hyp: rawHyp)],
                                               system: system, config: config)
        let score = try XCTUnwrap(report.items.first?.score.value)
        XCTAssertEqual(Array(score.rawReference.unicodeScalars), Array(rawRef.unicodeScalars))
        XCTAssertEqual(Array(score.rawHypothesis.unicodeScalars), Array(rawHyp.unicodeScalars))
        let utterance = try XCTUnwrap(score.utterances.value?.first)
        XCTAssertEqual(Array(utterance.rawReference.unicodeScalars), Array(rawRef.unicodeScalars))
        // And through JSON, byte for byte.
        let decoded = try JSONDecoder().decode(EvaluationReport.self, from: CanonicalJSON.encode(report))
        XCTAssertEqual(Array(try XCTUnwrap(decoded.items.first?.score.value).rawHypothesis.unicodeScalars),
                       Array(rawHyp.unicodeScalars))
    }

    // MARK: Explicit absence

    func testAnItemWithoutAReferenceIsUnavailableAndLeftOutOfTheCorpus() throws {
        let inputs = corpus + [input("c", ref: nil, hyp: "something was said")]
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: inputs, system: system, config: config)
        XCTAssertEqual(report.corpus.itemsScored, 2)
        XCTAssertEqual(report.corpus.itemsInManifest, 3)
        XCTAssertEqual(report.items[2].score.unavailableReason, "no reference: no reference file")
        let without = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        XCTAssertEqual(report.corpus.words, without.corpus.words)
        XCTAssertTrue(report.warnings.contains { $0.contains("could not be scored") && $0.contains("c") })
    }

    func testNoScorableItemGivesNoNumberAtAll() {
        let report = CorpusEvaluation.evaluate(
            corpusId: "c", inputs: [input("a", ref: nil, hyp: "x"), input("b", ref: reference("b", ["x"]), hyp: nil)],
            system: system, config: config)
        XCTAssertEqual(report.corpus.wer, .unavailable(reason: "no item could be scored"))
        XCTAssertEqual(report.corpus.cer, .unavailable(reason: "no item could be scored"))
        XCTAssertNil(report.corpus.werInterval.value)
        XCTAssertNil(report.corpus.languageBreakdown.value)
        XCTAssertNil(report.corpus.missingSpeech.value)
        XCTAssertEqual(report.items[1].score.unavailableReason, "no hypothesis: no hypothesis file")
        let markdown = EvaluationMarkdown.render(report)
        XCTAssertTrue(markdown.contains("| WER | unavailable: no item could be scored"))
        XCTAssertFalse(containsNaN(markdown))
    }

    func testAnEmptyReferenceHasNoErrorRate() throws {
        let report = CorpusEvaluation.evaluate(
            corpusId: "c", inputs: [input("a", ref: reference("a", []), hyp: "may sinabi")],
            system: system, config: config)
        XCTAssertNil(report.corpus.wer.value)
        XCTAssertEqual(report.corpus.words.insertions, 2)
    }

    func testAnItemWithoutCERMakesTheCorpusCERUnavailable() throws {
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        var items = report.items
        var score = try XCTUnwrap(items[0].score.value)
        score.cer = .unavailable(reason: "too long")
        score.characters = .zero
        items[0].score = .available(score)
        var warnings: [String] = []
        let summary = CorpusEvaluation.summarize(items: items, config: config, warnings: &warnings)
        XCTAssertEqual(summary.cer, .unavailable(reason: "no CER for a"))
        XCTAssertNotNil(summary.wer.value)
    }

    func testMissingSpeechNeedsTimestampsOnBothSides() {
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        XCTAssertNil(report.corpus.missingSpeech.value, "plain references and plain hypotheses carry no times")
    }

    // MARK: Annotated subsets

    func testLanguageAndOverlapPoolTheAnnotatedItemsAndSaySo() throws {
        let timed = EvaluationReference(itemId: "t", utterances: [
            ReferenceUtterance(id: "1", text: "sige na", startMs: 0, endMs: 1000, speaker: "A", language: "tl"),
            ReferenceUtterance(id: "2", text: "okay go", startMs: 500, endMs: 1500, speaker: "B", language: "en"),
        ])
        let plain = reference("p", ["walang anotasyon dito"])
        let report = CorpusEvaluation.evaluate(
            corpusId: "c", inputs: [input("t", ref: timed, hyp: "sige na okay"), input("p", ref: plain, hyp: "walang anotasyon")],
            system: system, config: config)
        XCTAssertEqual(report.corpus.languageItems, ["t"])
        XCTAssertEqual(report.corpus.overlapItems, ["t"])
        let breakdown = try XCTUnwrap(report.corpus.languageBreakdown.value)
        XCTAssertEqual(breakdown.byLanguage["tl"]?.referenceWords, 2)
        XCTAssertEqual(breakdown.byLanguage["en"]?.deletions, 1)
        XCTAssertEqual(try XCTUnwrap(report.corpus.byOverlap.value).first { $0.stratum == "overlap" }?.utterances, 2)
        XCTAssertTrue(report.warnings.contains { $0.contains("word-language breakdown covers 1 of 2") })
        XCTAssertTrue(report.warnings.contains { $0.contains("overlap breakdown covers 1 of 2") })
    }

    // MARK: Performance

    func testWholeFileRTFPoolsTimeOverAudioOnlyWhenEveryItemMeasuredIt() {
        func perf(_ decode: Int?, _ audio: Int?) -> PerformanceSummary {
            PerformanceSummary(wholeFileRTF: .unavailable(reason: "-"), liveCommitLatency: .unavailable(reason: "-"),
                               processPeakFootprintMB: .unavailable(reason: "-"), modelResidencyMB: .unavailable(reason: "-"),
                               offlineDecodeMs: decode, audioMs: audio)
        }
        let a = reference("a", ["isa"]), b = reference("b", ["dalawa"])
        let both = CorpusEvaluation.evaluate(
            corpusId: "c", inputs: [input("a", ref: a, hyp: "isa", performance: perf(100, 1000)),
                                    input("b", ref: b, hyp: "dalawa", performance: perf(900, 3000))],
            system: system, config: config)
        XCTAssertEqual(both.corpus.wholeFileRTF, .available(0.25), "(100 + 900) / (1000 + 3000), not the mean of 0.1 and 0.3")
        let one = CorpusEvaluation.evaluate(
            corpusId: "c", inputs: [input("a", ref: a, hyp: "isa", performance: perf(100, 1000)),
                                    input("b", ref: b, hyp: "dalawa", performance: perf(nil, nil))],
            system: system, config: config)
        XCTAssertNil(one.corpus.wholeFileRTF.value)
    }

    // MARK: Comparison

    func testTwoSystemsOnTheSameCorpusAreCompared() throws {
        let base = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        let perfect = corpus.map { item -> CorpusItemInput in
            var copy = item
            copy.hypothesis = .success(EvaluationHypothesis(text: (try? item.reference.get())?.rawText ?? ""))
            return copy
        }
        let cand = CorpusEvaluation.evaluate(corpusId: "c", inputs: perfect,
                                             system: RunProvenance(label: "perfect"), config: config)
        let comparison = try CorpusEvaluation.compare(baseline: base, candidate: cand)
        let wer = try XCTUnwrap(comparison.wer.value)
        XCTAssertEqual(wer.candidate, .available(0))
        XCTAssertLessThan(try XCTUnwrap(wer.difference.value), 0)
        XCTAssertEqual(comparison.baselineWER, base.corpus.wer)
        XCTAssertFalse(containsNaN(EvaluationMarkdown.render(comparison)))
    }

    func testComparisonsAcrossCorporaConfigsOrItemSetsAreRefused() {
        let base = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: config)
        let otherCorpus = CorpusEvaluation.evaluate(corpusId: "d", inputs: corpus, system: system, config: config)
        XCTAssertThrowsError(try CorpusEvaluation.compare(baseline: base, candidate: otherCorpus))
        var keep = config
        keep.scoring = .keepHyphens
        let otherConfig = CorpusEvaluation.evaluate(corpusId: "c", inputs: corpus, system: system, config: keep)
        XCTAssertThrowsError(try CorpusEvaluation.compare(baseline: base, candidate: otherConfig))
        var fewer = corpus
        fewer[1].hypothesis = .failure(EvaluationInputMissing("lost"))
        let otherItems = CorpusEvaluation.evaluate(corpusId: "c", inputs: fewer, system: system, config: config)
        XCTAssertThrowsError(try CorpusEvaluation.compare(baseline: base, candidate: otherItems))
        var edited = corpus
        edited[0].reference = .success(reference("a", ["kumusta ka na", "ayos lang ako talaga"], language: "tl"))
        let otherRefs = CorpusEvaluation.evaluate(corpusId: "c", inputs: edited, system: system, config: config)
        XCTAssertThrowsError(try CorpusEvaluation.compare(baseline: base, candidate: otherRefs))
    }

    // MARK: The committed fixture

    func testTheCommittedScoringFixtureIsValid() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eval/fixtures/scoring")
        let manifest = try CorpusManifest.parse(Data(contentsOf: root.appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.corpusId, "synthetic-scoring-fixture-v1")
        let standup = try EvaluationReference.load(json: Data(contentsOf: root.appendingPathComponent("refs/standup.json")))
        XCTAssertEqual(standup.itemId, "standup")
        let candidate = try String(contentsOf: root.appendingPathComponent("hyp-candidate/standup.txt"), encoding: .utf8)
        let score = Evaluator.score(reference: standup, hypothesis: EvaluationHypothesis(text: candidate), config: config)
        XCTAssertEqual(score.wer, .available(0), "the candidate fixture is the reference text, so it must score 0")
    }

    // MARK: Benchmark runs saved before the evaluation fields

    func testABenchmarkRunSavedBeforeTheEvaluationFieldsStillDecodes() throws {
        let old = BenchmarkRun(modelId: "m", tier: .balanced, label: "l", audioMs: 1000, processMs: 100, wer: 0.25)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "evaluation")
        object.removeValue(forKey: "evaluationConfigFingerprint")
        object.removeValue(forKey: "modelRevision")
        let decoded = try JSONDecoder().decode(BenchmarkRun.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.wer, 0.25)
        XCTAssertNil(decoded.evaluation)
    }

    func testABenchmarkRunKeepsItsEvaluation() throws {
        let score = Evaluator.score(reference: reference("x", ["isa dalawa"]),
                                    hypothesis: EvaluationHypothesis(text: "isa"), config: config)
        let run = BenchmarkRun(modelId: "m", label: "l", audioMs: 1000, processMs: 100,
                               evaluation: score, evaluationConfigFingerprint: config.fingerprint,
                               modelRevision: String(repeating: "a", count: 40))
        let decoded = try JSONDecoder().decode(BenchmarkRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded.evaluation, score)
        XCTAssertEqual(decoded.evaluation?.wer, .available(0.5))
    }

    // MARK: Findings of the independent review

    func testAnItemUnitIntervalUsesTheManifestCategoriesInBothReportAndComparison() throws {
        var itemConfig = config
        itemConfig.bootstrap.unit = .item
        let inputs = (1...6).map { n in
            input("i\(n)", ref: reference("i\(n)", ["isa dalawa tatlo apat lima anim"]),
                  hyp: String(repeating: "isa ", count: n), category: n <= 3 ? "tagalog" : "english")
        }
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: inputs, system: system, config: itemConfig)
        let estimate = try XCTUnwrap(report.corpus.werInterval.value)
        XCTAssertEqual(estimate.strata, ["tagalog": 3, "english": 3])
        let comparison = try CorpusEvaluation.compare(baseline: report, candidate: report)
        XCTAssertEqual(comparison.wer.value?.baselineInterval, estimate.interval,
                       "one system, one interval, whichever report prints it")
        XCTAssertTrue(EvaluationMarkdown.render(report).contains("stratified by manifest category"))
    }

    func testAPlainTextReferenceIsReportedAsTheFileWasWritten() throws {
        let file = "Unang linya\r\n\r\n  pangalawa  \r\n"
        let ref = CorpusManifest.plainTextReference(file, item: CorpusManifest.Item(id: "x"))
        let report = CorpusEvaluation.evaluate(corpusId: "c", inputs: [input("x", ref: ref, hyp: "unang linya pangalawa")],
                                               system: system, config: config)
        let score = try XCTUnwrap(report.items.first?.score.value)
        XCTAssertEqual(Array(score.rawReference.utf8), Array(file.utf8))
        XCTAssertEqual(score.wer, .available(0))
    }
}
