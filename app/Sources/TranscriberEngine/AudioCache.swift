import AVFoundation
import Foundation
import TranscriberCore

/// The 16 kHz mono working copy of a recording.
///
/// Why a second file at all: inference wants 16 kHz mono Float, the archive is
/// AAC at the hardware rate, and decoding AAC on every hop or every
/// re-transcription is wasted work. Why on disk rather than in memory: two
/// hours at 16 kHz Float is 460 MB resident, which on a 16 GB machine already
/// holding a 1.6 GB model is the difference between working and swapping.
///
/// The file is a plain 16-bit WAV, so it is also playable and inspectable when
/// something goes wrong, and it is disposable -- deleted once a recording is
/// transcribed and diarized, regenerated from the archive if the user ever
/// re-runs either.
public enum AudioCache {

    public static func directory(under support: URL) -> URL {
        let url = support.appendingPathComponent("Cache/PCM", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func url(for id: UUID, under support: URL) -> URL {
        directory(under: support).appendingPathComponent("\(id.uuidString).wav")
    }

    public static func discard(_ id: UUID, under support: URL) {
        try? FileManager.default.removeItem(at: url(for: id, under: support))
    }

    /// The working copy for one lane of a recording.
    public static func url(for id: UUID, lane: CaptureLane, under support: URL) -> URL {
        directory(under: support)
            .appendingPathComponent("\(id.uuidString)-\(lane.rawValue).wav")
    }

    /// The lane copy that belongs beside an existing working copy.
    ///
    /// Derived from the path the job already carries rather than rebuilt from
    /// the support directory, so a job pointed at a different location -- the
    /// command line tool, a test -- keeps its lanes with it.
    public static func url(besides cacheURL: URL, lane: CaptureLane) -> URL {
        let base = cacheURL.deletingPathExtension().lastPathComponent
        return cacheURL.deletingLastPathComponent()
            .appendingPathComponent("\(base)-\(lane.rawValue).wav")
    }

    /// Decodes any AVFoundation-readable file to the 16 kHz mono working copy.
    ///
    /// Streamed through `AVAssetReader` rather than loaded: a 90-minute MOV
    /// stays a few megabytes of buffers no matter how large the source is.
    ///
    /// - Parameter channel: which channel of a multi-channel source to take,
    ///   or nil to mix everything down. A two-lane recording is one stereo
    ///   file whose channels are the room and the call, and mixing them here
    ///   would throw away the separation the recording was made to keep.
    public static func build(from source: URL, to destination: URL,
                             channel: Int? = nil,
                             progress: (@Sendable (Double) -> Void)? = nil) async throws -> Int {
        try await build(from: source, to: destination, channel: channel,
                        progress: progress, disk: .system)
    }

    static func build(from source: URL, to destination: URL, channel: Int?,
                      progress: (@Sendable (Double) -> Void)?,
                      disk: DiskSpace) async throws -> Int {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw EngineError.audioUnreadable("no audio track in \(source.lastPathComponent)")
        }
        let duration = try await asset.load(.duration)
        let totalSeconds = max(0.001, CMTimeGetSeconds(duration))

        // Asking for one channel makes AVFoundation mix them; asking for the
        // source's own count keeps them apart so one can be picked out below.
        let sourceChannels = channel == nil
            ? 1
            : Int(try await track.load(.formatDescriptions).first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?
                    .pointee.mChannelsPerFrame }
                .map(Int.init) ?? 1)
        let wanted = channel.flatMap { $0 < sourceChannels ? $0 : nil }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Audio.sampleRate,
            AVNumberOfChannelsKey: wanted == nil ? 1 : sourceChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else {
            throw EngineError.audioUnreadable("cannot decode \(source.lastPathComponent)")
        }
        reader.add(output)

        let writer = try WavWriter(url: destination, disk: disk)
        defer { writer.close() }

        // Reported in whole percent, not per buffer. A 3h51m file yields 27,091
        // sample buffers -- decoding them takes ~3 s, and telling anyone about
        // each one costs orders of magnitude more than the decode.
        var lastReported = -1.0

        guard reader.startReading() else {
            throw EngineError.audioUnreadable(reader.error?.localizedDescription ?? "reader failed")
        }

        // A writer that stopped -- a full disk -- ends the decode: the copy
        // would otherwise come back short and look complete.
        while reader.status == .reading, writer.failure == nil {
            guard let sample = output.copyNextSampleBuffer() else { break }
            if let block = CMSampleBufferGetDataBuffer(sample) {
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                               totalLengthOut: &length,
                                               dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                   let pointer, length > 0 {
                    if let wanted, sourceChannels > 1 {
                        writer.write(Self.channel(wanted, of: pointer, bytes: length,
                                                  channels: sourceChannels))
                    } else {
                        writer.write(Data(bytes: pointer, count: length))
                    }
                }
            }
            let at = CMSampleBufferGetPresentationTimeStamp(sample)
            let fraction = min(1, max(0, CMTimeGetSeconds(at) / totalSeconds))
            if fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress?(fraction)
            }
            CMSampleBufferInvalidate(sample)
        }

        if let failure = writer.failure {
            reader.cancelReading()
            throw EngineError.cannotSaveAudio(failure.localizedDescription)
        }
        if reader.status == .failed {
            throw EngineError.audioUnreadable(reader.error?.localizedDescription ?? "decode failed")
        }
        return writer.durationMs
    }

    /// One channel out of interleaved 16-bit PCM.
    private static func channel(_ index: Int, of pointer: UnsafeMutablePointer<Int8>,
                                bytes: Int, channels: Int) -> Data {
        let frames = bytes / (MemoryLayout<Int16>.size * channels)
        var out = Data(count: frames * MemoryLayout<Int16>.size)
        pointer.withMemoryRebound(to: Int16.self, capacity: frames * channels) { samples in
            out.withUnsafeMutableBytes { raw in
                let target = raw.bindMemory(to: Int16.self)
                for frame in 0..<frames {
                    target[frame] = samples[frame * channels + index]
                }
            }
        }
        return out
    }
}

/// Appends 16 kHz mono PCM16 to a WAV file.
///
/// The RIFF header is rewritten on close, so a session killed mid-recording
/// leaves a file that can be repaired rather than one that is simply lost.
///
/// A write that fails -- a full disk, a volume that went away -- stops the
/// writer instead of crashing the app. The legacy `FileHandle.write(_:)` raises
/// an Objective-C exception on any error, which Swift cannot catch: measured,
/// filling a disk under it terminated the process with
/// `NSFileHandleOperationException: No space left on device` (FINDINGS §14).
/// Everything written before the failure stays a clean, readable prefix, and
/// nothing after it is attempted, because a write that resumed once space came
/// back would put the rest of the audio at the wrong time.
public final class WavWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    /// Live capture must never wait for a disk write on the main actor. The
    /// offline builder still uses `write` directly so it naturally applies
    /// back-pressure instead of queueing an entire imported file in memory.
    private let liveWriteQueue = DispatchQueue(label: "transcriber.live-pcm",
                                               qos: .utility)
    private let disk: DiskSpace
    private var byteCount = 0
    private var bytesSinceDiskCheck = 0
    private var closed = false
    private var _failure: (any Error)?
    private var _onFailure: (@Sendable (any Error) -> Void)?
    public let url: URL

    /// Why the working copy could not be opened.
    ///
    /// Worth a real error rather than a nil: this failure only ever shows up on
    /// someone else's Mac, and `createFile` returns a bare `Bool` while the
    /// `FileHandle` error was being swallowed by `try?`. The result was a
    /// message that said "cannot open the working copy for writing" and named
    /// neither the path nor the reason -- undiagnosable remotely, which is the
    /// only place it happens.
    public struct CannotWrite: LocalizedError {
        public let url: URL
        public let reason: String
        /// Free space on the volume, when it could be read. A full disk is the
        /// most common cause and the least obvious from the message.
        public let availableBytes: Int64?

        public var errorDescription: String? {
            var text = "Could not open the working copy for writing.\n\(url.path)\n\(reason)"
            if let availableBytes {
                let free = ByteCountFormatter.string(fromByteCount: availableBytes,
                                                     countStyle: .file)
                text += "\n\(free) free on this volume."
            }
            return text
        }
    }

    public convenience init(url: URL) throws {
        try self.init(url: url, disk: .system)
    }

    init(url: URL, disk: DiskSpace) throws {
        self.url = url
        self.disk = disk
        let directory = url.deletingLastPathComponent()

        func fail(_ reason: String) -> CannotWrite {
            CannotWrite(url: url, reason: reason, availableBytes: disk.available(url))
        }

        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        } catch {
            throw fail("The folder could not be created: \(error.localizedDescription)")
        }
        // Refused here rather than sealed a few seconds into the recording:
        // below the reserve there is nothing worth starting.
        if disk.shortfall(at: url) != nil {
            throw fail("The disk is almost full. Free some space, then try again.")
        }
        guard FileManager.default.createFile(atPath: url.path,
                                             contents: Self.header(dataBytes: 0)) else {
            throw fail("The file could not be created. The folder may be read-only, "
                     + "or the disk may be full.")
        }
        do {
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        } catch {
            throw fail(error.localizedDescription)
        }
    }

    public var durationMs: Int { Audio.bytesToMs(lock.withLock { byteCount }) }

    /// Why writing stopped, if it has. Set once; nothing is written after it.
    public var failure: (any Error)? { lock.withLock { _failure } }

    /// Called once, from whichever thread was writing, when writing stops
    /// early. The recording carries on -- the live transcript does not need
    /// this file -- so this is how the user gets told.
    public var onFailure: (@Sendable (any Error) -> Void)? {
        get { lock.withLock { _onFailure } }
        set { lock.withLock { _onFailure = newValue } }
    }

    public func write(_ pcm: Data) {
        let failed: (error: any Error, report: (@Sendable (any Error) -> Void)?)? = lock.withLock {
            guard !closed, _failure == nil, !pcm.isEmpty else { return nil }
            bytesSinceDiskCheck += pcm.count
            if Audio.bytesToMs(bytesSinceDiskCheck) >= DiskSpace.checkIntervalMs {
                bytesSinceDiskCheck = 0
                if let free = disk.shortfall(at: url) {
                    _failure = DiskSpace.Low(availableBytes: free)
                    return (_failure!, _onFailure)
                }
            }
            do {
                try handle.write(contentsOf: pcm)
                byteCount += pcm.count
                return nil
            } catch {
                _failure = error
                return (error, _onFailure)
            }
        }
        if let failed { failed.report?(failed.error) }
    }

    /// Enqueues a small live-capture buffer for ordered background writing.
    /// `close()` drains this queue before rewriting the WAV header, so callers
    /// do not need to keep track of individual writes and no tail audio is
    /// lost when a recording stops.
    public func writeAsync(_ pcm: Data) {
        liveWriteQueue.async { [self] in write(pcm) }
    }

    public func close() {
        liveWriteQueue.sync {
            lock.withLock {
                guard !closed else { return }
                closed = true
                // Overwrites the 44 bytes already there, so it needs no new
                // space -- but on a copy-on-write volume even that can fail.
                // `MappedPCM` reads a header that still says zero as "all of
                // the file", so a failure here costs nothing that matters.
                try? handle.seek(toOffset: 0)
                try? handle.write(contentsOf: Self.header(dataBytes: byteCount))
                try? handle.close()
            }
        }
    }

    static func header(dataBytes: Int) -> Data {
        let channels: UInt16 = 1, bits: UInt16 = 16
        let rate = UInt32(Audio.sampleRate)
        let blockAlign = channels * bits / 8

        var data = Data("RIFF".utf8)
        data.append(littleEndian: UInt32(36 + dataBytes))
        data.append(Data("WAVEfmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))         // PCM
        data.append(littleEndian: channels)
        data.append(littleEndian: rate)
        data.append(littleEndian: rate * UInt32(blockAlign))
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bits)
        data.append(Data("data".utf8))
        data.append(littleEndian: UInt32(dataBytes))
        return data
    }
}

/// A memory-mapped 16 kHz mono WAV, read in slices.
///
/// `mappedIfSafe` means the pages are the file's own -- resident set grows only
/// with what is actually touched, and the kernel evicts the rest under
/// pressure. That is what lets a two-hour recording be diarized on a 16 GB
/// machine at all.
public struct MappedPCM: @unchecked Sendable {
    private let data: Data
    private let offset: Int
    public let sampleCount: Int

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8) else {
            throw EngineError.audioUnreadable("\(url.lastPathComponent) is not a WAV")
        }
        // Walk the chunk list rather than assuming 44: writers insert LIST and
        // fact chunks, and a fixed offset would read the metadata as audio.
        var cursor = 12
        var found: (offset: Int, length: Int)?
        while cursor + 8 <= data.count {
            let id = data.subdata(in: cursor..<(cursor + 4))
            let size = Int(data.subdata(in: (cursor + 4)..<(cursor + 8))
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            if id == Data("data".utf8) {
                let remaining = data.count - cursor - 8
                // Trust the file over its own header. A session killed
                // mid-recording never got its header rewritten and still claims
                // zero bytes, while the audio is all sitting right there -- and
                // recovering it is the entire reason the header is written last.
                let declared = (size == 0 || size > remaining) ? remaining : size
                found = (cursor + 8, declared)
                break
            }
            cursor += 8 + size + (size % 2)
        }
        guard let found, found.length > 0 else {
            throw EngineError.audioUnreadable("\(url.lastPathComponent) has no audio")
        }
        self.data = data
        self.offset = found.offset
        self.sampleCount = found.length / 2
    }

    public var durationMs: Int { sampleCount * 1000 / Audio.sampleRate }

    /// Normalized floats for `range`, clamped to what exists.
    public func floats(_ range: Range<Int>) -> [Float] {
        let low = max(0, min(range.lowerBound, sampleCount))
        let high = max(low, min(range.upperBound, sampleCount))
        guard high > low else { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            let base = raw.baseAddress!.advanced(by: offset)
            return (low..<high).map { index in
                Float(base.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
                    .littleEndian) / 32768.0
            }
        }
    }

}

extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

extension MappedPCM: PCMSource {}
