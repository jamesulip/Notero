import XCTest
@testable import TranscriberCore

/// Pure, deterministic, model-free logic -- and the value it produces,
/// `trailingSilenceMs`, is what decides where segments end. It has to behave
/// identically however the audio happens to be chunked, because the capture
/// path delivers ragged batch sizes that are never a multiple of the frame.
final class VoiceActivityTests: XCTestCase {

    private let frame = EnergyVoiceActivity.frameSamples

    private func loud(_ frames: Int) -> [Float] {
        [Float](repeating: 0.5, count: frames * frame)
    }

    private func quiet(_ frames: Int) -> [Float] {
        [Float](repeating: 0.001, count: frames * frame)
    }

    func testCountsSpeechAndTrailingSilence() {
        let vad = EnergyVoiceActivity()
        vad.push(loud(3) + quiet(2))
        XCTAssertEqual(vad.current.speechMs, 3 * EnergyVoiceActivity.frameMs)
        XCTAssertEqual(vad.current.trailingSilenceMs, 2 * EnergyVoiceActivity.frameMs)
        XCTAssertEqual(vad.current.frames, 5)
    }

    func testSpeechResetsTrailingSilence() {
        let vad = EnergyVoiceActivity()
        vad.push(quiet(4) + loud(1))
        XCTAssertEqual(vad.current.trailingSilenceMs, 0)
    }

    func testRaggedChunkingMatchesOneCall() {
        // Speech then silence, delivered whole vs. in chunks that never align
        // with the 512-sample frame. The carried remainder must be scored
        // *before* newer samples, or frames are evaluated out of chronological
        // order and the two runs disagree about where the silence is.
        let samples = loud(6) + quiet(5) + loud(2) + quiet(3)

        let whole = EnergyVoiceActivity()
        whole.push(samples)

        for chunkSize in [340, 511, 513, 1_000, 4_096 + 17] {
            let chunked = EnergyVoiceActivity()
            var start = 0
            while start < samples.count {
                let end = min(start + chunkSize, samples.count)
                chunked.push(Array(samples[start..<end]))
                start = end
            }
            XCTAssertEqual(chunked.current, whole.current,
                           "chunk size \(chunkSize) diverged from a single push")
        }
    }

    func testFloatAndDataPathsAgree() {
        // The two entry points sit behind one interface; a session that falls
        // back from the neural detector mid-flight must not change semantics.
        let samples = loud(2) + quiet(3)
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-32768, min(32767, sample * 32768)))
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }

        let floats = EnergyVoiceActivity()
        floats.push(samples)
        let data = EnergyVoiceActivity()
        data.push(pcm)

        XCTAssertEqual(floats.current.speechMs, data.current.speechMs)
        XCTAssertEqual(floats.current.trailingSilenceMs, data.current.trailingSilenceMs)
        XCTAssertEqual(floats.current.frames, data.current.frames)
    }

    func testResetClearsCarriedRemainder() {
        let vad = EnergyVoiceActivity()
        vad.push(loud(1) + Array(loud(1).prefix(100)))   // leaves a partial frame
        vad.reset()
        vad.push(quiet(1))
        XCTAssertEqual(vad.current.frames, 1)
        XCTAssertEqual(vad.current.speechMs, 0)
    }
}
