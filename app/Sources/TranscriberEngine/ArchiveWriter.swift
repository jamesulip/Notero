@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import TranscriberCore

/// What `AudioCapture` needs of an archive: `ArchiveWriter` is the real one, and
/// a test passes one that stalls, so that "a hung encoder cannot freeze Stop" is
/// tested against a writer that actually hangs and not against a timeout that
/// the writer itself honours.
protocol ArchiveWriting: AnyObject, Sendable {
    var fileFormat: AVAudioFormat { get }
    /// The audio in the file: every frame handed over on a clean close, and only
    /// what was written once writing has stopped early.
    var frameCount: AVAudioFramePosition { get }
    var failure: (any Error)? { get }
    var onFailure: (@Sendable (any Error) -> Void)? { get set }
    func write(_ buffers: [CaptureLane: AVAudioPCMBuffer])
    /// Closes the file. May take as long as the encoder does; the caller bounds
    /// the wait (`AudioCapture.stop(closeWithin:)`).
    func finish()
    func settle()
}

/// Writes the archival AAC file off the audio thread.
///
/// `AVAssetWriter.append` encodes and hits the disk. Doing that inside the
/// capture callback is a real-time violation: a stalled write shows up as
/// dropped frames, and dropped frames are unrecoverable.
///
/// One channel per lane. A two-lane meeting is a stereo file whose channels are
/// the room and the call rather than left and right -- one file, one clock, and
/// no way for the two to drift apart. Anything that cannot read the lanes still
/// plays the meeting.
///
/// **The file is written as movie fragments, and that is what makes it survive
/// the app.** A plain MPEG-4 file is readable only once its index -- the `moov`
/// atom -- has been written, and that happens at close. A quit, a crash, a
/// SIGKILL or a power cut never gets there: measured, an `AVAudioFile` archive
/// killed at 30 s had every byte of audio on disk and could not be opened by
/// `afinfo`, `ffprobe` or `AVAudioFile` (finding 16). A fragmented file carries
/// its own index in each fragment, so the same kill leaves everything up to the
/// last complete fragment playable; the loss is bounded by `fragmentSeconds`,
/// not by the length of the recording. A clean close still produces a file with
/// exactly the frames that were written.
///
/// Writing stops early, and the file is closed while it still can be, when the
/// disk runs low or a write fails (FINDINGS §14). `onFailure` says so once.
final class ArchiveWriter: @unchecked Sendable {

    /// Seconds of audio between fragments, which is also the most a kill can
    /// cost. Five seconds adds about 4% to the file; the index is 1.2 KB a
    /// fragment.
    static let fragmentSeconds = 5.0

    /// Seconds of audio before the *first* fragment. Until a fragment is written the
    /// file holds no index at all, so a kill before it lost the whole recording:
    /// measured, a copy of an open archive was unreadable at 0.5, 1.2, 2.5 and 4.5 s
    /// and readable from 5.5 s (finding 33). One short first fragment moves that
    /// edge from 5 s to 1 s for the price of one more fragment header (about 1.2 KB).
    static let firstFragmentSeconds = 1.0

    /// How long `commit` waits for the encoder to take a buffer before the
    /// writer is declared stuck. A healthy encoder takes one in milliseconds.
    private static let stallLimit: TimeInterval = 30

    /// How long `close` waits for `finishWriting` before it gives up on the
    /// thread. Closing a six-hour recording writes a 4 MB index and takes well
    /// under a second; a writer that has not answered in this long is not going to.
    private static let closeLimit: TimeInterval = 30

    /// Touched only on `queue`, after `init`.
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var framesAppended: Int64 = 0
    private let queue = DispatchQueue(label: "transcriber.archive", qos: .utility)
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private var handedOver: AVAudioFramePosition = 0
    /// False once `finish()` has begun or writing has stopped early: a buffer that
    /// arrives after that is not counted and not written, so `frames` is the file.
    private var accepting = true
    private let lanes: [CaptureLane]
    /// What the device delivers, and what `write` copies.
    private let format: AVAudioFormat
    /// What the file holds. The same as `format` unless the device's rate is
    /// one the AAC encoder does not offer (see `encodableRate`).
    let fileFormat: AVAudioFormat
    /// Brings `format` to `fileFormat`; nil when they are the same. Used only
    /// on `queue`.
    private let converter: AVAudioConverter?
    private let description: CMAudioFormatDescription
    private let url: URL
    private let disk: DiskSpace
    /// Touched only on `queue`.
    private var framesSinceDiskCheck: AVAudioFramePosition = 0
    private var _failure: (any Error)?
    private var _onFailure: (@Sendable (any Error) -> Void)?

    /// The writer could not take a buffer, or took none for too long.
    struct Stalled: LocalizedError {
        var errorDescription: String? { "the audio encoder stopped accepting audio" }
    }

    /// `finishWriting` did not answer. What earlier fragments hold still plays.
    struct CloseStalled: LocalizedError {
        var errorDescription: String? { "the audio file did not finish closing" }
    }

    /// What the file holds once `close` has run: nil while that is not known
    /// (the encoder never answered). Touched only on `queue`.
    private var durable: AVAudioFramePosition?

    /// - Parameter firstFragmentSeconds: when the first fragment is written; nil for
    ///   none, which is what every recording had before finding 33. For tests that
    ///   compare the two.
    init(url: URL, sampleRate: Double, lanes: [CaptureLane], disk: DiskSpace = .system,
         firstFragmentSeconds: Double? = ArchiveWriter.firstFragmentSeconds) throws {
        self.lanes = lanes
        self.url = url
        self.disk = disk
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: AVAudioChannelCount(lanes.count))
        else { throw AudioCapture.CaptureError.unsupportedFormat(sampleRate) }
        self.format = format

        // The encoder offers no rate above 48 kHz, and a 96 kHz interface is
        // an ordinary thing to have: the recording would be refused outright.
        // The archive is written at the nearest rate the encoder takes, below
        // the device's, which loses nothing speech has.
        guard let fileRate = Self.encodableRate(for: sampleRate),
              let fileFormat = AVAudioFormat(standardFormatWithSampleRate: fileRate,
                                             channels: AVAudioChannelCount(lanes.count))
        else { throw AudioCapture.CaptureError.unsupportedFormat(sampleRate) }
        self.fileFormat = fileFormat
        if fileRate == sampleRate {
            self.converter = nil
        } else {
            guard let converter = AVAudioConverter(from: format, to: fileFormat) else {
                throw AudioCapture.CaptureError.unsupportedFormat(sampleRate)
            }
            self.converter = converter
        }

        var asbd = fileFormat.streamDescription.pointee
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description) == noErr, let description
        else { throw AudioCapture.CaptureError.unsupportedFormat(sampleRate) }
        self.description = description

        // 64 kbps a channel: transparent for speech, and about 28 MB an hour
        // mono against the 345 MB that raw 48 kHz float would cost.
        //
        // Asked for, not demanded. The encoder caps the bitrate by sample rate
        // -- 48 kbps for mono at 16 kHz, 24 kbps at 8 kHz -- and a request
        // above the cap is refused with `'!dat'` before a frame is captured.
        // Every Bluetooth headset in hands-free mode and many USB conference
        // speakerphones deliver 16 kHz, so the request is clamped to what the
        // encoder allows at this rate (finding 13).
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: fileRate,
            AVNumberOfChannelsKey: lanes.count,
        ]
        if let bitRate = Self.bitRate(target: 64_000 * lanes.count, for: fileFormat) {
            settings[AVEncoderBitRateKey] = bitRate
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let free = disk.shortfall(at: url) {
            throw EngineError.cannotSaveAudio(
                DiskSpace.Low(availableBytes: free).localizedDescription)
        }

        // `AVAssetWriter` raises an Objective-C exception, which Swift cannot
        // catch, for settings the encoder does not take -- a 96 kHz interface
        // is one. Asked first, so the answer is an error and not a crash.
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: Self.freshURL(url), fileType: .m4a)
        } catch {
            throw EngineError.cannotSaveAudio(error.localizedDescription)
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
            throw AudioCapture.CaptureError.unsupportedFormat(sampleRate)
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings,
                                       sourceFormatHint: description)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw AudioCapture.CaptureError.unsupportedFormat(sampleRate)
        }
        writer.add(input)
        writer.movieFragmentInterval = CMTime(seconds: Self.fragmentSeconds,
                                              preferredTimescale: 600)
        if let firstFragmentSeconds {
            writer.initialMovieFragmentInterval = CMTime(seconds: firstFragmentSeconds,
                                                         preferredTimescale: 600)
        }
        guard writer.startWriting() else {
            throw EngineError.cannotSaveAudio(
                writer.error?.localizedDescription ?? "the archive could not be started")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
    }

    /// `AVAssetWriter` refuses an output that exists; `AVAudioFile` replaced
    /// it, and a recording that restarts under the same name relies on that.
    private static func freshURL(_ url: URL) -> URL {
        try? FileManager.default.removeItem(at: url)
        return url
    }

    deinit {
        // A writer that is let go without `finish()` is still closed, so that
        // no path out of a recording leaves the file open.
        close()
    }

    var frameCount: AVAudioFramePosition {
        lock.withLock { frames }
    }

    /// Why writing stopped early, if it has.
    var failure: (any Error)? { lock.withLock { _failure } }

    /// Called once, on the writer's queue, when writing stops early.
    var onFailure: (@Sendable (any Error) -> Void)? {
        get { lock.withLock { _onFailure } }
        set { lock.withLock { _onFailure = newValue } }
    }

    /// The sample rate the file is written at for a device delivering `rate`:
    /// `rate` itself when the AAC encoder offers it, else one it does offer
    /// below it, read from the encoder.
    static func encodableRate(for rate: Double) -> Double? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 0, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
            mChannelsPerFrame: 0, mBitsPerChannel: 0, mReserved: 0)
        let specifier = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var size = UInt32(0)
        var offered: [Double] = [48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000]
        if AudioFormatGetPropertyInfo(kAudioFormatProperty_AvailableEncodeSampleRates,
                                      specifier, &asbd, &size) == noErr, size > 0 {
            var ranges = [AudioValueRange](
                repeating: AudioValueRange(),
                count: Int(size) / MemoryLayout<AudioValueRange>.size)
            if AudioFormatGetProperty(kAudioFormatProperty_AvailableEncodeSampleRates,
                                      specifier, &asbd, &size, &ranges) == noErr {
                let listed = ranges.map(\.mMaximum).filter { $0 > 0 }
                if !listed.isEmpty { offered = listed.sorted(by: >) }
            }
        }
        if offered.contains(rate) { return rate }
        // An exact fraction of the device's rate when there is one -- 96 kHz
        // to 48 kHz, 88.2 to 44.1 -- because a whole-number ratio is the
        // cleanest conversion; else the highest the encoder offers below it.
        let below = offered.filter { $0 < rate }
        return below.filter { rate.truncatingRemainder(dividingBy: $0) == 0 }.max() ?? below.max()
    }

    /// `target` clamped into the bitrates the AAC encoder accepts for `format`,
    /// read from the encoder itself rather than from a table that goes stale.
    /// Nil when the encoder cannot be asked; the caller then omits the key and
    /// lets the encoder choose.
    static func bitRate(target: Int, for format: AVAudioFormat) -> Int? {
        var source = format.streamDescription.pointee
        var aac = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1024,
            mBytesPerFrame: 0, mChannelsPerFrame: format.channelCount,
            mBitsPerChannel: 0, mReserved: 0
        )
        var converter: AudioConverterRef?
        guard AudioConverterNew(&source, &aac, &converter) == noErr, let converter else {
            return nil
        }
        defer { AudioConverterDispose(converter) }

        var size = UInt32(0)
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates,
                                            &size, nil) == noErr,
              size >= UInt32(MemoryLayout<AudioValueRange>.size)
        else { return nil }
        var ranges = [AudioValueRange](
            repeating: AudioValueRange(),
            count: Int(size) / MemoryLayout<AudioValueRange>.size
        )
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates,
                                        &size, &ranges) == noErr
        else { return nil }
        // Zero is the encoder's "unconstrained" marker, not a real floor.
        let floors = ranges.map(\.mMinimum).filter { $0 > 0 }
        guard let highest = ranges.map(\.mMaximum).max(), highest > 0 else { return nil }
        let lowest = floors.min() ?? highest
        return Int(min(max(Double(target), lowest), highest))
    }

    /// Interleaves the lanes into one multi-channel buffer and hands it off.
    ///
    /// A lane missing from this callback is written as silence rather than
    /// skipped: the channels of a file have to stay the same length as each
    /// other, and a lane that dropped out for a moment is a hole in that lane,
    /// not a shortening of the recording.
    func write(_ buffers: [CaptureLane: AVAudioPCMBuffer]) {
        let count = lanes.compactMap { buffers[$0]?.frameLength }.min() ?? 0
        guard count > 0, lock.withLock({ accepting }),
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)
        else { return }
        copy.frameLength = count
        guard let destination = copy.floatChannelData else { return }

        for (channel, lane) in lanes.enumerated() {
            let target = destination[channel]
            if let source = buffers[lane]?.floatChannelData?[0] {
                target.update(from: source, count: Int(count))
            } else {
                for index in 0..<Int(count) { target[index] = 0 }
            }
        }

        // Counted in what the file holds, so the length reported is the file's.
        // Counted and queued under one lock, so that `finish()` -- which closes the
        // door under the same lock before it queues the close -- cannot fall
        // between the two and leave a buffer counted that is never written. Held
        // strongly: every buffer that was accepted is written, even if the owner
        // lets go of the writer before the queue has drained.
        lock.withLock {
            guard accepting else { return }
            handedOver += AVAudioFramePosition(count)
            frames = converter == nil
                ? handedOver
                : AVAudioFramePosition((Double(handedOver) * fileFormat.sampleRate
                                        / format.sampleRate).rounded())
            queue.async { self.commit(copy) }
        }
    }

    /// The disk check and the write, on `queue`.
    private func commit(_ buffer: AVAudioPCMBuffer) {
        guard let writer, let input else { return }
        framesSinceDiskCheck += AVAudioFramePosition(buffer.frameLength)
        let interval = AVAudioFramePosition(format.sampleRate)
            * AVAudioFramePosition(DiskSpace.checkIntervalMs) / 1000
        if framesSinceDiskCheck >= interval {
            framesSinceDiskCheck = 0
            if let free = disk.shortfall(at: url) {
                stop(because: DiskSpace.Low(availableBytes: free))
                return
            }
        }

        // Back-pressure rather than a drop: the capture side is already
        // finished with this buffer, so waiting costs memory and never audio.
        let deadline = Date().addingTimeInterval(Self.stallLimit)
        while !input.isReadyForMoreMediaData {
            if writer.status != .writing {
                stop(because: writer.error ?? Stalled())
                return
            }
            if Date() > deadline {
                stop(because: Stalled())
                return
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        var toWrite = buffer
        if let converter {
            let ratio = fileFormat.sampleRate / format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: capacity),
                  converter.convertOnce(buffer, into: out)
            else {
                // Nothing came out of this buffer: carried inside the converter
                // and heard with the next one.
                return
            }
            toWrite = out
        }
        guard let sample = sampleBuffer(from: toWrite, atFrame: framesAppended),
              input.append(sample)
        else {
            stop(because: writer.error ?? Stalled())
            return
        }
        framesAppended += Int64(toWrite.frameLength)
    }

    /// `buffer` as a sample buffer stamped at its position in the file, so the
    /// timeline is the frame count and nothing else.
    private func sampleBuffer(from buffer: AVAudioPCMBuffer,
                              atFrame frame: Int64) -> CMSampleBuffer? {
        let scale = Int32(fileFormat.sampleRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: scale),
            presentationTimeStamp: CMTime(value: frame, timescale: scale),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
            sampleCount: CMItemCount(buffer.frameLength), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample) == noErr, let sample,
              CMSampleBufferSetDataBufferFromAudioBufferList(
                sample, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
                bufferList: buffer.audioBufferList) == noErr
        else { return nil }
        return sample
    }

    /// Closes the file now, while closing it can still succeed, and reports why.
    ///
    /// From here on the length reported is what the file holds. It was every frame
    /// handed over, which after a disk-low stop was 60 s in a probe while the file
    /// held 4.0 s; the recording is still 60 s long (the working copy holds it), but
    /// a caller that asks the *archive* how long it is must be told the truth.
    private func stop(because error: any Error) {
        close()
        let report = lock.withLock { () -> (@Sendable (any Error) -> Void)? in
            accepting = false
            frames = min(frames, durable ?? framesAppended)
            guard _failure == nil else { return nil }
            _failure = error
            return _onFailure
        }
        report?(error)
    }

    /// Records a failure once, and says so.
    private func fail(_ error: any Error) {
        let report = lock.withLock { () -> (@Sendable (any Error) -> Void)? in
            guard _failure == nil else { return nil }
            _failure = error
            return _onFailure
        }
        report?(error)
    }

    /// What `writer` left in the file, in frames at the file's rate: everything
    /// appended when it closed cleanly, and otherwise only what the last complete
    /// fragment holds, read back from the file.
    private func durableFrames(after writer: AVAssetWriter) -> AVAudioFramePosition {
        if writer.status == .completed { return framesAppended }
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return 0 }
        return min(framesAppended, file.length)
    }

    /// Finalizes the file: the last fragment, then the closing index.
    ///
    /// Every way out of a recording ends here -- `finish()`, a failed write, a
    /// disk running low, and the writer being let go. A recording that wrote no
    /// frame at all has no audio to keep, so its empty file is removed rather than
    /// left behind as something that looks like a recording; a file that holds
    /// audio is never removed, even when the writer failed, because what the last
    /// complete fragment holds still plays.
    ///
    /// The wait for `finishWriting` is bounded (`closeLimit`). It was a bare
    /// semaphore wait, and a hung encoder held the thread for good.
    private func close() {
        guard let writer, let input else { return }
        self.writer = nil
        self.input = nil
        guard writer.status == .writing else {
            durable = durableFrames(after: writer)
            return
        }
        if framesAppended == 0 {
            writer.cancelWriting()
            durable = 0
            return
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        // The writer is held by its own completion, so that a close that is given
        // up on is still finished when the encoder gets round to it.
        let held = Held(writer)
        writer.finishWriting { _ = held; finished.signal() }
        guard finished.wait(timeout: .now() + Self.closeLimit) == .success else {
            durable = nil
            fail(CloseStalled())
            return
        }
        durable = durableFrames(after: writer)
        if writer.status == .failed, let error = writer.error {
            lock.withLock { frames = min(frames, durable ?? framesAppended) }
            fail(error)
        }
    }

    /// Closes the file, and does mean *closes*: the last fragment is written
    /// and the file finalized before this returns.
    func finish() {
        // The door shuts first, under the lock `write` counts under: a buffer is
        // either queued ahead of the close or refused, never counted and lost.
        lock.withLock { accepting = false }
        queue.sync { close() }
    }

    /// Returns once everything handed over so far has been passed to the
    /// encoder. For tests that look at the file while the writer is open.
    func settle() {
        queue.sync {}
    }
}

extension ArchiveWriter: ArchiveWriting {}

/// Keeps an `AVAssetWriter` alive until the handler that holds this runs.
private final class Held: @unchecked Sendable {
    let writer: AVAssetWriter
    init(_ writer: AVAssetWriter) { self.writer = writer }
}

/// Whether the archive of a recording can be played.
public enum ArchiveStatus: Equatable, Sendable {
    /// Opens, and holds this much audio.
    case playable(durationMs: Int)
    /// The file is there and cannot be opened, or holds no audio. A recording
    /// made before the archive was written in fragments and then ended without
    /// a close -- a quit, a crash, a power cut -- is this: the audio is in the
    /// file and no reader can find it. The 16 kHz working copy is what is left.
    case unreadable(String)
    /// No file at that path.
    case missing
}

/// Asks the question the recovery path needs to answer before it says "the
/// audio is here": whether the archive opens, which `hasAudio` -- a check that
/// the file exists -- does not tell.
public enum AudioArchive {
    public static func status(of url: URL) -> ArchiveStatus {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let file = try AVAudioFile(forReading: url)
            let rate = file.fileFormat.sampleRate
            guard file.length > 0, rate > 0 else { return .unreadable("the file holds no audio") }
            return .playable(durationMs: Int(Double(file.length) / rate * 1000))
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }
}
