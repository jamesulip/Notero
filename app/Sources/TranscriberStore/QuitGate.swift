import Foundation

/// Holds a quit until a recording in progress has been stopped and saved.
///
/// An AAC file is readable only after its index is written at close, and
/// nothing wrote it when the app quit under a recording: Command-Q went
/// straight through, the file stayed unclosed, and `afinfo` could not open it
/// (finding 16). The working copy survives such a quit, but only the archive
/// plays. The window-level Stop button already closes both files, thus a quit
/// has to do what that button does before the process goes.
///
/// The gate is a decision and a timer. AppKit asks, through
/// `applicationShouldTerminate`, whether the app may quit. The answer is yes
/// at once when nothing records. If something does, the gate answers "later",
/// runs the stop, and calls every `reply` that waited when the stop returns.
/// A stop that does not return inside `timeout` is abandoned, because an app
/// that never quits is worse than the quit that the user asked for.
@MainActor
public final class QuitGate {

    public enum Decision: Sendable, Equatable {
        /// Nothing is recording. Quit now.
        case quitNow
        /// A stop is running. The `reply` closure is called when the app may quit.
        case wait
    }

    private let isRecording: @MainActor () -> Bool
    private let stop: @MainActor () async -> Void
    private let timeout: Duration
    private var waiters: [@MainActor () -> Void] = []
    private var stopping = false
    private var timer: Task<Void, Never>?

    public init(timeout: Duration = .seconds(30),
                isRecording: @escaping @MainActor () -> Bool,
                stop: @escaping @MainActor () async -> Void) {
        self.timeout = timeout
        self.isRecording = isRecording
        self.stop = stop
    }

    /// Answers one quit request. Every request that gets `.wait` has its
    /// `reply` called exactly once, whichever of the stop and the timeout
    /// comes first. A second request during a stop joins it and does not
    /// start a second stop.
    public func requestQuit(reply: @escaping @MainActor () -> Void) -> Decision {
        guard stopping || isRecording() else { return .quitNow }
        waiters.append(reply)
        if !stopping {
            stopping = true
            run()
        }
        return .wait
    }

    private func run() {
        let stop = self.stop
        let timeout = self.timeout
        let work = Task { @MainActor [weak self] in
            await stop()
            self?.finish()
        }
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            work.cancel()
            self?.finish()
        }
    }

    private func finish() {
        guard stopping else { return }
        stopping = false
        timer?.cancel()
        timer = nil
        let replies = waiters
        waiters = []
        for reply in replies { reply() }
    }
}
