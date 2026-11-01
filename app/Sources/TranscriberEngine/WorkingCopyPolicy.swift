import AVFoundation
import Foundation
import TranscriberCore

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

    /// Which lanes a job on a recording should read, and what to tell the person if
    /// that is not the lanes it was recorded with.
    public struct LanePlan: Equatable, Sendable {
        public var lanes: [CaptureLane]
        public var warning: String?

        public init(lanes: [CaptureLane], warning: String? = nil) {
            self.lanes = lanes
            self.warning = warning
        }
    }

    /// The lane path builds each lane's 16 kHz copy from one channel of the archive
    /// (or finds a lane copy an earlier run left), and live capture writes only the
    /// mixed copy. When the archive cannot be opened and no lane copy is left, asking
    /// for the lanes fails the job with "audio unreadable" while the mixed copy holds
    /// the whole meeting. That copy is the only source there is, so it is read as one
    /// lane, and the warning says what it costs: the transcript cannot say which side
    /// each line came from (finding 33).
    public static func lanePlan(recorded lanes: [CaptureLane], archiveReadable: Bool,
                                laneCopiesExist: Bool, mixedCopyExists: Bool) -> LanePlan {
        guard lanes.count > 1, !archiveReadable, !laneCopiesExist, mixedCopyExists else {
            return LanePlan(lanes: lanes, warning: nil)
        }
        return LanePlan(
            lanes: [.room],
            warning: "The recording file could not be opened, so the room and the call could "
                + "not be read apart. This transcript was made from the mixed copy of the audio, "
                + "and its lines do not say which side they came from.")
    }

    /// May the working copy of a recording that has just stopped be deleted when the
    /// work on it is done?
    ///
    /// Not when the archive's close timed out. A fragmented archive that is still
    /// closing is up to one fragment (5 s) shorter than the audio, and `archiveCovers`
    /// forgives 2 s: of 11 unclosed archives QA probed, 8 were 0.3-1.8 s short and
    /// still counted as covering the copy, so deleting it lost that tail for good while
    /// the notice promised a copy was kept (FINDINGS 35). The close goes on in the
    /// background; a later Transcribe Again rebuilds the copy if the archive finished.
    public static func discardsAfterStop(keepSetting: Bool, notices: [CaptureNotice]) -> Bool {
        guard !keepSetting else { return false }
        return !notices.contains { if case .archiveNotClosed = $0 { true } else { false } }
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
