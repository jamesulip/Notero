import EngineSeams
import Foundation
@testable import Nemotron3Backend
import TranscriberCore
import XCTest

final class Nemotron3SpeakerEngineTests: XCTestCase {

    func testConformsToTheAppProtocol() {
        let engine: any SpeakerDiarizing = Nemotron3SpeakerEngine(
            modelsDirectory: URL(fileURLWithPath: "/nonexistent"))
        XCTAssertNotNil(engine)
    }

    func testDefaultsAreTheRegisteredOnes() {
        let settings = Nemotron3SpeakerEngine.Settings.standard
        XCTAssertEqual(settings.preset, "offline")
        XCTAssertEqual(settings.threshold, 0.5)
        XCTAssertEqual(settings.minDurationSeconds, 0.2)
    }

    /// Offline-first: no models on disk is an error, never a download.
    func testPrepareWithoutModelsFailsAndDoesNotCreateTheDirectory() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("n3-missing-\(UUID().uuidString)")
        let engine = Nemotron3SpeakerEngine(modelsDirectory: dir)
        do {
            try await engine.prepare(progress: nil)
            XCTFail("prepare must fail without models")
        } catch let error as EngineError {
            guard case let .backendUnavailable(message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("learnable_sil_emb.bin"), message)
        } catch {
            XCTFail("\(error)")
        }
        let available = await engine.isAvailable
        XCTAssertFalse(available)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testUnknownPresetIsRejected() async {
        var settings = Nemotron3SpeakerEngine.Settings()
        settings.preset = "no-such-preset"
        let engine = Nemotron3SpeakerEngine(modelsDirectory: URL(fileURLWithPath: "/tmp"),
                                            settings: settings)
        do {
            try await engine.prepare(progress: nil)
            XCTFail("unknown preset must fail")
        } catch {}
    }

    func testDiarizeBeforePrepareThrows() async {
        let engine = Nemotron3SpeakerEngine(modelsDirectory: URL(fileURLWithPath: "/tmp"))
        do {
            _ = try await engine.diarize(ArrayPCM([Float](repeating: 0, count: 32_000)),
                                         speechRegions: nil, mode: .accurate,
                                         expectedSpeakers: nil, progress: nil)
            XCTFail("must throw")
        } catch EngineError.modelNotLoaded {
        } catch { XCTFail("\(error)") }
    }

    /// Timestamps stay on the recording: clamped, never inverted, sorted, and
    /// overlap between two channels is kept rather than cut.
    func testSpansAreClampedSortedAndKeepOverlap() {
        let spans = Nemotron3SpeakerEngine.spans(
            from: [(1, 4.0, 6.5), (0, 0.0, 5.0), (2, 9.8, 12.0), (3, 11.0, 11.0), (0, -0.5, 0.1)],
            durationMs: 10_000)
        XCTAssertEqual(spans.map(\.speakerId), ["N1", "N1", "N2", "N3"])
        XCTAssertEqual(spans.map(\.startMs), [0, 0, 4_000, 9_800])
        XCTAssertEqual(spans.map(\.endMs), [100, 5_000, 6_500, 10_000])
        for span in spans {
            XCTAssertLessThan(span.startMs, span.endMs)
            XCTAssertGreaterThanOrEqual(span.startMs, 0)
            XCTAssertLessThanOrEqual(span.endMs, 10_000)
        }
        // N1 and N2 overlap from 4.0 to 5.0 s; both survive.
        let normalized = SegmentMerger.normalize(spans)
        XCTAssertEqual(normalized.roster.count, 3)
    }

    func testRequiredFilesForPresets() {
        XCTAssertEqual(Nemotron3SpeakerEngine.requiredFiles(for: .offline),
                       ["Nemotron3Diarizer_offline.mlmodelc", "learnable_sil_emb.bin"])
    }
}
