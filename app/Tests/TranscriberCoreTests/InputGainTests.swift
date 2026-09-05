import Testing
@testable import TranscriberCore

@Suite("Input gain")
struct InputGainTests {

    @Test("0 dB is exactly unity")
    func unity() {
        #expect(InputGain.linear(fromDb: 0) == 1)
    }

    @Test("Decibels convert to the textbook ratios")
    func ratios() {
        #expect(abs(InputGain.linear(fromDb: 6) - 1.995) < 0.01)   // ~2x
        #expect(abs(InputGain.linear(fromDb: 20) - 10) < 0.01)     // 10x
        #expect(abs(InputGain.linear(fromDb: -6) - 0.501) < 0.01)  // ~0.5x
    }

    @Test("dB survives a round trip through linear")
    func roundTrip() {
        for db in stride(from: Float(-12), through: 30, by: 3) {
            #expect(abs(InputGain.db(fromLinear: InputGain.linear(fromDb: db)) - db) < 0.01)
        }
    }

    @Test("Gain outside the slider range is refused")
    func clamping() {
        #expect(InputGain.clampDb(120) == InputGain.maxDb)
        #expect(InputGain.clampDb(-90) == InputGain.minDb)
    }

    /// The failure this guards is not cosmetic: a float above 1.0 converted to
    /// Int16 wraps rather than saturating, so the loudest syllable of a word
    /// comes back as full-scale noise of the opposite sign.
    @Test("Boosting past full scale clamps instead of wrapping")
    func clampsRatherThanWraps() {
        var samples: [Float] = [0.8, -0.8, 0.3, -0.3, 0]
        samples.withUnsafeMutableBufferPointer {
            InputGain.apply(4, to: $0.baseAddress!, count: $0.count)
        }
        #expect(samples[0] == 1)
        #expect(samples[1] == -1)
        #expect(abs(samples[2] - 1) < 0.0001)
        #expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test("Unity gain leaves samples untouched")
    func unityIsIdentity() {
        var samples: [Float] = [0.25, -0.5, 0.125]
        let before = samples
        samples.withUnsafeMutableBufferPointer {
            InputGain.apply(1, to: $0.baseAddress!, count: $0.count)
        }
        #expect(samples == before)
    }

    /// A high-pass overshoots on transients, so the capture path clamps again
    /// after filtering. Measured +6.9 dBFS on already-hot audio; left unclamped
    /// that wraps sign when it becomes Int16.
    @Test("Clamp bounds filter overshoot without touching what is in range")
    func clampsOvershoot() {
        var samples: [Float] = [2.2, -1.8, 0.5, -0.5, 1, -1]
        samples.withUnsafeMutableBufferPointer {
            InputGain.clamp($0.baseAddress!, count: $0.count)
        }
        #expect(samples == [1, -1, 0.5, -0.5, 1, -1])
    }

    @Test("Gain scales sub-full-scale samples exactly")
    func scales() {
        var samples: [Float] = [0.1, -0.2]
        samples.withUnsafeMutableBufferPointer {
            InputGain.apply(2, to: $0.baseAddress!, count: $0.count)
        }
        #expect(abs(samples[0] - 0.2) < 0.0001)
        #expect(abs(samples[1] + 0.4) < 0.0001)
    }

    // MARK: - Soft limiter

    @Test("The limiter leaves everything under the threshold alone")
    func limiterPassesQuietSamples() {
        for value: Float in [0, 0.1, -0.3, 0.5, -0.7, InputGain.limiterThreshold] {
            #expect(InputGain.softLimit(value) == value)
        }
    }

    @Test("The threshold is 3 dB under full scale")
    func limiterThreshold() {
        #expect(abs(InputGain.limiterThreshold - 0.708) < 0.001)
    }

    /// The defect this pins: the tap delivered a loudness-maximised mix at
    /// full scale, and every sample of it clipped again in the archive and in
    /// the Int16 copy for the model.
    @Test("Full scale and beyond never come out above full scale")
    func limiterKeepsPeaksOffTheCeiling() {
        // Full scale itself, the measured case, gets real headroom back.
        #expect(InputGain.softLimit(1) < 0.95)
        #expect(InputGain.softLimit(1) > 0.9)
        // Far past the ceiling the knee flattens onto 1.0 in Float, which is
        // the one value that is still safe: it converts to Int16 without a wrap.
        for value: Float in [0.9, 1, 1.5, 4, 100] {
            let out = InputGain.softLimit(value)
            #expect(out <= 1)
            #expect(out > InputGain.limiterThreshold)
            #expect(InputGain.softLimit(-value) == -out)
        }
    }

    @Test("The limiter keeps the order of levels")
    func limiterIsMonotonic() {
        let steps = stride(from: Float(0), through: 1.5, by: 0.05).map(InputGain.softLimit)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("The knee is continuous at the threshold")
    func limiterKneeIsContinuous() {
        let justOver = InputGain.limiterThreshold + 0.0001
        #expect(abs(InputGain.softLimit(justOver) - justOver) < 0.0001)
    }

    @Test("The buffer form limits every sample in place")
    func limiterOverABuffer() {
        var samples: [Float] = [0.5, 1.2, -1.2, 0]
        samples.withUnsafeMutableBufferPointer {
            InputGain.softLimit($0.baseAddress!, count: $0.count)
        }
        #expect(samples[0] == 0.5)
        #expect(samples[1] < 1 && samples[1] > InputGain.limiterThreshold)
        #expect(samples[2] == -samples[1])
        #expect(samples[3] == 0)
    }

    // MARK: - Meter scale

    @Test("The meter spans silence to full scale")
    func meterEnds() {
        #expect(InputGain.meterFraction(0) == 0)
        #expect(InputGain.meterFraction(1) == 1)
        #expect(InputGain.meterFraction(0.0001) == 0) // -80 dBFS, below the floor
    }

    /// The regression this pins: measured speech on the built-in mic peaks near
    /// -28 dBFS, which drew 4% of a linear bar and read as a dead microphone.
    @Test("Speech lands in the readable middle of the meter")
    func speechIsVisible() {
        let speech = InputGain.meterFraction(0.04) // ~-28 dBFS
        #expect(speech > 0.4)
        #expect(speech < 0.7)
    }

    @Test("The meter rises with level")
    func monotonic() {
        let steps: [Float] = [0.001, 0.01, 0.05, 0.2, 0.5, 1]
        let fractions = steps.map(InputGain.meterFraction)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Clipping is flagged only at full scale")
    func clipping() {
        #expect(InputGain.isClipping(1))
        #expect(!InputGain.isClipping(0.5))
    }
}
