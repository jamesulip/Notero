import Foundation
import SwiftData
import Synchronization
import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore

/// Model weights on disk and in memory.
extension AppState {

    // MARK: - Model files

    func isModelDownloaded(_ id: String) -> Bool {
        ModelCatalogue.isDownloaded(id, modelsDirectory: Paths.models)
    }

    /// Fetches weights ahead of need. Progress is throttled to whole percents
    /// on the way to the main actor; WhisperKit reports per chunk.
    func downloadModel(_ id: String) {
        guard modelDownloads[id] == nil else { return }
        modelDownloads[id] = 0
        let last = Mutex(-1.0)
        Task {
            do {
                try await engines.downloadModel(id) { fraction in
                    let due = last.withLock { previous in
                        guard fraction - previous >= 0.01 || fraction >= 1 else { return false }
                        previous = fraction
                        return true
                    }
                    guard due else { return }
                    Task { @MainActor in self.modelDownloads[id] = fraction }
                }
            } catch {
                alert = AppAlert(title: "The download failed", message: error.localizedDescription)
            }
            modelDownloads[id] = nil
            modelsRevision += 1
        }
    }

    /// Deletes weights. Refused while a recording is in progress: the live
    /// session may be decoding on exactly this model.
    func removeModel(_ id: String) {
        guard !isLiveBusy else { return }
        Task {
            do {
                try await engines.removeModel(id)
            } catch {
                alert = AppAlert(title: "The app could not remove the model",
                                 message: error.localizedDescription)
            }
            modelsRevision += 1
        }
    }

    // MARK: - Memory

    /// Called when the app is idle. Releasing the diarizer between recordings
    /// is 200 MB back on a machine that is going to want it for the model.
    func releaseIdleModels() {
        guard !isRecording else { return }
        Task { await engines.releaseDiarizer() }
    }

    /// Loads the live model before anything asks for it, so hitting record does
    /// not sit on a cold load.
    ///
    /// Only for a model already on disk: warming one that is not would start a
    /// 1.6 GB download at launch that nobody asked for.
    func warmUpEngines() {
        guard warmup == nil, live.state == .idle else { return }
        // Only for the live path. With live transcription off, the model is
        // loaded when a whole-file job needs it, and the launch costs nothing.
        guard settings.liveTranscription else { return }
        guard ModelCatalogue.isDownloaded(settings.liveModelId,
                                          modelsDirectory: Paths.models) else { return }
        warmup = Task { [weak self] in
            guard let self else { return }
            live.configure(settings.liveConfiguration)
            await live.prepare(model: settings.liveModelId)
        }
    }
}
