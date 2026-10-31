import XCTest
@testable import TranscriberCore

/// A tier's memory is the Neural Engine memory its model occupies, not the
/// process footprint, which looked the same for every tier (finding 22).
final class BenchmarkRunTests: XCTestCase {

    private func run(residency: Int?) -> BenchmarkRun {
        BenchmarkRun(modelId: "m", tier: .balanced, label: "l", audioMs: 1000, processMs: 100,
                     loadMs: 9000, peakMemoryMB: 120, modelResidencyMB: residency)
    }

    func testTheModelResidencyIsKeptApartFromTheFootprint() throws {
        let original = run(residency: 1580)
        let decoded = try JSONDecoder().decode(BenchmarkRun.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.modelResidencyMB, 1580)
        XCTAssertEqual(decoded.peakMemoryMB, 120)
    }

    /// Runs saved before the field existed have no such key, and must still load.
    func testARunSavedWithoutTheResidencyStillDecodes() throws {
        let data = try JSONEncoder().encode(run(residency: nil))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["peakMemoryMB"], "the fixture was meant to carry the old fields")
        XCTAssertNil(object?["modelResidencyMB"], "the fixture was meant to lack the new one")
        let decoded = try JSONDecoder().decode(BenchmarkRun.self, from: data)
        XCTAssertNil(decoded.modelResidencyMB)
    }
}
