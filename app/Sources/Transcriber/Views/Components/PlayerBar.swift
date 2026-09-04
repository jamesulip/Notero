import SwiftUI
import TranscriberCore
import TranscriberStore

/// Transport, scrubber and waveform for a finished recording.
struct PlayerBar: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 8) {
            WaveformView(
                samples: recording.waveform ?? [],
                progress: fraction,
                bookmarks: bookmarkFractions,
                onScrub: { value in
                    state.seek(to: Int(value * Double(max(1, duration))), in: recording)
                }
            )
            .frame(height: 52)
            .overlay {
                // A hover target over each bookmark tick, so the label shows
                // and a click lands exactly on the moment rather than a few
                // hundred milliseconds off it.
                GeometryReader { geometry in
                    ForEach(sortedBookmarks) { bookmark in
                        let x = geometry.size.width
                            * CGFloat(Double(bookmark.atMs) / Double(max(1, duration)))
                        Color.clear
                            .frame(width: 10, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .help("\(bookmark.displayLabel) · \(TimeFormat.short(ms: bookmark.atMs))")
                            .onTapGesture { state.seek(to: bookmark.atMs, in: recording) }
                            .position(x: x, y: geometry.size.height / 2)
                    }
                }
            }

            HStack(spacing: 14) {
                Button {
                    state.player.skip(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                Button {
                    ensureLoaded()
                    state.player.toggle()
                } label: {
                    Image(systemName: state.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 26)
                }
                .keyboardShortcut(.return, modifiers: [])
                Button {
                    state.player.skip(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                }

                Text("\(TimeFormat.short(ms: state.player.currentMs)) / \(TimeFormat.short(ms: duration))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Toggle(isOn: $state.followPlayback) {
                    Label("Follow", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .toggleStyle(.button)
                .help("Keep the playing line in view. Scrolling by hand turns this off.")

                Button {
                    _ = state.addBookmark()
                } label: {
                    Label("Bookmark", systemImage: "bookmark")
                }
                .help("Bookmark this moment (⌘B)")

                Menu {
                    ForEach(AppState.playbackRates, id: \.self) { rate in
                        Button(String(format: "%.2gx", Double(rate))) { state.player.rate = rate }
                    }
                } label: {
                    Text(String(format: "%.2gx", Double(state.player.rate)))
                        .font(.caption)
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Playback speed (⌥↑ faster, ⌥↓ slower)")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .task(id: recording.id) { ensureLoaded() }
    }

    private var duration: Int {
        max(state.player.durationMs, recording.durationMs)
    }

    private var fraction: Double {
        duration > 0 ? Double(state.player.currentMs) / Double(duration) : 0
    }

    private var sortedBookmarks: [StoredBookmark] {
        (recording.bookmarks ?? []).sorted { $0.atMs < $1.atMs }
    }

    private var bookmarkFractions: [Double] {
        guard duration > 0 else { return [] }
        return sortedBookmarks.map { Double($0.atMs) / Double(duration) }
    }

    private func ensureLoaded() {
        guard let url = recording.audioURL, state.player.loadedURL != url else { return }
        _ = state.player.load(url)
    }
}
