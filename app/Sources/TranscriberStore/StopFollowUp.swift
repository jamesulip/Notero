import Foundation
import TranscriberCore

/// What has to run after a recording stops, and what its row says when the
/// app is closed before that can run.
///
/// The decision used to sit inline in `AppState.stopRecording`, where nothing
/// could test it. A quit has to stop a recording without starting the job
/// that follows, because the job would die with the process a moment later and
/// leave the row claiming a transcription that never ran.
public enum StopFollowUp: Equatable, Sendable {
    /// Decode the file. The recording has no live transcript, or has two
    /// lanes, which only the whole-file pass can tell apart.
    case wholeFile
    /// The live transcript is the transcript. Only the speakers are missing.
    case speakersOnly
    /// Nothing more to run.
    case finished

    public static func after(decodedLive: Bool, laneCount: Int, diarizes: Bool) -> StopFollowUp {
        // A two-lane recording always gets the whole-file pass, because the
        // live decoder reads the two lanes summed and cannot say which side
        // of the meeting a line came from.
        if !decodedLive || laneCount > 1 { return .wholeFile }
        return diarizes ? .speakersOnly : .finished
    }

    /// What the row says when the app closed first.
    public struct ClosedEarly: Equatable, Sendable {
        public var status: TranscriptionStatus
        public var errorMessage: String?
        public var warning: String?
    }

    /// Nil when there was nothing left to run.
    public var closedEarly: ClosedEarly? {
        switch self {
        case .wholeFile:
            return ClosedEarly(
                status: .failed,
                errorMessage: "Notero was closed while this was recording. The recording was "
                    + "stopped and saved at that moment, and it has not been transcribed yet. "
                    + "Use Transcribe Again to get the text.",
                warning: nil)
        case .speakersOnly:
            return ClosedEarly(
                status: .completed, errorMessage: nil,
                warning: "Notero was closed before the speakers were identified. The "
                    + "transcript is complete. Use Identify Speakers Again to label them.")
        case .finished:
            return nil
        }
    }
}
