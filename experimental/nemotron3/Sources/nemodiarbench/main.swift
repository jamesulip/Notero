import Darwin
import EngineSeams
import Foundation
@preconcurrency import FluidAudio
import Nemotron3Backend
import TranscriberCore

// EXPERIMENTAL. The Nemotron 3 counterpart of the app's `diarbench`: one audio file in,
// who-spoke-when as JSON out, with the time of the speaker work and the peak process
// footprint. The JSON has the fields `diarbench` writes, so `eval/diarization_eval.py`
// and `eval/der.py` read both the same way.
//
//   nemodiarbench --audio F.wav --models DIR --json OUT.json [--preset offline]
//                 [--threshold 0.5] [--min-duration 0.2] [--label L] [--carry-from PREV.json]
//   nemodiarbench --fetch CACHE --models DIR [--preset offline]     # the only download
//
// --audio must be 16 kHz mono 16-bit PCM WAV (`eval/diarization_eval.py` prepares it).
// One run per process: the peak footprint is a per-process maximum.

struct Options {
    var audio: URL?
    var models: URL?
    var json: URL?
    var fetch: URL?
    var label = ""
    var settings = Nemotron3SpeakerEngine.Settings.standard
    var carryFrom: URL?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("nemodiarbench: \(message)\n".utf8))
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
        case "--fetch": options.fetch = URL(fileURLWithPath: value())
        case "--label": options.label = value()
        case "--preset": options.settings.preset = value()
        case "--carry-from": options.carryFrom = URL(fileURLWithPath: value())
        case "--threshold":
            guard let v = Float(value()) else { fail("--threshold wants a number") }
            options.settings.threshold = v
        case "--min-duration":
            guard let v = Float(value()) else { fail("--min-duration wants a number") }
            options.settings.minDurationSeconds = v
        default: fail("unknown option \(flag)")
        }
    }
    return options
}

/// Peak and current physical footprint of this process, in bytes. Process footprint,
/// NOT model residency: Core ML weights on the Neural Engine or GPU are not all in it.
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

let options = parse()
guard let models = options.models else { fail("--models is required") }

// MARK: - Fetch: download one preset and lay it out flat for the engine

if let cache = options.fetch {
    guard let config = Nemotron3Config.preset(named: options.settings.preset) else {
        fail("unknown preset \(options.settings.preset)")
    }
    do {
        _ = try await Nemotron3Models.loadFromHuggingFace(config: config, cacheDirectory: cache)
    } catch {
        fail("download failed: \(error.localizedDescription)")
    }
    let fm = FileManager.default
    try fm.createDirectory(at: models, withIntermediateDirectories: true)
    for name in Nemotron3SpeakerEngine.requiredFiles(for: config) {
        guard let found = fm.enumerator(at: cache, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent == name }) else {
            fail("\(name) is not in \(cache.path) after the download")
        }
        let target = models.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: found, to: target)
    }
    print("ready: \(models.path)")
    exit(0)
}

guard let audioURL = options.audio else { fail("--audio is required") }
let source: WavPCM
do { source = try WavPCM(contentsOf: audioURL) } catch { fail("\(error)") }

let clock = ContinuousClock()
let engine = Nemotron3SpeakerEngine(modelsDirectory: models, settings: options.settings)

let prepareStart = clock.now
do { try await engine.prepare(progress: nil) } catch {
    fail("could not prepare the speaker model: \(error.localizedDescription)")
}
let prepareMs = milliseconds(clock.now - prepareStart)
let afterPrepare = footprint()

let diarizeStart = clock.now
let spans: [SpeakerSpan]
do {
    spans = try await engine.diarize(source, speechRegions: nil, mode: .accurate,
                                     expectedSpeakers: nil, progress: nil)
} catch {
    fail("diarization failed: \(error.localizedDescription)")
}
let diarizeMs = milliseconds(clock.now - diarizeStart)
let end = footprint()

let normalized = SegmentMerger.normalize(spans)

struct CarryOut: Encodable {
    var inherited: [String: String]
    var labels: [String: String]
    var kept: [String]
}

struct Out: Encodable {
    struct Span: Encodable {
        var start: Double
        var end: Double
        var speaker: String
    }
    var synthetic = false
    var experimental = true
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
    var tuning: [String: Double]
    var preset: String
    var fluidAudioVersion: String
    var carry: CarryOut?
}

var carryOut: CarryOut?
if let previous = options.carryFrom {
    struct Previous: Decodable {
        struct Span: Decodable { var start: Double; var end: Double; var speaker: String }
        var spans: [Span]
    }
    let earlier: Previous
    do {
        earlier = try JSONDecoder().decode(Previous.self, from: Data(contentsOf: previous))
    } catch { fail("could not read \(previous.path): \(error.localizedDescription)") }
    let old = earlier.spans.map {
        SpeakerSpan(speakerId: $0.speaker, startMs: Int($0.start * 1000), endMs: Int($0.end * 1000))
    }
    let carry = SpeakerMatching.carry(old: old, new: normalized.spans,
                                      newOrder: normalized.roster.map(\.id),
                                      named: Set(old.map(\.speakerId)))
    carryOut = CarryOut(inherited: carry.inherited, labels: carry.labels, kept: carry.kept)
}

let result = Out(
    label: options.label, engine: "nemotron3", mode: "accurate",
    audio: audioURL.lastPathComponent, durationMs: source.durationMs,
    spans: normalized.spans.sorted { $0.startMs < $1.startMs }.map {
        Out.Span(start: Double($0.startMs) / 1000, end: Double($0.endMs) / 1000, speaker: $0.speakerId)
    },
    speakers: normalized.roster.count,
    prepareMs: prepareMs, diarizeMs: diarizeMs,
    peakFootprintBytes: end.peak,
    footprintAfterPrepareBytes: afterPrepare.current,
    footprintAtEndBytes: end.current,
    tuning: [
        "threshold": Double(options.settings.threshold),
        "minDurationSeconds": Double(options.settings.minDurationSeconds),
        "feedWindowMs": Double(options.settings.feedWindowMs),
    ],
    preset: options.settings.preset,
    fluidAudioVersion: "0.18.0",
    carry: carryOut
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
