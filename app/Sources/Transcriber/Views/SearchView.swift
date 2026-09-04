import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

struct SearchView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @FocusState private var focused: Bool
    @State private var hits: [SearchHit] = []
    @State private var scopes: Set<SearchScope> = Set(SearchScope.allCases)

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcripts, notes and bookmarks", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            Group {
                if state.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Search everything", systemImage: "magnifyingglass")
                    } description: {
                        Text("Words from any transcript, note, action item or bookmark. "
                             + "Quote a phrase to keep it together. Results jump to the moment.")
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: state.searchText)
                } else {
                    results
                }
            }
            // Told to fill, because an empty state asks for only the height it
            // needs: a stack of things that all fit gets centred in the column
            // instead of filling it, which floated the search field into the
            // middle of the window whenever there was nothing to show under it.
            // The results branch is greedy already and does not mind.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            focused = true
            state.focusSearch = false
            runSearch()
        }
        // Debounced: search walks every matching recording's segments, and
        // running that per keystroke makes typing feel like wading.
        .task(id: state.searchText) {
            guard !state.searchText.isEmpty else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            runSearch()
        }
        .onChange(of: state.focusSearch) { _, wanted in
            if wanted { focused = true; state.focusSearch = false }
        }
    }

    private var visible: [SearchHit] {
        hits.filter { scopes.contains($0.scope) }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(visible.count) result\(visible.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Toggle(scope.label, isOn: Binding(
                        get: { scopes.contains(scope) },
                        set: { on in
                            if on { scopes.insert(scope) } else { scopes.remove(scope) }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Divider()

            List(visible) { hit in
                Button {
                    state.open(hit)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(hit.recordingTitle)
                                .font(.callout.weight(.medium))
                            if let ms = hit.atMs {
                                Text(TimeFormat.short(ms: ms))
                                    .font(.system(.caption, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(.tint)
                            }
                            Text(hit.scope.label)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.quaternary))
                            Spacer()
                            Text(hit.recordingDate, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        HighlightedText(text: hit.snippet, highlights: hit.highlights)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
    }

    private func runSearch() {
        hits = (try? SearchService.search(state.searchText, in: context)) ?? []
    }
}
