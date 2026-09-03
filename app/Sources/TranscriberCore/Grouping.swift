import Foundation

/// A run of consecutive segments from one speaker, shown as a single card.
public struct TranscriptBlock: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var speakerId: String?
    public var startMs: Int
    public var endMs: Int
    public var segments: [Segment]

    public var text: String {
        segments.map(\.displayText).joined(separator: " ")
    }

    public func contains(ms: Int) -> Bool { ms >= startMs && ms < max(endMs, startMs + 1) }
}

/// Segments stay fine-grained in storage -- each one needs its own id so a
/// search hit or a note back-link can address it -- but reading a transcript
/// one four-second row at a time is miserable. Grouping happens on the way to
/// the screen and to plain text, and leaves the stored data alone.
public enum TranscriptGrouping {

    public static func blocks(
        from segments: [Segment],
        maxGapMs: Int = 1_500,
        maxBlockMs: Int = 60_000
    ) -> [TranscriptBlock] {
        var out: [TranscriptBlock] = []
        var bucket: [Segment] = []

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            out.append(TranscriptBlock(
                id: first.id,
                speakerId: first.speakerId,
                startMs: first.startMs,
                endMs: max(last.endMs, first.startMs + 1),
                segments: bucket
            ))
            bucket.removeAll()
        }

        for segment in segments.sorted(by: { $0.startMs < $1.startMs }) {
            if let last = bucket.last, let first = bucket.first {
                let sameSpeaker = last.speakerId == segment.speakerId
                let gap = segment.startMs - last.endMs
                let span = segment.endMs - first.startMs
                if !sameSpeaker || gap > maxGapMs || span > maxBlockMs { flush() }
            }
            bucket.append(segment)
        }
        flush()
        return out
    }

    /// The block containing `ms`, or nil in a gap or past the end. Binary
    /// search, for the same reason as `segmentIndex`: the follower asks on
    /// every player tick.
    public static func blockIndex(at ms: Int, in blocks: [TranscriptBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var low = 0
        var high = blocks.count - 1
        var best: Int?
        while low <= high {
            let mid = (low + high) / 2
            if blocks[mid].startMs <= ms {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let best, blocks[best].contains(ms: ms) else { return nil }
        return best
    }

    /// The segment playing at `ms`, or the last one before it.
    ///
    /// Binary search rather than a scan: this runs on every player tick, and a
    /// two-hour meeting is tens of thousands of segments.
    public static func segmentIndex(at ms: Int, in segments: [Segment]) -> Int? {
        guard !segments.isEmpty else { return nil }
        var low = 0
        var high = segments.count - 1
        var best: Int?
        while low <= high {
            let mid = (low + high) / 2
            if segments[mid].startMs <= ms {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }
}
