import Foundation

/// How a waveform becomes a picture: the height of one bar, and how many bars
/// there are.
///
/// Neither is a drawing detail. Both were wrong in ways that made the view
/// misreport the audio, and both are worth testing on a machine with no window.

// MARK: - Bar height

/// How one amplitude becomes one bar height.
///
/// There are two waveforms in the app and they arrive on different scales, so
/// one shared curve cannot serve both.
///
/// The live meter is fed raw peaks against digital full scale. Nothing has
/// normalized them and nothing should: the point of watching it is to judge an
/// absolute level and set the gain against it. That is `.level`, and it is the
/// decibel curve in `InputGain`.
///
/// The stored envelope has already been divided by its loudest bucket, so its
/// peak is 1.0 by construction. Putting it through the meter curve as well
/// scales it twice, and the second pass is what flattened it: a bucket at 1% of
/// the loudest moment came out at a third of full height, and an hour of
/// far-field meeting drew as a solid slab with a wobbling top edge.
public enum WaveformScale: Sendable {

    /// Absolute level against full scale, on the decibel meter curve.
    case level

    /// A peak envelope whose loudest bucket is already 1.0.
    case envelope

    /// 0...1 bar height for one sample.
    public func fraction(_ amplitude: Float) -> Float {
        let magnitude = min(1, max(0, abs(amplitude)))
        guard magnitude > 0 else { return 0 }
        switch self {
        case .level:
            return InputGain.meterFraction(magnitude)
        case .envelope:
            // Square root -- amplitude to the 0.5. Gentle enough that the quiet
            // half of a room recording stays visible, steep enough that speech
            // still towers over it. Against the loudest moment in the file:
            // 50% draws at 0.71, 20% at 0.45, 5% at 0.22, 1% at 0.10. The
            // decibel curve puts those same four at 0.90, 0.77, 0.57 and 0.33,
            // which is why it read as a slab.
            return sqrt(magnitude)
        }
    }
}

// MARK: - Bar count

/// Fitting a stored envelope to the bars a view actually has room for.
public enum WaveformBars {

    /// Reduces -- or stretches -- an envelope to exactly `count` bars, keeping
    /// the loudest sample of each group.
    ///
    /// A mean here would be wrong twice over: these are already peaks, and the
    /// second voice cutting in, the transient the envelope exists to show, is
    /// exactly what averaging removes.
    ///
    /// Fitting at all is what was missing. The stored envelope is 600 buckets
    /// and the player is rarely 600 points wide, so the view drew 600
    /// overlapping one-point bars: no gaps, no bar shape, a filled area whose
    /// outline was whichever bucket happened to land last.
    ///
    /// An empty envelope returns a row of zeros rather than nothing, so a
    /// recording still being analysed shows a flat line to scrub along instead
    /// of a hole where the player should be.
    public static func fitted(_ samples: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: count) }
        guard samples.count != count else { return samples }

        var out = [Float](repeating: 0, count: count)
        for bar in 0..<count {
            let start = bar * samples.count / count
            let end = max(start + 1, (bar + 1) * samples.count / count)
            var peak: Float = 0
            for index in start..<min(end, samples.count) where samples[index] > peak {
                peak = samples[index]
            }
            out[bar] = peak
        }
        return out
    }

    /// The newest `count` samples, right-aligned, padded at the left with
    /// silence.
    ///
    /// This is the live meter, and the padding is the fix. Stretching whatever
    /// the buffer held across the full width meant the first bar of a session
    /// was as wide as the window and every bar narrowed as more arrived -- an
    /// animation, not a meter. Bars keep one width; the history scrolls left.
    public static func trailing(_ samples: [Float], in count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let tail = samples.suffix(count)
        let offset = count - tail.count
        for (index, value) in tail.enumerated() { out[offset + index] = value }
        return out
    }
}
