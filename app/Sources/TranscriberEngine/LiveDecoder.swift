import Foundation
import TranscriberCore

/// The decoding half of the live path: ring buffer, voice activity, the hop
/// scheduler, LocalAgreement, and utterance finalization.
///
/// `LiveSession` owns the microphone, the working copy and the observable
/// state the UI reads; this owns everything between a chunk of PCM arriving
/// and a token being committed. The split is what makes the scheduling
/// testable: hand it a scripted recognizer and a scripted VAD and every rule
/// below can be driven from a test with no model and no microphone.
///
/// Three rules govern the schedule:
///
/// - **Hops** happen every `hopMs` of audio and decode the whole window: the
///   committed pre-roll, the active region, and whatever silence has arrived.
///   One decode at a time; a hop that lands while another is running is
///   dropped rather than queued, because a stale partial is worse than none.
/// - **Finalization** is triggered by the VAD, not by the hop. When trailing
///   silence reaches `silenceBoundaryMs` and there is uncommitted speech, a
///   final decode is requested at once: run now if the slot is free, or as
///   soon as the running decode returns. If that running decode was a hop
///   whose window already reached the end of the speech, its result is used
///   and no second decode is made.
/// - **A boundary is concluded** only after that decode has gone through
///   LocalAgreement and only if the room is still silent when it returns. The
///   agreed prefix commits normally; the remainder -- the tail no earlier pass
///   had heard -- is committed from the final hypothesis at that confirmed
///   boundary. If someone resumed talking during the decode, nothing is
///   committed unagreed: the remainder stays provisional and the next silence
///   tries again.
@MainActor
public final class LiveDecoder {

    public enum DecodeKind: Sendable {
        case hop, final
    }

    public let config: SessionConfig
    private let recognizer: any SpeechRecognizing
    private let vad: any VoiceActivityDetecting

    private let ring: RingBuffer
    private let commit: LocalAgreement

    public private(set) var stats = SessionStats()

    /// Newly committed tokens, in order. Fired for agreed commits, forced
    /// commits, boundary tails and the final flush at `finish()`.
    public var onCommitted: (([Token]) -> Void)?
    /// The provisional tail after every decode. Empty once a boundary closes.
    public var onPartial: ((String) -> Void)?

    // Voice activity.
    /// Kept as compact PCM while it waits for a VAD batch. Expanding every
    /// microphone buffer to `[Float]` on the main actor made SwiftUI hitch;
    /// conversion now happens only after a full batch has moved to a detached
    /// worker.
    private var vadPending = Data()
    private var vadFedSamples = 0
    private var vadTask: Task<Void, Never>?
    private var lastReading = VoiceActivityReading(isSpeech: false, probability: 0,
                                                   trailingSilenceMs: 0, speechMs: 0)

    // Scheduling.
    private var msSinceHop = 0
    private var decodeTask: Task<Void, Never>?
    private var pendingFinal = false
    /// Where the utterance being finalized ended, on the session timeline.
    private var speechEndMs = 0
    /// Set when a silence run has had its finalization; cleared when the VAD
    /// hears speech again. Stops one long pause from finalizing repeatedly.
    private var finalizedThisSilence = false
    private var finishing = false
    private var lastInferMs = 0
    private var lastDecodeEndMs = 0
    /// A boundary closed; the VAD's per-utterance speech tally is stale until
    /// the next push clears it. Ordered with the pushes rather than fired off
    /// as a detached task so a reading can never be misattributed.
    private var clearSpeechPending = false

    /// Pauses the VAD has confirmed, on the session timeline, each at least
    /// `silenceBoundaryMs` long. A word the model places inside one was read
    /// out of silence -- Whisper's habit is to say the last phrase again -- and
    /// is dropped from every hypothesis, not only from the final decode. The
    /// final already drops its own tail past the pause; this catches the copy
    /// a *hop* produced, which survived when speech resumed before the final
    /// returned and the next two hops then agreed on it (FINDINGS §11).
    /// Pruned to what a window can still contain.
    private var silences: [Range<Int>] = []
    /// One VAD frame of slack when deciding whether a reading extends the
    /// pause already recorded or starts a new one: the frame count and the
    /// sample count round differently at a batch edge.
    private static let silenceStartSlackMs = 300

    public init(config: SessionConfig, recognizer: any SpeechRecognizing,
                vad: any VoiceActivityDetecting) {
        self.config = config
        self.recognizer = recognizer
        self.vad = vad
        self.ring = RingBuffer(contextMs: config.contextMs, preRollMs: config.preRollMs)
        self.commit = LocalAgreement(agreement: config.agreement)
    }

    /// Audio received so far. The transcript's clock.
    public var currentMs: Int { ring.totalMs }
    public var partial: String { commit.partial }
    public var committedEndMs: Int { commit.committedEndMs }
    public var committed: [Token] { commit.committed }

    /// The hop in force right now. Fixed unless `adaptiveHop` is on, in which
    /// case it tracks the last decode's cost and can never be shorter than
    /// 1.5x that -- which is what stops it from raising the drop rate.
    public var currentHopMs: Int {
        guard config.adaptiveHop else { return config.hopMs }
        return Swift.min(config.hopMs, Swift.max(config.minHopMs, lastInferMs * 3 / 2))
    }

    // MARK: - Ingest

    public func ingest(_ pcm: Data) {
        guard !finishing, !pcm.isEmpty else { return }
        ring.push(pcm)
        msSinceHop += Audio.bytesToMs(pcm.count)

        vadPending.append(pcm)
        if vadTask == nil,
           vadPending.count >= VADEngine.chunkSamples * Audio.bytesPerSample {
            let batch = vadPending
            vadPending = Data()
            vadFedSamples += batch.count / Audio.bytesPerSample
            let fedThroughMs = Audio.samplesToMs(vadFedSamples)
            vadTask = Task {
                let samples = await Task.detached(priority: .userInitiated) {
                    PCM.floats(from: batch)
                }.value
                await pumpVAD(samples, fedThroughMs: fedThroughMs)
                vadTask = nil
            }
        }

        guard msSinceHop >= currentHopMs else { return }
        msSinceHop = 0

        // One decode at a time. A hop that would queue behind a running one
        // is dropped -- unless a finalization is already waiting for that
        // slot, in which case this hop is superseded, not lost.
        guard decodeTask == nil else {
            if !pendingFinal { stats.droppedHops += 1 }
            return
        }
        if inSilence {
            // The VAD normally requests this itself the moment silence reaches
            // the threshold; the hop only has to catch a reading that landed
            // between batches. Otherwise nobody is talking: skip inference.
            if hasUncommittedSpeech, !finalizedThisSilence {
                armFinalization()
            } else {
                stats.skippedSilent += 1
            }
            return
        }
        startDecode(.hop)
    }

    // MARK: - Voice activity

    private var inSilence: Bool {
        lastReading.trailingSilenceMs >= config.silenceBoundaryMs
    }

    /// Whether a boundary would have anything to commit. `speechMs` counts
    /// from the last concluded boundary; the partial covers speech a hop has
    /// already heard but no boundary has closed.
    private var hasUncommittedSpeech: Bool {
        (!clearSpeechPending && lastReading.speechMs > 0) || commit.hasPartial
    }

    private func pumpVAD(_ samples: [Float], fedThroughMs: Int) async {
        if clearSpeechPending {
            await vad.clearSpeechCounter()
            clearSpeechPending = false
        }
        guard let reading = try? await vad.push(samples) else { return }
        let previous = lastReading
        lastReading = reading
        noteSilence(reading, heardThrough: fedThroughMs)
        guard !finishing else { return }

        // Re-arm when the silence counter reset, not when it reads zero: one
        // batch can carry a speech chunk followed by a silence chunk and come
        // back reading 256, never 0.
        if reading.trailingSilenceMs < previous.trailingSilenceMs {
            finalizedThisSilence = false
        }
        if inSilence, !finalizedThisSilence, hasUncommittedSpeech {
            speechEndMs = fedThroughMs - reading.trailingSilenceMs
            armFinalization()
        }
    }

    /// Records or extends a confirmed pause. Only pauses long enough to end an
    /// utterance count; shorter gaps are breath, and the model's word timings
    /// drift by more than their width.
    private func noteSilence(_ reading: VoiceActivityReading, heardThrough endMs: Int) {
        guard reading.trailingSilenceMs >= config.silenceBoundaryMs else { return }
        let startMs = endMs - reading.trailingSilenceMs
        if let last = silences.last, abs(last.lowerBound - startMs) <= Self.silenceStartSlackMs {
            silences[silences.count - 1] = Swift.min(last.lowerBound, startMs)..<Swift.max(last.upperBound, endMs)
        } else {
            silences.append(startMs..<endMs)
        }
        // Nothing before the commit can be committed again, so a pause that
        // ended before it has nothing left to protect.
        let floor = commit.committedEndMs
        silences.removeAll { $0.upperBound <= floor }
    }

    /// Whether a word that starts here was read out of a confirmed pause. The
    /// slack either side is the same drift the padding filter allows: a word
    /// that starts just inside a pause may be the last word of the utterance
    /// with its onset late, and one just before its end may be the first word
    /// after it with its onset early.
    private func startsInConfirmedSilence(_ startMs: Int) -> Bool {
        let slack = OfflinePipeline.paddingToleranceMs
        return silences.contains { startMs >= $0.lowerBound + slack && startMs < $0.upperBound - slack }
    }

    private func armFinalization() {
        finalizedThisSilence = true
        if speechEndMs == 0 {
            speechEndMs = Audio.samplesToMs(vadFedSamples) - lastReading.trailingSilenceMs
        }
        if decodeTask != nil {
            pendingFinal = true
        } else {
            startDecode(.final)
        }
    }

    // MARK: - Decoding

    private func startDecode(_ kind: DecodeKind) {
        msSinceHop = 0
        let (window, windowStartMs) = ring.window()
        let windowEndMs = ring.totalMs
        decodeTask = Task {
            let producedNothing = await runDecode(kind, window: window,
                                                 windowStartMs: windowStartMs,
                                                 windowEndMs: windowEndMs)
            decodeTask = nil
            afterDecode(kind, windowEndMs: windowEndMs, producedNothing: producedNothing)
        }
    }

    /// Decodes one window. Returns whether the model produced nothing usable,
    /// which a boundary treats differently from a hop.
    private func runDecode(_ kind: DecodeKind, window: Data, windowStartMs: Int,
                           windowEndMs: Int) async -> Bool {
        guard !window.isEmpty else { return true }
        commit.ceilingMs = windowEndMs
        lastDecodeEndMs = windowEndMs

        // The window has slid past the last commit, so audio at its head is
        // about to be discarded unagreed. Commit it now, or the next hypothesis
        // starts at a different word and prefixes stop aligning for good --
        // permanently, not until the next pause. With a pre-roll the window
        // normally starts *before* the commit; this fires only when the cap
        // has pushed it past.
        if windowStartMs > commit.committedEndMs {
            let forced = commit.forceCommit(before: windowStartMs)
            if !forced.isEmpty {
                stats.forcedCommits += 1
                deliver(forced)
            }
        }

        let output: ASROutput
        do {
            // A full context window can be hundreds of thousands of samples.
            // `Task {}` inherits MainActor here, so the old conversion blocked
            // animations and input even though the model API itself was async.
            let samples = await Task.detached(priority: .userInitiated) {
                PCM.floats(from: window)
            }.value
            try Task.checkCancellation()
            output = try await recognizer.transcribe(ASRRequest(
                samples: samples,
                language: config.language,
                prompt: config.prompt,
                wordTimestamps: true
            ))
        } catch {
            stats.failedHops += 1
            stats.lastError = error.localizedDescription
            if kind == .final { concludeBoundary(producedNothing: true) }
            return true
        }

        stats.hops += 1
        stats.totalAudioMs += output.audioMs
        stats.totalInferMs += output.inferMs
        stats.peakMemoryMB = max(stats.peakMemoryMB, MemoryProbe.footprintMB())
        lastInferMs = output.inferMs
        if kind == .final { stats.finalizations += 1 }

        var newly: [Token] = []
        if output.tokens.isEmpty {
            // Not silence: a decode threshold tripped. Worth counting, since it
            // is otherwise indistinguishable from nobody speaking.
            stats.emptyResults += 1
        } else {
            // Window-relative timings become absolute, so segments, exports and
            // diarization all share one timeline.
            //
            // Whisper pads every window to 30 s and will decode the padding --
            // most often by saying the last phrase again -- with timestamps past
            // the audio it was given. The offline path drops those in `rebase`;
            // here they were clamped to the ceiling and committed, which is how
            // a sentence before a pause came out three times. Anything starting
            // past the audio is that. At a final decode the VAD also knows where
            // speech ended: a word placed after it is silence being read.
            let audioEndMs = windowEndMs + OfflinePipeline.paddingToleranceMs
            let silentFromMs = (kind == .final && speechEndMs > 0)
                ? speechEndMs + OfflinePipeline.paddingToleranceMs : Int.max
            var absolute: [Token] = []
            absolute.reserveCapacity(output.tokens.count)
            for token in output.tokens {
                let start = windowStartMs + token.startMs
                guard start < audioEndMs, start < silentFromMs,
                      !startsInConfirmedSilence(start) else {
                    stats.hallucinationsDropped += 1
                    continue
                }
                absolute.append(Token(text: token.text, startMs: start,
                                      endMs: windowStartMs + token.endMs,
                                      confidence: token.confidence))
            }
            newly = commit.insert(absolute)
        }
        if !newly.isEmpty {
            ring.trim(to: commit.committedEndMs)
            deliver(newly)
        }
        if kind == .final {
            concludeBoundary(producedNothing: output.tokens.isEmpty)
        }
        stats.duplicatesDropped = commit.duplicatesDropped
        onPartial?(commit.partial)
        return output.tokens.isEmpty
    }

    /// Runs with the decode slot free again: the pending finalization, if any.
    private func afterDecode(_ kind: DecodeKind, windowEndMs: Int, producedNothing: Bool) {
        guard !finishing, pendingFinal else { return }
        pendingFinal = false
        guard inSilence else {
            // Someone spoke while the decode ran. A final now would only be
            // abandoned, and would push the next real hop back by its cost.
            stats.finalizationsAbandoned += 1
            return
        }
        if kind == .hop, windowEndMs >= speechEndMs {
            // The hop already heard the whole utterance. Its hypothesis has
            // been through agreement; conclude on it rather than decoding
            // nearly the same audio again.
            concludeBoundary(producedNothing: producedNothing)
            onPartial?(commit.partial)
            return
        }
        startDecode(.final)
    }

    /// Closes an utterance if the room is still silent. The agreed prefix is
    /// already committed; what remains is the tail only the last decode saw,
    /// committed here because the VAD confirmed nothing followed it.
    private func concludeBoundary(producedNothing: Bool) {
        guard inSilence else {
            stats.finalizationsAbandoned += 1
            return
        }
        // The tail only the last decode heard. Words it placed after the
        // point where the VAD heard speech end were decoded out of silence.
        let silentFromMs = speechEndMs > 0
            ? speechEndMs + OfflinePipeline.paddingToleranceMs : nil
        let before = commit.partialCount
        let tail = commit.flush(notAfter: silentFromMs)
        stats.hallucinationsDropped += max(0, before - tail.count)
        if !tail.isEmpty {
            if producedNothing {
                stats.finalFlushOnEmpty += 1
            } else {
                stats.unagreedTailCommits += tail.count
            }
            ring.trim(to: commit.committedEndMs)
            deliver(tail)
        }
        stats.boundaries += 1
        speechEndMs = 0
        clearSpeechPending = true
    }

    private func deliver(_ tokens: [Token]) {
        guard !tokens.isEmpty else { return }
        onCommitted?(tokens)
    }

    // MARK: - Ending

    /// Waits for whatever is in flight. Tests and the replay harness use this
    /// to make an inherently asynchronous schedule deterministic.
    public func drain() async {
        while let task = decodeTask ?? vadTask {
            await task.value
        }
    }

    /// Waits for the voice-activity batch in flight, leaving a decode alone.
    /// For tests that hold a decode open and need the VAD to be heard meanwhile.
    public func settleVAD() async {
        while let task = vadTask {
            await task.value
        }
    }

    /// Stops scheduling, drains the in-flight decode, gives the tail one
    /// agreement-checked decode if there is new audio to hear, then commits
    /// whatever is still provisional. Nothing arrives at `onCommitted` after
    /// this returns.
    public func finish() async {
        finishing = true
        await drain()
        pendingFinal = false

        // One more look at the tail, unless the last decode already reached
        // (within a VAD chunk of) the end of the audio.
        let unheardMs = ring.totalMs - lastDecodeEndMs
        let (window, windowStartMs) = ring.window()
        if hasUncommittedSpeech, !window.isEmpty,
           unheardMs >= Audio.samplesToMs(VADEngine.chunkSamples) {
            _ = await runDecode(.hop, window: window, windowStartMs: windowStartMs,
                                windowEndMs: ring.totalMs)
        }

        commit.ceilingMs = ring.totalMs
        let tail = commit.flush()
        if !tail.isEmpty {
            stats.unagreedTailCommits += tail.count
            deliver(tail)
        }
        stats.duplicatesDropped = commit.duplicatesDropped
        onPartial?("")
    }
}
