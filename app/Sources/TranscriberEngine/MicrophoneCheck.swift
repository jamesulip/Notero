@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import TranscriberCore

/// One test take: what a microphone heard, as the model would hear it.
public struct MicrophoneTake: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// The microphone that was open, by name, so takes from two microphones
    /// can be told apart when they are compared.
    public let microphone: String
    public let recorded: Date
    /// 16 kHz mono Int16, little-endian.
    public let pcm: Data
    public let peak: Float

    public var seconds: Double {
        Double(pcm.count / Audio.bytesPerSample) / Double(Audio.sampleRate)
    }

    public init(microphone: String, recorded: Date = Date(), pcm: Data, peak: Float) {
        self.id = UUID()
        self.microphone = microphone
        self.recorded = recorded
        self.pcm = pcm
        self.peak = peak
    }
}

/// Records a test take from one microphone.
///
/// The level meter says that a microphone delivers *something*. It cannot say
/// whether that something is the room or a hiss, whether the voice is clipped,
/// or whether a Bluetooth link is dropping syllables. Hearing the take answers
/// all three in the only way that is quick to judge: by ear.
///
/// The same `AudioCapture` the app records with feeds the 16 kHz mono copy
/// that the model would hear, so the take is the model's input, not the
/// archive's. Used by Settings and by `transcribe --mic-check`; `TakePlayer`
/// plays what this records.
public final class MicrophoneCheck: @unchecked Sendable {
    public let microphoneUID: String?
    /// The recording settings the take is heard through, so the test hears
    /// what a recording gets: a MacBook microphone across a table is 15 to
    /// 20 dB under a speakerphone's automatic gain, and without the boost the
    /// take sounds like nothing was recorded.
    public var gainDb: Float = 0
    public var isRoomMode = false
    /// Called on a background queue with the peak of every chunk, 0...1.
    public var onLevel: (@Sendable (Float) -> Void)?

    private var capture: AudioCapture?
    private var pcm = Data()
    private var peak: Float = 0
    private let lock = NSLock()
    /// Where the device is opened and closed. Both go through coreaudiod,
    /// and a Bluetooth profile switch or a slow HAL query can hold that for
    /// many seconds; on the main thread that is a hang report.
    private let io = DispatchQueue(label: "transcriber.microphone-check.io", qos: .userInitiated)

    public init(microphoneUID: String?) {
        self.microphoneUID = microphoneUID
    }

    /// What was opened, for the diagnostics command.
    public var diagnostics: String { capture?.diagnostics ?? "not open" }

    /// The microphone that is open: the pinned one, or the system default.
    ///
    /// Once an engine has an input node, the process's default input is a
    /// private aggregate that Core Audio names "CADefaultDeviceAggregate-…".
    /// The take is named after the device inside it.
    public var microphoneName: String {
        if let microphoneUID, let name = AudioDevices.device(uid: microphoneUID)?.name {
            return name
        }
        guard let id = try? CoreAudioObject.defaultInputDevice() else { return "Microphone" }
        if let main = Self.mainSubDevice(of: id),
           let name = AudioDevices.device(uid: main)?.name {
            return name
        }
        return (try? CoreAudioObject.name(of: id)) ?? "Microphone"
    }

    /// The UID of an aggregate's main sub-device, or nil for a plain device.
    private static func mainSubDevice(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyMainSubDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let uid = value?.takeRetainedValue() else { return nil }
        return uid as String
    }

    /// Seconds captured so far.
    public var seconds: Double {
        Double(lock.withLock { pcm.count } / Audio.bytesPerSample) / Double(Audio.sampleRate)
    }

    public func start() throws {
        guard let capture = AudioCapture(source: .microphone, microphoneUID: microphoneUID) else {
            throw AudioCapture.CaptureError.noInputDevice
        }
        lock.withLock {
            pcm.removeAll()
            peak = 0
        }
        capture.gainDb = gainDb
        capture.isRoomMode = isRoomMode
        try capture.start(archiveURL: nil) { [weak self] chunk in
            guard let self else { return }
            lock.withLock {
                pcm.append(chunk.pcm)
                peak = max(peak, chunk.peak)
            }
            onLevel?(chunk.peak)
        }
        self.capture = capture
    }

    /// `start()` on the I/O queue, for callers on the main actor.
    public func startInBackground() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            io.async {
                do {
                    try self.start()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// `stop()` on the I/O queue, for callers on the main actor.
    public func stopInBackground() async -> MicrophoneTake? {
        await withCheckedContinuation { (done: CheckedContinuation<MicrophoneTake?, Never>) in
            io.async { done.resume(returning: self.stop()) }
        }
    }

    /// Stops the capture and returns the take, or nil when nothing was heard.
    @discardableResult
    public func stop() -> MicrophoneTake? {
        let name = microphoneName
        capture?.stop()
        capture = nil
        let (audio, loudest) = lock.withLock { (pcm, peak) }
        guard !audio.isEmpty else { return nil }
        return MicrophoneTake(microphone: name, pcm: audio, peak: loudest)
    }
}

/// Plays takes through the default output, one at a time.
///
/// A Bluetooth device that is both the microphone and the speaker switches
/// profiles here, which is part of what the check shows.
public final class TakePlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                       sampleRate: Double(Audio.sampleRate),
                                       channels: 1, interleaved: true)!
    private let lock = NSLock()
    private var generation = 0
    private let io = DispatchQueue(label: "transcriber.take-player.io", qos: .userInitiated)

    public init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Starts `take` on a background queue and returns at once. `onFinish` is
    /// called when the take has been heard to the end, and not when `stop` or
    /// another `play` cut it short; `onFailure` when the output could not be
    /// opened. Both arrive on a background queue.
    public func play(_ take: MicrophoneTake, onFailure: @escaping @Sendable (String) -> Void,
                     onFinish: @escaping @Sendable () -> Void) {
        let frames = AVAudioFrameCount(take.pcm.count / Audio.bytesPerSample)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.int16ChannelData?[0]
        else { return }
        buffer.frameLength = frames
        take.pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            channel.update(from: base.assumingMemoryBound(to: Int16.self), count: Int(frames))
        }
        let mine = lock.withLock { () -> Int in
            generation += 1
            return generation
        }
        io.async { [self] in
            guard lock.withLock({ generation == mine }) else { return }
            node.stop()
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    onFailure("Playback failed: \(error.localizedDescription)")
                    return
                }
            }
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self, lock.withLock({ generation == mine }) else { return }
                // Let the output go: a speaker held open keeps a Bluetooth
                // device in its playback profile, and the next take's
                // microphone then waits on the switch.
                self.io.async { self.engine.stop() }
                onFinish()
            }
            node.play()
        }
    }

    public func stop() {
        lock.withLock { generation += 1 }
        io.async { [self] in
            node.stop()
            engine.stop()
        }
    }
}
