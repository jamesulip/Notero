import SwiftData
import SwiftUI
import TranscriberCore
import TranscriberStore

/// The manual meeting workspace: a free-text summary plus five typed lists.
///
/// Typed rows rather than one text blob, because every row keeps the timestamp
/// it came from. That is what makes a decision written down here checkable
/// against what was actually said -- and it is the shape an automatic
/// extraction pass would later write into, without the notes needing to be
/// re-modelled.
struct NotesPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    @State private var drafts: [MeetingItemKind: String] = [:]
    /// The quick-add row's kind and text. One field at the top beats five at
    /// the bottom of five sections when the note is being typed mid-meeting.
    @State private var quickKind: MeetingItemKind = .keyPoint
    @State private var quickText = ""
    @FocusState private var quickFocused: Bool
    /// Whether the notes model can run on this Mac today. Asked once per
    /// pane; nil until the answer is in.
    @State private var availability: NotesAvailability?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                draftRow
                quickAdd

                section("Summary") {
                    TextEditor(text: Binding(
                        get: { recording.summary },
                        set: { recording.summary = $0; recording.updatedAt = Date() }
                    ))
                    .font(.callout)
                    .frame(minHeight: 74)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                    .overlay(alignment: .topLeading) {
                        if recording.summary.isEmpty {
                            Text("What was the meeting about?")
                                .foregroundStyle(.tertiary)
                                .font(.callout)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
                }

                // Kinds with entries get a full section. Empty kinds collapse
                // to one add row each, so five empty headings do not push the
                // summary and the real notes off the top of a 340 pt column.
                ForEach(MeetingItemKind.allCases) { kind in
                    let items = RecordingStore.items(kind, of: recording)
                    if items.isEmpty {
                        addField(kind, compact: true)
                    } else {
                        section(kind.plural, symbol: kind.symbol) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(items) { item in
                                    ItemRow(recording: recording, item: item)
                                }
                                addField(kind)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .onDisappear { save() }
        .task { availability = await state.notesAvailability() }
        // The review of a draft, up while the coordinator holds one for this
        // recording. Closing it any way other than a button is a dismiss.
        .sheet(isPresented: Binding(
            get: { state.notes.draft(for: recording.id) != nil },
            set: { if !$0 { state.notes.dismiss(recording.id) } }
        )) {
            if let draft = state.notes.draft(for: recording.id) {
                NotesDraftSheet(recording: recording, draft: draft)
            }
        }
    }

    /// The model's offer, above the hand-written notes: one button, the
    /// progress while it reads, or the reason it stopped. Nothing at all on a
    /// macOS that has no model; the pane is the same as before then.
    @ViewBuilder
    private var draftRow: some View {
        if let progress = state.notes.progress(for: recording.id) {
            HStack(spacing: 8) {
                ProgressView(value: progress.fraction)
                Text(progress.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                Button("Cancel") { state.notes.cancel(recording.id) }
                    .controlSize(.small)
            }
        } else if let failure = state.notes.failure(for: recording.id) {
            VStack(alignment: .leading, spacing: 6) {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("OK") { state.notes.dismiss(recording.id) }
                    .controlSize(.small)
            }
        } else if state.canDraftNotes {
            Button {
                state.draftNotes(for: recording)
            } label: {
                Label("Draft Notes from the Transcript", systemImage: "sparkles")
                    .font(.callout)
            }
            .controlSize(.small)
            .disabled(!draftEnabled)
            .help(draftHelp)
        }
    }

    private var draftEnabled: Bool {
        (availability?.isAvailable ?? false) && recording.transcript != nil
            && !state.jobs.isBusy(recording.id)
    }

    private var draftHelp: String {
        if let availability, !availability.isAvailable { return availability.message }
        if recording.transcript == nil { return "Transcribe the recording first." }
        if state.jobs.isBusy(recording.id) { return "Wait for the transcription to complete." }
        return "The Apple Intelligence model on this Mac reads the transcript and proposes a "
             + "summary and notes. You select what to keep. Nothing leaves the Mac."
    }

    /// Kind on the left, text on the right, ↩ to add. The kind menu shows the
    /// shortcut that would have added the selected transcript line as that kind.
    private var quickAdd: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(MeetingItemKind.allCases) { kind in
                    Button {
                        quickKind = kind
                        quickFocused = true
                    } label: {
                        Label(kind.label, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label(quickKind.label, systemImage: quickKind.symbol)
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("The kind of note")

            TextField("Add a \(quickKind.label.lowercased())…", text: $quickText)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .focused($quickFocused)
                .onSubmit {
                    let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    drafts[quickKind] = text
                    commit(quickKind)
                    quickText = ""
                }
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                if let symbol { Image(systemName: symbol).font(.caption) }
            }
            content()
        }
    }

    private func addField(_ kind: MeetingItemKind, compact: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: compact ? kind.symbol : "plus")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            TextField(compact ? "Add \(kind.label.lowercased())" : "Add \(kind.label.lowercased())", text: Binding(
                get: { drafts[kind] ?? "" },
                set: { drafts[kind] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.callout)
            .onSubmit { commit(kind) }
        }
        .padding(.vertical, 3)
    }

    private func commit(_ kind: MeetingItemKind) {
        let text = (drafts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Typed by hand while listening, so the playhead is the right source
        // timestamp -- the same link a note lifted from a transcript row gets.
        let at = state.isRecording ? state.live.currentMs : state.player.currentMs
        let item = try? RecordingStore.addItem(kind, text: text, to: recording, in: context)
        item?.sourceMs = at > 0 ? at : nil
        drafts[kind] = ""
        save()
    }

    private func save() {
        RecordingStore.reindex(recording)
        try? context.save()
    }
}

struct ItemRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    let item: StoredMeetingItem

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if item.kind.isCheckable {
                Toggle("", isOn: Binding(
                    get: { item.isDone },
                    set: { item.isDone = $0; try? context.save() }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: Binding(
                    get: { item.text },
                    set: { item.text = $0 }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .onSubmit { try? context.save() }

                if let at = item.sourceMs {
                    Button {
                        state.pendingScrollTarget = item.sourceSegmentId
                        state.seek(to: at, in: recording)
                    } label: {
                        Label(TimeFormat.short(ms: at), systemImage: "arrow.turn.up.left")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Go to the line this came from")
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if item.kind.isCheckable {
                Button(item.isDone ? "Mark Not Done" : "Mark Done") {
                    item.isDone.toggle()
                    try? context.save()
                }
            }
            Menu("Change To") {
                ForEach(MeetingItemKind.allCases.filter { $0 != item.kind }) { kind in
                    Button(kind.label) { item.kind = kind; try? context.save() }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                context.delete(item)
                try? context.save()
            }
        }
    }
}

struct BookmarksPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    var body: some View {
        Group {
            if (recording.bookmarks ?? []).isEmpty {
                ContentUnavailableView {
                    Label("No bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Press ⌘B during a recording or during playback to mark the moment.")
                }
            } else {
                List {
                    ForEach((recording.bookmarks ?? []).sorted { $0.atMs < $1.atMs }) { bookmark in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TimeFormat.short(ms: bookmark.atMs))
                                .font(.system(.caption, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                                .frame(width: 52, alignment: .trailing)
                            TextField("Label", text: Binding(
                                get: { bookmark.label },
                                set: { bookmark.label = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .onSubmit { try? context.save() }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.seek(to: bookmark.atMs, in: recording) }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                context.delete(bookmark)
                                try? context.save()
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

/// The roster, by talk time, with the two repairs a far-field recording needs:
/// merge a fragment into the person it belongs to, and tell the next run how
/// many people were actually in the room.
struct SpeakersPane: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    let recording: StoredRecording

    /// Under this much speech, or under 1 % of the total, a speaker is more
    /// likely a fragment of someone else than a person. Flagged, not merged:
    /// a guest who said one thing is also under 30 s.
    private static let fragmentMs = 30_000

    private var speakers: [StoredSpeaker] {
        (recording.speakers ?? []).sorted { $0.speechMs > $1.speechMs }
    }

    private var totalMs: Int { speakers.reduce(0) { $0 + $1.speechMs } }

    private func isFragment(_ speaker: StoredSpeaker) -> Bool {
        speakers.count > 1
            && (speaker.speechMs < Self.fragmentMs
                || Double(speaker.speechMs) < 0.01 * Double(totalMs))
    }

    var body: some View {
        VStack(spacing: 0) {
            headCount
            Divider()
            if speakers.isEmpty {
                // Filling, so that the head count above stays at the top of
                // the pane rather than being centred with the empty state.
                ContentUnavailableView {
                    Label("No speakers yet", systemImage: "person.2")
                } description: {
                    Text(state.jobs.progress(for: recording.id)?.status == .diarizing
                         ? "Speaker identification in progress…"
                         : "The app identifies the speakers after the transcription.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(speakers) { speaker in
                        SpeakerRow(recording: recording, speaker: speaker,
                                   share: totalMs > 0 ? Double(speaker.speechMs) / Double(totalMs) : 0,
                                   isFragment: isFragment(speaker),
                                   others: speakers.filter { $0.id != speaker.id })
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    Text("Rename a speaker here, and every line follows. Right-click a "
                         + "speaker to merge it into another one. Right-click a transcript "
                         + "line to move only that line.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
        }
    }

    /// "People in the room". Stored on the recording and handed to the next
    /// speaker pass as a target. Shown even before speakers exist, because the
    /// best time to say six is before the run that finds fourteen.
    private var headCount: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Stepper(value: Binding(
                    get: { recording.expectedSpeakers ?? 0 },
                    set: { value in
                        recording.expectedSpeakers = value > 0 ? value : nil
                        recording.updatedAt = Date()
                        try? context.save()
                    }
                ), in: 0...30) {
                    HStack(spacing: 6) {
                        Text("Persons in the room")
                        Text(recording.expectedSpeakers.map(String.init) ?? "Any")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                }
                .font(.callout)
                Spacer()
                if recording.hasAudio, !state.jobs.isBusy(recording.id) {
                    Button("Identify Again") { state.rediarize(recording) }
                        .controlSize(.small)
                        .help("Run the speaker identification again, with this count as the target")
                }
            }
            if speakers.count > 1, let expected = recording.expectedSpeakers,
               speakers.count > expected {
                Text("The app found \(speakers.count) speakers for \(expected) persons. Merge "
                     + "the fragments below, or click Identify Again.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A target for the speaker identification, and not a limit. Voices "
                     + "that the model hears as different stay separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }
}

struct SpeakerRow: View {
    @Environment(\.modelContext) private var context
    let recording: StoredRecording
    let speaker: StoredSpeaker
    let share: Double
    let isFragment: Bool
    let others: [StoredSpeaker]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Circle()
                    .fill(SpeakerPalette.color(speaker.colorIndex))
                    .frame(width: 9, height: 9)
                TextField("Name", text: Binding(
                    get: { speaker.displayName },
                    set: { speaker.displayName = $0 }
                ))
                .textFieldStyle(.plain)
                .onSubmit {
                    try? RecordingStore.rename(speaker, to: speaker.displayName, in: context)
                }
                Spacer()
                Text(TimeFormat.coarse(ms: speaker.speechMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Talk time as a bar, so fourteen rows read as "two people and a
            // dozen slivers" at a glance rather than as a column of numbers.
            GeometryReader { geometry in
                Capsule()
                    .fill(SpeakerPalette.color(speaker.colorIndex).opacity(0.75))
                    .frame(width: max(2, geometry.size.width * share))
            }
            .frame(height: 4)
            .padding(.leading, 18)
            if isFragment {
                Label("Likely a fragment of another speaker", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Menu("Merge Into") {
                ForEach(others) { other in
                    Button(other.displayName) {
                        try? RecordingStore.merge(speaker, into: other, in: context)
                    }
                }
            }
            .disabled(others.isEmpty)
        }
    }
}
