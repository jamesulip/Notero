import Foundation
import TranscriberCore
import WhisperKit

/// Owns the three model-backed engines and decides who gets memory.
///
/// On a 16 GB machine the models are the budget: large-v3-turbo is ~1.6 GB
/// resident, the diarizer pair another ~200 MB, and macOS starts compressing
/// well before the ceiling. So there is exactly one of each, they are shared
/// between the live path and the background queue, and the diarizer is released
/// the moment a job stops needing it.
public actor EngineHost {

    public let modelsDirectory: URL
    private let asr: WhisperEngine
    private let vad: VADEngine
    private let diarizer: SpeakerEngine

    /// True while a recording is in progress. The queue refuses to start work
    /// during one: a background decode competing for the ANE is what turns a
    /// live hop from 0.9 s into 3 s, and dropped hops are dropped words.
    public private(set) var isLiveActive = false

    public init(modelsDirectory: URL, preferNeuralVAD: Bool = true) {
        self.modelsDirectory = modelsDirectory
        self.asr = WhisperEngine(modelsDirectory: modelsDirectory)
        self.vad = VADEngine(modelsDirectory: modelsDirectory, preferNeural: preferNeuralVAD)
        self.diarizer = SpeakerEngine(modelsDirectory: modelsDirectory)
    }

    // MARK: - Speech recognition

    public var loadedModel: String? { get async { await asr.loadedModel } }

    public func loadModel(_ model: String, progress: ProgressReport? = nil) async throws {
        try await asr.load(model: model, progress: progress)
    }

    public func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        try await asr.transcribe(request)
    }

    public func unloadModel() async {
        await asr.unload()
    }

    // MARK: - Model files

    /// Fetches a model's weights without loading them, so a download can be
    /// started from Settings ahead of the recording that needs it rather than
    /// discovered at the moment the recording is supposed to begin.
    public func downloadModel(_ id: String,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: id, downloadBase: modelsDirectory) { report in
            progress(report.fractionCompleted)
        }
    }

    /// Deletes a model's weights. A loaded copy is unloaded first: the files
    /// under it are gone either way, and a later reload would re-download.
    public func removeModel(_ id: String) async throws {
        if await asr.loadedModel == id { await asr.unload() }
        let directory = ModelCatalogue.directory(for: id, modelsDirectory: modelsDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Live

    public func prepareForLive(model: String, progress: ProgressReport? = nil) async throws {
        try await asr.load(model: model, progress: progress)
        // A VAD failure must not stop a recording; it only means a few more
        // silent windows get decoded.
        try? await vad.prepare(progress: progress)
    }

    public func beginLive() { isLiveActive = true }
    public func endLive() { isLiveActive = false }

    public var vadBackendName: String { get async { await vad.backend.rawValue } }

    public func pushVAD(_ samples: [Float]) async throws -> VoiceActivityReading {
        try await vad.push(samples)
    }

    public func clearVADSpeechCounter() async {
        await vad.clearSpeechCounter()
    }

    public func resetVAD() async {
        await vad.reset()
    }

    public func prepareVAD(progress: ProgressReport? = nil) async throws {
        try await vad.prepare(progress: progress)
    }

    public func speechRegions(in samples: [Float]) async throws -> [SpeechRegion] {
        try await vad.regions(in: samples)
    }

    public var voiceActivity: any VoiceActivityDetecting { vad }
    public var recognizer: any SpeechRecognizing { asr }

    // MARK: - Diarization

    public func prepareDiarizer(progress: ProgressReport? = nil) async throws {
        try await diarizer.prepare(progress: progress)
    }

    public func diarize(_ source: any PCMSource,
                        expectedSpeakers: Int? = nil,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws -> [SpeakerSpan] {
        try await diarizer.diarize(source, expectedSpeakers: expectedSpeakers, progress: progress)
    }

    /// Called at the end of every job. The diarizer is only needed in bursts,
    /// and holding its two models between recordings is 200 MB of nothing.
    public func releaseDiarizer() async {
        await diarizer.unload()
    }

    // MARK: - Memory

    public func footprintMB() -> Int { MemoryProbe.footprintMB() }

    /// Drops everything not currently in use, keeping the recognizer while a
    /// recording is live. Nothing calls this yet; it is the hook for an
    /// idle-memory pass.
    public func releaseAll() async {
        await diarizer.unload()
        if !isLiveActive { await asr.unload() }
    }
}
