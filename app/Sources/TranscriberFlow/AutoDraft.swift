import Foundation
import TranscriberCore

/// Whether a finished transcription should draft its notes by itself.
///
/// The rule that matters is the last one: **the notes model never runs while
/// a recording does.** A draft is two minutes of the GPU, and the live
/// decoder shares it -- a hop that arrives late is dropped, and a dropped hop
/// is missing words. The whole-file queue already refuses to start work
/// during a recording for the same reason; this is that rule for the notes.
///
/// A decision rather than a branch inside the app state, so a test can put
/// every combination to it without a model, a microphone or a window.
nonisolated public enum AutoDraft {

    public enum Decision: Equatable, Sendable {
        case draft
        case skip(Skip)

        public var isDraft: Bool { self == .draft }
    }

    /// Why a draft did not start. Each case is a real state the app reaches,
    /// and the reason is what the log and the tests name.
    public enum Skip: String, Equatable, Sendable {
        /// Settings › General › Automatic notes is off.
        case turnedOff
        /// No notes model on this macOS, or the chosen one is not downloaded.
        case noModel
        /// The job failed or was cancelled, so there is nothing to read.
        case notComplete
        /// Complete, but no rows: a recording that captured silence.
        case noTranscript
        /// A recording is running. The model waits.
        case recording
        /// A draft for this recording is already running or waiting to be read.
        case busy
    }

    /// - Parameters:
    ///   - enabled: Settings › General › Automatic notes › after a recording.
    ///   - hasModel: a notes backend exists and its weights are on this Mac.
    ///   - status: the recording's status now that the job has finished.
    ///   - hasTranscript: the recording has a transcript with rows.
    ///   - isRecording: the live session is capturing, paused included.
    ///   - hasDraft: the notes coordinator already holds a state for it.
    public static func decide(
        enabled: Bool,
        hasModel: Bool,
        status: TranscriptionStatus,
        hasTranscript: Bool,
        isRecording: Bool,
        hasDraft: Bool
    ) -> Decision {
        guard enabled else { return .skip(.turnedOff) }
        guard hasModel else { return .skip(.noModel) }
        guard status == .completed else { return .skip(.notComplete) }
        guard hasTranscript else { return .skip(.noTranscript) }
        // Checked after the cheap reasons so that the log says "off" rather
        // than "recording" for a user who never turned this on.
        guard !isRecording else { return .skip(.recording) }
        guard !hasDraft else { return .skip(.busy) }
        return .draft
    }
}
