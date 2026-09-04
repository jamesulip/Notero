import AppKit
import SwiftUI
import TranscriberEngine

/// Microphone permission, asked for here rather than mid-meeting.
///
/// The app needs one permission and normally requests it at the moment
/// recording starts. That is the worst moment to be refused, because a refused
/// microphone delivers silence instead of an error -- the recording runs, the
/// transcript comes back empty, and nothing anywhere says why.
///
/// The button changes with the state because macOS only prompts once. On an
/// app that has already been denied, `requestAccess` returns the stored answer
/// without showing anything, so offering to ask again would be offering a
/// button that does nothing.
struct MicrophonePermissionRow: View {
    @State private var access = MicrophoneAccess.current
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text("Microphone access")
                Spacer(minLength: 8)
                Text(access.label)
                    .foregroundStyle(.secondary)
                action
            }

            Text(access.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Re-read on activation, so granting it in System Settings and coming
        // back shows the new state instead of the stale one.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            access = .current
        }
        .onAppear { access = .current }
    }

    @ViewBuilder
    private var action: some View {
        if access.canRequest {
            Button("Ask Permission") {
                asking = true
                Task {
                    access = await MicrophoneAccess.request()
                    asking = false
                }
            }
            .disabled(asking)
        } else if access.needsSystemSettings {
            Button("Open System Settings") {
                NSWorkspace.shared.open(MicrophoneAccess.systemSettingsURL)
            }
        }
    }

    private var symbol: String {
        switch access {
        case .granted: return "checkmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "exclamationmark.triangle.fill"
        case .restricted: return "lock.fill"
        }
    }

    private var tint: Color {
        switch access {
        case .granted: return .green
        case .notDetermined: return .secondary
        case .denied, .restricted: return .orange
        }
    }
}
