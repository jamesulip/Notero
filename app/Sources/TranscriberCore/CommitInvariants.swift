import Foundation

/// One way a committed transcript broke the contract.
public struct CommitViolation: Sendable, Codable, Equatable {
    /// A stable slug: `rewritten`, `shrank`, `batchMismatch`, `backwards`, `overlap`,
    /// `pastAudio`, `emptyText`, `finalMismatch`.
    public var kind: String
    public var detail: String
    /// Audio received when it was seen.
    public var atAudioMs: Int

    public init(kind: String, detail: String, atAudioMs: Int) {
        self.kind = kind
        self.detail = detail
        self.atAudioMs = atAudioMs
    }
}

public struct CommitInvariantReport: Sendable, Codable, Equatable {
    public var batches: Int
    public var words: Int
    public var violations: [CommitViolation]

    public var holds: Bool { violations.isEmpty }
}

/// Checks, over a whole run, the promise the design rests on: committed text is
/// only ever appended to. Provisional text may change; a word that has been
/// committed never does.
///
/// It is fed what a consumer of the live decoder sees: each batch the decoder
/// delivers, and the decoder's own committed list at that moment. From those two
/// it holds, at every delivery, that
///
/// * the decoder's committed list is exactly everything delivered so far plus this
///   batch -- so no earlier word was rewritten, dropped, reordered or repeated
///   behind the consumer's back, and the consumer saw every commit;
/// * the timeline goes forward: each word starts at or after the previous word
///   ended, and ends at or after it starts;
/// * no word is timestamped past the audio received;
/// * no word is empty.
///
/// The property tests of `LocalAgreement` and `LiveDecoder` check the same thing
/// on random scripted recognizers. This is the check that runs over every real
/// replay of the experiment harness, where the recognizer is the model.
public struct CommitInvariantMonitor: Sendable {
    public private(set) var violations: [CommitViolation] = []
    public private(set) var batches = 0
    private var delivered: [Token] = []

    public init() {}

    public var words: Int { delivered.count }

    /// Everything delivered, in order.
    public var deliveredTokens: [Token] { delivered }

    public var report: CommitInvariantReport {
        CommitInvariantReport(batches: batches, words: delivered.count, violations: violations)
    }

    /// Call once per delivered batch, with the decoder's committed list as it
    /// stands when the batch is delivered and the audio received so far.
    public mutating func observe(batch: [Token], decoderCommitted: [Token], audioMs: Int) {
        batches += 1
        let expected = delivered + batch
        if decoderCommitted.count < delivered.count {
            note("shrank", "the decoder holds \(decoderCommitted.count) words after delivering "
                 + "\(delivered.count)", audioMs)
        } else if decoderCommitted != expected {
            if Array(decoderCommitted.prefix(delivered.count)) != delivered {
                let at = zip(decoderCommitted, delivered).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                note("rewritten", "word \(at.map(String.init) ?? "?") changed after it was delivered", audioMs)
            } else {
                note("batchMismatch", "the batch is not what the decoder appended: "
                     + "\(batch.count) delivered, \(decoderCommitted.count - delivered.count) appended", audioMs)
            }
        }
        var floor = delivered.last?.endMs ?? 0
        for token in batch {
            if token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note("emptyText", "a word with no text at \(token.startMs) ms", audioMs)
            }
            if token.endMs < token.startMs {
                note("backwards", "a word ends (\(token.endMs)) before it starts (\(token.startMs))", audioMs)
            }
            if token.startMs < floor {
                note("overlap", "a word starts at \(token.startMs) ms, before the previous one ended at \(floor) ms",
                     audioMs)
            }
            if token.endMs > audioMs {
                note("pastAudio", "a word ends at \(token.endMs) ms with \(audioMs) ms received", audioMs)
            }
            floor = Swift.max(floor, token.endMs)
        }
        delivered = expected
    }

    /// Call once when the session has ended, with the decoder's final committed list.
    public mutating func finish(decoderCommitted: [Token], audioMs: Int) {
        if decoderCommitted != delivered {
            note("finalMismatch", "the decoder ends with \(decoderCommitted.count) words and \(delivered.count) were delivered",
                 audioMs)
        }
    }

    private mutating func note(_ kind: String, _ detail: String, _ audioMs: Int) {
        // A broken invariant tends to repeat on every later batch; keep the first few of each kind.
        if violations.filter({ $0.kind == kind }).count < 5 {
            violations.append(CommitViolation(kind: kind, detail: detail, atAudioMs: audioMs))
        }
    }
}
