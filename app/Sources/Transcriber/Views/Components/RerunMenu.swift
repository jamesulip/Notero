import SwiftUI
import TranscriberCore
import TranscriberStore

/// The re-run choices for a recording with audio: decode again on a named
/// tier, or run speaker identification again over the transcript that exists.
///
/// Presented as items rather than a bare "Transcribe Again", which silently
/// used whatever tier Settings held. Re-transcribing a meeting is almost always
/// a request for the Accurate tier, and the diarize-only job existed with no
/// way to ask for it.
struct RerunItems: View {
    @Environment(AppState.self) private var state
    let recording: StoredRecording

    var body: some View {
        Menu("Transcribe Again", systemImage: "arrow.clockwise") {
            ForEach(ModelTier.allCases) { tier in
                Button {
                    state.retranscribe(recording, tier: tier)
                } label: {
                    if tier == state.settings.tier {
                        Label(title(tier), systemImage: "checkmark")
                    } else {
                        Text(title(tier))
                    }
                }
            }
        }
        if recording.transcript != nil {
            Button("Identify Speakers Again", systemImage: "person.2") {
                state.rediarize(recording)
            }
        }
    }

    /// "Accurate · large-v3": the tier is the choice, the model is what it
    /// costs, and the two are shown together so the menu needs no footnote.
    private func title(_ tier: ModelTier) -> String {
        let id = state.settings.modelId(for: tier)
        let model = ModelCatalogue.option(id)?.label ?? id
        return "\(tier.label) · \(model)"
    }
}

/// The same items as a toolbar-style button for the detail header.
struct RerunButton: View {
    let recording: StoredRecording
    var label = "Transcribe Again"

    var body: some View {
        Menu {
            RerunItems(recording: recording)
        } label: {
            Text(label)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
    }
}
