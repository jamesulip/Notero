import Foundation

/// Which speaker of an earlier run is which speaker of a new run.
///
/// A segment holds a label (`S1`) and a person's name for that speaker lives on
/// the row for the label. Labels are numbered by who speaks first, and that can
/// change between two runs over the same audio: a run that drops a one-second
/// opener numbers the other person first, a head-count changes which voices
/// fuse. Without this, "Maria" moves to whoever is `S1` now.
///
/// The only evidence the diarizer gives through `SpeakerDiarizing` is spans, so
/// the evidence here is time. Two speakers are the same person when the stretch
/// of the timeline the old run gave to one is, for the most part, the stretch the
/// new run gives to the other. No embeddings, no model, nothing stored beyond
/// what a transcript already holds.
///
/// The rule is built to be wrong by omission and not by commission. A pair is
/// matched only when it is mutual (each is the other's clear best), the overlap
/// is large in absolute terms, and it covers most of the smaller of the two
/// speakers. An even split, an even fusion or a speaker with almost no overlap
/// is left unmatched, and the caller keeps the old name off the new speaker.
public enum SpeakerMatching {

    public struct Policy: Sendable, Equatable {
        /// Overlap below this is noise: a boundary that disagrees by a turn.
        public var minOverlapMs: Int
        /// The winner must hold at least this many times the runner-up's
        /// overlap, on the old speaker's side and on the new one's. Above 1, so
        /// an exact tie never matches.
        public var dominance: Double
        /// The overlap must be at least this share of the smaller of the two
        /// speakers' total time, so a coincidental slice of a long speaker is
        /// not a match however clear it is next to other coincidences.
        public var minCoverage: Double

        public init(minOverlapMs: Int = 2_000, dominance: Double = 2.0,
                    minCoverage: Double = 0.5) {
            self.minOverlapMs = minOverlapMs
            self.dominance = max(1.000_001, dominance)
            self.minCoverage = minCoverage
        }

        public static let `default` = Policy()
    }

    /// New label -> old label, for the pairs that are unambiguous.
    ///
    /// `old` is the earlier run's territory: the spans of the earlier
    /// diarization, or the lines of the earlier transcript with the labels they
    /// carry (which includes every line a person moved by hand). `new` is the
    /// new run's spans. Both are on the same timeline.
    public static func match(old: [SpeakerSpan], new: [SpeakerSpan],
                             policy: Policy = .default) -> [String: String] {
        let overlap = overlaps(old: old, new: new)
        guard !overlap.isEmpty else { return [:] }

        var oldTotal: [String: Int] = [:]
        for span in old where span.durationMs > 0 { oldTotal[span.speakerId, default: 0] += span.durationMs }
        var newTotal: [String: Int] = [:]
        for span in new where span.durationMs > 0 { newTotal[span.speakerId, default: 0] += span.durationMs }

        // The largest overlap each speaker has with anyone but the pair under test.
        var byNew: [String: [(old: String, ms: Int)]] = [:]
        for (oldLabel, row) in overlap {
            for (newLabel, ms) in row { byNew[newLabel, default: []].append((oldLabel, ms)) }
        }

        var matched: [String: String] = [:]
        for (oldLabel, row) in overlap {
            for (newLabel, ms) in row where ms >= policy.minOverlapMs {
                let smaller = min(oldTotal[oldLabel] ?? 0, newTotal[newLabel] ?? 0)
                guard Double(ms) >= policy.minCoverage * Double(smaller) else { continue }

                let rowRunnerUp = row.filter { $0.key != newLabel }.map(\.value).max() ?? 0
                let columnRunnerUp = (byNew[newLabel] ?? [])
                    .filter { $0.old != oldLabel }.map(\.ms).max() ?? 0
                guard Double(ms) >= policy.dominance * Double(rowRunnerUp),
                      Double(ms) >= policy.dominance * Double(columnRunnerUp) else { continue }
                matched[newLabel] = oldLabel
            }
        }
        return matched
    }

    /// The label each new speaker ends up under.
    ///
    /// An inherited speaker takes its predecessor's label. Every other speaker
    /// keeps the label the new run gave it unless that label now belongs to
    /// someone (an inheriting speaker, or an old label in `reserved`), in which
    /// case it takes the lowest free number of the same kind. `reserved` is for
    /// old labels that must keep meaning the same thing: a speaker a person
    /// named and the new run did not find.
    ///
    /// `newOrder` is the order speakers are visited in, so the result does not
    /// depend on dictionary order.
    public static func finalLabels(newOrder: [String], inherited: [String: String],
                                   reserved: Set<String> = []) -> [String: String] {
        var final: [String: String] = [:]
        var taken = reserved
        for label in newOrder {
            if let old = inherited[label] {
                final[label] = old
                taken.insert(old)
            }
        }
        // Keep the new run's own label where it is free; this is what leaves a
        // first run, or a run with nothing in common, exactly as it came.
        var pending: [String] = []
        for label in newOrder where final[label] == nil {
            if taken.contains(label) { pending.append(label) } else {
                final[label] = label
                taken.insert(label)
            }
        }
        for label in pending {
            let next = freeLabel(like: label, taken: taken)
            final[label] = next
            taken.insert(next)
        }
        return final
    }

    /// Everything a caller needs: who inherits from whom, which old names stay,
    /// and what every new label becomes.
    public struct Carry: Sendable, Equatable {
        /// New label -> old label.
        public var inherited: [String: String]
        /// New label -> the label it is stored under.
        public var labels: [String: String]
        /// Old labels with a user-chosen name and no heir. Their rows stay.
        public var kept: [String]

        public func label(for newLabel: String) -> String { labels[newLabel] ?? newLabel }
    }

    /// `named` is the old labels a person gave a name to.
    public static func carry(old: [SpeakerSpan], new: [SpeakerSpan], newOrder: [String],
                             named: Set<String>, policy: Policy = .default) -> Carry {
        let inherited = match(old: old, new: new, policy: policy)
        let heirs = Set(inherited.values)
        let kept = named.subtracting(heirs).sorted()
        let labels = finalLabels(newOrder: newOrder, inherited: inherited, reserved: Set(kept))
        return Carry(inherited: inherited, labels: labels, kept: kept)
    }

    // MARK: - Arithmetic

    /// Milliseconds shared by each (old label, new label) pair.
    static func overlaps(old: [SpeakerSpan], new: [SpeakerSpan]) -> [String: [String: Int]] {
        let new = new.filter { $0.durationMs > 0 }.sorted { $0.startMs < $1.startMs }
        guard !new.isEmpty else { return [:] }
        // Spans from different speakers may overlap each other, so a plain
        // pointer walk would skip some. The running maximum of the end times
        // never decreases, which is what makes it searchable.
        var runningEnd: [Int] = []
        runningEnd.reserveCapacity(new.count)
        var highest = Int.min
        for span in new {
            highest = max(highest, span.endMs)
            runningEnd.append(highest)
        }

        var out: [String: [String: Int]] = [:]
        for oldSpan in old where oldSpan.durationMs > 0 {
            var low = 0, high = new.count
            while low < high {
                let mid = (low + high) / 2
                if runningEnd[mid] > oldSpan.startMs { high = mid } else { low = mid + 1 }
            }
            var index = low
            while index < new.count, new[index].startMs < oldSpan.endMs {
                let shared = new[index].overlapMs(startMs: oldSpan.startMs, endMs: oldSpan.endMs)
                if shared > 0 { out[oldSpan.speakerId, default: [:]][new[index].speakerId, default: 0] += shared }
                index += 1
            }
        }
        return out
    }

    /// `S3` -> the lowest `S<n>` not in `taken`; `room-S1` -> `room-S2` and so on.
    static func freeLabel(like label: String, taken: Set<String>) -> String {
        var prefix = Substring(label)
        while let last = prefix.last, last.isNumber { prefix = prefix.dropLast() }
        var number = 1
        while taken.contains("\(prefix)\(number)") { number += 1 }
        return "\(prefix)\(number)"
    }
}
