import Foundation

/// The free space audio writing keeps in hand.
///
/// A full disk loses more than the audio that did not fit. An MPEG-4 file is
/// only readable once its index -- the `moov` atom -- has been written, and
/// that happens when the file is closed. Measured: an AAC archive that ran into
/// a full disk after nine minutes could not be opened at all, so all nine
/// minutes were lost, not the last few seconds (FINDINGS §14). The writers
/// therefore stop *before* the disk is full, while there is still room to close
/// the file properly.
///
/// 100 MB is far more than any index needs (a six-hour AAC file's is about
/// 4 MB) and leaves SwiftData room to save the transcript. At the rate a
/// recording writes -- about 40 KB/s for the archive and the working copy
/// together -- it is also roughly 40 minutes of audio, so a disk that is
/// already below it is refused at the start rather than sealed seconds later.
struct DiskSpace: Sendable {

    static let reserveBytes: Int64 = 100_000_000

    /// How much audio, in milliseconds, a writer writes between looks at the
    /// disk. Looking is a `statfs` -- cheap, but not something to do per
    /// 85 ms capture buffer -- and at 40 KB/s five seconds is 200 KB, nowhere
    /// near the reserve.
    static let checkIntervalMs = 5_000

    /// Free bytes on the volume holding `url`, or nil when it cannot be read.
    /// Nil is treated as "enough": a probe that fails must not stop a recording
    /// that the disk could hold.
    let available: @Sendable (URL) -> Int64?

    static let system = DiskSpace { url in
        let directory = url.deletingLastPathComponent().path
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    /// The free space when it is below the reserve, else nil.
    func shortfall(at url: URL) -> Int64? {
        guard let free = available(url), free < Self.reserveBytes else { return nil }
        return free
    }

    /// Why a writer stopped before the disk was full.
    struct Low: LocalizedError, Sendable {
        let availableBytes: Int64

        var errorDescription: String? {
            let free = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return "the disk is almost full: \(free) free"
        }
    }
}
