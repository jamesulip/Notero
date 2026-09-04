import Foundation

public enum Audio {
    public static let sampleRate = 16_000
    public static let bytesPerSample = 2

    public static func msToBytes(_ ms: Int) -> Int {
        ms * sampleRate * bytesPerSample / 1000
    }

    public static func bytesToMs(_ count: Int) -> Int {
        count * 1000 / (sampleRate * bytesPerSample)
    }

    public static func msToSamples(_ ms: Int) -> Int {
        max(0, ms) * sampleRate / 1000
    }

    public static func samplesToMs(_ count: Int) -> Int {
        count * 1000 / sampleRate
    }
}

/// Holds the trailing context of audio and tracks absolute session time.
///
/// The absolute timeline matters: token timestamps come back relative to the
/// window, but segments, exports and diarization all need positions relative to
/// the start of the session.
public final class RingBuffer {
    /// The active region: audio not yet committed that every decode re-reads.
    public let contextMs: Int
    /// Committed audio kept in front of the active region as acoustic context.
    ///
    /// Zero means the window starts exactly at the last commit, which is what
    /// it did before pre-roll existed and what a decoder starting cold sounds
    /// like. The live path asks for ~1.5 s; whoever consumes the window is
    /// responsible for not committing what lies in it twice.
    public let preRollMs: Int
    private var buffer = Data()
    private var discardedBytes = 0

    public init(contextMs: Int = 15_000, preRollMs: Int = 0) {
        self.contextMs = contextMs
        self.preRollMs = max(0, preRollMs)
    }

    /// Room for the pre-roll and a full active region together, so the
    /// context never has to be traded for the pre-roll.
    public var capacityBytes: Int { Audio.msToBytes(contextMs + preRollMs) }

    /// Audio received since the session began.
    public var totalMs: Int { Audio.bytesToMs(discardedBytes + buffer.count) }

    /// Absolute position of the first sample currently held.
    public var windowStartMs: Int { Audio.bytesToMs(discardedBytes) }

    public var durationMs: Int { Audio.bytesToMs(buffer.count) }

    public func push(_ pcm: Data) {
        buffer.append(pcm)
        let overflow = buffer.count - capacityBytes
        if overflow > 0 {
            buffer.removeFirst(overflow)
            discardedBytes += overflow
        }
    }

    /// Anchors the window to a commit, keeping `preRollMs` of audio before it.
    ///
    /// This is what makes LocalAgreement work. If the window slides freely,
    /// consecutive hypotheses begin at different points in the audio, their
    /// prefixes describe different words, and the agreed prefix is empty
    /// forever -- the commit rate collapses while the provisional tail grows
    /// without bound. `contextMs` still caps the buffer, so a long stretch
    /// without agreement degrades to a sliding window rather than growing.
    ///
    /// The pre-roll sits in front of `absoluteMs`, so `windowStartMs` is
    /// normally *earlier* than the commit. Callers that compare the two must
    /// treat that as the resting state, not as the window having slid.
    public func trim(to absoluteMs: Int) {
        let keepFrom = Swift.max(0, absoluteMs - preRollMs)
        let target = Audio.msToBytes(keepFrom) - discardedBytes
        guard target > 0 else { return }
        let drop = Swift.min(target, buffer.count)
        buffer.removeFirst(drop)
        discardedBytes += drop
    }

    /// The current context and its absolute start.
    public func window() -> (pcm: Data, startMs: Int) {
        (buffer, windowStartMs)
    }

    public func reset() {
        buffer.removeAll()
        discardedBytes = 0
    }
}
