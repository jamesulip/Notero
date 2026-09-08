import XCTest
@testable import TranscriberCore

final class CatalogueTests: XCTestCase {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalogue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAModelIsDownloadedOnlyOnceItsDecoderExists() throws {
        // Settings offers Remove and Download off this answer, and WhisperKit
        // writes the decoder last, so a half-fetched model must read as absent.
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let id = ModelCatalogue.defaultModel
        XCTAssertFalse(ModelCatalogue.isDownloaded(id, modelsDirectory: base))
        XCTAssertNil(ModelCatalogue.sizeOnDisk(id, modelsDirectory: base))

        let folder = ModelCatalogue.directory(for: id, modelsDirectory: base)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("AudioEncoder.mlmodelc"),
            withIntermediateDirectories: true)
        XCTAssertFalse(ModelCatalogue.isDownloaded(id, modelsDirectory: base),
                       "an encoder alone is a download in progress")

        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("TextDecoder.mlmodelc"),
            withIntermediateDirectories: true)
        try Data("weights".utf8).write(
            to: folder.appendingPathComponent("TextDecoder.mlmodelc/coremldata.bin"))
        XCTAssertTrue(ModelCatalogue.isDownloaded(id, modelsDirectory: base))
        XCTAssertEqual(ModelCatalogue.sizeOnDisk(id, modelsDirectory: base), 7)
    }

    func testTheTierNamedAccurateStillReadsBackAsBest() throws {
        // The raw value is stored in UserDefaults, in a saved BenchmarkReport
        // and on the --tier flag. A Mac that wrote "accurate" before the
        // rename must keep the tier it chose rather than fall back.
        XCTAssertEqual(ModelTier(rawValue: "accurate"), .best)
        XCTAssertEqual(ModelTier(rawValue: "best"), .best)
        XCTAssertEqual(ModelTier.best.rawValue, "best")
        XCTAssertNil(ModelTier(rawValue: "unmeasured"))

        let decoded = try JSONDecoder().decode([ModelTier].self,
                                               from: Data(#"["fast","accurate"]"#.utf8))
        XCTAssertEqual(decoded, [.fast, .best])
    }

    func testEveryTierMapsToACataloguedModel() {
        for tier in ModelTier.allCases {
            XCTAssertNotNil(ModelCatalogue.option(tier.defaultModelId),
                            "\(tier.label) points at a model the catalogue does not describe")
        }
    }
}
