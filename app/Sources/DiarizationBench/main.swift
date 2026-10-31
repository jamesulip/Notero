import Darwin
import Foundation
@preconcurrency import FluidAudio
import TranscriberCore
import TranscriberEngine

// Diarization-only measurement harness.
//
// Runs the shipping `SpeakerEngine` over one audio file and writes who-spoke-when
// as JSON, with the wall time of the speaker work and the process's peak
// physical footprint. No ASR, no VAD: the only variable is speaker processing.
// Score the output with `eval/der.py`.
//
//   diarbench --audio F.wav --models DIR --json OUT.json
//             [--mode accurate|fast] [--expected N] [--vad-regions none]
//
// One run per process on purpose: peak footprint is a per-process maximum, so a
// second run in the same process would inherit the first one's peak.
//
// Numbers from this tool on `eval/make_multispeaker.py` audio are SYNTHETIC.
// They compare two builds on the same file; they say nothing about real meetings.

struct Options {
    var audio: URL?
    var models = URL(fileURLWithPath: NSString(
        string: "~/Library/Application Support/Transcriber/Models").expandingTildeInPath)
    var json: URL?
    var mode: DiarizationMode = .accurate
    var expected: Int?
    var engine = "turn"
    var label = ""
    /// Reference RTTM: switches to probe mode, which reports how far apart the
    /// per-turn embeddings of the reference speakers are. No diarization runs.
    var probeRef: URL?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("diarbench: \(message)\n".utf8))
    exit(2)
}

func parse() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst()
    while let flag = args.popFirst() {
        func value() -> String {
            guard let next = args.popFirst() else { fail("\(flag) needs a value") }
            return next
        }
        switch flag {
        case "--audio": options.audio = URL(fileURLWithPath: value())
        case "--models": options.models = URL(fileURLWithPath: value())
        case "--json": options.json = URL(fileURLWithPath: value())
        case "--expected": options.expected = Int(value())
        case "--engine": options.engine = value()
        case "--label": options.label = value()
        case "--probe-ref": options.probeRef = URL(fileURLWithPath: value())
        case "--mode":
            switch value() {
            case "accurate": options.mode = .accurate
            case "fast": options.mode = .fast
            default: fail("--mode is accurate or fast")
            }
        default: fail("unknown option \(flag)")
        }
    }
    return options
}

/// Peak and current physical footprint of this process, in bytes. This is the
/// number Activity Monitor calls "Memory"; it includes the loaded models, so it
/// is process footprint, NOT model residency.
func footprint() -> (peak: UInt64, current: UInt64) {
    var info = rusage_info_current()
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
        }
    }
    guard status == 0 else { return (0, 0) }
    return (info.ri_lifetime_max_phys_footprint, info.ri_phys_footprint)
}

func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
}

/// Thread-safe stopwatch for the progress callback, which is `@Sendable`.
final class Marks: @unchecked Sendable {
    private let lock = NSLock()
    private var firstPassDone: ContinuousClock.Instant?
    func firstPass(at instant: ContinuousClock.Instant) {
        lock.lock(); defer { lock.unlock() }
        if firstPassDone == nil { firstPassDone = instant }
    }
    var firstPassInstant: ContinuousClock.Instant? {
        lock.lock(); defer { lock.unlock() }
        return firstPassDone
    }
}

let options = parse()
guard let audioURL = options.audio else { fail("--audio is required") }
guard FileManager.default.fileExists(atPath: audioURL.path) else { fail("no such file: \(audioURL.path)") }

let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("diarbench-\(UUID().uuidString).wav")
defer { try? FileManager.default.removeItem(at: scratch) }
do {
    _ = try await AudioCache.build(from: audioURL, to: scratch)
} catch {
    fail("could not read \(audioURL.path): \(error.localizedDescription)")
}
let source: MappedPCM
do { source = try MappedPCM(contentsOf: scratch) } catch { fail("\(error.localizedDescription)") }

// MARK: - Embedding probe

/// How separable are the reference speakers to the embedding model, before any
/// clustering? Each reference turn of at least 1 s is embedded from its own
/// audio exactly as `SpeakerEngine` does it (first 10 s, L2-normalized), then:
/// the mean distance of a turn to its own speaker's centroid, and the distance
/// between every pair of speaker centroids. `SpeakerEngine` joins turns closer
/// than 0.7, so a pair of centroids under about 0.7 cannot be told apart by
/// that policy no matter what the first pass did.
func probeReference(_ rttm: URL, source: MappedPCM, models: URL) async throws {
    struct Turn { var speaker: String; var startMs: Int; var endMs: Int }
    var turns: [Turn] = []
    for line in try String(contentsOf: rttm, encoding: .utf8).split(separator: "\n") {
        let f = line.split(separator: " ")
        guard f.count >= 8, f[0] == "SPEAKER", let start = Double(f[3]), let dur = Double(f[4]) else { continue }
        turns.append(Turn(speaker: String(f[7]), startMs: Int(start * 1000), endMs: Int((start + dur) * 1000)))
    }
    let loaded = try await DiarizerModels.downloadIfNeeded(
        to: models.appendingPathComponent("Diarizer", isDirectory: true))
    let manager = DiarizerManager(config: DiarizerConfig.default)
    manager.initialize(models: loaded)

    var vectors: [String: [[Float]]] = [:]
    for turn in turns where turn.endMs - turn.startMs >= 1_000 {
        let end = min(turn.endMs, turn.startMs + 10_000)
        let samples = source.floats(msRange: turn.startMs..<end)
        guard let raw = try? manager.extractSpeakerEmbedding(from: samples),
              manager.validateEmbedding(raw),
              let unit = TurnClusterer.normalized(raw) else { continue }
        vectors[turn.speaker, default: []].append(unit)
    }
    let speakers = vectors.keys.sorted()
    var centroids: [String: [Float]] = [:]
    for speaker in speakers {
        let n = Float(vectors[speaker]!.count)
        var sum = [Float](repeating: 0, count: vectors[speaker]![0].count)
        for v in vectors[speaker]! { for i in v.indices { sum[i] += v[i] / n } }
        centroids[speaker] = TurnClusterer.normalized(sum)
    }
    for speaker in speakers {
        let within = vectors[speaker]!.map { TurnClusterer.cosineDistance($0, centroids[speaker]!) }
        let mean = within.reduce(0, +) / Float(within.count)
        print(String(format: "%@  turns %2d  mean distance to own centroid %.2f  max %.2f",
                     speaker, within.count, mean, within.max() ?? 0))
    }
    for (i, a) in speakers.enumerated() {
        for b in speakers[(i + 1)...] {
            // Nearest cross-speaker TURN pair: the worst case for the 0.7 rule.
            var nearest: Float = 2
            for x in vectors[a]! { for y in vectors[b]! { nearest = min(nearest, TurnClusterer.cosineDistance(x, y)) } }
            print(String(format: "%@ vs %@  centroid distance %.2f  nearest turn pair %.2f",
                         a, b, TurnClusterer.cosineDistance(centroids[a]!, centroids[b]!), nearest))
        }
    }
}

if let rttm = options.probeRef {
    try await probeReference(rttm, source: source, models: options.models)
    exit(0)
}

let clock = ContinuousClock()
let engine: any SpeakerDiarizing
switch options.engine {
case "turn":
    engine = SpeakerEngine(modelsDirectory: options.models)
default:
    fail("unknown --engine \(options.engine)")
}

let prepareStart = clock.now
do {
    try await engine.prepare(progress: nil)
} catch {
    fail("could not prepare the speaker models: \(error.localizedDescription)")
}
let prepareMs = milliseconds(clock.now - prepareStart)
let afterPrepare = footprint()

let marks = Marks()
let diarizeStart = clock.now
let spans: [SpeakerSpan]
do {
    spans = try await engine.diarize(
        source, speechRegions: nil, mode: options.mode,
        expectedSpeakers: options.expected
    ) { fraction in
        // In accurate mode the first pass owns 0...0.7; in fast mode it is all of it.
        if fraction >= (options.mode == .accurate ? 0.7 : 1.0) { marks.firstPass(at: clock.now) }
    }
} catch {
    fail("diarization failed: \(error.localizedDescription)")
}
let diarizeEnd = clock.now
let diarizeMs = milliseconds(diarizeEnd - diarizeStart)
let firstPassMs = marks.firstPassInstant.map { milliseconds($0 - diarizeStart) }
let end = footprint()

// What the app shows: speakers renumbered S1, S2... by first appearance. That is
// the label that has to be stable from run to run, so it is the one scored.
let normalized = SegmentMerger.normalize(spans)

struct Out: Encodable {
    struct Span: Encodable {
        var start: Double
        var end: Double
        var speaker: String       // S1, S2... after SegmentMerger.normalize
    }
    var synthetic = true
    var label: String
    var engine: String
    var mode: String
    var audio: String
    var durationMs: Int
    var spans: [Span]
    var speakers: Int
    var prepareMs: Double
    var diarizeMs: Double
    var firstPassMs: Double?
    var secondPassMs: Double?
    var peakFootprintBytes: UInt64
    var footprintAfterPrepareBytes: UInt64
    var footprintAtEndBytes: UInt64
}

let outSpans = normalized.spans.sorted { $0.startMs < $1.startMs }.map { span in
    Out.Span(start: Double(span.startMs) / 1000, end: Double(span.endMs) / 1000,
             speaker: span.speakerId)
}

let result = Out(
    label: options.label, engine: options.engine,
    mode: options.mode == .accurate ? "accurate" : "fast",
    audio: audioURL.lastPathComponent, durationMs: source.durationMs,
    spans: outSpans,
    speakers: normalized.roster.count,
    prepareMs: prepareMs, diarizeMs: diarizeMs,
    firstPassMs: firstPassMs,
    secondPassMs: firstPassMs.map { diarizeMs - $0 },
    peakFootprintBytes: end.peak,
    footprintAfterPrepareBytes: afterPrepare.current,
    footprintAtEndBytes: end.current
)

await engine.unload()

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
let data = try encoder.encode(result)
if let json = options.json {
    try FileManager.default.createDirectory(at: json.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: json)
} else {
    print(String(decoding: data, as: UTF8.self))
}
