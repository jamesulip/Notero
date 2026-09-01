import Foundation

/// Random access to 16 kHz mono audio without saying where it lives.
///
/// The diarizer and the benchmark both need to walk a whole recording. In the
/// app that recording is a memory-mapped file; in a test it is an array. This
/// is the only thing either of them needs to know.
public protocol PCMSource: Sendable {
    var sampleCount: Int { get }
    /// Normalized floats for `range`, clamped to what exists.
    func floats(_ range: Range<Int>) -> [Float]
}

public extension PCMSource {
    var durationMs: Int { Audio.samplesToMs(sampleCount) }

    func floats(msRange: Range<Int>) -> [Float] {
        floats(Audio.msToSamples(msRange.lowerBound)..<Audio.msToSamples(msRange.upperBound))
    }

    /// Walks the source in windows, so the caller never holds more than one.
    func windows(ofMs windowMs: Int) -> [Range<Int>] {
        let stride = max(1, Audio.msToSamples(windowMs))
        var out: [Range<Int>] = []
        var cursor = 0
        while cursor < sampleCount {
            out.append(cursor..<Swift.min(cursor + stride, sampleCount))
            cursor += stride
        }
        return out
    }
}

/// In-memory source. Used by tests, benchmarks and short clips.
public struct ArrayPCM: PCMSource {
    public let samples: [Float]

    public init(_ samples: [Float]) { self.samples = samples }

    public var sampleCount: Int { samples.count }

    public func floats(_ range: Range<Int>) -> [Float] {
        let low = Swift.max(0, Swift.min(range.lowerBound, samples.count))
        let high = Swift.max(low, Swift.min(range.upperBound, samples.count))
        return Array(samples[low..<high])
    }
}
