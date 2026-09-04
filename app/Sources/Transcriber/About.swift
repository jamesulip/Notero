import AppKit
import Foundation

/// What this copy of the app is, and where a newer one is published.
///
/// The app does not update itself. It carries no update key, downloads no
/// code, and replaces no bundle. A new version is a manual download from the
/// releases page, which is the only address in this file.
enum About {

    static let owner = "jamesulip"
    static let repository = "notero"

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases")!
    }

    /// `CFBundleShortVersionString`, which `build-app.sh` writes from VERSION.
    /// Nil when the binary runs outside a bundle -- `swift run`, or the
    /// executable straight out of `.build`.
    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The commit count that `build-app.sh` writes as `CFBundleVersion`.
    static var build: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    static var versionText: String {
        guard let version else { return "unknown" }
        guard let build else { return version }
        return "\(version) (\(build))"
    }

    /// Opens the releases page in the default browser. The one address this
    /// app knows, and the user asks for it every time.
    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }
}
