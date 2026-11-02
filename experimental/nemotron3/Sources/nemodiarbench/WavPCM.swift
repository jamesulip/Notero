import Foundation
import TranscriberCore

/// A 16 kHz mono 16-bit PCM WAV, memory-mapped. The same reading as the app's
/// `MappedPCM`, which lives in `TranscriberEngine` and is not linked here.
struct WavPCM: PCMSource, @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case unreadable(String)
        var description: String { if case let .unreadable(text) = self { return text }; return "" }
    }

    private let data: Data
    private let offset: Int
    let sampleCount: Int

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8) else {
            throw Failure.unreadable("\(url.lastPathComponent) is not a WAV")
        }
        func u32(_ at: Int) -> Int {
            Int(data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
        }
        func u16(_ at: Int) -> Int {
            Int(data.subdata(in: at..<(at + 2)).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian })
        }
        var cursor = 12
        var found: (offset: Int, length: Int)?
        var format: (channels: Int, rate: Int, bits: Int)?
        while cursor + 8 <= data.count {
            let id = data.subdata(in: cursor..<(cursor + 4))
            let size = u32(cursor + 4)
            if id == Data("fmt ".utf8) {
                format = (u16(cursor + 10), u32(cursor + 12), u16(cursor + 22))
            } else if id == Data("data".utf8) {
                found = (cursor + 8, min(size, data.count - cursor - 8))
                break
            }
            cursor += 8 + size + (size % 2)
        }
        guard let format, format == (1, Audio.sampleRate, 16) else {
            throw Failure.unreadable("\(url.lastPathComponent) is not 16 kHz mono 16-bit")
        }
        guard let found, found.length > 0 else {
            throw Failure.unreadable("\(url.lastPathComponent) has no audio")
        }
        self.data = data
        self.offset = found.offset
        self.sampleCount = found.length / 2
    }

    func floats(_ range: Range<Int>) -> [Float] {
        let low = max(0, min(range.lowerBound, sampleCount))
        let high = max(low, min(range.upperBound, sampleCount))
        guard high > low else { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            let base = raw.baseAddress!.advanced(by: offset)
            return (low..<high).map { index in
                Float(base.loadUnaligned(fromByteOffset: index * 2, as: Int16.self).littleEndian) / 32768.0
            }
        }
    }
}
