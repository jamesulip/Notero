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
final class ArchiveWriter: @unchecked Sendable {
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "transcriber.archive", qos: .utility)
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private let lanes: [CaptureLane]
    private let format: AVAudioFormat

    init(url: URL, sampleRate: Double, lanes: [CaptureLane]) throws {
        self.lanes = lanes
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: AVAudioChannelCount(lanes.count))
        else { throw AudioCapture.CaptureError.unsupportedFormat(sampleRate) }
        self.format = format

        // 64 kbps a channel: transparent for speech, and about 28 MB an hour
        // mono against the 345 MB that raw 48 kHz float would cost.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: lanes.count,
            AVEncoderBitRateKey: 64_000 * lanes.count,
        ]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var frameCount: AVAudioFramePosition {
        lock.withLock { frames }
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
            guard let self else { return }
            try? self.file?.write(from: copy)
        }
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
