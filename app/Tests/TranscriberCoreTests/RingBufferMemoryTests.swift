import Foundation
import XCTest
@testable import TranscriberCore

/// FINDING (audio agent): `Data.removeFirst` followed by `Data.append`, the ring's
/// own pattern, never frees the dead prefix. Measured: the ring grew by the whole
/// PCM rate, 1.8 MB/min = 110 MB/h, without bound, in the live decoder.
/// Fails on RingBuffer.swift at f022c6e (footprint +36 MB in 20 simulated minutes),
/// passes with ringbuffer-leak-fix.patch (about 0). Drop into Tests/TranscriberCoreTests.
final class RingBufferMemoryTests: XCTestCase {
    func testTheRingDoesNotGrowWithTheLengthOfTheSession() {
        let ring = RingBuffer(contextMs: 15_000, preRollMs: 1_500)
        let chunk = Data(count: Audio.msToBytes(85))
        // Warm up past the capacity and the allocator's first growth.
        for _ in 0..<(120_000 / 85) { ring.push(chunk); if ring.totalMs % 1_530 < 85 { _ = ring.window() } }
        let before = MemoryProbe.footprintMB()
        for _ in 0..<(20 * 60_000 / 85) { ring.push(chunk); if ring.totalMs % 1_530 < 85 { _ = ring.window() } }
        let growth = MemoryProbe.footprintMB() - before
        XCTAssertLessThan(growth, 12, "20 minutes of audio grew the ring's process footprint by \(growth) MB")
        XCTAssertLessThanOrEqual(ring.durationMs, 16_500)
    }
}
