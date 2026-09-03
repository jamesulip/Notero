import SwiftUI
import TranscriberCore

/// The pipeline stage, with a progress bar only where progress is meaningful.
///
/// Stages have wildly different durations -- preparing is seconds, diarizing a
/// two-hour meeting is minutes -- so naming the stage matters more than the
/// percentage. A bar that sits still under one label reads as a hang.
struct StatusChip: View {
    let status: TranscriptionStatus
    var fraction: Double = 0
    /// Seconds left in the stage, shown on hover. Too changeable for the
    /// chip itself, which sits in a list row that should not be re-laid-out
    /// every tick.
    var remaining: TimeInterval?

    var body: some View {
        HStack(spacing: 5) {
            icon
            Text(label)
                .font(.caption2)
            if status.isBusy, fraction > 0.01 {
                ProgressView(value: min(1, fraction))
                    .progressViewStyle(.linear)
                    .frame(width: 44)
            }
        }
        .foregroundStyle(tint)
        .help(remaining.map { "\(TimeFormat.remaining(seconds: $0)) left" } ?? "")
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
        case .recording:
            Circle().fill(.red).frame(width: 7, height: 7)
        case .pending:
            Image(systemName: "clock").font(.system(size: 9))
        default:
            ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 10, height: 10)
        }
    }

    private var label: String {
        status.isBusy && fraction > 0.01 && status != .diarizing
            ? "\(status.label) \(Int(fraction * 100))%"
            : status.label
    }

    private var tint: Color {
        switch status {
        case .failed: return .orange
        case .completed: return .secondary
        case .recording: return .red
        default: return .secondary
        }
    }
}
