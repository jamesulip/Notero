import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// A two-lane recording whose archive cannot be opened (finding 33).
///
/// The lane path builds each lane's 16 kHz copy from one channel of the archive. Live
/// capture writes only the mixed copy. With the archive unreadable (an encoder that
/// never closed the file, a recording from before the archive was fragmented), asking
/// for the lanes failed the job with "audio unreadable" although the mixed copy held
/// the whole meeting. The honest answer is the mixed copy as one lane, with a warning
/// that says what that costs.
final class LanePlanTests: XCTestCase {

    private let two: [CaptureLane] = [.room, .remote]

    func testAReadableArchiveKeepsTheLanes() {
        let plan = WorkingCopyPolicy.lanePlan(recorded: two, archiveReadable: true,
                                              laneCopiesExist: false, mixedCopyExists: true)
        XCTAssertEqual(plan.lanes, two)
        XCTAssertNil(plan.warning)
    }

    func testAnUnreadableArchiveFallsBackToTheMixedCopyAsOneLaneAndSaysSo() throws {
        let plan = WorkingCopyPolicy.lanePlan(recorded: two, archiveReadable: false,
                                              laneCopiesExist: false, mixedCopyExists: true)
        XCTAssertEqual(plan.lanes, [.room], "the mixed copy is one stream")
        let warning = try XCTUnwrap(plan.warning)
        XCTAssertTrue(warning.contains("which side"), warning)
        XCTAssertTrue(warning.contains("mixed"), warning)
    }

    /// Lane copies left by an earlier run are what the lane path reads first.
    func testLaneCopiesThatAreStillThereKeepTheLanesWithoutTheArchive() {
        let plan = WorkingCopyPolicy.lanePlan(recorded: two, archiveReadable: false,
                                              laneCopiesExist: true, mixedCopyExists: true)
        XCTAssertEqual(plan.lanes, two)
        XCTAssertNil(plan.warning)
    }

    /// With nothing to fall back to the job is left to say why it cannot run.
    func testWithNoMixedCopyEitherTheLanesAreLeftAlone() {
        let plan = WorkingCopyPolicy.lanePlan(recorded: two, archiveReadable: false,
                                              laneCopiesExist: false, mixedCopyExists: false)
        XCTAssertEqual(plan.lanes, two)
        XCTAssertNil(plan.warning)
    }

    func testOneLaneIsNeverChanged() {
        for readable in [true, false] {
            let plan = WorkingCopyPolicy.lanePlan(recorded: [.room], archiveReadable: readable,
                                                  laneCopiesExist: false, mixedCopyExists: true)
            XCTAssertEqual(plan.lanes, [.room])
            XCTAssertNil(plan.warning)
        }
    }
}
