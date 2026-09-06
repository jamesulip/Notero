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
        /// What the decoder reported for each window, in order. The single
        /// `detectedLanguage` above is the first of these; on `auto` the rest
        /// show whether the decoder changed its mind mid-recording, which is
        /// the failure mode auto-detect is flagged for on Taglish.
        public var windowLanguages: [String?] = []
        /// Windows that came back empty and succeeded on a warmer retry.
        public var retriedWindows: Int
        /// Windows that came back empty every time. Audio the transcript is
        /// missing, and the caller is expected to say so rather than present a
        /// short transcript as complete.
        public var droppedWindows: Int
        /// Boundary to carry into a following batch. Kept public because the
        /// whole-file streaming wrapper invokes this decoder once per VAD
        /// batch while preserving overlap deduplication across calls.
        public var nextFloorMs: Int = 0
    }

    /// Whole-file output when VAD and decoding are interleaved a few minutes
    /// at a time. Timings are separate so the app can persist a useful stage
    /// profile even though the two stages no longer run in two large blocks.
    public struct FileDecodeReport: Sendable {
        public var regions: [SpeechRegion]
        public var decode: DecodeReport
        public var windowCount: Int
        public var speechWindowMs: Int
        public var vadMs: Int
        public var decodeMs: Int
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
        initialFloorMs: Int = 0,
        /// Called after each window with the words it produced, already on the
        /// file timeline and in order. What lets a two-hour transcript appear
        /// as it is decoded rather than after.
        onWindow: (@Sendable (_ tokens: [Token], _ window: SpeechRegion) -> Void)? = nil
    ) async throws -> DecodeReport {
        var tokens: [Token] = []
        var detected: String?
        var perWindow: [String?] = []
        var retried = 0
        var dropped = 0
        /// Nothing may be emitted starting before this. Windows overlap by
        /// `padMs` so onsets are not clipped, and a word inside the overlap was
        /// already committed by the window before.
        var floorMs = initialFloorMs

        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let outcome = try await decode(
                window, in: source, using: asr, language: language, prompt: prompt,
                notBefore: floorMs, depth: 0
            )
            detected = detected ?? outcome.language
            perWindow.append(outcome.language)
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
            windowLanguages: perWindow,
            retriedWindows: retried,
            droppedWindows: dropped,
            nextFloorMs: floorMs
        )
    }

    /// Scans and decodes a long file in bounded batches.
    ///
    /// The old path scanned the complete recording before the first Whisper
    /// call. A four-hour file therefore sat at "Transcribing" with no text even
    /// though every five-minute VAD result except its final seam was already
    /// safe to decode. Here only a region touching the right processing seam is
    /// carried forward; everything else is packed and decoded immediately.
    /// VAD and ASR remain sequential so they do not contend for the ANE.
    public static func transcribeFile(
        source: any PCMSource,
        using vad: any VoiceActivityDetecting,
        asr: any SpeechRecognizing,
        language: String,
        prompt: String?,
        progress: (@Sendable (Double) -> Void)? = nil,
        onWindow: (@Sendable (_ tokens: [Token], _ window: SpeechRegion) -> Void)? = nil
    ) async throws -> FileDecodeReport {
        let chunks = source.windows(ofMs: 5 * 60 * 1000)
        var carry: [SpeechRegion] = []
        var allRegions: [SpeechRegion] = []
        var allTokens: [Token] = []
        var detected: String?
        var languages: [String?] = []
        var retried = 0
        var dropped = 0
        var floorMs = 0
        var windowCount = 0
        var speechWindowMs = 0
        var vadMs = 0
        var decodeMs = 0

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let offsetMs = Audio.samplesToMs(chunk.lowerBound)
            let chunkEndMs = Audio.samplesToMs(chunk.upperBound)

            let vadStarted = Date()
            let found = try await vad.regions(in: source.floats(chunk)).map {
                SpeechRegion(startMs: $0.startMs + offsetMs,
                             endMs: $0.endMs + offsetMs)
            }
            vadMs += Int(Date().timeIntervalSince(vadStarted) * 1000)

            var candidates = joinAcrossSeam(carry, found, at: offsetMs)
            carry.removeAll(keepingCapacity: true)
            let isLast = index == chunks.count - 1
            if !isLast, let last = candidates.last,
               abs(last.endMs - chunkEndMs) <= seamToleranceMs {
                carry = [last]
                candidates.removeLast()
            }
            allRegions.append(contentsOf: candidates)
            let batchWindows = windows(for: candidates, durationMs: source.durationMs)
            windowCount += batchWindows.count
            speechWindowMs += batchWindows.reduce(0) { $0 + $1.durationMs }

            if !batchWindows.isEmpty {
                let decodeStarted = Date()
                let report = try await transcribe(
                    source: source, windows: batchWindows, using: asr,
                    language: language, prompt: prompt,
                    progress: { batchFraction in
                        let completed = Double(index) + batchFraction
                        progress?(completed / Double(max(1, chunks.count)))
                    },
                    initialFloorMs: floorMs,
                    onWindow: onWindow
                )
                decodeMs += Int(Date().timeIntervalSince(decodeStarted) * 1000)
                allTokens.append(contentsOf: report.tokens)
                detected = detected ?? report.detectedLanguage
                languages.append(contentsOf: report.windowLanguages)
                retried += report.retriedWindows
                dropped += report.droppedWindows
                floorMs = report.nextFloorMs
            }
            progress?(Double(index + 1) / Double(max(1, chunks.count)))
        }

        return FileDecodeReport(
            regions: allRegions.sorted { $0.startMs < $1.startMs },
            decode: DecodeReport(
                tokens: allTokens.sorted { $0.startMs < $1.startMs },
                detectedLanguage: detected,
                windowLanguages: languages,
                retriedWindows: retried,
                droppedWindows: dropped,
                nextFloorMs: floorMs
            ),
            windowCount: windowCount,
            speechWindowMs: speechWindowMs,
            vadMs: vadMs,
            decodeMs: decodeMs
        )
    }

    /// What a second pass over one stretch of the recording produced.
    public struct RangeDecodeReport: Sendable {
        /// Words inside the range, on the file's timeline.
        public var tokens: [Token]
        public var windowCount: Int
        public var retriedWindows: Int
        public var droppedWindows: Int
    }

    /// Decodes one stretch of a recording again, for the one turn the model
    /// got wrong in a long meeting. Four hours of audio must not be decoded
    /// again to fix forty seconds of it.
    ///
    /// The range is the caller's word that speech is there, so its edges are
    /// the edges of the decode: the first window starts at the start of the
    /// range and the last ends at its end, whatever the voice detector heard.
    /// Measured on a real turn, the detector placed the first region 600 ms
    /// after the turn began and the first word of the turn was lost. The
    /// detector still chooses the cut points inside a range longer than one
    /// window, so those fall in pauses as they do for the whole file. The
    /// windows reach `padMs` past each edge so an onset is not clipped, and
    /// the model stamps the first word of a window at the window's start:
    /// with the floor at the turn's own start, that word was dropped every
    /// time. A word therefore stays when its midpoint is inside the range. A
    /// word that lies mostly before the range belongs to the neighbour, which
    /// already has it.
    public static func transcribeRange(
        _ range: SpeechRegion,
        in source: any PCMSource,
        using vad: any VoiceActivityDetecting,
        asr: any SpeechRecognizing,
        language: String,
        prompt: String?,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> RangeDecodeReport {
        let from = max(0, range.startMs)
        let to = min(source.durationMs, range.endMs)
        guard to > from else {
            return RangeDecodeReport(tokens: [], windowCount: 0, retriedWindows: 0, droppedWindows: 0)
        }
        var regions = try await vad.regions(in: source.floats(msRange: from..<to)).map {
            SpeechRegion(startMs: $0.startMs + from, endMs: $0.endMs + from)
        }
        if regions.isEmpty {
            regions = [SpeechRegion(startMs: from, endMs: to)]
        } else {
            regions[0].startMs = from
            regions[regions.count - 1].endMs = to
        }
        let decodeWindows = windows(for: regions, durationMs: source.durationMs)
        let report = try await transcribe(
            source: source, windows: decodeWindows, using: asr,
            language: language, prompt: prompt, progress: progress,
            initialFloorMs: max(0, from - padMs)
        )
        return RangeDecodeReport(
            tokens: report.tokens.filter { ($0.startMs + $0.endMs) / 2 >= from && $0.startMs < to },
            windowCount: decodeWindows.count,
            retriedWindows: report.retriedWindows,
            droppedWindows: report.droppedWindows
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
