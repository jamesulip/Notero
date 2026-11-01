import Foundation

/// What the live decoder did, with wall-clock timings, for finding out where a
/// commit's latency and a dropped hop come from.
///
/// `LiveDecoder.trace` is nil unless something installs a sink, and the
/// decoder only reads a monotonic clock a few times per decode, so leaving it
/// off costs nothing measurable. Everything is on one clock: milliseconds since
/// the decoder was created (`wallMs`), so a decode's span can be laid beside a
/// VAD batch's and a commit's without converting. `audioMs` is the other
/// clock, the session timeline of the PCM received so far.
///
/// FINDINGS 11 said `inferMs` understates the wall cost of a decode because
/// audio conversion, actor hops and the main-actor ingest sit outside it. A
/// `DecodeSpan` is that statement made measurable: each of those phases has its
/// own field. FINDINGS 26 is what it showed: all of them together are about a
/// millisecond; the time is in the model and in waiting for agreement.
public enum LiveTraceEvent: Sendable {
    case decode(DecodeSpan)
    case dropped(DroppedHop)
    /// A hop that found the room silent and ran no inference.
    case skippedSilent(wallMs: Double, audioMs: Int)
    case vad(VADSpan)
    case commit(CommitSpan)
    /// An utterance closed (`speechEndMs` is where the VAD heard it end).
    case boundary(wallMs: Double, audioMs: Int, speechEndMs: Int)
    /// A finalization was requested and then not carried out because speech resumed.
    case abandoned(wallMs: Double, audioMs: Int)
}

public struct DecodeSpan: Sendable, Codable, Equatable {
    /// "hop", "final" or "finish" (the extra look at the tail when a session ends).
    public var kind: String
    /// Wall time the decode was requested, i.e. when the hop (or the VAD) fired.
    public var requestedWallMs: Double
    public var audioAtRequestMs: Int
    public var windowStartMs: Int
    public var windowEndMs: Int
    /// Length of the audio handed to the model.
    public var windowMs: Int
    /// Request until the decode task's body began: main-actor queueing.
    public var scheduleDelayMs: Double
    /// `PCM.floats` on a detached task, including the hop onto it and back.
    public var convertMs: Double
    /// `await recognizer.transcribe`, as the decoder saw it. Includes the
    /// recognizer's actor hop, its own audio handling and the model.
    public var recognizerMs: Double
    /// The model-reported inference time. Always below `recognizerMs`.
    public var inferMs: Int
    /// Recognizer returned until the decode's work on the main actor was done:
    /// the hop back onto the main actor, window filters, agreement, delivery.
    public var postMs: Double
    /// Request until the decode slot was free again.
    public var totalMs: Double
    public var tokens: Int
    /// Tokens this decode committed through agreement (forced and boundary
    /// commits are `CommitSpan`s of their own).
    public var committed: Int
    public var failed: Bool

    public var completedWallMs: Double { requestedWallMs + totalMs }
}

public struct DroppedHop: Sendable, Codable, Equatable {
    public var wallMs: Double
    public var audioMs: Int
    /// What was running when the hop had to be dropped, and for how long.
    public var inFlightKind: String
    public var inFlightForMs: Double
}

/// One batch through the voice-activity detector.
public struct VADSpan: Sendable, Codable, Equatable {
    /// When the batch left the ingest path for the detector.
    public var handoffWallMs: Double
    /// Audio in the batch. More than one VAD chunk (256 ms) means the detector
    /// was still busy with the previous batch and audio queued behind it.
    public var batchMs: Int
    public var audioThroughMs: Int
    public var convertMs: Double
    public var pushMs: Double
    /// Hand-off until the reading was applied: how stale the VAD's view of the
    /// room is, and so how late a boundary can be requested.
    public var lagMs: Double
    public var trailingSilenceMs: Int
    public var speechMs: Int
    public var failed: Bool
}

public enum CommitReason: String, Sendable, Codable {
    /// Two passes agreed.
    case agreed
    /// The window was about to slide past it.
    case forced
    /// The tail committed at a confirmed utterance boundary.
    case boundaryTail
    /// The remainder at the end of the session.
    case finish
}

public struct CommitSpan: Sendable, Codable, Equatable {
    public var wallMs: Double
    public var audioMs: Int
    public var reason: CommitReason
    public var words: Int
    public var firstEndMs: Int
    public var lastEndMs: Int
}
