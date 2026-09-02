import Foundation
import TranscriberCore
import TranscriberEngine

// Headless end-to-end run of the same pipeline the app uses.
//
// Not a second implementation: it calls `OfflinePipeline`, `SpeakerEngine` and
// `Exporter` exactly as the queue does. That is the point -- it verifies the
// real path on real audio without a window, a microphone, or a human, which is
// what makes it usable from CI and from the eval harness in ../eval.
//
//   swift run -c release transcribe --audio clip.wav [--reference ref.txt]
//                                   [--models DIR] [--model ID] [--tier fast]
//                                   [--language tl] [--no-diarize] [--room-mode]
//                                   [--minutes] [--format txt]

struct Options {
    var audio: URL?
    var reference: URL?
    var models = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Transcriber/Models")
    var modelId: String?
    var tier: ModelTier = .balanced
    var language = LanguageCatalogue.defaultLanguage
    var diarize = true
    var roomMode = false
    var minutes = false
    var format: ExportFormat = .txt
    var output: URL?
}

func parse() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while let flag = arguments.first {
        arguments.removeFirst()
        func value() -> String? {
            guard let next = arguments.first, !next.hasPrefix("--") else { return nil }
            arguments.removeFirst()
            return next
        }
        switch flag {
        case "--audio": options.audio = value().map { URL(fileURLWithPath: $0) }
        case "--reference": options.reference = value().map { URL(fileURLWithPath: $0) }
        case "--models": options.models = value().map { URL(fileURLWithPath: $0) } ?? options.models
        case "--model": options.modelId = value()
        case "--tier": options.tier = value().flatMap(ModelTier.init(rawValue:)) ?? options.tier
        case "--language": options.language = value() ?? options.language
        case "--format": options.format = value().flatMap(ExportFormat.init(rawValue:)) ?? options.format
        case "--out": options.output = value().map { URL(fileURLWithPath: $0) }
        case "--no-diarize": options.diarize = false
        case "--minutes": options.minutes = true
        case "--room-mode": options.roomMode = true
        case "--help", "-h":
            print("""
            transcribe --audio FILE [--reference FILE] [--models DIR]
                       [--model ID | --tier fast|balanced|accurate]
                       [--language tl] [--no-diarize] [--minutes]
                       [--format txt|srt|vtt|json] [--out FILE]
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown option \(flag)\n".utf8))
            exit(2)
        }
    }
    return options
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let options = parse()
guard let audioURL = options.audio else {
    log("error: --audio is required (see --help)")
    exit(2)
}

let started = Date()
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("transcriber-cli-\(UUID().uuidString).wav")
defer { try? FileManager.default.removeItem(at: scratch) }

log("preparing 16 kHz working copy…")
_ = try await AudioCache.build(from: audioURL, to: scratch)
let rawPCM = try MappedPCM(contentsOf: scratch)
// Room mode wraps the source exactly as the queue does, so this verifies
// the shipping filter rather than a second implementation of it.
let source: any PCMSource = options.roomMode ? HighPassPCM(rawPCM) : rawPCM
if options.roomMode { log("room mode: high-pass at \(Int(HighPassFilter.roomCornerHz)) Hz") }
log("audio: \(TimeFormat.short(ms: source.durationMs)) (\(source.sampleCount) samples)")

let engines = EngineHost(modelsDirectory: options.models)
let modelId = options.modelId ?? options.tier.defaultModelId
log("model: \(modelId)")

try await engines.loadModel(modelId) { message, _ in log("  \(message)") }
try? await engines.prepareVAD { message, _ in log("  \(message)") }

let vad = await engines.voiceActivity
let regions = try await OfflinePipeline.speechRegions(in: source, using: vad)
let windows = OfflinePipeline.windows(for: regions, durationMs: source.durationMs)
if ProcessInfo.processInfo.environment["TRANSCRIBE_DEBUG_SPANS"] != nil {
    for region in regions {
        log(String(format: "  region %7.2f-%7.2f",
                   Double(region.startMs) / 1000, Double(region.endMs) / 1000))
    }
}
let speechMs = regions.reduce(0) { $0 + $1.durationMs }
log("speech: \(regions.count) regions, \(TimeFormat.short(ms: speechMs)) in \(windows.count) windows")

let decodeStarted = Date()
let asr = await engines.recognizer
let decoded = try await OfflinePipeline.transcribe(
    source: source, windows: windows, using: asr,
    language: options.language, prompt: nil
)
let decodeMs = Int(Date().timeIntervalSince(decodeStarted) * 1000)
log("decoded \(decoded.tokens.count) words in \(TimeFormat.short(ms: decodeMs)) "
    + "(RTF \(String(format: "%.3f", Double(decodeMs) / Double(max(1, source.durationMs)))))")
if decoded.retriedWindows > 0 { log("  \(decoded.retriedWindows) window(s) needed a warmer retry") }
if decoded.droppedWindows > 0 { log("  WARNING \(decoded.droppedWindows) window(s) never decoded — audio is missing from this transcript") }

var spans: [SpeakerSpan] = []
var roster: [SpeakerLabel] = []
if options.diarize {
    do {
        try await engines.prepareDiarizer { message, _ in log("  \(message)") }
        let diarizeStarted = Date()
        let raw = try await engines.diarize(source)
        if ProcessInfo.processInfo.environment["TRANSCRIBE_DEBUG_SPANS"] != nil {
            for span in raw.sorted(by: { $0.startMs < $1.startMs }) {
                log(String(format: "  span %7.2f-%7.2f %@ q=%.2f",
                           Double(span.startMs) / 1000, Double(span.endMs) / 1000,
                           span.speakerId, span.quality ?? -1))
            }
        }
        let normalized = SegmentMerger.normalize(raw)
        spans = normalized.spans
        roster = normalized.roster
        log("speakers: \(roster.count) in "
            + "\(TimeFormat.short(ms: Int(Date().timeIntervalSince(diarizeStarted) * 1000)))")
    } catch {
        log("speaker identification unavailable: \(error.localizedDescription)")
    }
    await engines.releaseDiarizer()
}

let segments = SegmentMerger.segments(from: decoded.tokens, spans: spans)
let document = MeetingDocument(
    id: UUID(),
    title: audioURL.deletingPathExtension().lastPathComponent,
    kind: options.diarize ? .meeting : .recording,
    createdAt: Date(),
    durationMs: source.durationMs,
    language: decoded.detectedLanguage ?? options.language,
    modelId: modelId,
    audioFileName: audioURL.lastPathComponent,
    speakers: roster,
    segments: segments
)

let rendered = Exporter.render(options.format, document: document)
if let output = options.output {
    try rendered.write(to: output, atomically: true, encoding: .utf8)
    log("wrote \(output.path)")
} else {
    print(rendered)
}

// Minutes are the one stage that leaves the machine, so they are opt-in here
// exactly as they are in the app -- never a side effect of transcribing.
if options.minutes {
    log("drafting minutes with Claude…")
    let minutesStarted = Date()
    do {
        let raw = try await ClaudeCLIMinutes().generate(prompt: Minutes.prompt(for: document))
        let draft = try Minutes.parse(raw, against: segments)
        log("minutes: \(draft.items.count) item(s) in "
            + "\(TimeFormat.short(ms: Int(Date().timeIntervalSince(minutesStarted) * 1000)))")
        if draft.uncitedCount > 0 {
            log("  WARNING \(draft.uncitedCount) item(s) cited a moment not in the transcript")
        }
        print("\nSUMMARY\n\(draft.summary)")
        for kind in MeetingItemKind.allCases {
            let items = draft.items.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            print("\n\(kind.plural.uppercased())")
            for item in items {
                let at = item.sourceMs.map { " [\(TimeFormat.short(ms: $0))]" } ?? " [uncited]"
                let owner = item.owner.map { " (\($0))" } ?? ""
                print("- \(item.text)\(owner)\(at)")
            }
        }
    } catch {
        log("minutes unavailable: \(error.localizedDescription)")
    }
}

if let referenceURL = options.reference {
    let reference = try String(contentsOf: referenceURL, encoding: .utf8)
    let hypothesis = segments.map(\.displayText).joined(separator: " ")
    let wer = WordErrorRate.score(reference: reference, hypothesis: hypothesis)
    log(String(format: "WER %.4f (%.1f%%)", wer, wer * 100))
}

log("peak memory \(MemoryProbe.footprintMB()) MB, "
    + "total \(TimeFormat.short(ms: Int(Date().timeIntervalSince(started) * 1000)))")
