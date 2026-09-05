import CoreAudio
import Foundation

/// One audio device, as the picker needs it.
///
/// Identified by UID rather than by `AudioObjectID`: object ids are handed out
/// per boot and reused, so a stored id points at whatever device happens to
/// hold that number next week. The UID is stable across reboots, sleep and
/// unplugging, which is the only property a saved preference can be built on.
public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let uid: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int

    public var id: String { uid }
    public var canRecord: Bool { inputChannels > 0 }
    public var canPlay: Bool { outputChannels > 0 }
}

/// The devices this Mac has, and which one a recording should use.
///
/// The app had no picker at all before this: capture opened `AVAudioEngine`'s
/// input node, which follows whatever macOS currently calls the default input.
/// That is the right default and the wrong only option -- plugging in a
/// headset mid-meeting moves a room recording onto a headset microphone with
/// nothing on screen to say it happened, and there was no way to pin the
/// conference microphone in advance.
public enum AudioDevices {

    /// Every device that can record, default first.
    ///
    /// "Default" is offered as an absent selection rather than as an entry
    /// here: a picker that stores today's default device by UID stops
    /// following the system the moment the user touches it, which is not what
    /// choosing "Default device" means to anyone.
    public static func inputs() -> [AudioDevice] {
        all().filter(\.canRecord)
    }

    public static func all() -> [AudioDevice] {
        guard let ids = try? CoreAudioObject.allDevices() else { return [] }
        return ids.compactMap(describe)
    }

    public static func defaultInput() -> AudioDevice? {
        guard let id = try? CoreAudioObject.defaultInputDevice() else { return nil }
        return describe(id)
    }

    public static func defaultOutput() -> AudioDevice? {
        guard let id = try? CoreAudioObject.defaultOutputDevice() else { return nil }
        return describe(id)
    }

    /// The named device, or nil when it is no longer attached.
    public static func device(uid: String) -> AudioDevice? {
        all().first { $0.uid == uid }
    }

    static func objectID(uid: String) -> AudioObjectID? {
        guard let ids = try? CoreAudioObject.allDevices() else { return nil }
        return ids.first { (try? CoreAudioObject.uid(of: $0)) == uid }
    }

    private static func describe(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = try? CoreAudioObject.uid(of: id),
              let name = try? CoreAudioObject.name(of: id) else { return nil }
        return AudioDevice(
            uid: uid,
            name: name,
            inputChannels: (try? CoreAudioObject.channelCount(
                of: id, scope: kAudioObjectPropertyScopeInput)) ?? 0,
            outputChannels: (try? CoreAudioObject.channelCount(
                of: id, scope: kAudioObjectPropertyScopeOutput)) ?? 0
        )
    }

    /// Calls back when devices appear or disappear, or when the default
    /// changes. Hold the returned object; releasing it stops the callbacks.
    public static func watch(_ onChange: @escaping @Sendable () -> Void) -> Observation {
        Observation(onChange)
    }

    public final class Observation: @unchecked Sendable {
        private let queue = DispatchQueue(label: "transcriber.audio-devices")
        private let block: AudioObjectPropertyListenerBlock
        private let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
        ]

        init(_ onChange: @escaping @Sendable () -> Void) {
            block = { _, _ in onChange() }
            for selector in selectors {
                var address = CoreAudioObject.address(selector)
                AudioObjectAddPropertyListenerBlock(CoreAudioObject.system, &address,
                                                    queue, block)
            }
        }

        deinit {
            for selector in selectors {
                var address = CoreAudioObject.address(selector)
                AudioObjectRemovePropertyListenerBlock(CoreAudioObject.system, &address,
                                                       queue, block)
            }
        }
    }
}
