@preconcurrency import AVFoundation
import Foundation
import TranscriberCore

/// Writes the archival AAC file off the audio thread.
///
/// `AVAudioFile.write` encodes and hits the disk. Doing that inside the capture
/// callback is a real-time violation: a stalled write shows up as dropped
/// frames, and dropped frames are unrecoverable.
///
/// One channel per lane. A two-lane meeting is a stereo file whose channels are
/// the room and the call rather than left and right -- one file, one clock, and
/// no way for the two to drift apart. Anything that cannot read the lanes still
/// plays the meeting.
///
/// Writing stops early, and the file is closed while it still can be, when the
/// disk runs low or a write fails. An MPEG-4 file whose index was never written
/// cannot be opened at all, so pressing on into a full disk loses the whole
/// recording rather than its end (FINDINGS §14). `onFailure` says so once.
final class ArchiveWriter: @unchecked Sendable {
    /// Touched only on `queue`, after `init`.
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "transcriber.archive", qos: .utility)
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private let lanes: [CaptureLane]
    private let format: AVAudioFormat
    private let url: URL
    private let disk: DiskSpace
    /// Touched only on `queue`.
    private var framesSinceDiskCheck: AVAudioFramePosition = 0
    private var _failure: (any Error)?
    private var _onFailure: (@Sendable (any Error) -> Void)?

    init(url: URL, sampleRate: Double, lanes: [CaptureLane], disk: DiskSpace = .system) throws {
        self.lanes = lanes
        self.url = url
        self.disk = disk
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: AVAudioChannelCount(lanes.count))
        else { throw AudioCapture.CaptureError.unsupportedFormat(sampleRate) }
        self.format = format

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
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: lanes.count,
        ]
        if let bitRate = Self.bitRate(target: 64_000 * lanes.count, for: format) {
            settings[AVEncoderBitRateKey] = bitRate
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let free = disk.shortfall(at: url) {
            throw EngineError.cannotSaveAudio(
                DiskSpace.Low(availableBytes: free).localizedDescription)
        }
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
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
        guard count > 0,
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

        lock.withLock { frames += AVAudioFramePosition(count) }
        queue.async { [weak self] in
            self?.commit(copy)
        }
    }

    /// The disk check and the write, on `queue`.
    private func commit(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }
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
        do {
            try file.write(from: buffer)
        } catch {
            stop(because: error)
        }
    }

    /// Closes the file now, while closing it can still succeed, and reports why.
    private func stop(because error: any Error) {
        file = nil
        let report = lock.withLock { () -> (@Sendable (any Error) -> Void)? in
            _failure = error
            return _onFailure
        }
        report?(error)
    }

    /// Closes the file, and does mean *closes*.
    ///
    /// An MPEG-4 container is only finalized -- the sample tables flushed and
    /// the `moov` atom written -- when `AVAudioFile` is deallocated. Merely
    /// stopping writes leaves bytes on disk that every decoder refuses to open,
    /// so the reference is dropped here rather than left to whenever the owner
    /// happens to release the writer.
    func finish() {
        queue.sync { file = nil }
    }
}
