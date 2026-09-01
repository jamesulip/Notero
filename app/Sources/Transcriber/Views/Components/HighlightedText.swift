import SwiftUI
import TranscriberCore

/// A snippet with the matched terms marked.
///
/// Built as an `AttributedString` from ranges the search already computed,
/// rather than re-searching here: the snippet may contain the term more than
/// once, and only the occurrences that were matched should light up.
struct HighlightedText: View {
    let text: String
    let highlights: [Range<String.Index>]

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString(text)
        for range in highlights {
            guard let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out),
                  lower < upper else { continue }
            out[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            out[lower..<upper].backgroundColor = .yellow.opacity(0.35)
        }
        return out
    }
}

/// Consistent per-speaker colour, derived from the roster position rather than
/// a hash of the name: renaming "Speaker 2" to "Maria" must not change colour
/// halfway through reading a transcript.
enum SpeakerPalette {
    static let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .green, .indigo, .brown]

    static func color(_ index: Int) -> Color {
        colors[abs(index) % colors.count]
    }
}
