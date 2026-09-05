import TranscriberCore
import XCTest

/// Merging two decoded lanes. Pure logic, so all of it is testable without
/// audio, a model or a permission -- which is the point of it living here.
final class LaneTranscriptTests: XCTestCase {

    func testLanesInterleaveByTime() {
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 0, 1000, "hello"),
                                          segment(1, 4000, 5000, "still here")]),
            .init(lane: .remote, segments: [segment(0, 2000, 3000, "hi from the call")]),
        ])
        XCTAssertEqual(merged.segments.map(\.text),
                       ["hello", "hi from the call", "still here"])
        XCTAssertEqual(merged.segments.map(\.speakerId), ["room", "remote", "room"])
    }

    func testIndicesAreRewrittenAcrossTheMerge() {
        // Both lanes index from zero. Left alone, the merged transcript has
        // two segments claiming to be number 0, and every back-link that
        // resolves a segment by index lands on the wrong line.
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 0, 500, "a"), segment(1, 3000, 3500, "c")]),
            .init(lane: .remote, segments: [segment(0, 1000, 1500, "b")]),
        ])
        XCTAssertEqual(merged.segments.map(\.index), [0, 1, 2])
    }

    func testOverlappingSpeechKeepsBothLines() {
        // The room and the call talking at once. Mixed, this is one garbled
        // line; kept apart it is two clean ones that share a timestamp.
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 1000, 2000, "as I was saying")]),
            .init(lane: .remote, segments: [segment(0, 1000, 2000, "sorry, go ahead")]),
        ])
        XCTAssertEqual(merged.segments.count, 2)
        XCTAssertEqual(merged.segments.map(\.text), ["as I was saying", "sorry, go ahead"])
        // Ties resolve to the lane order given, not to dictionary order.
        XCTAssertEqual(merged.segments.map(\.speakerId), ["room", "remote"])
    }

    // MARK: - Echo

    func testARoomEchoOfTheCallIsDropped() {
        // The room listens through speakers, so the microphone hears the
        // caller too. Measured on a real capture: the same sentence, twice,
        // under two speakers, on every line.
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 43_000, 45_000, "All my fellow Filipinos,")]),
            .init(lane: .remote, segments: [segment(0, 43_000, 48_000,
                                                    "All my fellow Filipinos, now this is my side.")]),
        ])
        XCTAssertEqual(merged.segments.map(\.text), ["All my fellow Filipinos, now this is my side."])
        XCTAssertEqual(merged.roster.map(\.id), ["remote"])
    }

    func testAnEchoSpanningTwoCallSegmentsIsDropped() {
        // The lanes are segmented on their own, so the room's copy can
        // straddle two remote segments. Its words are still all there.
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 11_000, 14_000, "Divorce? Yes, divorce. Divorce, divorce.")]),
            .init(lane: .remote, segments: [
                segment(0, 4_000, 12_000, "Lagi silang nagkaka ng divorce, divorce din. Divorce? Yes, divorce."),
                segment(1, 13_000, 15_000, "Divorce, divorce. No. No. No catching?"),
            ]),
        ])
        XCTAssertEqual(merged.segments.count, 2)
        XCTAssertEqual(merged.segments.map(\.speakerId), ["remote", "remote"])
    }

    func testMostlyMatchingWordsStillCountAsAnEcho() {
        // The microphone's copy is the worse one, so a word or two comes back
        // garbled. Fifteen words of sixteen is still the same sentence.
        let room = segment(0, 15_000, 22_000,
                           "No catching. Peng call me, I'm in the way, pushing the car because our car damage.")
        let remote = [segment(0, 15_000, 16_500, "No catching. Okay."),
                      segment(1, 17_000, 22_000, "Then call me. I'm in the way. Pushing the car because our car damage.")]
        XCTAssertTrue(LaneTranscript.isEcho(room, of: remote))
    }

    func testRoomSpeechWithItsOwnWordsStays() {
        // Someone in the room talking over the caller is the case two lanes
        // exist for. Different words, same moment: both lines stay.
        let room = segment(0, 1_000, 2_000, "as I was saying, the budget is fine")
        XCTAssertFalse(LaneTranscript.isEcho(room, of: [segment(0, 1_000, 2_000, "sorry, go ahead")]))
    }

    func testTheSameWordsLaterAreNotAnEcho() {
        // A person in the room repeating the caller ten seconds later is a
        // person, not a speaker. The echo arrives within the second.
        let room = segment(0, 20_000, 22_000, "Listen, look and listen and learn.")
        XCTAssertFalse(LaneTranscript.isEcho(room, of: [segment(0, 5_000, 7_000, "Listen, look and listen and learn.")]))
    }

    func testAnEchoIsNotCountedInTheRoster() {
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 0, 1_000, "hello there"),
                                          segment(1, 5_000, 6_000, "yes, that is right")]),
            .init(lane: .remote, segments: [segment(0, 5_000, 6_200, "Yes, that is right.")]),
        ])
        XCTAssertEqual(merged.segments.map(\.text), ["hello there", "Yes, that is right."])
        XCTAssertEqual(merged.roster.first { $0.id == "room" }?.speechMs, 1_000)
    }

    func testRosterCountsSpeechPerLane() {
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 0, 1000, "a"), segment(1, 2000, 2500, "b")]),
            .init(lane: .remote, segments: [segment(0, 1000, 1200, "c")]),
        ])
        XCTAssertEqual(merged.roster.map(\.id), ["room", "remote"])
        XCTAssertEqual(merged.roster.map(\.displayName), ["Room", "Remote"])
        XCTAssertEqual(merged.roster.first?.speechMs, 1500)
        XCTAssertEqual(merged.roster.last?.speechMs, 200)
    }

    func testASilentLaneIsNotInTheRoster() {
        // A meeting with nobody on the call should not list "Remote" as a
        // participant who happened to say nothing.
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [segment(0, 0, 1000, "a")]),
            .init(lane: .remote, segments: []),
        ])
        XCTAssertEqual(merged.roster.map(\.id), ["room"])
    }

    func testADiarizedSpeakerSurvivesTheMerge() {
        // Within-lane diarization has already said which of the six people in
        // the room is talking. The lane must not overwrite that.
        var diarized = segment(0, 0, 1000, "a")
        diarized.speakerId = "room-S2"
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [diarized]),
            .init(lane: .remote, segments: [segment(0, 2000, 3000, "b")]),
        ])
        XCTAssertEqual(merged.segments.map(\.speakerId), ["room-S2", "remote"])
    }

    func testQualifyingKeepsTheLanesApart() {
        // Both diarizers call their first speaker S1. Unqualified, the person
        // at the head of the table and the loudest person on the call become
        // one speaker who interrupts themselves.
        let room = LaneTranscript.qualify(
            [SpeakerSpan(speakerId: "S1", startMs: 0, endMs: 100)], as: .room
        )
        let remote = LaneTranscript.qualify(
            [SpeakerSpan(speakerId: "S1", startMs: 0, endMs: 100)], as: .remote
        )
        XCTAssertEqual(room.first?.speakerId, "room-S1")
        XCTAssertEqual(remote.first?.speakerId, "remote-S1")
        XCTAssertNotEqual(room.first?.speakerId, remote.first?.speakerId)
    }

    func testQualifiedNamesNumberOnlyWhenThereIsMoreThanOne() {
        let one = LaneTranscript.qualify(
            [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 10)], as: .remote
        )
        XCTAssertEqual(one.map(\.displayName), ["Remote"])

        let several = LaneTranscript.qualify([
            SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 10),
            SpeakerLabel(id: "S2", displayName: "Speaker 2", speechMs: 20),
        ], as: .room)
        XCTAssertEqual(several.map(\.displayName), ["Room 1", "Room 2"])
        XCTAssertEqual(several.map(\.id), ["room-S1", "room-S2"])
    }

    // MARK: - The finished roster

    func testAnUnattributedSegmentStillGetsALaneName() {
        // The bug this fixes rendered a speaker called "room" in the
        // transcript: diarization covered most of the lane, the leftover
        // segment kept the bare lane id, and no roster entry named it.
        var known = segment(0, 0, 1000, "a")
        known.speakerId = "room-S1"
        let unattributed = segment(1, 2000, 3000, "b")   // speakerId set by merge
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [known, unattributed]),
        ])
        let roster = LaneTranscript.roster(
            for: merged.segments, lanes: [.room],
            diarized: [SpeakerLabel(id: "room-S1", displayName: "Room 1", speechMs: 1000)]
        )
        XCTAssertEqual(roster.map(\.id), ["room-S1", "room"])
        XCTAssertEqual(roster.map(\.displayName), ["Room 1", "Room"])
    }

    func testALaneWhoseSegmentsAreAllAttributedHasNoCatchAll() {
        var first = segment(0, 0, 1000, "a")
        first.speakerId = "room-S1"
        var second = segment(1, 2000, 3000, "b")
        second.speakerId = "room-S2"
        let merged = LaneTranscript.merge([.init(lane: .room, segments: [first, second])])
        let roster = LaneTranscript.roster(
            for: merged.segments, lanes: [.room],
            diarized: [SpeakerLabel(id: "room-S1", displayName: "Room 1"),
                       SpeakerLabel(id: "room-S2", displayName: "Room 2")]
        )
        XCTAssertEqual(roster.map(\.id), ["room-S1", "room-S2"])
    }

    func testASpeakerNoSegmentUsesIsNotListed() {
        // The diarizer found three people; the merge gave segments to two.
        // Listing the third invents a participant.
        var only = segment(0, 0, 1000, "a")
        only.speakerId = "remote-S1"
        let merged = LaneTranscript.merge([.init(lane: .remote, segments: [only])])
        let roster = LaneTranscript.roster(
            for: merged.segments, lanes: [.remote],
            diarized: [SpeakerLabel(id: "remote-S1", displayName: "Remote 1"),
                       SpeakerLabel(id: "remote-S2", displayName: "Remote 2")]
        )
        XCTAssertEqual(roster.map(\.id), ["remote-S1"])
    }

    func testTheRosterKeepsEachLaneTogether() {
        var roomPerson = segment(0, 0, 1000, "a")
        roomPerson.speakerId = "room-S1"
        let merged = LaneTranscript.merge([
            .init(lane: .room, segments: [roomPerson, segment(1, 5000, 6000, "b")]),
            .init(lane: .remote, segments: [segment(0, 2000, 3000, "c")]),
        ])
        let roster = LaneTranscript.roster(
            for: merged.segments, lanes: [.room, .remote],
            diarized: [SpeakerLabel(id: "room-S1", displayName: "Room 1")]
        )
        XCTAssertEqual(roster.map(\.id), ["room-S1", "room", "remote"])
    }

    func testRosterSpeechIsCountedFromTheSegments() {
        var tagged = segment(0, 0, 2000, "a")
        tagged.speakerId = "room-S1"
        let merged = LaneTranscript.merge([.init(lane: .room, segments: [tagged])])
        let roster = LaneTranscript.roster(
            for: merged.segments, lanes: [.room],
            diarized: [SpeakerLabel(id: "room-S1", displayName: "Room 1", speechMs: 999)]
        )
        XCTAssertEqual(roster.first?.speechMs, 2000)
    }

    private func segment(_ index: Int, _ start: Int, _ end: Int, _ text: String) -> Segment {
        Segment(index: index, startMs: start, endMs: end, text: text)
    }
}
