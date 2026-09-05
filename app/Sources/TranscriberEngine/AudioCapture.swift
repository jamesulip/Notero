@preconcurrency import AVFoundation
import Foundation
import TranscriberCore

/// One chunk of captured audio, ready for inference.
public struct CapturedAudio: Sendable {
    /// 16 kHz mono Int16, little-endian: every lane summed. What a
    /// single-transcript session decodes and what the working copy holds.
    public let pcm: Data
    /// Peak amplitude of this chunk, 0...1, across every lane. Drives the
    /// level meter, whose job is to warn about clipping.
    public let peak: Float
    /// The same audio kept apart, one entry per captured lane. A one-lane
    /// recording has a single entry equal to `pcm`.
    public let lanes: [CaptureLane: Data]
    /// Per-lane peaks, so a two-lane recording can show two meters.
    public let peaks: [CaptureLane: Float]
}

/// Capture with two outputs from one tap, from one to two lanes.
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
///
/// A two-lane recording keeps the room and the call in separate channels of
/// one stereo archive rather than mixing them. Mixing is irreversible, and the
/// thing it destroys is the only clean copy of the remote voices: in a room
/// with speakers the microphone hears them again a fraction of a second later,
/// and summing the two produces comb filtering and doubled words. Kept apart,
/// that is a problem that can still be solved next year.
public final class AudioCapture: @unchecked Sendable {

    public let source: CaptureSource
    public let lanes: [CaptureLane]

    /// Everything below the lock is written by `start`/`stop` on the caller's
    /// thread and read by the capture callback on the audio thread. Neither
    /// `removeTap` nor `AudioDeviceStop` waits for an in-flight callback, so
    /// `stop()` releasing these while the callback still retains them is an
    /// unsynchronized refcount race -- an over-release crash, not a wrong
    /// result.
    private let stateLock = NSLock()
    private var input: (any LaneCapturing)?
    private var chains: [CaptureLane: LaneChain] = [:]
    private var archive: ArchiveWriter?
    private var onAudio: (@Sendable (CapturedAudio) -> Void)?
    private var _isMuted = false
    private var _gain: Float = 1
    private var _roomMode = false

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
    /// showed. Settable mid-recording: the callback reads it per buffer, so the
    /// slider takes effect within one block rather than at the next session.
    ///
    /// The room lane only. What comes off the system tap left an application's
    /// mixer at the level that application chose, and there is no microphone
    /// placement to compensate for.
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
    ///
    /// Also the room lane only: a fan under a table is not on the call.
    public var isRoomMode: Bool {
        get { stateLock.withLock { _roomMode } }
        set { stateLock.withLock { _roomMode = newValue } }
    }

    /// - Parameters:
    ///   - source: which lanes to record.
    ///   - microphoneUID: which microphone, or nil to follow the system
    ///     default. A UID rather than a device id, because ids are reassigned
    ///     across reboots and a saved preference outlives one.
    public init?(source: CaptureSource = .default, microphoneUID: String? = nil) {
        self.source = source
        self.lanes = source.lanes
        self.microphoneUID = microphoneUID
    }

    private let microphoneUID: String?

    /// What the capture actually opened. Empty before `start`.
    public var diagnostics: String {
        stateLock.withLock { input }?.diagnostics ?? ""
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

        let input: any LaneCapturing = switch source {
        case .microphone: MicrophoneInput(deviceUID: microphoneUID)
        case .systemAudio: TapInput(withMicrophone: false, microphoneUID: nil)
        case .both: TapInput(withMicrophone: true, microphoneUID: microphoneUID)
        }
        try input.prepare()
        let rate = input.sampleRate
        guard rate > 0 else { throw CaptureError.noInputDevice }

        // Mono per lane at the capture rate: a meeting microphone is not
        // stereo in any way worth 2x the bytes, and Whisper would downmix it
        // anyway. Two lanes make a stereo file, but each channel is one lane
        // rather than one half of a stereo image.
        guard let archiveFormat = AVAudioFormat(standardFormatWithSampleRate: rate,
                                                channels: AVAudioChannelCount(lanes.count))
        else { throw CaptureError.unsupportedFormat(rate) }
        self.archiveFormat = archiveFormat

        var chains: [CaptureLane: LaneChain] = [:]
        for lane in lanes {
            // Built here, where the capture rate is finally known, and freshly:
            // delay-line state left over from the previous session decays into
            // the start of this one as an audible thump.
            guard let chain = LaneChain(lane: lane, sampleRate: rate) else {
                throw CaptureError.unsupportedFormat(rate)
            }
            chains[lane] = chain
        }
        let writer = try archiveURL.map {
            try ArchiveWriter(url: $0, sampleRate: rate, lanes: lanes)
        }
        stateLock.withLock {
            self.input = input
            self.chains = chains
            self.archive = writer
        }

        input.onGap = { [weak self] frames in self?.fillGap(frames) }
        do {
            try input.start { [weak self] frames in self?.handle(frames) }
        } catch {
            let closing = stateLock.withLock { () -> ArchiveWriter? in
                defer {
                    archive = nil
                    self.input = nil
                    self.chains = [:]
                }
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
        stateLock.withLock { input }?.stop()
        let closing = stateLock.withLock { () -> ArchiveWriter? in
            defer {
                archive = nil
                input = nil
                chains = [:]
                onAudio = nil
            }
            return archive
        }
        let frames = closing?.frameCount ?? 0
        let rate = archiveSampleRate
        closing?.finish()
        isRunning = false
        return (frames, rate)
    }

    // MARK: - The chain

    private func handle(_ frames: [CaptureLane: AVAudioPCMBuffer]) {
        // Snapshot under the lock, then work from locals: a concurrent stop()
        // can release everything here mid-callback otherwise.
        stateLock.lock()
        let chains = self.chains
        let onAudio = self.onAudio
        let archive = self.archive
        let muted = _isMuted
        let gain = _gain
        let roomMode = _roomMode
        stateLock.unlock()
        guard let onAudio, !chains.isEmpty else { return }

        var peaks: [CaptureLane: Float] = [:]
        var pcm: [CaptureLane: Data] = [:]

        for lane in lanes {
            guard let buffer = frames[lane], chains[lane] != nil,
                  let channel = buffer.floatChannelData?[0] else { continue }
            let count = Int(buffer.frameLength)

            if muted {
                for index in 0..<count { channel[index] = 0 }
            } else if lane == .room {
                // Gain goes on before the archive write, not after, so the file
                // kept on disk is the audio that was actually transcribed.
                // Boosting only the inference copy would leave the user with an
                // archive quieter than the meter they watched while recording.
                InputGain.apply(gain, to: channel, count: count)
            }

            // Measured here rather than after the resample, and before the
            // filter: the meter's job is to warn about clipping, which happens
            // at this point in the chain. Reading it post-filter would hide
            // rumble that is eating the headroom and leave the user raising
            // gain into a clip.
            var peak: Float = 0
            for index in 0..<count {
                let sample = abs(channel[index])
                if sample > peak { peak = sample }
            }
            peaks[lane] = peak
        }

        // Written before any filtering, and as one call, so the channels of a
        // two-lane archive stay frame-for-frame together.
        archive?.write(frames)

        for lane in lanes {
            guard let buffer = frames[lane], let chain = chains[lane] else { continue }
            // Safe to filter in place here: `write` deep-copies before it
            // returns, so the archive already has the unfiltered audio.
            if roomMode, lane == .room, let channel = buffer.floatChannelData?[0] {
                chain.applyRoomMode(channel, count: Int(buffer.frameLength))
            }
            if let narrow = chain.toInference(buffer) { pcm[lane] = narrow }
        }

        guard !pcm.isEmpty else { return }
        onAudio(CapturedAudio(pcm: Self.mix(pcm, order: lanes),
                              peak: peaks.values.max() ?? 0,
                              lanes: pcm, peaks: peaks))
    }

    /// Silence for a gap in a lane, so later timestamps stay where they were.
    ///
    /// The output device changing mid-recording tears the tap down and builds
    /// it again, and the audio during that is simply not there. Dropping those
    /// frames would pull every subsequent word earlier by the length of the
    /// gap; writing them as silence keeps the recording on wall-clock and
    /// leaves an audible, visible hole where the truth is.
    private func fillGap(_ frames: Int) {
        stateLock.lock()
        let chains = self.chains
        let onAudio = self.onAudio
        let archive = self.archive
        stateLock.unlock()
        guard let onAudio, frames > 0 else { return }

        var buffers: [CaptureLane: AVAudioPCMBuffer] = [:]
        for lane in lanes {
            guard let chain = chains[lane],
                  let buffer = AVAudioPCMBuffer(pcmFormat: chain.monoFormat,
                                                frameCapacity: AVAudioFrameCount(frames))
            else { continue }
            buffer.frameLength = AVAudioFrameCount(frames)
            if let channel = buffer.floatChannelData?[0] {
                for index in 0..<frames { channel[index] = 0 }
            }
            buffers[lane] = buffer
        }
        archive?.write(buffers)

        var pcm: [CaptureLane: Data] = [:]
        for (lane, buffer) in buffers {
            if let narrow = chains[lane]?.toInference(buffer) { pcm[lane] = narrow }
        }
        guard !pcm.isEmpty else { return }
        onAudio(CapturedAudio(pcm: Self.mix(pcm, order: lanes), peak: 0,
                              lanes: pcm, peaks: [:]))
    }

    /// Sums the lanes for the single-transcript path.
    ///
    /// Summed rather than averaged: the lanes hold different people, so they
    /// are rarely loud at the same moment, and averaging would drop every
    /// voice by 6 dB to guard against an overlap that mostly does not happen.
    /// Clamped, for the overlap that does.
    static func mix(_ lanes: [CaptureLane: Data], order: [CaptureLane]) -> Data {
        let present = order.compactMap { lanes[$0] }
        guard present.count > 1 else { return present.first ?? Data() }
        let count = present.map(\.count).min() ?? 0
        var out = Data(count: count)
        out.withUnsafeMutableBytes { destination in
            let target = destination.bindMemory(to: Int16.self)
            for (index, _) in target.enumerated() { target[index] = 0 }
            for lane in present {
                lane.withUnsafeBytes { source in
                    let samples = source.bindMemory(to: Int16.self)
                    for index in 0..<target.count {
                        let sum = Int32(target[index]) + Int32(samples[index])
                        target[index] = Int16(clamping: sum)
                    }
                }
            }
        }
        return out
    }

    public enum CaptureError: LocalizedError {
        case noInputDevice
        case unsupportedFormat(Double)
        /// The chosen microphone is not attached any more.
        case deviceGone(String)
        case cannotUseDevice(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .noInputDevice:
                return "No microphone is available. Check System Settings › Sound › Input."
            case .unsupportedFormat(let rate):
                return "Cannot resample this input (\(Int(rate)) Hz) to 16 kHz."
            case .deviceGone:
                return "The microphone chosen in Settings is not connected. "
                     + "Choose another one, or reconnect it."
            case .cannotUseDevice(let status):
                return "That microphone could not be opened (Core Audio error \(status))."
            }
        }
    }
}

// MARK: - Per-lane processing

/// Everything between a mono buffer at the capture rate and the bytes the
/// model is given. One per lane, because the filter carries state and two
/// lanes sharing one would bleed each other's history.
final class LaneChain {
    let lane: CaptureLane
    let monoFormat: AVAudioFormat
    private let inferenceFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let highPass: HighPassFilter

    init?(lane: CaptureLane, sampleRate: Double) {
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let narrow = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Double(Audio.sampleRate),
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: mono, to: narrow)
        else { return nil }
        self.lane = lane
        self.monoFormat = mono
        self.inferenceFormat = narrow
        self.converter = converter
        self.highPass = HighPassFilter(cornerHz: HighPassFilter.roomCornerHz,
                                       sampleRate: sampleRate)
    }

    func applyRoomMode(_ channel: UnsafeMutablePointer<Float>, count: Int) {
        highPass.process(channel, count: count)
        // The filter is not level-preserving: it overshoots on transients, so
        // a buffer that was in range before can leave it above ±1 and wrap
        // when it becomes Int16.
        InputGain.clamp(channel, count: count)
    }

    func toInference(_ buffer: AVAudioPCMBuffer) -> Data? {
        let ratio = inferenceFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: inferenceFormat,
                                         frameCapacity: capacity),
              converter.convertOnce(buffer, into: out),
              let channel = out.int16ChannelData?[0] else { return nil }
        return Data(bytes: channel, count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }
}

extension AVAudioConverter {
    /// Converts one buffer into `out`, handing the input block that buffer
    /// exactly once. Returns false when the conversion failed or produced
    /// nothing.
    ///
    /// The converter asks repeatedly until it has enough input; feeding the
    /// same buffer twice would duplicate audio and shift the whole timeline.
    /// A class box rather than a captured var: the block is `@Sendable`.
    func convertOnce(_ buffer: AVAudioPCMBuffer, into out: AVAudioPCMBuffer) -> Bool {
        let supplied = Flag()
        var error: NSError?
        convert(to: out, error: &error) { _, status in
            if supplied.value {
                status.pointee = .noDataNow
                return nil
            }
            supplied.value = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }
}
