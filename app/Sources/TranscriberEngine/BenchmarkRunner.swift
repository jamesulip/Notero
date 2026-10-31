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

// MARK: - Run metrics for the `transcribe` CLI
//
// Four numbers that used to be conflated, now reported apart:
//
//   * whole-file RTF   wall time of a whole offline run over the audio length
//   * per-decode time  what one call to the recognizer costs (`DecodeTimingSummary`)
//   * commit latency   how far behind the audio a committed word trails
//   * memory           what this process's accounting says, at named stages
//
// They live here, in the engine module, because the CLI is an executable
// target a test cannot import. Everything below is a pure value type or a thin
// decorator, so it is testable with a fake recognizer and no model.

/// Order statistics, one definition for everything in this file.
///
/// Percentiles use linear interpolation between order statistics (Hyndman and
/// Fan type 7, the default of numpy and R), because `eval/bench_runs.py` uses
/// the same definition and the two have to agree when a number crosses over.
public enum RunStats {
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(p, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// One reading of this process's memory accounting, in megabytes.
///
/// **This is the footprint of one process, not the residency of a model.**
/// `phys_footprint` is dirty plus compressed pages plus some IOKit mappings.
/// File-backed pages that are merely mapped, which is how CoreML holds compiled
/// weights, do not count until they are dirtied, and memory that the Neural
/// Engine owns is accounted to the kernel and to other processes. A model can
/// be 1.6 GB on disk and in use, and a snapshot here can still say 300.
/// Compare snapshots across stages of one build; never read a smaller number
/// as "this build needs less memory for the model".
public struct MemorySnapshot: Codable, Sendable, Equatable {
    public var stage: String
    /// `phys_footprint` now. What Activity Monitor calls Memory.
    public var physFootprintMB: Int
    /// The highest `phys_footprint` this process has reached so far.
    public var lifetimePeakFootprintMB: Int
    /// Resident pages now, including clean file-backed pages that are mapped.
    public var residentMB: Int
    /// Anonymous (heap) pages now, resident or compressed.
    public var internalMB: Int
    /// File-backed and other external pages now.
    public var externalMB: Int
    public var compressedMB: Int

    public init(stage: String, physFootprintMB: Int, lifetimePeakFootprintMB: Int,
                residentMB: Int, internalMB: Int, externalMB: Int, compressedMB: Int) {
        self.stage = stage
        self.physFootprintMB = physFootprintMB
        self.lifetimePeakFootprintMB = lifetimePeakFootprintMB
        self.residentMB = residentMB
        self.internalMB = internalMB
        self.externalMB = externalMB
        self.compressedMB = compressedMB
    }

    public static func current(stage: String) -> MemorySnapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let mb: (UInt64) -> Int = { Int($0 / (1024 * 1024)) }
        guard result == KERN_SUCCESS else {
            return MemorySnapshot(stage: stage, physFootprintMB: 0, lifetimePeakFootprintMB: 0,
                                  residentMB: 0, internalMB: 0, externalMB: 0, compressedMB: 0)
        }
        return MemorySnapshot(
            stage: stage,
            physFootprintMB: mb(info.phys_footprint),
            lifetimePeakFootprintMB: mb(UInt64(max(0, info.ledger_phys_footprint_peak))),
            residentMB: mb(info.resident_size),
            internalMB: mb(info.internal),
            externalMB: mb(info.external),
            compressedMB: mb(info.compressed)
        )
    }
}

/// What one call to the recognizer cost, measured from outside it.
public struct DecodeSample: Sendable, Equatable {
    /// Audio handed to the model, including context and pre-roll.
    public var audioMs: Int
    /// The model's own report of its inference time.
    public var inferMs: Int
    /// Wall time around the whole call. The gap to `inferMs` is audio
    /// conversion, actor hops and anything else the model's clock leaves out.
    public var wallMs: Int

    public init(audioMs: Int, inferMs: Int, wallMs: Int) {
        self.audioMs = audioMs
        self.inferMs = inferMs
        self.wallMs = wallMs
    }
}

/// Per-decode cost over a run. **Not the whole-file RTF**: on the live path a
/// call decodes a 15 s window to advance the transcript by one hop, so a
/// per-decode RTF of 0.06 and a hop that costs 0.9 s describe the same run as
/// a whole-file RTF of 0.15 and a replay that takes 8 s.
public struct DecodeTimingSummary: Codable, Sendable, Equatable {
    public var calls: Int
    /// Sum of model-reported inference time over sum of audio decoded.
    public var inferRtf: Double
    /// Sum of wall time around each call over sum of audio decoded.
    public var wallRtf: Double
    public var meanInferMs: Double
    public var medianInferMs: Double
    public var p95InferMs: Double
    public var maxInferMs: Int
    public var meanWallMs: Double
    public var p95WallMs: Double
    public var maxWallMs: Int

    public init?(samples: [DecodeSample]) {
        guard !samples.isEmpty else { return nil }
        let audio = Double(max(1, samples.reduce(0) { $0 + $1.audioMs }))
        let infer = samples.map { Double($0.inferMs) }
        let wall = samples.map { Double($0.wallMs) }
        calls = samples.count
        inferRtf = infer.reduce(0, +) / audio
        wallRtf = wall.reduce(0, +) / audio
        meanInferMs = RunStats.mean(infer) ?? 0
        medianInferMs = RunStats.percentile(infer, 0.5) ?? 0
        p95InferMs = RunStats.percentile(infer, 0.95) ?? 0
        maxInferMs = samples.map(\.inferMs).max() ?? 0
        meanWallMs = RunStats.mean(wall) ?? 0
        p95WallMs = RunStats.percentile(wall, 0.95) ?? 0
        maxWallMs = samples.map(\.wallMs).max() ?? 0
    }
}

/// Records every decode that passes through it and forwards the call.
///
/// The live decoder reports only totals in `SessionStats`, which hide the slow
/// hop that causes a drop. Wrapping the recognizer from outside shows the
/// distribution without touching the decoder.
public actor TimedRecognizer: SpeechRecognizing {
    private let inner: any SpeechRecognizing
    public private(set) var samples: [DecodeSample] = []

    public init(wrapping inner: any SpeechRecognizing) {
        self.inner = inner
    }

    public var loadedModel: String? {
        get async { await inner.loadedModel }
    }

    public func load(model: String, progress: ProgressReport?) async throws {
        try await inner.load(model: model, progress: progress)
    }

    public func unload() async {
        await inner.unload()
    }

    public func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        let started = ContinuousClock.now
        let output = try await inner.transcribe(request)
        let elapsed = started.duration(to: .now)
        let wallMs = Int((Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15).rounded())
        samples.append(DecodeSample(audioMs: output.audioMs, inferMs: output.inferMs, wallMs: wallMs))
        return output
    }

    public var summary: DecodeTimingSummary? { DecodeTimingSummary(samples: samples) }
}

/// How far behind the audio a committed word trails, in milliseconds.
public struct CommitLatencySummary: Codable, Sendable, Equatable {
    public var words: Int
    public var minMs: Int
    public var medianMs: Double
    public var meanMs: Double
    public var p95Ms: Double
    public var maxMs: Int
    /// Words committed with an end time later than the audio fed so far. Zero
    /// in a healthy run; anything else is a timestamp past the audio.
    public var aheadOfAudio: Int
}

/// Commit latency: the clock at the moment a word was committed, minus the
/// time that word ended in the audio.
///
/// Which clock is the caller's choice and has to be stated with the number.
/// Audio fed so far measures the mechanism, how long the commit policy waits
/// for agreement and for a pause. Wall time since the replay began, under
/// `--realtime`, adds what the machine costs.
public struct CommitLatencyTracker: Sendable {
    private var latenciesMs: [Int] = []

    public init() {}

    public mutating func record(_ tokens: [Token], atMs clockMs: Int) {
        for token in tokens {
            latenciesMs.append(clockMs - token.endMs)
        }
    }

    public var summary: CommitLatencySummary? {
        guard !latenciesMs.isEmpty else { return nil }
        let values = latenciesMs.map(Double.init)
        return CommitLatencySummary(
            words: latenciesMs.count,
            minMs: latenciesMs.min() ?? 0,
            medianMs: RunStats.percentile(values, 0.5) ?? 0,
            meanMs: RunStats.mean(values) ?? 0,
            p95Ms: RunStats.percentile(values, 0.95) ?? 0,
            maxMs: latenciesMs.max() ?? 0,
            aheadOfAudio: latenciesMs.filter { $0 < 0 }.count
        )
    }
}
