//  asrd -- persistent WhisperKit ASR sidecar.
//
//  Loads the model once and serves transcription requests over stdio, so the
//  orchestrator measures inference time rather than model-load time. A CLI
//  invocation per chunk would reload the model every hop and make the Phase 1
//  real-time-factor number meaningless.
//
//  Wire protocol
//    stdin   4-byte big-endian header length (0 means shut down), then that
//            many bytes of JSON:
//              {"bytes": N, "language": "tl"|"auto"|null, "prompt": string|null}
//            followed by N bytes of PCM16LE mono 16 kHz.
//    stdout  newline-delimited JSON, one object per request, plus a single
//            {"type":"ready"} once the model is loaded.
//    stderr  human-readable diagnostics only; never protocol data.
//
//  Language travels with each request rather than being fixed at launch. The
//  orchestrator supports one session per language against a shared model, so a
//  startup-only setting would silently transcribe every session in whatever
//  the first one asked for.

import Foundation
import WhisperKit

// MARK: - stdio helpers

private let stdoutLock = NSLock()

/// Writes one NDJSON line to stdout and flushes. Locked so concurrent
/// completions can never interleave halves of two lines.
func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          var line = String(data: data, encoding: .utf8)
    else { return }
    line += "\n"
    stdoutLock.lock()
    FileHandle.standardOutput.write(Data(line.utf8))
    stdoutLock.unlock()
}

func note(_ message: String) {
    FileHandle.standardError.write(Data("[asrd] \(message)\n".utf8))
}

/// Reads exactly `count` bytes, or returns nil at clean end-of-stream.
func readExactly(_ count: Int) -> Data? {
    guard count > 0 else { return Data() }
    var buffer = Data()
    buffer.reserveCapacity(count)
    while buffer.count < count {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: count - buffer.count),
              !chunk.isEmpty
        else { return nil }
        buffer.append(chunk)
    }
    return buffer
}

/// PCM16LE bytes to normalised Float32 samples.
func pcm16ToFloat(_ data: Data) -> [Float] {
    let sampleCount = data.count / 2
    guard sampleCount > 0 else { return [] }
    var samples = [Float](repeating: 0, count: sampleCount)
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        for i in 0..<sampleCount {
            let lo = UInt16(raw[i * 2])
            let hi = UInt16(raw[i * 2 + 1])
            let sample = Int16(bitPattern: lo | (hi << 8))
            samples[i] = Float(sample) / 32768.0
        }
    }
    return samples
}

func argument(_ name: String, default fallback: String? = nil) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count else { return fallback }
    return args[index + 1]
}

// MARK: - Entry point

@main
struct ASRD {
    static let sampleRate = 16_000

    static func main() async {
        let model = argument("model", default: "openai_whisper-large-v3-v20240930_turbo")!
        let language = argument("language", default: "tl")!
        let downloadBase = argument("download-base")
        let verbose = CommandLine.arguments.contains("--verbose")

        if verbose {
            // Route WhisperKit's own diagnostics to stderr; stdout is protocol-only.
            Logging.shared.loggingCallback = { message in
                FileHandle.standardError.write(Data("[whisperkit] \(message)\n".utf8))
            }
            Logging.shared.logLevel = .debug
        }

        note("loading model \(model) (language=\(language))")
        let loadStarted = Date()

        let whisperKit: WhisperKit
        do {
            let config = WhisperKitConfig(
                model: model,
                downloadBase: downloadBase.map { URL(fileURLWithPath: $0) },
                verbose: verbose,
                logLevel: verbose ? .debug : .none,
                prewarm: true,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
        } catch {
            emit(["type": "error", "code": "model_load_failed", "message": "\(error)"])
            note("model load failed: \(error)")
            exit(1)
        }

        let loadMs = Int(Date().timeIntervalSince(loadStarted) * 1000)
        note("model ready in \(loadMs) ms")
        emit(["type": "ready", "model": model, "language": language, "load_ms": loadMs])

        // Plan section 7: greedy, temperature 0, no fallback ladder, forced
        // language, and no conditioning on previous text (promptTokens left nil)
        // because it risks hallucination loops when streaming.
        var baseOptions = DecodingOptions()
        baseOptions.verbose = verbose
        baseOptions.task = .transcribe
        baseOptions.temperature = 0.0
        // Section 7 asks for temperature 0 with the fallback ladder reserved for
        // offline cleanup. Taken literally (fallbackCount 0) that is a silent
        // data-loss bug: WhisperKit's firstTokenLogProbThreshold discards any
        // window whose first token looks improbable, and with no fallback left
        // the whole window returns empty rather than being retried. Removing the
        // threshold instead is worse -- it lets repetition loops through. So keep
        // the quality gates and give them somewhere to fall back to.
        baseOptions.temperatureFallbackCount = Int(argument("fallbacks", default: "2")!) ?? 2
        baseOptions.temperatureIncrementOnFallback = 0.2
        baseOptions.usePrefillPrompt = !CommandLine.arguments.contains("--no-prefill")
        baseOptions.skipSpecialTokens = true
        baseOptions.withoutTimestamps = CommandLine.arguments.contains("--without-timestamps")
        baseOptions.wordTimestamps = !CommandLine.arguments.contains("--no-word-timestamps")
        let args = CommandLine.arguments
        if args.contains("--no-thresholds") || args.contains("--no-nospeech") {
            baseOptions.noSpeechThreshold = nil
        }
        if args.contains("--no-thresholds") || args.contains("--no-logprob") {
            baseOptions.logProbThreshold = nil
        }
        if args.contains("--no-thresholds") || args.contains("--no-firsttoken") {
            baseOptions.firstTokenLogProbThreshold = nil
        }
        if args.contains("--no-thresholds") || args.contains("--no-compression") {
            baseOptions.compressionRatioThreshold = nil
        }
        baseOptions.chunkingStrategy = nil

        var sequence = 0
        while true {
            guard let lengthBytes = readExactly(4) else {
                note("stdin closed; exiting")
                break
            }
            var headerLength: UInt32 = 0
            for byte in lengthBytes {
                headerLength = (headerLength << 8) | UInt32(byte)
            }
            if headerLength == 0 {
                note("shutdown requested")
                break
            }
            guard let headerData = readExactly(Int(headerLength)),
                  let header = (try? JSONSerialization.jsonObject(with: headerData))
                      as? [String: Any]
            else {
                note("unreadable request header; exiting")
                break
            }
            let byteCount = header["bytes"] as? Int ?? 0
            guard let payload = readExactly(byteCount) else {
                note("truncated payload; exiting")
                break
            }

            var options = baseOptions
            let requested = (header["language"] as? String) ?? language
            if requested == "auto" {
                // Section 2 warns this resolves Taglish to English and starts
                // translating. Offered, never defaulted.
                options.language = nil
                options.detectLanguage = true
            } else {
                options.language = requested
                options.detectLanguage = false
            }
            if let prompt = header["prompt"] as? String, !prompt.isEmpty,
               let promptTokens = whisperKit.tokenizer?.encode(text: " " + prompt) {
                options.promptTokens = promptTokens
                options.usePrefillPrompt = true
            }

            sequence += 1
            let samples = pcm16ToFloat(payload)
            let audioMs = Int(Double(samples.count) / Double(sampleRate) * 1000)
            let started = Date()

            do {
                let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
                let inferMs = Int(Date().timeIntervalSince(started) * 1000)

                var words: [[String: Any]] = []
                for result in results {
                    for segment in result.segments {
                        if let timings = segment.words {
                            for word in timings {
                                words.append([
                                    "text": word.word,
                                    "start_ms": Int(word.start * 1000),
                                    "end_ms": Int(word.end * 1000),
                                ])
                            }
                        } else {
                            words.append([
                                "text": segment.text,
                                "start_ms": Int(segment.start * 1000),
                                "end_ms": Int(segment.end * 1000),
                            ])
                        }
                    }
                }

                let combined: String = results.map { $0.text }.joined()
                emit([
                    "type": "result",
                    "seq": sequence,
                    "language": results.first?.language ?? requested,
                    "text": combined,
                    "words": words,
                    "audio_ms": audioMs,
                    "infer_ms": inferMs,
                ])
            } catch {
                emit([
                    "type": "error",
                    "seq": sequence,
                    "code": "transcribe_failed",
                    "message": "\(error)",
                ])
                note("transcribe failed on seq \(sequence): \(error)")
            }
        }
    }
}
