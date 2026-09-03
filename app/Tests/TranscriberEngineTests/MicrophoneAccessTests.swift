import XCTest
@testable import TranscriberEngine

/// The one rule worth locking down: macOS prompts once.
///
/// `AVCaptureDevice.requestAccess` on an app that has already been denied
/// returns the stored answer without showing anything. So exactly one state
/// may offer to ask, and a denied app must be sent to System Settings instead
/// of being given a button that silently does nothing.
final class MicrophoneAccessTests: XCTestCase {

    func testOnlyAnUnaskedStateCanBeAsked() {
        XCTAssertEqual(MicrophoneAccess.allCases.filter(\.canRequest), [.notDetermined])
    }

    func testOnlyDeniedIsSentToSystemSettings() {
        // Not `restricted`: that is a profile or parental controls, and the
        // user cannot change it there either, so offering the trip is a lie.
        XCTAssertEqual(MicrophoneAccess.allCases.filter(\.needsSystemSettings), [.denied])
    }

    func testEveryStateExplainsItself() {
        for access in MicrophoneAccess.allCases {
            XCTAssertFalse(access.label.isEmpty, "\(access) has no label")
            XCTAssertFalse(access.detail.isEmpty, "\(access) has no detail")
        }
    }
}
