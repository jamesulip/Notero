import Foundation
import TranscriberCore
import TranscriberEngine

/// What to do with a live session that just stopped, decided before any of
/// it is done.
///
/// The method that stopped a recording was 110 lines that decided and acted
/// in the same breath: the failure warning, the persister-or-writer choice,
/// the three-way follow-up, the notice merging and the short-take question,
/// each between awaited effects. None of the decisions ran without SwiftUI,
/// a microphone and a model. This value is the decisions; the method that
/// executes it is awaits only.
nonisolated public struct StopPlan: Equatable, Sendable {

    /// Where the live transcript, if any, goes.
    public enum TranscriptStep: Equatable, Sendable {
        /// The persister that wrote lines during the recording completes its
        /// revision with the final list.
        case completePersister
        /// No persister was open; store the final list as a fresh revision.
        case storeFresh
        /// Nothing was decoded live.
        case none
    }

    /// The job, if any, that follows the stop.
    public enum FollowUp: Equatable, Sendable {
        /// The whole-file pass: the transcript for a capture-only session, and
        /// the better transcript for a two-lane one, whose live decode ran on
        /// the lanes summed and cannot say which side a line came from.
        case fullTranscription
        /// The live transcript stands; identify the speakers over it.
        case diarizeOnly(DiarizationMode)
        /// Done. Drop the working copy unless Settings keeps it.
        case markCompleted(discardCache: Bool)
    }

    /// "Keep this recording?" for a take that stopped almost at once.
    public struct ShortTakeQuestion: Equatable, Sendable {
        public var durationMs: Int
        /// Nil when nothing was decoded live, so there is no count to give.
        public var words: Int?
    }

    /// The live decoder threw on some or every hop.
    public var liveFailureWarning: String?
    public var transcript: TranscriptStep
    public var followUp: FollowUp
    /// What changed under the recording: a replaced microphone, a moved
    /// default input. One string, in order.
    public var noticesWarning: String?
    public var shortTake: ShortTakeQuestion?

    /// - Parameters:
    ///   - result: what the session handed back.
    ///   - decodedLive: whether the session decoded while it recorded.
    ///   - hadPersister: whether committed lines were written during the
    ///     recording, so a revision is already open.
    ///   - diarizationMode: Settings › After you record.
    ///   - keepWorkingCopy: Settings › Storage.
    ///   - shortTakeMs: below this the take is asked about.
    public static func make(
        result: LiveSessionResult, decodedLive: Bool, hadPersister: Bool,
        diarizationMode: DiarizationMode, keepWorkingCopy: Bool, shortTakeMs: Int
    ) -> StopPlan {
        var warning: String?
        if decodedLive, result.stats.failedHops > 0 {
            let detail = result.stats.lastError.map { " Last error: \($0)" } ?? ""
            warning = result.stats.hops == 0
                ? "Live transcription failed for this entire recording "
                  + "(\(result.stats.failedHops) decode errors).\(detail) "
                  + "The audio was saved. Use Transcribe Again to recover it."
                : "\(result.stats.failedHops) decode(s) failed during this "
                  + "recording, so some words may be missing.\(detail)"
        }

        let transcript: TranscriptStep = decodedLive
            ? (hadPersister ? .completePersister : .storeFresh)
            : .none

        let followUp: FollowUp
        if !decodedLive || result.lanes.count > 1 {
            followUp = .fullTranscription
        } else if diarizationMode.performsDiarization {
            followUp = .diarizeOnly(diarizationMode)
        } else {
            followUp = .markCompleted(discardCache: !keepWorkingCopy)
        }

        let notices = result.notices.isEmpty
            ? nil
            : result.notices.map(\.message).joined(separator: " ")

        var shortTake: ShortTakeQuestion?
        if result.durationMs < shortTakeMs {
            shortTake = ShortTakeQuestion(
                durationMs: result.durationMs,
                words: decodedLive
                    ? result.segments.reduce(0) {
                        $0 + $1.displayText.split(whereSeparator: \.isWhitespace).count
                    }
                    : nil
            )
        }

        return StopPlan(liveFailureWarning: warning, transcript: transcript, followUp: followUp,
                        noticesWarning: notices, shortTake: shortTake)
    }
}
