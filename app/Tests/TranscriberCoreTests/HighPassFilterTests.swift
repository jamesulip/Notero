import Foundation
import Testing
@testable import TranscriberCore

@Suite("Room-mode high-pass")
struct HighPassFilterTests {

    private static let sampleRate = 16_000.0

    /// Amplitude of a pure tone after filtering, relative to before, in dB.
    ///
    /// Measured as RMS rather than peak. A sampled sine rarely lands a sample on
    /// its crest, so peak carries ~0.01 dB of phase-dependent jitter -- more
    /// than the real difference across the passband, which would make a
    /// correctly flat filter look non-monotonic. RMS is independent of where the
    /// samples fall, and the frequencies below all complete whole cycles in the
    /// measured window, so there is no partial-period ripple either.
    private func responseDb(at hz: Float,
                            corner: Float = HighPassFilter.roomCornerHz) -> Float {
        let sr = Float(Self.sampleRate)
        let count = 16_000
        var samples = (0..<count).map { sinf(2 * .pi * hz * Float($0) / sr) }
        HighPassFilter(cornerHz: corner, sampleRate: Self.sampleRate).process(&samples)
        // Tail only: the head is the filter settling, which is a transient
        // rather than a steady-state response.
        let tail = Array(samples[(count / 2)...])
        let rms = sqrt(tail.reduce(Float(0)) { $0 + $1 * $1 } / Float(tail.count))
        // A unit sine has RMS 1/sqrt(2); referencing to that makes 0 dB mean
        // "passed through unchanged".
        return 20 * log10(max(rms, 1e-9) * sqrt(2))
    }

    @Test("Speech passes essentially untouched")
    func passband() {
        for hz in [Float(600), 1_000, 2_000, 3_000] {
            let response = responseDb(at: hz)
            #expect(response > -1, "\(hz) Hz attenuated by \(-response) dB")
            #expect(response < 1, "\(hz) Hz boosted by \(response) dB")
        }
    }

    @Test("The corner sits near -3 dB, as Butterworth defines it")
    func corner() {
        let response = responseDb(at: HighPassFilter.roomCornerHz)
        #expect(response < -1)
        #expect(response > -8)
    }

    /// The band that measured 85% of a meeting recording's energy.
    @Test("Rumble below the corner is removed, harder the lower it goes")
    func stopband() {
        let at125 = responseDb(at: 125)
        let at60 = responseDb(at: 60)
        #expect(at125 < -18, "125 Hz only down \(-at125) dB")
        #expect(at60 < -40, "60 Hz only down \(-at60) dB")
        #expect(at60 < at125, "slope should steepen below the corner")
    }

    @Test("Response rises monotonically with frequency")
    func monotonic() {
        let sweep: [Float] = [50, 100, 150, 200, 300, 500, 1_000]
        let responses = sweep.map { responseDb(at: $0) }
        #expect(zip(responses, responses.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("A corner above Nyquist is clamped rather than producing NaNs")
    func degenerateCorner() {
        var samples = (0..<512).map { sinf(Float($0) * 0.1) }
        HighPassFilter(cornerHz: 40_000, sampleRate: Self.sampleRate).process(&samples)
        #expect(samples.allSatisfy { $0.isFinite })
    }

    @Test("Reset clears the delay line")
    func reset() {
        let filter = HighPassFilter(cornerHz: HighPassFilter.roomCornerHz,
                                    sampleRate: Self.sampleRate)
        var loud = [Float](repeating: 0.9, count: 512)
        filter.process(&loud)
        filter.reset()
        var silence = [Float](repeating: 0, count: 512)
        filter.process(&silence)
        #expect(silence.allSatisfy { $0 == 0 })
    }

    @Test("Filtering never introduces out-of-range samples")
    func staysBounded() {
        var samples = (0..<8_000).map { _ in Float.random(in: -1...1) }
        HighPassFilter(cornerHz: HighPassFilter.roomCornerHz,
                       sampleRate: Self.sampleRate).process(&samples)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) < 4 })
    }

    // MARK: - The PCMSource decorator

    @Test("Wrapping preserves length and leaves the base untouched")
    func decoratorShape() {
        let base = ArrayPCM((0..<5_000).map { sinf(Float($0) * 0.3) })
        let wrapped = HighPassPCM(base, sampleRate: Self.sampleRate)
        #expect(wrapped.sampleCount == base.sampleCount)
        #expect(wrapped.floats(0..<1_000).count == 1_000)
        #expect(base.floats(0..<10) == ArrayPCM(base.samples).floats(0..<10))
    }

    /// The regression this guards: a stateful filter over random-access reads
    /// restarts its step response at every window boundary, so each decode
    /// window would open with a transient exactly where words get cut.
    @Test("Reads mid-stream match a filter run over the whole source")
    func warmUpMatchesContinuousFiltering() {
        let tone = (0..<20_000).map { sinf(2 * .pi * 900 * Float($0) / 16_000) }
        let whole = HighPassFilter.filtered(tone, cornerHz: HighPassFilter.roomCornerHz,
                                            sampleRate: Self.sampleRate)
        let piece = HighPassPCM(ArrayPCM(tone), sampleRate: Self.sampleRate)
            .floats(10_000..<11_000)
        let expected = Array(whole[10_000..<11_000])
        let worst = zip(piece, expected).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 0.01, "seam error \(worst)")
    }

    @Test("Out-of-range reads are clamped, not crashes")
    func decoratorBounds() {
        let wrapped = HighPassPCM(ArrayPCM([Float](repeating: 0.5, count: 100)),
                                  sampleRate: Self.sampleRate)
        #expect(wrapped.floats(-50..<50).count == 50)
        #expect(wrapped.floats(90..<500).count == 10)
        #expect(wrapped.floats(200..<300).isEmpty)
    }
}
