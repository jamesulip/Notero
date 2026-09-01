import CoreML
import Foundation
@preconcurrency import FluidAudio
import TranscriberCore

/// Speaker diarization.
///
/// The plan named SpeakerKit. Argmax ships that as a licensed SDK rather than a
/// public Swift package, so the shipping backend is FluidAudio's pyannote
/// segmentation plus WeSpeaker embeddings -- also CoreML, also on the Neural
/// Engine, also entirely local. `SpeakerDiarizing` is the seam: dropping
/// SpeakerKit in later is one new conformance and one line in `EngineFactory`,
/// with no change above this file.
public actor SpeakerEngine: SpeakerDiarizing {

    private let modelsDirectory: URL
    private var manager: DiarizerManager?
    private var loadFailure: String?

    /// How much audio to hand the diarizer at a time.
    ///
    /// It already chunks internally at 10 s, but it takes the whole array by
    /// value. Ten minutes is 9.6M floats -- 38 MB -- and speaker identity
    /// survives across calls because the manager's speaker database is not
    /// reset between them.
    private static let windowMs = 10 * 60 * 1000

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public var isAvailable: Bool { manager?.isAvailable ?? false }

    public func prepare(progress: ProgressReport?) async throws {
        guard manager == nil else { return }
        progress?("Loading speaker models…", nil)
        do {
            let models = try await DiarizerModels.downloadIfNeeded(
                to: modelsDirectory.appendingPathComponent("Diarizer", isDirectory: true)
            )
            var config = DiarizerConfig.default
            // A meeting turn shorter than this is almost always a backchannel
            // ("oo", "sige") landing inside someone else's sentence, and
            // crediting it to a new speaker fragments the transcript.
            config.minSpeechDuration = 1.0
            config.minSilenceGap = 0.5
            let manager = DiarizerManager(config: config)
            manager.initialize(models: consume models)
            self.manager = manager
            loadFailure = nil
            progress?("Speaker models ready", 1)
        } catch {
            loadFailure = error.localizedDescription
            throw EngineError.backendUnavailable(
                "Speaker identification is unavailable: \(error.localizedDescription)")
        }
    }

    public func unload() {
        manager?.cleanup()
        manager = nil
    }

    public func diarize(_ source: any PCMSource,
                        progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan] {
        guard let manager else { throw EngineError.modelNotLoaded }
        guard source.sampleCount > Audio.sampleRate else { return [] }

        var spans: [SpeakerSpan] = []
        let windows = source.windows(ofMs: Self.windowMs)
        for (offset, window) in windows.enumerated() {
            try Task.checkCancellation()
            let samples = source.floats(window)
            guard samples.count > Audio.sampleRate else { continue }
            let startSeconds = Double(window.lowerBound) / Double(Audio.sampleRate)

            let result = try manager.performCompleteDiarization(
                samples, sampleRate: Audio.sampleRate, atTime: startSeconds
            )
            spans.append(contentsOf: result.segments.map {
                SpeakerSpan(
                    speakerId: $0.speakerId,
                    startMs: Int($0.startTimeSeconds * 1000),
                    endMs: Int($0.endTimeSeconds * 1000),
                    quality: Double($0.qualityScore)
                )
            })
            progress?(0.7 * Double(offset + 1) / Double(max(1, windows.count)))
        }
        return try recluster(merge(spans), in: source, using: manager) { fraction in
            progress?(0.7 + 0.3 * fraction)
        }
    }

    // MARK: - Second pass: one embedding per turn

    /// Same-speaker distance for the WeSpeaker embeddings, matching
    /// `DiarizerConfig.clusteringThreshold`'s default and scale (cosine
    /// distance of L2-normalized vectors).
    private static let sameSpeakerDistance: Float = 0.7
    /// A turn shorter than this may join an existing speaker but never found a
    /// new one: a 1-2 s embedding is noisy enough that letting it open a
    /// cluster is how phantom third speakers get invented.
    private static let foundingTurnMs = 2_000
    /// The embedding model reads at most one 10 s window; a longer turn is
    /// represented by its first 10 s, which is fine because a turn is one
    /// speaker by construction.
    private static let embedCapMs = 10_000

    /// Re-assigns every turn its own speaker, from its own audio.
    ///
    /// The first pass cuts audio into fixed 10 s chunks and pulls ONE
    /// embedding per local speaker slot per chunk. When two voices the
    /// segmentation model cannot tell apart share a chunk -- an adult and a
    /// child, say -- both speakers collapse into one slot, one embedding, one
    /// cluster, and no clustering threshold can split them again. (Verified
    /// directly: the same two voices cluster apart the moment they stop
    /// sharing a chunk.)
    ///
    /// So the first pass is trusted only for *where turns are*, never for who
    /// spoke: each merged span is re-embedded from exactly its own audio and
    /// the spans are re-clustered globally, longest first, so the cleanest
    /// embeddings found the clusters and two-second replies only ever join
    /// them.
    private func recluster(
        _ spans: [SpeakerSpan], in source: any PCMSource, using manager: DiarizerManager,
        progress: (Double) -> Void
    ) throws -> [SpeakerSpan] {
        guard spans.count > 1 else { return spans }

        var clusters: [Cluster] = []
        var out: [SpeakerSpan] = []
        out.reserveCapacity(spans.count)

        let ordered = spans.sorted { $0.durationMs > $1.durationMs }
        for (index, span) in ordered.enumerated() {
            try Task.checkCancellation()
            defer { progress(Double(index + 1) / Double(spans.count)) }

            let endMs = min(span.endMs, span.startMs + Self.embedCapMs)
            let samples = source.floats(msRange: span.startMs..<endMs)
            // The extractor's doc says L2-normalized; the vectors it returns
            // are not. Normalize here or cosine distances are meaningless.
            guard let raw = try? manager.extractSpeakerEmbedding(from: samples),
                  manager.validateEmbedding(raw),
                  let embedding = Self.normalized(raw) else {
                // Unembeddable audio keeps its first-pass guess: possibly
                // fused, but strictly better than dropping the turn.
                out.append(span)
                continue
            }

            let nearest = clusters.indices.min {
                Self.cosineDistance(embedding, clusters[$0].centroid)
                    < Self.cosineDistance(embedding, clusters[$1].centroid)
            }
            var copy = span
            if let found = nearest,
               Self.cosineDistance(embedding, clusters[found].centroid) < Self.sameSpeakerDistance
                   || span.durationMs < Self.foundingTurnMs {
                copy.speakerId = clusters[found].id
                clusters[found] = Self.absorb(clusters[found], embedding, weightMs: span.durationMs)
            } else {
                let cluster = Cluster(id: "T\(clusters.count + 1)",
                                      centroid: embedding, weightMs: span.durationMs)
                clusters.append(cluster)
                copy.speakerId = cluster.id
            }
            out.append(copy)
        }
        return out.sorted { $0.startMs < $1.startMs }
    }

    private struct Cluster {
        let id: String
        var centroid: [Float]
        var weightMs: Int
    }

    private static func absorb(_ cluster: Cluster, _ embedding: [Float],
                               weightMs: Int) -> Cluster {
        var updated = cluster
        let total = Float(cluster.weightMs + weightMs)
        let keep = Float(cluster.weightMs) / total
        let add = Float(weightMs) / total
        for index in updated.centroid.indices where index < embedding.count {
            updated.centroid[index] = updated.centroid[index] * keep + embedding[index] * add
        }
        let norm = sqrt(updated.centroid.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { updated.centroid = updated.centroid.map { $0 / norm } }
        updated.weightMs += weightMs
        return updated
    }

    private static func normalized(_ vector: [Float]) -> [Float]? {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }

    /// 1 - cosine similarity of unit vectors, in 0...2.
    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        for index in 0..<min(a.count, b.count) { dot += a[index] * b[index] }
        return 1 - dot
    }

    /// Joins spans the chunking split at a window edge, and drops the
    /// sub-frame slivers that come out of overlapping segmentation.
    private func merge(_ spans: [SpeakerSpan]) -> [SpeakerSpan] {
        let sorted = spans.sorted { $0.startMs < $1.startMs }
        var out: [SpeakerSpan] = []
        for span in sorted where span.durationMs >= 120 {
            if var last = out.last, last.speakerId == span.speakerId,
               span.startMs - last.endMs <= 250 {
                last.endMs = max(last.endMs, span.endMs)
                out[out.count - 1] = last
            } else {
                out.append(span)
            }
        }
        return out
    }
}
