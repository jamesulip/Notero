import SwiftUI
import TranscriberCore

/// The peak envelope, drawn with `Canvas`.
///
/// One shape per bar in a `ForEach` would be several hundred SwiftUI views
/// re-laid-out on every playhead tick. `Canvas` is one view that draws a path.
struct WaveformView: View {
    let samples: [Float]
    /// 0...1. Bars before it are drawn as played.
    var progress: Double = 0
    var bookmarks: [Double] = []
    var tint: Color = .accentColor
    var onScrub: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !samples.isEmpty else { return }
                let count = samples.count
                let barWidth = max(1, size.width / CGFloat(count) * 0.72)
                let step = size.width / CGFloat(count)
                let middle = size.height / 2
                let playedUntil = size.width * CGFloat(min(1, max(0, progress)))

                var played = Path()
                var upcoming = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * step
                    // Drawn on a dB scale, not on raw amplitude: speech peaks
                    // around -28 dBFS, which is 4% of a linear bar and reads as
                    // a dead microphone. A floor of one point keeps silence a
                    // visible line rather than a gap that looks like lost audio.
                    let height = max(1, CGFloat(InputGain.meterFraction(sample))
                                        * (size.height - 2))
                    let rect = CGRect(x: x, y: middle - height / 2,
                                      width: barWidth, height: height)
                    let rounded = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    if x <= playedUntil { played.addPath(rounded) } else { upcoming.addPath(rounded) }
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
        HStack(alignment: .center, spacing: 2) {
            WaveformView(samples: samples, progress: 1, tint: .red)
                .frame(height: 64)
            RoundedRectangle(cornerRadius: 2)
                .fill(InputGain.isClipping(level) ? Color.orange : Color.red)
                .frame(width: 4,
                       height: max(4, CGFloat(InputGain.meterFraction(level)) * 64))
                .animation(.linear(duration: 0.08), value: level)
        }
    }
}
