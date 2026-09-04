import SwiftUI
import TranscriberCore

/// The one window the updater has. Every phase of `Updater.Phase` says its
/// piece here, including the refusals: a build with no update key and an app
/// in a folder it cannot write both explain themselves and offer the releases
/// page, rather than showing a button that would fail.
struct UpdateSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var updater: Updater { state.updater }

    /// Quitting mid-recording would end the recording. The install button is
    /// off until it stops; a queued transcription only earns a caution,
    /// because launch-time recovery picks those up again.
    private var isRecording: Bool { state.isLiveBusy }
    private var isTranscribing: Bool { state.progress.values.contains { $0.status.isBusy } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            body(for: updater.phase)
            Spacer(minLength: 0)
            Divider()
            buttons(for: updater.phase)
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcriber").font(.headline)
                Text("Version \(updater.versionText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for phase: Updater.Phase) -> some View {
        switch phase {
        case .idle:
            message("Check whether a newer version has been released.")

        case .checking:
            waiting("Asking GitHub for the list of releases…")

        case .upToDate:
            VStack(alignment: .leading, spacing: 8) {
                Label("This is the newest version.", systemImage: "checkmark.circle")
                    .font(.body.weight(.medium))
                if let last = updater.lastChecked { checkedLine(last) }
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                Text("Version \(String(describing: release.version)) is available.")
                    .font(.body.weight(.medium))
                if let size = size(of: release) {
                    Text("Download \(size). The update is checked against the "
                         + "maintainer's signature before anything is replaced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                notes(release)
            }

        case .downloading(let release, let fraction):
            VStack(alignment: .leading, spacing: 10) {
                Text("Downloading version \(String(describing: release.version))…")
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

        case .verifying:
            waiting("Checking the signature and unpacking…")

        case .ready(let release, _):
            VStack(alignment: .leading, spacing: 10) {
                Label("Version \(String(describing: release.version)) is ready to install.",
                      systemImage: "checkmark.seal")
                    .font(.body.weight(.medium))
                Text("Transcriber quits, the new version replaces this one, and it "
                     + "opens again. Your recordings and settings are untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isRecording {
                    caution("A recording is running. Stop it before you install.")
                } else if isTranscribing {
                    caution("A transcription is running. It starts again when the "
                            + "app reopens.")
                }
                notes(release)
            }

        case .quitting:
            waiting("Quitting to install the update…")

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                Label("The update did not go through.", systemImage: "exclamationmark.triangle")
                    .font(.body.weight(.medium))
                ScrollView {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("This copy has not been changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private func buttons(for phase: Updater.Phase) -> some View {
        HStack {
            switch phase {
            case .available(let release):
                Button("Skip This Version") { updater.skip(release) }
                Spacer()
                Button("Later") { dismiss() }
                Button("Update") { updater.download(release) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!updater.canInstall)

            case .ready(let release, let unpacked):
                Button("Show in Finder") { updater.revealInFinder(unpacked) }
                Spacer()
                Button("Later") { dismiss() }
                Button("Install and Relaunch") { updater.install(release, from: unpacked) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRecording)

            case .checking, .downloading, .verifying:
                Spacer()
                Button("Cancel") { updater.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)

            case .quitting:
                Spacer()
                ProgressView().controlSize(.small)

            case .failed:
                Button("Open Releases Page") { updater.openReleasesPage() }
                Spacer()
                Button("Done") { updater.cancel(); dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .idle, .upToDate:
                Button("Open Releases Page") { updater.openReleasesPage() }
                Spacer()
                Button("Check Again") { updater.checkNow() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Pieces

    private func message(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
            if !updater.canInstall { keyWarning }
            if let last = updater.lastChecked { checkedLine(last) }
        }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func caution(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checkedLine(_ date: Date) -> some View {
        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened)).")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Shown whenever the app cannot install for itself, so the user is never
    /// left wondering why the button did nothing.
    private var keyWarning: some View {
        Label(UpdateSource.canInstall
              ? "This copy is not running from an installed app, so it cannot replace itself."
              : "This build carries no update key, so it cannot check that a download "
                + "is genuine. It will not install one.",
              systemImage: "lock.slash")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func notes(_ release: Release) -> some View {
        if !release.notes.isEmpty {
            GroupBox {
                ScrollView {
                    Text(release.notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private func size(of release: Release) -> String? {
        guard let bytes = release.appZip?.size, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
