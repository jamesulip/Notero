import Foundation

/// The text handed to the decoder as a "previous transcript" before each
/// window.
///
/// Whisper reads the prompt as the words that came just before the audio, so
/// the prompt sets the style of the output: the spelling, the casing and, for
/// code-switched speech, which language an English word is written in. The
/// primer below is one sentence of ordinary Taglish with the hyphenated
/// affixes and the English nouns that a meeting is made of; it names nothing
/// that a real meeting would say, so it cannot leak into a measurement.
///
/// **The app does not send the primer.** Measured on 2026-09-06 through
/// `transcribe --style-hint` (docs/FINDINGS.md, finding 12): on the live path
/// the model repeated the primer instead of the room and the word error rate
/// went from 27% to 96%; offline it was worse on one clip and better on the
/// other. The primer stays here so the measurement can be repeated, and so
/// the next person does not have to rediscover the result.
public enum TranscriptionPrompt {

    /// A style primer for each language that has one. Only Tagalog has one,
    /// and only the CLI uses it.
    public static func primer(for language: String) -> String? {
        switch language {
        case "tl":
            return "Sige, mag-start na tayo. Na-send ko na yung email kahapon, pero hindi pa "
                 + "na-approve ng client. I-check natin mamaya kung okay na ang design, tapos "
                 + "mag-schedule tayo ng follow-up meeting next week."
        default:
            return nil
        }
    }

    /// The prompt for one decode: the primer for the language, when wanted,
    /// followed by the names and terms the user typed. Nil when there is
    /// nothing to say, so the decoder runs with no prompt at all.
    public static func compose(language: String, usePrimer: Bool,
                               vocabulary: String?) -> String? {
        var parts: [String] = []
        if usePrimer, let primer = primer(for: language) { parts.append(primer) }
        if let vocabulary {
            let trimmed = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
