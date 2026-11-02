import Foundation

// Minimum-edit alignment of a reference to a hypothesis.
//
// The split of an error rate into substitutions, deletions and insertions is
// not unique: several alignments can share the minimum distance. Which one is
// reported is decided by the tie-breaking below, and it is fixed to the one
// `eval/score.py`'s `levenshtein` makes, so the S/D/I columns of a report and
// of the documented baseline tables mean the same thing.
//
// Tie-breaking, at each cell (i, j):
//   * reference[i-1] == hypothesis[j-1]: the diagonal, a match. With unit costs
//     the diagonal is then always a minimum, so nothing is lost by not looking.
//   * otherwise the first minimum of substitution (diagonal), deletion (up),
//     insertion (left), in that order.
// Row 0 is all insertions and column 0 all deletions. The backtrace follows the
// choice stored per cell, which is exactly the chain score.py carries forward.

public enum EditOperation: String, Codable, Sendable {
    case match, substitution, deletion, insertion
}

/// One step of an alignment. A match or substitution has both indices, a
/// deletion only the reference index, an insertion only the hypothesis index.
public struct AlignmentStep: Codable, Sendable, Equatable {
    public var operation: EditOperation
    public var referenceIndex: Int?
    public var hypothesisIndex: Int?

    public init(operation: EditOperation, referenceIndex: Int?, hypothesisIndex: Int?) {
        self.operation = operation
        self.referenceIndex = referenceIndex
        self.hypothesisIndex = hypothesisIndex
    }
}

public enum Alignment {
    /// Above this many DP cells (n * m) the full path is not built. One byte
    /// per cell, so this is a 120 MB direction matrix: about an 11,000-word
    /// reference against an 11,000-word hypothesis, a meeting of well over an
    /// hour scored as one item.
    public static let maxCellsForFullPath = 120_000_000

    /// The full optimal path, deterministic. Nil when n * m > ``maxCellsForFullPath``.
    public static func path<T: Equatable>(reference: [T], hypothesis: [T]) -> [AlignmentStep]? {
        path(reference: reference, hypothesis: hypothesis, maxCells: maxCellsForFullPath)
    }

    /// As ``path(reference:hypothesis:)`` with a caller-chosen cell limit, so
    /// tests can reach the too-large branch without allocating gigabytes.
    static func path<T: Equatable>(reference: [T], hypothesis: [T], maxCells: Int) -> [AlignmentStep]? {
        let n = reference.count, m = hypothesis.count
        let (cells, overflow) = n.multipliedReportingOverflow(by: m)
        guard !overflow, cells <= maxCells else { return nil }

        // 0 match, 1 substitution, 2 deletion, 3 insertion; row-major, (i-1)*m + (j-1).
        var directions = [UInt8](repeating: 0, count: cells)
        if n > 0 && m > 0 {
            var previous = Array(0...m)
            var current = [Int](repeating: 0, count: m + 1)
            directions.withUnsafeMutableBufferPointer { dir in
                for i in 1...n {
                    current[0] = i
                    let row = (i - 1) * m
                    let r = reference[i - 1]
                    for j in 1...m {
                        if r == hypothesis[j - 1] {
                            current[j] = previous[j - 1]
                            dir[row + j - 1] = 0
                            continue
                        }
                        let sub = previous[j - 1] + 1, del = previous[j] + 1, ins = current[j - 1] + 1
                        if sub <= del && sub <= ins {
                            current[j] = sub; dir[row + j - 1] = 1
                        } else if del <= ins {
                            current[j] = del; dir[row + j - 1] = 2
                        } else {
                            current[j] = ins; dir[row + j - 1] = 3
                        }
                    }
                    swap(&previous, &current)
                }
            }
        }

        var steps: [AlignmentStep] = []
        steps.reserveCapacity(max(n, m))
        var i = n, j = m
        while i > 0 || j > 0 {
            let choice: UInt8 = i == 0 ? 3 : j == 0 ? 2 : directions[(i - 1) * m + (j - 1)]
            switch choice {
            case 0:
                steps.append(AlignmentStep(operation: .match, referenceIndex: i - 1, hypothesisIndex: j - 1))
                i -= 1; j -= 1
            case 1:
                steps.append(AlignmentStep(operation: .substitution, referenceIndex: i - 1, hypothesisIndex: j - 1))
                i -= 1; j -= 1
            case 2:
                steps.append(AlignmentStep(operation: .deletion, referenceIndex: i - 1, hypothesisIndex: nil))
                i -= 1
            default:
                steps.append(AlignmentStep(operation: .insertion, referenceIndex: nil, hypothesisIndex: j - 1))
                j -= 1
            }
        }
        steps.reverse()
        return steps
    }

    /// Counts in linear memory, with the same tie-breaking as ``path`` and
    /// therefore the same counts: each cell carries the S/D/I of the choice it
    /// stored, as score.py does, instead of a direction to backtrace.
    public static func counts<T: Equatable>(reference: [T], hypothesis: [T]) -> ErrorCounts {
        let n = reference.count, m = hypothesis.count
        if n == 0 { return ErrorCounts(insertions: m) }
        if m == 0 { return ErrorCounts(deletions: n) }

        var previous = (0...m).map { Cell(distance: $0, substitutions: 0, deletions: 0, insertions: $0) }
        var current = previous
        for i in 1...n {
            current[0] = Cell(distance: i, substitutions: 0, deletions: i, insertions: 0)
            let r = reference[i - 1]
            for j in 1...m {
                if r == hypothesis[j - 1] {
                    current[j] = previous[j - 1]
                    continue
                }
                let sub = previous[j - 1], del = previous[j], ins = current[j - 1]
                if sub.distance <= del.distance && sub.distance <= ins.distance {
                    current[j] = Cell(distance: sub.distance + 1, substitutions: sub.substitutions + 1,
                                      deletions: sub.deletions, insertions: sub.insertions)
                } else if del.distance <= ins.distance {
                    current[j] = Cell(distance: del.distance + 1, substitutions: del.substitutions,
                                      deletions: del.deletions + 1, insertions: del.insertions)
                } else {
                    current[j] = Cell(distance: ins.distance + 1, substitutions: ins.substitutions,
                                      deletions: ins.deletions, insertions: ins.insertions + 1)
                }
            }
            swap(&previous, &current)
        }
        let last = previous[m]
        return ErrorCounts(hits: n - last.substitutions - last.deletions,
                           substitutions: last.substitutions,
                           deletions: last.deletions,
                           insertions: last.insertions)
    }

    /// The counts a path stands for.
    static func counts(of steps: some Sequence<AlignmentStep>) -> ErrorCounts {
        var c = ErrorCounts()
        for step in steps {
            switch step.operation {
            case .match: c.hits += 1
            case .substitution: c.substitutions += 1
            case .deletion: c.deletions += 1
            case .insertion: c.insertions += 1
            }
        }
        return c
    }

    private struct Cell {
        var distance: Int
        var substitutions: Int
        var deletions: Int
        var insertions: Int
    }
}
