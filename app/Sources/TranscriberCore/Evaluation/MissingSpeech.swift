import Foundation

// Speech the reference has and the hypothesis never produced a word for.
//
// A WER says how many words were lost, not where. A window that never decoded
// (a refused window, a VAD gap, a stalled lane) shows up here as a stretch of
// reference speech with no hypothesis word near it, which is what has to be
// found to fix it. This reads only times, so it works the same whatever the
// words were.

/// A stretch of reference speech that the hypothesis words barely cover.
public struct MissingRegion: Codable, Sendable, Equatable {
    public var startMs: Int
    public var endMs: Int
    /// Share of the region covered by padded hypothesis words, 0...1.
    public var coverage: Double
    /// The reference utterances that make up the region, in reference order.
    public var utteranceIds: [String]

    public init(startMs: Int, endMs: Int, coverage: Double, utteranceIds: [String]) {
        self.startMs = startMs
        self.endMs = endMs
        self.coverage = coverage
        self.utteranceIds = utteranceIds
    }
}

public struct MissingSpeechReport: Codable, Sendable, Equatable {
    /// Speech regions long enough to check (`minRegionMs`).
    public var checkedRegions: Int
    public var checkedSpeechMs: Int
    /// Milliseconds of checked speech that no padded hypothesis word touches,
    /// summed over every checked region, missing or not.
    public var uncoveredSpeechMs: Int
    public var missingRegions: [MissingRegion]
    /// Duration of the missing regions over `checkedSpeechMs`.
    public var missingShare: MetricValue

    public init(checkedRegions: Int, checkedSpeechMs: Int, uncoveredSpeechMs: Int,
                missingRegions: [MissingRegion], missingShare: MetricValue) {
        self.checkedRegions = checkedRegions
        self.checkedSpeechMs = checkedSpeechMs
        self.uncoveredSpeechMs = uncoveredSpeechMs
        self.missingRegions = missingRegions
        self.missingShare = missingShare
    }
}

public enum MissingSpeech {
    /// Speech regions are the union of the timed reference utterances (touching
    /// or overlapping utterances, of any speaker, form one region). Coverage is
    /// the union of hypothesis word intervals, each widened by `wordPaddingMs`
    /// on both sides. A region of at least `minRegionMs` whose covered share is
    /// below `coverageThreshold` is missing.
    ///
    /// Unavailable without hypothesis word times or reference times. An empty
    /// `words` array is a measurement: the system produced nothing, so every
    /// checked region is missing.
    public static func detect(reference: EvaluationReference, words: [Token]?,
                              settings: MissingSpeechSettings) -> Measured<MissingSpeechReport> {
        guard let words else { return .unavailable(reason: "the hypothesis has no word timestamps") }

        let timed = reference.utterances.enumerated().filter { $0.element.hasTimes }
        guard !timed.isEmpty else { return .unavailable(reason: "the reference has no timestamps") }

        // Speech regions, with the reference positions of their utterances.
        let sortedUtterances = timed.sorted {
            ($0.element.startMs!, $0.offset) < ($1.element.startMs!, $1.offset)
        }
        var regions: [(start: Int, end: Int, members: [Int])] = []
        for (offset, u) in sortedUtterances {
            let s = u.startMs!, e = u.endMs!
            if let last = regions.last, s <= last.end {
                regions[regions.count - 1].end = max(last.end, e)
                regions[regions.count - 1].members.append(offset)
            } else {
                regions.append((s, e, [offset]))
            }
        }

        let coverage = mergedIntervals(words.map { word in
            let start = max(0, word.startMs - settings.wordPaddingMs)
            let end = max(word.startMs, word.endMs) + settings.wordPaddingMs
            return (start, end)
        })

        var checkedRegions = 0, checkedMs = 0, uncoveredMs = 0, missingMs = 0
        var missing: [MissingRegion] = []
        for region in regions {
            let duration = region.end - region.start
            guard duration >= settings.minRegionMs, duration > 0 else { continue }
            checkedRegions += 1
            checkedMs += duration
            let covered = coveredMs(region.start, region.end, coverage)
            uncoveredMs += duration - covered
            let share = Double(covered) / Double(duration)
            if share < settings.coverageThreshold {
                missingMs += duration
                let ids = region.members.sorted().map { reference.utterances[$0].id }
                missing.append(MissingRegion(startMs: region.start, endMs: region.end,
                                             coverage: share, utteranceIds: ids))
            }
        }

        return .available(MissingSpeechReport(
            checkedRegions: checkedRegions, checkedSpeechMs: checkedMs, uncoveredSpeechMs: uncoveredMs,
            missingRegions: missing,
            missingShare: .ratio(missingMs, checkedMs,
                                 unavailable: "no reference speech region is long enough to check")))
    }

    /// Sorted, non-overlapping union of half-open intervals.
    static func mergedIntervals(_ intervals: [(Int, Int)]) -> [(start: Int, end: Int)] {
        var merged: [(start: Int, end: Int)] = []
        for (s, e) in intervals.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) where e > s {
            if let last = merged.last, s <= last.end {
                merged[merged.count - 1].end = max(last.end, e)
            } else {
                merged.append((s, e))
            }
        }
        return merged
    }

    private static func coveredMs(_ start: Int, _ end: Int, _ intervals: [(start: Int, end: Int)]) -> Int {
        // Binary search to the first interval that ends after `start`; a long
        // meeting has thousands of words and hundreds of regions.
        var lo = 0, hi = intervals.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if intervals[mid].end <= start { lo = mid + 1 } else { hi = mid }
        }
        var total = 0
        var k = lo
        while k < intervals.count, intervals[k].start < end {
            total += min(end, intervals[k].end) - max(start, intervals[k].start)
            k += 1
        }
        return total
    }
}
