import AVFoundation
import Foundation

/// Microphone authorization, as a thing the UI can show and act on.
///
/// The app needs exactly one permission. It is asked for at the moment
/// recording starts, which is the worst time to find out the answer is no: a
/// refused microphone does not error, it delivers silence, so a denied prompt
/// looks like a meeting nobody spoke at.
///
/// The distinction that matters is `notDetermined` versus `denied`. macOS
/// prompts once. After that `requestAccess` returns the stored answer
/// immediately without showing anything, so a "Grant Access" button on a
/// denied app is a button that does nothing. Only `notDetermined` can be
/// asked; `denied` has to go through System Settings.
public enum MicrophoneAccess: String, Sendable, CaseIterable {
    /// Recording will work.
    case granted
    /// Never asked. The one state where asking shows a prompt.
    case notDetermined
    /// Asked and refused. Only System Settings can change this.
    case denied
    /// Blocked by a profile or parental controls; the user cannot change it.
    case restricted

    public static var current: MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt, and only then. Returns the resulting state.
    public static func request() async -> MicrophoneAccess {
        guard current == .notDetermined else { return current }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return current
    }

    /// Whether asking would actually put a prompt on screen.
    public var canRequest: Bool { self == .notDetermined }

    /// Whether the user has to go to System Settings to change this.
    public var needsSystemSettings: Bool { self == .denied }

    public var label: String {
        switch self {
        case .granted: return "Allowed"
        case .notDetermined: return "Not requested yet"
        case .denied: return "Denied"
        case .restricted: return "Blocked by this Mac's policy"
        }
    }

    public var detail: String {
        switch self {
        case .granted:
            return "A recording captures audio."
        case .notDetermined:
            return "macOS asks the first time you record. Give the permission here, "
                 + "and a meeting never starts with a permission dialog."
        case .denied:
            return "A recording gives silence and no error. macOS asks one time only, "
                 + "thus you must change this in System Settings."
        case .restricted:
            return "A configuration profile or parental controls block the microphone. "
                 + "A recording gives silence."
        }
    }

    /// Deep link to Privacy & Security › Microphone.
    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!
}
