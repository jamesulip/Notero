import SwiftUI
import TranscriberCore

/// The peak envelope, drawn with `Canvas`.
///
/// One shape per bar in a `ForEach` would be several hundred SwiftUI views
/// re-laid-out on every playhead tick. `Canvas` is one view that draws a path.
struct WaveformView: View {

    /// How the samples are spread across the width.
    enum Layout {
        /// The whole recording, edge to edge. Used for a finished file, where
        /// the width is the duration and the playhead has to mean something.
        case fill
        /// Newest sample at the right edge, older ones scrolling off the left.
        /// Used for the live meter, where the width is recent history.
        case trailing
    }

    let samples: [Float]
    /// Which curve turns a sample into a height. The stored envelope and the
    /// live meter are on different scales -- see `WaveformScale`.
    var scale: WaveformScale = .envelope
    var layout: Layout = .fill
    /// 0...1. Bars before it are drawn as played.
    var progress: Double = 0
    var bookmarks: [Double] = []
    var tint: Color = .accentColor
    /// A line at `progress`. The colour change alone is hard to read on a
    /// quiet passage, where the bars either side are both near the floor.
    var showsPlayhead = false
    var onScrub: ((Double) -> Void)?

    /// One bar plus its gap, in points. Two points of bar and one of gap is
    /// the narrowest that still reads as bars rather than as a filled shape.
    private static let barPitch: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let count = max(1, Int(size.width / Self.barPitch))
                let values = layout == .fill
                    ? WaveformBars.fitted(samples, to: count)
                    : WaveformBars.trailing(samples, in: count)
                let step = size.width / CGFloat(count)
                let barWidth = max(1, step - 1)
                let middle = size.height / 2
                let playedUntil = size.width * CGFloat(min(1, max(0, progress)))

                // A continuous rule under the bars. Silence draws as
                // one-point bars with a gap between each, which reads as a
                // dotted line rather than as a track; the rule is what makes an
                // empty player -- a recording whose envelope is still being
                // computed -- look like something to scrub along.
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: middle))
                baseline.addLine(to: CGPoint(x: size.width, y: middle))
                context.stroke(baseline, with: .color(tint.opacity(0.22)), lineWidth: 1)

                var played = Path()
                var upcoming = Path()
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    // A floor of one point keeps silence a visible line rather
                    // than a gap that looks like lost audio.
                    let height = max(1, CGFloat(scale.fraction(value)) * (size.height - 2))
                    let rect = CGRect(x: x, y: middle - height / 2,
                                      width: barWidth, height: height)
                    let rounded = Path(roundedRect: rect,
                                       cornerRadius: min(barWidth, height) / 2)
                    if x < playedUntil { played.addPath(rounded) } else { upcoming.addPath(rounded) }
                }
                context.fill(upcoming, with: .color(tint.opacity(0.28)))
                context.fill(played, with: .color(tint))

                for mark in bookmarks {
                    let x = size.width * CGFloat(min(1, max(0, mark)))
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.orange), lineWidth: 1.5)
                }

                if showsPlayhead {
                    let x = min(size.width - 1, max(0, playedUntil))
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.primary), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onScrub, geometry.size.width > 0 else { return }
                        onScrub(min(1, max(0, value.location.x / geometry.size.width)))
                    }
            )
        }
    }
}

/// Microphone boost, with the clipping warning next to it rather than buried in
/// Settings: the only way to choose a gain is to watch the meter while talking,
/// so the control belongs beside the meter it is being tuned against.
struct InputGainSlider: View {
    @Binding var gainDb: Float
    var isClipping = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: $gainDb,
                   in: InputGain.minDb...InputGain.maxDb,
                   step: 1)
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isClipping ? .orange : .secondary)
                .frame(width: 62, alignment: .leading)
        }
        .help("Boosts the microphone before recording and transcription. "
            + "Raise it until speech fills most of the meter.")
    }

    private var label: String {
        if isClipping { return "clipping" }
        return gainDb == 0 ? "0 dB" : String(format: "%+.0f dB", gainDb)
    }
}

/// The live input meter: newest bar on the right, scrolling left.
struct LevelMeter: View {
    let samples: [Float]
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Raw peaks against full scale, so the height means the same thing
            // as the clipping warning under it. The stored envelope is drawn on
            // the other curve; see `WaveformScale`.
            WaveformView(samples: samples, scale: .level, layout: .trailing,
                         progress: 1, tint: .red)
                .frame(maxWidth: .infinity)
            // The instant level, beside the history rather than in it: the bars
            // are one per 100 ms and a clip shorter than that would not show.
            RoundedRectangle(cornerRadius: 2)
                .fill(InputGain.isClipping(level) ? Color.orange : Color.red)
                .frame(width: 4,
                       height: max(4, CGFloat(WaveformScale.level.fraction(level)) * 64))
                .animation(.linear(duration: 0.08), value: level)
        }
        .frame(height: 64)
    }
}
