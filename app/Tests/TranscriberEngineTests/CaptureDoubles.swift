import AVFoundation
import Foundation
import TranscriberCore
@testable import TranscriberEngine

// Doubles for the capture path. `ScriptedInput` stands where the microphone or
// the system tap stands, so everything above `LaneCapturing` -- gain, the
// meter, room mode, the archive, the 16 kHz conversion -- runs from a test
// with no device, no permission and no wall clock.

/// A lane source a test drives by hand.
final class ScriptedInput: LaneCapturing, @unchecked Sendable {
    let sampleRate: Double
    var onGap: (@Sendable (Int) -> Void)?
    var onNotice: (@Sendable (CaptureNotice) -> Void)?
    var diagnostics: String { "scripted \(Int(sampleRate)) Hz" }

    /// Thrown from `prepare` / `start` when set.
    var prepareError: (any Error)?
    var startError: (any Error)?

    private let lock = NSLock()
    private var onFrames: (@Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func prepare() throws {
        if let prepareError { throw prepareError }
    }

    func start(_ onFrames: @escaping @Sendable ([CaptureLane: AVAudioPCMBuffer]) -> Void) throws {
        lock.withLock { startCalls += 1 }
        if let startError { throw startError }
        lock.withLock { self.onFrames = onFrames }
    }

    func stop() {
        // The callback stays reachable: a real input can deliver one more
        // buffer after `stop` returns, and the chain has to survive that.
        lock.withLock { stopCalls += 1 }
    }

    /// One callback's worth of audio.
    func deliver(_ frames: [CaptureLane: AVAudioPCMBuffer]) {
        let callback = lock.withLock { onFrames }
        callback?(frames)
    }
}

/// A continuous sine at `rate`, handed out in buffers of any size. The phase
/// is carried between calls, so the signal has no seam where one buffer ends.
struct SineSource {
    let rate: Double
    var frequency = 440.0
    var amplitude: Float = 0.4
    private var position = 0

    init(rate: Double, frequency: Double = 440, amplitude: Float = 0.4) {
        self.rate = rate
        self.frequency = frequency
        self.amplitude = amplitude
    }

    var framesProduced: Int { position }

    mutating func buffer(frames: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frames {
            channel[index] = amplitude
                * Float(sin(2 * Double.pi * frequency * Double(position + index) / rate))
        }
        position += frames
        return buffer
    }
}

/// Collects what `AudioCapture` hands the live path.
final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _pcm = Data()
    private var _chunks = 0
    private var _largest = 0

    var pcm: Data { lock.withLock { _pcm } }
    var chunks: Int { lock.withLock { _chunks } }
    var bytes: Int { lock.withLock { _pcm.count } }
    /// The biggest single chunk, in bytes: a gap written as one buffer shows
    /// up here.
    var largestChunk: Int { lock.withLock { _largest } }

    /// `keep: false` counts without holding the audio, for runs of hours.
    var keep = true

    func receive(_ chunk: CapturedAudio) {
        lock.withLock {
            if keep { _pcm.append(chunk.pcm) }
            _chunks += 1
            _largest = max(_largest, chunk.pcm.count)
            _bytes += chunk.pcm.count
        }
    }

    private var _bytes = 0
    var totalBytes: Int { lock.withLock { _bytes } }
}
