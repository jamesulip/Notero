import AppKit
import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

/// Files that arrive from outside the window: a drop on the Dock icon, "Open
/// With" in the Finder, or `open -a Notero file.m4a`.
///
/// `Info.plist` has declared the audio and video types since the first
/// release, but nothing received them, thus a drop on the Dock icon did
/// nothing. Files that arrive before the app has a state to give them to are
/// kept and delivered when it does.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)? {
        didSet {
            guard let onOpen, !pending.isEmpty else { return }
            let urls = pending
            pending = []
            onOpen(urls)
        }
    }
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen {
            onOpen(urls)
        } else {
            pending.append(contentsOf: urls)
        }
    }
}

@main
struct TranscriberApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState
    @State private var startupFailure: String?

    init() {
        let settings = AppSettings()
        let state: AppState
        var failure: String?
        do {
            state = AppState(container: try StoreContainer.make(), settings: settings)
        } catch {
            // An in-memory store rather than a crash: the user can still record,
            // and the message says plainly that nothing will be kept. If even an
            // in-memory store cannot be built there is nothing left to fall back
            // to -- say why rather than trapping on a bare `try!`.
            guard let fallback = try? StoreContainer.ephemeral() else {
                fatalError("Storage is unavailable and an in-memory store could not "
                           + "be created either: \(error.localizedDescription)")
            }
            state = AppState(container: fallback, settings: settings)
            failure = error.localizedDescription
        }
        _state = State(initialValue: state)
        _startupFailure = State(initialValue: failure)
        delegate.onOpen = { urls in state.importFiles(urls) }
    }

    var body: some Scene {
        WindowGroup("Notero") {
            ContentView()
                .environment(state)
                .modelContainer(state.container)
                // Small enough to sit beside another window. Below ~700 pt the
                // sidebar folds, below ~1060 the inspector does; every row in
                // the detail has a compact form (see ViewThatFits uses).
                .frame(minWidth: 300, minHeight: 420)
                .alert(item: Binding(
                    get: { state.alert },
                    set: { state.alert = $0 }
                )) { alert in
                    Alert(title: Text(alert.title), message: Text(alert.message))
                }
                .task {
                    // Ahead of the first tap, not on it: the model load is the
                    // several seconds between hitting record and the recording
                    // starting. Only when live transcription is on; otherwise
                    // nothing runs until the user asks for something.
                    state.warmUpEngines()
                    if let startupFailure {
                        state.alert = AppState.AppAlert(
                            title: "Storage is not available",
                            message: "The app cannot save recordings in this session. \(startupFailure)"
                        )
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(state: state) }

        Settings {
            SettingsView()
                .environment(state)
                .modelContainer(state.container)
        }
    }
}
