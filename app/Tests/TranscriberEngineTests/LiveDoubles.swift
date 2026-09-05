import Foundation
import TranscriberCore
@testable import TranscriberEngine

// Test doubles for the live path. Together they let `LiveDecoder` be driven
// from a test with no model and no microphone, and -- the important part --
// they know where in the session each window sits, so a test can assert on
// absolute timestamps and on exactly which audio each decode was handed.

/// PCM whose samples encode their own position on the session timeline.
///
/// Each millisecond is 16 samples; the first two carry the millisecond index
/// (low 15 bits, then the rest), so a recognizer handed any window can read its
/// absolute start from sample zero. `PCM.floats` divides by 32768, and the
/// round trip through `Int16` is exact.
enum OraclePCM {
    static func data(fromMs start: Int, ms: Int) -> Data {
        var out = Data(capacity: ms * 32)
        for m in start..<(start + ms) {
            var block = [Int16](repeating: 0, count: 16)
            block[0] = Int16(m & 0x7FFF)
            block[1] = Int16((m >> 15) & 0x7FFF)
            for sample in block {
                var little = sample.littleEndian
                withUnsafeBytes(of: &little) { out.append(contentsOf: $0) }
            }
        }
        return out
    }

    static func startMs(of samples: [Float]) -> Int {
        guard samples.count >= 2 else { return 0 }
        let low = Int((samples[0] * 32768).rounded())
        let high = Int((samples[1] * 32768).rounded())
        return low | (high << 15)
    }
}

/// A word on the session timeline, the ground truth a test speaks.
struct SpokenWord: Sendable {
    var text: String
    var startMs: Int
    var endMs: Int
}

/// Transcribes whatever ground-truth words overlap the window it is handed.
///
/// Window-relative timings, a leading space per token as Whisper produces,
/// and a clipped fragment when the window cuts a word -- which is exactly the
/// straddling token the commit boundary has to cope with. Optional jitter
/// shifts every timing by a few ms, alternating direction per call; optional
/// per-call text mutation makes hypotheses disagree on purpose.
actor OracleRecognizer: SpeechRecognizing {
    struct Call: Sendable {
        var startMs: Int
        var endMs: Int
    }

    var words: [SpokenWord]
    /// Things the model "hears" that nobody said. Returned like words when
    /// they overlap the window, but not part of the ground truth.
    var phantoms: [SpokenWord] = []
    /// Add a word out in the 30 s padding on every call, as Whisper does.
    var paddingPhantom = false
    var jitterMs = 0
    /// Token text is passed through this with the 1-based call index; a test
    /// can make a tail word wrong on one call or every word unique per call.
    var mutate: (@Sendable (_ text: String, _ call: Int, _ isLast: Bool) -> String)?
    var inferMs = 1
    private(set) var calls: [Call] = []

    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(words: [SpokenWord]) {
        self.words = words
    }

    var loadedModel: String? { "oracle" }
    func load(model: String, progress: ProgressReport?) async throws {}
    func unload() {}

    func setJitter(_ ms: Int) { jitterMs = ms }
    func setInferMs(_ ms: Int) { inferMs = ms }
    func setMutation(_ mutate: (@Sendable (String, Int, Bool) -> String)?) { self.mutate = mutate }
    func setPhantoms(_ phantoms: [SpokenWord], inPadding: Bool = false) {
        self.phantoms = phantoms
        paddingPhantom = inPadding
    }

    /// The next `transcribe` call blocks until `release()`.
    func hold() { held = true }
    func release() {
        held = false
        let resumed = waiters
        waiters = []
        for waiter in resumed { waiter.resume() }
    }

    func transcribe(_ request: ASRRequest) async throws -> ASROutput {
        let startMs = OraclePCM.startMs(of: request.samples)
        let durationMs = request.samples.count / 16
        let endMs = startMs + durationMs
        calls.append(Call(startMs: startMs, endMs: endMs))
        let index = calls.count
        if held {
            await withCheckedContinuation { waiters.append($0) }
        }

        let jitter = jitterMs == 0 ? 0 : (index.isMultiple(of: 2) ? jitterMs : -jitterMs)
        let overlapping = (words + phantoms)
            .filter { $0.endMs > startMs && $0.startMs < endMs }
            .sorted { $0.startMs < $1.startMs }
        var tokens: [Token] = []
        for (offset, word) in overlapping.enumerated() {
            var text = word.text
            if word.startMs < startMs {
                text = String(text.suffix(max(1, text.count / 2)))
            }
            if word.endMs > endMs {
                text = String(text.prefix(max(1, text.count / 2)))
            }
            if let mutate {
                text = mutate(text, index, offset == overlapping.count - 1)
            }
            let relativeStart = max(0, word.startMs - startMs + jitter)
            let relativeEnd = min(durationMs, word.endMs - startMs + jitter)
            tokens.append(Token(text: " " + text, startMs: relativeStart,
                                endMs: max(relativeEnd, relativeStart + 1), confidence: 0.9))
        }
        if paddingPhantom {
            tokens.append(Token(text: " hallucinated", startMs: durationMs + 5_000,
                                endMs: durationMs + 5_400, confidence: 0.9))
        }
        return ASROutput(tokens: tokens, audioMs: durationMs, inferMs: inferMs,
                         detectedLanguage: request.language)
    }
}

/// Voice activity from a script: speech is wherever the test says it is.
///
/// Frames are 32 ms like the energy detector, counted from the samples pushed
/// rather than from batch boundaries, so `trailingSilenceMs` is the same
/// whatever batch size the decoder happens to use.
actor ScriptedVAD: VoiceActivityDetecting {
    private let speech: [Range<Int>]
    private var leftover: [Float] = []
    private var framesSeen = 0
    private var speechMs = 0
    private var trailingSilenceMs = 0
    private var lastWasSpeech = false
    private(set) var clears = 0

    init(speech: [Range<Int>]) {
        self.speech = speech
    }

    func prepare(progress: ProgressReport?) async throws {}
    func regions(in samples: [Float]) async throws -> [SpeechRegion] { [] }

    func clearSpeechCounter() {
        speechMs = 0
        clears += 1
    }

    func reset() {
        leftover = []
        framesSeen = 0
        speechMs = 0
        trailingSilenceMs = 0
        lastWasSpeech = false
    }

    func push(_ samples: [Float]) async throws -> VoiceActivityReading {
        leftover.append(contentsOf: samples)
        let frame = EnergyVoiceActivity.frameSamples
        var consumed = 0
        while leftover.count - consumed >= frame {
            let atMs = framesSeen * EnergyVoiceActivity.frameMs
            let frameRange = atMs..<(atMs + EnergyVoiceActivity.frameMs)
            lastWasSpeech = speech.contains { $0.overlaps(frameRange) }
            if lastWasSpeech {
                speechMs += EnergyVoiceActivity.frameMs
                trailingSilenceMs = 0
            } else {
                trailingSilenceMs += EnergyVoiceActivity.frameMs
            }
            framesSeen += 1
            consumed += frame
        }
        if consumed > 0 { leftover.removeFirst(consumed) }
        return VoiceActivityReading(isSpeech: lastWasSpeech, probability: lastWasSpeech ? 1 : 0,
                                    trailingSilenceMs: trailingSilenceMs, speechMs: speechMs)
    }
}
