import AppKit
import Foundation
import TranscriberCore
import TranscriberStore

/// The corrected transcripts of the library, written as a reference set for
/// the evaluation harness. Refer to `ReferenceSet`.
extension AppState {

    /// Asks for a folder, then writes the set into a dated subfolder of it.
    /// Reports the count and the pooled raw word error rate in an alert.
    func exportReferenceSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "The app writes a folder with a copy of each corrected recording, "
                      + "its reference text and a manifest for the evaluation harness."
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        Task {
            do {
                let result = try await writeReferenceSet(into: parent)
                alert = AppAlert(
                    title: result.count == 0 ? "No corrections to export" : "Reference set written",
                    message: result.count == 0
                        ? "No transcript has an edited line. Double-click a turn, correct it, "
                          + "and export again."
                        : "\(result.count) recording\(result.count == 1 ? "" : "s") with corrections. "
                          + "Raw model text against your corrections: "
                          + "\(String(format: "%.1f%%", result.pooledWER * 100)) WER over "
                          + "\(result.words) reference words. The folder is "
                          + "\(result.folder.lastPathComponent), and its README says how to score a "
                          + "configuration against it."
                )
                if result.count > 0 { NSWorkspace.shared.activateFileViewerSelecting([result.folder]) }
            } catch {
                alert = AppAlert(title: "The export failed", message: error.localizedDescription)
            }
        }
    }

    struct ReferenceExport {
        var folder: URL
        var count: Int
        var words: Int
        var pooledWER: Double
    }

    /// The files: `audio/`, `refs/`, `raw/`, `edits/`, `manifest.json`,
    /// `summary.md`, `README.md`. The audio is copied, not linked: the folder
    /// is meant to leave this Mac's library, to the eval directory or another
    /// machine, and a link would point at nothing there.
    func writeReferenceSet(into parent: URL) async throws -> ReferenceExport {
        let corrected = try await makeReader().correctedTranscripts()
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let folder = parent.appendingPathComponent("notero-references-\(stamp)", isDirectory: true)
        guard !corrected.isEmpty else {
            return ReferenceExport(folder: folder, count: 0, words: 0, pooledWER: 0)
        }
        let files = FileManager.default
        for sub in ["audio", "refs", "raw", "edits"] {
            try files.createDirectory(at: folder.appendingPathComponent(sub),
                                      withIntermediateDirectories: true)
        }

        var entries: [ReferenceSet.Entry] = []
        var summaries: [ReferenceSet.Summary] = []
        var words = 0
        var errors = 0.0
        for item in corrected {
            let id = item.recordingId.uuidString.lowercased()
            let ext = item.audioURL?.pathExtension ?? "m4a"
            let audioPath = "audio/\(id).\(ext)"
            if let source = item.audioURL, files.fileExists(atPath: source.path) {
                let destination = folder.appendingPathComponent(audioPath)
                try? files.removeItem(at: destination)
                try files.copyItem(at: source, to: destination)
            }
            try ReferenceSet.referenceText(item.segments)
                .write(to: folder.appendingPathComponent("refs/\(id).txt"), atomically: true, encoding: .utf8)
            try ReferenceSet.rawText(item.segments)
                .write(to: folder.appendingPathComponent("raw/\(id).txt"), atomically: true, encoding: .utf8)
            try ReferenceSet.editsTSV(item.segments)
                .write(to: folder.appendingPathComponent("edits/\(id).tsv"), atomically: true, encoding: .utf8)
            entries.append(ReferenceSet.Entry(
                id: id, audio: audioPath, ref: "refs/\(id).txt", raw: "raw/\(id).txt",
                edits: "edits/\(id).tsv", title: item.title, durationMs: item.durationMs
            ))
            let summary = ReferenceSet.summary(title: item.title, durationMs: item.durationMs,
                                               segments: item.segments)
            summaries.append(summary)
            words += summary.referenceWords
            errors += summary.rawWER * Double(summary.referenceWords)
        }
        try ReferenceSet.manifestJSON(entries).write(to: folder.appendingPathComponent("manifest.json"))
        try ReferenceSet.summaryMarkdown(summaries)
            .write(to: folder.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        try ReferenceSet.readme(count: entries.count)
            .write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return ReferenceExport(folder: folder, count: entries.count, words: words,
                               pooledWER: words > 0 ? errors / Double(words) : 0)
    }
}
