import Foundation
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

    /// What the review sheet and the settings call the backend.
    static func notesModelLabel(_ modelId: String) -> String {
        modelId == "apple-foundation-model" ? "the Apple Intelligence model" : modelId
    }
}
