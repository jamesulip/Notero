import Foundation
import TranscriberCore

/// What the evaluation framework records about a run, read from this machine.
///
/// Local files and `sysctl` only. Nothing here touches the network: a
/// provenance lookup that needed a connection would make scoring depend on one.
public enum EvaluationProvenance {

    /// The machine, as `MachineInfo` describes it.
    public static var hardware: HardwareInfo {
        HardwareInfo(machine: MachineInfo.description, memoryGB: MemoryProbe.installedGB())
    }

    /// The source revision of a downloaded WhisperKit model.
    ///
    /// The Hugging Face downloader keeps one `<file>.metadata` per file under
    /// `<repo>/.cache/huggingface/download/<model-id>/`; its first line is the
    /// commit the file came from. All files of one download share it. When
    /// they do not (a model updated file by file), every commit is listed, so
    /// the record shows the mix rather than picking one.
    public static func modelRevision(modelId: String, modelsDirectory: URL) -> Measured<String> {
        let repo = ModelCatalogue.directory(for: modelId, modelsDirectory: modelsDirectory)
            .deletingLastPathComponent()
        let cache = repo.appendingPathComponent(".cache/huggingface/download/\(modelId)", isDirectory: true)
        return revision(inDownloadCache: cache)
    }

    /// The commit recorded in a Hugging Face download cache folder.
    public static func revision(inDownloadCache cache: URL) -> Measured<String> {
        guard let enumerator = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: nil) else {
            return .unavailable(reason: "no download metadata for \(cache.lastPathComponent)")
        }
        var commits = Set<String>()
        for case let file as URL in enumerator where file.pathExtension == "metadata" {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let first = text.split(whereSeparator: \.isNewline).first else { continue }
            let commit = first.trimmingCharacters(in: .whitespaces)
            // A git commit is 40 hex digits; anything else is not a revision.
            if commit.count == 40, commit.allSatisfy(\.isHexDigit) { commits.insert(commit) }
        }
        switch commits.count {
        case 0: return .unavailable(reason: "the download metadata for \(cache.lastPathComponent) records no commit")
        case 1: return .available(commits.first!)
        default: return .available("mixed: " + commits.sorted().joined(separator: ", "))
        }
    }
}
