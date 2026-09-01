import Foundation

/// Everything the app writes, in one place.
///
///     Application Support/Transcriber/
///     ├── Transcriber.store          SwiftData
///     ├── Recordings/YYYY/MM/<uuid>.m4a
///     ├── Exports/
///     └── Models/                    CoreML weights, gigabytes, downloaded
///
/// Audio is filed by year and month rather than in one flat directory: a year
/// of daily meetings is a few thousand files, and Finder, Time Machine and
/// `FileManager.contentsOfDirectory` all get noticeably worse at that size.
public enum Paths {

    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent("Transcriber", isDirectory: true))
    }

    public static var storeURL: URL { support.appendingPathComponent("Transcriber.store") }

    public static var recordings: URL {
        ensure(support.appendingPathComponent("Recordings", isDirectory: true))
    }

    public static var exports: URL {
        ensure(support.appendingPathComponent("Exports", isDirectory: true))
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
