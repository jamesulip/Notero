import AppKit
import Carbon.HIToolbox
import SwiftUI
import TranscriberCore

/// The menu bar item: the clock of the recording beside the icon, and
/// Record, Pause and Stop from any application.
///
/// Its purpose is the moment a meeting starts while another window is in
/// front. Finding the Notero window first is the step that loses the first
/// minute of the meeting; the menu bar and the global shortcuts remove it.
struct MenuBarLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.isRecording {
            Label {
                Text(TimeFormat.short(ms: state.live.elapsedMs))
                    .monospacedDigit()
            } icon: {
                Image(systemName: state.isPaused ? "pause.circle.fill" : "record.circle.fill")
            }
            .labelStyle(.titleAndIcon)
        } else if state.isLiveBusy {
            Image(systemName: "record.circle")
        } else {
            Image(systemName: "waveform")
        }
    }
}

struct MenuBarMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.isRecording {
            Text(state.isPaused
                 ? "Paused at \(TimeFormat.short(ms: state.live.elapsedMs))"
                 : "Recording · \(TimeFormat.short(ms: state.live.elapsedMs))")
            Button(state.isPaused ? "Resume" : "Pause") { state.togglePause() }
                .keyboardShortcut("p", modifiers: [.control, .option])
            Button("Stop") { Task { await state.stopRecording() } }
                .keyboardShortcut("r", modifiers: [.control, .option])
            Button("Add a Bookmark") { _ = state.addBookmark() }
        } else if state.isLiveBusy {
            Text(state.live.state.label)
        } else {
            Button("Record") { state.toggleRecording() }
                .keyboardShortcut("r", modifiers: [.control, .option])
            Button("Transcribe a File…") {
                // The file panel is attached to the main window, so the
                // window has to be up first.
                state.showMainWindow(openWindow)
                state.isImporting = true
            }
        }

        Divider()

        Button("Open Notero") { state.showMainWindow(openWindow) }
        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Notero") { NSApp.terminate(nil) }
            .disabled(state.isLiveBusy)
    }
}

/// Keyboard shortcuts that work in every application, through the Carbon
/// hot-key API. That API needs no accessibility permission, which is what
/// makes it the right one: a permission prompt at the first recording is the
/// thing this feature exists to remove.
///
/// Two shortcuts, fixed: ⌃⌥R starts or stops a recording, ⌃⌥P pauses or
/// resumes it. Both are free in macOS and in the common applications.
final class GlobalHotKeys {

    /// "NTRO", so an event handler can tell these hot keys from any other.
    private static let signature: OSType = 0x4E54_524F

    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    struct Shortcut {
        var keyCode: UInt32
        var modifiers: UInt32
        var action: () -> Void
    }

    /// Replaces whatever was registered before.
    func register(_ shortcuts: [Shortcut]) {
        unregister()
        guard !shortcuts.isEmpty else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard status == noErr, id.signature == GlobalHotKeys.signature else { return noErr }
                // Carbon delivers the event on the main thread; the actions
                // touch main-actor state.
                let keys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { keys.actions[id.id]?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { return }

        for (index, shortcut) in shortcuts.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            if RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                   GetEventDispatcherTarget(), 0, &ref) == noErr, let ref {
                registered.append(ref)
                actions[id] = shortcut.action
            }
        }
    }

    func unregister() {
        for ref in registered { UnregisterEventHotKey(ref) }
        registered = []
        actions = [:]
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    // No `deinit`: `AppState` owns the one instance for the life of the
    // process, and `unregister()` is the explicit way to let the keys go.
}

extension AppState {

    /// The menu bar item and the global shortcuts, on or off together.
    func setMenuBarItem(_ shown: Bool) {
        settings.menuBarItem = shown
        applyMenuBarSetting()
    }

    /// Registers the global shortcuts when the menu bar item is on, and
    /// removes them when it is off. Called once at launch and on each change.
    func applyMenuBarSetting() {
        guard settings.menuBarItem else {
            hotKeys.unregister()
            return
        }
        hotKeys.register([
            GlobalHotKeys.Shortcut(keyCode: UInt32(kVK_ANSI_R),
                                   modifiers: UInt32(controlKey | optionKey)) { [weak self] in
                self?.toggleRecording()
            },
            GlobalHotKeys.Shortcut(keyCode: UInt32(kVK_ANSI_P),
                                   modifiers: UInt32(controlKey | optionKey)) { [weak self] in
                self?.togglePause()
            },
        ])
    }

    /// ⌃⌥R and the menu bar: stop the recording that runs, or start one.
    /// Nothing during the preparation phase, where a second start would be
    /// refused with an alert in a window that may not be in front.
    func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else if !isLiveBusy {
            newItem(newRecordingKind)
        }
    }

    /// Brings the main window to the front, and makes one if the user closed
    /// it. The identifier prefix is what SwiftUI gives the windows of the
    /// `WindowGroup` with id "main".
    func showMainWindow(_ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix("main") == true
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
