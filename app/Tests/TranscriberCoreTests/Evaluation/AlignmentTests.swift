import XCTest
@testable import TranscriberCore

final class AlignmentTests: XCTestCase {

    /// (reference, hypothesis, S, D, I). The S/D/I were produced by running
    /// `eval/score.py`'s `levenshtein(ref.split(), hyp.split())` with
    /// `python3 -I` on each pair. Do not edit by hand.
    static let scorePyLevenshtein: [(String, String, Int, Int, Int)] = [
        ("a b c", "a b c", 0, 0, 0),
        ("a b c", "", 0, 3, 0),
        ("", "a b", 0, 0, 2),
        ("a b c d", "a x c", 1, 1, 0),
        ("a b", "b a", 2, 0, 0),
        ("sige i send mo na", "sige send mo na po", 0, 1, 1),
        ("the cat sat on the mat", "cat sat on a mat mat", 1, 1, 1),
        ("a a a b", "b a a a", 2, 0, 0),
        ("x y z", "y z x", 0, 1, 1),
        ("isa dalawa tatlo apat lima", "isa tatlo apat apat lima anim", 2, 0, 1),
        ("a b c d e", "e d c b a", 4, 0, 0),
        ("ab", "cd ef gh", 1, 0, 2),
    ]

    private func split(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    func testSplitMatchesScorePyLevenshtein() throws {
        for (ref, hyp, s, d, i) in Self.scorePyLevenshtein {
            let r = split(ref), h = split(hyp)
            let counts = Alignment.counts(reference: r, hypothesis: h)
            XCTAssertEqual([counts.substitutions, counts.deletions, counts.insertions], [s, d, i], "\(ref) | \(hyp)")
            XCTAssertEqual(counts.hits, r.count - s - d)
            let path = try XCTUnwrap(Alignment.path(reference: r, hypothesis: h))
            XCTAssertEqual(Alignment.counts(of: path), counts, "\(ref) | \(hyp)")
        }
    }

    func testPathIsAValidAlignment() {
        let r = split("isa dalawa tatlo apat lima"), h = split("isa tatlo apat apat lima anim")
        let path = Alignment.path(reference: r, hypothesis: h)!
        XCTAssertEqual(path.compactMap(\.referenceIndex), Array(r.indices))
        XCTAssertEqual(path.compactMap(\.hypothesisIndex), Array(h.indices))
        for step in path {
            switch step.operation {
            case .match: XCTAssertEqual(r[step.referenceIndex!], h[step.hypothesisIndex!])
            case .substitution: XCTAssertNotEqual(r[step.referenceIndex!], h[step.hypothesisIndex!])
            case .deletion: XCTAssertNil(step.hypothesisIndex)
            case .insertion: XCTAssertNil(step.referenceIndex)
            }
        }
    }

    func testEmptyInputs() {
        let empty: [String] = []
        XCTAssertEqual(Alignment.path(reference: empty, hypothesis: empty), [])
        XCTAssertEqual(Alignment.counts(reference: empty, hypothesis: empty), .zero)
        XCTAssertEqual(Alignment.path(reference: ["a", "b"], hypothesis: empty)?.map(\.operation),
                       [.deletion, .deletion])
        XCTAssertEqual(Alignment.path(reference: empty, hypothesis: ["a"])?.map(\.operation), [.insertion])
        XCTAssertEqual(Alignment.counts(reference: ["a", "b"], hypothesis: empty), ErrorCounts(deletions: 2))
        XCTAssertEqual(Alignment.counts(reference: empty, hypothesis: ["a"]), ErrorCounts(insertions: 1))
    }

    func testPathIsNilAboveTheCellLimit() {
        let r = Array(repeating: "a", count: 10), h = Array(repeating: "b", count: 10)
        XCTAssertNil(Alignment.path(reference: r, hypothesis: h, maxCells: 99))
        XCTAssertNotNil(Alignment.path(reference: r, hypothesis: h, maxCells: 100))
        XCTAssertNotNil(Alignment.path(reference: r, hypothesis: [String](), maxCells: 0),
                        "an empty side is zero cells")
        XCTAssertEqual(Alignment.maxCellsForFullPath, 120_000_000)
    }

    /// A fixed linear congruential generator, so the "random" inputs are the
    /// same on every run and every machine.
    private struct LCG {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    func testCountsEqualPathCountsOnDeterministicInputs() {
        var rng = LCG(state: 42)
        for _ in 0..<300 {
            let alphabet = 1 + rng.next(5)
            let r = (0..<rng.next(14)).map { _ in rng.next(alphabet) }
            let h = (0..<rng.next(14)).map { _ in rng.next(alphabet) }
            let path = Alignment.path(reference: r, hypothesis: h)!
            let counts = Alignment.counts(reference: r, hypothesis: h)
            XCTAssertEqual(Alignment.counts(of: path), counts, "\(r) | \(h)")
            // Minimal: the distance equals the plain Levenshtein distance.
            XCTAssertEqual(counts.errors, levenshtein(r, h), "\(r) | \(h)")
        }
    }

    private func levenshtein(_ a: [Int], _ b: [Int]) -> Int {
        var row = Array(0...b.count)
        for i in a.indices {
            var next = [i + 1]
            for j in b.indices {
                next.append(Swift.min(row[j + 1] + 1, next[j] + 1, row[j] + (a[i] == b[j] ? 0 : 1)))
            }
            row = next
        }
        return row[b.count]
    }
}
