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

    private let modelsDirectory: URL
    private var pipeline: WhisperKit?
    private var currentModel: String?
    public private(set) var loadMs: Int = 0

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public var loadedModel: String? { currentModel }
    public var isLoaded: Bool { pipeline != nil }

    // MARK: - Lifecycle

    public func load(model: String, progress: ProgressReport?) async throws {
        if pipeline != nil, currentModel == model { return }

        let option = ModelCatalogue.option(model)
        let label = option?.label ?? model
        let known = ModelCatalogue.isDownloaded(model, modelsDirectory: modelsDirectory)

        let previous = pipeline
        let previousName = currentModel
        pipeline = nil

        let started = Date()
        do {
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
            pipeline = try await WhisperKit(config)
            currentModel = model
            loadMs = Int(Date().timeIntervalSince(started) * 1000)
            progress?("Ready", 1)
        } catch {
            // Leave the working model in place rather than no model at all --
            // a failed switch should not take the session down with it.
            pipeline = previous
            currentModel = previousName
            throw error
        }
    }

    public func unload() {
        pipeline = nil
        currentModel = nil
        loadMs = 0
    }

    // MARK: - Inference

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
        // Attempt 0 is greedy. A retry warms the sampler: the failure being
        // retried is a window whose greedy first token looked improbable, and
        // repeating the same deterministic decode would fail identically.
        options.temperature = Float(request.decodeAttempt) * 0.2
        options.temperatureIncrementOnFallback = 0.2
        // Zero fallbacks is silent data loss: WhisperKit discards any window
        // whose first token looks improbable, and with nothing to fall back to
        // the window returns empty rather than being retried. Sliding windows
        // start mid-word every hop, so this fires often -- measured at 37% of
        // hops with no fallbacks, 16% with two.
        options.temperatureFallbackCount = 2 + request.decodeAttempt * 2

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
        for result in results {
            for segment in result.segments {
                // Whisper reports how sure it is that a window is silence.
                // Above this it is almost always about to invent a sentence.
                if segment.noSpeechProb > 0.85 { continue }
                logProbs.append(Double(segment.avgLogprob))

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
        return ASROutput(tokens: tokens, audioMs: audioMs, inferMs: inferMs,
                         detectedLanguage: results.first?.language ?? request.language,
                         confidence: confidence)
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
