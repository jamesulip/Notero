import AppKit
import SwiftUI

/// Reports the hosting window's content width.
///
/// Measuring the split view itself does not work for the purpose this serves:
/// when its columns no longer fit, the split view overflows the window rather
/// than shrinking, so its own width never drops and the fold that would fix
/// the overflow never triggers. The window's width is the one number that
/// only the user changes.
struct WindowWidthReader: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> Tracker {
        let tracker = Tracker()
        tracker.onChange = onChange
        return tracker
    }

    func updateNSView(_ view: Tracker, context: Context) {
        view.onChange = onChange
    }

    final class Tracker: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var lastWidth: CGFloat = -1

        // Selector-based, so the observation is dropped with the view and no
        // deinit has to touch it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.didResizeNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResize(_:)),
                name: NSWindow.didResizeNotification, object: window)
            report()
        }

        @objc private func windowDidResize(_ note: Notification) {
            report()
        }

        private func report() {
            guard let window else { return }
            let width = window.contentLayoutRect.width
            guard width != lastWidth else { return }
            lastWidth = width
            onChange?(width)
        }
    }
}
