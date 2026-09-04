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
/// SpeakerKit in later is one new conformance and one line in `EngineHost`,
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
    /// A gap this long is worth skipping. Shorter pauses stay in the same
    /// diarization call: turn segmentation needs some silence for context and
    /// thousands of tiny model calls would give back the time saved.
    static let silenceSkipMs = 10_000
    /// Keep acoustic context around every VAD region so breaths and quiet word
    /// endings are not clipped by a detector tuned for transcription.
    static let speechPadMs = 1_000

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
                        speechRegions: [SpeechRegion]? = nil,
                        mode: DiarizationMode = .accurate,
                        expectedSpeakers: Int? = nil,
                        progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan] {
        guard let manager else { throw EngineError.modelNotLoaded }
        guard source.sampleCount > Audio.sampleRate else { return [] }
        guard mode.performsDiarization else { return [] }

        var spans: [SpeakerSpan] = []
        let windows = Self.processingWindows(
            durationMs: source.durationMs, speechRegions: speechRegions
        )
        let firstPassShare = mode == .accurate ? 0.7 : 1.0
        for (offset, window) in windows.enumerated() {
            try Task.checkCancellation()
            let samples = source.floats(msRange: window.startMs..<window.endMs)
            guard samples.count > Audio.sampleRate else { continue }
            let startSeconds = Double(window.startMs) / 1000

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
            progress?(firstPassShare * Double(offset + 1) / Double(max(1, windows.count)))
        }
        let merged = merge(spans)
        guard mode == .accurate else { return merged }
        return try recluster(merged, in: source, using: manager,
                             expectedSpeakers: expectedSpeakers) { fraction in
            progress?(0.7 + 0.3 * fraction)
        }
    }

    /// Continuous ranges handed to FluidAudio. VAD is advisory: nil falls
    /// back to the complete recording, while a non-empty list removes only
    /// silences of at least `silenceSkipMs`. Every result remains on the source
    /// timeline, so no timestamp remapping or audio concatenation is involved.
    static func processingWindows(durationMs: Int,
                                  speechRegions: [SpeechRegion]?) -> [SpeechRegion] {
        guard durationMs > 0 else { return [] }
        guard let speechRegions else {
            return split(SpeechRegion(startMs: 0, endMs: durationMs))
        }
        guard !speechRegions.isEmpty else { return [] }

        let padded = speechRegions
            .map {
                SpeechRegion(startMs: max(0, $0.startMs - speechPadMs),
                             endMs: min(durationMs, $0.endMs + speechPadMs))
            }
            .filter { $0.durationMs > 0 }
            .sorted { $0.startMs < $1.startMs }

        var joined: [SpeechRegion] = []
        for region in padded {
            if var last = joined.last,
               region.startMs - last.endMs < silenceSkipMs {
                last.endMs = max(last.endMs, region.endMs)
                joined[joined.count - 1] = last
            } else {
                joined.append(region)
            }
        }
        return joined.flatMap(split)
    }

    private static func split(_ region: SpeechRegion) -> [SpeechRegion] {
        var out: [SpeechRegion] = []
        var start = region.startMs
        while start < region.endMs {
            let end = min(region.endMs, start + windowMs)
            out.append(SpeechRegion(startMs: start, endMs: end))
            start = end
        }
        return out
    }

    // MARK: - Second pass: one embedding per turn

    /// Same-speaker distance for the WeSpeaker embeddings, matching
    /// `DiarizerConfig.clusteringThreshold`'s default and scale (cosine
    /// distance of L2-normalized vectors).
    private static let sameSpeakerDistance: Float = 0.7
    /// How far apart two clusters may be and still be folded together when
    /// the user's head-count says there are too many. Wider than
    /// `sameSpeakerDistance`, because the count is evidence the threshold did
    /// not have; narrower than "anything", because a real seventh voice must
    /// survive a count of six. Unmeasured: tune on the six-person room file.
    private static let consolidationDistance: Float = 0.85
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
        expectedSpeakers: Int?, progress: (Double) -> Void
    ) throws -> [SpeakerSpan] {
        guard spans.count > 1 else { return spans }

        var clusterer = TurnClusterer(sameSpeakerDistance: Self.sameSpeakerDistance,
                                      foundingTurnMs: Self.foundingTurnMs)
        var out: [SpeakerSpan] = []
        out.reserveCapacity(spans.count)
        /// Which spans were placed by the clusterer, as opposed to keeping
        /// their first-pass label. Only these are subject to consolidation.
        var placed = Set<UUID>()

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
                  let embedding = TurnClusterer.normalized(raw) else {
                // Unembeddable audio keeps its first-pass guess: possibly
                // fused, but strictly better than dropping the turn.
                out.append(span)
                continue
            }

            var copy = span
            copy.speakerId = clusterer.assign(embedding, durationMs: span.durationMs)
            placed.insert(copy.id)
            out.append(copy)
        }

        if let target = expectedSpeakers, target > 0 {
            let aliases = clusterer.consolidate(toward: target,
                                                withinDistance: Self.consolidationDistance)
            if !aliases.isEmpty {
                out = out.map { span in
                    guard placed.contains(span.id), let to = aliases[span.speakerId] else { return span }
                    var copy = span
                    copy.speakerId = to
                    return copy
                }
            }
        }
        return out.sorted { $0.startMs < $1.startMs }
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
