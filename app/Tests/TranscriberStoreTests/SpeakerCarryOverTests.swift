import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A name a person typed belongs to a voice, not to a label number.
///
/// Segments hold the diarizer's label (`S1`) and the name lives on the row for
/// that label. The app numbers the speakers by who speaks first, and the
/// number can change between two runs over the same audio: the opening turn is
/// under a second and one run drops it, or a head-count changes which voices
/// fuse. Applied literally, a new run moves "Maria" to whoever is `S1` now.
///
/// Every test here runs the diarizer's answer through `applySpeakers`, which is
/// what Identify Speakers Again does. The lines sit at 5 s steps, 4 s long, and
/// the spans cover each line, so the overlap between an old line and a new span
/// is exact and nothing depends on the clock or the machine.
@MainActor
final class SpeakerCarryOverTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-carry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let schema = Schema(TranscriberSchema.models)
        container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: scratch.appendingPathComponent("t.store"))
        ])
    }

    override func tearDown() async throws {
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private let stepMs = 5_000
    private let lineMs = 4_000

    /// A finished transcript with one line per entry, labelled as given. The
    /// roster is every distinct label, numbered and coloured in order.
    private func seed(_ labels: [String?]) async throws -> (id: UUID, writer: TranscriptWriter) {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let segments = labels.enumerated().map { offset, label in
            Segment(index: offset, startMs: offset * stepMs, endMs: offset * stepMs + lineMs,
                    text: "line \(offset)", speakerId: label)
        }
        let roster = Self.roster(of: labels, lineMs: lineMs)
        try await writer.storeTranscript(segments: segments, roster: roster, modelId: "turbo",
                                         language: "en", processMs: 1, didDiarize: true, for: id)
        return (id, writer)
    }

    private static func roster(of labels: [String?], lineMs: Int) -> [SpeakerLabel] {
        var seen: [String] = []
        for case let label? in labels where !seen.contains(label) { seen.append(label) }
        return seen.map { label in
            SpeakerLabel(id: label, displayName: SpeakerLabel.defaultName(for: label),
                         speechMs: labels.filter { $0 == label }.count * lineMs)
        }
    }

    /// What the diarizer says about the same audio: one span per entry, nil for
    /// "heard nobody".
    private func spans(_ labels: [String?]) -> [SpeakerSpan] {
        labels.enumerated().compactMap { offset, label in
            label.map {
                SpeakerSpan(speakerId: $0, startMs: offset * stepMs,
                            endMs: offset * stepMs + stepMs - 500, quality: 1)
            }
        }
    }

    @discardableResult
    private func identifyAgain(_ writer: TranscriptWriter, _ id: UUID,
                               _ labels: [String?]) async throws -> Bool {
        try await writer.applySpeakers(spans: spans(labels),
                                       roster: Self.roster(of: labels, lineMs: lineMs), for: id)
    }

    private func rename(_ speakerId: String, to name: String, in id: UUID) throws {
        let context = container.mainContext
        let speaker = try XCTUnwrap(try recording(id, in: context).speakers?
            .first { $0.speakerId == speakerId })
        try RecordingStore.rename(speaker, to: name, in: context)
    }

    private func recording(_ id: UUID, in context: ModelContext? = nil) throws -> StoredRecording {
        let context = context ?? ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    /// The name each line ends up under, by position. nil is "nobody".
    private func namesOnLines(_ id: UUID) throws -> [String?] {
        let after = try recording(id)
        let byLabel = Dictionary((after.speakers ?? []).map { ($0.speakerId, $0.displayName) },
                                 uniquingKeysWith: { first, _ in first })
        return (after.transcript?.orderedSegments ?? []).map { row in
            row.speakerId.map { byLabel[$0] ?? "UNKNOWN LABEL \($0)" }
        }
    }

    private func speakerRows(_ id: UUID) throws -> [String: StoredSpeaker] {
        Dictionary((try recording(id).speakers ?? []).map { ($0.speakerId, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Every line points at a label the roster lists.
    private func assertNoLineIsOrphaned(_ id: UUID, file: StaticString = #filePath,
                                        line: UInt = #line) throws {
        let after = try recording(id)
        let known = Set((after.speakers ?? []).map(\.speakerId))
        let used = Set((after.transcript?.orderedSegments ?? []).compactMap(\.speakerId))
        XCTAssertTrue(used.isSubset(of: known),
                      "lines point at \(used.subtracting(known)), which the roster does not list",
                      file: file, line: line)
    }

    // MARK: - Swapped labels

    func testANameFollowsItsVoiceWhenTheNewRunNumbersTheSpeakersTheOtherWayRound() async throws {
        // Maria speaks on lines 0, 2, 4; Juan on 1, 3, 5. The new run drops
        // Maria's opening turn, so Juan opens and is numbered S1.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)

        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S2", "S1"])

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Speaker 2"],
                       "the name stayed with the voice that was given it")
        try assertNoLineIsOrphaned(id)
    }

    func testAColourFollowsItsVoiceToo() async throws {
        // The new run drops Maria's opening line, so Juan is heard first and the
        // roster comes back in the other order. The colour of a row is its place
        // in that roster, so without care Maria is painted in Juan's colour.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        let before = try speakerRows(id)
        let mariaColour = try XCTUnwrap(before["S1"]).colorIndex
        let juanColour = try XCTUnwrap(before["S2"]).colorIndex
        XCTAssertNotEqual(mariaColour, juanColour)

        try await identifyAgain(writer, id, [nil, "S1", "S2", "S1", "S2", "S1"])

        let rows = try recording(id).speakers ?? []
        XCTAssertEqual(rows.first { $0.displayName == "Maria" }?.colorIndex, mariaColour)
        XCTAssertEqual(rows.first { $0.displayName == "Speaker 2" }?.colorIndex, juanColour)
        XCTAssertEqual(Set(rows.map(\.colorIndex)).count, rows.count, "no two people share a colour")
    }

    func testANewSpeakerIsNeverGivenAColourAnotherSpeakerKeeps() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", nil, nil])
        let before = try speakerRows(id)

        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S3", "S3"])

        let rows = try recording(id).speakers ?? []
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.colorIndex)).count, 3, "three people, three colours")
        XCTAssertEqual(rows.first { $0.speakerId == "S1" }?.colorIndex, before["S1"]?.colorIndex)
        XCTAssertEqual(rows.first { $0.speakerId == "S2" }?.colorIndex, before["S2"]?.colorIndex)
    }

    func testTheTalkTimeStaysWithTheNameAfterASwap() async throws {
        // Maria 3 lines, Juan 2: the totals must not trade places with the labels.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1"])
        try rename("S1", to: "Maria", in: id)

        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S2"])

        let rows = try recording(id).speakers ?? []
        XCTAssertEqual(rows.first { $0.displayName == "Maria" }?.speechMs, 3 * lineMs)
        XCTAssertEqual(rows.first { $0.displayName == "Speaker 2" }?.speechMs, 2 * lineMs)
    }

    // MARK: - A speaker that disappeared

    func testASpeakerTheNewRunDidNotFindKeepsItsNameAndNobodyInheritsIt() async throws {
        // Maria, Juan and Ana take turns. The new run finds Maria and Ana only,
        // so Ana is numbered S2, which used to be Juan.
        let old: [String?] = ["S1", "S2", "S3", "S1", "S2", "S3", "S1", "S2", "S3"]
        let (id, writer) = try await seed(old)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)

        try await identifyAgain(writer, id, ["S1", nil, "S2", "S1", nil, "S2", "S1", nil, "S2"])

        let lines = try namesOnLines(id)
        XCTAssertEqual(lines[0], "Maria")
        XCTAssertEqual(lines[2], "Speaker 3", "Ana is not Juan, whatever number she is now")
        XCTAssertEqual(lines[5], "Speaker 3")
        XCTAssertNil(lines[1], "nobody spoke there, as far as the new run knows")
        XCTAssertEqual(try recording(id).speakers?.first { $0.displayName == "Juan" }?.speechMs, 0,
                       "Juan's name is still there to hand back, with no lines")
        try assertNoLineIsOrphaned(id)
    }

    // MARK: - A new speaker

    func testANewSpeakerStartsWithADefaultNameAndTakesNobodysName() async throws {
        // Lines 6 and 7 had no label before; the new run hears a third person
        // there, and also numbers Juan first.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2", nil, nil])
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)

        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S2", "S1", "S3", "S3"])

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Juan", "Maria", "Juan", "Maria", "Juan",
                        "Speaker 3", "Speaker 3"])
        let ids = try recording(id).speakers.map { Set($0.map(\.speakerId)) }
        XCTAssertEqual(ids?.count, 3)
        try assertNoLineIsOrphaned(id)
    }

    // MARK: - Two speakers merging

    func testTwoVoicesTheDiarizerFusedAreNotGivenEitherName() async throws {
        // Maria and Juan alternate for eight lines; Ana speaks the last four.
        // The new run hears Maria and Juan as one person.
        var old = [String?](repeating: nil, count: 12)
        for index in 0..<8 { old[index] = index.isMultiple(of: 2) ? "S1" : "S2" }
        for index in 8..<12 { old[index] = "S3" }
        let (id, writer) = try await seed(old)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        try rename("S3", to: "Ana", in: id)

        let fused = (0..<12).map { $0 < 8 ? "S1" : "S2" }
        try await identifyAgain(writer, id, fused)

        let lines = try namesOnLines(id)
        XCTAssertEqual(Set(lines[8...]), ["Ana"], "Ana is the one unambiguous match")
        let fusedName = try XCTUnwrap(lines[0])
        XCTAssertNotEqual(fusedName, "Maria", "half of those lines are Juan's")
        XCTAssertNotEqual(fusedName, "Juan", "half of those lines are Maria's")
        let kept = Set((try recording(id).speakers ?? []).map(\.displayName))
        XCTAssertTrue(kept.isSuperset(of: ["Maria", "Juan", "Ana"]),
                      "no rename is deleted because the diarizer was unsure: \(kept)")
        try assertNoLineIsOrphaned(id)
    }

    func testAFusedSpeakerMostlyOneVoiceInheritsThatVoicesName() async throws {
        // Maria 6 lines, Juan 2: fused, the new speaker is three quarters Maria.
        var old = [String?](repeating: nil, count: 12)
        for index in 0..<8 { old[index] = [1, 5].contains(index) ? "S2" : "S1" }
        for index in 8..<12 { old[index] = "S3" }
        let (id, writer) = try await seed(old)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)

        try await identifyAgain(writer, id, (0..<12).map { $0 < 8 ? "S1" : "S2" })

        XCTAssertEqual(try namesOnLines(id)[0], "Maria")
        XCTAssertEqual(try recording(id).speakers?.first { $0.displayName == "Juan" }?.speechMs, 0,
                       "Juan is kept, with no lines, rather than deleted")
    }

    // MARK: - One speaker splitting in two

    func testASplitSpeakerGivesItsNameToTheLargerHalf() async throws {
        // Maria's eight lines come back as six and two. Juan's are untouched.
        var old = [String?](repeating: nil, count: 16)
        for index in 0..<8 { old[index] = "S1" }
        for index in 8..<16 { old[index] = "S2" }
        let (id, writer) = try await seed(old)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)

        let split: [String?] = (0..<16).map { $0 < 6 ? "S1" : ($0 < 8 ? "S3" : "S2") }
        try await identifyAgain(writer, id, split)

        let lines = try namesOnLines(id)
        XCTAssertEqual(Array(lines[0..<6]), Array(repeating: "Maria", count: 6))
        XCTAssertEqual(Array(lines[8..<16]), Array(repeating: "Juan", count: 8))
        XCTAssertEqual(Array(lines[6..<8]), ["Speaker 3", "Speaker 3"],
                       "the smaller half is a speaker nobody has named")
        try assertNoLineIsOrphaned(id)
    }

    func testAnEvenSplitGivesItsNameToNeitherHalf() async throws {
        var old = [String?](repeating: nil, count: 16)
        for index in 0..<8 { old[index] = "S1" }
        for index in 8..<16 { old[index] = "S2" }
        let (id, writer) = try await seed(old)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)

        let split: [String?] = (0..<16).map { $0 < 4 ? "S1" : ($0 < 8 ? "S3" : "S2") }
        try await identifyAgain(writer, id, split)

        let lines = try namesOnLines(id)
        XCTAssertFalse(lines[0..<8].contains("Maria"), "a coin flip would be a wrong name half the time")
        XCTAssertEqual(Array(lines[8..<16]), Array(repeating: "Juan", count: 8))
        XCTAssertNotNil(try recording(id).speakers?.first { $0.displayName == "Maria" },
                        "the name is kept for the person to place by hand")
        try assertNoLineIsOrphaned(id)
    }

    // MARK: - What must not change

    func testAnUnchangedRunLeavesEverythingWhereItWas() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        let colours = try speakerRows(id).mapValues(\.colorIndex)

        try await identifyAgain(writer, id, ["S1", "S2", "S1", "S2", "S1", "S2"])

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Speaker 2"])
        XCTAssertEqual(try speakerRows(id).mapValues(\.colorIndex), colours)
        XCTAssertEqual(Set(try speakerRows(id).keys), ["S1", "S2"])
    }

    func testTheFirstSpeakerPassOverALiveTranscriptJustLabelsTheLines() async throws {
        // Nothing was attributed yet, so there is nothing to match against:
        // the new numbering is used as it comes.
        let (id, writer) = try await seed([nil, nil, nil, nil])
        let labels: [String?] = ["S1", "S2", "S1", "S2"]
        try await writer.applySpeakers(
            spans: spans(labels),
            roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 8_000),
                     SpeakerLabel(id: "S2", displayName: "Speaker 2", speechMs: 8_000)], for: id)

        XCTAssertEqual(try recording(id).transcript?.orderedSegments.map(\.speakerId), labels)
        XCTAssertEqual(Set(try speakerRows(id).keys), ["S1", "S2"])
    }

    func testTheTextAPersonEditedIsNeverTouched() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2"])
        let context = container.mainContext
        let rows = try XCTUnwrap(try recording(id, in: context).transcript?.orderedSegments)
        rows[0].textClean = "Maria's own wording"
        try context.save()

        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1"])

        let after = try XCTUnwrap(try recording(id).transcript?.orderedSegments)
        XCTAssertEqual(after.map(\.text), ["line 0", "line 1", "line 2", "line 3"])
        XCTAssertEqual(after[0].textClean, "Maria's own wording")
        XCTAssertEqual(after.map(\.startMs), [0, 5_000, 10_000, 15_000])
    }

    func testAPersonsRenameIsNeverDeletedByAnyOfTheseOutcomes() async throws {
        // The strictest reading of "never delete a rename": whatever the new
        // run looks like, the typed names are still in the roster afterwards.
        let old: [String?] = ["S1", "S2", "S3", "S1", "S2", "S3"]
        let outcomes: [[String?]] = [
            ["S1", "S1", "S1", "S1", "S1", "S1"],       // everyone fused
            ["S3", "S2", "S1", "S3", "S2", "S1"],       // reversed
            [nil, nil, nil, nil, nil, "S1"],            // almost nothing heard
            ["S1", "S2", "S4", "S1", "S2", "S4"],       // a fourth label for the third voice
        ]
        for outcome in outcomes {
            let (id, writer) = try await seed(old)
            try rename("S1", to: "Maria", in: id)
            try rename("S2", to: "Juan", in: id)
            try rename("S3", to: "Ana", in: id)

            try await identifyAgain(writer, id, outcome)

            let kept = Set((try recording(id).speakers ?? []).map(\.displayName))
            XCTAssertTrue(kept.isSuperset(of: ["Maria", "Juan", "Ana"]),
                          "outcome \(outcome.map { $0 ?? "-" }) lost a name: \(kept)")
            try assertNoLineIsOrphaned(id)
        }
    }

    // MARK: - Transcribing again

    /// A run of lines as Transcribe Again produces them: new text, new labels.
    private func transcribedAgain(_ labels: [String?]) -> [Segment] {
        labels.enumerated().map { offset, label in
            Segment(index: offset, startMs: offset * stepMs, endMs: offset * stepMs + lineMs,
                    text: "again \(offset)", speakerId: label)
        }
    }

    func testTranscribingAgainStoresTheNewLinesUnderTheLabelsAPersonNamed() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        let labels: [String?] = ["S2", "S1", "S2", "S1", "S2", "S1"]

        let carried = try await writer.carriedSpeakers(
            segments: transcribedAgain(labels),
            roster: Self.roster(of: labels, lineMs: lineMs), for: id)

        XCTAssertEqual(carried.segments.map(\.speakerId),
                       ["S1", "S2", "S1", "S2", "S1", "S2"], "Maria's lines stay S1")
        XCTAssertEqual(carried.segments.map(\.text).first, "again 0", "the text is the new text")
        XCTAssertEqual(Set(carried.roster.map(\.id)), ["S1", "S2"])
        XCTAssertEqual(carried.roster.first { $0.id == "S1" }?.speechMs, 3 * lineMs)
    }

    func testTranscribingAgainKeepsTheOldNamesOfWhoeverTheRunDidNotFind() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S3", "S1", "S2", "S3"])
        try rename("S2", to: "Juan", in: id)
        let labels: [String?] = ["S1", nil, "S2", "S1", nil, "S2"]   // Juan is not heard

        let carried = try await writer.carriedSpeakers(
            segments: transcribedAgain(labels),
            roster: Self.roster(of: labels, lineMs: lineMs), for: id)

        XCTAssertEqual(carried.segments.map(\.speakerId), ["S1", nil, "S3", "S1", nil, "S3"])
        let kept = try XCTUnwrap(carried.roster.first { $0.displayName == "Juan" })
        XCTAssertEqual(kept.id, "S2")
        XCTAssertEqual(kept.speechMs, 0)
    }

    func testTranscribingAgainWithNothingEarlierPassesTheLabelsThrough() async throws {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let labels: [String?] = ["S2", "S1", "S2"]
        let segments = transcribedAgain(labels)
        let roster = Self.roster(of: labels, lineMs: lineMs)

        let carried = try await writer.carriedSpeakers(segments: segments, roster: roster, for: id)

        XCTAssertEqual(carried.segments, segments)
        XCTAssertEqual(carried.roster, roster)
    }

    func testTranscribingAgainWithoutSpeakersChangesNothing() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2"])
        let segments = transcribedAgain([nil, nil, nil, nil])

        let carried = try await writer.carriedSpeakers(segments: segments, roster: [], for: id)

        XCTAssertEqual(carried.segments, segments)
        XCTAssertTrue(carried.roster.isEmpty, "an empty roster stays empty, so nothing is pruned")
    }

    func testAnOpenPartialRevisionIsNeverTheEvidence() async throws {
        // A job that is still decoding (or died part-way) has rows and no
        // speakers. The newest revision is that one; the evidence is the
        // newest that finished.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        _ = try await writer.openPartialTranscript(modelId: "turbo", language: "en", for: id)
        let labels: [String?] = ["S2", "S1", "S2", "S1"]

        let carried = try await writer.carriedSpeakers(
            segments: transcribedAgain(labels),
            roster: Self.roster(of: labels, lineMs: lineMs), for: id)

        XCTAssertEqual(carried.segments.map(\.speakerId), ["S1", "S2", "S1", "S2"])
    }

    func testTheRevisionBeingWrittenIsNotTheEvidence() async throws {
        // `storeTranscript` inserts the new revision, finished and empty, before
        // its rows are decided. Taken for the earlier run it would match nothing.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        try await writer.storeTranscript(segments: [], roster: [], modelId: "turbo",
                                         language: "en", processMs: 1, didDiarize: false, for: id)
        let newest = try XCTUnwrap(try recording(id).transcript)
        XCTAssertEqual(newest.revision, 2)
        XCTAssertTrue(newest.isComplete, "this is what makes it look like evidence")
        let labels: [String?] = ["S2", "S1", "S2", "S1"]
        let roster = Self.roster(of: labels, lineMs: lineMs)

        let ignored = try await writer.carriedSpeakers(
            segments: transcribedAgain(labels), roster: roster, for: id)
        XCTAssertEqual(ignored.segments.map(\.speakerId), labels,
                       "with the empty revision as evidence there is nothing to match")

        let carried = try await writer.carriedSpeakers(
            segments: transcribedAgain(labels), roster: roster, for: id, excluding: [newest.id])
        XCTAssertEqual(carried.segments.map(\.speakerId), ["S1", "S2", "S1", "S2"])
    }
}
