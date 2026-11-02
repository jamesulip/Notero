import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The model revision comes from the local download cache, never the network,
/// and is unavailable rather than guessed when the cache does not say.
final class EvaluationProvenanceTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func metadata(_ name: String, firstLine: String, model: String = "m") throws {
        let dir = ModelCatalogue.directory(for: model, modelsDirectory: root).deletingLastPathComponent()
            .appendingPathComponent(".cache/huggingface/download/\(model)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "\(firstLine)\nsome-etag\n1789358367.888833\n"
            .write(to: dir.appendingPathComponent("\(name).metadata"), atomically: true, encoding: .utf8)
    }

    private let commitA = "0f63a7800b00dd0226abd051b906c246e1907482"
    private let commitB = "f6c3db01a3124f90b3bfbf3d58e47ba5de1f5ccd"

    func testOneCommitIsTheRevision() throws {
        try metadata("config.json", firstLine: commitA)
        try metadata("generation_config.json", firstLine: commitA)
        XCTAssertEqual(EvaluationProvenance.modelRevision(modelId: "m", modelsDirectory: root), .available(commitA))
    }

    func testFilesFromDifferentCommitsAreAllListed() throws {
        try metadata("config.json", firstLine: commitB)
        try metadata("generation_config.json", firstLine: commitA)
        XCTAssertEqual(EvaluationProvenance.modelRevision(modelId: "m", modelsDirectory: root),
                       .available("mixed: \(commitA), \(commitB)"))
    }

    func testNoCacheMeansNoRevision() {
        XCTAssertNil(EvaluationProvenance.modelRevision(modelId: "m", modelsDirectory: root).value)
    }

    func testAFirstLineThatIsNotACommitIsIgnored() throws {
        try metadata("config.json", firstLine: "not-a-commit")
        XCTAssertNil(EvaluationProvenance.modelRevision(modelId: "m", modelsDirectory: root).value)
    }

    func testAnotherModelsCacheIsNotRead() throws {
        try metadata("config.json", firstLine: commitA, model: "other")
        XCTAssertNil(EvaluationProvenance.modelRevision(modelId: "m", modelsDirectory: root).value)
    }

    func testHardwareIsRecorded() {
        let hardware = EvaluationProvenance.hardware
        XCTAssertFalse(hardware.machine.isEmpty)
        XCTAssertGreaterThan(hardware.memoryGB, 0)
    }
}
