import SwiftUI
import TranscriberCore
import TranscriberEngine

/// The list of recording devices, kept current while the window is open.
///
/// Devices come and go -- a headset is plugged in, an iPhone wanders into
/// Continuity range -- and a picker showing the list from launch offers
/// choices that no longer exist and hides the one the user just connected.
@Observable
final class AudioDeviceList {
    private(set) var devices: [AudioDevice] = AudioDevices.inputs()
    private(set) var defaultName: String = AudioDevices.defaultInput()?.name ?? "system default"
    private var observation: AudioDevices.Observation?

    init() {
        observation = AudioDevices.watch { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        devices = AudioDevices.inputs()
        defaultName = AudioDevices.defaultInput()?.name ?? "system default"
    }
}

/// Which microphone to record from.
///
/// "Default device" is stored as no selection rather than as the UID of
/// whatever is default today. The difference shows up the moment a headset is
/// plugged in: following the system is a standing instruction, while a stored
/// UID is a decision that silently stops matching what the rest of the Mac is
/// doing.
struct InputDevicePicker: View {
    @Binding var selection: String?
    @State private var list = AudioDeviceList()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker("Microphone", selection: $selection) {
                Text("Default device — \(list.defaultName)").tag(String?.none)
                Divider()
                ForEach(list.devices) { device in
                    Text(device.name).tag(String?.some(device.uid))
                }
            }

            if let selection, list.devices.allSatisfy({ $0.uid != selection }) {
                Label("That microphone is not connected. Recording will fail until "
                      + "it is back or another one is chosen.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { list.refresh() }
    }
}
