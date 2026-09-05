import AppKit
import AVFoundation
import Foundation
import TranscriberCore
import TranscriberEngine

/// `transcribe --record` -- capture for a few seconds and say what was heard.
///
/// The same `AudioCapture` the app uses, so this answers the questions that
/// only the real path can: does this Mac permit a system tap, which channel
/// holds which lane, and does a two-lane recording actually come out aligned.
/// The archive it leaves behind can be fed straight back to `--audio`.
func runRecord(source: CaptureSource, deviceUID: String?, seconds: Double,
               out: URL?, gui: Bool) -> Never {
    if gui {
        // TCC cannot put a dialog in front of a process that is not a UI app,
        // and a request it cannot show is a request it refuses. Becoming a
        // regular application is the difference between being asked and being
        // silently denied -- which is why this exists at all, and why the
        // permission cannot be granted from a plain command line.
        becomeForegroundApplication()
    }

    if source.usesSystemAudio {
        log("system audio permission: \(SystemAudioAccess.current.label.lowercased())")
        if gui, SystemAudioAccess.current.canRequest {
            let asked = DispatchSemaphore(value: 0)
            Task {
                let answer = await SystemAudioAccess.request()
                log("system audio permission: \(answer.label.lowercased())")
                asked.signal()
            }
            _ = asked.wait(timeout: .now() + 120)
        }
        guard SystemAudioAccess.current.mightWork else {
            log("refused. Allow it in System Settings › Privacy & Security.")
            exit(1)
        }
    }

    guard let capture = AudioCapture(source: source, microphoneUID: deviceUID) else {
        log("could not create the capture")
        exit(1)
    }

    let meter = LaneMeter(lanes: source.lanes)
    capture.onNotice = { notice in log("  " + notice.message) }
    do {
        try capture.start(archiveURL: out) { chunk in meter.consume(chunk) }
    } catch {
        log("record: \(error.localizedDescription)")
        exit(1)
    }
    log("recording \(source.rawValue) for \(Int(seconds)) s at "
        + "\(capture.archiveSampleRate) Hz, \(source.lanes.count) lane(s)")
    log("  " + capture.diagnostics)

    let ticker = DispatchSource.makeTimerSource(queue: .global())
    ticker.schedule(deadline: .now() + 1, repeating: 1)
    ticker.setEventHandler { meter.report() }
    ticker.resume()

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.signal() }
    done.wait()
    ticker.cancel()

    let written = capture.stop()
    log(meter.summary(frames: written.frames, sampleRate: written.sampleRate))
    if let out { log("wrote \(out.path)") }
    exit(meter.heardAnything ? 0 : 3)
}

/// `NSApplication` is main-actor state. Both probes are called from the top
/// level of `main.swift`, which runs on the main thread, so this is a fact and
/// not an assumption.
private func becomeForegroundApplication() {
    MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// Per-lane peak tracking, off the capture callback's critical path.
private final class LaneMeter: @unchecked Sendable {
    private let lock = NSLock()
    private let lanes: [CaptureLane]
    private var interval: [CaptureLane: Float] = [:]
    private var overall: [CaptureLane: Float] = [:]
    private var bytes = 0

    init(lanes: [CaptureLane]) { self.lanes = lanes }

    var heardAnything: Bool { lock.withLock { overall.values.contains { $0 > 0.0001 } } }

    func consume(_ chunk: CapturedAudio) {
        lock.withLock {
            bytes += chunk.pcm.count
            for (lane, peak) in chunk.peaks {
                interval[lane] = max(interval[lane] ?? 0, peak)
                overall[lane] = max(overall[lane] ?? 0, peak)
            }
        }
    }

    func report() {
        let snapshot = lock.withLock { () -> [CaptureLane: Float] in
            defer { interval = [:] }
            return interval
        }
        let parts = lanes.map { lane in
            "\(lane.rawValue) \(Self.decibels(snapshot[lane] ?? 0))"
        }
        log("  " + parts.joined(separator: "   "))
    }

    func summary(frames: AVAudioFramePosition, sampleRate: Int) -> String {
        let (snapshot, ingested) = lock.withLock { (overall, bytes) }
        guard snapshot.values.contains(where: { $0 > 0.0001 }) else {
            return "heard nothing on any lane."
        }
        // From the archive when there is one, and from what reached the
        // 16 kHz copy when there is not: an inference-only run writes no file
        // and would otherwise report zero seconds of perfectly good audio.
        let seconds = frames > 0 && sampleRate > 0
            ? Double(frames) / Double(sampleRate)
            : Double(ingested / MemoryLayout<Int16>.size) / 16_000
        let parts = lanes.map { "\($0.rawValue) \(Self.decibels(snapshot[$0] ?? 0))" }
        return String(format: "captured %.1f s, loudest ", seconds)
             + parts.joined(separator: ", ")
    }

    private static func decibels(_ value: Float) -> String {
        value > 0 ? String(format: "%.1f dBFS", 20 * log10(value)) : "silence"
    }
}


/// `transcribe --channels` -- peak level of every raw channel of the combined
/// aggregate, with no lane mapping in the way.
///
/// The order Core Audio presents an aggregate's inputs in is not documented
/// anywhere that binds it, and getting it wrong swaps the room lane with the
/// call lane silently. This prints the ground truth: play something and watch
/// which channels move, speak and watch the other one.
func runChannelScan(seconds: Double) -> Never {
    becomeForegroundApplication()

    let tap = SystemAudioTap(withMicrophone: true, microphoneUID: nil)
    do {
        try tap.prepare()
    } catch {
        log("channels: \(error.localizedDescription)")
        exit(1)
    }
    guard let layout = tap.layout else { exit(1) }
    log("aggregate \(Int(layout.sampleRate)) Hz, \(layout.totalChannels) channels")

    let peaks = ChannelPeaks(count: layout.totalChannels)
    do {
        try tap.start { list, frames in peaks.consume(list, frames: frames) }
    } catch {
        log("channels: \(error.localizedDescription)")
        exit(1)
    }

    let ticker = DispatchSource.makeTimerSource(queue: .global())
    ticker.schedule(deadline: .now() + 1, repeating: 1)
    ticker.setEventHandler { peaks.report() }
    ticker.resume()

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.signal() }
    done.wait()
    ticker.cancel()
    tap.stop()
    exit(0)
}

private final class ChannelPeaks: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float]
    private var shape = ""

    init(count: Int) { values = Array(repeating: 0, count: max(count, 1)) }

    func consume(_ list: UnsafePointer<AudioBufferList>, frames: AVAudioFrameCount) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var description: [String] = []
        var peaks: [Float] = []
        for buffer in buffers {
            let width = Int(buffer.mNumberChannels)
            description.append("\(width)ch/\(buffer.mDataByteSize)B")
            guard let raw = buffer.mData else {
                peaks.append(contentsOf: Array(repeating: 0, count: width))
                continue
            }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let available = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * max(1, width))
            for channel in 0..<width {
                var peak: Float = 0
                for frame in 0..<min(Int(frames), available) {
                    let value = abs(samples[frame * width + channel])
                    if value > peak { peak = value }
                }
                peaks.append(peak)
            }
        }
        lock.withLock {
            shape = description.joined(separator: " + ")
            for (index, peak) in peaks.enumerated() where index < values.count {
                values[index] = max(values[index], peak)
            }
        }
    }

    func report() {
        let (snapshot, layout) = lock.withLock { () -> ([Float], String) in
            defer { values = Array(repeating: 0, count: values.count) }
            return (values, shape)
        }
        let parts = snapshot.enumerated().map { index, value in
            "ch\(index) " + (value > 0 ? String(format: "%.0f", 20 * log10(value)) : "--")
        }
        log("  [\(layout)]  " + parts.joined(separator: "  "))
    }
}
