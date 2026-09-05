import AVFoundation
import TranscriberCore
import XCTest
@testable import TranscriberEngine

/// The two-lane path, tested where it can be tested without a microphone, a
/// tap or a permission: the archive layout and the mix.
final class LaneCaptureTests: XCTestCase {

    private var scratch = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lanes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - The archive

    func testTwoLanesBecomeAStereoFile() throws {
        let url = scratch.appendingPathComponent("both.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000,
                                       lanes: [.room, .remote])
        writer.write([.room: constant(0.5, seconds: 0.5),
                      .remote: constant(0.25, seconds: 0.5)])
        writer.finish()

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.fileFormat.channelCount, 2)
        XCTAssertEqual(Double(readBack.length) / readBack.fileFormat.sampleRate,
                       0.5, accuracy: 0.1)
    }

    func testEachLaneKeepsItsOwnChannel() throws {
        // The failure this guards against is silent and total: swap the lanes
        // and every remote speaker is labelled as being in the room, with
        // nothing in the output to say so.
        let url = scratch.appendingPathComponent("channels.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)

        let lanes: [CaptureLane] = [.room, .remote]
        let frames = AVAudioFrameCount(480)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        // Room is loud, remote is quiet: which is which has to survive.
        for index in 0..<Int(frames) {
            buffer.floatChannelData![ArchiveChannels.channel(for: .room)][index] = 0.8
            buffer.floatChannelData![ArchiveChannels.channel(for: .remote)][index] = 0.1
        }
        try file.write(from: buffer)

        XCTAssertEqual(ArchiveChannels.channel(for: .room), 0)
        XCTAssertEqual(ArchiveChannels.channel(for: .remote), 1)
        XCTAssertEqual(ArchiveChannels.lane(atChannel: 0, of: lanes), .room)
        XCTAssertEqual(ArchiveChannels.lane(atChannel: 1, of: lanes), .remote)
        // A one-lane recording has whatever lane it has on channel 0.
        XCTAssertEqual(ArchiveChannels.lane(atChannel: 0, of: [.remote]), .remote)
    }

    func testAMissingLaneIsWrittenAsSilenceNotSkipped() throws {
        // A lane that drops out for a moment is a hole in that lane. Writing
        // fewer frames instead would shorten the whole recording and pull
        // every later timestamp earlier.
        let url = scratch.appendingPathComponent("gap.m4a")
        let writer = try ArchiveWriter(url: url, sampleRate: 48_000,
                                       lanes: [.room, .remote])
        writer.write([.room: constant(0.5, seconds: 0.4)])
        writer.finish()

        let readBack = try AVAudioFile(forReading: url)
        XCTAssertEqual(readBack.fileFormat.channelCount, 2)
        XCTAssertEqual(Double(readBack.length) / readBack.fileFormat.sampleRate,
                       0.4, accuracy: 0.1)
    }

    // MARK: - The mix

    func testMixSumsTheLanes() {
        let room = pcm([1000, -1000, 0])
        let remote = pcm([500, 500, 500])
        let mixed = AudioCapture.mix([.room: room, .remote: remote],
                                     order: [.room, .remote])
        XCTAssertEqual(samples(mixed), [1500, -500, 500])
    }

    func testMixClampsRatherThanWrapping() {
        // Two loud lanes at once. Wrapping would turn the loudest moment of a
        // meeting into a full-scale click in the opposite direction.
        let room = pcm([30_000, -30_000])
        let remote = pcm([30_000, -30_000])
        let mixed = AudioCapture.mix([.room: room, .remote: remote],
                                     order: [.room, .remote])
        XCTAssertEqual(samples(mixed), [32_767, -32_768])
    }

    func testMixOfOneLaneIsThatLaneUntouched() {
        let room = pcm([7, -7, 21])
        let mixed = AudioCapture.mix([.room: room], order: [.room])
        XCTAssertEqual(samples(mixed), [7, -7, 21])
    }

    func testMixTruncatesToTheShorterLane() {
        // The lanes come off one clock, so this should not happen -- but a
        // partial buffer at a boundary must not read past the end of one.
        let room = pcm([100, 100, 100])
        let remote = pcm([1, 1])
        let mixed = AudioCapture.mix([.room: room, .remote: remote],
                                     order: [.room, .remote])
        XCTAssertEqual(samples(mixed), [101, 101])
    }

    // MARK: - Sources

    func testEachSourceNamesItsLanes() {
        XCTAssertEqual(CaptureSource.microphone.lanes, [.room])
        XCTAssertEqual(CaptureSource.systemAudio.lanes, [.remote])
        XCTAssertEqual(CaptureSource.both.lanes, [.room, .remote])
        XCTAssertTrue(CaptureSource.both.usesMicrophone)
        XCTAssertTrue(CaptureSource.both.usesSystemAudio)
        XCTAssertFalse(CaptureSource.microphone.usesSystemAudio)
        XCTAssertFalse(CaptureSource.systemAudio.usesMicrophone)
    }

    // MARK: - Helpers

    private func constant(_ value: Float, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frames = AVAudioFrameCount(48_000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = value }
        return buffer
    }

    private func pcm(_ values: [Int16]) -> Data {
        var data = Data(capacity: values.count * 2)
        for value in values {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func samples(_ data: Data) -> [Int16] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }
}
