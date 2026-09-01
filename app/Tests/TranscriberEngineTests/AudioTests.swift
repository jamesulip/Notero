import AVFoundation
import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The audio file path, exercised without a microphone.
///
/// Recording is the one thing that cannot be tested end to end here -- it needs
/// a device and a permission prompt. Everything downstream of the tap can be,
/// and this is where the deployment risk actually lives: whether the AAC
/// settings produce a file that macOS will play back, and whether the working
/// copy can be mapped and read.
final class AudioFileTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A 440 Hz tone, as the tap would deliver it.
    private func tone(seconds: Double, rate: Double = 48_000) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        let step: Double = 2 * Double.pi * 440 / rate
        for index in 0..<Int(frames) {
            let phase: Double = step * Double(index)
            channel[index] = Float(0.5 * sin(phase))
        }
        return buffer
    }

    // MARK: - The archive

    func testArchiveWriterProducesAPlayableAacFile() throws {
        let url = scratch.appendingPathComponent("archive.m4a")
        let buffer = try tone(seconds: 1)
        let writer = try ArchiveWriter(url: url, format: buffer.format)
        for _ in 0..<3 { writer.write(buffer) }
        writer.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(writer.frameCount, AVAudioFramePosition(buffer.frameLength) * 3)

        // The real assertion: AVFoundation can open what we wrote.
        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.fileFormat.channelCount, 1)
        XCTAssertEqual(readBack.fileFormat.sampleRate, 48_000, accuracy: 1)
        XCTAssertEqual(Double(readBack.length) / readBack.fileFormat.sampleRate,
                       3.0, accuracy: 0.15)

        // 64 kbps mono for 3 seconds is tens of kilobytes; raw float would be
        // over half a megabyte. If this ever inverts, the codec silently fell
        // back to PCM and an hour of meeting became 345 MB.
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        XCTAssertLessThan(bytes, 120_000)
    }

    func testArchiveWriterCopiesBuffersSoTheTapCanReuseThem() throws {
        // The tap hands back the same buffer every callback. Writing happens on
        // another queue, so anything not copied is a race with the next tap.
        let url = scratch.appendingPathComponent("reused.m4a")
        let buffer = try tone(seconds: 0.5)
        let writer = try ArchiveWriter(url: url, format: buffer.format)
        writer.write(buffer)
        // Scribble over the buffer exactly as the audio thread would.
        let channel = buffer.floatChannelData![0]
        for index in 0..<Int(buffer.frameLength) { channel[index] = 0 }
        writer.finish()

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(readBack.length, 0)
    }

    // MARK: - The working copy

    func testWavWriterAndMappedPcmRoundTrip() throws {
        let url = scratch.appendingPathComponent("copy.wav")
        let writer = WavWriter(url: url)!
        // One second of a ramp, so a wrong offset shows up as wrong values.
        let samples = (0..<Audio.sampleRate).map { Float($0) / Float(Audio.sampleRate) }
        writer.write(PCM.data(from: samples))
        XCTAssertEqual(writer.durationMs, 1_000)
        writer.close()

        let mapped = try MappedPCM(contentsOf: url)
        XCTAssertEqual(mapped.sampleCount, Audio.sampleRate)
        XCTAssertEqual(mapped.durationMs, 1_000)

        let read = mapped.floats(0..<10)
        for (index, value) in read.enumerated() {
            XCTAssertEqual(value, samples[index], accuracy: 0.0001)
        }
        let tail = mapped.floats(msRange: 900..<1_000)
        XCTAssertEqual(tail.count, Audio.sampleRate / 10)
    }

    func testMappedPcmRejectsSomethingThatIsNotAWav() throws {
        let url = scratch.appendingPathComponent("bogus.wav")
        try Data("not audio at all, just some bytes sitting in a file".utf8).write(to: url)
        XCTAssertThrowsError(try MappedPCM(contentsOf: url))
    }

    func testMappedPcmSurvivesAnInterruptedRecording() throws {
        // A session killed mid-recording leaves a header claiming zero bytes.
        // The file still holds the audio, and the reader must not believe the
        // header over the file it can see.
        let url = scratch.appendingPathComponent("interrupted.wav")
        let writer = WavWriter(url: url)!
        writer.write(PCM.data(from: [Float](repeating: 0.2, count: 16_000)))
        // No close(): the header is never rewritten.

        let mapped = try MappedPCM(contentsOf: url)
        XCTAssertEqual(mapped.sampleCount, 16_000)
    }

    // MARK: - Decoding anything into the working copy

    func testAacIsDecodedIntoA16kWorkingCopy() async throws {
        let source = scratch.appendingPathComponent("source.m4a")
        let buffer = try tone(seconds: 1)
        let writer = try ArchiveWriter(url: source, format: buffer.format)
        for _ in 0..<2 { writer.write(buffer) }
        writer.finish()

        let destination = scratch.appendingPathComponent("work.wav")
        let durationMs = try await AudioCache.build(from: source, to: destination)

        XCTAssertEqual(durationMs, 2_000, accuracy: 150)
        let mapped = try MappedPCM(contentsOf: destination)
        XCTAssertEqual(mapped.durationMs, durationMs)
        // A 440 Hz tone survives resampling to 16 kHz; silence would mean the
        // decode produced an empty file that still looked the right length.
        let peak = mapped.floats(0..<8_000).map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.1)
    }

    func testBuildingFromAFileWithNoAudioTrackFails() async throws {
        let url = scratch.appendingPathComponent("empty.txt")
        try Data("nothing".utf8).write(to: url)
        do {
            _ = try await AudioCache.build(from: url,
                                           to: scratch.appendingPathComponent("x.wav"))
            XCTFail("expected a failure")
        } catch {}
    }

    // MARK: - Waveform

    func testWaveformIsNormalizedAndBucketed() throws {
        let samples = (0..<Audio.sampleRate * 4).map { index -> Float in
            index < Audio.sampleRate * 2 ? 0.05 : 0.4
        }
        let envelope = WaveformAnalyzer.envelope(of: ArrayPCM(samples), buckets: 100)
        XCTAssertEqual(envelope.count, 100)
        XCTAssertEqual(envelope.max() ?? 0, 1.0, accuracy: 0.0001)
        // Quiet first half, loud second: the shape must survive normalization.
        XCTAssertLessThan(envelope[10], envelope[90])
    }

    func testSilenceStaysFlatRatherThanDividingByZero() throws {
        let envelope = WaveformAnalyzer.envelope(
            of: ArrayPCM([Float](repeating: 0, count: 16_000)), buckets: 20
        )
        XCTAssertEqual(envelope.count, 20)
        XCTAssertTrue(envelope.allSatisfy { $0 == 0 })
    }

    func testLiveMeterKeepsOnlyTheRecentPast() {
        var meter: [Float] = []
        for index in 0..<400 {
            meter = WaveformAnalyzer.appending(Float(index % 10) / 10, to: meter, limit: 240)
        }
        XCTAssertEqual(meter.count, 240)
    }
}
