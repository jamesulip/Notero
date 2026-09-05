import Foundation

/// Combining two separately decoded lanes into one transcript.
///
/// Each lane is decoded on its own rather than mixed, and this is why: mixing
/// throws away the one piece of speaker information that costs nothing and
/// cannot be wrong. Nobody in the room is on the remote lane and nobody on the
/// call is on the room lane, so the attribution is a fact about where the
/// samples came from rather than a clustering decision with a threshold in it.
///
/// Decoding separately also means overlapping speech survives. When someone in
/// the room talks over someone on the call, a mixed recording gives the model
/// two voices at once and it returns one garbled line; two lanes give two
/// clean lines that happen to share a timestamp.
public enum LaneTranscript {

    /// One lane's decoded segments, before they are given a speaker.
    public struct Lane: Sendable {
        public let lane: CaptureLane
        public let segments: [Segment]

        public init(lane: CaptureLane, segments: [Segment]) {
            self.lane = lane
            self.segments = segments
        }
    }

    /// Interleaves the lanes by time and gives every segment a speaker.
    ///
    /// Segments keep their own text and boundaries; only the order, the index
    /// and the speaker change. Ties go to the earlier lane in the list, which
    /// keeps the result stable rather than dependent on dictionary order.
    public static func merge(_ lanes: [Lane]) -> (segments: [Segment], roster: [SpeakerLabel]) {
        var tagged: [(order: Int, segment: Segment)] = []
        var speech: [CaptureLane: Int] = [:]

        for (order, lane) in lanes.enumerated() {
            for segment in lane.segments {
                var copy = segment
                // Only when the lane has something to say. A segment that
                // already carries a diarized speaker from within its own lane
                // keeps it, so "Room 2" survives this step.
                if copy.speakerId == nil { copy.speakerId = lane.lane.rawValue }
                tagged.append((order, copy))
                speech[lane.lane, default: 0] += segment.durationMs
            }
        }

        let ordered = tagged
            .enumerated()
            .sorted { left, right in
                if left.element.segment.startMs != right.element.segment.startMs {
                    return left.element.segment.startMs < right.element.segment.startMs
                }
                if left.element.order != right.element.order {
                    return left.element.order < right.element.order
                }
                return left.offset < right.offset
            }
            .map(\.element.segment)

        var indexed: [Segment] = []
        indexed.reserveCapacity(ordered.count)
        for (index, segment) in ordered.enumerated() {
            var copy = segment
            copy.index = index
            indexed.append(copy)
        }

        let roster = lanes.compactMap { lane -> SpeakerLabel? in
            guard let ms = speech[lane.lane], ms > 0 else { return nil }
            return SpeakerLabel(id: lane.lane.rawValue,
                                displayName: lane.lane.speakerLabel,
                                speechMs: ms)
        }
        return (indexed, roster)
    }

    /// Prefixes a lane's own diarization so two lanes cannot collide.
    ///
    /// Both lanes are diarized independently and both call their first speaker
    /// `S1`. Left alone, the person at the head of the table and the loudest
    /// person on the call merge into one speaker who appears to interrupt
    /// themselves.
    public static func qualify(_ spans: [SpeakerSpan], as lane: CaptureLane) -> [SpeakerSpan] {
        spans.map { span in
            var copy = span
            copy.speakerId = "\(lane.rawValue)-\(span.speakerId)"
            return copy
        }
    }

    /// The speakers a finished two-lane transcript actually has.
    ///
    /// Diarization within a lane does not cover every segment: a stretch the
    /// diarizer had no opinion about leaves a segment attributed to its lane
    /// and to nobody in particular. That segment is not a mistake -- the lane
    /// is real information, and "someone in the room" is the honest label --
    /// but without an entry naming it, the transcript renders the raw id and
    /// shows a speaker called `room`.
    ///
    /// So the roster is built from what the segments actually reference, and
    /// from nothing else. A diarized speaker nobody was assigned to does not
    /// appear, and neither does a lane that every segment attributed more
    /// precisely.
    public static func roster(for segments: [Segment], lanes: [CaptureLane],
                              diarized: [SpeakerLabel]) -> [SpeakerLabel] {
        var speech: [String: Int] = [:]
        for segment in segments {
            guard let id = segment.speakerId else { continue }
            speech[id, default: 0] += segment.durationMs
        }

        var roster: [SpeakerLabel] = []
        for lane in lanes {
            // The lane's own diarized speakers first, then the catch-all for
            // that lane, so the people of one side stay together.
            for label in diarized where label.id.hasPrefix("\(lane.rawValue)-") {
                if let ms = speech[label.id] {
                    roster.append(SpeakerLabel(id: label.id,
                                               displayName: label.displayName,
                                               speechMs: ms))
                }
            }
            if let ms = speech[lane.rawValue] {
                roster.append(SpeakerLabel(id: lane.rawValue,
                                           displayName: lane.speakerLabel,
                                           speechMs: ms))
            }
        }
        return roster
    }

    /// Display names for lane-qualified speakers: "Room 1", "Remote 2".
    public static func qualify(_ roster: [SpeakerLabel], as lane: CaptureLane) -> [SpeakerLabel] {
        roster.enumerated().map { index, label in
            SpeakerLabel(id: "\(lane.rawValue)-\(label.id)",
                         displayName: roster.count == 1
                             ? lane.speakerLabel
                             : "\(lane.speakerLabel) \(index + 1)",
                         speechMs: label.speechMs)
        }
    }
}
