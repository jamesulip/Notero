import XCTest
@testable import TranscriberCore

final class WaveformDisplayTests: XCTestCase {

    // MARK: - Bar height

    /// The bug this file exists for: the stored envelope is peak-normalized, so
    /// putting it through the meter curve as well left a quiet passage almost
    /// as tall as a loud one and the whole thing drew as a slab.
    func testEnvelopeKeepsContrastTheMeterCurveThrowsAway() {
        let quiet = WaveformScale.envelope.fraction(0.01)
        let loud = WaveformScale.envelope.fraction(1.0)
        XCTAssertEqual(loud, 1.0, accuracy: 0.001)
        XCTAssertEqual(quiet, 0.1, accuracy: 0.001)
        // The same pair on the meter curve, for the record.
        XCTAssertGreaterThan(WaveformScale.level.fraction(0.01), 0.3)
    }

    func testEnvelopeIsMonotonicAndBounded() {
        var previous: Float = -1
        for step in 0...100 {
            let fraction = WaveformScale.envelope.fraction(Float(step) / 100)
            XCTAssertGreaterThanOrEqual(fraction, previous)
            XCTAssertLessThanOrEqual(fraction, 1)
            previous = fraction
        }
    }

    func testSilenceIsZeroOnBothCurves() {
        XCTAssertEqual(WaveformScale.envelope.fraction(0), 0)
        XCTAssertEqual(WaveformScale.level.fraction(0), 0)
    }

    func testOutOfRangeAmplitudesAreClamped() {
        XCTAssertEqual(WaveformScale.envelope.fraction(4), 1.0, accuracy: 0.001)
        XCTAssertEqual(WaveformScale.envelope.fraction(-1), 1.0, accuracy: 0.001)
        XCTAssertEqual(WaveformScale.level.fraction(4), 1.0, accuracy: 0.001)
    }

    /// The live meter is judged against an absolute level, so its curve must
    /// stay the decibel one it shares with the clipping warning.
    func testLevelCurveStillMatchesTheMeter() {
        for amplitude: Float in [0.01, 0.05, 0.2, 0.5, 1.0] {
            XCTAssertEqual(WaveformScale.level.fraction(amplitude),
                           InputGain.meterFraction(amplitude), accuracy: 0.0001)
        }
    }

    // MARK: - Bar count

    func testFittedReducesToExactlyTheBarsAsked() {
        let samples = (0..<600).map { Float($0) / 600 }
        XCTAssertEqual(WaveformBars.fitted(samples, to: 120).count, 120)
        XCTAssertEqual(WaveformBars.fitted(samples, to: 1).count, 1)
    }

    /// Averaging would smooth away the one-bucket transient that a peak
    /// envelope exists to show.
    func testFittedKeepsTheLoudestOfEachGroup() {
        var samples = [Float](repeating: 0.1, count: 100)
        samples[42] = 1.0
        let bars = WaveformBars.fitted(samples, to: 10)
        XCTAssertEqual(bars.count, 10)
        XCTAssertEqual(bars[4], 1.0, accuracy: 0.0001)
        XCTAssertEqual(bars.filter { $0 > 0.5 }.count, 1)
    }

    func testFittedStretchesAnEnvelopeShorterThanTheView() {
        let bars = WaveformBars.fitted([0, 1, 0], to: 9)
        XCTAssertEqual(bars.count, 9)
        XCTAssertEqual(bars.max(), 1)
        XCTAssertEqual(bars.first, 0)
        XCTAssertEqual(bars.last, 0)
    }

    /// A recording still being analysed has no envelope. A row of zeros draws a
    /// flat line to scrub along; returning nothing left a hole where the player
    /// should be.
    func testFittedGivesAFlatLineForAnEmptyEnvelope() {
        let bars = WaveformBars.fitted([], to: 40)
        XCTAssertEqual(bars.count, 40)
        XCTAssertTrue(bars.allSatisfy { $0 == 0 })
    }

    func testFittedHandlesZeroBars() {
        XCTAssertTrue(WaveformBars.fitted([0.5, 0.5], to: 0).isEmpty)
    }

    /// The live meter fix: a half-full buffer pads on the left rather than
    /// stretching, so bar width stays put and the history scrolls.
    func testTrailingPadsAtTheLeftAndKeepsTheNewestAtTheRight() {
        let bars = WaveformBars.trailing([0.2, 0.4, 0.6], in: 6)
        XCTAssertEqual(bars, [0, 0, 0, 0.2, 0.4, 0.6])
    }

    func testTrailingDropsTheOldestWhenTheBufferOverflowsTheView() {
        let samples = (0..<10).map { Float($0) }
        XCTAssertEqual(WaveformBars.trailing(samples, in: 3), [7, 8, 9])
    }

    func testTrailingOfAnEmptyMeterIsAllSilence() {
        XCTAssertEqual(WaveformBars.trailing([], in: 4), [0, 0, 0, 0])
    }
}
