import Foundation
import TranscriberCore

/// Whole-file transcription.
///
/// Not one call per file and not one call per hop. VAD finds where speech
/// actually is, those regions are packed into windows just under Whisper's
/// 30-second limit, and each window is decoded once. Three things fall out of
/// that: silence is never decoded (Whisper invents sentences in silence),
/// windows never cut mid-word if a pause is available, and peak memory is one
/// window rather than one file.
public enum OfflinePipeline {

    /// Whisper's receptive field is 30 s; anything longer is truncated
    /// silently. 28 leaves room for the padding either side of a region.
    public static let maxWindowMs = 28_000
    /// Slack allowed when rejoining a region that a processing seam cut in two.
    public static let seamToleranceMs = 80
    /// Audio kept either side of a speech region, so onsets are not clipped.
    public static let padMs = 200
    /// How far past a window's real audio a word may be timestamped before it
    /// is treated as a hallucination.
    ///
    /// Whisper pads every input to 30 s and will happily decode the padding,
    /// emitting confident sentences that were never spoken. Anything starting
    /// past the audio it was given is that.
    static let paddingToleranceMs = 250

    public struct Progress: Sendable {
        public var stage: String
        public var fraction: Double
    }

    /// Speech regions over a whole source, found a few minutes at a time.
    ///
    /// The detector takes an array, so handing it the file would mean
    /// materializing all of it. Five-minute windows are 4.8M floats each.
    public static func speechRegions(
        in source: any PCMSource, using vad: any VoiceActivityDetecting,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SpeechRegion] {
        let windows = source.windows(ofMs: 5 * 60 * 1000)
        var out: [SpeechRegion] = []
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let offsetMs = Audio.samplesToMs(window.lowerBound)
            let found = try await vad.regions(in: source.floats(window)).map {
                SpeechRegion(startMs: $0.startMs + offsetMs, endMs: $0.endMs + offsetMs)
            }
            out = joinAcrossSeam(out, found, at: offsetMs)
            progress?(Double(index + 1) / Double(max(1, windows.count)))
        }
        return out
    }

    /// Rejoins only the one region a processing seam may have cut in half.
    ///
    /// Nothing else is joined. The detector's own boundaries are the point: it
    /// splits long speech at the quietest moment it can find, and those are
    /// exactly the places a decode window should end. Merging generously here
    /// would hand `windows` a single region per recording and force every
    /// boundary back to an arbitrary count of seconds, mid-word.
    static func joinAcrossSeam(_ existing: [SpeechRegion], _ next: [SpeechRegion],
                               at seamMs: Int) -> [SpeechRegion] {
        var out = existing
        guard var last = out.last, let first = next.first,
              abs(last.endMs - seamMs) <= seamToleranceMs,
              abs(first.startMs - seamMs) <= seamToleranceMs
        else {
            out.append(contentsOf: next)
            return out
        }
        last.endMs = max(last.endMs, first.endMs)
        out[out.count - 1] = last
        out.append(contentsOf: next.dropFirst())
        return out
    }

    /// Packs regions into decode windows no longer than `maxWindowMs`.
    ///
    /// Windows end where regions end, which is to say in silence. That is the
    /// whole reason the packing exists: a fixed 28-second stride would cut
    /// mid-word roughly every time, and Whisper handed half a word at each end
    /// of a window guesses at both.
    ///
    /// A region longer than one window on its own -- an uninterrupted
    /// monologue with no pause for 28 seconds -- has to be cut at the window
    /// boundary. There is nowhere better, and it is why callers must not rely
    /// on sentence structure surviving across windows.
    public static func windows(for regions: [SpeechRegion], durationMs: Int) -> [SpeechRegion] {
        guard !regions.isEmpty else { return [] }
        var out: [SpeechRegion] = []
        var current: SpeechRegion?

        for region in regions {
            var start = max(0, region.startMs - padMs)
            let end = min(durationMs, region.endMs + padMs)

            while start < end {
                let chunkEnd = min(end, start + maxWindowMs)
                if var open = current, chunkEnd - open.startMs <= maxWindowMs {
                    open.endMs = chunkEnd
                    current = open
                } else {
                    if let open = current { out.append(open) }
                    current = SpeechRegion(startMs: start, endMs: chunkEnd)
                }
                start = chunkEnd
            }
        }
        if let open = current { out.append(open) }
        return out
    }

    /// What one pass over the windows produced.
    public struct DecodeReport: Sendable {
        public var tokens: [Token]
        public var detectedLanguage: String?
        /// Windows that came back empty and succeeded on a warmer retry.
        public var retriedWindows: Int
        /// Windows that came back empty every time. Audio the transcript is
        /// missing, and the caller is expected to say so rather than present a
        /// short transcript as complete.
        public var droppedWindows: Int
    }

    /// Decodes every window and returns words on the file's timeline.
    ///
    /// Windows that come back empty are retried, and empty is not the same as
    /// silent: VAD already said there was speech there. WhisperKit returns an
    /// empty result set for a window it gives up on, and it gives up
    /// deterministically -- on the Taglish fixture a 24.876 s window returned
    /// nothing on every single attempt, while the same audio plus 600 ms
    /// decoded fine. Twenty seconds of speech went missing from a transcript
    /// that looked merely short. So a refused window is decoded again on
    /// *different* audio, and finally in halves, which is both shorter and
    /// differently bounded.
    public static let maxDecodeAttempts = 3
    /// How much further either side each retry reaches.
    static let retryWidenMs = 700
    /// How many times a refused window may be halved before it is given up on.
    static let maxSplitDepth = 2
    /// Below this a fragment is not worth splitting further.
    static let minSplitMs = 4_000

    public static func transcribe(
        source: any PCMSource,
        windows: [SpeechRegion],
        using asr: any SpeechRecognizing,
        language: String,
        prompt: String?,
        progress: (@Sendable (Double) -> Void)? = nil,
        /// Called after each window with the words it produced, already on the
        /// file timeline and in order. What lets a two-hour transcript appear
        /// as it is decoded rather than after.
        onWindow: (@Sendable (_ tokens: [Token], _ window: SpeechRegion) -> Void)? = nil
    ) async throws -> DecodeReport {
        var tokens: [Token] = []
        var detected: String?
        var retried = 0
        var dropped = 0
        /// Nothing may be emitted starting before this. Windows overlap by
        /// `padMs` so onsets are not clipped, and a word inside the overlap was
        /// already committed by the window before.
        var floorMs = 0

        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let outcome = try await decode(
                window, in: source, using: asr, language: language, prompt: prompt,
                notBefore: floorMs, depth: 0
            )
            detected = detected ?? outcome.language
            if outcome.tokens.isEmpty {
                dropped += 1
            } else if outcome.neededRetry {
                retried += 1
            }
            if let last = outcome.tokens.last {
                // A little slack: the next window re-decodes the boundary word
                // and its timings will not land on the same millisecond.
                floorMs = max(floorMs, last.endMs - 120)
            }
            tokens.append(contentsOf: outcome.tokens)
            onWindow?(outcome.tokens, window)
            progress?(Double(index + 1) / Double(max(1, windows.count)))
        }
        return DecodeReport(
            tokens: tokens.sorted { $0.startMs < $1.startMs },
            detectedLanguage: detected,
            retriedWindows: retried,
            droppedWindows: dropped
        )
    }

    struct Outcome {
        var tokens: [Token]
        var language: String?
        var neededRetry: Bool
    }

    /// One window: decode, widen, then halve.
    static func decode(
        _ window: SpeechRegion, in source: any PCMSource, using asr: any SpeechRecognizing,
        language: String, prompt: String?, notBefore floorMs: Int, depth: Int
    ) async throws -> Outcome {
        var detected: String?

        for attempt in 0..<maxDecodeAttempts {
            try Task.checkCancellation()
            let widen = attempt * retryWidenMs
            let decodeWindow = SpeechRegion(
                startMs: max(0, window.startMs - widen),
                endMs: min(source.durationMs, window.endMs + widen)
            )
            let samples = source.floats(msRange: decodeWindow.startMs..<decodeWindow.endMs)
            guard samples.count > Audio.sampleRate / 10 else { break }

            let output = try await asr.transcribe(ASRRequest(
                samples: samples, language: language, prompt: prompt,
                wordTimestamps: true, decodeAttempt: attempt
            ))
            detected = detected ?? output.detectedLanguage
            let produced = rebase(output.tokens, into: decodeWindow,
                                  keeping: window, notBefore: floorMs)
            if !produced.isEmpty {
                return Outcome(tokens: produced, language: detected, neededRetry: attempt > 0)
            }
        }

        // Still refused. Halve it: a shorter window with different boundaries is
        // a different decode problem, and the halves are independently retried.
        guard depth < maxSplitDepth, window.durationMs >= minSplitMs else {
            return Outcome(tokens: [], language: detected, neededRetry: false)
        }
        let middle = window.startMs + window.durationMs / 2
        let halves = [
            SpeechRegion(startMs: window.startMs, endMs: min(source.durationMs, middle + padMs)),
            SpeechRegion(startMs: max(0, middle - padMs), endMs: window.endMs),
        ]

        var tokens: [Token] = []
        var floor = floorMs
        for half in halves {
            let outcome = try await decode(half, in: source, using: asr, language: language,
                                           prompt: prompt, notBefore: floor, depth: depth + 1)
            detected = detected ?? outcome.language
            if let last = outcome.tokens.last { floor = max(floor, last.endMs - 120) }
            tokens.append(contentsOf: outcome.tokens)
        }
        return Outcome(tokens: tokens, language: detected, neededRetry: !tokens.isEmpty)
    }

    /// Window-relative timings to file-relative, dropping padding
    /// hallucinations, anything already committed, and anything a widened
    /// retry pulled in from a neighbouring window.
    static func rebase(_ tokens: [Token], into decoded: SpeechRegion,
                       keeping owned: SpeechRegion, notBefore floorMs: Int) -> [Token] {
        var out: [Token] = []
        out.reserveCapacity(tokens.count)
        for token in tokens {
            guard !token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let start = decoded.startMs + max(0, token.startMs)
            let end = decoded.startMs + max(token.startMs, token.endMs)
            // Whisper pads every input to 30 s and will decode the padding,
            // emitting confident sentences that were never spoken. Anything
            // starting past the audio it was handed is that.
            guard start < decoded.endMs + paddingToleranceMs else { continue }
            // A retry reaches into its neighbours to change the boundary. Their
            // words are their own to emit.
            guard start >= floorMs, start < owned.endMs + paddingToleranceMs else { continue }
            out.append(Token(
                text: token.text,
                startMs: min(start, decoded.endMs),
                endMs: min(max(end, start + 1), decoded.endMs + paddingToleranceMs),
                confidence: token.confidence
            ))
        }
        return out
    }
}
