import Foundation

/// One decoded word with its position on the session timeline.
public struct Token: Equatable, Sendable, Codable {
    public var text: String
    public var startMs: Int
    public var endMs: Int
    /// 0...1 when the backend reports one. Averaged up into `Segment.confidence`.
    public var confidence: Double?

    public init(text: String, startMs: Int, endMs: Int, confidence: Double? = nil) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.confidence = confidence
    }
}

public extension Array where Element == Token {
    var joinedText: String {
        map(\.text).joined().trimmingCharacters(in: .whitespaces)
    }

    /// Mean of the confidences that exist. Nil if none do.
    var meanConfidence: Double? {
        let values = compactMap(\.confidence)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
