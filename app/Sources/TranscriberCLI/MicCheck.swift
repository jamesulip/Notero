import Foundation
import TranscriberCore
import TranscriberEngine

/// `transcribe --mic-check` -- record a take, then hear it back.
///
/// The same `MicrophoneCheck` and `TakePlayer` as the Settings pane, with a
/// level line each second so a microphone that hears nothing says so.
func runMicCheck(deviceUID: String?, seconds: Double, gui: Bool) -> Never {
    if gui { becomeForegroundApplication() }

    let check = MicrophoneCheck(microphoneUID: deviceUID)
    let meter = CheckMeter()
    check.onLevel = { level in meter.note(level) }
    do {
        try check.start()
    } catch {
        log("mic check: \(error.localizedDescription)")
        exit(1)
    }
    log("  " + check.diagnostics)
    log("speak for \(Int(seconds)) s; the take plays back after that")

    let ticker = DispatchSource.makeTimerSource(queue: .global())
    ticker.schedule(deadline: .now() + 1, repeating: 1)
    ticker.setEventHandler { log("  hearing \(decibels(meter.take()))") }
    ticker.resume()
    Thread.sleep(forTimeInterval: seconds)
    ticker.cancel()

    guard let take = check.stop(), take.peak > 0.0001 else {
        log("heard nothing.")
        exit(3)
    }
    log(String(format: "take: %.1f s from %@, peak %@ -- playing", take.seconds,
               take.microphone, decibels(take.peak)))
    let player = TakePlayer()
    let done = DispatchSemaphore(value: 0)
    let failed = CheckMeter()
    player.play(take, onFailure: { message in
        log("  " + message)
        failed.note(1)
        done.signal()
    }, onFinish: { done.signal() })
    _ = done.wait(timeout: .now() + take.seconds + 5)
    player.stop()
    exit(failed.take() > 0 ? 1 : 0)
}

private func decibels(_ value: Float) -> String {
    value > 0 ? String(format: "%.1f dBFS", 20 * log10(value)) : "silence"
}

/// The loudest chunk since the last tick.
private final class CheckMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0

    func note(_ level: Float) { lock.withLock { peak = max(peak, level) } }
    func take() -> Float {
        lock.withLock {
            defer { peak = 0 }
            return peak
        }
    }
}
