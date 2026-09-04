import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// One model measured over one clip.
public struct BenchmarkRun: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var modelId: String
    public var tier: ModelTier?
    public var label: String
    public var audioMs: Int
    public var processMs: Int
    public var loadMs: Int
    public var peakMemoryMB: Int
    public var segmentCount: Int
    public var wordCount: Int
    public var language: String
    public var startedAt: Date
    /// Word error rate against a reference, when one was supplied.
    public var wer: Double?
    public var failure: String?

    public init(id: UUID = UUID(), modelId: String, tier: ModelTier? = nil,
                label: String, audioMs: Int, processMs: Int, loadMs: Int = 0,
                peakMemoryMB: Int = 0, segmentCount: Int = 0, wordCount: Int = 0,
                language: String = "tl", startedAt: Date = Date(),
                wer: Double? = nil, failure: String? = nil) {
        self.id = id
        self.modelId = modelId
        self.tier = tier
        self.label = label
        self.audioMs = audioMs
        self.processMs = processMs
        self.loadMs = loadMs
        self.peakMemoryMB = peakMemoryMB
        self.segmentCount = segmentCount
        self.wordCount = wordCount
        self.language = language
        self.startedAt = startedAt
        self.wer = wer
        self.failure = failure
    }

    /// Processing time over audio duration. Below 1.0 is faster than real time.
    public var rtf: Double {
        audioMs > 0 ? Double(processMs) / Double(audioMs) : 0
    }

    /// How much faster than real time, for the label that humans read.
    public var speedup: Double { rtf > 0 ? 1 / rtf : 0 }

    /// Whether this run's decode speed leaves room for the live path.
    ///
    /// This is a proxy and not a measurement of the live path. `rtf` here is a
    /// whole-file decode of the VAD windows, thus it excludes the audio
    /// conversion, the actor hops and the main-actor ingest that finding 11
    /// measured. The 0.6 limit holds that margin in reserve.
    public var canKeepUpLive: Bool { rtf > 0 && rtf < 0.6 }
}

public struct BenchmarkReport: Sendable, Codable {
    public var runs: [BenchmarkRun]
    public var machine: String
    public var memoryGB: Int
    public var finishedAt: Date

    public init(runs: [BenchmarkRun], machine: String, memoryGB: Int,
                finishedAt: Date = Date()) {
        self.runs = runs
        self.machine = machine
        self.memoryGB = memoryGB
        self.finishedAt = finishedAt
    }

    /// The slowest tier that still keeps up with live audio and did not fail.
    ///
    /// Live transcription is the binding constraint: a model that cannot decode
    /// a window inside the hop interval does not merely run slow, it stops
    /// committing at all. Tiers that `ModelTier.suitableForLive` rejects are
    /// therefore never recommended, however fast they measured on this Mac.
    ///
    /// **This ranks by decode time and not by accuracy.** `wer` is nil unless
    /// the caller supplied a reference transcript, and the in-app benchmark has
    /// no reference to supply. "Slowest is most accurate" is an assumption from
    /// the model sizes; this project has not measured it. docs/MODELS.md says
    /// which tier promises are measured and which are inferred.
    public var recommendedTier: ModelTier? {
        let usable = runs.filter { $0.failure == nil && $0.rtf > 0 }
        guard !usable.isEmpty else { return nil }
        // A run with no tier cannot be recommended, thus it is dropped here
        // rather than being picked and then returning nil.
        let liveCapable = { (r: BenchmarkRun) in r.tier?.suitableForLive ?? false }
        let live = usable.filter { $0.canKeepUpLive && liveCapable($0) }
        // Among the models that keep up, prefer the slowest. It is the largest
        // one inside the budget, which is a proxy for accuracy and not a
        // measurement of it.
        let pick = live.max { $0.rtf < $1.rtf }
            ?? usable.filter(liveCapable).min { $0.rtf < $1.rtf }
            ?? usable.min { $0.rtf < $1.rtf }
        return pick?.tier
    }

    /// The tier that actually finished fastest on this machine and clip.
    ///
    /// Quantized models use less memory but are not necessarily lower latency
    /// on every Apple Silicon generation. Keeping this separate from
    /// `recommendedTier` lets the UI offer a speed-first choice without
    /// changing the existing accuracy-first recommendation.
    public var fastestTier: ModelTier? {
        runs
            .filter { $0.failure == nil && $0.processMs > 0 }
            .min { $0.processMs < $1.processMs }?
            .tier
    }
}

/// Resident memory of this process, in megabytes.
///
/// `phys_footprint` rather than `resident_size`: on Apple silicon the CoreML
/// weights are mapped, and resident size undercounts them badly enough to make
/// a 1.6 GB model look free.
public enum MemoryProbe {
    public static func footprintMB() -> Int {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / (1024 * 1024))
        #else
        return 0
        #endif
    }

    /// Physical memory installed, in gigabytes.
    public static func installedGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
}

/// Word error rate: edit distance over words, normalized by reference length.
public enum WordErrorRate {
    public static func score(reference: String, hypothesis: String) -> Double {
        let source = words(reference)
        let target = words(hypothesis)
        guard !source.isEmpty else { return target.isEmpty ? 0 : 1 }
        // An empty hypothesis is every reference word deleted -- and it is a
        // reachable case, not a degenerate one: a run whose every window was
        // refused produces exactly this (FINDINGS 9). Without the guard the
        // 1...0 range below traps, so the CLI would print its "N windows never
        // decoded" warning and then crash on the next statement.
        guard !target.isEmpty else { return 1 }

        // Two rows instead of a full matrix: a 60-minute transcript is tens of
        // thousands of words and the square would be gigabytes.
        var previous = Array(0...target.count)
        var current = [Int](repeating: 0, count: target.count + 1)
        for i in 1...source.count {
            current[0] = i
            for j in 1...target.count {
                let cost = source[i - 1] == target[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return Double(previous[target.count]) / Double(source.count)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
