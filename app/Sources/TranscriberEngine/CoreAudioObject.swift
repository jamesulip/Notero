import CoreAudio
import Foundation

/// The `AudioObjectGetPropertyData` dance, once, instead of at twenty call sites.
///
/// Core Audio's property interface is four out-parameters and a manual size
/// negotiation for every question, however small. None of that is interesting
/// anywhere else in this target, so it is all in here and everything above
/// asks in one line and gets a Swift value or a thrown error.
enum CoreAudioObject {

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func error(_ status: OSStatus, _ what: String) -> SystemAudioTap.TapError {
        .coreAudio(status, what)
    }

    static func check(_ status: OSStatus, _ what: String) throws {
        guard status != noErr else { return }
        throw error(status, what)
    }

    // MARK: - Devices

    static func defaultOutputDevice() throws -> AudioObjectID {
        try read(system, selector: kAudioHardwarePropertyDefaultOutputDevice,
                 as: AudioObjectID.self, what: "find the output device")
    }

    static func defaultInputDevice() throws -> AudioObjectID {
        try read(system, selector: kAudioHardwarePropertyDefaultInputDevice,
                 as: AudioObjectID.self, what: "find the microphone")
    }

    static func allDevices() throws -> [AudioObjectID] {
        try readArray(system, selector: kAudioHardwarePropertyDevices,
                      as: AudioObjectID.self, what: "list the audio devices")
    }

    static func uid(of device: AudioObjectID) throws -> String {
        try string(device, selector: kAudioDevicePropertyDeviceUID,
                   what: "identify the audio device")
    }

    static func name(of device: AudioObjectID) throws -> String {
        try string(device, selector: kAudioObjectPropertyName,
                   what: "read the audio device name")
    }

    static func sampleRate(of device: AudioObjectID) throws -> Double {
        try read(device, selector: kAudioDevicePropertyNominalSampleRate,
                 as: Float64.self, what: "read the audio device sample rate")
    }

    static func isRunning(_ device: AudioObjectID) throws -> Bool {
        try read(device, selector: kAudioDevicePropertyDeviceIsRunning,
                 as: UInt32.self, what: "check the capture device") != 0
    }

    /// Channels a device offers in one direction. For an aggregate this is the
    /// sum over everything adopted into it, which is how the combined capture
    /// works out where the microphone ends and the tap begins.
    static func channelCount(of device: AudioObjectID,
                             scope: AudioObjectPropertyScope) throws -> Int {
        var address = self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr
        else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func inputChannelCount(of device: AudioObjectID) throws -> Int {
        try channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    }

    // MARK: - Property reads

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                                as type: T.Type, what: String) throws -> T {
        var address = self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<T>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw), what)
        return raw.assumingMemoryBound(to: T.self).pointee
    }

    private static func readArray<T>(_ object: AudioObjectID,
                                     selector: AudioObjectPropertySelector,
                                     as type: T.Type, what: String) throws -> [T] {
        var address = self.address(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), what)
        let count = Int(size) / MemoryLayout<T>.size
        guard count > 0 else { return [] }
        var values = [T](unsafeUninitializedCapacity: count) { _, initialized in
            initialized = count
        }
        try values.withUnsafeMutableBytes { raw in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                                 raw.baseAddress!), what)
        }
        return values
    }

    /// A `CFString` property arrives retained. Loading the pointee and letting
    /// ARC take a second reference leaks the first one, once per device per
    /// refresh -- which the device picker does on every hot-plug.
    private static func string(_ object: AudioObjectID,
                               selector: AudioObjectPropertySelector,
                               what: String) throws -> String {
        var address = self.address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        try check(withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }, what)
        guard let value else { throw error(kAudioHardwareUnknownPropertyError, what) }
        return value.takeRetainedValue() as String
    }
}

extension AudioObjectID {
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}
