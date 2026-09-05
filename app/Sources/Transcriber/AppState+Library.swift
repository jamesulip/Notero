import Foundation
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore
import UniformTypeIdentifiers

/// The library: importing files, queueing work on a recording, and deleting.
extension AppState {

    // MARK: - Importing

    static let importableTypes: [UTType] = [
        .audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie,
    ]

    /// A file that looks like one already in the library: same size, same
    /// extension. Asked about rather than imported, since the library had
    /// several copies of one meeting under one title.
    struct DuplicateImport: Identifiable {
        let id = UUID()
        let url: URL
        let existingId: UUID
        let existingTitle: String
    }


    func importFiles(_ urls: [URL]) {
        for url in urls {
            if let existing = existingRecording(matching: url) {
                duplicateImports.append(DuplicateImport(
                    url: url, existingId: existing.id, existingTitle: existing.title))
            } else {
                importFile(url)
            }
        }
    }

    func resolveDuplicate(_ duplicate: DuplicateImport, importAnyway: Bool) {
        duplicateImports.removeAll { $0.id == duplicate.id }
        if importAnyway {
            importFile(duplicate.url)
        } else {
            route = .recording(duplicate.existingId)
        }
    }

    /// Byte-for-byte size is a strong signal for the same file and costs one
    /// stat per recording; hashing gigabytes of audio to be certain is not
    /// worth it for a question the user answers in a click.
    private func existingRecording(matching url: URL) -> StoredRecording? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0
        else { return nil }
        let ext = url.pathExtension.lowercased()
        let candidates = (try? context.fetch(FetchDescriptor<StoredRecording>())) ?? []
        return candidates.first { recording in
            guard let existing = recording.audioURL,
                  existing.pathExtension.lowercased() == ext,
                  let existingSize = try? existing.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return false }
            return existingSize == size
        }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let recording = try RecordingStore.create(
                kind: .recording,
                title: url.deletingPathExtension().lastPathComponent,
                in: context
            )
            // Copied into the library rather than referenced: a file the user
            // moves or deletes would otherwise take the recording's audio with
            // it, and there is no way to notice until playback fails.
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let name = Paths.newRecordingName(id: recording.id, ext: ext)
            let destination = Paths.recordingURL(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)

            recording.audioFileName = name
            recording.status = .pending
            try context.save()

            enqueueTranscription(recording, work: .full)
            route = .recording(recording.id)
        } catch {
            alert = AppAlert(title: "Could not import \(url.lastPathComponent)",
                             message: error.localizedDescription)
        }
    }

    func enqueueTranscription(_ recording: StoredRecording, work: TranscriptionJob.Work,
                              modelId: String? = nil,
                              diarizationMode: DiarizationMode? = nil) {
        guard let name = recording.audioFileName else { return }
        warnings[recording.id] = nil
        recording.warningMessage = nil
        let job = TranscriptionJob(
            id: recording.id,
            title: recording.title,
            sourceURL: Paths.recordingURL(name),
            cacheURL: AudioCache.url(for: recording.id, under: Paths.support),
            modelId: modelId ?? settings.offlineModelId,
            language: settings.language,
            prompt: settings.promptOrNil,
            diarizationMode: diarizationMode ?? settings.diarizationMode,
            work: work,
            discardCacheWhenDone: !settings.keepWorkingCopy,
            roomMode: settings.roomMode,
            expectedSpeakers: recording.expectedSpeakers,
            lanes: recording.lanes
        )
        progress[recording.id] = JobProgress(status: .pending, fraction: 0)
        queuedJobs[recording.id] = job
        Task { await queue.enqueue(job) }
    }

    /// Decode again, optionally on a named tier. Nil means the tier Settings
    /// holds -- but the menu always names one, because "again" with the same
    /// model is rarely what anyone re-transcribing a meeting wants.
    func retranscribe(_ recording: StoredRecording, tier: ModelTier? = nil) {
        enqueueTranscription(recording, work: .full,
                             modelId: tier.map { settings.modelId(for: $0) })
    }

    /// Speaker identification only, over the transcript that exists. Forced on
    /// regardless of the setting: asking for it is the setting.
    func rediarize(_ recording: StoredRecording) {
        enqueueTranscription(recording, work: .diarizeOnly,
                             diarizationMode: settings.diarizationMode.performsDiarization
                                ? settings.diarizationMode : .accurate)
    }

    func cancelJob(_ id: UUID) {
        Task { await queue.cancel(id) }
    }

    // MARK: - Deleting

    func delete(_ recording: StoredRecording) {
        let id = recording.id
        Task { await queue.cancel(id) }
        AudioCache.discard(id, under: Paths.support)
        if case .recording(id) = route { route = nil }
        if player.loadedURL == recording.audioURL { player.unload() }
        do {
            try RecordingStore.delete(recording, in: context)
        } catch {
            alert = AppAlert(title: "Could not delete", message: error.localizedDescription)
        }
    }

    func delete(_ recordings: [StoredRecording]) {
        for recording in recordings { delete(recording) }
    }
}
