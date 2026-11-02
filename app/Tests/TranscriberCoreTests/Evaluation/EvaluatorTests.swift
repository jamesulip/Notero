import XCTest
@testable import TranscriberCore

final class EvaluatorTests: XCTestCase {

    private let config = EvaluationConfig.default

    private func reference(_ utterances: [ReferenceUtterance]) -> EvaluationReference {
        EvaluationReference(itemId: "item", utterances: utterances)
    }

    private func score(_ ref: EvaluationReference, _ hyp: String, words: [Token]? = nil,
                       config: EvaluationConfig = .default) -> ItemScore {
        Evaluator.score(reference: ref, hypothesis: EvaluationHypothesis(text: hyp, words: words), config: config)
    }

    private func sum(_ scores: [UtteranceScore], _ key: KeyPath<UtteranceScore, ErrorCounts>) -> ErrorCounts {
        scores.reduce(ErrorCounts()) { $0 + $1[keyPath: key] }
    }

    // MARK: - Item scoring and projection

    func testItemWERIsTheWEROfTheJoinedText() throws {
        let ref = reference([
            ReferenceUtterance(id: "u1", text: "Sige, i-send mo na yung report."),
            ReferenceUtterance(id: "u2", text: "Okay na ba 'yung slides?"),
            ReferenceUtterance(id: "u3", text: "Bukas na lang tayo mag-meeting."),
        ])
        let hyp = "uh sige i send mo yung report po okay na ba yong slides bukas na tayo mag meeting ha"
        let item = score(ref, hyp)
        let joined = Alignment.counts(reference: TextNormalizer.words(ref.rawText, policy: .standard),
                                      hypothesis: TextNormalizer.words(hyp, policy: .standard))
        XCTAssertEqual(item.words, joined)
        XCTAssertEqual(item.wer, joined.rate)

        let utterances = try XCTUnwrap(item.utterances.value)
        XCTAssertEqual(sum(utterances, \.words), item.words, "per-utterance word counts sum to the item")
        XCTAssertEqual(sum(utterances, \.characters), item.characters)
        XCTAssertEqual(utterances.flatMap(\.assignedHypothesis), item.normalizedHypothesis,
                       "every hypothesis word is projected exactly once, in order")
        // The leading "uh" precedes every reference word: it goes to u1.
        XCTAssertEqual(utterances[0].assignedHypothesis.first, "uh")
        // "po" follows u1's last word: it stays with u1.
        XCTAssertEqual(utterances[0].assignedHypothesis.last, "po")
        XCTAssertEqual(utterances[2].assignedHypothesis.last, "ha")
        for u in utterances {
            XCTAssertEqual(u.characters, Alignment.counts(reference: Array(u.normalizedReference.joined(separator: " ")),
                                                          hypothesis: Array(u.assignedHypothesis.joined(separator: " "))))
        }
    }

    func testProjectionSumsOnDeterministicInputs() throws {
        var state: UInt64 = 7
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        let vocabulary = ["isa", "dalawa", "tatlo", "apat", "lima", "anim", "pito"]
        for _ in 0..<60 {
            let utterances = (0..<(1 + next(4))).map { k in
                ReferenceUtterance(id: "u\(k)", text: (0..<next(6)).map { _ in vocabulary[next(7)] }.joined(separator: " "))
            }
            let hyp = (0..<next(18)).map { _ in vocabulary[next(7)] }.joined(separator: " ")
            let item = score(reference(utterances), hyp)
            let scores = try XCTUnwrap(item.utterances.value)
            XCTAssertEqual(sum(scores, \.words), item.words)
            XCTAssertEqual(sum(scores, \.characters), item.characters)
            XCTAssertEqual(scores.flatMap(\.assignedHypothesis), item.normalizedHypothesis)
        }
    }

    // MARK: - Empty transcripts

    func testEmptyReferenceAndEmptyHypothesis() {
        let item = score(reference([]), "")
        XCTAssertEqual(item.words, .zero)
        XCTAssertFalse(item.wer.isAvailable, "WER over no words is undefined, not 0")
        XCTAssertFalse(item.cer.isAvailable)
        XCTAssertEqual(item.utterances, .available([]))
    }

    func testEmptyReferenceWithHypothesisWords() {
        let item = score(reference([]), "may sinabi pala")
        XCTAssertEqual(item.words, ErrorCounts(insertions: 3))
        XCTAssertEqual(item.characters, ErrorCounts(insertions: "may sinabi pala".count))
        XCTAssertFalse(item.wer.isAvailable)
        XCTAssertFalse(item.cer.isAvailable)
        XCTAssertEqual(item.utterances, .available([]))
        XCTAssertEqual(item.byLanguageClass, [])
    }

    func testWordsAgainstAnEmptyHypothesisAreAllDeleted() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "isa dalawa", startMs: 0, endMs: 1000),
                             ReferenceUtterance(id: "b", text: "tatlo apat", startMs: 1000, endMs: 2000)])
        let item = score(ref, "  ")
        XCTAssertEqual(item.words, ErrorCounts(deletions: 4))
        XCTAssertEqual(item.wer, .available(1.0))
        XCTAssertEqual(item.cer, .available(1.0))
        let bursts = try XCTUnwrap(item.deletionBursts.value)
        XCTAssertEqual(bursts, [DeletionBurst(firstUtteranceId: "a", lastUtteranceId: "b", referenceStartIndex: 0,
                                              length: 4, words: ["isa", "dalawa", "tatlo", "apat"],
                                              startMs: 0, endMs: 2000)])
    }

    func testPunctuationOnlyReferenceLines() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "..."),
                             ReferenceUtterance(id: "b", text: "  \t "),
                             ReferenceUtterance(id: "c", text: "Sige na."),
                             ReferenceUtterance(id: "d", text: "?!")])
        let item = score(ref, "sige na po")
        XCTAssertEqual(item.words, ErrorCounts(hits: 2, insertions: 1))
        let scores = try XCTUnwrap(item.utterances.value)
        XCTAssertEqual(scores.map(\.normalizedReference), [[], [], ["sige", "na"], []])
        XCTAssertFalse(scores[0].wer.isAvailable)
        XCTAssertEqual(scores[2].assignedHypothesis, ["sige", "na", "po"])
        XCTAssertEqual(sum(scores, \.words), item.words)
    }

    func testReferenceWithNoWordsGivesInsertionsToTheFirstUtterance() throws {
        let item = score(reference([ReferenceUtterance(id: "a", text: "..."),
                                    ReferenceUtterance(id: "b", text: "!")]), "uh oo")
        XCTAssertEqual(item.words, ErrorCounts(insertions: 2))
        XCTAssertFalse(item.wer.isAvailable)
        let scores = try XCTUnwrap(item.utterances.value)
        XCTAssertEqual(scores.map(\.assignedHypothesis), [["uh", "oo"], []])
    }

    // MARK: - Raw text and determinism

    func testRawTextIsKeptVerbatim() {
        let lines = ["  Cafe\u{301}\u{A0}na\t", "ni\u{F1}o\u{2019}y  "]
        let ref = reference(lines.enumerated().map { ReferenceUtterance(id: "l\($0.offset)", text: $0.element) })
        let hyp = " Cafe\u{301}  na\r\n "
        let item = score(ref, hyp)
        XCTAssertEqual(Array(item.rawReference.utf8), Array(lines.joined(separator: "\n").utf8))
        XCTAssertEqual(Array(item.rawHypothesis.utf8), Array(hyp.utf8))
        XCTAssertEqual(item.utterances.value?.map { Array($0.rawReference.utf8) }, lines.map { Array($0.utf8) })
    }

    func testScoringIsDeterministic() throws {
        let ref = reference([
            ReferenceUtterance(id: "a", text: "Sige i-send mo na", startMs: 0, endMs: 2000, speaker: "A",
                               languageSpans: [LanguageSpan(text: "Sige ", language: "tl"),
                                               LanguageSpan(text: "i-send", language: "en"),
                                               LanguageSpan(text: " mo na", language: "tl")]),
            ReferenceUtterance(id: "b", text: "Okay, thank you", startMs: 1500, endMs: 3000, speaker: "B",
                               language: "en"),
            ReferenceUtterance(id: "c", text: "Salamat po sa lahat", startMs: 5000, endMs: 8000, speaker: "A",
                               language: "tl"),
        ])
        let words = [Token(text: " sige", startMs: 100, endMs: 400), Token(text: " send", startMs: 500, endMs: 900)]
        let hyp = "sige send mo na okay thank you salamat sa lahat"
        let first = try CanonicalJSON.encode(score(ref, hyp, words: words))
        let second = try CanonicalJSON.encode(score(ref, hyp, words: words))
        XCTAssertEqual(first, second)
        let decoded = try JSONDecoder().decode(ItemScore.self, from: first)
        XCTAssertEqual(decoded, score(ref, hyp, words: words), "the report round-trips")
    }

    // MARK: - Language

    func testLanguageClassesFromTagsAndSpans() {
        let ref = reference([
            ReferenceUtterance(id: "tl", text: "kumusta", language: "tl"),
            ReferenceUtterance(id: "fil", text: "salamat", language: "fil"),
            ReferenceUtterance(id: "en", text: "thanks", language: "en"),
            ReferenceUtterance(id: "mixed", text: "sige okay", language: "mixed"),
            ReferenceUtterance(id: "es", text: "gracias", language: "es"),
            ReferenceUtterance(id: "none", text: "oo"),
            ReferenceUtterance(id: "spans", text: "sige okay",
                               languageSpans: [LanguageSpan(text: "sige ", language: "tl"),
                                               LanguageSpan(text: "okay", language: "en")]),
            ReferenceUtterance(id: "spans-en", text: "okay, ",
                               languageSpans: [LanguageSpan(text: "okay", language: "en"),
                                               LanguageSpan(text: ", ", language: "tl")]),
        ])
        let item = score(ref, "kumusta salamat thanks sige okay gracias oo sige okay okay")
        XCTAssertEqual(item.utterances.value?.map(\.languageClass),
                       [.tagalog, .tagalog, .english, .codeSwitched, .other, .unannotated, .codeSwitched, .english])
        XCTAssertEqual(item.byLanguageClass.map(\.stratum),
                       ["tagalog", "english", "code-switched", "other", "unannotated"])
        XCTAssertEqual(item.byLanguageClass.map(\.utterances), [2, 2, 2, 1, 1])
    }

    func testLanguageBreakdownAndCodeSwitchPoints() throws {
        let ref = reference([
            // Words sige, i, send, mo, na with languages tl, en, en, tl, tl.
            ReferenceUtterance(id: "a", text: "Sige i-send mo na",
                               languageSpans: [LanguageSpan(text: "Sige ", language: "tl"),
                                               LanguageSpan(text: "i-send", language: "en"),
                                               LanguageSpan(text: " mo na", language: "fil")]),
            ReferenceUtterance(id: "b", text: "thank you", language: "en"),
            ReferenceUtterance(id: "c", text: "sige okay", language: "mixed"),
        ])
        let item = score(ref, "sige i sent mo thank you po sige okay")
        let breakdown = try XCTUnwrap(item.languageBreakdown.value)
        // tl words: sige(hit) mo(hit) na(deleted); en: i(hit) send(sub) thank you(hits).
        XCTAssertEqual(breakdown.byLanguage["tl"],
                       LanguageErrorCounts(referenceWords: 3, hits: 2, substitutions: 0, deletions: 1,
                                           rate: .available(1.0 / 3.0)))
        XCTAssertEqual(breakdown.byLanguage["en"],
                       LanguageErrorCounts(referenceWords: 4, hits: 3, substitutions: 1, deletions: 0,
                                           rate: .available(0.25)))
        XCTAssertNil(breakdown.byLanguage["other"])
        XCTAssertEqual(breakdown.unattributedReferenceWords, 2, "the mixed line has no word-level language")
        XCTAssertEqual(breakdown.insertionsUnattributed, 1)
        // Switch points in "a": i (tl->en) and mo (en->tl).
        let switches = try XCTUnwrap(breakdown.codeSwitchPoints.value)
        XCTAssertEqual([switches.referenceWords, switches.hits], [2, 2])
        let others = try XCTUnwrap(breakdown.nonSwitchPoints.value)
        XCTAssertEqual([others.referenceWords, others.hits, others.substitutions, others.deletions], [3, 1, 1, 1])
    }

    func testSpansNotAtWordBoundariesLeaveWordsUnattributed() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "nagmeeting kami",
                                                languageSpans: [LanguageSpan(text: "nag", language: "tl"),
                                                                LanguageSpan(text: "meeting", language: "en"),
                                                                LanguageSpan(text: " kami", language: "tl")])])
        let item = score(ref, "nagmeeting kami")
        XCTAssertEqual(item.utterances.value?.first?.normalizedReference, ["nagmeeting", "kami"])
        XCTAssertEqual(item.utterances.value?.first?.languageClass, .codeSwitched)
        let breakdown = try XCTUnwrap(item.languageBreakdown.value)
        XCTAssertEqual(breakdown.unattributedReferenceWords, 2)
        XCTAssertEqual(breakdown.byLanguage, [:])
        XCTAssertEqual(breakdown.codeSwitchPoints.value?.referenceWords, 0)
    }

    func testSpansThatDoNotConcatenateAreRejected() {
        let ref = reference([ReferenceUtterance(id: "a", text: "sige okay",
                                                languageSpans: [LanguageSpan(text: "sige", language: "tl"),
                                                                LanguageSpan(text: "okay", language: "en")])])
        XCTAssertThrowsError(try ref.validate())
    }

    func testLanguageBreakdownUnavailableWithoutAnnotation() {
        let item = score(reference([ReferenceUtterance(id: "a", text: "sige okay", language: "mixed")]), "sige")
        XCTAssertEqual(item.languageBreakdown.unavailableReason, "the reference has no language annotation")
        let tagged = score(reference([ReferenceUtterance(id: "a", text: "sige", language: "tl")]), "sige")
        XCTAssertNotNil(tagged.languageBreakdown.value)
        XCTAssertNotNil(tagged.languageBreakdown.value?.codeSwitchPoints.unavailableReason,
                        "switch points need spans")
    }

    // MARK: - Overlap

    func testExplicitOverlapFlag() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "sige", overlap: true),
                             ReferenceUtterance(id: "b", text: "okay po", overlap: false),
                             ReferenceUtterance(id: "c", text: "ano")])
        let item = score(ref, "sige okay ano")
        XCTAssertEqual(item.utterances.value?.map(\.overlap), [true, false, nil])
        let strata = try XCTUnwrap(item.byOverlap.value)
        // "c" has no mark and no timed turn: it is counted as unknown, not dropped.
        XCTAssertEqual(strata.map(\.stratum), ["overlap", "no-overlap", "unknown"])
        XCTAssertEqual(strata.map(\.utterances), [1, 1, 1])
        XCTAssertEqual(strata[0].wer, .available(0))
        XCTAssertEqual(strata[1].wer, .available(0.5))
        XCTAssertEqual(strata[2].wer, .available(0))
    }

    func testOverlapDerivedFromTimedSpeakers() throws {
        let ref = reference([
            ReferenceUtterance(id: "a", text: "isa", startMs: 0, endMs: 2000, speaker: "A"),
            ReferenceUtterance(id: "b", text: "dalawa", startMs: 1500, endMs: 2500, speaker: "B"),
            ReferenceUtterance(id: "c", text: "tatlo", startMs: 2500, endMs: 3000, speaker: "A"),   // touches b only
            ReferenceUtterance(id: "d", text: "apat", startMs: 2600, endMs: 2800, speaker: "A"),   // same speaker as c
            ReferenceUtterance(id: "e", text: "lima"),                                            // untimed
        ])
        let item = score(ref, "isa dalawa tatlo apat lima")
        XCTAssertEqual(item.utterances.value?.map(\.overlap), [true, true, false, false, nil])
        XCTAssertEqual(item.byOverlap.value?.map(\.utterances), [2, 2, 1])
    }

    func testOverlapUnavailableWithoutAnnotationOrTimedTurns() {
        let untimed = score(reference([ReferenceUtterance(id: "a", text: "isa", speaker: "A"),
                                       ReferenceUtterance(id: "b", text: "dalawa", speaker: "B")]), "isa")
        XCTAssertEqual(untimed.byOverlap.unavailableReason,
                       "the reference has no overlap annotation and no timed speaker turns")
        // Partial times: one timed turn is not enough to derive anything.
        let partial = score(reference([ReferenceUtterance(id: "a", text: "isa", startMs: 0, endMs: 900, speaker: "A"),
                                       ReferenceUtterance(id: "b", text: "dalawa", speaker: "B")]), "isa")
        XCTAssertNil(partial.byOverlap.value)
        XCTAssertEqual(partial.utterances.value?.map(\.overlap), [nil, nil])
    }

    // MARK: - Incomplete references

    func testUnpairedTimesAreRejected() {
        XCTAssertThrowsError(try reference([ReferenceUtterance(id: "a", text: "x", startMs: 10)]).validate())
    }

    func testNoTimesAndPartialTimes() throws {
        let none = score(reference([ReferenceUtterance(id: "a", text: "isa dalawa tatlo")]), "",
                         words: [])
        XCTAssertEqual(none.missingSpeech.unavailableReason, "the reference has no timestamps")
        XCTAssertNil(try XCTUnwrap(none.deletionBursts.value).first?.startMs)

        let partial = score(reference([ReferenceUtterance(id: "a", text: "isa dalawa", startMs: 0, endMs: 1500),
                                       ReferenceUtterance(id: "b", text: "tatlo apat")]), "", words: [])
        let report = try XCTUnwrap(partial.missingSpeech.value)
        XCTAssertEqual(report.checkedRegions, 1)
        XCTAssertEqual(report.missingRegions.map(\.utteranceIds), [["a"]])
        let burst = try XCTUnwrap(partial.deletionBursts.value?.first)
        XCTAssertEqual([burst.startMs, burst.endMs], [0, nil])
    }

    // MARK: - Deletion bursts

    func testDeletionBurstsNeedTheMinimumRun() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "isa dalawa tatlo apat lima anim pito walo")])
        // score.py gives (S, D, I) = (1, 4, 0); the tie-breaking substitutes
        // "x" for "anim", so dalawa..lima is one run of four deletions.
        let item = score(ref, "isa x pito walo")
        XCTAssertEqual(item.words, ErrorCounts(hits: 3, substitutions: 1, deletions: 4))
        XCTAssertEqual(try XCTUnwrap(item.deletionBursts.value),
                       [DeletionBurst(firstUtteranceId: "a", lastUtteranceId: "a", referenceStartIndex: 1, length: 4,
                                      words: ["dalawa", "tatlo", "apat", "lima"], startMs: nil, endMs: nil)])
        let five = score(ref, "isa x pito walo", config: EvaluationConfig(deletionBurstMinWords: 5))
        XCTAssertEqual(five.deletionBursts, .available([]))

        let scattered = score(ref, "isa tatlo lima pito")
        XCTAssertEqual(scattered.deletionBursts, .available([]), "single deletions between matches are no burst")
    }

    func testABurstCrossesUtterancesAndBreaksOnAnything() throws {
        let ref = reference([ReferenceUtterance(id: "a", text: "a b c"),
                             ReferenceUtterance(id: "b", text: "d e f g")])
        let item = score(ref, "a g", config: EvaluationConfig(deletionBurstMinWords: 2))
        let bursts = try XCTUnwrap(item.deletionBursts.value)
        XCTAssertEqual(bursts.map(\.words), [["b", "c", "d", "e", "f"]])
        XCTAssertEqual(bursts.map(\.firstUtteranceId), ["a"])
        XCTAssertEqual(bursts.map(\.lastUtteranceId), ["b"])
        XCTAssertEqual(bursts.first?.referenceStartIndex, 1)
        // A matched word in the middle splits the run in two.
        let split = score(ref, "a d g", config: EvaluationConfig(deletionBurstMinWords: 2))
        XCTAssertEqual(try XCTUnwrap(split.deletionBursts.value).map(\.words), [["b", "c"], ["e", "f"]])
    }

    // MARK: - Large input

    func testTooLargeForAPathFallsBackToCounts() {
        let ref = reference([ReferenceUtterance(id: "a", text: "isa dalawa tatlo"),
                             ReferenceUtterance(id: "b", text: "apat lima")])
        let hyp = EvaluationHypothesis(text: "isa tatlo apat lima anim")
        let item = Evaluator.score(reference: ref, hypothesis: hyp, config: config, maxAlignmentCells: 10)
        let full = Evaluator.score(reference: ref, hypothesis: hyp, config: config)
        XCTAssertEqual(item.words, full.words)
        XCTAssertEqual(item.wer, full.wer)
        let reason = "the item is too long for a word alignment (5 x 5 cells)"
        XCTAssertEqual(item.utterances.unavailableReason, reason)
        XCTAssertEqual(item.languageBreakdown.unavailableReason, reason)
        XCTAssertEqual(item.deletionBursts.unavailableReason, reason)
        XCTAssertEqual(item.byOverlap.unavailableReason, reason)
        XCTAssertEqual(item.byLanguageClass, [])
        // CER needs the word alignment to place hypothesis words in
        // utterances, so it is unavailable here and not a pooled zero.
        XCTAssertEqual(item.cer, .unavailable(reason: reason))
        XCTAssertEqual(item.characters, .zero)
    }

    // MARK: Findings of the independent review

    func testAnAnnotatedNoOverlapWinsOverTheDerivedOne() throws {
        let ref = reference([
            ReferenceUtterance(id: "a", text: "isa dalawa", startMs: 0, endMs: 2000, speaker: "A", overlap: false),
            ReferenceUtterance(id: "b", text: "tatlo apat", startMs: 1500, endMs: 3000, speaker: "B"),
        ])
        let item = Evaluator.score(reference: ref, hypothesis: EvaluationHypothesis(text: "isa dalawa tatlo apat"),
                                   config: config)
        let utterances = try XCTUnwrap(item.utterances.value)
        XCTAssertEqual(utterances.map(\.overlap), [false, true])
    }

    func testOverlapStrataAddUpToTheItem() throws {
        let ref = reference([
            ReferenceUtterance(id: "a", text: "isa dalawa", startMs: 0, endMs: 2000, speaker: "A"),
            ReferenceUtterance(id: "b", text: "tatlo apat", startMs: 1500, endMs: 3000, speaker: "B"),
            ReferenceUtterance(id: "c", text: "lima anim pito"),
            ReferenceUtterance(id: "d", text: "walo", startMs: 4000, endMs: 4000, speaker: "A"),
        ])
        let item = Evaluator.score(reference: ref, hypothesis: EvaluationHypothesis(text: "isa dalawa lima"),
                                   config: config)
        let strata = try XCTUnwrap(item.byOverlap.value)
        XCTAssertEqual(strata.map(\.stratum), ["overlap", "no-overlap", "unknown"])
        XCTAssertEqual(strata.map(\.utterances), [2, 0, 2])
        XCTAssertEqual(strata.reduce(ErrorCounts()) { $0 + $1.words }, item.words)
    }
}
