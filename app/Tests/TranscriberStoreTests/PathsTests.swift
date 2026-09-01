import XCTest
@testable import TranscriberStore

final class PathsTests: XCTestCase {
    func testRecordingNameIsFiledByYearAndMonth() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 8; parts.day = 30
        let date = Calendar.current.date(from: parts)!
        let id = UUID()
        let name = Paths.newRecordingName(id: id, ext: "m4a", on: date)
        XCTAssertEqual(name, "2026/08/\(id.uuidString).m4a")
    }
}
