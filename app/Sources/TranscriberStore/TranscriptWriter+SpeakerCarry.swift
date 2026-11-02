import Foundation
import SwiftData
import TranscriberCore

/// What a new speaker pass inherits from the one before it.
///
/// The decision lives in `SpeakerMatching`, which is pure. This is the part that
/// reads the stored transcript for the evidence and writes the result back, kept
/// out of `TranscriptWriter.swift` so that file changes by one call.
struct SpeakerCarryPlan {
    var carry: SpeakerMatching.Carry
    /// Old rows a person named that the new run did not find. They stay in the
    /// roster with no talk time, so the name is there to hand back.
    var kept: [SpeakerLabel]
    /// Colour of each old row, by the label it will have afterwards.
    var colours: [String: Int]

    func relabel(_ spans: [SpeakerSpan]) -> [SpeakerSpan] {
        spans.map { span in
            var copy = span
            copy.speakerId = carry.label(for: span.speakerId)
            return copy
        }
    }

    /// The new roster under its final labels, then the kept rows.
    func relabel(_ roster: [SpeakerLabel]) -> [SpeakerLabel] {
        // An empty roster means no identification ran; the writer treats it as
        // "change nothing", and appending kept rows would turn it into a prune.
        guard !roster.isEmpty else { return [] }
        let renamed = roster.map { label -> SpeakerLabel in
            let final = carry.label(for: label.id)
            // A diarizer name is always the default for its label, so it
            // follows the label it ends up with. Anything else was chosen.
            let isDefault = label.displayName == SpeakerLabel.defaultName(for: label.id)
            return SpeakerLabel(id: final,
                                displayName: isDefault ? SpeakerLabel.defaultName(for: final)
                                                       : label.displayName,
                                speechMs: label.speechMs)
        }
        return renamed + kept
    }
}

extension TranscriptWriter {

    /// Matches the new run's speakers against the transcript as it stands.
    ///
    /// The evidence is the transcript's own lines and the labels they carry
    /// now, which includes every line a person moved by hand: their correction
    /// counts as the territory of the speaker they gave it to.
    func speakerCarryPlan(rows: [StoredSegment], recording: StoredRecording,
                          spans: [SpeakerSpan], roster: [SpeakerLabel]) -> SpeakerCarryPlan {
        let old: [SpeakerSpan] = rows.compactMap { row in
            guard let label = row.speakerId, row.endMs > row.startMs else { return nil }
            return SpeakerSpan(speakerId: label, startMs: row.startMs, endMs: row.endMs)
        }
        let existing = recording.speakers ?? []
        let named = Set(existing.filter {
            let name = $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name != SpeakerLabel.defaultName(for: $0.speakerId)
        }.map(\.speakerId))

        // Roster order is first appearance; `spans` may name a label the roster
        // does not (a roster is optional input), so those follow it.
        var order = roster.map(\.id)
        for span in spans.sorted(by: { $0.startMs < $1.startMs }) where !order.contains(span.speakerId) {
            order.append(span.speakerId)
        }

        let carry = SpeakerMatching.carry(old: old, new: spans, newOrder: order, named: named)
        let kept = existing
            .filter { carry.kept.contains($0.speakerId) }
            .sorted { $0.colorIndex < $1.colorIndex }
            .map { SpeakerLabel(id: $0.speakerId, displayName: $0.displayName, speechMs: 0) }
        // Colour belongs to the label a row ends up with. Rows that go away
        // (an unnamed speaker nobody inherited) are simply not in the map.
        var colours: [String: Int] = [:]
        for row in existing { colours[row.speakerId] = row.colorIndex }
        return SpeakerCarryPlan(carry: carry, kept: kept, colours: colours)
    }

    /// Puts each surviving row back on the colour it had, and gives a row that
    /// is new the lowest colour nobody holds, so two people never share one
    /// because the roster was renumbered.
    func restoreColours(_ plan: SpeakerCarryPlan, on recording: StoredRecording) {
        let rows = recording.speakers ?? []
        var used = Set<Int>()
        var fresh: [StoredSpeaker] = []
        for row in rows {
            if let colour = plan.colours[row.speakerId] {
                row.colorIndex = colour
                used.insert(colour)
            } else {
                fresh.append(row)
            }
        }
        var next = 0
        for row in fresh.sorted(by: { $0.colorIndex < $1.colorIndex }) {
            while used.contains(next) { next += 1 }
            row.colorIndex = next
            used.insert(next)
        }
    }
}

// MARK: - A transcription that brings its own speakers

extension TranscriptWriter {

    /// What Transcribe Again stores: the new run's segments and roster under the
    /// labels the recording already uses.
    ///
    /// Same question as `applySpeakers`, asked of a new revision instead of the
    /// current rows: the evidence is the lines of the latest earlier revision that
    /// finished with speaker labels (`labelledRows`), set against the lines the new run produced. `excluding` names the
    /// revisions that are not "earlier": the one being written, and the open
    /// partial revision of this very job (which has no speakers yet).
    ///
    /// Nothing changes where there is nothing to match (no earlier revision, none
    /// with speakers, no roster): the new run's labels pass through.
    func carriedSpeakers(segments: [Segment], roster: [SpeakerLabel],
                         on recording: StoredRecording,
                         excluding: Set<UUID> = []) -> (segments: [Segment], roster: [SpeakerLabel]) {
        guard !roster.isEmpty,
              let evidence = labelledRows(on: recording, excluding: excluding)
        else { return (segments, roster) }

        let spans: [SpeakerSpan] = segments.compactMap { segment in
            guard let label = segment.speakerId, segment.endMs > segment.startMs else { return nil }
            return SpeakerSpan(speakerId: label, startMs: segment.startMs, endMs: segment.endMs)
        }
        let plan = speakerCarryPlan(rows: evidence, recording: recording,
                                    spans: spans, roster: roster)
        let relabelled = segments.map { segment -> Segment in
            var copy = segment
            copy.speakerId = segment.speakerId.map { plan.carry.label(for: $0) }
            return copy
        }
        return (relabelled, plan.relabel(roster))
    }

    /// The lines of the newest finished revision that carries speaker labels,
    /// leaving out `excluding`. Nil when no revision does.
    ///
    /// Newest *labelled*, not newest: Transcribe Again with speaker
    /// identification off stores a revision with no labels and leaves the names
    /// on rows with no lines. Taken as the evidence, that revision matched
    /// nothing, and the next Identify Speakers Again or Transcribe Again put
    /// every voice under a new default name while the names a person typed sat
    /// on no line. Every revision is a reading of the same audio, so the one
    /// before it says just as well whose stretch of the timeline was whose.
    func labelledRows(on recording: StoredRecording,
                      excluding: Set<UUID> = []) -> [StoredSegment]? {
        let candidates = (recording.transcripts ?? [])
            .filter { !excluding.contains($0.id) && $0.isComplete }
            .sorted { $0.revision > $1.revision }
        for transcript in candidates {
            let rows = transcript.orderedSegments
            if rows.contains(where: { $0.speakerId != nil }) { return rows }
        }
        return nil
    }

    /// The same, by recording id, for a caller outside the actor.
    func carriedSpeakers(segments: [Segment], roster: [SpeakerLabel], for id: UUID,
                         excluding: Set<UUID> = []) throws -> (segments: [Segment], roster: [SpeakerLabel]) {
        var descriptor = FetchDescriptor<StoredRecording>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let recording = try modelContext.fetch(descriptor).first else { return (segments, roster) }
        return carriedSpeakers(segments: segments, roster: roster, on: recording, excluding: excluding)
    }
}
