import AVFoundation
import CoreAudio
import Foundation
import TranscriberCore

/// A source of lane audio: mono buffers, one per lane, on one clock.
///
/// Two conformances and one seam. Everything above this protocol -- gain, the
/// meter, room mode, the archive, the 16 kHz conversion -- is written once and
/// does not know whether the samples came from a microphone or from what the
/// Mac was playing.
protocol LaneCapturing: AnyObject {
    /// Valid after `prepare()`. The chains are built around it, so it has to
    /// be known before a single sample arrives.
    var sampleRate: Double { get }
    /// Frames lost to a device change, reported so the caller can keep the
    /// timeline pinned by writing silence in their place.
    var onGap: (@Sendable (Int) -> Void)? { get set }

    /// What this source actually opened, for the diagnostics command and for
    /// support questions that begin "it records nothing".
    var diagnostics: String { get }

    func prepare() throws
    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws
    func stop()
}

// MARK: - Microphone

/// The room lane, through `AVAudioEngine`.
///
/// Pinning a device is the reason this takes a UID at all. The engine's input
/// node follows whatever macOS calls the default input, which moves when a
/// headset is plugged in -- mid-meeting, silently, from the conference
/// microphone on the table to the one on somebody's ear.
final class MicrophoneInput: LaneCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let deviceUID: String?
    private var hardwareFormat: AVAudioFormat?
    private var toMono: AVAudioConverter?
    private var onFrames: (@Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void)?

    var onGap: (@Sendable (Int) -> Void)?
    var sampleRate: Double { hardwareFormat?.sampleRate ?? 0 }

    var diagnostics: String {
        let device = deviceUID.flatMap { AudioDevices.device(uid: $0)?.name }
            ?? AudioDevices.defaultInput()?.name ?? "unknown"
        let format = hardwareFormat.map { "\(Int($0.sampleRate)) Hz, \($0.channelCount) ch" }
            ?? "not open"
        return "microphone \(device) (\(format))"
    }

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
    }

    func prepare() throws {
        // Before the format is read, because reading it instantiates the audio
        // unit against whatever device it is currently pointed at.
        if let deviceUID {
            guard let id = AudioDevices.objectID(uid: deviceUID) else {
                throw AudioCapture.CaptureError.deviceGone(deviceUID)
            }
            try pin(id)
        }
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioCapture.CaptureError.noInputDevice }
        hardwareFormat = format

        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                       channels: 1),
              let converter = AVAudioConverter(from: format, to: mono)
        else { throw AudioCapture.CaptureError.unsupportedFormat(format.sampleRate) }
        toMono = converter
    }

    /// `kAudioOutputUnitProperty_CurrentDevice` on the engine's own audio unit.
    /// This works for input; it is the tap's aggregate that cannot be selected
    /// this way, where the same call returns success and does nothing.
    private func pin(_ device: AudioObjectID) throws {
        guard let unit = engine.inputNode.audioUnit else {
            throw AudioCapture.CaptureError.noInputDevice
        }
        var id = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &id,
                                          UInt32(MemoryLayout<AudioObjectID>.size))
        guard status == noErr else {
            throw AudioCapture.CaptureError.cannotUseDevice(status)
        }
    }

    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws {
        guard let hardwareFormat, let toMono else {
            throw AudioCapture.CaptureError.noInputDevice
        }
        self.onFrames = onFrames

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) {
            [weak self] buffer, _ in
            guard let self, let mono = Self.downmix(buffer, with: toMono) else { return }
            self.onFrames?([.room: mono])
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onFrames = nil
    }

    private static func downmix(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                         frameCapacity: buffer.frameLength + 64),
              converter.convertOnce(buffer, into: out)
        else { return nil }
        return out
    }
}

// MARK: - System audio, and both

/// The remote lane, and optionally the room lane beside it on the same clock.
///
/// When both are asked for they come out of one aggregate device and one
/// callback, already frame-aligned. That is the whole reason this is one class
/// rather than two captures running side by side.
final class TapInput: LaneCapturing, @unchecked Sendable {
    private let tap: SystemAudioTap
    private var scratch: [CaptureLane: AVAudioPCMBuffer] = [:]
    private var monoFormat: AVAudioFormat?

    var onGap: (@Sendable (Int) -> Void)? {
        get { tap.onGap }
        set { tap.onGap = newValue }
    }

    var sampleRate: Double { tap.layout?.sampleRate ?? 0 }

    var diagnostics: String {
        guard let layout = tap.layout else { return "system audio (not open)" }
        let microphone = layout.microphone.map { "mic ch \($0.lowerBound)…\($0.upperBound - 1)" }
            ?? "no mic"
        return "aggregate \(Int(layout.sampleRate)) Hz, \(layout.totalChannels) ch: "
             + "\(microphone), system ch \(layout.system.lowerBound)…"
             + "\(layout.system.upperBound - 1)"
    }

    init(withMicrophone: Bool, microphoneUID: String?) {
        self.tap = SystemAudioTap(withMicrophone: withMicrophone,
                                  microphoneUID: microphoneUID)
    }

    func prepare() throws {
        // Checked rather than attempted, because a refusal is not an error
        // here: Core Audio would start the device, return success and never
        // deliver a sample. A recording that silently contains none of the
        // call is worse than one that refuses to start.
        guard SystemAudioAccess.current.mightWork else {
            throw SystemAudioTap.TapError.notPermitted
        }
        try tap.prepare()
        guard let layout = tap.layout, layout.sampleRate > 0 else {
            throw SystemAudioTap.TapError.unsupportedFormat
        }
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: layout.sampleRate,
                                       channels: 1)
        else { throw SystemAudioTap.TapError.unsupportedFormat }
        monoFormat = mono
    }

    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws {
        guard let layout = tap.layout, let monoFormat else {
            throw SystemAudioTap.TapError.unsupportedFormat
        }
        try tap.start { [weak self] list, frames in
            guard let self else { return }
            var delivered: [CaptureLane: AVAudioPCMBuffer] = [:]
            if let microphone = layout.microphone,
               let buffer = self.buffer(for: .room, format: monoFormat, frames: frames) {
                AudioBufferListReader.mixDown(microphone, of: list, frames: frames,
                                              into: buffer.floatChannelData![0])
                delivered[.room] = buffer
            }
            if let buffer = self.buffer(for: .remote, format: monoFormat, frames: frames) {
                AudioBufferListReader.mixDown(layout.system, of: list, frames: frames,
                                              into: buffer.floatChannelData![0])
                delivered[.remote] = buffer
            }
            guard !delivered.isEmpty else { return }
            onFrames(delivered)
        }
    }

    func stop() {
        tap.stop()
        scratch = [:]
    }

    /// Reused across callbacks. Everything downstream copies before it returns
    /// -- the archive deep-copies, the converter writes into its own buffer --
    /// so allocating two buffers a hundred times a second on the audio thread
    /// would buy nothing.
    private func buffer(for lane: CaptureLane, format: AVAudioFormat,
                        frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        if let existing = scratch[lane], existing.frameCapacity >= frames {
            existing.frameLength = frames
            return existing
        }
        guard let fresh = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames + 512)
        else { return nil }
        fresh.frameLength = frames
        scratch[lane] = fresh
        return fresh
    }
}
