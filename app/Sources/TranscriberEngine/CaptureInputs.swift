@preconcurrency import AVFoundation
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
    /// Valid after `prepare()`, and fixed for the session. The chains and the
    /// archive are built around it, so a device that arrives later at another
    /// rate is converted to this one rather than changing it.
    var sampleRate: Double { get }
    /// Frames lost to a device change, reported so the caller can keep the
    /// timeline pinned by writing silence in their place.
    var onGap: (@Sendable (Int) -> Void)? { get set }
    /// Something changed under the recording that the user has to be told
    /// about: the microphone was replaced, or capture could not be restarted.
    var onNotice: (@Sendable (CaptureNotice) -> Void)? { get set }

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
    /// Mono at the rate of the device that was open at `prepare`, for the
    /// whole session. A device that takes over later is converted to it.
    private var monoFormat: AVAudioFormat?
    private var hardwareFormat: AVAudioFormat?
    private var toMono: AVAudioConverter?
    private var onFrames: (@Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void)?
    private var configurationObserver: NSObjectProtocol?
    /// The device the engine is reading, for the notice when it changes.
    private var currentDeviceName = "unknown"
    private let queue = DispatchQueue(label: "transcriber.microphone", qos: .userInitiated)

    /// Everything below the lock is touched by the tap on the audio thread and
    /// by a restart on `queue`.
    private let stateLock = NSLock()
    private var running = false
    /// When the last buffer arrived, so a restart knows how much audio the
    /// engine lost while it was down.
    private var lastDelivery: Date?
    /// Set by a restart and consumed by the first buffer after it: the moment
    /// the old device went quiet, from which the gap is measured.
    private var resumedAfter: Date?

    var onGap: (@Sendable (Int) -> Void)?
    var onNotice: (@Sendable (CaptureNotice) -> Void)?
    var sampleRate: Double { monoFormat?.sampleRate ?? 0 }

    var diagnostics: String {
        let format = hardwareFormat.map { "\(Int($0.sampleRate)) Hz, \($0.channelCount) ch" }
            ?? "not open"
        return "microphone \(currentDeviceName) (\(format))"
    }

    init(deviceUID: String?) {
        self.deviceUID = deviceUID
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
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

        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                       channels: 1),
              let converter = AVAudioConverter(from: format, to: mono)
        else { throw AudioCapture.CaptureError.unsupportedFormat(format.sampleRate) }
        hardwareFormat = format
        monoFormat = mono
        toMono = converter
        currentDeviceName = Self.deviceName(pinned: deviceUID)
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

    /// The name of the device the engine reads: the pinned one, or the default.
    private static func deviceName(pinned uid: String?) -> String {
        uid.flatMap { AudioDevices.device(uid: $0)?.name }
            ?? AudioDevices.defaultInput()?.name ?? "unknown"
    }

    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws {
        guard let hardwareFormat, let toMono else {
            throw AudioCapture.CaptureError.noInputDevice
        }
        self.onFrames = onFrames
        try run(format: hardwareFormat, converter: toMono)
        stateLock.withLock { running = true }
        observeConfigurationChanges()
    }

    func stop() {
        stateLock.withLock { running = false }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        onFrames = nil
    }

    /// Installs the tap and starts the engine against `format`, converting to
    /// the session's mono format on the way out.
    private func run(format: AVAudioFormat, converter: AVAudioConverter) throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            [weak self] buffer, _ in
            guard let self else { return }
            // The first buffer after a restart: everything between the last
            // buffer of the old device and the start of this one was never
            // captured. Reported as a gap before this buffer, so the silence
            // lands where the hole is and every later timestamp stays put.
            let since: Date? = self.stateLock.withLock {
                defer { self.resumedAfter = nil }
                return self.resumedAfter
            }
            if let since {
                let covered = Double(buffer.frameLength) / buffer.format.sampleRate
                let lost = Int((Date().timeIntervalSince(since) - covered) * self.sampleRate)
                if lost > 0 { self.onGap?(lost) }
            }
            guard let mono = Self.downmix(buffer, with: converter) else { return }
            self.stateLock.withLock { self.lastDelivery = Date() }
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

    // MARK: Device changes

    /// `AVAudioEngine` stops itself when its input changes shape -- the pinned
    /// microphone is unplugged, or the default input moves to a device with
    /// another rate or channel count -- and posts this notification in place
    /// of an error. Left alone, the tap never fires again and the recording
    /// carries on with no audio in it, which on screen is a quiet room.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { self.restartAfterConfigurationChange() }
        }
    }

    /// Opens whatever microphone is available now and carries on.
    ///
    /// The pinned microphone if it is still attached; the system default when
    /// it is not. Falling back is the point: a recording that stops when a
    /// headset is unplugged loses the rest of the meeting, and one that
    /// pretends to continue loses it too, more quietly. Either way the user
    /// is told, because a room recorded through a headset is not the
    /// recording they asked for.
    private func restartAfterConfigurationChange() {
        guard stateLock.withLock({ running }), let monoFormat else { return }
        // A notification the engine survived is not a stop, and restarting
        // on it would put a gap into a recording that has none.
        guard !engine.isRunning else { return }

        let previousName = currentDeviceName
        let interrupted = stateLock.withLock { lastDelivery } ?? Date()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // The pinned microphone if it is still there; otherwise -- and when
        // this capture follows the default -- whatever macOS calls the default
        // now, pinned explicitly rather than left to the engine to re-resolve.
        let pinned = deviceUID.flatMap { AudioDevices.objectID(uid: $0) }
        let replaced = deviceUID != nil && pinned == nil
        guard let device = pinned ?? (try? CoreAudioObject.defaultInputDevice()),
              (try? pin(device)) != nil
        else {
            stateLock.withLock { running = false }
            onNotice?(.microphoneLost(previousName))
            return
        }

        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let converter = AVAudioConverter(from: format, to: monoFormat) else {
            stateLock.withLock { running = false }
            onNotice?(.microphoneLost(previousName))
            return
        }
        stateLock.withLock { resumedAfter = interrupted }
        do {
            try run(format: format, converter: converter)
        } catch {
            stateLock.withLock {
                running = false
                resumedAfter = nil
            }
            onNotice?(.captureFailed(error.localizedDescription))
            return
        }
        hardwareFormat = format
        let name = Self.deviceName(pinned: replaced ? nil : deviceUID)
        currentDeviceName = name
        if replaced {
            onNotice?(.microphoneReplaced(lost: previousName, now: name))
        } else if name != previousName {
            onNotice?(.microphoneChanged(now: name))
        }
    }

    /// Whatever the device delivers, as mono at the session's rate. After a
    /// restart the converter may also be changing the rate, so the output is
    /// sized by the ratio rather than assumed to match.
    private static func downmix(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                         frameCapacity: capacity),
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
    /// Mono at the aggregate's rate at `prepare`, for the whole session.
    private var monoFormat: AVAudioFormat?
    /// Mono at whatever rate the aggregate has now, when a rebuild changed it.
    private var currentFormat: AVAudioFormat?
    /// Per lane, from `currentFormat` back to `monoFormat`.
    private var resamplers: [CaptureLane: AVAudioConverter] = [:]

    var onGap: (@Sendable (Int) -> Void)? {
        get { tap.onGap }
        set { tap.onGap = newValue }
    }

    var onNotice: (@Sendable (CaptureNotice) -> Void)? {
        get { tap.onNotice }
        set { tap.onNotice = newValue }
    }

    var sampleRate: Double { monoFormat?.sampleRate ?? 0 }

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
        currentFormat = mono
    }

    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws {
        guard let monoFormat else {
            throw SystemAudioTap.TapError.unsupportedFormat
        }
        try tap.start { [weak self] list, frames in
            // The layout is read on every callback, not captured at start: a
            // rebuild around a new output device or a replaced microphone can
            // move the lanes to other channels, and a stale layout would put
            // the call in the room lane with nothing to say so.
            guard let self, let layout = self.tap.layout,
                  let format = self.inputFormat(at: layout.sampleRate, session: monoFormat)
            else { return }
            var delivered: [CaptureLane: AVAudioPCMBuffer] = [:]
            if let microphone = layout.microphone,
               let buffer = self.buffer(for: .room, format: format, frames: frames) {
                AudioBufferListReader.mixDown(microphone, of: list, frames: frames,
                                              into: buffer.floatChannelData![0])
                delivered[.room] = self.atSessionRate(buffer, lane: .room, session: monoFormat)
            }
            if let buffer = self.buffer(for: .remote, format: format, frames: frames) {
                AudioBufferListReader.mixDown(layout.system, of: list, frames: frames,
                                              into: buffer.floatChannelData![0])
                delivered[.remote] = self.atSessionRate(buffer, lane: .remote, session: monoFormat)
            }
            guard !delivered.isEmpty else { return }
            onFrames(delivered)
        }
    }

    func stop() {
        tap.stop()
        scratch = [:]
        resamplers = [:]
    }

    /// Mono at the aggregate's current rate: the session format itself until
    /// a rebuild changes the rate.
    private func inputFormat(at rate: Double, session: AVAudioFormat) -> AVAudioFormat? {
        if session.sampleRate == rate { return session }
        if let currentFormat, currentFormat.sampleRate == rate { return currentFormat }
        currentFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
        return currentFormat
    }

    /// The lane at the session's rate.
    ///
    /// An aggregate rebuilt around another device can come back at another
    /// rate, and the archive's rate was fixed when the file was created. The
    /// samples are converted rather than the file being told a lie about
    /// them, which would play the rest of the meeting fast or slow.
    private func atSessionRate(_ buffer: AVAudioPCMBuffer, lane: CaptureLane,
                               session: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format.sampleRate != session.sampleRate else { return buffer }
        if resamplers[lane]?.inputFormat.sampleRate != buffer.format.sampleRate {
            resamplers[lane] = AVAudioConverter(from: buffer.format, to: session)
        }
        guard let converter = resamplers[lane] else { return nil }
        let ratio = session.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: session, frameCapacity: capacity),
              converter.convertOnce(buffer, into: out)
        else { return nil }
        return out
    }

    /// Reused across callbacks. Everything downstream copies before it returns
    /// -- the archive deep-copies, the converter writes into its own buffer --
    /// so allocating two buffers a hundred times a second on the audio thread
    /// would buy nothing.
    private func buffer(for lane: CaptureLane, format: AVAudioFormat,
                        frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        if let existing = scratch[lane], existing.frameCapacity >= frames,
           existing.format.sampleRate == format.sampleRate {
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
