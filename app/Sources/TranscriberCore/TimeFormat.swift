import Foundation

/// Clock formatting, in one place.
///
/// Four different consumers need timestamps -- the transcript rows, the player
/// scrubber, SRT and WebVTT -- and they disagree only about the separator and
/// whether to show the hour. Keeping them together is what stops an export
/// drifting from what the UI showed.
public enum TimeFormat {

    /// `M:SS`, or `H:MM:SS` past an hour. What the UI shows.
    public static func short(ms: Int) -> String {
        let total = max(0, ms) / 1000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm` (WebVTT).
    public static func cue(ms: Int, comma: Bool) -> String {
        let ms = max(0, ms)
        let separator = comma ? "," : "."
        return String(format: "%02d:%02d:%02d%@%03d",
                      ms / 3_600_000,
                      (ms % 3_600_000) / 60_000,
                      (ms % 60_000) / 1000,
                      separator,
                      ms % 1000)
    }

    /// Spoken duration, for history rows: "42:18", "1:12:44".
    public static func duration(ms: Int) -> String { short(ms: ms) }

    /// "about 14 min", "about 1 hr 5 min" -- for time remaining, which is an
    /// estimate and should read like one.
    public static func remaining(seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "about \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "about \(hours) hr" : "about \(hours) hr \(rest) min"
    }

    /// "~14 min" -- `remaining` for a chip that has no room for "about".
    public static func remainingCompact(seconds: Double) -> String {
        remaining(seconds: seconds).replacingOccurrences(of: "about ", with: "~")
    }

    /// "1:23:45", "12:34" or "45" to milliseconds. Nil for anything else, so a
    /// half-typed field is ignored rather than read as zero.
    public static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            values.append(value)
        }
        // Minutes and seconds past the first field must be a clock reading.
        for value in values.dropFirst() where value >= 60 { return nil }
        var seconds = 0
        for value in values { seconds = seconds * 60 + value }
        return seconds * 1000
    }

    /// "4 min", "1 hr 12 min" -- for places where seconds are noise.
    public static func coarse(ms: Int) -> String {
        let minutes = max(0, ms) / 60_000
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}
