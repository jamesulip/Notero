import Foundation
import TranscriberCore

/// What the sidebar row, the detail header and the empty transcript show
/// about the state of one recording.
///
/// Three views used to rebuild the same ladder, each with its own branches,
/// and the warning had two sources: one view read the stored one only, one
/// read stored-or-in-memory. This is the one ladder. The caller resolves the
/// inputs; every view reads the same answer.
nonisolated public struct RecordingDisplayStatus: Equatable, Sendable {

    /// The chip in the row and the header. Nil when the recording is complete
    /// and quiet.
    public struct Chip: Equatable, Sendable {
        public var status: TranscriptionStatus
        public var fraction: Double
        public var remaining: TimeInterval?
    }

    /// The one button beside the chip, when there is one.
    public enum Action: Equatable, Sendable {
        /// A job runs; the button stops it.
        case cancel
        /// The last job failed and the audio is here.
        case retry
        /// The last job was cancelled and the audio is here.
        case transcribe
        /// Complete; a second pass on another tier is possible.
        case transcribeAgain
    }

    /// What the transcript pane says when it has no rows.
    public struct EmptyState: Equatable, Sendable {
        public var title: String
        public var symbol: String
        public var detail: String
    }

    public var chip: Chip?
    /// The live session is on this recording and paused.
    public var isPaused: Bool
    /// A job or the live session is on this recording: no edits now.
    public var isBusy: Bool
    /// The note about imperfect work, from one source.
    public var warning: String?
    public var action: Action?
    public var emptyState: EmptyState

    /// - Parameters:
    ///   - status: the stored status of the recording.
    ///   - progress: the queue's progress on it, if a job is queued or runs.
    ///   - isLive: the live session is on this recording, in any phase.
    ///   - isPaused: that session is paused.
    ///   - warning: the stored warning, or the coordinator's when the row has
    ///     none yet. The caller resolves the two sources into one.
    ///   - hasAudio: the audio file exists.
    ///   - errorMessage: the stored error of a failed job.
    public static func make(
        status: TranscriptionStatus, progress: JobProgress?,
        isLive: Bool, isPaused: Bool, warning: String?,
        hasAudio: Bool, errorMessage: String?
    ) -> RecordingDisplayStatus {
        let cleanWarning = warning.flatMap { $0.isEmpty ? nil : $0 }

        if let progress {
            let detail: String
            if let remaining = progress.remaining {
                detail = "\(progress.status.label) · \(TimeFormat.remaining(seconds: remaining)) left"
            } else {
                detail = progress.status.label
            }
            return RecordingDisplayStatus(
                chip: Chip(status: progress.status, fraction: progress.fraction,
                           remaining: progress.remaining),
                isPaused: false, isBusy: true, warning: cleanWarning, action: .cancel,
                emptyState: EmptyState(title: "Work in progress", symbol: "text.alignleft",
                                       detail: detail)
            )
        }

        if isLive {
            // Live work never reaches the queue, so it has no progress entry;
            // the stored status is what there is.
            return RecordingDisplayStatus(
                chip: isPaused ? nil : Chip(status: status, fraction: 0, remaining: nil),
                isPaused: isPaused, isBusy: true, warning: cleanWarning, action: nil,
                emptyState: EmptyState(title: "Recording", symbol: "waveform",
                                       detail: "The transcript comes after you stop.")
            )
        }

        switch status {
        case .failed:
            // "Transcription failed" is wrong for a recording that never
            // captured anything -- nothing got as far as being transcribed.
            return RecordingDisplayStatus(
                chip: Chip(status: .failed, fraction: 0, remaining: nil),
                isPaused: false, isBusy: false, warning: cleanWarning,
                action: hasAudio ? .retry : nil,
                emptyState: EmptyState(
                    title: hasAudio ? "Transcription failed" : "The recording stopped early",
                    symbol: "exclamationmark.triangle",
                    detail: errorMessage ?? Self.noTranscriptDetail(hasAudio: hasAudio))
            )
        case .cancelled:
            return RecordingDisplayStatus(
                chip: Chip(status: .cancelled, fraction: 0, remaining: nil),
                isPaused: false, isBusy: false, warning: cleanWarning,
                action: hasAudio ? .transcribe : nil,
                emptyState: EmptyState(title: "Transcription cancelled", symbol: "xmark.circle",
                                       detail: Self.noTranscriptDetail(hasAudio: hasAudio))
            )
        default:
            // Pending with no job, or a stale busy status the queue does not
            // know: nothing runs. Complete is the common case.
            return RecordingDisplayStatus(
                chip: status.isBusy || status == .pending
                    ? Chip(status: status, fraction: 0, remaining: nil) : nil,
                isPaused: false, isBusy: false, warning: cleanWarning,
                action: hasAudio ? .transcribeAgain : nil,
                emptyState: EmptyState(title: "No transcript yet", symbol: "text.alignleft",
                                       detail: Self.noTranscriptDetail(hasAudio: hasAudio))
            )
        }
    }

    private static func noTranscriptDetail(hasAudio: Bool) -> String {
        hasAudio
            ? "The audio is on this Mac. It has no transcript yet."
            : "The app captured no audio, thus there is nothing to transcribe. "
              + "A file that you import becomes a new recording. You can delete this one."
    }
}
