import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// Speaker names and assignments that a person made, through the things that
/// run again without asking: identifying speakers again, transcribing again,
/// and a restart.
@MainActor
final class SpeakerPersistenceTests: XCTestCase {

    private var scratch: URL!
    private var storeURL: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        storeURL = scratch.appendingPathComponent("t.store")
        container = try open()
    }

    override func tearDown() async throws {
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    private func open() throws -> ModelContainer {
        let schema = Schema(TranscriberSchema.models)
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: storeURL)
        ])
    }

    private let roster = [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 9_000),
                          SpeakerLabel(id: "S2", displayName: "Speaker 2", speechMs: 6_000)]

    /// Six lines, S1 S2 S1 S2 S1 S2, stored through the writer as a finished
    /// transcript. Returns the recording id.
    private func seedDiarized() async throws -> (id: UUID, writer: TranscriptWriter) {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        let segments = (0..<6).map {
            Segment(index: $0, startMs: $0 * 5_000, endMs: $0 * 5_000 + 4_000,
                    text: "line \($0)", speakerId: $0.isMultiple(of: 2) ? "S1" : "S2")
        }
        try await writer.storeTranscript(segments: segments, roster: roster, modelId: "turbo",
                                         language: "tl", processMs: 1, didDiarize: true, for: id)
        return (id, writer)
    }

    private func recording(_ id: UUID, in context: ModelContext? = nil) throws -> StoredRecording {
        let context = context ?? ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    private func names(_ recording: StoredRecording) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (recording.speakers ?? []).map { ($0.speakerId, $0.displayName) })
    }

    private func spans(_ ids: [String]) -> [SpeakerSpan] {
        ids.enumerated().map {
            SpeakerSpan(speakerId: $0.element, startMs: $0.offset * 5_000,
                        endMs: $0.offset * 5_000 + 4_500, quality: 1)
        }
    }

    // MARK: - Identifying speakers again

    func testARenameSurvivesIdentifyingSpeakersAgainWhileTheLabelStays() async throws {
        let (id, writer) = try await seedDiarized()
        let context = container.mainContext
        let live = try recording(id, in: context)
        let s1 = try XCTUnwrap(live.speakers?.first { $0.speakerId == "S1" })
        try RecordingStore.rename(s1, to: "Maria", in: context)

        try await writer.applySpeakers(spans: spans(["S1", "S2", "S1", "S2", "S1", "S2"]),
                                       roster: roster, for: id)

        let after = try recording(id)
        XCTAssertEqual(names(after)["S1"], "Maria", "an automatic re-run must not take a name back")
        XCTAssertEqual(names(after)["S2"], "Speaker 2")
    }

    func testEveryLineCarriesALabelThatTheRosterKnowsAfterIdentifyingAgain() async throws {
        let (id, writer) = try await seedDiarized()

        // The new pass hears one speaker only.
        try await writer.applySpeakers(
            spans: spans(["S1", "S1", "S1", "S1", "S1", "S1"]),
            roster: [SpeakerLabel(id: "S1", displayName: "Speaker 1", speechMs: 24_000)], for: id)

        let after = try recording(id)
        let known = Set((after.speakers ?? []).map(\.speakerId))
        let used = Set((after.transcript?.orderedSegments ?? []).compactMap(\.speakerId))
        XCTAssertTrue(used.isSubset(of: known),
                      "a line points at \(used.subtracting(known)), which the roster no longer lists")
        XCTAssertEqual(known, ["S1"], "no ghost left from the earlier pass")
    }

    func testAnEmptyIdentificationDoesNotWipeTheNamesOrTheLabels() async throws {
        // A pass that finds no speech at all returns no spans and no roster.
        // Applying that literally took every label off every line and deleted
        // every name a person had typed.
        let (id, writer) = try await seedDiarized()
        let context = container.mainContext
        let s2 = try XCTUnwrap(try recording(id, in: context).speakers?.first { $0.speakerId == "S2" })
        try RecordingStore.rename(s2, to: "Juan", in: context)

        try await writer.applySpeakers(spans: [], roster: [], for: id)

        let after = try recording(id)
        XCTAssertEqual(names(after)["S2"], "Juan")
        XCTAssertEqual(after.transcript?.orderedSegments.compactMap(\.speakerId).count, 6,
                       "the lines keep their labels")
    }

    // MARK: - Transcribing again

    func testARenameSurvivesTranscribingAgainWhenTheNewRunIdentifiesSpeakers() async throws {
        let (id, writer) = try await seedDiarized()
        let context = container.mainContext
        let s1 = try XCTUnwrap(try recording(id, in: context).speakers?.first { $0.speakerId == "S1" })
        try RecordingStore.rename(s1, to: "Maria", in: context)

        let again = (0..<6).map {
            Segment(index: $0, startMs: $0 * 5_000, endMs: $0 * 5_000 + 4_000, text: "again \($0)",
                    speakerId: $0.isMultiple(of: 2) ? "S1" : "S2")
        }
        try await writer.storeTranscript(segments: again, roster: roster, modelId: "large",
                                         language: "tl", processMs: 1, didDiarize: true, for: id)

        let after = try recording(id)
        XCTAssertEqual(after.transcript?.revision, 2)
        XCTAssertEqual(names(after)["S1"], "Maria")
    }

    func testTranscribingAgainWithoutSpeakerIdentificationKeepsTheNamesAPersonChose() async throws {
        // Speaker identification set to Off in Settings, then Transcribe Again.
        // The roster comes back empty, and an empty roster deleted every
        // speaker row, names included. The earlier revision still points at
        // those labels, and Identify Speakers Again later starts from nothing.
        let (id, writer) = try await seedDiarized()
        let context = container.mainContext
        let s1 = try XCTUnwrap(try recording(id, in: context).speakers?.first { $0.speakerId == "S1" })
        try RecordingStore.rename(s1, to: "Maria", in: context)

        let plain = (0..<6).map {
            Segment(index: $0, startMs: $0 * 5_000, endMs: $0 * 5_000 + 4_000, text: "plain \($0)")
        }
        try await writer.storeTranscript(segments: plain, roster: [], modelId: "large",
                                         language: "tl", processMs: 1, didDiarize: false, for: id)

        XCTAssertEqual(names(try recording(id))["S1"], "Maria")
    }

    // MARK: - A restart

    func testNamesAndReassignmentsSurviveAClosedAndReopenedStore() async throws {
        let (id, _) = try await seedDiarized()
        var context: ModelContext? = container.mainContext
        let live = try recording(id, in: context)
        let s1 = try XCTUnwrap(live.speakers?.first { $0.speakerId == "S1" })
        let s2 = try XCTUnwrap(live.speakers?.first { $0.speakerId == "S2" })
        try RecordingStore.rename(s1, to: "Maria", in: context!)
        let rows = try XCTUnwrap(live.transcript?.orderedSegments)
        try RecordingStore.assign([rows[0], rows[2]], to: s2, on: live, in: context!)
        context = nil
        container = nil

        // The app starts again: a new container on the same file.
        container = try open()
        let reopened = try recording(id)
        XCTAssertEqual(names(reopened), ["S1": "Maria", "S2": "Speaker 2"])
        let labels = reopened.transcript?.orderedSegments.map(\.speakerId)
        XCTAssertEqual(labels, ["S2", "S2", "S2", "S2", "S1", "S2"],
                       "lines 0 and 2 were moved to Speaker 2 by hand")
        let talk = Dictionary(uniqueKeysWithValues: (reopened.speakers ?? []).map { ($0.speakerId, $0.speechMs) })
        XCTAssertEqual(talk["S1"], 9_000 - 8_000, "talk time moved with the lines")
    }

    // MARK: - Merging, then identifying again

    func testMergedAwaySpeakerComesBackWithItsDefaultNameAndAnEvenSplitDoesNotInheritTheTargetsName() async throws {
        let (id, writer) = try await seedDiarized()
        let context = container.mainContext
        let live = try recording(id, in: context)
        let s1 = try XCTUnwrap(live.speakers?.first { $0.speakerId == "S1" })
        let s2 = try XCTUnwrap(live.speakers?.first { $0.speakerId == "S2" })
        try RecordingStore.rename(s1, to: "Maria", in: context)
        try RecordingStore.rename(s2, to: "Juan", in: context)
        try RecordingStore.merge(s2, into: s1, in: context)
        XCTAssertEqual(names(try recording(id)), ["S1": "Maria"])

        try await writer.applySpeakers(spans: spans(["S1", "S2", "S1", "S2", "S1", "S2"]),
                                       roster: roster, for: id)

        // Documented: a new pass starts from a fresh roster. The name of the
        // speaker that was merged away is gone, and the new S2 is a new person.
        // Maria now holds every line, and the new run splits them three and
        // three: which half is Maria is a coin flip, so neither inherits her
        // name. It stays in the roster, with no lines, for a person to place.
        let after = try recording(id)
        XCTAssertEqual(Set(names(after).values), ["Maria", "Speaker 2", "Speaker 3"])
        XCTAssertEqual(names(after)["S1"], "Maria", "the name keeps its label")
        XCTAssertEqual(after.speakers?.first { $0.speakerId == "S1" }?.speechMs, 0)
        let lines = Set((after.transcript?.orderedSegments ?? []).compactMap(\.speakerId))
        XCTAssertFalse(lines.contains("S1"), "no line is given to Maria by a guess")
    }
}
