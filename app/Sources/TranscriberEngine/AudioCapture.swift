import AVFoundation
import Foundation
import TranscriberCore

/// One chunk of captured audio, ready for inference.
public struct CapturedAudio: Sendable {
    /// 16 kHz mono Int16, little-endian.
    public let pcm: Data
    /// Peak amplitude of this chunk, 0...1. Drives the level meter.
    public let peak: Float
}

/// Microphone capture with two outputs from one tap.
///
/// The archive keeps the hardware's own rate as AAC, because that is the copy
/// the user still has in a year. Inference gets 16 kHz mono, because that is
/// all Whisper can consume. Deriving both from a single tap is what keeps them
/// sample-aligned: two taps would drift, and the transcript timestamps would
/// stop lining up with the audio the player is scrubbing.
///
/// The hardware rate is whatever the device offers -- 44.1 or 48 kHz typically,
/// Bluetooth headsets often something else again -- so nothing here assumes it
/// got the format it asked for. `AVAudioConverter` does the rate change with
/// proper anti-aliasing; decimating by taking every Nth sample would fold
/// everything above 8 kHz back into the speech band, which is exactly where the
/// consonant detail Whisper needs lives.
public final class AudioCapture: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let inferenceFormat: AVAudioFormat

    /// Everything below the lock is written by `start`/`stop` on the caller's
    /// thread and read by `handle` on the tap's thread. `removeTap` does not
    /// wait for an in-flight tap block, so `stop()` releasing these references
    /// while `handle` is still retaining them is an unsynchronized refcount
    /// race -- an over-release crash, not a wrong result.
    private let stateLock = NSLock()
    private var toArchive: AVAudioConverter?
    private var toInference: AVAudioConverter?
    private var archive: ArchiveWriter?
    private var onAudio: (@Sendable (CapturedAudio) -> Void)?
    private var _isMuted = false
    private var _gain: Float = 1
    private var _roomMode = false
    private var highPass: HighPassFilter?

    public private(set) var isRunning = false
    public private(set) var archiveFormat: AVAudioFormat?

    /// Muted capture writes silence rather than dropping frames, so timestamps
    /// stay pinned to wall-clock and the transcript never desyncs from audio.
    public var isMuted: Bool {
        get { stateLock.withLock { _isMuted } }
        set { stateLock.withLock { _isMuted = newValue } }
    }

    /// Input gain in decibels, applied to both the archive and the inference
    /// copy so the file on disk matches what was transcribed and what the meter
    /// showed. Settable mid-recording: the tap reads it per buffer, so the
    /// slider takes effect within one 4096-frame block rather than at the next
    /// session.
    public var gainDb: Float {
        get { InputGain.db(fromLinear: stateLock.withLock { _gain }) }
        set {
            let linear = InputGain.linear(fromDb: newValue)
            stateLock.withLock { _gain = linear }
        }
    }

    /// Removes low-frequency rumble from the copy sent for transcription.
    ///
    /// The archive is deliberately left unfiltered: room mode is a decision
    /// about what the model should be given, and the recording the user keeps
    /// should still contain everything the microphone heard. Re-transcribing
    /// later re-applies this from the setting rather than inheriting it, so a
    /// meeting recorded in the wrong mode is recoverable.
    public var isRoomMode: Bool {
        get { stateLock.withLock { _roomMode } }
        set { stateLock.withLock { _roomMode = newValue } }
    }

    public init?() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Audio.sampleRate),
            channels: 1,
            interleaved: true
        ) else { return nil }
        inferenceFormat = format
    }

    public var archiveSampleRate: Int {
        Int(archiveFormat?.sampleRate ?? 0)
    }

    // MARK: - Lifecycle

    /// - Parameter archiveURL: where to write the AAC copy, or nil to run
    ///   inference-only (benchmarks, and the live preview before a session is
    ///   committed to disk).
    public func start(archiveURL: URL?,
                      onAudio: @escaping @Sendable (CapturedAudio) -> Void) throws {
        guard !isRunning else { return }
        self.onAudio = onAudio

        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0 else { throw CaptureError.noInputDevice }

        // Mono at the hardware rate: a meeting mic is not stereo in any way
        // worth 2x the bytes, and Whisper would downmix it anyway.
        guard let archiveFormat = AVAudioFormat(
            standardFormatWithSampleRate: hardware.sampleRate, channels: 1
        ) else { throw CaptureError.unsupportedFormat(hardware.sampleRate) }
        self.archiveFormat = archiveFormat

        guard let toArchive = AVAudioConverter(from: hardware, to: archiveFormat),
              let toInference = AVAudioConverter(from: archiveFormat, to: inferenceFormat)
        else { throw CaptureError.unsupportedFormat(hardware.sampleRate) }
        let writer = try archiveURL.map { try ArchiveWriter(url: $0, format: archiveFormat) }
        // Built here, where the hardware rate is finally known, and freshly:
        // delay-line state left over from the previous session decays into the
        // start of this one as an audible thump.
        let filter = HighPassFilter(cornerHz: HighPassFilter.roomCornerHz,
                                    sampleRate: hardware.sampleRate)
        stateLock.withLock {
            self.highPass = filter
            self.toArchive = toArchive
            self.toInference = toInference
            self.archive = writer
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardware) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            let closing = stateLock.withLock { () -> ArchiveWriter? in
                defer { archive = nil }
                return archive
            }
            closing?.finish()
            throw error
        }
        isRunning = true
    }

    /// Stops capture and closes the archive. Returns what was written.
    @discardableResult
    public func stop() -> (frames: AVAudioFramePosition, sampleRate: Int) {
        guard isRunning else {
            return (stateLock.withLock { archive?.frameCount ?? 0 }, archiveSampleRate)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let closing = stateLock.withLock { () -> ArchiveWriter? in
            defer {
                archive = nil
                toArchive = nil
                toInference = nil
                onAudio = nil
                highPass = nil
            }
            return archive
        }
        let frames = closing?.frameCount ?? 0
        let rate = archiveSampleRate
        closing?.finish()
        isRunning = false
        return (frames, rate)
    }

    // MARK: - Tap

    private func handle(_ buffer: AVAudioPCMBuffer) {
        // Snapshot under the lock, then work from locals: a concurrent stop()
        // can release everything here mid-callback otherwise.
        stateLock.lock()
        let toArchive = self.toArchive
        let toInference = self.toInference
        let onAudio = self.onAudio
        let archive = self.archive
        let muted = _isMuted
        let gain = _gain
        let roomMode = _roomMode
        let highPass = self.highPass
        stateLock.unlock()
        guard let toArchive, let toInference, let onAudio else { return }

        guard let mono = Self.convert(buffer, with: toArchive, ratioHint: 1) else { return }
        if muted {
            Self.silence(mono)
        } else if let channel = mono.floatChannelData?[0] {
            // Gain goes on before the archive write, not after, so the file kept
            // on disk is the audio that was actually transcribed. Boosting only
            // the inference copy would leave the user with an archive quieter
            // than the meter they watched while recording it.
            InputGain.apply(gain, to: channel, count: Int(mono.frameLength))
        }

        // Measured here rather than after the resample, and before the filter:
        // the meter's job is to warn about clipping, which happens at this
        // point in the chain. Reading it post-filter would hide rumble that is
        // eating the headroom and leave the user raising gain into a clip.
        var peak: Float = 0
        if let channel = mono.floatChannelData?[0] {
            for index in 0..<Int(mono.frameLength) {
                let sample = abs(channel[index])
                if sample > peak { peak = sample }
            }
        }

        archive?.write(mono)

        // After the archive write, so only the model sees the filtering. Safe
        // to mutate in place here: `write` deep-copies before it returns.
        if roomMode, let highPass, let channel = mono.floatChannelData?[0] {
            let frames = Int(mono.frameLength)
            highPass.process(channel, count: frames)
            // The filter is not level-preserving: it overshoots on transients,
            // so a buffer that was in range before can leave it above ±1 and
            // wrap when it becomes Int16.
            InputGain.clamp(channel, count: frames)
        }

        guard let narrow = Self.convert(
            mono, with: toInference,
            ratioHint: inferenceFormat.sampleRate / mono.format.sampleRate
        ), narrow.frameLength > 0, let channel = narrow.int16ChannelData?[0] else { return }

        let count = Int(narrow.frameLength)
        let data = Data(bytes: channel, count: count * MemoryLayout<Int16>.size)
        onAudio(CapturedAudio(pcm: data, peak: peak))
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter,
                                ratioHint: Double) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                         frameCapacity: capacity) else { return nil }

        // The converter asks repeatedly until it has enough input; feeding the
        // same buffer twice would duplicate audio and shift the whole timeline.
        // A class box rather than a captured var: the block is @Sendable.
        let supplied = Flag()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied.value {
                status.pointee = .noDataNow
                return nil
            }
            supplied.value = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    private static func silence(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        for index in 0..<Int(buffer.frameLength) { channel[index] = 0 }
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }

    public enum CaptureError: LocalizedError {
        case noInputDevice
        case unsupportedFormat(Double)

        public var errorDescription: String? {
            switch self {
            case .noInputDevice:
                return "No microphone is available. Check System Settings › Sound › Input."
            case .unsupportedFormat(let rate):
                return "Cannot resample this input (\(Int(rate)) Hz) to 16 kHz."
            }
        }
    }
}

/// Writes the archival AAC file off the audio thread.
///
/// `AVAudioFile.write` encodes and hits the disk. Doing that inside the tap
/// callback is a real-time violation: a stalled write shows up as dropped
/// microphone frames, and dropped frames are unrecoverable.
final class ArchiveWriter: @unchecked Sendable {
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "transcriber.archive", qos: .utility)
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0

    init(url: URL, format: AVAudioFormat) throws {
        // 64 kbps mono AAC: transparent for speech, and about 28 MB an hour
        // against the 345 MB that raw 48 kHz float would cost.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
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

    func write(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.deepCopy() else { return }
        lock.withLock { frames += AVAudioFramePosition(copy.frameLength) }
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

extension AVAudioPCMBuffer {
    /// The tap reuses its buffer, so anything handed to another thread has to
    /// own its bytes.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let source = floatChannelData, let destination = copy.floatChannelData
        else { return nil }
        let count = Int(frameLength)
        for channel in 0..<Int(format.channelCount) {
            destination[channel].update(from: source[channel], count: count)
        }
        copy.frameLength = frameLength
        return copy
    }
}
