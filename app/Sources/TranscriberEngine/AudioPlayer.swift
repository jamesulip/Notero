import AVFoundation
import Foundation
import Observation
import TranscriberCore

/// Playback for one recording, with the position the transcript follows.
///
/// `AVAudioPlayer` rather than `AVPlayer`: the files are local, seeking has to
/// be immediate when a transcript row is clicked, and `currentTime` on
/// `AVAudioPlayer` is sample-accurate rather than quantized to a decode window.
@MainActor
@Observable
public final class AudioPlayer {

    public private(set) var isPlaying = false
    public private(set) var currentMs: Int = 0
    public private(set) var durationMs: Int = 0
    public private(set) var loadedURL: URL?
    public private(set) var failure: String?

    public var rate: Float = 1 {
        didSet {
            player?.enableRate = true
            player?.rate = rate
        }
    }

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    public init() {}

    // No deinit cancel: the ticker captures self weakly, so it exits on its
    // next tick once the player is gone. A deinit cannot touch main-actor
    // state anyway.

    // MARK: - Loading

    @discardableResult
    public func load(_ url: URL) -> Bool {
        guard loadedURL != url else { return true }
        stop()
        guard FileManager.default.fileExists(atPath: url.path) else {
            failure = "The audio file is missing."
            durationMs = 0
            loadedURL = nil
            return false
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            loadedURL = url
            durationMs = Int(player.duration * 1000)
            currentMs = 0
            failure = nil
            return true
        } catch {
            failure = error.localizedDescription
            player = nil
            loadedURL = nil
            durationMs = 0
            return false
        }
    }

    public func unload() {
        stop()
        player = nil
        loadedURL = nil
        durationMs = 0
        currentMs = 0
    }

    // MARK: - Transport

    public func play() {
        guard let player else { return }
        // Restart from the top rather than sitting at the end doing nothing.
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        player.rate = rate
        guard player.play() else { return }
        isPlaying = true
        startTicking()
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
        syncPosition()
    }

    public func stop() {
        player?.stop()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    public func toggle() {
        isPlaying ? pause() : play()
    }

    /// Seeks and keeps playing if it already was. Clicking a transcript row
    /// during playback should move the playhead, not stop the audio.
    public func seek(toMs ms: Int) {
        guard let player else { return }
        let clamped = min(max(0, ms), max(0, durationMs))
        player.currentTime = Double(clamped) / 1000
        currentMs = clamped
        if isPlaying, !player.isPlaying { player.play() }
    }

    public func skip(seconds: Double) {
        seek(toMs: currentMs + Int(seconds * 1000))
    }

    // MARK: - Position

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            // 20 Hz. Fast enough that the highlighted transcript row never
            // visibly lags the audio, slow enough to stay off the profiler.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                self.syncPosition()
                if self.player?.isPlaying == false {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    private func syncPosition() {
        guard let player else { return }
        currentMs = Int(player.currentTime * 1000)
    }
}
