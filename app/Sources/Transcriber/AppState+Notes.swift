import Foundation
import SwiftData
import TranscriberCore
import TranscriberEngine
import TranscriberFlow
import TranscriberStore

/// Automatic notes: a draft from the model on this Mac, reviewed before any
/// of it is written. The coordinator holds the draft; this is the glue to
/// the store and the settings.
extension AppState {

    /// The backend for automatic notes in this build, on this macOS. Nil on
    /// macOS 15, where the pane shows no button. Whether the model can run
    /// today is `notesAvailability()`.
    static let notesEngine: (any NotesGenerating)? = NotesEngines.systemModel()

    var canDraftNotes: Bool { Self.notesEngine != nil }

    func notesAvailability() async -> NotesAvailability {
        guard let engine = Self.notesEngine else { return .needsNewerMacOS }
        return await engine.availability()
    }

    /// Starts a draft from the latest transcript. The rows are read off the
    /// main actor, as the transcript view reads them, and handed to the
    /// coordinator as values.
    func draftNotes(for recording: StoredRecording) {
        guard let engine = Self.notesEngine, let transcript = recording.transcript,
              !notes.isBusy(recording.id) else { return }
        let id = recording.id
        let title = recording.title
        let transcriptId = transcript.id
        let speakers = (recording.speakers ?? [])
            .sorted { $0.colorIndex < $1.colorIndex }
            .map { SpeakerLabel(id: $0.speakerId, displayName: $0.displayName, speechMs: $0.speechMs) }
        let style = settings.notesStyle
        let reader = makeReader()
        Task {
            do {
                let segments = try await reader.segments(ofTranscript: transcriptId)
                notes.generate(id: id, title: title, segments: segments, speakers: speakers,
                               style: style, using: engine)
            } catch {
                alert = AppAlert(title: "The app could not read the transcript",
                                 message: error.localizedDescription)
            }
        }
    }

    /// Writes the part of the draft the user kept, and closes the review.
    func acceptNotes(_ items: [NotesDraft.Item], summary: String?, for recording: StoredRecording) {
        do {
            try RecordingStore.apply(items, summary: summary, to: recording, in: context)
        } catch {
            alert = AppAlert(title: "The app could not add the notes",
                             message: error.localizedDescription)
        }
        notes.dismiss(recording.id)
    }

    // MARK: - Drafting by itself

    /// A transcription job left the queue. Draft the notes if everything
    /// `AutoDraft` asks for is true.
    ///
    /// Availability is awaited first, so "Apple Intelligence is off" skips
    /// quietly here rather than posting a failure into the pane of every
    /// recording the user makes.
    func autoDraftNotes(for id: UUID) {
        guard settings.autoDraftNotes, let engine = Self.notesEngine else { return }
        Task {
            let ready = await engine.availability().isAvailable
            // The status and the rows are read from a context of their own.
            // The queue emits `.completed` and then `.finished`, and the
            // status is written by the writer actor on its own context; the
            // main context has not necessarily merged that by the time this
            // runs, and a stale read here skips the draft on every recording.
            let state = committedState(of: id)
            let decision = AutoDraft.decide(
                enabled: settings.autoDraftNotes,
                hasModel: ready,
                status: state.status,
                hasTranscript: state.hasTranscript,
                isRecording: isLiveBusy,
                hasDraft: notes.state(for: id) != nil
            )
            guard decision.isDraft, let recording = recording(id) else { return }
            draftNotes(for: recording)
        }
    }

    /// The recording's status and whether it has any transcript rows, read
    /// from a fresh context so the values are the ones on disk.
    private func committedState(of id: UUID) -> (status: TranscriptionStatus, hasTranscript: Bool) {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return (.failed, false) }
        let hasRows = row.transcript.map { transcript in
            ((try? TranscriptReader.segmentRows(ofTranscript: transcript.id, in: context)) ?? []).isEmpty == false
        } ?? false
        return (row.status, hasRows)
    }

    /// Stops any draft when a recording starts.
    ///
    /// The decision above keeps a draft from starting during a recording. This
    /// is the other order: a draft already running when the user hits Record.
    /// The live decoder needs the chip more, and a draft is cheap to repeat.
    func stopNotesForRecording() {
        for (id, state) in notes.states {
            if case .running = state { notes.cancel(id) }
        }
    }

    /// What the review sheet and the settings call the backend.
    static func notesModelLabel(_ modelId: String) -> String {
        modelId == "apple-foundation-model" ? "the Apple Intelligence model" : modelId
    }
}
