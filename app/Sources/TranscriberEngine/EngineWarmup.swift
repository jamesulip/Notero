import Foundation
@preconcurrency import FluidAudio
import WhisperKit

/// Compile-time proof both backends are linked and the versions we expect.
/// Also the single place that documents what each one is here for.
public enum EngineBackends {
    public static let asr = "WhisperKit 1.1.0 (CoreML, ANE)"
    public static let vad = "FluidAudio Silero VAD (CoreML)"
    public static let diarization = "FluidAudio pyannote segmentation + WeSpeaker embedding (CoreML)"
}
