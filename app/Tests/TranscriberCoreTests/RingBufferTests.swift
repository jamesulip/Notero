import XCTest
@testable import TranscriberCore

/// If `windowStartMs` drifts, every downstream timestamp drifts with it:
/// segment boundaries, SRT cues, and the overlap merge diarization would use.
final class RingBufferTests: XCTestCase {

    private func audio(_ ms: Int) -> Data {
        Data(repeating: 1, count: Audio.msToBytes(ms))
    }

    func testBufferHoldsOnlyTheContextWindow() {
        let ring = RingBuffer(contextMs: 15_000)
        ring.push(audio(20_000))
        XCTAssertEqual(ring.durationMs, 15_000)
        XCTAssertEqual(ring.totalMs, 20_000)
    }

    func testWindowStartTracksDiscardedAudio() {
        let ring = RingBuffer(contextMs: 15_000)
        ring.push(audio(10_000))
        XCTAssertEqual(ring.windowStartMs, 0)

        ring.push(audio(10_000))
        XCTAssertEqual(ring.windowStartMs, 5_000)
        XCTAssertEqual(ring.windowStartMs + ring.durationMs, ring.totalMs)
    }

    func testTimelineStaysExactOverManySmallPushes() {
        // Frames arrive every 100 ms; rounding must not accumulate.
        let ring = RingBuffer(contextMs: 15_000)
        for _ in 0..<600 { ring.push(audio(100)) }
        XCTAssertEqual(ring.totalMs, 60_000)
        XCTAssertEqual(ring.durationMs, 15_000)
        XCTAssertEqual(ring.windowStartMs, 45_000)
    }

    func testTrimAnchorsTheWindowAtACommit() {
        let ring = RingBuffer(contextMs: 15_000)
        ring.push(audio(10_000))
        ring.trim(to: 4_000)
        XCTAssertEqual(ring.windowStartMs, 4_000)
        XCTAssertEqual(ring.durationMs, 6_000)
        XCTAssertEqual(ring.totalMs, 10_000)
    }

    func testTrimIsMonotonicAndIgnoresThePast() {
        let ring = RingBuffer(contextMs: 15_000)
        ring.push(audio(10_000))
        ring.trim(to: 6_000)
        ring.trim(to: 2_000)
        XCTAssertEqual(ring.windowStartMs, 6_000)
    }

    func testWindowReturnsItsOwnStart() {
        let ring = RingBuffer(contextMs: 5_000)
        ring.push(audio(8_000))
        let (pcm, start) = ring.window()
        XCTAssertEqual(start, 3_000)
        XCTAssertEqual(pcm.count, Audio.msToBytes(5_000))
    }
}

/// Pre-roll: committed audio kept in front of the active region so a decode
/// never starts cold at the commit. Context only -- the consumer must not
/// commit it twice -- but the ring has to hold it and account for it.
extension RingBufferTests {
    func testTrimKeepsThePreRollInFrontOfTheCommit() {
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 1_500)
        ring.push(audio(10_000))
        ring.trim(to: 4_000)
        XCTAssertEqual(ring.windowStartMs, 2_500, "1.5 s of committed audio stays")
        XCTAssertEqual(ring.durationMs, 7_500)
        XCTAssertEqual(ring.totalMs, 10_000, "the absolute clock is untouched")
    }

    func testPreRollIsClampedAtTheStartOfTheSession() {
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 1_500)
        ring.push(audio(3_000))
        ring.trim(to: 1_000)
        XCTAssertEqual(ring.windowStartMs, 0)
        XCTAssertEqual(ring.durationMs, 3_000)
    }

    func testCapacityHoldsThePreRollAndAFullActiveRegion() {
        // The pre-roll must not be paid for out of the 15 s of context.
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 1_500)
        ring.push(audio(30_000))
        XCTAssertEqual(ring.durationMs, 16_500)
        XCTAssertEqual(ring.windowStartMs, 13_500)
    }

    func testWindowStartStaysAbsoluteAndTrimStaysMonotonicWithPreRoll() {
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 1_500)
        for _ in 0..<100 { ring.push(audio(100)) }
        ring.trim(to: 6_000)
        let (pcm, start) = ring.window()
        XCTAssertEqual(start, 4_500)
        XCTAssertEqual(pcm.count, Audio.msToBytes(5_500))

        // Trimming to the same commit again, or to an earlier one, moves nothing.
        ring.trim(to: 6_000)
        ring.trim(to: 3_000)
        XCTAssertEqual(ring.windowStartMs, 4_500)
    }

    func testZeroPreRollIsTheOldBehaviour() {
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 0)
        ring.push(audio(10_000))
        ring.trim(to: 4_000)
        XCTAssertEqual(ring.windowStartMs, 4_000)
        XCTAssertEqual(ring.capacityBytes, Audio.msToBytes(15_000))
    }
}
