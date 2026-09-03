import Foundation

/// Selectable models.
///
/// The names in WhisperKit's zoo are actively misleading, so every entry
/// carries what the model actually *is* rather than what it is called.
public struct ModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    public let approxMB: Int
    public let multilingual: Bool
    public let recommended: Bool

    public var sizeLabel: String {
        approxMB >= 1024
            ? String(format: "%.1f GB", Double(approxMB) / 1024)
            : "\(approxMB) MB"
    }
}

public enum ModelCatalogue {
    public static let all: [ModelOption] = [
        ModelOption(
            id: "openai_whisper-large-v3-v20240930_turbo",
            label: "large-v3-turbo",
            detail: "OpenAI's turbo model: large-v3 with the decoder pruned from "
                  + "32 layers to 4. Same encoder, ~809M parameters.",
            approxMB: 1638, multilingual: true, recommended: true),
        ModelOption(
            id: "openai_whisper-large-v3-v20240930_626MB",
            label: "large-v3-turbo (quantized)",
            detail: "The same turbo model, quantized. Faster and lighter; the "
                  + "accuracy cost on Tagalog is unmeasured.",
            approxMB: 626, multilingual: true, recommended: false),
        ModelOption(
            id: "openai_whisper-large-v3_turbo",
            label: "large-v3 (full, not turbo)",
            detail: "Full 1.5B large-v3. The `_turbo` suffix here is a WhisperKit "
                  + "compute variant, NOT the turbo model — its decoder is 5.3x "
                  + "heavier. Most accurate, far slower per hop.",
            approxMB: 3195, multilingual: true, recommended: false),
        ModelOption(
            id: "openai_whisper-medium",
            label: "medium",
            detail: "Multilingual and much lighter. Expect a real accuracy drop "
                  + "on Taglish.",
            approxMB: 1530, multilingual: true, recommended: false),
        ModelOption(
            id: "openai_whisper-small",
            label: "small",
            detail: "Fastest multilingual option. Useful for checking the "
                  + "pipeline, not for transcripts you intend to keep.",
            approxMB: 483, multilingual: true, recommended: false),
        ModelOption(
            id: "distil-whisper_distil-large-v3_turbo",
            label: "distil-large-v3 (English only)",
            detail: "English-only. On Tagalog it will translate rather than "
                  + "transcribe.",
            approxMB: 600, multilingual: false, recommended: false),
    ]

    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    public static func option(_ id: String) -> ModelOption? {
        all.first { $0.id == id }
    }

    /// WhisperKit lays models out under <base>/models/<repo>/<model-id>/.
    public static func directory(for id: String, modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(id)",
                                               isDirectory: true)
    }

    /// The decoder is the last file WhisperKit writes, so its presence means
    /// the download finished rather than merely started.
    public static func isDownloaded(_ id: String, modelsDirectory: URL) -> Bool {
        let path = directory(for: id, modelsDirectory: modelsDirectory)
            .appendingPathComponent("TextDecoder.mlmodelc")
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Bytes on disk for a downloaded model, or nil when it is not there.
    public static func sizeOnDisk(_ id: String, modelsDirectory: URL) -> Int64? {
        let root = directory(for: id, modelsDirectory: modelsDirectory)
        guard FileManager.default.fileExists(atPath: root.path),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

public struct LanguageOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let note: String
    public let isAutoDetect: Bool
}

/// Tagalog is forced by default. Auto-detect on Taglish resolves elsewhere and
/// the model starts *translating* -- on a Taglish fixture it reported
/// Indonesian, because it hears the voice rather than reading the script. So it
/// is offered, listed last, and flagged.
public enum LanguageCatalogue {
    public static let all: [LanguageOption] = [
        LanguageOption(id: "tl", label: "Tagalog / Taglish",
                       note: "Forced Tagalog. Code-switched English is transcribed as spoken.",
                       isAutoDetect: false),
        LanguageOption(id: "en", label: "English", note: "", isAutoDetect: false),
        LanguageOption(id: "id", label: "Indonesian", note: "", isAutoDetect: false),
        LanguageOption(id: "ms", label: "Malay", note: "", isAutoDetect: false),
        LanguageOption(id: "zh", label: "Chinese", note: "", isAutoDetect: false),
        LanguageOption(id: "ja", label: "Japanese", note: "", isAutoDetect: false),
        LanguageOption(id: "ko", label: "Korean", note: "", isAutoDetect: false),
        LanguageOption(id: "es", label: "Spanish", note: "", isAutoDetect: false),
        LanguageOption(id: "fr", label: "French", note: "", isAutoDetect: false),
        LanguageOption(id: "de", label: "German", note: "", isAutoDetect: false),
        LanguageOption(id: "pt", label: "Portuguese", note: "", isAutoDetect: false),
        LanguageOption(id: "ar", label: "Arabic", note: "", isAutoDetect: false),
        LanguageOption(id: "hi", label: "Hindi", note: "", isAutoDetect: false),
        LanguageOption(id: "vi", label: "Vietnamese", note: "", isAutoDetect: false),
        LanguageOption(id: "th", label: "Thai", note: "", isAutoDetect: false),
        LanguageOption(id: "auto", label: "Auto-detect",
                       note: "Not recommended for Taglish: the decoder picks a "
                           + "language per window and may translate instead of "
                           + "transcribe.",
                       isAutoDetect: true),
    ]

    public static let defaultLanguage = "tl"

    public static func option(_ id: String) -> LanguageOption? {
        all.first { $0.id == id }
    }
}

/// The three choices offered in Settings.
///
/// A tier is a *promise about speed*, not a model name -- which is the point.
/// Benchmarking on this machine decides which id sits behind each tier, and the
/// UI never has to mention `openai_whisper-large-v3-v20240930_turbo` to anyone.
public enum ModelTier: String, CaseIterable, Identifiable, Sendable, Codable {
    case fast, balanced, accurate

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }

    public var summary: String {
        switch self {
        case .fast:
            return "Quantized turbo. Lowest latency and the smallest memory "
                 + "footprint; some accuracy given up on Taglish."
        case .balanced:
            return "large-v3-turbo. The default: full large-v3 encoder with a "
                 + "4-layer decoder, which is what keeps live transcription real-time."
        case .accurate:
            return "Full large-v3. Best transcript, roughly 5x the decode cost "
                 + "per window — meant for re-transcribing a finished recording, "
                 + "not for the live path."
        }
    }

    /// Default mapping. Overridden per-machine once the benchmark has run.
    public var defaultModelId: String {
        switch self {
        case .fast: return "openai_whisper-large-v3-v20240930_626MB"
        case .balanced: return ModelCatalogue.defaultModel
        case .accurate: return "openai_whisper-large-v3_turbo"
        }
    }

    /// Whether this tier is sane to run on the live path on an M2 Pro.
    ///
    /// `accurate` is not: a 15 s window costs multiples of the 1.5 s hop, so
    /// every hop would be dropped and the commit policy would never see two
    /// consecutive passes.
    public var suitableForLive: Bool { self != .accurate }
}
