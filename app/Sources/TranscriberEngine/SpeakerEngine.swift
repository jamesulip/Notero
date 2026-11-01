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

    /// Every number the speaker pipeline is tuned by.
    ///
    /// `shipping` is what the app runs and what the tests pin. The benchmark
    /// tool builds the others, so a threshold can be measured against the
    /// fixtures without editing the engine (`eval/run_diarization_ab.py` runs
    /// the arms; `eval/tuning_verdict.py` holds the rule a change has to meet).
    public struct Tuning: Sendable, Equatable {
        /// FluidAudio's first pass drops a segment shorter than this, and a
        /// segment shorter than this cannot found a speaker there either.
        ///
        /// This is the minimum for `accurate` mode, where a second pass re-embeds
        /// every turn and a short turn can join a speaker but never found one
        /// (`foundingTurnMs`). It was 1.0 s, on the reasoning that a turn under a
        /// second is a backchannel and crediting it to a new speaker fragments the
        /// transcript. 0.6 s recovers those turns: on 36 synthetic fixtures, 19
        /// of them tuning and 17 hold-out, missed speech fell from 6.7% to 3.6%
        /// and from 4.8% to 2.4%, mean DER fell 2.4 and 2.1 points, no speaker was
        /// merged or invented, and speaker processing took 5.7% longer. It also
        /// puts 98 spans of under a second into the output where there were none,
        /// so a backchannel inside someone's sentence now splits the transcript
        /// line. 0.4 s collapsed two voices into one (finding 29). Every number is
        /// from text-to-speech audio. Set it back to 1.0 to undo.
        public var firstPassMinSpeechSeconds: Float = 0.6
        /// The same minimum for `fast` mode, which has no second pass: whatever
        /// the first pass decides is the answer, and a lower minimum lets its
        /// online clustering found phantom speakers from short segments.
        public var fastFirstPassMinSpeechSeconds: Float = 1.0
        /// Same-label spans closer than this are one span. Chunking splits a
        /// turn at a window edge; this joins it again.
        public var mergeGapMs: Int = 250
        /// Slivers shorter than this come out of overlapping segmentation.
        public var minSpanMs: Int = 120
        /// After the second pass, same-speaker spans closer than this are joined
        /// again. Zero (the shipping value) leaves them alone. Exists so the merge
        /// before clustering can be switched off (`mergeGapMs` 0), which keeps a
        /// turn boundary the first pass bridged for the embeddings to see, without
        /// losing the speech that bridging used to cover.
        public var finalMergeGapMs: Int = 0
        /// Same-speaker distance for the WeSpeaker embeddings, matching
        /// `DiarizerConfig.clusteringThreshold`'s default and scale (cosine
        /// distance of L2-normalized vectors).
        public var sameSpeakerDistance: Float = 0.7
        /// How far apart two clusters may be and still be folded together when
        /// the user's head-count says there are too many. Wider than
        /// `sameSpeakerDistance`, because the count is evidence the threshold did
        /// not have; narrower than "anything", because a real seventh voice must
        /// survive a count of six. Measured only on synthetic voices
        /// (`eval/run_headcount.py`); never on a real six-person room.
        public var consolidationDistance: Float = 0.85
        /// A turn shorter than this may join an existing speaker but never found
        /// a new one: a 1-2 s embedding is noisy enough that letting it open a
        /// cluster is how phantom third speakers get invented.
        public var foundingTurnMs: Int = 2_000
        public static let shipping = Tuning()
        public init() {}

        /// FluidAudio fixes this when its manager is built, so each mode has its own.
        func firstPassMinSpeechSeconds(for mode: DiarizationMode) -> Float {
            mode == .accurate ? firstPassMinSpeechSeconds : fastFirstPassMinSpeechSeconds
        }
    }

    private let modelsDirectory: URL
    private let tuning: Tuning
    /// What `prepare` loaded. Kept so a manager can be built for each mode:
    /// FluidAudio's first-pass minimum is a `let` of the manager, so two modes
    /// that want two minimums need two managers over the same models.
    private var models: DiarizerModels?
    private var managers: [DiarizationMode: DiarizerManager] = [:]

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

    public init(modelsDirectory: URL, tuning: Tuning = .shipping) {
        self.modelsDirectory = modelsDirectory
        self.tuning = tuning
    }

    public var isAvailable: Bool { models != nil }

    public func prepare(progress: ProgressReport?) async throws {
        guard models == nil else { return }
        progress?("Loading speaker models…", nil)
        do {
            let models = try await DiarizerModels.downloadIfNeeded(
                to: modelsDirectory.appendingPathComponent("Diarizer", isDirectory: true)
            )
            self.models = models
            progress?("Speaker models ready", 1)
        } catch {
            throw EngineError.backendUnavailable(
                "Speaker identification is unavailable: \(error.localizedDescription)")
        }
    }

    public func unload() {
        for manager in managers.values { manager.cleanup() }
        managers = [:]
        models = nil
    }

    /// The manager for a mode, built on first use and kept until `unload` so its
    /// speaker database carries across the windows of one recording.
    private func manager(for mode: DiarizationMode) throws -> DiarizerManager {
        if let existing = managers[mode] { return existing }
        guard let models else { throw EngineError.modelNotLoaded }
        var config = DiarizerConfig.default
        config.minSpeechDuration = tuning.firstPassMinSpeechSeconds(for: mode)
        // FluidAudio 0.15.6 declares `minSilenceGap` and never reads it (the only
        // mentions are the declaration and its CLI flags), so setting it changed
        // nothing. Left at its default.
        let manager = DiarizerManager(config: config)
        manager.initialize(models: models)
        managers[mode] = manager
        return manager
    }

    public func diarize(_ source: any PCMSource,
                        speechRegions: [SpeechRegion]? = nil,
                        mode: DiarizationMode = .accurate,
                        expectedSpeakers: Int? = nil,
                        progress: (@Sendable (Double) -> Void)?) async throws -> [SpeakerSpan] {
        guard models != nil else { throw EngineError.modelNotLoaded }
        guard source.sampleCount > Audio.sampleRate else { return [] }
        guard mode.performsDiarization else { return [] }
        let manager = try manager(for: mode)

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
        let placed = try recluster(merged, in: source, using: manager,
                                   expectedSpeakers: expectedSpeakers) { fraction in
            progress?(0.7 + 0.3 * fraction)
        }
        return tuning.finalMergeGapMs > 0
            ? Self.join(placed, gapMs: tuning.finalMergeGapMs) : placed
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

        var clusterer = TurnClusterer(sameSpeakerDistance: tuning.sameSpeakerDistance,
                                      foundingTurnMs: tuning.foundingTurnMs)
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
                                                withinDistance: tuning.consolidationDistance)
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
            .filter { $0.durationMs >= tuning.minSpanMs }
        return Self.join(sorted, gapMs: tuning.mergeGapMs)
    }

    /// Consecutive spans of one speaker that are no further apart than `gapMs`
    /// become one. `sorted` is in start order. Only the span directly before
    /// is considered, so a span of another speaker in between keeps two apart.
    static func join(_ sorted: [SpeakerSpan], gapMs: Int) -> [SpeakerSpan] {
        var out: [SpeakerSpan] = []
        out.reserveCapacity(sorted.count)
        for span in sorted {
            if var last = out.last, last.speakerId == span.speakerId,
               span.startMs - last.endMs <= gapMs {
                last.endMs = max(last.endMs, span.endMs)
                out[out.count - 1] = last
            } else {
                out.append(span)
            }
        }
        return out
    }
}
