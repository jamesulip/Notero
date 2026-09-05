import Foundation
import TranscriberCore

/// Measures the model tiers on this machine, on real audio.
///
/// The published Whisper numbers are for English on other hardware; neither
/// half of that transfers. What the app needs to know is narrower and
/// answerable locally: on *this* Mac, with *this* Taglish audio, which tier
/// still decodes faster than the audio arrives.
public actor BenchmarkRunner {

    public struct Progress: Sendable {
        public var tier: ModelTier
        public var stage: String
        public var fraction: Double
    }

    private let engines: EngineHost

    public init(engines: EngineHost) {
        self.engines = engines
    }

    /// - Parameter reference: ground-truth transcript, when there is one. WER
    ///   is only reported if it is supplied; a made-up number would be worse
    ///   than no number.
    public func run(
        source: any PCMSource,
        tiers: [ModelTier] = ModelTier.allCases,
        language: String = LanguageCatalogue.defaultLanguage,
        reference: String? = nil,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> BenchmarkReport {

        // Speech regions once, outside the timing. Every tier decodes exactly
        // the same windows, or the comparison measures VAD variance instead of
        // the models.
        try? await engines.prepareVAD(progress: nil)
        let vad = await engines.voiceActivity
        let regions = try await OfflinePipeline.speechRegions(in: source, using: vad)
        let windows = OfflinePipeline.windows(for: regions, durationMs: source.durationMs)
        let speechMs = windows.reduce(0) { $0 + $1.durationMs }

        var runs: [BenchmarkRun] = []
        for tier in tiers {
            try Task.checkCancellation()
            let model = tier.defaultModelId
            let option = ModelCatalogue.option(model)
            onProgress?(Progress(tier: tier, stage: "Loading \(option?.label ?? model)", fraction: 0))

            // Each tier starts from an unloaded state: a warm model would make
            // whichever tier ran second look free.
            await engines.unloadModel()
            let loadStarted = Date()
            do {
                try await engines.loadModel(model, progress: nil)
            } catch {
                runs.append(BenchmarkRun(modelId: model, tier: tier,
                                         label: option?.label ?? model,
                                         audioMs: speechMs, processMs: 0,
                                         language: language,
                                         failure: error.localizedDescription))
                continue
            }
            let loadMs = Int(Date().timeIntervalSince(loadStarted) * 1000)

            let asr = await engines.recognizer
            let baseline = MemoryProbe.footprintMB()
            var peak = baseline

            let started = Date()
            do {
                let decoded = try await OfflinePipeline.transcribe(
                    source: source, windows: windows, using: asr,
                    language: language, prompt: nil
                ) { fraction in
                    onProgress?(Progress(tier: tier, stage: "Transcribing", fraction: fraction))
                }
                let processMs = Int(Date().timeIntervalSince(started) * 1000)
                peak = max(peak, MemoryProbe.footprintMB())

                let segments = SegmentMerger.segments(from: decoded.tokens)
                let text = segments.map(\.displayText).joined(separator: " ")
                runs.append(BenchmarkRun(
                    modelId: model, tier: tier, label: option?.label ?? model,
                    audioMs: speechMs, processMs: processMs, loadMs: loadMs,
                    peakMemoryMB: peak, segmentCount: segments.count,
                    wordCount: text.split(separator: " ").count,
                    language: language,
                    wer: reference.map { WordErrorRate.score(reference: $0, hypothesis: text) }
                ))
            } catch {
                runs.append(BenchmarkRun(modelId: model, tier: tier,
                                         label: option?.label ?? model,
                                         audioMs: speechMs, processMs: 0, loadMs: loadMs,
                                         language: language,
                                         failure: error.localizedDescription))
            }
        }

        await engines.unloadModel()
        return BenchmarkReport(
            runs: runs,
            machine: MachineInfo.description,
            memoryGB: MemoryProbe.installedGB()
        )
    }
}

public enum MachineInfo {
    /// e.g. "Mac14,12 · 12 cores · macOS 26.6".
    public static var description: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                           as: UTF8.self)
        let cores = ProcessInfo.processInfo.processorCount
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(model) · \(cores) cores · macOS \(os.majorVersion).\(os.minorVersion)"
    }
}
