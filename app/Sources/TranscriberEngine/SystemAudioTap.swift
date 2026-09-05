import AVFoundation
import CoreAudio
import Foundation
import TranscriberCore

/// What the Mac is playing, captured before it reaches the speakers -- and,
/// when asked, the microphone alongside it on the same clock.
///
/// The microphone answers "who is in the room"; this answers "who is on the
/// call". In a hybrid meeting they are different people, and the microphone's
/// copy of a remote voice -- through a speaker, off a wall, into a far-field
/// mic three metres away -- is the worst recording of that voice available.
/// This is the clean one.
///
/// Core Audio process taps rather than ScreenCaptureKit: this is audio-only
/// work, and SCStream would charge Screen Recording permission, a purple menu
/// bar indicator and a re-consent prompt every month for pixels nobody wants.
/// The tap has its own TCC category and no indicator.
///
/// The shape Core Audio requires is roundabout and worth stating once. A tap
/// is not a device and cannot be read directly: it has to be adopted as a
/// sub-tap of a private aggregate device built around the real output device,
/// and the aggregate is then read like any other input. `AVAudioEngine` cannot
/// be pointed at that aggregate -- setting `kAudioOutputUnitProperty_CurrentDevice`
/// returns `noErr` and then quietly ignores it -- so this class installs an
/// IOProc directly rather than reusing the engine the microphone path uses.
///
/// Adopting the microphone into the same aggregate is what makes a two-lane
/// recording trustworthy. Two separate captures run on two crystals: about
/// 50 ppm apart, which is a third of a second of slip over a two-hour meeting,
/// growing the whole time. One aggregate has one clock and drift-compensates
/// everything else against it, so the lanes cannot come apart no matter how
/// long the meeting runs.
public final class SystemAudioTap: @unchecked Sendable {

    /// Where each lane's channels sit inside the buffers the IOProc delivers.
    ///
    /// An aggregate presents its sub-devices' input channels first, in the
    /// order they were listed, and its taps' channels after them.
    public struct Layout: Sendable {
        public let sampleRate: Double
        public let totalChannels: Int
        /// Microphone channels, when the microphone was adopted too.
        public let microphone: Range<Int>?
        /// The system audio channels.
        public let system: Range<Int>
    }

    public private(set) var layout: Layout?
    public private(set) var isRunning = false

    /// The microphone to adopt alongside the tap, by UID; nil for system audio
    /// only, and nil inside a combined capture means "whatever is default".
    private let microphoneUID: String?
    private let wantsMicrophone: Bool

    private let stateLock = NSLock()
    private var tap: AudioObjectID = .unknown
    private var aggregate: AudioObjectID = .unknown
    private var procID: AudioDeviceIOProcID?
    private var onAudio: (@Sendable (UnsafePointer<AudioBufferList>, AVAudioFrameCount) -> Void)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private let keepAlive = OutputKeepAlive()
    private let queue = DispatchQueue(label: "transcriber.system-audio", qos: .userInitiated)

    /// Called when the default output device changes and the tap had to be
    /// rebuilt around the new one, with the frames lost while it happened.
    ///
    /// Plugging in headphones mid-meeting invalidates the aggregate: the whole
    /// thing has to be torn down and built again, and that takes long enough
    /// to hear. Reporting the gap rather than swallowing it lets the caller
    /// write that many samples of silence and keep every later timestamp
    /// pinned to wall-clock, which is the bargain `isMuted` already makes.
    public var onGap: (@Sendable (Int) -> Void)?

    /// - Parameters:
    ///   - withMicrophone: adopt a microphone into the same aggregate, so both
    ///     lanes arrive in one callback on one clock.
    ///   - microphoneUID: which microphone, or nil for the system default.
    public init(withMicrophone: Bool = false, microphoneUID: String? = nil) {
        self.wantsMicrophone = withMicrophone
        self.microphoneUID = microphoneUID
    }

    // MARK: - Lifecycle

    /// Creates the tap, the aggregate and the IOProc, and works out the
    /// channel layout -- everything except letting audio flow.
    ///
    /// Separate from `start` because the sample rate is a property of the
    /// aggregate, and the caller has to build its converters and filters
    /// around that rate before the first buffer arrives. Asking afterwards
    /// would mean discarding whatever came in the meantime.
    public func prepare() throws {
        guard aggregateIsBuilt == false else { return }
        try build()
    }

    private var aggregateIsBuilt: Bool { stateLock.withLock { aggregate != .unknown } }

    public func start(
        onAudio: @escaping @Sendable (UnsafePointer<AudioBufferList>, AVAudioFrameCount) -> Void
    ) throws {
        guard !isRunning else { return }
        stateLock.withLock { self.onAudio = onAudio }
        try prepare()
        // Before the device is started, because the thing it prevents is the
        // device never starting at all.
        keepAlive.start()
        let (device, proc) = stateLock.withLock { (aggregate, procID) }
        // Permission is decided here and nowhere else, and a refusal is not an
        // error: `AudioDeviceStart` returns `noErr`, the device never runs, and
        // no callback ever arrives. `SystemAudioAccess` is checked before this
        // for exactly that reason.
        guard AudioDeviceStart(device, proc) == noErr else {
            throw TapError.notPermitted
        }
        installDeviceListener()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        removeDeviceListener()
        keepAlive.stop()
        tearDown()
        stateLock.withLock { onAudio = nil }
        isRunning = false
    }

    deinit {
        removeDeviceListener()
        keepAlive.stop()
        tearDown()
    }

    // MARK: - Construction

    private func build() throws {
        // A global tap, deliberately, including this process.
        //
        // The obvious thing is to exclude ourselves: Notero plays recordings
        // back through the output it is tapping, and recording a recording
        // while transcribing it is a feedback loop with text in it. Measured,
        // that costs more than it saves. A tap that excludes this process has
        // nothing to tap while this process is the only one playing -- so the
        // silence `OutputKeepAlive` renders to hold the device open does not
        // reach it, the aggregate idles anyway, and both lanes go with it. On
        // a nine-second capture that was 4.8 seconds of missing room audio.
        // Global, the same test captured every second of it.
        //
        // What this costs is bounded and handled elsewhere: the app pauses
        // playback for the length of a recording, so the only thing of ours
        // the tap ever hears is the keep-alive's silence.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Notero System Audio"
        // Set here and never touched again: on the exclude-processes
        // initializer, assigning `isExclusive` afterwards does not relax a
        // lock, it flips the list from "everything except these" to "only
        // these" -- which is silence, because the excluded process is us.
        description.isPrivate = true

        var tapID: AudioObjectID = .unknown
        try CoreAudioObject.check(AudioHardwareCreateProcessTap(description, &tapID),
                                  "create the system audio tap")

        let output = try CoreAudioObject.defaultOutputDevice()
        let outputUID = try CoreAudioObject.uid(of: output)

        // The microphone joins as a sub-device rather than as a second
        // capture, and when it is here it is also the clock.
        //
        // Not a detail. An aggregate built around the output device only runs
        // its IO while something is playing: with the Mac silent the callbacks
        // simply stop, and every lane stops with them -- including the
        // microphone, in the middle of a meeting, exactly when the room is the
        // only thing happening. A microphone in use never idles, so making it
        // the main sub-device keeps the whole device running and leaves the
        // tap to deliver silence when there is nothing to hear, which is what
        // silence is supposed to look like.
        var microphone: (uid: String, channels: Int)?
        if wantsMicrophone {
            let device = try microphoneUID.flatMap { AudioDevices.objectID(uid: $0) }
                ?? CoreAudioObject.defaultInputDevice()
            let uid = try CoreAudioObject.uid(of: device)
            let channels = (try? CoreAudioObject.inputChannelCount(of: device)) ?? 0
            if channels > 0 { microphone = (uid, channels) }
        }

        // Order matters twice over: the first entry is the clock, and the
        // aggregate presents input channels in this order.
        var ordered: [(uid: String, channels: Int)] = []
        if let microphone { ordered.append(microphone) }
        ordered.append((outputUID, (try? CoreAudioObject.inputChannelCount(of: output)) ?? 0))

        let main = microphone?.uid ?? outputUID
        let subDevices: [[String: Any]] = ordered.map { device in
            var entry: [String: Any] = [kAudioSubDeviceUIDKey: device.uid]
            // Everything that is not the clock gets resampled against it.
            if device.uid != main { entry[kAudioSubDeviceDriftCompensationKey] = 1 }
            return entry
        }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notero Capture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: main,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]

        var aggregateID: AudioObjectID = .unknown
        let created = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        guard created == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw CoreAudioObject.error(created, "create the capture device")
        }

        do {
            let layout = try Self.layout(of: aggregateID, subDevices: ordered,
                                         microphoneUID: microphone?.uid)
            self.layout = layout

            var proc: AudioDeviceIOProcID?
            try CoreAudioObject.check(
                AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) {
                    [weak self] _, input, _, _, _ in
                    self?.deliver(input, channels: layout.totalChannels)
                },
                "listen to the capture device"
            )

            stateLock.withLock {
                self.tap = tapID
                self.aggregate = aggregateID
                self.procID = proc
            }
        } catch {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
    }

    /// Works out which channels belong to which lane.
    ///
    /// Derived from the sub-device list as it was actually built and from what
    /// the aggregate reports, rather than from what was asked for: an output
    /// device with inputs of its own -- a display, an audio interface -- shifts
    /// everything along, and getting this wrong swaps the room lane with the
    /// call lane silently, which nothing downstream can detect.
    private static func layout(of aggregate: AudioObjectID,
                               subDevices: [(uid: String, channels: Int)],
                               microphoneUID: String?) throws -> Layout {
        let total = try CoreAudioObject.inputChannelCount(of: aggregate)
        guard total > 0 else { throw TapError.unsupportedFormat }
        let rate = try CoreAudioObject.sampleRate(of: aggregate)

        var cursor = 0
        var microphone: Range<Int>?
        for device in subDevices {
            let range = cursor..<min(total, cursor + device.channels)
            if device.uid == microphoneUID, !range.isEmpty { microphone = range }
            cursor += device.channels
        }
        // The taps come after every sub-device. Trust the reported total over
        // the sum of the parts: if they disagree the aggregate did something
        // unexpected, and the tap is still the last thing in the list.
        let system = min(cursor, max(0, total - 1))..<total
        return Layout(sampleRate: rate, totalChannels: total,
                      microphone: microphone, system: system)
    }

    private func tearDown() {
        let (tapID, aggregateID, proc) = stateLock.withLock {
            defer {
                tap = .unknown
                aggregate = .unknown
                procID = nil
            }
            return (tap, aggregate, procID)
        }
        if aggregateID != .unknown, let proc {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        if aggregateID != .unknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID) }
    }

    // MARK: - Delivery

    private func deliver(_ list: UnsafePointer<AudioBufferList>, channels: Int) {
        let onAudio = stateLock.withLock { self.onAudio }
        guard let onAudio else { return }
        let frames = AudioBufferListReader.frameCount(of: list, channels: channels)
        guard frames > 0 else { return }
        // Handed on without copying: this is the audio thread, and the chain
        // above deep-copies before anything outlives the callback.
        onAudio(list, frames)
    }

    // MARK: - Output device changes

    private func installDeviceListener() {
        var address = CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebuildForNewOutputDevice()
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(CoreAudioObject.system, &address, queue, listener)
    }

    private func removeDeviceListener() {
        guard let listener = deviceListener else { return }
        var address = CoreAudioObject.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(CoreAudioObject.system, &address, queue, listener)
        deviceListener = nil
    }

    private func rebuildForNewOutputDevice() {
        guard isRunning else { return }
        let rate = layout?.sampleRate ?? Double(Audio.sampleRate)
        let started = Date()
        tearDown()
        do {
            try build()
            let (device, proc) = stateLock.withLock { (aggregate, procID) }
            guard AudioDeviceStart(device, proc) == noErr else {
                throw TapError.notPermitted
            }
        } catch {
            // Nothing to fall back to. A combined recording carries on with
            // the microphone lane, and the caller sees the gap keep growing
            // rather than a claim that all is well.
            isRunning = false
        }
        let lost = Int(Date().timeIntervalSince(started) * rate)
        if lost > 0 { onGap?(lost) }
    }

    public enum TapError: LocalizedError {
        case unsupportedFormat
        case notPermitted
        case coreAudio(OSStatus, String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "This Mac's audio output uses a format that cannot be captured."
            case .notPermitted:
                return "Notero is not allowed to record this Mac's audio. Allow it in "
                     + "System Settings › Privacy & Security › System Audio Recording, "
                     + "then start the recording again."
            case .coreAudio(let status, let what):
                return "Could not \(what) (Core Audio error \(status))."
            }
        }
    }
}

/// Reads one channel out of whatever shape Core Audio delivered.
///
/// The same aggregate can present its input as one interleaved buffer or as
/// one buffer per stream, and which one it picks is not something the caller
/// gets to choose. Walking the list and counting channels handles both without
/// a special case at every use.
enum AudioBufferListReader {

    static func frameCount(of list: UnsafePointer<AudioBufferList>,
                           channels: Int) -> AVAudioFrameCount {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, first.mNumberChannels > 0 else { return 0 }
        let bytesPerSample = MemoryLayout<Float>.size
        return AVAudioFrameCount(Int(first.mDataByteSize)
                                 / (bytesPerSample * Int(first.mNumberChannels)))
    }

    /// Averages `channels` into `destination`, which is how a stereo lane
    /// becomes the mono the archive and the model both want. Averaging rather
    /// than summing: two correlated channels summed clip at half scale.
    static func mixDown(_ range: Range<Int>, of list: UnsafePointer<AudioBufferList>,
                        frames: AVAudioFrameCount,
                        into destination: UnsafeMutablePointer<Float>) {
        let count = Int(frames)
        for index in 0..<count { destination[index] = 0 }
        guard !range.isEmpty else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var channelBase = 0
        var mixed = 0
        for buffer in buffers {
            let width = Int(buffer.mNumberChannels)
            defer { channelBase += width }
            guard let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let available = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * max(1, width))
            let usable = min(count, available)
            for local in 0..<width where range.contains(channelBase + local) {
                for frame in 0..<usable {
                    destination[frame] += samples[frame * width + local]
                }
                mixed += 1
            }
        }
        guard mixed > 1 else { return }
        let scale = 1 / Float(mixed)
        for index in 0..<count { destination[index] *= scale }
    }
}


/// Renders silence to the default output for as long as a tap is running.
///
/// Not a workaround for a bug -- it is how the hardware works. An output
/// device with nothing to play stops running its IO, and an aggregate built
/// around one stops with it: no callbacks, on any lane, including the
/// microphone. Measured on a MacBook Pro, a nine-second capture of a quiet
/// room yielded 4.2 seconds of audio, and the missing 4.8 were simply the
/// stretches when the Mac had nothing to say.
///
/// Silence from this process is not recorded by the tap that needs it: the tap
/// is created excluding this process, for the separate reason that Notero
/// plays recordings back.
///
/// The cost is that the speakers stay powered for the length of a meeting,
/// which in a meeting they were going to be anyway.
final class OutputKeepAlive: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard engine == nil else { return }

        let engine = AVAudioEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        let source = AVAudioSourceNode(format: format) { _, _, _, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            for buffer in list {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            // Nothing to do about it here. The capture still runs; it will
            // just have holes wherever the Mac was quiet, and the gap
            // reporting is what makes those visible rather than silent.
            engine.detach(source)
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        engine?.stop()
        engine = nil
    }
}
