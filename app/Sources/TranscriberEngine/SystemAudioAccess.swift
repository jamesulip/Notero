import Foundation

/// Permission to record this Mac's own audio, as a thing the UI can show.
///
/// A separate permission from the microphone, in its own category
/// (`kTCCServiceAudioCapture`), with its own row in System Settings and its own
/// usage string in the bundle. Granting one says nothing about the other.
///
/// The failure mode is why this type exists at all. A refused microphone
/// records silence; a refused system tap does not even do that. Core Audio
/// creates the tap, builds the aggregate, accepts the IOProc and returns
/// `noErr` from `AudioDeviceStart` -- and then never runs the device. No error,
/// no callback, no indicator. A hybrid meeting recorded without this permission
/// looks exactly like a hybrid meeting where nobody on the call said anything,
/// and the user finds out afterwards.
///
/// There is no public API here: nothing to read the state, and nothing to ask
/// at a chosen moment. Apple ships neither. The functions that do exist are in
/// a private framework, and they are loaded by name at run time -- so a macOS
/// release that removes or renames them costs this app an accurate permission
/// row, not a crash, and never a wrong answer: `unknown` is a state the UI
/// handles.
public enum SystemAudioAccess: String, Sendable, CaseIterable {
    /// Recording will capture what the Mac plays.
    case granted
    /// Never asked. The one state where asking shows a prompt.
    case notDetermined
    /// Asked and refused. Only System Settings can change this.
    case denied
    /// The private interface is not there. Try, and find out from the result.
    case unknown

    public static var current: SystemAudioAccess {
        guard let preflight = TCC.preflight else { return .unknown }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system prompt, and only when one can appear.
    ///
    /// macOS asks once. After that the stored answer comes back immediately
    /// with nothing on screen, so offering this on a denied app is offering a
    /// button that does nothing.
    ///
    /// The prompt also needs a foreground application to attach itself to. Run
    /// from a terminal, or from a process launched by one, TCC decides the
    /// request belongs to the parent and refuses it without asking anybody --
    /// which is why the command line tool cannot grant itself this and the app
    /// can.
    public static func request() async -> SystemAudioAccess {
        guard current == .notDetermined, let request = TCC.request else { return current }
        return await withCheckedContinuation { continuation in
            request("kTCCServiceAudioCapture" as CFString, nil) { _ in
                continuation.resume(returning: current)
            }
        }
    }

    public var canRequest: Bool { self == .notDetermined }
    public var needsSystemSettings: Bool { self == .denied }
    /// Whether starting a capture is worth attempting at all.
    public var mightWork: Bool { self != .denied }

    public var label: String {
        switch self {
        case .granted: return "Allowed"
        case .notDetermined: return "Not requested yet"
        case .denied: return "Denied"
        case .unknown: return "Cannot be checked"
        }
    }

    public var detail: String {
        switch self {
        case .granted:
            return "Recording will capture what this Mac plays."
        case .notDetermined:
            return "macOS will ask the first time you record this Mac's audio. "
                 + "Granting it here instead means a meeting never starts with a "
                 + "permission dialog."
        case .denied:
            return "The call side of a meeting will be missing, and nothing will "
                 + "say so while recording. macOS only asks once, so this has to "
                 + "be changed in System Settings."
        case .unknown:
            return "This version of macOS does not report the answer. Recording "
                 + "will ask if it needs to."
        }
    }

    /// Deep link to Privacy & Security. The pane has no per-service anchor for
    /// system audio, so this opens the section rather than the row.
    public static let systemSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy"
    )!
}

/// The private side of the permission, isolated to one place and resolved by
/// name so that its absence is a missing feature rather than a missing symbol.
private enum TCC {
    typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    typealias Request = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    // `nonisolated(unsafe)` on the handle: it is resolved once, never written
    // again, and the C functions behind it are thread-safe. The two function
    // pointers below are `Sendable` on their own.
    nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW
    )

    static let preflight: Preflight? = symbol("TCCAccessPreflight").map {
        unsafeBitCast($0, to: Preflight.self)
    }

    static let request: Request? = symbol("TCCAccessRequest").map {
        unsafeBitCast($0, to: Request.self)
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        handle.flatMap { dlsym($0, name) }
    }
}
