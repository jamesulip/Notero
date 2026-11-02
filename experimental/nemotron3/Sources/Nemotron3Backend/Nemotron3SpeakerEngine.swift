import CoreML
import EngineSeams
import Foundation
@preconcurrency import FluidAudio
import TranscriberCore

/// EXPERIMENTAL speaker diarization on NVIDIA Nemotron 3 Diarization (FluidAudio's
/// Core ML port). Disabled: nothing in the app builds or selects it.
///
/// The model is an end-to-end streaming diarizer. It reads 16 kHz audio and writes,
/// every 10 ms, one activity probability for each of at most 8 speaker channels,
/// numbered in the order the speakers first talk. It has no speaker embeddings and
/// no clustering step, so:
///
/// - `expectedSpeakers` is not used. The model decides the count, at most 8.
/// - `mode` does not change the work: there is no second pass to skip.
/// - Two channels can be active in the same frame, so the spans can overlap.
///   `SegmentMerger.dominantSpeaker` already reads overlapping spans.
///
/// Offline-first: `prepare` only loads from `modelsDirectory` and never downloads.
/// `nemodiarbench --fetch` is the one explicit download step.
public actor Nemotron3SpeakerEngine: SpeakerDiarizing {

    /// The numbers this backend is run with. Fixed before any measurement; see
    /// `eval/diarization/plan-*.json`.
    public struct Settings: Sendable, Equatable {
        /// A FluidAudio preset name: `offline`, `fast128`, `fast32`, ...
        public var preset: String = "offline"
        /// A channel is active in a frame when its probability is above this.
        public var threshold: Float = 0.5
        /// Shorter activity runs are dropped (FluidAudio's default).
        public var minDurationSeconds: Float = 0.2
        /// Audio is handed to the model in pieces of this length, so the engine never
        /// holds the whole recording as one array.
        public var feedWindowMs: Int = 30_000
        public init() {}
        public static let standard = Settings()
    }

    /// The file names one preset needs in `modelsDirectory`.
    public static func requiredFiles(for config: Nemotron3Config) -> [String] {
        var files = [config.modelFileName, "learnable_sil_emb.bin"]
        if config.splitGraph { files.append("pre_encode_proj_t.bin") }
        return files
    }

    private let modelsDirectory: URL
    public let settings: Settings
    private var diarizer: Nemotron3Diarizer?

    /// - Parameter modelsDirectory: a flat folder with the preset's `.mlmodelc` and
    ///   `learnable_sil_emb.bin` side by side.
    public init(modelsDirectory: URL, settings: Settings = .standard) {
        self.modelsDirectory = modelsDirectory
        self.settings = settings
    }

    public var isAvailable: Bool { diarizer != nil }

    public func prepare(progress: ProgressReport?) async throws {
        guard diarizer == nil else { return }
        guard let config = Nemotron3Config.preset(named: settings.preset) else {
            throw EngineError.backendUnavailable("Unknown Nemotron 3 preset \(settings.preset)")
        }
        let missing = Self.requiredFiles(for: config).filter {
            !FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent($0).path)
        }
        guard missing.isEmpty else {
            throw EngineError.backendUnavailable(
                "Nemotron 3 models are not in \(modelsDirectory.path): missing \(missing.joined(separator: ", "))")
        }
        progress?("Loading Nemotron 3 speaker model…", nil)
        do {
            let models = try await Nemotron3Models.load(config: config, directory: modelsDirectory)
            diarizer = Nemotron3Diarizer(config: config, models: models)
            progress?("Speaker model ready", 1)
        } catch {
            throw EngineError.backendUnavailable(
                "Nemotron 3 speaker model did not load: \(error.localizedDescription)")
        }
    }

    public func unload() {
        diarizer = nil
    }

    public func diarize(_ source: any PCMSource,
                        speechRegions: [SpeechRegion]? = nil,
                        mode: DiarizationMode = .accurate,
                        expectedSpeakers: Int? = nil,
                        progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan] {
        guard let diarizer else { throw EngineError.modelNotLoaded }
        guard source.sampleCount > Audio.sampleRate else { return [] }
        guard mode.performsDiarization else { return [] }

        diarizer.reset()
        var probabilities: [Float] = []
        var frameCount = 0
        let speakers = diarizer.config.numSpeakers
        let windows = source.windows(ofMs: settings.feedWindowMs)
        for (index, range) in windows.enumerated() {
            try Task.checkCancellation()
            diarizer.appendAudio(source.floats(range))
            for chunk in try diarizer.processBufferedAudio() {
                probabilities.append(contentsOf: chunk.probabilities)
                frameCount += chunk.frameCount
            }
            progress?(Double(index + 1) / Double(windows.count + 1))
        }
        for chunk in try diarizer.finishStream() {
            probabilities.append(contentsOf: chunk.probabilities)
            frameCount += chunk.frameCount
        }
        progress?(1)

        let segments = Nemotron3Diarizer.segments(
            probabilities: probabilities, frameCount: frameCount, numSpeakers: speakers,
            threshold: settings.threshold, frameSeconds: diarizer.config.outputFrameSeconds,
            minDurationSeconds: settings.minDurationSeconds)
        return Self.spans(from: segments.map { ($0.speakerIndex, $0.startSeconds, $0.endSeconds) },
                          durationMs: source.durationMs)
    }

    /// Model segments to spans on the source timeline, clamped to the recording.
    /// Labels are `N1`...`N8` by model channel; the app renumbers them anyway.
    static func spans(from segments: [(speaker: Int, start: Float, end: Float)],
                      durationMs: Int) -> [SpeakerSpan] {
        segments.compactMap { segment in
            let start = max(0, Int((Double(segment.start) * 1000).rounded()))
            let end = min(durationMs, Int((Double(segment.end) * 1000).rounded()))
            guard end > start else { return nil }
            return SpeakerSpan(speakerId: "N\(segment.speaker + 1)", startMs: start, endMs: end)
        }
        .sorted { ($0.startMs, $0.endMs, $0.speakerId) < ($1.startMs, $1.endMs, $1.speakerId) }
    }
}
