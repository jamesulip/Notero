import SwiftUI
import TranscriberCore
import TranscriberStore

/// The live screen. Everything on it is transient except the committed text.
struct RecordingView: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    /// The model is still loading. Capture has not started, so there is no
    /// elapsed time, no level and nothing to mute yet -- but there is very
    /// much something to say.
    private var isPreparing: Bool { !state.live.state.isRecording }

    /// Specifically the model load, as opposed to `.finishing`, which uses the
    /// same header on the way out and should not be told the model loads once.
    private var isLoadingModel: Bool {
        if case .preparing = state.live.state { return true }
        return false
    }

    /// "large-v3-turbo · 1.6 GB · English".
    private var modelSummary: String {
        let id = state.settings.liveModelId
        let model = ModelCatalogue.option(id)
        let language = state.settings.language == "auto"
            ? "Auto-detect"
            : (LanguageCatalogue.option(state.settings.language)?.label
               ?? state.settings.language)
        return [model?.label ?? id, model?.sizeLabel, language]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            if isPreparing { preparingHeader } else { recordingHeader }

            Divider()
            liveTranscript
            Divider()
            footer
        }
    }

    private var preparingHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if state.live.state.fraction == nil {
                    ProgressView()
                        .controlSize(.small)
                }
                // WhisperKit's own message: "Loading large-v3-turbo…", or the
                // download and its size when the model is not on disk yet.
                Text(state.live.state.label)
                    .font(.headline)
            }
            if let fraction = state.live.state.fraction {
                // A download has a length; a spinner over 1.6 GB reads as a hang.
                HStack(spacing: 10) {
                    ProgressView(value: fraction)
                        .frame(width: 260)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                }
            }
            if isLoadingModel {
                // Named here rather than left to WhisperKit's progress string,
                // which only says "Loading" once the file is found.
                Text(modelSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The model loads once. Recordings after this one start immediately.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
        .background(.background.secondary)
    }

    private var recordingHeader: some View {
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
                        VStack(spacing: 6) {
                            Text(isPreparing ? "Not recording yet…"
                                 : (state.live.decodeLive ? "Listening…" : "Recording"))
                            if !isPreparing, !state.live.decodeLive {
                                Text("Transcription runs when you stop. Turn on "
                                     + "“Transcribe while recording” in Settings to see text live.")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 380)
                            }
                        }
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

    @State private var showStats = false

    private var footer: some View {
        HStack(spacing: 14) {
            if !state.live.decodeLive {
                Label("Transcribes after you stop, on \(ModelCatalogue.option(state.settings.offlineModelId)?.label ?? state.settings.offlineModelId)",
                      systemImage: "clock")
            } else {
                // Which model is decoding: the first thing anyone wants to know
                // when the live text reads oddly.
                Label(ModelCatalogue.option(state.settings.liveModelId)?.label
                      ?? state.settings.liveModelId,
                      systemImage: "cpu")
                    .help(ModelCatalogue.option(state.settings.liveModelId)?.detail ?? "")
                // The engineering numbers live behind a button. They were the
                // whole footer, and nobody in a meeting needs the RTF -- but
                // the dropped-window count is a warning and stays in sight.
                Button {
                    showStats.toggle()
                } label: {
                    Label("Stats", systemImage: state.live.stats.droppedHops > 0
                          ? "exclamationmark.circle" : "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(state.live.stats.droppedHops > 0 ? .orange : .secondary)
                .popover(isPresented: $showStats, arrowEdge: .top) { statsPopover }
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

    private var statsPopover: some View {
        let stats = state.live.stats
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Voice detection").foregroundStyle(.secondary)
                Text(state.live.vadBackend == "silero" ? "Silero (neural)" : "Energy")
            }
            GridRow {
                Text("Decodes").foregroundStyle(.secondary)
                Text("\(stats.hops) · \(TimeFormat.duration(ms: stats.totalInferMs)) of model time")
            }
            if stats.hops > 0 {
                GridRow {
                    Text("RTF").foregroundStyle(.secondary)
                    Text(String(format: "%.2f", stats.meanRtf))
                        .help("Decode time over audio duration. Below 1.0 keeps up with live audio.")
                }
            }
            GridRow {
                Text("Dropped").foregroundStyle(.secondary)
                Text("\(stats.droppedHops)")
                    .foregroundStyle(stats.droppedHops > 0 ? .orange : .primary)
                    .help("Windows skipped because the previous decode was still running.")
            }
            if stats.failedHops > 0 {
                GridRow {
                    Text("Failed").foregroundStyle(.secondary)
                    Text("\(stats.failedHops)").foregroundStyle(.orange)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
        .padding(14)
    }
}
