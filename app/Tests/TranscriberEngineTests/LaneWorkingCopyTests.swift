import AVFoundation
import TranscriberCore
import XCTest
@testable import TranscriberEngine

/// Getting one lane back out of a two-lane archive.
///
/// The failure this guards against is quiet: extract the wrong channel and
/// every line of the transcript is attributed to the wrong side of the
/// meeting, with nothing in the output that looks wrong.
final class LaneWorkingCopyTests: XCTestCase {

    private var scratch = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lane-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testEachChannelComesBackOnItsOwn() async throws {
        // A loud tone on the room channel, a quiet one on the call channel, at
        // different frequencies so neither could be mistaken for the other.
        let archive = scratch.appendingPathComponent("both.m4a")
        try write(archive, left: (frequency: 440, amplitude: 0.7),
                  right: (frequency: 880, amplitude: 0.1), seconds: 2)

        let room = scratch.appendingPathComponent("room.wav")
        let remote = scratch.appendingPathComponent("remote.wav")
        _ = try await AudioCache.build(from: archive, to: room, channel: 0)
        _ = try await AudioCache.build(from: archive, to: remote, channel: 1)

        let roomLevel = rms(try MappedPCM(contentsOf: room))
        let remoteLevel = rms(try MappedPCM(contentsOf: remote))

        // The amplitudes were 7:1 apart. Through AAC they will not be exactly
        // that, but the loud channel must still be clearly the loud one.
        XCTAssertGreaterThan(roomLevel, remoteLevel * 3,
                             "channel 0 should be the loud room tone")
        XCTAssertGreaterThan(remoteLevel, 0.005, "channel 1 should not be silent")
    }

    func testMixingDownIsStillTheDefault() async throws {
        // Everything recorded before two-lane capture is a mono file, and the
        // path that reads it must not change.
        let archive = scratch.appendingPathComponent("mono.m4a")
        try write(archive, left: (frequency: 440, amplitude: 0.5),
                  right: (frequency: 440, amplitude: 0.5), seconds: 1)
        let mixed = scratch.appendingPathComponent("mixed.wav")
        let ms = try await AudioCache.build(from: archive, to: mixed)
        XCTAssertEqual(ms, 1000, accuracy: 120)
        XCTAssertGreaterThan(rms(try MappedPCM(contentsOf: mixed)), 0.05)
    }

    func testAskingForAChannelThatIsNotThereMixesInstead() async throws {
        // A one-lane recording whose row wrongly claims two lanes must give
        // back the audio it has, not an empty file.
        let archive = scratch.appendingPathComponent("single.m4a")
        try write(archive, left: (frequency: 440, amplitude: 0.5),
                  right: nil, seconds: 1)
        let out = scratch.appendingPathComponent("out.wav")
        _ = try await AudioCache.build(from: archive, to: out, channel: 1)
        XCTAssertGreaterThan(rms(try MappedPCM(contentsOf: out)), 0.05)
    }

    // MARK: - Helpers

    private typealias Tone = (frequency: Double, amplitude: Float)

    private func write(_ url: URL, left: Tone, right: Tone?, seconds: Double) throws {
        let channels: AVAudioChannelCount = right == nil ? 1 : 2
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderBitRateKey: 64_000 * Int(channels),
        ], commonFormat: .pcmFormatFloat32, interleaved: false)

        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            buffer.floatChannelData![0][frame] =
                left.amplitude * Float(sin(2 * .pi * left.frequency * t))
            if let right {
                buffer.floatChannelData![1][frame] =
                    right.amplitude * Float(sin(2 * .pi * right.frequency * t))
            }
        }
        try file.write(from: buffer)
    }

    private func rms(_ pcm: MappedPCM) -> Float {
        let samples = pcm.floats(0..<pcm.sampleCount)
        guard !samples.isEmpty else { return 0 }
        let total = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (total / Float(samples.count)).squareRoot()
    }
}
