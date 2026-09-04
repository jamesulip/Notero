import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The live schedule, driven end to end with no model and no microphone.
///
/// The oracle recognizer reads each window's absolute position out of the PCM
/// and answers with the ground-truth words in it, so every test can say what
/// was said, feed the audio 100 ms at a time, and check both the committed
/// text and exactly which audio each decode was handed.
@MainActor
final class LiveDecoderTests: XCTestCase {

    final class Recorder {
        var committed: [Token] = []
        var batches = 0
        var partials: [String] = []
    }

    private enum Settle {
        /// Wait for every decode and VAD batch: the schedule runs as if the
        /// model were infinitely fast. Deterministic, and nothing is dropped.
        case all
        /// Let the VAD keep up while a decode is being held open.
        case vadOnly
    }

    private func word(_ text: String, _ start: Int, _ end: Int) -> SpokenWord {
        SpokenWord(text: text, startMs: start, endMs: end)
    }

    private func config(hop: Int = 1_500, preRoll: Int = 1_500, context: Int = 15_000,
                        adaptive: Bool = false, minHop: Int = 1_000) -> SessionConfig {
        SessionConfig(contextMs: context, hopMs: hop, silenceBoundaryMs: 700, agreement: 2,
                      language: "tl", prompt: nil, useNeuralVAD: false, preRollMs: preRoll,
                      adaptiveHop: adaptive, minHopMs: minHop)
    }

    private func make(words: [SpokenWord], speech: [Range<Int>],
                      config: SessionConfig? = nil)
        -> (decoder: LiveDecoder, asr: OracleRecognizer, vad: ScriptedVAD, out: Recorder) {
        let asr = OracleRecognizer(words: words)
        let vad = ScriptedVAD(speech: speech)
        let decoder = LiveDecoder(config: config ?? self.config(), recognizer: asr, vad: vad)
        let out = Recorder()
        decoder.onCommitted = { tokens in
            out.committed += tokens
            out.batches += 1
        }
        decoder.onPartial = { out.partials.append($0) }
        return (decoder, asr, vad, out)
    }

    /// Feeds 100 ms chunks from `clock` up to `untilMs`.
    private func feed(_ decoder: LiveDecoder, _ clock: inout Int, to untilMs: Int,
                      settle: Settle = .all) async {
        while clock < untilMs {
            decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
            clock += 100
            switch settle {
            case .all: await decoder.drain()
            case .vadOnly: await decoder.settleVAD()
            }
        }
    }

    /// The sentence from the request, spoken from 2.2 s so the first commit
    /// lands late enough for the pre-roll to be visible in the window start.
    private var quotation: [SpokenWord] {
        [word("so", 2_200, 2_500), word("yung", 2_500, 2_800), word("quotation", 2_800, 3_300),
         word("kailangan", 3_300, 3_800), word("nating", 3_800, 4_200),
         word("i-send", 4_600, 5_000), word("tomorrow", 5_000, 5_500)]
    }

    // MARK: - Pre-roll and the commit boundary

    func testCommitsCarryAbsoluteTimestampsAndNoDuplicatesAcrossBoundaries() async throws {
        let (decoder, asr, _, out) = make(words: quotation, speech: [2_200..<5_500])
        var clock = 0
        await feed(decoder, &clock, to: 8_000)

        XCTAssertEqual(out.committed.joinedText,
                       "so yung quotation kailangan nating i-send tomorrow")
        XCTAssertEqual(out.committed.map { [$0.startMs, $0.endMs] },
                       quotation.map { [$0.startMs, $0.endMs] },
                       "window-relative timings must come back on the session timeline")

        let calls = await asr.calls
        // Silence at 1.5 s is skipped, not decoded. The first two hops start
        // at zero; after "so yung" commits (end 2 800) the window starts
        // 1.5 s before that, and after "...nating" (end 4 200) likewise.
        XCTAssertEqual(calls.map(\.startMs), [0, 0, 1_300, 2_700])
        XCTAssertEqual(decoder.stats.skippedSilent, 2, "the silent hops at 1.5 s and 7.5 s")
        XCTAssertEqual(decoder.stats.boundaries, 1)
        XCTAssertEqual(decoder.stats.finalizations, 1)
        XCTAssertEqual(decoder.stats.droppedHops, 0)
        XCTAssertEqual(decoder.stats.forcedCommits, 0)
        XCTAssertEqual(decoder.stats.unagreedTailCommits, 0, "everything agreed")
        XCTAssertEqual(out.partials.last, "")
    }

    func testJitteredReDecodesOfThePreRollAreCaughtWithoutLosingWords() async throws {
        let (decoder, asr, _, out) = make(words: quotation, speech: [2_200..<5_500])
        await asr.setJitter(60)
        var clock = 0
        await feed(decoder, &clock, to: 8_000)

        XCTAssertEqual(out.committed.joinedText,
                       "so yung quotation kailangan nating i-send tomorrow")
        XCTAssertGreaterThan(decoder.stats.duplicatesDropped, 0,
                             "a boundary word drifted past the commit and text had to catch it")
        for (earlier, later) in zip(out.committed, out.committed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.startMs, earlier.endMs, "timeline went backwards")
        }
    }

    func testTheWindowStartsExactlyOnePreRollBeforeTheCommit() async throws {
        let (decoder, asr, _, _) = make(words: quotation, speech: [2_200..<5_500],
                                        config: config(preRoll: 1_000))
        var clock = 0
        await feed(decoder, &clock, to: 6_100)

        let calls = await asr.calls
        // "so yung" committed at 4.5 s with end 2 800; the 6 s hop starts 1 s before.
        XCTAssertEqual(calls.last?.startMs, 1_800)
        XCTAssertEqual(decoder.committedEndMs, 4_200)
    }

    // MARK: - Finalization on the VAD's clock

    func testSilenceTriggersTheFinalDecodeBeforeTheNextHop() async throws {
        let (decoder, asr, _, out) = make(words: [word("sige", 200, 600), word("na", 600, 1_000)],
                                          speech: [200..<1_000])
        var clock = 0
        await feed(decoder, &clock, to: 4_600)

        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.endMs), [1_500, 1_800],
                       "the final ran when silence reached 700 ms, not at the 3 s hop")
        XCTAssertEqual(out.committed.joinedText, "sige na")
        XCTAssertEqual(decoder.stats.finalizations, 1)
        XCTAssertEqual(decoder.stats.boundaries, 1)
        XCTAssertEqual(decoder.stats.unagreedTailCommits, 0, "the final decode agreed with the hop")
        // The final restarted the hop clock, so the one silent tick is at 3.3 s.
        XCTAssertEqual(decoder.stats.skippedSilent, 1)
    }

    func testWordsSpokenAfterTheLastHopAreCommittedAtTheBoundary() async throws {
        // The old boundary flushed the previous hop's hypothesis, whose window
        // ended at 1.5 s. "po" was never decoded by anyone.
        let (decoder, asr, _, out) = make(
            words: [word("sige", 200, 600), word("na", 600, 1_000), word("po", 1_400, 1_700)],
            speech: [200..<1_700]
        )
        var clock = 0
        await feed(decoder, &clock, to: 4_000)

        XCTAssertEqual(out.committed.joinedText, "sige na po")
        let calls = await asr.calls
        XCTAssertEqual(calls.map(\.endMs), [1_500, 2_700])
        XCTAssertEqual(decoder.stats.unagreedTailCommits, 1, "\"po\": only the final decode heard it whole")
        XCTAssertEqual(decoder.stats.boundaries, 1)
    }

    func testAHopThatAlreadyCoversTheUtteranceEndsItWithoutASecondDecode() async throws {
        let (decoder, asr, _, out) = make(words: [word("sige", 200, 600), word("na", 600, 1_000)],
                                          speech: [200..<1_000])
        await asr.hold()
        var clock = 0
        await feed(decoder, &clock, to: 1_500, settle: .vadOnly)   // the hop starts, and hangs
        await feed(decoder, &clock, to: 1_800, settle: .vadOnly)   // silence reaches 700 ms
        await asr.release()
        await decoder.drain()

        let calls = await asr.calls
        XCTAssertEqual(calls.count, 1, "the hop's window reached past the speech; reuse it")
        XCTAssertEqual(out.committed.joinedText, "sige na")
        XCTAssertEqual(decoder.stats.finalizations, 0)
        XCTAssertEqual(decoder.stats.boundaries, 1)
        XCTAssertEqual(decoder.stats.unagreedTailCommits, 2)
    }

    func testAFinalRequestedDuringAHopRunsOnceAfterItAndSupersedesTheNextHop() async throws {
        let (decoder, asr, _, out) = make(
            words: [word("sige", 200, 600), word("na", 600, 1_000), word("po", 1_400, 1_700)],
            speech: [200..<1_700]
        )
        await asr.hold()
        var clock = 0
        await feed(decoder, &clock, to: 1_500, settle: .vadOnly)   // hop held open
        await feed(decoder, &clock, to: 3_000, settle: .vadOnly)   // silence at 2.7 s, hop tick at 3 s
        let calls1 = await asr.calls
        XCTAssertEqual(calls1.count, 1)
        XCTAssertEqual(decoder.stats.droppedHops, 0, "a hop superseded by a pending final is not a drop")

        await asr.release()
        await decoder.drain()

        let calls = await asr.calls
        XCTAssertEqual(calls.count, 2, "exactly one final, coalesced")
        XCTAssertEqual(calls[1].endMs, 3_000, "the final decodes everything up to now")
        XCTAssertEqual(out.committed.joinedText, "sige na po")
        XCTAssertEqual(decoder.stats.finalizations, 1)
        XCTAssertEqual(decoder.stats.boundaries, 1)
    }

    func testAPendingFinalIsDroppedWhenSpeechResumesBeforeTheHopReturns() async throws {
        let (decoder, asr, _, _) = make(
            words: [word("sige", 200, 600), word("na", 600, 1_000), word("po", 1_400, 1_700),
                    word("ulit", 2_800, 3_200)],
            speech: [200..<1_700, 2_800..<3_200]
        )
        await asr.hold()
        var clock = 0
        await feed(decoder, &clock, to: 1_500, settle: .vadOnly)
        await feed(decoder, &clock, to: 3_300, settle: .vadOnly)   // silent at 2.7 s, talking again by 3 s
        await asr.release()
        await decoder.drain()

        let calls2 = await asr.calls
        XCTAssertEqual(calls2.count, 1, "no final for a pause that turned out not to be one")
        XCTAssertEqual(decoder.stats.finalizationsAbandoned, 1)
        XCTAssertEqual(decoder.stats.boundaries, 0)
    }

    func testSpeechResumingDuringTheFinalDecodeLeavesTheRemainderProvisional() async throws {
        let (decoder, asr, _, out) = make(
            words: [word("sige", 200, 600), word("na", 600, 1_000), word("ulit", 2_000, 2_400)],
            speech: [200..<1_000, 2_000..<2_400]
        )
        // The final decode (call 2) disagrees with the hop on its last word.
        await asr.setMutation { text, call, isLast in call == 2 && isLast ? "???" : text }
        var clock = 0
        await feed(decoder, &clock, to: 1_500)                       // hop: "sige na"
        await asr.hold()
        await feed(decoder, &clock, to: 1_800, settle: .vadOnly)     // final starts, hangs
        await feed(decoder, &clock, to: 2_400, settle: .vadOnly)     // speech resumes meanwhile
        await asr.release()
        await decoder.drain()

        XCTAssertEqual(out.committed.joinedText, "sige", "only what the two passes agreed on")
        XCTAssertEqual(decoder.partial, "???", "the disputed tail stays provisional")
        XCTAssertEqual(decoder.stats.finalizationsAbandoned, 1)
        XCTAssertEqual(decoder.stats.boundaries, 0)

        // The next pause closes it properly: the 3.3 s hop already covers the
        // end of "ulit", so it is used and no second final decode is needed.
        await feed(decoder, &clock, to: 4_000)
        XCTAssertEqual(out.committed.joinedText, "sige na ulit")
        XCTAssertEqual(decoder.stats.boundaries, 1)
        XCTAssertEqual(decoder.stats.finalizations, 1)
        XCTAssertEqual(decoder.stats.unagreedTailCommits, 2, "\"na ulit\" against a stale \"???\"")
    }

    func testAContinuedPauseIsNotFinalizedTwice() async throws {
        let (decoder, asr, _, _) = make(words: [word("sige", 200, 600)], speech: [200..<600])
        var clock = 0
        await feed(decoder, &clock, to: 10_000)

        XCTAssertEqual(decoder.stats.boundaries, 1)
        let calls3 = await asr.calls
        XCTAssertLessThanOrEqual(calls3.count, 2)
        XCTAssertGreaterThanOrEqual(decoder.stats.skippedSilent, 5)
    }

    func testFinalizationReArmsWhenOneBatchSpansSpeechAndSilence() async throws {
        // 80 ms of speech inside a single VAD batch: the trailing-silence
        // counter never reads zero, it just gets smaller. That must re-arm.
        let (decoder, _, _, out) = make(words: [word("sige", 200, 600), word("oo", 2_110, 2_190)],
                                        speech: [200..<600, 2_110..<2_190])
        var clock = 0
        await feed(decoder, &clock, to: 4_000)

        XCTAssertEqual(out.committed.joinedText, "sige oo")
        XCTAssertEqual(decoder.stats.boundaries, 2)
    }

    // MARK: - Drops, stalls, adaptive hop

    func testAHopThatLandsDuringADecodeIsDroppedNotQueued() async throws {
        let words = (0..<20).map { word("w\($0)", $0 * 500, $0 * 500 + 400) }
        let (decoder, asr, _, _) = make(words: words, speech: [0..<10_000])
        await asr.hold()
        var clock = 0
        await feed(decoder, &clock, to: 3_000, settle: .vadOnly)
        XCTAssertEqual(decoder.stats.droppedHops, 1)
        await asr.release()
        await decoder.drain()
        let calls4 = await asr.calls
        XCTAssertEqual(calls4.count, 1, "the dropped hop never decoded")
    }

    func testAStallForcesCommitsWhenTheWindowHasToSlide() async throws {
        // Every pass names every word differently, so nothing ever agrees.
        let words = (0..<40).map { word("w\($0)", $0 * 500, $0 * 500 + 400) }
        let (decoder, asr, _, out) = make(words: words, speech: [0..<20_000],
                                          config: config(preRoll: 1_000, context: 4_000))
        await asr.setMutation { text, call, _ in "\(text)_\(call)" }
        var clock = 0
        await feed(decoder, &clock, to: 12_000)

        XCTAssertGreaterThan(decoder.stats.forcedCommits, 0)
        XCTAssertFalse(out.committed.isEmpty)
        for (earlier, later) in zip(out.committed, out.committed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.startMs, earlier.endMs)
        }
        XCTAssertGreaterThan(decoder.committedEndMs, 0)
    }

    func testAdaptiveHopShortensOnlyWhileDecodesAreFast() async throws {
        let words = (0..<20).map { word("w\($0)", $0 * 500, $0 * 500 + 400) }
        let (decoder, asr, _, _) = make(words: words, speech: [0..<10_000],
                                        config: config(adaptive: true, minHop: 1_000))
        await asr.setInferMs(200)
        var clock = 0
        await feed(decoder, &clock, to: 3_100)
        let calls5 = await asr.calls
        XCTAssertEqual(calls5.map(\.endMs), [1_000, 2_000, 3_000])

        // A 1.2 s decode: 1.5x that is above the ceiling, so the hop is back to 1.5 s.
        await asr.setInferMs(1_200)
        await feed(decoder, &clock, to: 5_600)
        let calls6 = await asr.calls
        XCTAssertEqual(calls6.map(\.endMs), [1_000, 2_000, 3_000, 4_000, 5_500])
        XCTAssertEqual(decoder.currentHopMs, 1_500)
        XCTAssertEqual(decoder.stats.droppedHops, 0)
    }

    func testFixedHopIgnoresDecodeCost() async throws {
        let words = (0..<20).map { word("w\($0)", $0 * 500, $0 * 500 + 400) }
        let (decoder, asr, _, _) = make(words: words, speech: [0..<10_000])
        await asr.setInferMs(100)
        var clock = 0
        await feed(decoder, &clock, to: 3_100)
        let calls7 = await asr.calls
        XCTAssertEqual(calls7.map(\.endMs), [1_500, 3_000])
    }

    // MARK: - Things nobody said

    func testWordsDecodedOutOfThePaddingAreNeverCommitted() async throws {
        // Whisper pads every window to 30 s and reads the padding, usually by
        // saying the last phrase again with timestamps past the audio. Clamped
        // to the ceiling, those used to commit as zero-length duplicates.
        let (decoder, asr, _, out) = make(words: quotation, speech: [2_200..<5_500])
        await asr.setPhantoms([], inPadding: true)
        var clock = 0
        await feed(decoder, &clock, to: 8_000)

        XCTAssertEqual(out.committed.joinedText,
                       "so yung quotation kailangan nating i-send tomorrow")
        XCTAssertFalse(out.committed.contains { $0.text.contains("hallucinated") })
        XCTAssertGreaterThanOrEqual(decoder.stats.hallucinationsDropped, 3)
    }

    func testWordsPlacedInTheClosedSilenceAreNotCommittedAtTheBoundary() async throws {
        // "Thank you." 400 ms into a pause the VAD has already closed.
        let (decoder, asr, _, out) = make(words: [word("sige", 200, 600), word("na", 600, 1_000)],
                                          speech: [200..<1_000])
        await asr.setPhantoms([word("thank", 1_400, 1_550), word("you.", 1_550, 1_700)])
        var clock = 0
        await feed(decoder, &clock, to: 4_000)

        XCTAssertEqual(out.committed.joinedText, "sige na")
        XCTAssertEqual(decoder.stats.boundaries, 1)
        XCTAssertGreaterThanOrEqual(decoder.stats.hallucinationsDropped, 2)
    }

    // MARK: - Stop

    func testFinishDrainsTheDecodeInFlightAndHearsTheTailOnceMore() async throws {
        let (decoder, asr, _, out) = make(
            words: [word("sige", 200, 600), word("na", 600, 1_000), word("po", 1_400, 1_700)],
            speech: [200..<1_700]
        )
        await asr.hold()
        var clock = 0
        await feed(decoder, &clock, to: 1_500, settle: .vadOnly)   // hop held
        await feed(decoder, &clock, to: 2_700, settle: .vadOnly)   // a final is now pending

        let finishing = Task { await decoder.finish() }
        await asr.release()
        await finishing.value

        XCTAssertEqual(out.committed.joinedText, "sige na po")
        let afterFinish = await asr.calls
        XCTAssertEqual(afterFinish.count, 2,
                       "the held hop, then one look at the tail -- not a chained final as well")
        XCTAssertEqual(out.partials.last, "")

        // Nothing after Stop reaches anyone.
        let settled = out.committed.count
        decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
        await decoder.drain()
        XCTAssertEqual(out.committed.count, settled)
        let calls8 = await asr.calls
        XCTAssertEqual(calls8.count, 2)
    }

    func testFinishSkipsTheExtraDecodeWhenNothingNewWasHeard() async throws {
        let (decoder, asr, _, out) = make(words: [word("sige", 200, 600), word("na", 600, 1_000)],
                                          speech: [200..<1_000])
        var clock = 0
        await feed(decoder, &clock, to: 1_500)
        await decoder.finish()

        let calls9 = await asr.calls
        XCTAssertEqual(calls9.count, 1, "the hop at 1.5 s heard everything there was")
        XCTAssertEqual(out.committed.joinedText, "sige na")
    }
}
