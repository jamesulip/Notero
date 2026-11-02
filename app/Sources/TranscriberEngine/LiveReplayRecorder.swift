import Foundation
import TranscriberCore

/// CPU time of this process, from `getrusage`. Includes the model's CPU work and
/// leaves out the Neural Engine and the GPU, which a process does not account.
public struct CPUUsage: Sendable, Codable, Equatable {
    public var userMs: Double
    public var systemMs: Double
    public var totalMs: Double { userMs + systemMs }

    public static func now() -> CPUUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
        return CPUUsage(userMs: ms(usage.ru_utime), systemMs: ms(usage.ru_stime))
    }

    public func since(_ start: CPUUsage) -> CPUUsage {
        CPUUsage(userMs: userMs - start.userMs, systemMs: systemMs - start.systemMs)
    }
}

/// One delivery of committed words, as the consumer saw it.
public struct ReplayCommit: Sendable, Codable, Equatable {
    /// Milliseconds since the replay began, on the decoder's monotonic clock.
    public var wallMs: Double
    /// Audio handed to the decoder when the batch was delivered.
    public var audioFedMs: Int
    public var reason: CommitReason
    /// Each word's stamped end on the session timeline, in order. A word's commit
    /// latency is `wallMs` (or `audioFedMs`) minus its end.
    public var wordEndMs: [Int]
    /// Each word's start, in order.
    public var wordStartMs: [Int]
}

public struct ReplayBoundary: Sendable, Codable, Equatable {
    public var wallMs: Double
    public var audioMs: Int
    /// Where the VAD heard the utterance end.
    public var speechEndMs: Int
}

public struct ReplayAbandoned: Sendable, Codable, Equatable {
    public var wallMs: Double
    public var audioMs: Int
}

public struct ReplayVADSummary: Sendable, Codable, Equatable {
    public var batches = 0
    public var failed = 0
    public var maxLagMs = 0.0
    public var meanLagMs = 0.0
}

/// Everything one live replay did, in numbers: no audio and no words.
///
/// `eval/live_latency.py` reads this to measure what the live path costs a user:
/// when each word was committed, why, how long every decode took and which hops
/// were dropped, where each utterance closed, how much CPU it all used, and
/// whether committed text was only ever appended to.
public struct LiveReplayTrace: Sendable, Codable, Equatable {
    public var schema = 1
    public var realtime: Bool
    /// Replay start to `finish()` returning.
    public var replayWallMs: Double
    public var decodes: [DecodeSpan]
    public var dropped: [DroppedHop]
    public var skippedSilent: Int
    public var boundaries: [ReplayBoundary]
    public var abandoned: [ReplayAbandoned]
    public var commits: [ReplayCommit]
    public var vad: ReplayVADSummary
    public var cpu: CPUUsage
    public var invariants: CommitInvariantReport
}

/// Installs itself on a `LiveDecoder`, records what the decoder reports and
/// checks the commit invariant on every delivery.
///
/// The decoder's trace hook and `onCommitted` are the only things it touches.
/// A downstream consumer can still be given (it is called after the recorder has
/// looked at the batch). One recorder per decoder, created before audio is fed.
@MainActor
public final class LiveReplayRecorder {
    private let decoder: LiveDecoder
    private let realtime: Bool
    private let downstream: (([Token]) -> Void)?

    private var monitor = CommitInvariantMonitor()
    private var commits: [ReplayCommit] = []
    private var decodes: [DecodeSpan] = []
    private var dropped: [DroppedHop] = []
    private var skippedSilent = 0
    private var boundaries: [ReplayBoundary] = []
    private var abandoned: [ReplayAbandoned] = []
    private var vad = ReplayVADSummary()
    private var vadLagSum = 0.0
    private var pendingReason: CommitReason = .agreed

    private var startMs = 0.0
    private var startCPU = CPUUsage.now()
    private var fedMs = 0

    public init(decoder: LiveDecoder, realtime: Bool, onCommitted: (([Token]) -> Void)? = nil) {
        self.decoder = decoder
        self.realtime = realtime
        self.downstream = onCommitted
        decoder.trace = { [weak self] event in self?.record(event) }
        decoder.onCommitted = { [weak self] tokens in self?.delivered(tokens) }
    }

    /// Marks the start of the replay: wall time zero and the CPU baseline.
    public func begin() {
        startMs = decoder.traceNowMs
        startCPU = CPUUsage.now()
    }

    /// Audio handed to the decoder so far. Set before each `ingest`, so a word
    /// committed during that call is measured against the audio that had arrived.
    public func noteFed(_ ms: Int) {
        fedMs = ms
    }

    /// Ends the recording. Call after `decoder.finish()`.
    public func finish() -> LiveReplayTrace {
        let endMs = decoder.traceNowMs
        monitor.finish(decoderCommitted: decoder.committed, audioMs: decoder.currentMs)
        let cpu = CPUUsage.now().since(startCPU)
        if vad.batches > 0 { vad.meanLagMs = vadLagSum / Double(vad.batches) }
        let origin = startMs
        return LiveReplayTrace(
            realtime: realtime,
            replayWallMs: endMs - origin,
            decodes: decodes.map { span in
                var shifted = span
                shifted.requestedWallMs -= origin
                return shifted
            },
            dropped: dropped.map { drop in
                var shifted = drop
                shifted.wallMs -= origin
                return shifted
            },
            skippedSilent: skippedSilent,
            boundaries: boundaries.map {
                ReplayBoundary(wallMs: $0.wallMs - origin, audioMs: $0.audioMs, speechEndMs: $0.speechEndMs)
            },
            abandoned: abandoned.map { ReplayAbandoned(wallMs: $0.wallMs - origin, audioMs: $0.audioMs) },
            commits: commits.map { commit in
                var shifted = commit
                shifted.wallMs -= origin
                return shifted
            },
            vad: vad,
            cpu: cpu,
            invariants: monitor.report)
    }

    private func record(_ event: LiveTraceEvent) {
        switch event {
        case .decode(let span):
            decodes.append(span)
        case .dropped(let drop):
            dropped.append(drop)
        case .skippedSilent:
            skippedSilent += 1
        case .vad(let span):
            vad.batches += 1
            if span.failed { vad.failed += 1 }
            vad.maxLagMs = Swift.max(vad.maxLagMs, span.lagMs)
            vadLagSum += span.lagMs
        case .commit(let span):
            // Delivered immediately before the `onCommitted` call for the same batch.
            pendingReason = span.reason
        case .boundary(let wallMs, let audioMs, let speechEndMs):
            boundaries.append(ReplayBoundary(wallMs: wallMs, audioMs: audioMs, speechEndMs: speechEndMs))
        case .abandoned(let wallMs, let audioMs):
            abandoned.append(ReplayAbandoned(wallMs: wallMs, audioMs: audioMs))
        }
    }

    private func delivered(_ tokens: [Token]) {
        monitor.observe(batch: tokens, decoderCommitted: decoder.committed, audioMs: decoder.currentMs)
        commits.append(ReplayCommit(wallMs: decoder.traceNowMs, audioFedMs: fedMs, reason: pendingReason,
                                    wordEndMs: tokens.map(\.endMs), wordStartMs: tokens.map(\.startMs)))
        pendingReason = .agreed
        downstream?(tokens)
    }
}
