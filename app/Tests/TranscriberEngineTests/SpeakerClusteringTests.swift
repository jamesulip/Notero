import XCTest
import TranscriberCore
@testable import TranscriberEngine

/// The turn-clustering policy, on synthetic unit vectors.
///
/// The real embeddings come from a CoreML model that needs 200 MB of weights
/// and an audio file; the decisions made over them do not, and the decisions
/// are what went wrong in the six-person room that came back as fourteen.
final class SpeakerClusteringTests: XCTestCase {

    /// Unit vector along one axis of an 8-dimensional space. Two different axes
    /// are at cosine distance 1.0 -- unmistakably different voices.
    private func axis(_ index: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: 8)
        vector[index] = 1
        return vector
    }

    /// The same axis nudged sideways: a second turn from the same voice.
    private func near(_ index: Int, by amount: Float = 0.2) -> [Float] {
        var vector = axis(index)
        vector[(index + 1) % 8] = amount
        return TurnClusterer.normalized(vector)!
    }

    /// A unit vector in the plane of the first two axes, at an angle from
    /// axis 0. Cosine distance from axis 0 is 1 - cos(angle): 72.5° is the
    /// 0.7 same-speaker threshold, 81.4° the 0.85 consolidation limit.
    private func direction(_ degrees: Double) -> [Float] {
        var vector = [Float](repeating: 0, count: 8)
        vector[0] = Float(cos(degrees * .pi / 180))
        vector[1] = Float(sin(degrees * .pi / 180))
        return vector
    }

    func testDistinctVoicesFoundDistinctClusters() {
        var clusterer = TurnClusterer()
        let a = clusterer.assign(axis(0), durationMs: 5_000)
        let b = clusterer.assign(axis(1), durationMs: 5_000)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(clusterer.clusters.count, 2)
    }

    func testANearbyTurnJoinsTheExistingCluster() {
        var clusterer = TurnClusterer()
        let first = clusterer.assign(axis(0), durationMs: 5_000)
        let second = clusterer.assign(near(0), durationMs: 5_000)
        XCTAssertEqual(first, second)
        XCTAssertEqual(clusterer.clusters.count, 1)
    }

    func testAShortTurnNeverFoundsACluster() {
        // A two-second "sige" from a genuinely new voice still joins the
        // nearest speaker: a noisy embedding must not invent a person.
        var clusterer = TurnClusterer()
        _ = clusterer.assign(axis(0), durationMs: 5_000)
        let short = clusterer.assign(axis(1), durationMs: 1_500)
        XCTAssertEqual(short, "T1")
        XCTAssertEqual(clusterer.clusters.count, 1)
    }

    func testConsolidationMergesTheClosestPairTowardTheHeadCount() {
        var clusterer = TurnClusterer()
        for index in 0..<6 { _ = clusterer.assign(axis(index), durationMs: 20_000) }
        // A seventh cluster that is really speaker 3 heard badly: just past the
        // same-speaker threshold (distance ~0.76), but not far.
        var wobble = axis(3)
        wobble[7] = 4
        let seventh = clusterer.assign(TurnClusterer.normalized(wobble)!, durationMs: 3_000)
        XCTAssertEqual(clusterer.clusters.count, 7, "it did found a cluster")

        let aliases = clusterer.consolidate(toward: 6, withinDistance: 0.85)

        XCTAssertEqual(clusterer.clusters.count, 6)
        XCTAssertEqual(aliases[seventh], "T4", "folded into speaker 3's cluster, the heavier one")
    }

    func testConsolidationStopsAtVoicesThatAreClearlyDifferent() {
        // Six orthogonal voices and a head-count of four: nothing is within
        // reach, so nothing merges. The count is a target, not a cap.
        var clusterer = TurnClusterer()
        for index in 0..<6 { _ = clusterer.assign(axis(index), durationMs: 20_000) }

        let aliases = clusterer.consolidate(toward: 4, withinDistance: 0.85)

        XCTAssertTrue(aliases.isEmpty)
        XCTAssertEqual(clusterer.clusters.count, 6)
    }

    func testConsolidationResolvesChainsOfMerges() {
        // Three clusters in a line: A at 0°, B at 76° (0.76 from A), C at
        // 149.5° (0.72 from B, far from A). B-C is the closest pair, so B
        // absorbs the light C first; B barely moves, A then absorbs B. C's
        // alias must point at A, the survivor -- not at the retired B.
        var clusterer = TurnClusterer()
        let a = clusterer.assign(direction(0), durationMs: 50_000)
        let b = clusterer.assign(direction(76), durationMs: 40_000)
        let c = clusterer.assign(direction(149.5), durationMs: 2_500)
        XCTAssertEqual(clusterer.clusters.count, 3)

        let aliases = clusterer.consolidate(toward: 1, withinDistance: 0.85)

        XCTAssertEqual(clusterer.clusters.count, 1)
        XCTAssertEqual(aliases[b], a)
        XCTAssertEqual(aliases[c], a, "resolved through the chain, not left at \(b)")
    }

    func testNoTargetMeansNoConsolidation() {
        var clusterer = TurnClusterer()
        _ = clusterer.assign(axis(0), durationMs: 5_000)
        _ = clusterer.assign(near(0, by: 4), durationMs: 5_000)
        XCTAssertTrue(clusterer.consolidate(toward: 0, withinDistance: 0.85).isEmpty)
        XCTAssertEqual(clusterer.clusters.count, 2)
    }
}
