import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The 4 GiB edge of the working copy's RIFF header, and odd byte counts.
///
/// 16 kHz PCM16 is 115 MB an hour, so six hours is 690 MB and the limit is
/// about 37 hours -- a recording nobody means to make, and exactly the one a
/// Mac left recording over a weekend makes. `UInt32(36 + dataBytes)` is a trap
/// there, not a wrong number: the app terminates inside `close()`, at Stop,
/// with the whole recording written and the header never finished.
final class WavLimitTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcriber-wav-limit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func word(_ header: Data, at offset: Int) -> UInt32 {
        header.subdata(in: offset..<(offset + 4))
            .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }

    func testTheHeaderOfAFileBeyondFourGigabytesIsMarkedUnknownNotTrapped() {
        for bytes in [Int(UInt32.max) - 35, Int(UInt32.max), 5_000_000_000, Int(Int32.max) * 4] {
            let header = WavWriter.header(dataBytes: bytes)
            XCTAssertEqual(header.count, 44)
            XCTAssertEqual(word(header, at: 4), UInt32.max, "RIFF size for \(bytes)")
            XCTAssertEqual(word(header, at: 40), UInt32.max, "data size for \(bytes)")
        }
    }

    func testTheHeaderBelowTheLimitIsExact() {
        let limit = Int(UInt32.max) - 36
        let atLimit = WavWriter.header(dataBytes: limit)
        XCTAssertEqual(word(atLimit, at: 4), UInt32.max)
        XCTAssertEqual(word(atLimit, at: 40), UInt32(limit))
        let small = WavWriter.header(dataBytes: 690_000_000)   // six hours
        XCTAssertEqual(word(small, at: 4), 690_000_036)
        XCTAssertEqual(word(small, at: 40), 690_000_000)
    }

    func testAFileLargerThanItsHeaderCanSayIsReadInFull() throws {
        // A sparse 4.5 GB file: the header says "unknown" and the audio is
        // everything after it. Nothing is written to disk but the header.
        let url = scratch.appendingPathComponent("huge.wav")
        let total: UInt64 = 4_500_000_000
        FileManager.default.createFile(atPath: url.path,
                                       contents: WavWriter.header(dataBytes: Int(total)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 44 + total)
        try handle.close()

        let mapped = try MappedPCM(contentsOf: url)
        XCTAssertEqual(mapped.sampleCount, Int(total) / 2,
                       "the 32-bit size field must not cap what is read")
    }

    func testAnOddByteCountKeepsTheWholeSamples() throws {
        // A write that was cut part way through a sample leaves one stray byte.
        let url = scratch.appendingPathComponent("odd.wav")
        var data = WavWriter.header(dataBytes: 0)
        data.append(contentsOf: [0x00, 0x10, 0x00, 0x20, 0x07])   // 2 samples and a byte
        try data.write(to: url)
        let mapped = try MappedPCM(contentsOf: url)
        XCTAssertEqual(mapped.sampleCount, 2)
        XCTAssertEqual(mapped.floats(0..<5).count, 2)

        // The same with a header that was finished and says 5.
        var finished = WavWriter.header(dataBytes: 5)
        finished.append(contentsOf: [0x00, 0x10, 0x00, 0x20, 0x07])
        let other = scratch.appendingPathComponent("odd-finished.wav")
        try finished.write(to: other)
        XCTAssertEqual(try MappedPCM(contentsOf: other).sampleCount, 2)
    }
}
