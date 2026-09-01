import Foundation

/// How aggressively to cut the token stream into segments.
public struct SegmentPolicy: Sendable {
    /// A pause longer than this starts a new segment.
    public var maxGapMs: Int
    /// Hard ceiling, so one unbroken monologue does not become one giant row.
    public var maxSegmentMs: Int
    /// Below this a segment will not be cut on punctuation alone.
    public var minSegmentMs: Int
    /// A speaker must hold at least this share of a segment to be credited.
    /// Below it the segment keeps `nil`, which reads as "unattributed" rather
    /// than confidently wrong.
    public var minSpeakerShare: Double
    /// Cut whenever the diarizer says the speaker changed.
    public var splitOnSpeakerChange: Bool

    public init(maxGapMs: Int = 800, maxSegmentMs: Int = 20_000,
                minSegmentMs: Int = 1_200, minSpeakerShare: Double = 0.34,
                splitOnSpeakerChange: Bool = true) {
        self.maxGapMs = maxGapMs
        self.maxSegmentMs = maxSegmentMs
        self.minSegmentMs = minSegmentMs
        self.minSpeakerShare = minSpeakerShare
        self.splitOnSpeakerChange = splitOnSpeakerChange
    }

    public static let `default` = SegmentPolicy()
}

/// Joins the two pipelines that ran over the same audio without knowing about
/// each other: Whisper produced words with timings, the diarizer produced spans
/// with speakers. Neither is authoritative about the other, so everything here
/// is decided by overlap on the shared timeline.
public enum SegmentMerger {

    // MARK: - Attribution

    /// The speaker holding the most of `startMs..<endMs`, and its share.
    ///
    /// Returns nil when the winner does not clear `minShare`. Whisper's word
    /// boundaries and pyannote's speech boundaries disagree by a few hundred
    /// milliseconds routinely, so a token straddling a turn gets a genuine
    /// two-way split and guessing would be worse than abstaining.
    public static func dominantSpeaker(
        startMs: Int, endMs: Int, spans: [SpeakerSpan], minShare: Double
    ) -> (speakerId: String, share: Double)? {
        let span = max(1, endMs - startMs)
        var totals: [String: Int] = [:]
        for candidate in spans {
            // Sorted input means we can stop once spans start after us.
            if candidate.startMs >= endMs { break }
            let overlap = candidate.overlapMs(startMs: startMs, endMs: endMs)
            if overlap > 0 { totals[candidate.speakerId, default: 0] += overlap }
        }
        guard let best = totals.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(best.value) / Double(span)
        return share >= minShare ? (best.key, share) : nil
    }

    /// Stamps speakers onto segments that already exist -- the live path, where
    /// segments were committed before diarization had anything to say.
    public static func attribute(
        _ segments: [Segment], to spans: [SpeakerSpan],
        policy: SegmentPolicy = .default
    ) -> [Segment] {
        guard !spans.isEmpty else { return segments }
        let sorted = spans.sorted { $0.startMs < $1.startMs }
        return segments.map { segment in
            var copy = segment
            copy.speakerId = dominantSpeaker(
                startMs: segment.startMs, endMs: segment.endMs,
                spans: sorted, minShare: policy.minSpeakerShare
            )?.speakerId
            return copy
        }
    }

    // MARK: - Building segments from words

    /// Cuts a word stream into transcript segments, splitting on speaker turns.
    ///
    /// This is the offline/import path, where all the words and all the spans
    /// exist at once and the segmentation can be chosen properly rather than
    /// being dictated by when the commit policy happened to agree.
    public static func segments(
        from tokens: [Token],
        spans: [SpeakerSpan] = [],
        audio: AudioReference? = nil,
        startingAt firstIndex: Int = 0,
        policy: SegmentPolicy = .default
    ) -> [Segment] {
        guard !tokens.isEmpty else { return [] }
        let sortedSpans = spans.sorted { $0.startMs < $1.startMs }

        var out: [Segment] = []
        var bucket: [Token] = []
        var bucketSpeaker: String?
        var index = firstIndex

        func flush() {
            guard !bucket.isEmpty else { return }
            let text = bucket.joinedText
            guard !text.isEmpty else { bucket.removeAll(); return }
            let start = bucket.first!.startMs
            let end = max(bucket.last!.endMs, start + 1)
            var reference = audio
            reference?.offsetMs = start
            out.append(Segment(
                index: index,
                startMs: start,
                endMs: end,
                text: text,
                speakerId: bucketSpeaker,
                confidence: bucket.meanConfidence,
                audio: reference
            ))
            index += 1
            bucket.removeAll()
        }

        for token in tokens {
            let speaker = sortedSpans.isEmpty ? nil : dominantSpeaker(
                startMs: token.startMs, endMs: token.endMs,
                spans: sortedSpans, minShare: policy.minSpeakerShare
            )?.speakerId

            if let last = bucket.last {
                let gap = token.startMs - last.endMs
                let span = token.endMs - bucket[0].startMs
                // An unattributed word between two of the same speaker's words
                // is a boundary artefact, not a turn -- do not cut on it.
                let turnChanged = policy.splitOnSpeakerChange
                    && speaker != nil && bucketSpeaker != nil && speaker != bucketSpeaker
                let sentenceEnded = span >= policy.minSegmentMs && endsSentence(last.text)

                if gap > policy.maxGapMs || span > policy.maxSegmentMs
                    || turnChanged || sentenceEnded {
                    flush()
                }
            }
            if bucket.isEmpty { bucketSpeaker = speaker }
            else if bucketSpeaker == nil { bucketSpeaker = speaker }
            bucket.append(token)
        }
        flush()
        return out
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?。！？".contains(last)
    }

    // MARK: - Speaker roster

    /// The speakers present, ordered by when each first spoke, relabelled
    /// `S1, S2, ...` in that order.
    ///
    /// Backends number speakers by internal cluster index, which is arbitrary
    /// and can put the person who opens the meeting at "Speaker 4". Renumbering
    /// by first appearance is the only ordering a reader can predict.
    public static func normalize(_ spans: [SpeakerSpan]) -> (spans: [SpeakerSpan], roster: [SpeakerLabel]) {
        let sorted = spans.sorted { $0.startMs < $1.startMs }
        var mapping: [String: String] = [:]
        var speech: [String: Int] = [:]
        var next = 1

        var renamed: [SpeakerSpan] = []
        renamed.reserveCapacity(sorted.count)
        for span in sorted {
            let label: String
            if let existing = mapping[span.speakerId] {
                label = existing
            } else {
                label = "S\(next)"
                mapping[span.speakerId] = label
                next += 1
            }
            speech[label, default: 0] += span.durationMs
            var copy = span
            copy.speakerId = label
            renamed.append(copy)
        }

        let roster = speech.keys.sorted { lhs, rhs in
            (Int(lhs.dropFirst()) ?? 0) < (Int(rhs.dropFirst()) ?? 0)
        }.map { label in
            SpeakerLabel(id: label,
                         displayName: SpeakerLabel.defaultName(for: label),
                         speechMs: speech[label] ?? 0)
        }
        return (renamed, roster)
    }
}
