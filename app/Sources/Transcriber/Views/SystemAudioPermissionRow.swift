import AppKit
import SwiftUI
import TranscriberEngine

/// Permission to record what this Mac plays, asked for here rather than
/// mid-meeting.
///
/// A separate permission from the microphone, with a worse failure. A refused
/// microphone at least records silence; a refused system tap records nothing
/// at all and reports success while doing it -- Core Audio starts the device,
/// returns no error, and never delivers a sample. A hybrid meeting recorded
/// without this is a transcript with one side of the conversation missing and
/// nothing anywhere to say why.
struct SystemAudioPermissionRow: View {
    @State private var access = SystemAudioAccess.current
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    title
                    Spacer(minLength: 8)
                    status.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    status
                }
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

    private var title: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text("System audio access")
        }
        .fixedSize()
    }

    private var status: some View {
        HStack(spacing: 7) {
            Text(access.label)
                .foregroundStyle(.secondary)
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        if access.canRequest {
            Button("Ask Permission") {
                asking = true
                Task {
                    access = await SystemAudioAccess.request()
                    asking = false
                }
            }
            .disabled(asking)
        } else if access.needsSystemSettings {
            Button("Open System Settings") {
                NSWorkspace.shared.open(SystemAudioAccess.systemSettingsURL)
            }
        }
    }

    private var symbol: String {
        switch access {
        case .granted: return "checkmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch access {
        case .granted: return .green
        case .notDetermined, .unknown: return .secondary
        case .denied: return .orange
        }
    }
}
