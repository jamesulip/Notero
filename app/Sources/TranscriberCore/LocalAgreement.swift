import Foundation

/// LocalAgreement-n commit policy.
///
/// Consecutive overlapping windows are transcribed independently. A token is
/// committed only once the last `agreement` passes have produced it at the same
/// position. Committed text is then frozen permanently -- that is what makes
/// the design contract true: provisional text may change, committed text never
/// will.
public final class LocalAgreement {
    public let agreement: Int
    public private(set) var committed: [Token] = []

    /// Absolute ms of audio received so far. Nothing may be timestamped past it.
    public var ceilingMs: Int?

    /// How far past the commit a re-decoded boundary word may start and still
    /// be recognised, by text, as the word already committed. Whisper's word
    /// timings drift between passes by tens of milliseconds and occasionally
    /// by a few hundred; this is the same slack the offline path allows for
    /// its padding hallucinations (`OfflinePipeline.paddingToleranceMs`).
    public static let timingSlackMs = 250

    /// Boundary words the model re-transcribed from already-committed audio
    /// that timestamps alone did not catch. Every hop drops the bulk of the
    /// pre-roll by time, silently; these are the ones text had to rescue.
    public private(set) var duplicatesDropped = 0

    private var history: [[Token]] = []

    public init(agreement: Int = 2) {
        precondition(agreement >= 2, "agreement must be at least 2")
        self.agreement = agreement
    }

    public var committedEndMs: Int { committed.last?.endMs ?? 0 }
    public var committedText: String { committed.joinedText }

    /// The provisional tail: newest hypothesis minus what is committed.
    public var partial: String { history.last?.joinedText ?? "" }

    /// Whether anything provisional is waiting on agreement.
    public var hasPartial: Bool { !(history.last?.isEmpty ?? true) }
    public var partialCount: Int { history.last?.count ?? 0 }

    // MARK: - Policy

    /// Feeds one window's transcription. Returns tokens newly committed.
    @discardableResult
    public func insert(_ hypothesis: [Token]) -> [Token] {
        history.append(dropAlreadyCommitted(hypothesis))
        if history.count > agreement { history.removeFirst() }
        guard history.count >= agreement else { return [] }

        let prefixLength = agreedPrefixLength(history)
        guard prefixLength > 0 else { return [] }

        let newly = monotonic(Array(history[history.count - 1].prefix(prefixLength)))
        committed.append(contentsOf: newly)
        // Drop the committed prefix from every retained hypothesis so the next
        // pass compares only what is still provisional.
        history = history.map { Array($0.dropFirst(prefixLength)) }
        return newly
    }

    /// Commits pending tokens ending at or before `absoluteMs`, unagreed.
    ///
    /// The escape hatch for when the context window has to slide. The window
    /// can only stay anchored to the last commit while commits keep happening;
    /// if two passes never agree, audio piles up until the buffer hits its cap
    /// and the window is forced forward. Once it moves past the committed
    /// point, consecutive hypotheses start at different words and nothing can
    /// ever commit again -- the stall is permanent, not temporary.
    @discardableResult
    public func forceCommit(before absoluteMs: Int) -> [Token] {
        guard let newest = history.last else { return [] }
        // Skip anything already committed. Retained hypotheses are trimmed by
        // prefix length, not by time, so filtering only on `absoluteMs` would
        // re-emit words agreed earlier -- visible as duplicated phrases, and
        // worst exactly when forcing is frequent.
        let take = newest.filter { committedEndMs < $0.endMs && $0.endMs <= absoluteMs }
        guard !take.isEmpty else { return [] }

        let committedNow = monotonic(take)
        committed.append(contentsOf: committedNow)
        let consumed = newest.filter { $0.endMs <= absoluteMs }.count
        history = history.map { Array($0.dropFirst(Swift.min(consumed, $0.count))) }
        return committedNow
    }

    /// Commits the provisional tail unconditionally.
    ///
    /// Used at a confirmed utterance boundary, after the final decode has had
    /// its chance to agree, and at session end. Without it the last words of
    /// every utterance would sit forever in the partial, one pass short of
    /// agreement.
    ///
    /// `notAfter` drops tail tokens that start at or past that absolute time
    /// before committing: at a confirmed boundary the VAD knows where speech
    /// ended, and a word the model places after that point was decoded out of
    /// silence, not speech.
    @discardableResult
    public func flush(notAfter limitMs: Int? = nil) -> [Token] {
        guard var tail = history.last, !tail.isEmpty else {
            history.removeAll()
            return []
        }
        history.removeAll()
        if let limitMs { tail.removeAll { $0.startMs >= limitMs } }
        guard !tail.isEmpty else { return [] }
        let committedNow = monotonic(tail)
        committed.append(contentsOf: committedNow)
        return committedNow
    }

    public func reset() {
        committed.removeAll()
        history.removeAll()
        ceilingMs = nil
        duplicatesDropped = 0
    }

    // MARK: - Internals

    /// Comparison form. Whisper varies casing and punctuation between passes on
    /// identical audio, so comparing raw text would block almost every commit.
    static func key(_ token: Token) -> String {
        let folded = token.text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        return String(folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "'"
        })
    }

    /// Removes tokens the window re-transcribed from already-committed audio.
    ///
    /// With a pre-roll in front of every window, the first second and a half
    /// of each hypothesis describes audio that is already committed, and the
    /// whole point of the pre-roll is that the model may segment it however
    /// it likes. Three rules, in order, against the last committed word `L`
    /// (`Ls...Le`, where `Le` is the commit boundary):
    ///
    /// 1. Anything ending at or before the boundary is pre-roll. Dropped by
    ///    time, whatever its text.
    /// 2. A token straddling the boundary is dropped when it starts nearer
    ///    `L`'s start than its end: a re-decode of `L`, or `L` merged with
    ///    the next word, begins where `L` began, while a genuinely new word
    ///    whose start bled early begins near `Le`. Anchoring on `L`'s own
    ///    duration is what keeps 100-200 ms function words safe -- a plain
    ///    midpoint test would drop one on every pass, so it could never commit.
    /// 3. What remains at the head is compared by text against the committed
    ///    tail, longest match first, allowing `timingSlackMs` of drift past
    ///    the boundary. This catches the boundary word whose timing shifted
    ///    by a few hundred milliseconds, and the two-word version of the same
    ///    thing, which timestamps cannot distinguish from new speech.
    ///
    /// Nothing starting at or after the boundary is ever dropped by time.
    private func dropAlreadyCommitted(_ hypothesis: [Token]) -> [Token] {
        guard let last = committed.last else { return hypothesis }
        let boundary = last.endMs
        let anchor = (last.startMs + last.endMs) / 2

        var remaining: [Token] = []
        remaining.reserveCapacity(hypothesis.count)
        var rescued = 0
        for token in hypothesis {
            if token.endMs <= boundary { continue }
            if token.startMs < boundary, token.startMs < anchor {
                rescued += 1
                continue
            }
            remaining.append(token)
        }

        let tail = committed.suffix(8).map(Self.key)
        var overlap = Swift.min(tail.count, remaining.count)
        while overlap > 0 {
            let head = remaining.prefix(overlap).map(Self.key)
            if Array(tail.suffix(overlap)) == head,
               !head.contains(where: \.isEmpty),
               remaining[overlap - 1].startMs < boundary + Self.timingSlackMs {
                break
            }
            overlap -= 1
        }
        if overlap > 0 {
            remaining.removeFirst(overlap)
            rescued += overlap
        }
        duplicatesDropped += rescued
        return remaining
    }

    private func agreedPrefixLength(_ hypotheses: [[Token]]) -> Int {
        guard let shortest = hypotheses.map(\.count).min() else { return 0 }
        var length = 0
        while length < shortest {
            let keys = Set(hypotheses.map { Self.key($0[length]) })
            guard keys.count == 1, let only = keys.first, !only.isEmpty else { break }
            length += 1
        }
        return length
    }

    /// Clamps timings so the committed timeline only moves forward.
    ///
    /// Word timings shift by tens of milliseconds between passes, so a token
    /// committed from a later window can carry a start earlier than the token
    /// before it. Harmless on screen, not harmless in an SRT file where cues
    /// must be ordered and non-overlapping. Pushing each token past the
    /// previous one also accumulates, so a long tail of overlapping timings can
    /// ratchet the clock past the end of the audio -- hence the ceiling.
    private func monotonic(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        out.reserveCapacity(tokens.count)
        var floor = committedEndMs
        for token in tokens {
            var start = Swift.max(token.startMs, floor)
            var end = Swift.max(token.endMs, start)
            if let ceiling = ceilingMs {
                start = Swift.min(start, ceiling)
                end = Swift.min(Swift.max(end, start), ceiling)
            }
            out.append(Token(text: token.text, startMs: start, endMs: end,
                             confidence: token.confidence))
            floor = end
        }
        return out
    }
}
