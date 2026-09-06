import SwiftUI

extension EnvironmentValues {
    /// Simple or Advanced, for the views. Set once at the root of each scene
    /// from Settings; the views read it here rather than reaching into
    /// `AppState.settings`. The default is a stable enum case, so a reader
    /// that falls back to it does not invalidate on unrelated writes.
    @Entry var interfaceMode: InterfaceMode = .simple
}

extension View {
    /// Shown in Advanced mode only. The one modifier for the controls that
    /// Simple mode hides, in place of an `if` at each of them.
    func advancedOnly() -> some View {
        modifier(AdvancedOnly())
    }
}

private struct AdvancedOnly: ViewModifier {
    @Environment(\.interfaceMode) private var mode

    func body(content: Content) -> some View {
        if mode == .advanced {
            content
        }
    }
}
