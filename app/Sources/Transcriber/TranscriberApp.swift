import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

@main
struct TranscriberApp: App {

    @State private var state: AppState
    @State private var startupFailure: String?

    init() {
        let settings = AppSettings()
        do {
            _state = State(initialValue: AppState(container: try StoreContainer.make(),
                                                  settings: settings))
        } catch {
            // An in-memory store rather than a crash: the user can still record,
            // and the message says plainly that nothing will be kept. If even an
            // in-memory store cannot be built there is nothing left to fall back
            // to -- say why rather than trapping on a bare `try!`.
            guard let fallback = try? StoreContainer.ephemeral() else {
                fatalError("Storage is unavailable and an in-memory store could not "
                           + "be created either: \(error.localizedDescription)")
            }
            _state = State(initialValue: AppState(container: fallback, settings: settings))
            _startupFailure = State(initialValue: error.localizedDescription)
        }
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
                    // starting.
                    state.warmUpEngines()
                    // Off unless the user asked for it, and at most once a day.
                    state.updater.checkOnLaunch()
                    if let startupFailure {
                        state.alert = AppState.AppAlert(
                            title: "Storage unavailable",
                            message: "Recordings will not be saved this session. \(startupFailure)"
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
