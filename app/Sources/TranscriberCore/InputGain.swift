import Foundation

/// Microphone input gain, and the decibel scale the meter is drawn on.
///
/// Two separate problems live here, and they are easy to conflate.
///
/// *Gain* is a real change to the samples: the built-in mic on a laptop lands
/// speech around -28 dBFS peak at arm's length, which is 15-20 dB under where
/// it wants to be. Boosting is not cosmetic -- it is the difference between a
/// recording that survives being listened to a year later and one that does not.
///
/// *The meter scale* is purely how that signal is drawn. Loudness is
/// logarithmic, so a bar whose height is linear amplitude spends its whole life
/// in the bottom eighth: speech at -28 dBFS draws 4% of a linear bar and reads
/// as a dead microphone. Every meter worth trusting is dB-scaled, which is why
/// `meterFraction` exists rather than the view multiplying by height directly.
///
/// Keeping both here, in the layer with no AV and no UI, is what lets the
/// clipping and round-trip behaviour be tested on a machine with no microphone.
public enum InputGain {

    /// Bounds for the user-facing slider. -12 dB trims a hot interface; +30 dB
    /// covers a quiet built-in mic at conversational distance. Beyond +30 the
    /// noise floor rises faster than the speech does and nothing is gained.
    public static let minDb: Float = -12
    public static let maxDb: Float = 30
    public static let defaultDb: Float = 0

    /// Amplitude multiplier for a gain in decibels. 0 dB is exactly 1.0, so the
    /// default path multiplies by one rather than by 0.9999.
    public static func linear(fromDb db: Float) -> Float {
        db == 0 ? 1 : pow(10, clampDb(db) / 20)
    }

    public static func db(fromLinear linear: Float) -> Float {
        linear <= 0 ? minDb : clampDb(20 * log10(linear))
    }

    public static func clampDb(_ db: Float) -> Float {
        min(maxDb, max(minDb, db))
    }

    // MARK: - Meter scale

    /// Bottom of the meter. Below this is silence as far as the display is
    /// concerned -- room tone on a quiet mic sits near -60 dBFS.
    public static let floorDb: Float = -60

    /// Where a linear 0...1 amplitude sits on the dB meter, as 0...1.
    ///
    /// Speech at -28 dBFS lands at 0.53 here against 0.04 on a linear scale,
    /// which is the entire reason the meter looked broken.
    public static func meterFraction(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return 0 }
        let db = 20 * log10(min(1, amplitude))
        guard db > floorDb else { return 0 }
        return min(1, db / floorDb * -1 + 1)
    }

    /// True when the signal is at or past digital full scale, where boosting
    /// further only flattens the peaks.
    public static func isClipping(_ amplitude: Float) -> Bool {
        amplitude >= 0.99
    }

    // MARK: - Application

    /// Applies gain to one buffer of float samples in place, clamped to ±1.
    ///
    /// The clamp is not optional. These samples are converted to Int16 for
    /// inference, and a float above 1.0 does not saturate on the way down -- it
    /// wraps, turning the loudest part of a word into full-scale noise in the
    /// opposite direction. Clipping a peak is survivable; wrapping it is not.
    public static func apply(_ gain: Float, to samples: UnsafeMutablePointer<Float>,
                             count: Int) {
        guard gain != 1 else { return }
        for index in 0..<count {
            samples[index] = min(1, max(-1, samples[index] * gain))
        }
    }

    // MARK: - Limiting

    /// Where the soft limiter starts to bend: 3 dB under full scale, which is
    /// about 0.708 as an amplitude.
    public static let limiterThresholdDb: Float = -3
    public static let limiterThreshold: Float = pow(10, limiterThresholdDb / 20)

    /// One sample through the soft limiter: unchanged up to the threshold,
    /// then bent along a tanh knee that flattens toward full scale. A sample
    /// at full scale comes out about 0.6 dB under it, and nothing comes out
    /// above it, however far past the ceiling the input was.
    ///
    /// For the lane that arrives with no headroom. A process tap hands over
    /// the system mix at the level the other application chose, and a call
    /// application's mix is loudness-maximised: measured on a real capture,
    /// 0.35% of the remote lane's samples sat at or past full scale, and each
    /// one clipped again in the AAC archive and in the Int16 copy the model
    /// reads. A gain slider is the wrong tool -- there is no microphone
    /// placement to compensate for -- and a hard clamp keeps the distortion.
    ///
    /// Memoryless on purpose. A limiter with attack and release has state to
    /// carry between buffers, constants to tune and a sound of its own; this
    /// one only has to keep the peaks off the ceiling, and a source that
    /// stays under the threshold passes through untouched. The knee is
    /// continuous in value and in slope at the threshold, so nothing marks
    /// the point where it starts.
    public static func softLimit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterThreshold else { return sample }
        let knee = 1 - limiterThreshold
        let limited = limiterThreshold + knee * tanh((magnitude - limiterThreshold) / knee)
        return sample < 0 ? -limited : limited
    }

    /// `softLimit` over one buffer, in place.
    public static func softLimit(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        for index in 0..<count {
            samples[index] = softLimit(samples[index])
        }
    }

    /// Clamps to ±1 without scaling.
    ///
    /// Needed after filtering, which is not level-preserving the way gain is.
    /// A high-pass overshoots on sharp transitions -- measured at +6.9 dBFS on
    /// audio that was already touching full scale -- so a signal that was in
    /// range going in can come out above it. Anything still above ±1 when it
    /// reaches the Int16 conversion risks wrapping to the opposite sign, which
    /// turns a loud syllable into noise.
    public static func clamp(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        for index in 0..<count {
            samples[index] = min(1, max(-1, samples[index]))
        }
    }
}
