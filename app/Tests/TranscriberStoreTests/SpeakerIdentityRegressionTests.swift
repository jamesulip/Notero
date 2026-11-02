import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// Speaker identity through the paths and the combinations the other speaker
/// tests do not walk: a merge or a hand-made speaker that has to outlive a
/// restart and a re-run, a rename followed by a reassignment, a re-run and a
/// restart in one go, Transcribe Again with identification off followed by
/// Identify Speakers Again, and a single turn decoded again.
///
/// Every test also checks what none of these operations may do: change a
/// line's start or end, put the lines out of order, or point a line at a
/// label the roster does not list.
///
/// The store is a file in a scratch folder, so a restart is a new container
/// on the same file. Lines sit at 5 s steps, 4 s long; a diarizer span covers
/// 4.5 s of each step. Nothing depends on the clock or the machine.
@MainActor
final class SpeakerIdentityRegressionTests: XCTestCase {

    private var scratch: URL!
    private var storeURL: URL!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaker-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        storeURL = scratch.appendingPathComponent("t.store")
        container = try open()
    }

    override func tearDown() async throws {
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private let stepMs = 5_000
    private let lineMs = 4_000

    private func open() throws -> ModelContainer {
        let schema = Schema(TranscriberSchema.models)
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: storeURL)
        ])
    }

    /// Quits and starts again: every context and the container go, and a new
    /// container opens the same file. Returns a writer on the new container.
    private func restart() throws -> TranscriptWriter {
        container = nil
        container = try open()
        return TranscriptWriter(modelContainer: container)
    }

    private func lines(_ labels: [String?], text: String) -> [Segment] {
        labels.enumerated().map { offset, label in
            Segment(index: offset, startMs: offset * stepMs, endMs: offset * stepMs + lineMs,
                    text: "\(text) \(offset)", speakerId: label)
        }
    }

    private func roster(_ labels: [String?]) -> [SpeakerLabel] {
        var seen: [String] = []
        for case let label? in labels where !seen.contains(label) { seen.append(label) }
        return seen.map { label in
            SpeakerLabel(id: label, displayName: SpeakerLabel.defaultName(for: label),
                         speechMs: labels.filter { $0 == label }.count * lineMs)
        }
    }

    private func spans(_ labels: [String?]) -> [SpeakerSpan] {
        labels.enumerated().compactMap { offset, label in
            label.map {
                SpeakerSpan(speakerId: $0, startMs: offset * stepMs,
                            endMs: offset * stepMs + stepMs - 500, quality: 1)
            }
        }
    }

    private func seed(_ labels: [String?]) async throws -> (id: UUID, writer: TranscriptWriter) {
        let id = try RecordingStore.create(kind: .meeting, in: container.mainContext).id
        let writer = TranscriptWriter(modelContainer: container)
        try await writer.storeTranscript(segments: lines(labels, text: "first"),
                                         roster: roster(labels), modelId: "turbo",
                                         language: "en", processMs: 1, didDiarize: true, for: id)
        return (id, writer)
    }

    private func identifyAgain(_ writer: TranscriptWriter, _ id: UUID,
                               _ labels: [String?]) async throws {
        try await writer.applySpeakers(spans: spans(labels), roster: roster(labels), for: id)
    }

    private func recording(_ id: UUID, in context: ModelContext? = nil) throws -> StoredRecording {
        let context = context ?? ModelContext(container)
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    private func speaker(_ label: String, of id: UUID) throws -> StoredSpeaker {
        try XCTUnwrap(try recording(id, in: container.mainContext).speakers?
            .first { $0.speakerId == label }, "no speaker \(label)")
    }

    private func rename(_ label: String, to name: String, in id: UUID) throws {
        try RecordingStore.rename(try speaker(label, of: id), to: name, in: container.mainContext)
    }

    /// Moves lines, by position, to a speaker by hand.
    private func assign(_ positions: [Int], to label: String?, in id: UUID) throws {
        let context = container.mainContext
        let live = try recording(id, in: context)
        let rows = try XCTUnwrap(live.transcript?.orderedSegments)
        let target = try label.map { try speaker($0, of: id) }
        try RecordingStore.assign(positions.map { rows[$0] }, to: target, on: live, in: context)
    }

    private func namesOnLines(_ id: UUID) throws -> [String?] {
        let after = try recording(id)
        let byLabel = Dictionary((after.speakers ?? []).map { ($0.speakerId, $0.displayName) },
                                 uniquingKeysWith: { first, _ in first })
        return (after.transcript?.orderedSegments ?? []).map { row in
            row.speakerId.map { byLabel[$0] ?? "UNKNOWN LABEL \($0)" }
        }
    }

    private func names(_ id: UUID) throws -> Set<String> {
        Set((try recording(id).speakers ?? []).map(\.displayName))
    }

    /// The (start, end) of every line of the latest transcript, in the order
    /// the transcript gives them.
    private func timeline(_ id: UUID) throws -> [[Int]] {
        (try recording(id).transcript?.orderedSegments ?? []).map { [$0.startMs, $0.endMs] }
    }

    /// The timeline the helpers build, for `count` lines.
    private func expectedTimeline(_ count: Int) -> [[Int]] {
        (0..<count).map { [$0 * stepMs, $0 * stepMs + lineMs] }
    }

    /// Lines in time order, each with a positive length, none overlapping the
    /// next, every label known to the roster, and no two roster rows on one
    /// label.
    private func assertIntact(_ id: UUID, file: StaticString = #filePath,
                              line: UInt = #line) throws {
        let after = try recording(id)
        let rows = after.transcript?.orderedSegments ?? []
        for row in rows {
            XCTAssertLessThan(row.startMs, row.endMs, "a line lost its length", file: file, line: line)
        }
        for (a, b) in zip(rows, rows.dropFirst()) {
            XCTAssertLessThanOrEqual(a.endMs, b.startMs, "lines out of order", file: file, line: line)
            XCTAssertLessThan(a.index, b.index, "index disagrees with time", file: file, line: line)
        }
        let labels = (after.speakers ?? []).map(\.speakerId)
        XCTAssertEqual(labels.count, Set(labels).count,
                       "two roster rows share a label: \(labels)", file: file, line: line)
        let used = Set(rows.compactMap(\.speakerId))
        XCTAssertTrue(used.isSubset(of: Set(labels)),
                      "lines point at \(used.subtracting(labels)), which the roster does not list",
                      file: file, line: line)
    }

    // MARK: - Rename, reassign, identify again, restart

    func testRenameThenReassignThenIdentifyAgainThenRestartKeepsEveryNameOnItsVoice() async throws {
        let first: [String?] = ["S1", "S2", "S1", "S2", "S1", "S2", "S1", "S2"]
        let (id, writer) = try await seed(first)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        // A person decides line 1 was Maria's, not Juan's.
        try assign([1], to: "S1", in: id)
        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Maria", "Maria", "Juan", "Maria", "Juan", "Maria", "Juan"])

        // The new pass hears the same two voices, numbered the other way round.
        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S2", "S1", "S2", "S1"])
        _ = try restart()

        // The names follow the voices across the renumbering and the restart.
        // Line 1 goes back to Juan: Identify Again re-places every line and a
        // line moved by hand cannot be told from one the diarizer placed
        // (finding 28, a known gap). Neither name is lost or swapped.
        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Juan", "Maria", "Juan", "Maria", "Juan", "Maria", "Juan"])
        XCTAssertEqual(try names(id), ["Maria", "Juan"])
        XCTAssertEqual(try timeline(id), expectedTimeline(8))
        try assertIntact(id)
    }

    func testRenameThenReassignThenRestartThenTranscribeAgainKeepsTheNamesOnTheVoices() async throws {
        let first: [String?] = ["S1", "S2", "S1", "S2", "S1", "S2", "S1", "S2"]
        let (id, _) = try await seed(first)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        try assign([1], to: "S1", in: id)
        var writer = try restart()
        XCTAssertEqual(try namesOnLines(id)[1], "Maria", "the hand move survived the restart")

        let again: [String?] = ["S2", "S1", "S2", "S1", "S2", "S1", "S2", "S1"]
        try await writer.storeTranscript(segments: lines(again, text: "again"), roster: roster(again),
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: true, for: id)
        writer = try restart()

        XCTAssertEqual(try recording(id).transcript?.revision, 2)
        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Juan", "Maria", "Juan", "Maria", "Juan", "Maria", "Juan"])
        XCTAssertEqual(try names(id), ["Maria", "Juan"])
        XCTAssertEqual(try timeline(id), expectedTimeline(8))
        try assertIntact(id)
        _ = writer
    }

    // MARK: - Merge

    func testAMergeTouchesOnlyTheTwoSpeakersAndNoTimestampsAndSurvivesARestart() async throws {
        let first: [String?] = ["S1", "S2", "S3", "S1", "S2", "S3"]
        let (id, _) = try await seed(first)
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        try rename("S3", to: "Ana", in: id)

        try RecordingStore.merge(try speaker("S3", of: id), into: try speaker("S1", of: id),
                                 in: container.mainContext)
        _ = try restart()

        XCTAssertEqual(try namesOnLines(id), ["Maria", "Juan", "Maria", "Maria", "Juan", "Maria"])
        XCTAssertEqual(try names(id), ["Maria", "Juan"], "only the merged-away row went")
        let talk = Dictionary(uniqueKeysWithValues: (try recording(id).speakers ?? [])
            .map { ($0.speakerId, $0.speechMs) })
        XCTAssertEqual(talk, ["S1": 4 * lineMs, "S2": 2 * lineMs], "talk time moved, none was invented")
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }

    func testAMergeThenRestartThenTranscribeAgainOfOneVoiceKeepsTheTargetsName() async throws {
        // The repair for a diarizer that heard one person as two. The new run
        // agrees with the person: one voice. It inherits the merged name.
        let (id, _) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        try RecordingStore.merge(try speaker("S2", of: id), into: try speaker("S1", of: id),
                                 in: container.mainContext)
        let writer = try restart()

        let again: [String?] = Array(repeating: "S1", count: 6)
        try await writer.storeTranscript(segments: lines(again, text: "again"), roster: roster(again),
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: true, for: id)

        XCTAssertEqual(try namesOnLines(id), Array(repeating: "Maria", count: 6))
        XCTAssertEqual(try names(id), ["Maria"], "no speaker reappears that nobody heard")
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }

    // MARK: - A speaker made by hand

    func testASpeakerMadeByHandAndNamedSurvivesARestartAndIsFoundAgainByIdentify() async throws {
        // The diarizer heard two voices; a person heard a third at the end,
        // made a speaker for her, named her and moved her lines to her.
        let (id, _) = try await seed(["S1", "S2", "S1", "S2", "S1", "S1", "S1", "S1"])
        try rename("S1", to: "Maria", in: id)
        let ana = try RecordingStore.addSpeaker(named: "Ana", to: try recording(id, in: container.mainContext),
                                                in: container.mainContext)
        XCTAssertEqual(ana.speakerId, "S3")
        try assign([5, 6, 7], to: "S3", in: id)
        let writer = try restart()
        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Ana", "Ana", "Ana"])

        // A second pass now hears three voices, and numbers Ana's second.
        try await identifyAgain(writer, id, ["S1", "S3", "S1", "S3", "S1", "S2", "S2", "S2"])

        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Ana", "Ana", "Ana"])
        XCTAssertEqual(try timeline(id), expectedTimeline(8))
        try assertIntact(id)
    }

    // MARK: - No speaker

    func testALineTakenFromEverySpeakerKeepsItsTimesAndTheNamesStay() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        try assign([0], to: nil, in: id)
        XCTAssertEqual(try namesOnLines(id).first, .some(nil))
        XCTAssertEqual(try speaker("S1", of: id).speechMs, 2 * lineMs)

        try await identifyAgain(writer, id, ["S1", "S2", "S1", "S2", "S1", "S2"])

        // Identify Again labels the line again (it re-places every line).
        XCTAssertEqual(try namesOnLines(id),
                       ["Maria", "Speaker 2", "Maria", "Speaker 2", "Maria", "Speaker 2"])
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }

    // MARK: - Transcribe Again with identification off, then Identify Again

    func testIdentifyAgainAfterATranscribeAgainWithoutSpeakersGivesTheNamesBackToTheVoices() async throws {
        // Speaker identification off in Settings, Transcribe Again: the new
        // revision has no labels, and the names stay on rows with no lines.
        // Then the person turns identification on and runs Identify Speakers
        // Again over the same audio. The earlier revision still says which
        // stretch of the timeline was Maria's.
        let (id, _) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        var writer = try restart()
        let plain: [String?] = Array(repeating: nil, count: 6)
        try await writer.storeTranscript(segments: lines(plain, text: "plain"), roster: [],
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: false, for: id)
        XCTAssertEqual(try names(id), ["Maria", "Juan"])
        writer = try restart()

        // Same voices, numbered the other way round this time.
        try await identifyAgain(writer, id, ["S2", "S1", "S2", "S1", "S2", "S1"])

        XCTAssertEqual(try namesOnLines(id), ["Maria", "Juan", "Maria", "Juan", "Maria", "Juan"])
        XCTAssertEqual(try names(id), ["Maria", "Juan"], "no extra default-named speakers")
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }

    func testTranscribeAgainWithSpeakersAfterOneWithoutGivesTheNamesBackToTheVoices() async throws {
        // The same, with the second Transcribe Again identifying speakers
        // itself: the latest earlier revision has no labels, the one before
        // it does.
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S1", to: "Maria", in: id)
        try rename("S2", to: "Juan", in: id)
        let plain: [String?] = Array(repeating: nil, count: 6)
        try await writer.storeTranscript(segments: lines(plain, text: "plain"), roster: [],
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: false, for: id)

        let again: [String?] = ["S2", "S1", "S2", "S1", "S2", "S1"]
        try await writer.storeTranscript(segments: lines(again, text: "again"), roster: roster(again),
                                         modelId: "large", language: "en", processMs: 1,
                                         didDiarize: true, for: id)

        XCTAssertEqual(try recording(id).transcript?.revision, 3)
        XCTAssertEqual(try namesOnLines(id), ["Maria", "Juan", "Maria", "Juan", "Maria", "Juan"])
        XCTAssertEqual(try names(id), ["Maria", "Juan"], "no extra default-named speakers")
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }

    // MARK: - One turn decoded again

    func testDecodingOneTurnAgainKeepsItsSpeakerAndNameAndEveryOtherLinesTimes() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S1", "S2", "S1", "S2"])
        try rename("S2", to: "Juan", in: id)

        // Line 3 (15 s to 19 s) decoded again on another model. The queue
        // stamps the turn's own label on the new rows.
        try await writer.replaceSegments(
            fromMs: 15_000, toMs: 20_000,
            with: [Segment(index: 0, startMs: 15_100, endMs: 17_000, text: "better", speakerId: "S2"),
                   Segment(index: 1, startMs: 17_100, endMs: 18_900, text: "words", speakerId: "S2")],
            for: id)
        _ = try restart()

        XCTAssertEqual(try namesOnLines(id),
                       ["Speaker 1", "Juan", "Speaker 1", "Juan", "Juan", "Speaker 1", "Juan"])
        var expected = expectedTimeline(6)
        expected.replaceSubrange(3...3, with: [[15_100, 17_000], [17_100, 18_900]])
        XCTAssertEqual(try timeline(id), expected)
        XCTAssertEqual(try names(id), ["Speaker 1", "Juan"])
        try assertIntact(id)
    }

    // MARK: - Running the same thing twice

    func testIdentifyingAgainTwiceWithTheSameAnswerChangesNothingTheSecondTime() async throws {
        let (id, writer) = try await seed(["S1", "S2", "S3", "S1", "S2", "S3"])
        try rename("S1", to: "Maria", in: id)
        try rename("S3", to: "Ana", in: id)
        let flipped: [String?] = ["S3", "S1", "S2", "S3", "S1", "S2"]

        try await identifyAgain(writer, id, flipped)
        let once = try namesOnLines(id)
        let coloursOnce = Dictionary(uniqueKeysWithValues: (try recording(id).speakers ?? [])
            .map { ($0.displayName, $0.colorIndex) })
        let restarted = try restart()
        try await identifyAgain(restarted, id, flipped)

        XCTAssertEqual(once, ["Maria", "Speaker 2", "Ana", "Maria", "Speaker 2", "Ana"])
        XCTAssertEqual(try namesOnLines(id), once)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (try recording(id).speakers ?? [])
            .map { ($0.displayName, $0.colorIndex) }), coloursOnce)
        XCTAssertEqual(try timeline(id), expectedTimeline(6))
        try assertIntact(id)
    }
}
