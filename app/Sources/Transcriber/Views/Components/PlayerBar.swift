import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore

/// Transport, scrubber and waveform for a finished recording.
///
/// Three views inside read the playhead, which moves twenty times a second:
/// the waveform's playhead line, the clock, and nothing else. They are their
/// own view types, so a tick re-runs those two bodies and not the bar with
/// its buttons, menu and bookmark targets. The bar itself depends on the
/// recording and on the loaded duration, which change on selection.
struct PlayerBar: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    var body: some View {
        VStack(spacing: 8) {
            PlayheadWaveform(player: state.player, recording: recording, durationMs: duration,
                             bookmarks: sortedBookmarks)
                .frame(height: 52)

            HStack(spacing: 14) {
                // Skip buttons go first when the column is narrow; play and
                // the clock stay.
                ViewThatFits(in: .horizontal) {
                    transport(withSkips: true)
                    transport(withSkips: false)
                }

                Spacer(minLength: 8)

                // Labels while there is room, icons when the column is narrow,
                // and no speed menu when there is barely that. A fixed row here
                // is what stopped the detail column shrinking and made the
                // window overflow beside the inspector.
                ViewThatFits(in: .horizontal) {
                    trailingControls(iconOnly: false, withSpeed: true)
                    trailingControls(iconOnly: true, withSpeed: true)
                    trailingControls(iconOnly: true, withSpeed: false)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .task(id: recording.id) { ensureLoaded() }
    }

    private func transport(withSkips: Bool) -> some View {
        HStack(spacing: 14) {
            if withSkips {
                Button {
                    state.player.skip(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .help("Back 10 seconds")
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
            .help(state.player.isPlaying ? "Pause" : "Play")
            if withSkips {
                Button {
                    state.player.skip(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .help("Forward 10 seconds")
            }

            PlaybackClock(player: state.player, durationMs: duration)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func trailingControls(iconOnly: Bool, withSpeed: Bool) -> some View {
        if iconOnly {
            trailingCluster(withSpeed: withSpeed).labelStyle(.iconOnly).fixedSize()
        } else {
            trailingCluster(withSpeed: withSpeed).labelStyle(.titleAndIcon).fixedSize()
        }
    }

    private func trailingCluster(withSpeed: Bool) -> some View {
        @Bindable var state = state
        return HStack(spacing: 14) {
            Toggle(isOn: $state.followPlayback) {
                Label("Follow", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .toggleStyle(.button)
            .help("Keep the line that plays in view. A scroll by hand turns this off.")

            Button {
                _ = state.addBookmark()
            } label: {
                Label("Bookmark", systemImage: "bookmark")
            }
            .help("Bookmark this moment (⌘B)")

            if withSpeed {
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
        }
    }

    private var duration: Int {
        max(state.player.durationMs, recording.durationMs)
    }

    private var sortedBookmarks: [StoredBookmark] {
        (recording.bookmarks ?? []).sorted { $0.atMs < $1.atMs }
    }

    private func ensureLoaded() {
        guard let url = recording.audioURL, state.player.loadedURL != url else { return }
        _ = state.player.load(url)
    }
}

/// "0:42 / 1:15". The one text that changes with every tick.
private struct PlaybackClock: View {
    let player: AudioPlayer
    let durationMs: Int

    var body: some View {
        Text("\(TimeFormat.short(ms: player.currentMs)) / \(TimeFormat.short(ms: durationMs))")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

/// The waveform with the playhead line over it, and one target on each
/// bookmark tick. The playhead is why this view reads the player; the
/// targets are a separate view again so their layout does not re-run with it.
private struct PlayheadWaveform: View {
    @Environment(AppState.self) private var state
    let player: AudioPlayer
    let recording: StoredRecording
    let durationMs: Int
    let bookmarks: [StoredBookmark]

    var body: some View {
        WaveformView(
            samples: recording.waveform ?? [],
            progress: durationMs > 0 ? Double(player.currentMs) / Double(durationMs) : 0,
            bookmarks: bookmarks.map { Double($0.atMs) / Double(max(1, durationMs)) },
            showsPlayhead: true,
            onScrub: { value in
                state.seek(to: Int(value * Double(max(1, durationMs))), in: recording)
            }
        )
        .overlay {
            BookmarkTargets(recording: recording, durationMs: durationMs, bookmarks: bookmarks)
        }
    }
}

/// A hover target over each bookmark tick, so the label shows and a click
/// lands exactly on the moment rather than a few hundred milliseconds off it.
/// Buttons, not tap gestures: they carry the label for assistive technology.
private struct BookmarkTargets: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording
    let durationMs: Int
    let bookmarks: [StoredBookmark]

    var body: some View {
        GeometryReader { geometry in
            ForEach(bookmarks) { bookmark in
                let x = geometry.size.width
                    * CGFloat(Double(bookmark.atMs) / Double(max(1, durationMs)))
                Button {
                    state.seek(to: bookmark.atMs, in: recording)
                } label: {
                    Color.clear
                        .frame(width: 10, height: geometry.size.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(bookmark.displayLabel) · \(TimeFormat.short(ms: bookmark.atMs))")
                .accessibilityLabel(bookmark.displayLabel)
                .position(x: x, y: geometry.size.height / 2)
            }
        }
    }
}
