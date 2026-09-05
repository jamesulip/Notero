import Foundation

/// Everything the app writes, in one place.
///
///     Application Support/Transcriber/
///     ├── Transcriber.store          SwiftData
///     ├── Recordings/YYYY/MM/<uuid>.m4a
///     └── Models/                    CoreML weights, gigabytes, downloaded
///
/// Audio is filed by year and month rather than in one flat directory: a year
/// of daily meetings is a few thousand files, and Finder, Time Machine and
/// `FileManager.contentsOfDirectory` all get noticeably worse at that size.
public enum Paths {

    /// The directory is named `Transcriber` and not `Notero`, although the app
    /// is now Notero. It holds the recordings and the store that the private
    /// builds wrote. To rename it here is to point the app at an empty
    /// directory and to hide every recording that a user already made. Rename
    /// it only together with a migration that moves the old directory first.
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent("Transcriber", isDirectory: true))
    }

    public static var storeURL: URL { support.appendingPathComponent("Transcriber.store") }

    public static var recordings: URL {
        ensure(support.appendingPathComponent("Recordings", isDirectory: true))
    }

    public static var models: URL {
        ensure(support.appendingPathComponent("Models", isDirectory: true))
    }

    /// Absolute location of a recording from the relative name stored on it.
    public static func recordingURL(_ relativeName: String) -> URL {
        recordings.appendingPathComponent(relativeName)
    }

    /// Allocates `YYYY/MM/<uuid>.<ext>` and creates the directory.
    /// Returns the path relative to `recordings`, which is what gets persisted.
    public static func newRecordingName(id: UUID, ext: String, on date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        let year = String(format: "%04d", parts.year ?? 1970)
        let month = String(format: "%02d", parts.month ?? 1)
        _ = ensure(recordings.appendingPathComponent("\(year)/\(month)", isDirectory: true))
        return "\(year)/\(month)/\(id.uuidString).\(ext)"
    }

    @discardableResult
    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
