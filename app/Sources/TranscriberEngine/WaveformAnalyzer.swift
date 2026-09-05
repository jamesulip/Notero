import Foundation
import TranscriberCore

/// Peak envelope for the waveform view.
///
/// Peak rather than RMS: RMS looks smooth and pretty and hides exactly what
/// someone scanning a recording is looking for -- the moment a second voice
/// cuts in. Peak keeps the transients.
public enum WaveformAnalyzer {

    /// How many buckets to draw. More than the pixel width of the view is waste.
    public static let defaultBuckets = 600

    public static func envelope(of source: any PCMSource,
                                buckets: Int = defaultBuckets) -> [Float] {
        guard source.sampleCount > 0, buckets > 0 else { return [] }
        let perBucket = max(1, source.sampleCount / buckets)
        var out: [Float] = []
        out.reserveCapacity(buckets)

        var cursor = 0
        while cursor < source.sampleCount, out.count < buckets {
            let end = min(cursor + perBucket, source.sampleCount)
            // Read in windows so a mapped two-hour file never materializes.
            let slice = source.floats(cursor..<end)
            var peak: Float = 0
            for sample in slice {
                let magnitude = abs(sample)
                if magnitude > peak { peak = magnitude }
            }
            out.append(peak)
            cursor = end
        }

        // Normalize so a quiet recording still fills the view. A recording of
        // pure silence would divide by zero, so it stays flat instead.
        let loudest = out.max() ?? 0
        guard loudest > 0.001 else { return out }
        return out.map { min(1, $0 / loudest) }
    }

    /// Live meter envelope: appends one bucket per call, dropping the oldest.
    ///
    /// One bucket is 100 ms, so the default holds a minute of history. The view
    /// draws the newest bars that fit its width at a fixed bar pitch and lets
    /// the rest scroll off, so the buffer has to be longer than the widest
    /// window rather than sized to any particular one.
    public static func appending(_ peak: Float, to envelope: [Float],
                                 limit: Int = 600) -> [Float] {
        var out = envelope
        out.append(min(1, max(0, peak)))
        if out.count > limit { out.removeFirst(out.count - limit) }
        return out
    }
}
