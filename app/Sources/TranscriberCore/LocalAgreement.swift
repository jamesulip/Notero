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

    private var history: [[Token]] = []

    public init(agreement: Int = 2) {
        precondition(agreement >= 2, "agreement must be at least 2")
        self.agreement = agreement
    }

    public var committedEndMs: Int { committed.last?.endMs ?? 0 }
    public var committedText: String { committed.joinedText }

    /// The provisional tail: newest hypothesis minus what is committed.
    public var partial: String { history.last?.joinedText ?? "" }

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
    /// Used when VAD reports a speech boundary and at session end. Without it
    /// the last words of every utterance would sit forever in the partial, one
    /// pass short of agreement.
    @discardableResult
    public func flush() -> [Token] {
        guard let tail = history.last, !tail.isEmpty else {
            history.removeAll()
            return []
        }
        history.removeAll()
        let committedNow = monotonic(tail)
        committed.append(contentsOf: committedNow)
        return committedNow
    }

    public func reset() {
        committed.removeAll()
        history.removeAll()
        ceilingMs = nil
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
    private func dropAlreadyCommitted(_ hypothesis: [Token]) -> [Token] {
        let boundary = committedEndMs
        var remaining = hypothesis.filter { $0.endMs > boundary }

        // Timestamps do most of the work. This catches the case where a pass
        // nudges a boundary word's timing by a few milliseconds and it would
        // otherwise be committed twice.
        var tail = committed.suffix(8).map(Self.key).filter { !$0.isEmpty }
        while let first = remaining.first, let last = tail.last {
            let head = Self.key(first)
            guard !head.isEmpty, head == last, first.startMs < boundary else { break }
            remaining.removeFirst()
            tail.removeLast()
        }
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
            out.append(Token(text: token.text, startMs: start, endMs: end))
            floor = end
        }
        return out
    }
}
