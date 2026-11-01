import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranscriberCore
@testable import TranscriberStore

/// A `@Query` view of the library, hosted in a window of its own, and how long it
/// takes to show what the writer saved (finding 32). This is the UI's own path:
/// the sidebar is a `@Query`, and a row held on the main context is only brought
/// up to date by a fetch.
@MainActor
private final class Observed {
    var status: TranscriptionStatus?
    var durationMs: Int?
    var warning: String?
    var rows: Int?
    var renders = 0
}

private struct LibraryProbe: View {
    @Query(sort: \StoredRecording.createdAt, order: .reverse) private var recordings: [StoredRecording]
    let observed: Observed

    var body: some View {
        let first = recordings.first
        // Reads what the real views read, so that observation is registered on it.
        observed.status = first?.status
        observed.durationMs = first?.durationMs
        observed.warning = first?.warningMessage
        observed.rows = first?.transcript?.segments?.count
        observed.renders += 1
        return Text("\(first?.status.rawValue ?? "-") \(first?.durationMs ?? 0)")
            .frame(width: 200, height: 40)
    }
}

@MainActor
final class QueryViewRefreshTests: XCTestCase {

    private var scratch: URL!
    private var container: ModelContainer!
    private var window: NSWindow?

    override func setUp() async throws {
        try await super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("query-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let schema = Schema(TranscriberSchema.models)
        container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: scratch.appendingPathComponent("t.store"))
        ])
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        container = nil
        try? FileManager.default.removeItem(at: scratch)
        try await super.tearDown()
    }

    private func host(_ observed: Observed) {
        _ = NSApplication.shared
        let view = LibraryProbe(observed: observed).modelContainer(container)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        self.window = window
    }

    /// Waits for the main actor until `condition`, up to `limit`. Returns the ms
    /// it took, or nil on a timeout.
    private func wait(limit: Double = 2_000, until condition: () -> Bool) async -> Double? {
        let started = ContinuousClock.now
        while !condition() {
            let elapsed = ContinuousClock.now - started
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            if ms > limit { return nil }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// A `@Query` that is on screen shows each save of the writer, and how soon.
    func testAQueryViewShowsWhatTheWriterSaved() async throws {
        // A window needs a window server: a headless session cannot host the view.
        try XCTSkipIf(NSScreen.screens.isEmpty, "no window server to host the view")
        let main = container.mainContext
        let id = try RecordingStore.create(kind: .recording, in: main).id
        let observed = Observed()
        host(observed)
        let rendered = await wait { observed.renders > 0 }
        XCTAssertNotNil(rendered, "the hosted view has to render, or nothing below means anything")

        let writer = TranscriptWriter(modelContainer: container)
        let cycles = ProcessInfo.processInfo.environment["NOTERO_RAW_CYCLES"].flatMap(Int.init) ?? 60
        var latencies: [Double] = []
        var missed = 0
        var immediately = 0
        for cycle in 0..<cycles {
            let ms = 2_000 + cycle
            try await writer.attachAudio(fileName: "a\(cycle).m4a", sampleRate: 48_000, durationMs: ms,
                                         waveform: nil, lanes: [.room], for: id)
            if observed.durationMs == ms { immediately += 1 }
            if let took = await wait(until: { observed.durationMs == ms }) { latencies.append(took) } else { missed += 1 }

            let status: TranscriptionStatus = cycle % 2 == 0 ? .transcribing : .completed
            try await writer.updateStatus(status, progress: 0.5, for: id)
            if let took = await wait(until: { observed.status == status }) { latencies.append(took) } else { missed += 1 }

            let warning = "w\(cycle)"
            try await writer.setWarning(warning, for: id)
            if let took = await wait(until: { observed.warning == warning }) { latencies.append(took) } else { missed += 1 }
        }
        latencies.sort()
        let median = latencies.isEmpty ? -1 : latencies[latencies.count / 2]
        print("@Query view after a writer save, \(cycles * 3) saves: shown at once \(immediately)/\(cycles) (attachAudio), "
              + "missed within 2 s \(missed), latency median \(String(format: "%.1f", median)) ms, "
              + "max \(String(format: "%.1f", latencies.last ?? -1)) ms, renders \(observed.renders)")
        XCTAssertEqual(missed, 0, "a @Query view did not show a save within 2 s")
    }
}
