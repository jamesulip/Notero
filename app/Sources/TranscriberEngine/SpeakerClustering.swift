import Foundation

/// Groups turn embeddings into speakers.
///
/// Pure arithmetic, split out of `SpeakerEngine` so the policy can be tested
/// with synthetic vectors: the engine feeds it one embedding per turn, longest
/// turn first, and reads back which cluster each joined. Cluster ids are
/// `T1, T2, ...`; `SegmentMerger.normalize` renumbers them by first appearance
/// afterwards, so nothing here has to be stable across runs.
public struct TurnClusterer: Sendable {

    public struct Cluster: Sendable, Equatable {
        public let id: String
        public var centroid: [Float]
        public var weightMs: Int
    }

    /// Cosine distance (of unit vectors) under which two turns are the same
    /// voice. Matches the WeSpeaker default.
    public var sameSpeakerDistance: Float
    /// A turn shorter than this may join a cluster but never found one: a
    /// 1-2 s embedding is noisy enough that letting it open a cluster is how
    /// phantom speakers get invented.
    public var foundingTurnMs: Int

    public private(set) var clusters: [Cluster] = []

    public init(sameSpeakerDistance: Float = 0.7, foundingTurnMs: Int = 2_000) {
        self.sameSpeakerDistance = sameSpeakerDistance
        self.foundingTurnMs = foundingTurnMs
    }

    /// Places one turn. Returns the id of the cluster it joined or founded.
    /// `embedding` must already be unit length; see `normalized`.
    public mutating func assign(_ embedding: [Float], durationMs: Int) -> String {
        let nearest = clusters.indices.min {
            Self.cosineDistance(embedding, clusters[$0].centroid)
                < Self.cosineDistance(embedding, clusters[$1].centroid)
        }
        if let found = nearest,
           Self.cosineDistance(embedding, clusters[found].centroid) < sameSpeakerDistance
               || durationMs < foundingTurnMs {
            clusters[found] = Self.absorb(clusters[found], embedding, weightMs: durationMs)
            return clusters[found].id
        }
        let cluster = Cluster(id: "T\(clusters.count + 1)", centroid: embedding,
                              weightMs: durationMs)
        clusters.append(cluster)
        return cluster.id
    }

    /// Pulls the cluster count toward how many people were in the room.
    ///
    /// A target, not a cap: while there are more clusters than `target`, the
    /// two closest are merged -- but only if their centroids are within
    /// `withinDistance`. Two voices further apart than that stay two speakers
    /// however wrong the count turns out to be, because collapsing real
    /// people is worse than an extra fragment. The heavier cluster survives.
    ///
    /// Returns every retired id mapped to the id that absorbed it, resolved
    /// through chains, so callers can rewrite spans in one pass.
    @discardableResult
    public mutating func consolidate(toward target: Int, withinDistance: Float) -> [String: String] {
        var aliases: [String: String] = [:]
        guard target > 0 else { return aliases }

        while clusters.count > target {
            var best: (a: Int, b: Int, distance: Float)?
            for a in clusters.indices {
                for b in clusters.indices where b > a {
                    let distance = Self.cosineDistance(clusters[a].centroid, clusters[b].centroid)
                    if best == nil || distance < best!.distance { best = (a, b, distance) }
                }
            }
            guard let pair = best, pair.distance <= withinDistance else { break }

            let (keep, drop) = clusters[pair.a].weightMs >= clusters[pair.b].weightMs
                ? (pair.a, pair.b) : (pair.b, pair.a)
            let retired = clusters[drop]
            clusters[keep] = Self.absorb(clusters[keep], retired.centroid, weightMs: retired.weightMs)
            aliases[retired.id] = clusters[keep].id
            clusters.remove(at: drop)
        }

        // Resolve chains: T5 -> T3 -> T1 becomes T5 -> T1.
        for (from, var to) in aliases {
            var hops = 0
            while let next = aliases[to], hops < aliases.count { to = next; hops += 1 }
            aliases[from] = to
        }
        return aliases
    }

    // MARK: - Vector arithmetic

    static func absorb(_ cluster: Cluster, _ embedding: [Float], weightMs: Int) -> Cluster {
        var updated = cluster
        let total = Float(max(1, cluster.weightMs + weightMs))
        let keep = Float(cluster.weightMs) / total
        let add = Float(weightMs) / total
        for index in updated.centroid.indices where index < embedding.count {
            updated.centroid[index] = updated.centroid[index] * keep + embedding[index] * add
        }
        if let unit = normalized(updated.centroid) { updated.centroid = unit }
        updated.weightMs += weightMs
        return updated
    }

    public static func normalized(_ vector: [Float]) -> [Float]? {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }

    /// 1 - cosine similarity of unit vectors, in 0...2.
    public static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        for index in 0..<min(a.count, b.count) { dot += a[index] * b[index] }
        return 1 - dot
    }
}
