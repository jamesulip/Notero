import Foundation
import TranscriberCore
import WhisperKit

/// WhisperKit behind `SpeechRecognizing`.
///
/// The model id matters more than it looks. WhisperKit's `_turbo` suffix marks
/// a *compute variant*, not OpenAI's large-v3-turbo -- that one is published
/// under its September 2024 date stamp. `openai_whisper-large-v3_turbo` is full
/// 1.5B large-v3 with a decoder 5.3x heavier, which in a loop that re-decodes
/// the whole window every hop is the difference between real-time and not.
public actor WhisperEngine: SpeechRecognizing {

    /// Builds a ready WhisperKit for a model id, downloading it first if it is
    /// not on disk. A seam: a test can stand in for the 1.6 GB load.
    typealias PipelineFactory = @Sendable (
        _ model: String, _ modelsDirectory: URL, _ progress: ProgressReport?
    ) async throws -> sending WhisperKit

    private let modelsDirectory: URL
    private let makePipeline: PipelineFactory
    private var pipeline: WhisperKit?
    private var currentModel: String?
    public private(set) var loadMs: Int = 0

    /// The load in progress, and the callers waiting for it.
    private struct LoadInFlight {
        var model: String
        var waiters: [CheckedContinuation<Void, Error>] = []
    }
    private var inFlight: LoadInFlight?

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        self.makePipeline = Self.loadPipeline
    }

    init(modelsDirectory: URL, makePipeline: @escaping PipelineFactory) {
        self.modelsDirectory = modelsDirectory
        self.makePipeline = makePipeline
    }

    public var loadedModel: String? { currentModel }

    /// Callers parked behind the load in progress. For tests.
    var waitingLoads: Int { inFlight?.waiters.count ?? 0 }

    // MARK: - Lifecycle

    /// Loads `model`, once.
    ///
    /// The `pipeline` guard below only sees a *finished* load, and a load takes
    /// seconds to minutes (the first compile of a model took 284 s). The actor
    /// is re-entered at every `await`, so a second call that arrived while the
    /// first was still loading found `pipeline == nil` and started a second
    /// 1.6 GB load of the same model: the launch warm-up and a Dock-drop import
    /// can both ask within that window. A call for the model that is loading now
    /// waits for that load and shares its result; a call for a different model
    /// waits its turn, because two loads at once cannot both leave `pipeline`
    /// as the caller asked.
    public func load(model: String, progress: ProgressReport?) async throws {
        while true {
            if pipeline != nil, currentModel == model { return }
            guard let running = inFlight else { break }
            do {
                try await waitForLoad()
            } catch {
                // The failure belongs to whoever asked for that model.
                if running.model == model { throw error }
            }
            if running.model == model, pipeline != nil, currentModel == model {
                progress?("Ready", 1)
            }
        }

        inFlight = LoadInFlight(model: model)
        let previous = pipeline
        let previousName = currentModel
        pipeline = nil

        let started = Date()
        do {
            let loaded = try await makePipeline(model, modelsDirectory, progress)
            pipeline = loaded
            currentModel = model
            loadMs = Int(Date().timeIntervalSince(started) * 1000)
            progress?("Ready", 1)
            finishLoad(nil)
        } catch {
            // Leave the working model in place rather than no model at all --
            // a failed switch should not take the session down with it.
            pipeline = previous
            currentModel = previousName
            finishLoad(error)
            throw error
        }
    }

    private func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            // Runs on the actor before any suspension, so `inFlight` is still
            // the load that was seen a line ago.
            inFlight?.waiters.append(continuation)
        }
    }

    private func finishLoad(_ error: Error?) {
        let waiters = inFlight?.waiters ?? []
        inFlight = nil
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
    }

    private static func loadPipeline(model: String, modelsDirectory: URL,
                                     progress: ProgressReport?) async throws -> sending WhisperKit {
        let option = ModelCatalogue.option(model)
        let label = option?.label ?? model
        let known = ModelCatalogue.isDownloaded(model, modelsDirectory: modelsDirectory)

        if !known {
            // Fetched separately first: the combined download-and-load
            // path reports nothing until the weights are on disk, and a
            // 1.6 GB wait behind a spinner reads as a hang.
            let title = "Downloading \(label) (\(option?.sizeLabel ?? "~1.6 GB"))…"
            progress?(title, 0)
            _ = try await WhisperKit.download(variant: model, downloadBase: modelsDirectory) { report in
                progress?(title, report.fractionCompleted)
            }
        }
        progress?("Loading \(label)…", nil)
        let config = WhisperKitConfig(
            model: model,
            downloadBase: modelsDirectory,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        return try await WhisperKit(config)
    }

    public func unload() {
        pipeline = nil
        currentModel = nil
        loadMs = 0
    }

    // MARK: - Inference

    /// Where WhisperKit's temperature ladder starts and how long it is.
    struct Sampling: Equatable {
        var temperature: Float
        var fallbackCount: Int
    }

    /// The standard ladder, and the two halves of it that the offline pass runs
    /// separately.
    ///
    /// Attempt 0 is greedy. A retry warms the sampler: the failure being
    /// retried is a window whose greedy first token looked improbable, and
    /// repeating the same deterministic decode would fail identically.
    ///
    /// Zero fallbacks on a request that is allowed to fall back is silent data
    /// loss: WhisperKit discards any window whose first token looks improbable,
    /// and with nothing to fall back to the window returns empty rather than
    /// being retried. Sliding windows start mid-word every hop, so this fires
    /// often -- measured at 37% of hops with no fallbacks, 16% with two.
    /// `.greedyOnly` is for a caller that retries on its own.
    static func sampling(for request: ASRRequest) -> Sampling {
        let attempt = request.decodeAttempt
        switch request.sampling {
        case .standard:
            return Sampling(temperature: Float(attempt) * 0.2, fallbackCount: 2 + attempt * 2)
        case .greedyOnly:
            return Sampling(temperature: 0, fallbackCount: 0)
        case .resampleOnly:
            // The standard ladder at attempt 0 is temperatures 0, 0.2, 0.4;
            // this is 0.2, 0.4. Later attempts never started at 0.
            return attempt == 0
                ? Sampling(temperature: 0.2, fallbackCount: 1)
                : Sampling(temperature: Float(attempt) * 0.2, fallbackCount: 2 + attempt * 2)
        }
    }

    public func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        guard let pipeline else { throw EngineError.modelNotLoaded }
        let audioMs = request.samples.count * 1000 / Audio.sampleRate
        guard !request.samples.isEmpty else {
            return ASROutput(tokens: [], audioMs: 0, inferMs: 0,
                             detectedLanguage: request.language)
        }

        var options = DecodingOptions()
        options.verbose = false
        options.task = .transcribe
        options.skipSpecialTokens = true
        options.wordTimestamps = request.wordTimestamps
        options.withoutTimestamps = false
        options.chunkingStrategy = nil
        let sampling = Self.sampling(for: request)
        options.temperature = sampling.temperature
        options.temperatureIncrementOnFallback = 0.2
        options.temperatureFallbackCount = sampling.fallbackCount

        if request.language == "auto" {
            // Auto-detect resolves Taglish elsewhere and starts translating; on
            // a Taglish fixture it reported Indonesian, because it hears the
            // voice rather than reading the script.
            options.detectLanguage = true
            options.language = nil
        } else {
            options.detectLanguage = false
            options.language = request.language
        }
        if let prompt = request.prompt, !prompt.isEmpty,
           let promptTokens = pipeline.tokenizer?.encode(text: " " + prompt) {
            options.promptTokens = promptTokens
            options.usePrefillPrompt = true
        }

        let started = Date()
        let results = try await pipeline.transcribe(audioArray: request.samples,
                                                    decodeOptions: options)
        let inferMs = Int(Date().timeIntervalSince(started) * 1000)

        var tokens: [Token] = []
        var logProbs: [Double] = []
        // The gates are WhisperKit's own, read back from the segments of the
        // decode it returned. See `DecodeQuality`.
        var worstLogProb = Double.infinity
        var worstCompression = 0.0
        for result in results {
            for segment in result.segments {
                // Whisper reports how sure it is that a window is silence.
                // Above this it is almost always about to invent a sentence.
                if segment.noSpeechProb > 0.85 { continue }
                logProbs.append(Double(segment.avgLogprob))
                if !segment.text.trimmed.isEmpty {
                    worstLogProb = min(worstLogProb, Double(segment.avgLogprob))
                    worstCompression = max(worstCompression, Double(segment.compressionRatio))
                }

                if let words = segment.words, !words.isEmpty {
                    for word in words where !word.word.trimmed.isEmpty {
                        tokens.append(Token(
                            text: word.word,
                            startMs: Int(word.start * 1000),
                            endMs: Int(word.end * 1000),
                            confidence: Double(word.probability)
                        ))
                    }
                } else if !segment.text.trimmed.isEmpty {
                    // A segment with no text is a decode that produced only
                    // special tokens. Emitting it as one word spanning the whole
                    // window would look like a successful empty transcription.
                    tokens.append(Token(
                        text: segment.text,
                        startMs: Int(segment.start * 1000),
                        endMs: Int(segment.end * 1000),
                        confidence: Double(exp(segment.avgLogprob))
                    ))
                }
            }
        }

        let confidence = logProbs.isEmpty
            ? nil
            : min(1, max(0, exp(logProbs.reduce(0, +) / Double(logProbs.count))))
        var quality: DecodeQuality?
        if worstLogProb.isFinite {
            quality = DecodeQuality(
                avgLogProb: worstLogProb,
                compressionRatio: worstCompression,
                isRepetitive: options.compressionRatioThreshold.map { worstCompression > Double($0) } ?? false,
                isLowConfidence: options.logProbThreshold.map { worstLogProb < Double($0) } ?? false
            )
        }
        return ASROutput(tokens: tokens, audioMs: audioMs, inferMs: inferMs,
                         detectedLanguage: results.first?.language ?? request.language,
                         confidence: confidence, quality: quality)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Sample conversion

public enum PCM {
    /// Int16 little-endian bytes to normalized floats.
    public static func floats(from pcm: Data) -> [Float] {
        let count = pcm.count / 2
        guard count > 0 else { return [] }
        return pcm.withUnsafeBytes { raw -> [Float] in
            let source = raw.bindMemory(to: Int16.self)
            return (0..<count).map { Float(Int16(littleEndian: source[$0])) / 32768.0 }
        }
    }

    /// Normalized floats to Int16 little-endian bytes.
    public static func data(from samples: [Float]) -> Data {
        var out = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * 32767).littleEndian
            withUnsafeBytes(of: &value) { out.append(contentsOf: $0) }
        }
        return out
    }
}
