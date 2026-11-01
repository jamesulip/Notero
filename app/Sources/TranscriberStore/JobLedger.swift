import Foundation
import TranscriberCore

/// Keeps track of what a job could not write, so the row can say so.
///
/// The app wrote every result of a job with `try?`. A transcript that failed
/// to save was dropped without a word, and the stage event that followed
/// marked the recording "Complete" (finding 16): a row that read as finished
/// with no text, or with the live rows only. Failures are recorded here
/// instead, and the final status of the job is decided from them.
///
/// Counted, not listed: forty failed batches are one sentence with the number
/// forty and the last reason, and not forty sentences.
@MainActor
public final class JobLedger {

    /// What the job was writing.
    public enum Kind: Hashable, Sendable {
        /// The finished transcript. Losing it is losing the job's result.
        case transcript
        /// A batch of rows saved while the job runs. They are replaced by the
        /// finished transcript, so they matter only if the job does not finish.
        case partialRows
        /// The speaker labels on a transcript that exists.
        case speakers
        /// One turn decoded again.
        case turn
        /// The stage, the length or the waveform of the recording.
        case status
    }

    private struct Entry {
        var count = 0
        var lastReason = ""
    }

    private var entries: [UUID: [Kind: Entry]] = [:]
    /// Why the queue said a job failed. The stage event that follows writes
    /// the status again, and without the reason it wrote an empty message over
    /// the one the failure event had just saved.
    private var failureMessages: [UUID: String] = [:]

    public init() {}

    // MARK: - Recording

    public func record(_ kind: Kind, _ error: any Error, for id: UUID) {
        var entry = entries[id]?[kind] ?? Entry()
        entry.count += 1
        entry.lastReason = error.localizedDescription
        entries[id, default: [:]][kind] = entry
    }

    /// Runs one write. A failure is recorded and answered with nil.
    @discardableResult
    public func attempt<T>(_ kind: Kind, for id: UUID,
                           _ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            record(kind, error, for: id)
            return nil
        }
    }

    /// The queue's own reason for a failed job.
    public func noteFailure(_ message: String, for id: UUID) {
        failureMessages[id] = message
    }

    /// Runs one write that returns nothing. True when it worked.
    public func succeeded(_ kind: Kind, for id: UUID,
                          _ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            return true
        } catch {
            record(kind, error, for: id)
            return false
        }
    }

    public func failed(_ kind: Kind, for id: UUID) -> Bool {
        (entries[id]?[kind]?.count ?? 0) > 0
    }

    /// A new job on the recording starts with a clean account.
    public func clear(_ id: UUID) {
        entries[id] = nil
        failureMessages[id] = nil
    }

    // MARK: - Deciding

    /// What a stage should be written as, given what failed so far.
    public struct Outcome: Equatable, Sendable {
        public var status: TranscriptionStatus
        public var errorMessage: String?
        /// For the row's warning, apart from the status.
        public var warning: String?
    }

    /// `.completed` becomes `.failed` when the transcript was lost. Every
    /// other failure leaves the status alone and adds a warning, because a
    /// transcript that saved is not made worse by a label that did not.
    public func outcome(of stage: TranscriptionStatus, for id: UUID) -> Outcome {
        guard stage.isTerminal else {
            return Outcome(status: stage, errorMessage: nil, warning: nil)
        }
        var notes: [String] = []
        let transcript = entries[id]?[.transcript]
        if let speakers = entries[id]?[.speakers] {
            notes.append("The speaker labels could not be saved (\(speakers.lastReason)). "
                         + "Use Identify Speakers Again.")
        }
        if let turn = entries[id]?[.turn] {
            notes.append("The turn decoded again could not be saved (\(turn.lastReason)), "
                         + "so the old text of that turn is still there.")
        }
        if let status = entries[id]?[.status] {
            notes.append("The app could not record all of this job's details "
                         + "(\(status.lastReason)). If this recording looks stuck, "
                         + "restart the app.")
        }
        if let partial = entries[id]?[.partialRows], stage != .completed {
            notes.append("\(Self.batches(partial.count)) of the text decoded before "
                         + "this stopped could not be saved (\(partial.lastReason)), so the "
                         + "transcript is shorter than what was decoded.")
        }
        let warning = notes.isEmpty ? nil : notes.joined(separator: " ")

        if stage == .completed, let transcript {
            return Outcome(
                status: .failed,
                errorMessage: "The transcript could not be saved (\(transcript.lastReason)). "
                    + "The audio is kept. Use Transcribe Again to try once more.",
                warning: warning)
        }
        // The reason the queue gave, so that the status write that follows
        // the failure event keeps it.
        let message = stage == .failed ? failureMessages[id] : nil
        return Outcome(status: stage, errorMessage: message, warning: warning)
    }

    private static func batches(_ count: Int) -> String {
        count == 1 ? "One batch" : "\(count) batches"
    }
}
