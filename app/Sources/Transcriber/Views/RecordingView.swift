import SwiftUI
import TranscriberCore
import TranscriberStore

/// The live screen. Everything on it is transient except the committed text.
struct RecordingView: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .opacity(state.live.isMuted ? 0.3 : 1)
                        .symbolEffect(.pulse, isActive: true)
                    Text(state.live.isMuted ? "Muted" : "Recording")
                        .font(.headline)
                }

                Text(TimeFormat.short(ms: state.live.elapsedMs))
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                LevelMeter(samples: state.live.meter, level: state.live.level)
                    .frame(height: 64)
                    .padding(.horizontal, 40)

                InputGainSlider(gainDb: Binding(
                    get: { state.settings.inputGainDb },
                    set: { state.setInputGain($0) }
                ), isClipping: InputGain.isClipping(state.live.level))
                .padding(.horizontal, 40)

                Toggle(isOn: Binding(
                    get: { state.settings.roomMode },
                    set: { state.setRoomMode($0) }
                )) {
                    Label("Room mode", systemImage: "person.3")
                }
                .toggleStyle(.button)
                .help("Filters out low-frequency room noise before transcription. "
                    + "For a mic picking up a table rather than a person. "
                    + "The saved recording is not affected.")

                HStack(spacing: 16) {
                    Button {
                        state.live.isMuted.toggle()
                    } label: {
                        Label(state.live.isMuted ? "Unmute" : "Mute",
                              systemImage: state.live.isMuted ? "mic.slash.fill" : "mic.fill")
                    }

                    Button {
                        Task { await state.stopRecording() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(minWidth: 76)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(".", modifiers: .command)

                    Button {
                        _ = state.addBookmark()
                    } label: {
                        Label("Bookmark", systemImage: "bookmark")
                    }
                    .help("Bookmark this moment (⌘B)")
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(.background.secondary)

            Divider()
            liveTranscript
            Divider()
            footer
        }
    }

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(state.live.segments) { segment in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(TimeFormat.short(ms: segment.startMs))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 52, alignment: .trailing)
                            Text(segment.displayText)
                                .textSelection(.enabled)
                        }
                        .id(segment.id)
                    }

                    if !state.live.partial.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("")
                                .frame(width: 52)
                            // Provisional. It may be rewritten by the next pass;
                            // committed text above it never will be.
                            Text(state.live.partial)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .id("partial")
                    }

                    if state.live.segments.isEmpty && state.live.partial.isEmpty {
                        Text("Listening…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: state.live.segments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(state.live.segments.last?.id ?? "partial" as AnyHashable,
                                   anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label(state.live.vadBackend == "silero" ? "Silero VAD" : "Energy VAD",
                  systemImage: "waveform.badge.mic")
            if state.live.stats.hops > 0 {
                Label(String(format: "RTF %.2f", state.live.stats.meanRtf),
                      systemImage: "speedometer")
                    .help("Decode time over audio duration. Below 1.0 keeps up with live audio.")
            }
            if state.live.stats.droppedHops > 0 {
                Label("\(state.live.stats.droppedHops) dropped",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Decode windows skipped because the previous one was still running.")
            }
            Spacer()
            Text(state.settings.language == "auto"
                 ? "Auto-detect"
                 : (LanguageCatalogue.option(state.settings.language)?.label ?? state.settings.language))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
