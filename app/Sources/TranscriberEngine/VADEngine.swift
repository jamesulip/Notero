import Foundation
@preconcurrency import FluidAudio
import TranscriberCore

/// Voice activity, neural where possible and energy where not.
///
/// VAD does two jobs on the live path and both are cheap threshold decisions:
/// skip inference while nobody is talking -- Whisper hallucinates confidently
/// on silence -- and end a segment after enough trailing silence so the last
/// words of an utterance do not sit forever one pass short of agreement.
///
/// Silero (through FluidAudio, on the Neural Engine) is markedly better in a
/// noisy room. The energy detector stays as the fallback because the failure it
/// covers is real: the model has to be downloaded before first use, and a VAD
/// that cannot load must not take recording down with it.
public actor VADEngine: VoiceActivityDetecting {

    public enum Backend: String, Sendable {
        case silero, energy
    }

    private let modelsDirectory: URL
    private let preferNeural: Bool
    private var manager: VadManager?
    private var streamState: VadStreamState?
    private let fallback = EnergyVoiceActivity()

    /// 4096 samples at 16 kHz: 256 ms. FluidAudio's unified model's window.
    public static let chunkSamples = VadManager.chunkSize
    private static var chunkMs: Int { chunkSamples * 1000 / Audio.sampleRate }

    private var pending: [Float] = []
    private var speechMs = 0
    private var trailingSilenceMs = 0
    private var lastProbability: Float = 0

    public private(set) var backend: Backend = .energy

    public init(modelsDirectory: URL, preferNeural: Bool = true) {
        self.modelsDirectory = modelsDirectory
        self.preferNeural = preferNeural
    }

    // MARK: - Lifecycle

    public func prepare(progress: ProgressReport?) async throws {
        guard preferNeural else {
            backend = .energy
            return
        }
        guard manager == nil else { return }
        progress?("Loading voice activity model…", nil)
        do {
            let manager = try await VadManager(
                config: VadConfig(defaultThreshold: 0.45),
                modelDirectory: modelsDirectory
            )
            self.manager = manager
            streamState = await manager.makeStreamState()
            backend = .silero
        } catch {
            // Recording still works; it just decodes a few more silent windows.
            manager = nil
            backend = .energy
            progress?("Voice activity model unavailable, using energy detection", nil)
        }
    }

    public func reset() async {
        pending.removeAll()
        speechMs = 0
        trailingSilenceMs = 0
        lastProbability = 0
        fallback.reset()
        if let manager { streamState = await manager.makeStreamState() }
    }

    public func clearSpeechCounter() {
        speechMs = 0
        fallback.clearSpeechCounter()
    }

    // MARK: - Streaming

    public func push(_ samples: [Float]) async throws -> VoiceActivityReading {
        guard let manager, var state = streamState else {
            let reading = fallback.push(samples)
            return VoiceActivityReading(
                isSpeech: reading.lastLevel >= 0.02,
                probability: reading.lastLevel,
                trailingSilenceMs: reading.trailingSilenceMs,
                speechMs: reading.speechMs
            )
        }

        pending.append(contentsOf: samples)
        while pending.count >= Self.chunkSamples {
            let chunk = Array(pending.prefix(Self.chunkSamples))
            pending.removeFirst(Self.chunkSamples)
            let result = try await manager.processStreamingChunk(chunk, state: state)
            state = result.state
            lastProbability = result.probability
            if result.probability >= 0.45 {
                speechMs += Self.chunkMs
                trailingSilenceMs = 0
            } else {
                trailingSilenceMs += Self.chunkMs
            }
        }
        streamState = state
        return VoiceActivityReading(
            isSpeech: lastProbability >= 0.45,
            probability: lastProbability,
            trailingSilenceMs: trailingSilenceMs,
            speechMs: speechMs
        )
    }

    // MARK: - Offline

    /// Speech regions across a whole clip. The import path uses this to avoid
    /// paying decode time for the silence between utterances.
    ///
    /// `maxSpeechDuration` is set just under the decode window rather than left
    /// at the 14 s default: the detector splits a long stretch at the quietest
    /// point it can find, which is a far better place to end a decode window
    /// than an arbitrary count of seconds. Leaving it low would work too, but
    /// it costs a decode per fragment.
    public func regions(in samples: [Float]) async throws -> [SpeechRegion] {
        guard let manager else { return energyRegions(samples) }
        let config = VadSegmentationConfig(
            minSpeechDuration: 0.2,
            minSilenceDuration: 0.35,
            maxSpeechDuration: 25.0,
            speechPadding: 0.1
        )
        let segments = try await manager.segmentSpeech(samples, config: config)
        return segments.map {
            SpeechRegion(startMs: Int($0.startTime * 1000), endMs: Int($0.endTime * 1000))
        }
    }

    private func energyRegions(_ samples: [Float]) -> [SpeechRegion] {
        let frame = EnergyVoiceActivity.frameSamples
        let frameMs = EnergyVoiceActivity.frameMs
        var out: [SpeechRegion] = []
        var start: Int?
        var silence = 0

        var index = 0
        while index + frame <= samples.count {
            var sum: Float = 0
            for offset in index..<(index + frame) { sum += samples[offset] * samples[offset] }
            let rms = (sum / Float(frame)).squareRoot()
            let atMs = index * 1000 / Audio.sampleRate

            if rms >= 0.02 {
                if start == nil { start = atMs }
                silence = 0
            } else if let began = start {
                silence += frameMs
                if silence >= 400 {
                    out.append(SpeechRegion(startMs: began, endMs: atMs - silence + frameMs))
                    start = nil
                    silence = 0
                }
            }
            index += frame
        }
        if let began = start {
            out.append(SpeechRegion(startMs: began,
                                    endMs: samples.count * 1000 / Audio.sampleRate))
        }
        return out
    }
}
