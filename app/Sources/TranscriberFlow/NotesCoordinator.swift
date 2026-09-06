import Foundation
import Observation
import TranscriberCore
import TranscriberEngine

/// One draft of notes per recording, from the request to the review.
///
/// The pane reads one value: the state for its recording. Running carries
/// the progress, ready carries the draft the review sheet shows, failed
/// carries the message. Nothing is written to the store here: the draft is
/// a proposal until the user accepts some of it, and that write is
/// `RecordingStore.apply`.
@MainActor
@Observable
public final class NotesCoordinator {

    public enum State: Equatable, Sendable {
        case running(NotesProgress)
        case ready(NotesDraft)
        case failed(String)
    }

    public private(set) var states: [UUID: State] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    // MARK: - Reads

    public func state(for id: UUID) -> State? { states[id] }

    public func isBusy(_ id: UUID) -> Bool {
        if case .running = states[id] { return true }
        return false
    }

    public func progress(for id: UUID) -> NotesProgress? {
        if case .running(let progress) = states[id] { return progress }
        return nil
    }

    public func draft(for id: UUID) -> NotesDraft? {
        if case .ready(let draft) = states[id] { return draft }
        return nil
    }

    public func failure(for id: UUID) -> String? {
        if case .failed(let message) = states[id] { return message }
        return nil
    }

    // MARK: - Commands

    /// Starts a draft. The transcript comes in as values, read by the caller
    /// off the main actor; the pipeline runs detached so the window never
    /// waits on the chunking, and each progress step hops back here.
    public func generate(id: UUID, title: String, segments: [Segment], speakers: [SpeakerLabel],
                         style: NotesStyle, using engine: any NotesGenerating,
                         maxCharacters: Int = NotesChunker.defaultMaxCharacters) {
        guard !isBusy(id) else { return }
        states[id] = .running(NotesProgress(stage: .reading, chunksDone: 0, chunkCount: 0))
        let report: @Sendable (NotesProgress) -> Void = { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in self.advance(id, to: progress) }
        }
        tasks[id] = Task.detached { [weak self] in
            let outcome: State?
            do {
                let draft = try await NotesPipeline.generate(
                    segments: segments, speakers: speakers, title: title, style: style,
                    using: engine, maxCharacters: maxCharacters, progress: report
                )
                outcome = .ready(draft)
            } catch is CancellationError {
                outcome = nil
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            guard let self else { return }
            await self.finish(id, with: outcome)
        }
    }

    private func advance(_ id: UUID, to progress: NotesProgress) {
        guard isBusy(id) else { return }
        states[id] = .running(progress)
    }

    private func finish(_ id: UUID, with outcome: State?) {
        // A cancel that landed while the pipeline was finishing wins.
        guard tasks[id] != nil else { return }
        tasks[id] = nil
        states[id] = outcome
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        states[id] = nil
    }

    /// Clears a finished or failed state, after the review sheet closes.
    public func dismiss(_ id: UUID) {
        guard !isBusy(id) else { return }
        states[id] = nil
    }
}
