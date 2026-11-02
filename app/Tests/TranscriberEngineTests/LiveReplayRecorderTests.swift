import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The recorder is how the latency experiment sees the live path, so it has to
/// agree with the decoder it watches: same commits, same words, same drops.
@MainActor
final class LiveReplayRecorderTests: XCTestCase {

    private func word(_ text: String, _ start: Int, _ end: Int) -> SpokenWord {
        SpokenWord(text: text, startMs: start, endMs: end)
    }

    /// Two utterances ten words each, a 2 s pause between, fed 100 ms at a time.
    private func scenario() -> (words: [SpokenWord], speech: [Range<Int>], totalMs: Int) {
        var words: [SpokenWord] = []
        var t = 400
        var speech: [Range<Int>] = []
        for utterance in 0..<2 {
            let start = t
            for i in 0..<10 {
                words.append(word("u\(utterance)w\(i)", t, t + 320))
                t += 400
            }
            speech.append(start..<t)
            t += 2_000
        }
        return (words, speech, t)
    }

    private func replay(config: SessionConfig, awaiting: Bool = true)
        async -> (decoder: LiveDecoder, trace: LiveReplayTrace, downstream: [Token]) {
        let scene = scenario()
        let asr = OracleRecognizer(words: scene.words)
        let vad = ScriptedVAD(speech: scene.speech)
        let decoder = LiveDecoder(config: config, recognizer: asr, vad: vad)
        var downstream: [Token] = []
        let recorder = LiveReplayRecorder(decoder: decoder, realtime: !awaiting) { downstream += $0 }
        recorder.begin()
        var clock = 0
        while clock < scene.totalMs {
            recorder.noteFed(clock + 100)
            decoder.ingest(OraclePCM.data(fromMs: clock, ms: 100))
            clock += 100
            await decoder.drain()
        }
        recorder.noteFed(scene.totalMs)
        await decoder.finish()
        return (decoder, recorder.finish(), downstream)
    }

    private func config(headTolerance: Int = 0) -> SessionConfig {
        SessionConfig(contextMs: 15_000, hopMs: 1_500, silenceBoundaryMs: 700, agreement: 2,
                      language: "tl", prompt: nil, useNeuralVAD: false, preRollMs: 1_500,
                      adaptiveHop: false, minHopMs: 1_000, headTolerance: headTolerance, headMinRun: 3)
    }

    func testTheRecordedCommitsAreExactlyWhatTheDecoderCommitted() async throws {
        let run = await replay(config: config())

        XCTAssertEqual(run.downstream, run.decoder.committed, "the downstream consumer still gets every batch")
        let recordedEnds = run.trace.commits.flatMap(\.wordEndMs)
        XCTAssertEqual(recordedEnds, run.decoder.committed.map(\.endMs))
        XCTAssertEqual(run.trace.commits.flatMap(\.wordStartMs), run.decoder.committed.map(\.startMs))
        XCTAssertEqual(run.decoder.committed.count, 20)
        XCTAssertTrue(run.trace.invariants.holds, "\(run.trace.invariants.violations)")
        XCTAssertEqual(run.trace.invariants.words, 20)
    }

    func testEveryBatchCarriesTheReasonItWasCommittedFor() async throws {
        let run = await replay(config: config())

        let reasons = Set(run.trace.commits.map(\.reason))
        XCTAssertTrue(reasons.contains(.agreed), "\(reasons)")
        // A 2 s pause closes the first utterance, committing its tail without agreement,
        // and the session end commits what the last pause did not.
        XCTAssertTrue(reasons.contains(.boundaryTail) || reasons.contains(.finish), "\(reasons)")
        XCTAssertEqual(run.trace.commits.map { $0.wordEndMs.count }.reduce(0, +), 20)
    }

    func testTheTraceCountsMatchTheDecodersOwnStats() async throws {
        let run = await replay(config: config())
        let stats = run.decoder.stats

        XCTAssertEqual(run.trace.decodes.count, stats.hops + stats.failedHops)
        XCTAssertEqual(run.trace.dropped.count, stats.droppedHops)
        XCTAssertEqual(run.trace.skippedSilent, stats.skippedSilent)
        XCTAssertEqual(run.trace.boundaries.count, stats.boundaries)
        XCTAssertEqual(run.trace.abandoned.count, stats.finalizationsAbandoned)
        XCTAssertGreaterThan(run.trace.vad.batches, 0)
        XCTAssertEqual(run.trace.vad.failed, 0)
    }

    func testTimesAreRelativeToTheStartOfTheReplay() async throws {
        let run = await replay(config: config())

        XCTAssertGreaterThan(run.trace.replayWallMs, 0)
        for commit in run.trace.commits {
            XCTAssertGreaterThanOrEqual(commit.wallMs, 0)
            XCTAssertLessThanOrEqual(commit.wallMs, run.trace.replayWallMs)
        }
        for span in run.trace.decodes {
            XCTAssertGreaterThanOrEqual(span.requestedWallMs, 0)
        }
        XCTAssertGreaterThanOrEqual(run.trace.cpu.totalMs, 0)
    }

    func testAudioFedIsWhatTheReplayHadHandedOverWhenTheBatchWasDelivered() async throws {
        let run = await replay(config: config())

        for commit in run.trace.commits {
            let newest = commit.wordEndMs.max() ?? 0
            XCTAssertGreaterThanOrEqual(commit.audioFedMs, newest,
                                        "a word cannot be committed before the audio containing it arrived")
        }
    }

    func testHeadTolerantReplaysKeepTheInvariantToo() async throws {
        let run = await replay(config: config(headTolerance: 3))
        XCTAssertTrue(run.trace.invariants.holds, "\(run.trace.invariants.violations)")
        XCTAssertEqual(run.downstream, run.decoder.committed)
    }

    func testTheTraceEncodesAndDecodesUnchanged() async throws {
        let run = await replay(config: config())
        let data = try JSONEncoder().encode(run.trace)
        let back = try JSONDecoder().decode(LiveReplayTrace.self, from: data)
        XCTAssertEqual(back, run.trace)
    }
}
