import SwiftData
import XCTest
import TranscriberCore
@testable import TranscriberStore

@MainActor
final class NotesApplyTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = try StoreContainer.ephemeral()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testAppliedItemsFollowTheExistingOnesAndKeepTheirLinks() throws {
        let context = container.mainContext
        let recording = try RecordingStore.create(kind: .meeting, title: "Taxonomy", in: context)
        try RecordingStore.addItem(.decision, text: "Hand-written first", to: recording, in: context)
        let segmentId = UUID()

        let added = try RecordingStore.apply([
            NotesDraft.Item(kind: .decision, text: " Colour is an attribute. ", sourceMs: 4_000, sourceSegmentId: segmentId),
            NotesDraft.Item(kind: .actionItem, text: "Send the sheet.", sourceMs: 9_000),
            NotesDraft.Item(kind: .question, text: "   "),
        ], summary: nil, to: recording, in: context)
        XCTAssertEqual(added, 3, "counts what it was handed; the blank one is not written")

        let decisions = RecordingStore.items(.decision, of: recording)
        XCTAssertEqual(decisions.map(\.text), ["Hand-written first", "Colour is an attribute."])
        XCTAssertEqual(decisions.map(\.order), [0, 1])
        XCTAssertEqual(decisions[1].sourceMs, 4_000)
        XCTAssertEqual(decisions[1].sourceSegmentId, segmentId)
        XCTAssertEqual(RecordingStore.items(.actionItem, of: recording).map(\.order), [0])
        XCTAssertTrue(RecordingStore.items(.question, of: recording).isEmpty)
        XCTAssertTrue(recording.searchText.contains("Colour is an attribute."))
    }

    func testTheSummaryIsReplacedOnlyWhenOneIsGiven() throws {
        let context = container.mainContext
        let recording = try RecordingStore.create(kind: .meeting, title: "Taxonomy", in: context)
        recording.summary = "Written by hand."

        try RecordingStore.apply([], summary: nil, to: recording, in: context)
        XCTAssertEqual(recording.summary, "Written by hand.")

        try RecordingStore.apply([], summary: "  Written by the model. ", to: recording, in: context)
        XCTAssertEqual(recording.summary, "Written by the model.")
        XCTAssertTrue(recording.searchText.contains("Written by the model."))
    }
}
