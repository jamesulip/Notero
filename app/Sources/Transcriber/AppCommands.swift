import SwiftUI
import TranscriberCore
import TranscriberStore

/// Menu bar and keyboard shortcuts.
///
/// Space for play/pause is deliberately *not* here. A menu key equivalent with
/// no modifier is consumed before the responder chain, so it would swallow
/// every space typed into a note. It lives on the transcript view as an
/// `onKeyPress`, which only fires when that view has focus; ⌥Space is the
/// global equivalent for when it does not.
struct AppCommands: Commands {

    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { state.newItem(.recording) }
                .keyboardShortcut("r")
            Button("New Meeting") { state.newItem(.meeting) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("New Note") { state.newItem(.note) }
                .keyboardShortcut("n")

            Divider()

            Button("Import Audio or Video…") { state.isImporting = true }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .newItem) {
            Button("Stop Recording") { Task { await state.stopRecording() } }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!state.isRecording)

            Divider()

            Button("Export…") { state.isExporting = true }
                .keyboardShortcut("e")
                .disabled(state.selectedRecording == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Recordings") {
                state.route = .search
                state.focusSearch = true
            }
            .keyboardShortcut("f")
        }

        CommandMenu("Meeting") {
            Button("Add Bookmark") { _ = state.addBookmark() }
                .keyboardShortcut("b")
                .disabled(state.selectedRecording == nil)

            Divider()

            ForEach(MeetingItemKind.allCases) { kind in
                Button("Add Selection as \(kind.label)") {
                    state.addSelectionAsItem(kind)
                }
                .keyboardShortcut(shortcut(for: kind), modifiers: [.command, .control])
                .disabled(state.selectedSegmentId == nil)
            }
        }

        CommandMenu("Playback") {
            Button(state.player.isPlaying ? "Pause" : "Play") { state.player.toggle() }
                .keyboardShortcut(.space, modifiers: .option)
                .disabled(state.player.loadedURL == nil)

            Button("Back 5 Seconds") { state.player.skip(seconds: -5) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(state.player.loadedURL == nil)

            Button("Forward 5 Seconds") { state.player.skip(seconds: 5) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(state.player.loadedURL == nil)

            Divider()

            Menu("Speed") {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button(String(format: "%.2gx", rate)) {
                        state.player.rate = Float(rate)
                    }
                }
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Model Benchmark") { state.route = .benchmark }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

    private func shortcut(for kind: MeetingItemKind) -> KeyEquivalent {
        switch kind {
        case .keyPoint: return "k"
        case .decision: return "d"
        case .actionItem: return "a"
        case .question: return "q"
        case .followUp: return "u"
        }
    }
}
