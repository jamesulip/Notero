import Foundation

public struct VadState: Equatable, Sendable {
    public var lastLevel: Float = 0
    public var speechMs: Int = 0
    public var trailingSilenceMs: Int = 0
    public var frames: Int = 0

    public var hasSpeech: Bool { speechMs > 0 }
}

/// Energy-based voice activity detection.
///
/// The Python build used Silero, which is markedly better in noise. This is a
/// deliberate downgrade for the first native cut: Silero would mean carrying an
/// ONNX or CoreML runtime into the app, and the two jobs VAD does here --
/// skipping inference during silence, and ending a segment after trailing
/// silence -- are both threshold decisions that energy handles acceptably in a
/// quiet room. Swap in Silero (FluidAudio ships an ANE build) if it misfires on
/// real recordings; `speechThreshold` is the knob to try first.
///
/// Frames are 32 ms to match what Silero consumes, so the two are
/// interchangeable behind this interface.
public final class EnergyVoiceActivity {
    public static let frameSamples = 512          // 32 ms at 16 kHz
    public static let frameMs = 32

    /// RMS above which a frame counts as speech. Roughly -34 dBFS.
    public var speechThreshold: Float

    private var buffer = Data()
    private var leftover: [Float] = []
    private var state = VadState()

    public init(speechThreshold: Float = 0.02) {
        self.speechThreshold = speechThreshold
    }

    public var current: VadState { state }

    public func reset() {
        buffer.removeAll()
        leftover.removeAll()
        state = VadState()
    }

    /// Resets the speech tally without disturbing anything else. Called after a
    /// boundary flush so the next segment is measured from zero.
    public func clearSpeechCounter() {
        state.speechMs = 0
    }

    /// Float entry point. The neural detector consumes floats, so the fallback
    /// has to as well or the two would need different call sites.
    ///
    /// Mirrors the Data path: append first, then drain whole frames from the
    /// head. Scoring the new samples immediately and the carried remainder
    /// afterwards would feed the detector audio out of chronological order,
    /// corrupting `trailingSilenceMs` -- the value segment boundaries hang on.
    @discardableResult
    public func push(_ samples: [Float]) -> VadState {
        leftover.append(contentsOf: samples)
        var start = 0
        while leftover.count - start >= Self.frameSamples {
            consume(Array(leftover[start..<(start + Self.frameSamples)]))
            start += Self.frameSamples
        }
        if start > 0 { leftover.removeFirst(start) }
        return state
    }

    private func consume(_ frame: [Float]) {
        var sumSquares: Float = 0
        for sample in frame { sumSquares += sample * sample }
        let rms = (sumSquares / Float(frame.count)).squareRoot()
        state.lastLevel = rms
        state.frames += 1
        if rms >= speechThreshold {
            state.speechMs += Self.frameMs
            state.trailingSilenceMs = 0
        } else {
            state.trailingSilenceMs += Self.frameMs
        }
    }

    @discardableResult
    public func push(_ pcm: Data) -> VadState {
        buffer.append(pcm)
        let frameBytes = Self.frameSamples * 2

        while buffer.count >= frameBytes {
            let frame = buffer.prefix(frameBytes)
            buffer.removeFirst(frameBytes)

            var sumSquares: Float = 0
            frame.withUnsafeBytes { raw in
                for index in 0..<Self.frameSamples {
                    let lo = UInt16(raw[index * 2])
                    let hi = UInt16(raw[index * 2 + 1])
                    let sample = Float(Int16(bitPattern: lo | (hi << 8))) / 32768.0
                    sumSquares += sample * sample
                }
            }
            let rms = (sumSquares / Float(Self.frameSamples)).squareRoot()

            state.lastLevel = rms
            state.frames += 1
            if rms >= speechThreshold {
                state.speechMs += Self.frameMs
                state.trailingSilenceMs = 0
            } else {
                state.trailingSilenceMs += Self.frameMs
            }
        }
        return state
    }
}
