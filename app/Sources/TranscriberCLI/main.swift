import Foundation
import TranscriberCore
import TranscriberEngine

// Headless end-to-end run of the same pipeline the app uses.
//
// Not a second implementation: it calls `OfflinePipeline`, `LiveDecoder`,
// `SpeakerEngine` and `Exporter` exactly as the app does. That is the point --
// it verifies the real path on real audio without a window, a microphone, or a
// human, which is what makes it usable from CI and from the eval harness in
// ../eval.
//
//   swift run -c release transcribe --audio clip.wav [--reference ref.txt]
//                                   [--models DIR] [--model ID] [--tier fast]
//                                   [--language tl] [--fast-diarize|--no-diarize]
//                                   [--format txt] [--json report.json]
//
// `--live` replays the file through the live path instead -- ring buffer, VAD,
// hop schedule, LocalAgreement and finalization -- feeding 100 ms at a time.
// By default every decode is awaited so the schedule runs as if the model were
// infinitely fast and nothing is dropped: that measures the mechanism.
// `--realtime` paces the feed at wall-clock speed instead and measures drops.

struct Options {
    var audio: URL?
    var reference: URL?
    var models = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Transcriber/Models")
    var modelId: String?
    var tier: ModelTier = .balanced
    var language = LanguageCatalogue.defaultLanguage
    /// Names and terms for the decoder, as the app's Vocabulary field.
    var vocabulary: String?
    /// Put the built-in style primer for the language in front of the prompt,
    /// as the app does by default.
    var styleHint = false
    var diarizationMode: DiarizationMode = .accurate
    var roomMode = false
    var format: ExportFormat = .txt
    var output: URL?
    var json: URL?
    // Live replay.
    var live = false
    var realtime = false
    var hopMs = SessionConfig().hopMs
    var preRollMs = SessionConfig().preRollMs
    var contextMs = SessionConfig().contextMs
    var adaptiveHop = false
    // Capture smoke test.
    var record = false
    var captureSource: CaptureSource = .microphone
    var deviceUID: String?
    var seconds = 10.0
    var gui = false
    var listDevices = false
    var channelScan = false
    /// Which lane of a two-lane recording to read, for measuring one against
    /// the other.
    var lane: CaptureLane?
    var logFile: URL?
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
        case "--prompt": options.vocabulary = value()
        case "--style-hint": options.styleHint = true
        case "--format": options.format = value().flatMap(ExportFormat.init(rawValue:)) ?? options.format
        case "--out": options.output = value().map { URL(fileURLWithPath: $0) }
        case "--json": options.json = value().map { URL(fileURLWithPath: $0) }
        case "--fast-diarize": options.diarizationMode = .fast
        case "--no-diarize": options.diarizationMode = .off
        case "--room-mode": options.roomMode = true
        case "--live": options.live = true
        case "--realtime": options.realtime = true
        case "--adaptive-hop": options.adaptiveHop = true
        case "--record": options.record = true
        case "--source":
            options.captureSource = value().flatMap(CaptureSource.init(rawValue:))
                ?? options.captureSource
        case "--device": options.deviceUID = value()
        case "--gui": options.gui = true
        case "--devices": options.listDevices = true
        case "--channels": options.channelScan = true
        case "--lane": options.lane = value().flatMap(CaptureLane.init(rawValue:))
        case "--log": options.logFile = value().map { URL(fileURLWithPath: $0) }
        case "--seconds": options.seconds = value().flatMap(Double.init) ?? options.seconds
        case "--hop": options.hopMs = value().flatMap(Int.init) ?? options.hopMs
        case "--pre-roll": options.preRollMs = value().flatMap(Int.init) ?? options.preRollMs
        case "--context": options.contextMs = value().flatMap(Int.init) ?? options.contextMs
        case "--help", "-h":
            print("""
            transcribe --audio FILE [--reference FILE] [--models DIR]
                       [--model ID | --tier fast|balanced|accurate]
                       [--language tl] [--prompt "Maria, Jose"] [--style-hint]
                       [--fast-diarize | --no-diarize] [--room-mode]
                       [--format txt|markdown|srt|vtt|json] [--out FILE] [--json FILE]
                       [--live [--realtime] [--hop MS] [--pre-roll MS] [--context MS] [--adaptive-hop]]
            transcribe --record [--source microphone|systemAudio|both] [--device UID]
                       [--seconds N] [--out FILE.m4a] [--gui]
            transcribe --audio FILE --lane room|remote   # one channel of a two-lane file
            transcribe --devices
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown option \(flag)\n".utf8))
            exit(2)
        }
    }
    return options
}

/// A second copy of the log on disk, for runs with no terminal attached.
/// `open` launches through LaunchServices, which is the whole point of the GUI
/// probe -- and which throws stderr away.
nonisolated(unsafe) var logFileHandle: FileHandle?

func log(_ message: String) {
    let line = Data((message + "\n").utf8)
    FileHandle.standardError.write(line)
    logFileHandle?.write(line)
}

/// One run, machine-readable. What `eval/compare_language.py` reads.
struct RunReport: Codable {
    var audio: String
    var mode: String
    var model: String
    var language: String
    var detectedLanguage: String?
    var windowLanguages: [String?]
    var durationMs: Int
    var decodeMs: Int
    /// Wall-clock decode time over audio duration.
    var rtf: Double
    var wordCount: Int
    var transcript: String
    var words: [Token]
    var wer: Double?
    var live: SessionStats?
    var config: SessionConfig?
}

let options = parse()

if let logURL = options.logFile {
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    logFileHandle = try? FileHandle(forWritingTo: logURL)
}

if options.listDevices {
    let defaultInput = AudioDevices.defaultInput()?.uid
    let defaultOutput = AudioDevices.defaultOutput()?.uid
    for device in AudioDevices.all() {
        var marks: [String] = []
        if device.canRecord { marks.append("in:\(device.inputChannels)") }
        if device.canPlay { marks.append("out:\(device.outputChannels)") }
        if device.uid == defaultInput { marks.append("default input") }
        if device.uid == defaultOutput { marks.append("default output") }
        print("\(device.name)  [\(marks.joined(separator: ", "))]\n    \(device.uid)")
    }
    exit(0)
}

if options.channelScan {
    runChannelScan(seconds: options.seconds)
}

// Before the --audio requirement: this captures rather than reads.
if options.record {
    runRecord(source: options.captureSource, deviceUID: options.deviceUID,
              seconds: options.seconds, out: options.output, gui: options.gui)
}

guard let audioURL = options.audio else {
    log("error: --audio is required (see --help)")
    exit(2)
}
// Checked here so a wrong path says so. AVFoundation reports a missing file
// as "The operation could not be completed", which sends people looking for
// a codec problem they do not have.
guard FileManager.default.fileExists(atPath: audioURL.path) else {
    log("error: no such file: \(audioURL.path)")
    exit(2)
}

let started = Date()
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("transcriber-cli-\(UUID().uuidString).wav")
defer { try? FileManager.default.removeItem(at: scratch) }

log("preparing 16 kHz working copy…"
    + (options.lane.map { " (\($0.rawValue) lane only)" } ?? ""))
do {
    // A two-lane recording holds the room and the call in separate channels.
    // Reading one of them is how the two get measured against each other:
    // the same speech, once through a microphone and once before the speaker.
    _ = try await AudioCache.build(from: audioURL, to: scratch,
                                   channel: options.lane.map(ArchiveChannels.channel(for:)))
} catch {
    log("error: could not read \(audioURL.path): \(error.localizedDescription)")
    exit(1)
}
let rawPCM: MappedPCM
do {
    rawPCM = try MappedPCM(contentsOf: scratch)
} catch {
    log("error: \(error.localizedDescription)")
    exit(1)
}
// Room mode wraps the source exactly as the queue does, so this verifies
// the shipping filter rather than a second implementation of it.
let source: any PCMSource = options.roomMode ? HighPassPCM(rawPCM) : rawPCM
if options.roomMode { log("room mode: high-pass at \(Int(HighPassFilter.roomCornerHz)) Hz") }
log("audio: \(TimeFormat.short(ms: source.durationMs)) (\(source.sampleCount) samples)")

let engines = EngineHost(modelsDirectory: options.models)
let modelId = options.modelId ?? options.tier.defaultModelId
log("model: \(modelId)")
let prompt = TranscriptionPrompt.compose(language: options.language,
                                         usePrimer: options.styleHint,
                                         vocabulary: options.vocabulary)
if let prompt { log("prompt: \(prompt)") }

do {
    try await engines.loadModel(modelId) { message, _ in log("  \(message)") }
} catch {
    log("error: could not load model \(modelId): \(error.localizedDescription)")
    exit(1)
}
try? await engines.prepareVAD { message, _ in log("  \(message)") }
let vad = await engines.voiceActivity
let asr = await engines.recognizer

var tokens: [Token] = []
var detectedLanguage: String?
var windowLanguages: [String?] = []
var offlineRegions: [SpeechRegion]?
var liveStats: SessionStats?
var liveConfig: SessionConfig?
let decodeStarted = Date()

if options.live {
    // The live path, fed from the file. Same decoder, same schedule, same
    // commit policy as a recording -- minus the microphone.
    let config = SessionConfig(
        contextMs: options.contextMs, hopMs: options.hopMs, language: options.language,
        prompt: prompt, preRollMs: options.preRollMs, adaptiveHop: options.adaptiveHop
    )
    liveConfig = config
    await vad.reset()
    let decoder = LiveDecoder(config: config, recognizer: asr, vad: vad)
    decoder.onCommitted = { tokens += $0 }
    log("live replay: hop \(config.hopMs) ms, pre-roll \(config.preRollMs) ms, context "
        + "\(config.contextMs) ms\(config.adaptiveHop ? ", adaptive hop" : "")"
        + "\(options.realtime ? ", real-time pacing" : ", every decode awaited")")

    let chunkMs = 100
    var cursor = 0
    while cursor < source.durationMs {
        let end = min(source.durationMs, cursor + chunkMs)
        decoder.ingest(PCM.data(from: source.floats(msRange: cursor..<end)))
        cursor = end
        if options.realtime {
            try? await Task.sleep(for: .milliseconds(chunkMs))
        } else {
            await decoder.drain()
        }
    }
    await decoder.finish()
    let stats = decoder.stats
    liveStats = stats
    detectedLanguage = options.language
    log("live: \(stats.hops) decodes, \(stats.droppedHops) dropped, \(stats.skippedSilent) silent, "
        + "\(stats.forcedCommits) forced, \(stats.boundaries) boundaries "
        + "(\(stats.finalizations) final decodes, \(stats.finalizationsAbandoned) abandoned), "
        + "\(stats.unagreedTailCommits) unagreed tail words, \(stats.finalFlushOnEmpty) empty finals, "
        + "\(stats.duplicatesDropped) deduplicated, "
        + "mean RTF \(String(format: "%.3f", stats.meanRtf))")
    if stats.failedHops > 0 {
        log("  WARNING \(stats.failedHops) decode(s) failed: \(stats.lastError ?? "")")
    }
} else {
    let regions: [SpeechRegion]
    do {
        regions = try await OfflinePipeline.speechRegions(in: source, using: vad)
    } catch {
        log("error: voice activity detection failed: \(error.localizedDescription)")
        exit(1)
    }
    let windows = OfflinePipeline.windows(for: regions, durationMs: source.durationMs)
    offlineRegions = regions
    if ProcessInfo.processInfo.environment["TRANSCRIBE_DEBUG_SPANS"] != nil {
        for region in regions {
            log(String(format: "  region %7.2f-%7.2f",
                       Double(region.startMs) / 1000, Double(region.endMs) / 1000))
        }
    }
    let speechMs = regions.reduce(0) { $0 + $1.durationMs }
    log("speech: \(regions.count) regions, \(TimeFormat.short(ms: speechMs)) in \(windows.count) windows")

    let decoded: OfflinePipeline.DecodeReport
    do {
        decoded = try await OfflinePipeline.transcribe(
            source: source, windows: windows, using: asr,
            language: options.language, prompt: prompt
        )
    } catch {
        log("error: transcription failed: \(error.localizedDescription)")
        exit(1)
    }
    tokens = decoded.tokens
    detectedLanguage = decoded.detectedLanguage
    windowLanguages = decoded.windowLanguages
    if decoded.retriedWindows > 0 { log("  \(decoded.retriedWindows) window(s) needed a warmer retry") }
    if decoded.droppedWindows > 0 { log("  WARNING \(decoded.droppedWindows) window(s) never decoded — audio is missing from this transcript") }
    if options.language == "auto" {
        let seen = decoded.windowLanguages.compactMap { $0 }
        let histogram = Dictionary(seen.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value > $1.value }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: " ")
        log("  detected per window: \(histogram)")
    }
}

let decodeMs = Int(Date().timeIntervalSince(decodeStarted) * 1000)
log("decoded \(tokens.count) words in \(TimeFormat.short(ms: decodeMs)) "
    + "(RTF \(String(format: "%.3f", Double(decodeMs) / Double(max(1, source.durationMs)))))")

var spans: [SpeakerSpan] = []
var roster: [SpeakerLabel] = []
if options.diarizationMode.performsDiarization {
    do {
        try await engines.prepareDiarizer { message, _ in log("  \(message)") }
        let diarizeStarted = Date()
        let raw = try await engines.diarize(
            source, speechRegions: offlineRegions, mode: options.diarizationMode
        )
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

let segments = SegmentMerger.segments(from: tokens, spans: spans)
let document = MeetingDocument(
    id: UUID(),
    title: audioURL.deletingPathExtension().lastPathComponent,
    kind: options.diarizationMode.performsDiarization ? .meeting : .recording,
    createdAt: Date(),
    durationMs: source.durationMs,
    language: detectedLanguage ?? options.language,
    modelId: modelId,
    audioFileName: audioURL.lastPathComponent,
    speakers: roster,
    segments: segments
)

let rendered = Exporter.render(options.format, document: document)
if let output = options.output {
    do {
        try rendered.write(to: output, atomically: true, encoding: .utf8)
    } catch {
        log("error: could not write \(output.path): \(error.localizedDescription)")
        exit(1)
    }
    log("wrote \(output.path)")
} else {
    print(rendered)
}

let hypothesis = segments.map(\.displayText).joined(separator: " ")
var wer: Double?
if let referenceURL = options.reference {
    let reference: String
    do {
        reference = try String(contentsOf: referenceURL, encoding: .utf8)
    } catch {
        log("error: could not read \(referenceURL.path): \(error.localizedDescription)")
        exit(1)
    }
    let score = WordErrorRate.score(reference: reference, hypothesis: hypothesis)
    wer = score
    log(String(format: "WER %.4f (%.1f%%)", score, score * 100))
}

if let jsonURL = options.json {
    let report = RunReport(
        audio: audioURL.path,
        mode: options.live ? (options.realtime ? "live-realtime" : "live") : "offline",
        model: modelId,
        language: options.language,
        detectedLanguage: detectedLanguage,
        windowLanguages: windowLanguages,
        durationMs: source.durationMs,
        decodeMs: decodeMs,
        rtf: Double(decodeMs) / Double(max(1, source.durationMs)),
        wordCount: tokens.count,
        transcript: hypothesis,
        words: tokens,
        wer: wer,
        live: liveStats,
        config: liveConfig
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try FileManager.default.createDirectory(at: jsonURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoder.encode(report).write(to: jsonURL)
        log("wrote \(jsonURL.path)")
    } catch {
        log("error: could not write \(jsonURL.path): \(error.localizedDescription)")
        exit(1)
    }
}

log("peak memory \(MemoryProbe.footprintMB()) MB, "
    + "total \(TimeFormat.short(ms: Int(Date().timeIntervalSince(started) * 1000)))")
