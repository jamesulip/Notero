import SwiftUI
import TranscriberCore
import TranscriberEngine

/// Test the microphone from Settings: record a take, hear it back, keep it.
///
/// The permission row says the app *may* use the microphone and the picker
/// says which one. Neither says whether the room is heard, whether the voice
/// clips, or whether a Bluetooth link drops syllables. Hearing the take is
/// the quick way to know, and it is the same 16 kHz copy the model gets.
///
/// Takes stay in the list, each with the microphone it came from, so the
/// user can change the microphone, record again and play the two in turn.
struct MicrophoneTestRow: View {
    @Environment(AppState.self) private var state
    let microphoneUID: String?

    @State private var check: MicrophoneCheck?
    /// Set while the device opens or closes, which happens off the main
    /// thread and can take seconds on a Bluetooth microphone.
    @State private var busy = false
    @State private var level: Float = 0
    @State private var elapsed = 0.0
    @State private var failure: String?
    @State private var clock: Timer?

    private var takes: MicrophoneTakes { state.microphoneTakes }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(check == nil ? "Test Microphone" : "Stop") {
                    check == nil ? start() : stop()
                }
                .disabled(busy || (check == nil && state.isLiveBusy))
                if busy {
                    ProgressView()
                        .controlSize(.small)
                    Text(check == nil ? "Opening the microphone…" : "Stopping…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if check != nil {
                    Text("Recording \(TimeFormat.short(ms: Int(elapsed * 1000)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    LevelBar(level: level)
                        .frame(width: 90, height: 6)
                } else if let failure = failure ?? takes.failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(takes.all) { take in
                TakeRow(take: take, playing: takes.playing == take.id,
                        play: { takes.play(take) }, stopPlaying: { takes.stopPlaying() },
                        remove: { takes.remove(take) })
            }
        }
        // A new microphone stops the take; the list keeps the old ones for
        // the comparison, and no capture outlives the pane.
        .onChange(of: microphoneUID) { _, _ in if check != nil { stop() } }
        .onDisappear {
            if check != nil { stop() }
            takes.stopPlaying()
        }
    }

    private var detail: String {
        if state.isLiveBusy, check == nil {
            return "Stop the recording before you test the microphone."
        }
        return "Click Test Microphone and speak. Click Stop to hear what the microphone "
             + "heard, with the Input boost and Room mode applied, at the quality the "
             + "transcription gets. Each take stays here with the name of its microphone, "
             + "so you can change the microphone and compare."
    }

    private func start() {
        guard !busy else { return }
        takes.stopPlaying()
        failure = nil
        busy = true
        let check = MicrophoneCheck(microphoneUID: microphoneUID)
        check.gainDb = state.settings.inputGainDb
        check.isRoomMode = state.settings.roomMode
        check.onLevel = { peak in
            Task { @MainActor in level = peak }
        }
        Task {
            do {
                try await check.startInBackground()
            } catch {
                failure = error.localizedDescription
                busy = false
                return
            }
            self.check = check
            busy = false
            level = 0
            elapsed = 0
            clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                Task { @MainActor in elapsed = check.seconds }
            }
        }
    }

    /// Ends the take and plays it at once.
    private func stop() {
        guard let check, !busy else { return }
        clock?.invalidate()
        clock = nil
        busy = true
        level = 0
        Task {
            let take = await check.stopInBackground()
            self.check = nil
            busy = false
            guard let take else { return }
            guard take.peak > 0.0001 else {
                failure = "The microphone heard nothing."
                return
            }
            takes.add(take)
            takes.play(take)
        }
    }
}

private struct TakeRow: View {
    let take: MicrophoneTake
    let playing: Bool
    let play: () -> Void
    let stopPlaying: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                playing ? stopPlaying() : play()
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(playing ? "Stop" : "Play this take")
            Text(take.microphone)
                .lineLimit(1)
            Text(TimeFormat.short(ms: Int(take.seconds * 1000)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(take.recorded, style: .time)
                .foregroundStyle(.secondary)
            if InputGain.isClipping(take.peak) {
                Label("Clipped", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            Button {
                remove()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove this take")
        }
        .font(.callout)
    }
}

/// A peak meter on the input-gain curve, so speech lands mid-bar instead of
/// in the bottom eighth of a linear one.
private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            let fraction = CGFloat(InputGain.meterFraction(level))
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(InputGain.isClipping(level) ? Color.red : Color.accentColor)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .animation(.linear(duration: 0.1), value: level)
    }
}
