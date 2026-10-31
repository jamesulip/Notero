import AVFoundation
import Foundation

/// How long the audio in an archive file is, or nil when it cannot be read.
///
/// An AAC file in an MP4 container is readable only after its index (the
/// `moov` atom) is written at close. A recording that never got to close
/// leaves a file that exists, has a size, and cannot be opened (finding 16).
/// Existence is therefore no evidence that the archive holds the audio.
public enum ArchiveProbe {

    /// For a job in the queue: the same reader `AudioCache.build` uses, so a
    /// file that this reports readable is one that the working copy can be
    /// rebuilt from.
    public static func durationMs(of url: URL) async -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.loadTracks(withMediaType: .audio).first != nil else { return nil }
            let seconds = CMTimeGetSeconds(try await asset.load(.duration))
            guard seconds.isFinite, seconds > 0 else { return nil }
            return Int(seconds * 1000)
        } catch {
            return nil
        }
    }

    /// For the launch, where nothing can await: a file this app recorded is an
    /// AAC `.m4a`, which `AVAudioFile` opens at once or refuses at once.
    public static func recordedDurationMs(of url: URL) -> Int? {
        guard let file = try? AVAudioFile(forReading: url),
              file.fileFormat.sampleRate > 0, file.length > 0 else { return nil }
        return Int(Double(file.length) / file.fileFormat.sampleRate * 1000)
    }
}

/// When the 16 kHz working copy may be deleted.
///
/// The queue used to delete it after any successful job, because the archive
/// can rebuild it. That holds only when the archive can be read and holds as
/// much audio. After a quit or a crash under a recording the archive is an
/// unclosed file that nothing opens, the working copy is the only audio
/// there is, and the default setting (`keepWorkingCopy` off) deleted it as
/// soon as the user did what the recovery message told them to do.
public enum WorkingCopyPolicy {

    /// How much shorter than the archive a working copy may be and still
    /// count as complete: the two come from one tap, and codec padding makes
    /// them differ by a few tens of milliseconds. A fixed two seconds, not a
    /// share of the length: at 1% a two-hour recording let a working copy that
    /// was 72 s longer than its archive be deleted as "covered", and the
    /// archive cannot rebuild those seconds (QA finding S4). Measured, the two
    /// stay within a fraction of a millisecond over six hours.
    public static func toleranceMs(archiveMs: Int) -> Int {
        2_000
    }

    /// Whether the archive holds all of the working copy's audio, so that
    /// deleting the copy loses nothing the archive cannot rebuild.
    public static func archiveCovers(archiveMs: Int?, workingCopyMs: Int) -> Bool {
        guard let archiveMs else { return false }
        return archiveMs + toleranceMs(archiveMs: archiveMs) >= workingCopyMs
    }

    /// Whether a working copy is short of the archive it came from, which is
    /// what a writer that stopped early (a full disk) leaves behind.
    public static func isTruncated(workingCopyMs: Int, archiveMs: Int?) -> Bool {
        guard let archiveMs else { return false }
        return archiveMs > workingCopyMs + toleranceMs(archiveMs: archiveMs)
    }

    /// `canDiscard` with the real probe, for a caller outside the queue.
    public static func canDiscard(workingCopy: URL, archive: URL?) async -> Bool {
        await canDiscard(workingCopy: workingCopy, archive: archive,
                         probe: { url in await ArchiveProbe.durationMs(of: url) })
    }

    /// May `workingCopy` be deleted now? Yes only when `archive` can stand in
    /// for it. A missing or empty working copy has nothing to keep.
    public static func canDiscard(
        workingCopy: URL, archive: URL?,
        probe: @Sendable (URL) async -> Int?
    ) async -> Bool {
        guard FileManager.default.fileExists(atPath: workingCopy.path) else { return true }
        guard let copy = try? MappedPCM(contentsOf: workingCopy), copy.sampleCount > 0 else {
            return true
        }
        guard let archive else { return false }
        return archiveCovers(archiveMs: await probe(archive), workingCopyMs: copy.durationMs)
    }
}
