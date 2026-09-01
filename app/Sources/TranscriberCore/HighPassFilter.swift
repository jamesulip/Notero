import Foundation

/// Fourth-order Butterworth high-pass, as a cascade of two biquads.
///
/// Room recordings are dominated by energy that carries no words. Measured on a
/// laptop sitting on a meeting table: 31% of the captured energy was below
/// 120 Hz and another 54% between 120 and 300 Hz -- desk knocks, typing and
/// chassis vibration conducted through the case -- leaving 14% for the 300 Hz
/// to 3.4 kHz band that actually distinguishes one word from another. Removing
/// the bottom does not merely tidy the spectrum; it stops the rumble consuming
/// the headroom that gain is trying to give the voices.
///
/// Fourth order rather than second: a 12 dB/octave slope from 250 Hz still
/// leaves substantial energy at 125 Hz, and it is the octave below the corner
/// that holds the worst of it. Butterworth because its passband is flat --
/// ripple here would colour the formants the model reads.
///
/// This is deliberately *not* a general EQ. Boosting the high end to compensate
/// for a distant talker was measured to make transcription worse, not better:
/// where speech is already below the noise floor, lifting the band lifts the
/// noise with it and pushes the model into repetition loops. Subtracting what
/// is known to be noise is safe; amplifying what might be signal is not.
public final class HighPassFilter: @unchecked Sendable {

    /// Corner frequency for room capture.
    ///
    /// Chosen by measurement rather than convention. Against the same meeting
    /// audio, transcription recovered 48 words unfiltered, 60 with a 100 Hz
    /// corner, 114 at 250 Hz, and fell to 28 at 400 Hz -- by 400 the filter is
    /// eating the first formant of the vowels it is meant to protect. The usual
    /// broadcast 80-100 Hz cut is tuned for a close mic that never had this
    /// problem in the first place.
    public static let roomCornerHz: Float = 250

    private var stages: [Biquad]

    public init(cornerHz: Float, sampleRate: Double) {
        // Butterworth pole Qs for a fourth-order cascade.
        stages = [0.541_196, 1.306_563].map {
            Biquad(cornerHz: cornerHz, sampleRate: sampleRate, q: $0)
        }
    }

    /// Clears the delay line. Required between recordings: state carried over
    /// from the previous session decays as an audible thump into the new one.
    public func reset() {
        for stage in stages { stage.reset() }
    }

    /// Filters in place. Cheap enough for the audio thread: two biquads is
    /// eight multiply-adds per sample.
    public func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        for stage in stages { stage.process(samples, count: count) }
    }

    public func process(_ samples: inout [Float]) {
        samples.withUnsafeMutableBufferPointer {
            guard let base = $0.baseAddress else { return }
            process(base, count: $0.count)
        }
    }

    /// One-shot over a copy, for callers with no state to keep.
    public static func filtered(_ samples: [Float], cornerHz: Float,
                                sampleRate: Double) -> [Float] {
        var out = samples
        HighPassFilter(cornerHz: cornerHz, sampleRate: sampleRate).process(&out)
        return out
    }

    /// Transposed direct form II: fewer rounding artefacts than direct form I
    /// at the low corner frequencies used here, where the poles sit close to
    /// the unit circle and coefficient error turns into drift.
    private final class Biquad {
        private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        private var z1: Float = 0, z2: Float = 0

        init(cornerHz: Float, sampleRate: Double, q: Float) {
            // Guard the degenerate cases rather than emitting NaNs into audio:
            // a corner at or above Nyquist has no meaningful response.
            let nyquist = Float(sampleRate) / 2
            let fc = min(max(cornerHz, 1), nyquist * 0.99)
            let w0 = 2 * Float.pi * fc / Float(sampleRate)
            let cosw = cos(w0)
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            b0 = ((1 + cosw) / 2) / a0
            b1 = (-(1 + cosw)) / a0
            b2 = ((1 + cosw) / 2) / a0
            a1 = (-2 * cosw) / a0
            a2 = (1 - alpha) / a0
        }

        func reset() { z1 = 0; z2 = 0 }

        func process(_ x: UnsafeMutablePointer<Float>, count: Int) {
            var s1 = z1, s2 = z2
            for index in 0..<count {
                let input = x[index]
                let output = b0 * input + s1
                s1 = b1 * input - a1 * output + s2
                s2 = b2 * input - a2 * output
                x[index] = output
            }
            z1 = s1
            z2 = s2
        }
    }
}

/// A `PCMSource` that high-passes on the way out.
///
/// Wrapping the source rather than filtering the file keeps the archive on disk
/// untouched: room mode changes what the model is given, never what the user
/// can go back and listen to.
///
/// The filter is stateful but `floats(_:)` is random access, so each read warms
/// the filter on the samples immediately preceding the range and discards them.
/// Without that, every window would begin with the filter's step response --
/// a transient at exactly the seams where words are most likely to be cut.
public struct HighPassPCM: PCMSource {
    public let base: any PCMSource
    public let cornerHz: Float
    public let sampleRate: Double

    /// Long enough for a 250 Hz fourth-order section to settle at 16 kHz, with
    /// room to spare at the lower corners.
    static let warmUpSamples = 2_048

    public init(_ base: any PCMSource, cornerHz: Float = HighPassFilter.roomCornerHz,
                sampleRate: Double = Double(Audio.sampleRate)) {
        self.base = base
        self.cornerHz = cornerHz
        self.sampleRate = sampleRate
    }

    public var sampleCount: Int { base.sampleCount }

    public func floats(_ range: Range<Int>) -> [Float] {
        let low = Swift.max(0, Swift.min(range.lowerBound, sampleCount))
        let high = Swift.max(low, Swift.min(range.upperBound, sampleCount))
        guard high > low else { return [] }

        let warmStart = Swift.max(0, low - Self.warmUpSamples)
        var block = base.floats(warmStart..<high)
        let filter = HighPassFilter(cornerHz: cornerHz, sampleRate: sampleRate)
        filter.process(&block)
        return Array(block[(low - warmStart)...])
    }
}
