import Foundation
import XCTest
import TranscriberCore
import TranscriberEngine
@testable import TranscriberFlow

@MainActor
final class NotesCoordinatorTests: XCTestCase {

    actor StubEngine: NotesGenerating {
        nonisolated let modelId = "stub"
        let outcome: Result<Void, NotesError>
        let delayMs: Int
        init(outcome: Result<Void, NotesError> = .success(()), delayMs: Int = 0) {
            self.outcome = outcome
            self.delayMs = delayMs
        }
        func availability() async -> NotesAvailability { .available }
        func notes(for chunk: NotesChunk, style: NotesStyle) async throws -> ChunkNotes {
            if delayMs > 0 { try await Task.sleep(for: .milliseconds(delayMs)) }
            try outcome.get()
            return ChunkNotes(summary: "Part.", items: [
                ChunkNotes.Item(kind: .actionItem, text: "Do the thing", at: chunk.lines[0].stamp),
            ])
        }
        func summary(partSummaries: [String], title: String, style: NotesStyle) async throws -> String {
            "Whole."
        }
    }

    private let segments = (0..<4).map { i in
        Segment(index: i, startMs: i * 5_000, endMs: i * 5_000 + 4_000, text: "Line \(i)", speakerId: "S1")
    }

    private func settle(_ coordinator: NotesCoordinator, _ id: UUID) async {
        for _ in 0..<200 where coordinator.isBusy(id) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testGenerateRunsThenHoldsTheDraftForReview() async {
        let coordinator = NotesCoordinator()
        let id = UUID()
        coordinator.generate(id: id, title: "T", segments: segments, speakers: [],
                             style: .english, using: StubEngine())
        XCTAssertTrue(coordinator.isBusy(id))
        await settle(coordinator, id)

        let draft = coordinator.draft(for: id)
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.items.count, 1)
        XCTAssertEqual(draft?.items.first?.sourceMs, 0)
        XCTAssertEqual(draft?.summary, "Part.")
        XCTAssertFalse(coordinator.isBusy(id))

        coordinator.dismiss(id)
        XCTAssertNil(coordinator.state(for: id))
    }

    func testAFailureIsHeldAsAMessage() async {
        let coordinator = NotesCoordinator()
        let id = UUID()
        coordinator.generate(id: id, title: "T", segments: segments, speakers: [],
                             style: .english, using: StubEngine(outcome: .failure(.languageNotSupported)))
        await settle(coordinator, id)
        XCTAssertEqual(coordinator.failure(for: id), NotesError.languageNotSupported.errorDescription)
        XCTAssertNil(coordinator.draft(for: id))
    }

    func testCancelClearsTheStateAndTheLateResultIsDropped() async {
        let coordinator = NotesCoordinator()
        let id = UUID()
        coordinator.generate(id: id, title: "T", segments: segments, speakers: [],
                             style: .english, using: StubEngine(delayMs: 200))
        XCTAssertTrue(coordinator.isBusy(id))
        coordinator.cancel(id)
        XCTAssertNil(coordinator.state(for: id))
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(coordinator.state(for: id), "a result that lands after a cancel is not shown")
    }

    func testASecondGenerateWhileBusyIsIgnored() async {
        let coordinator = NotesCoordinator()
        let id = UUID()
        coordinator.generate(id: id, title: "T", segments: segments, speakers: [],
                             style: .english, using: StubEngine(delayMs: 100))
        coordinator.generate(id: id, title: "T", segments: segments, speakers: [],
                             style: .english, using: StubEngine(outcome: .failure(.contentRefused)))
        await settle(coordinator, id)
        XCTAssertNotNil(coordinator.draft(for: id), "the first request's result stands")
    }
}
