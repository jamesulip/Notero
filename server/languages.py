"""Selectable transcription languages.

Section 2 forces `tl` by default and warns why: auto-detect on Taglish resolves
to English and the model starts *translating* rather than transcribing. That is
not theoretical -- run auto-detect over the Taglish fixture and Whisper reports
Indonesian, because it hears the voice rather than reading the script.

So auto-detect is offered, listed last, and flagged. Everything else is an
explicit choice.
"""

from __future__ import annotations

from dataclasses import dataclass

AUTO = "auto"


@dataclass(frozen=True)
class Language:
    code: str
    label: str
    note: str = ""
    recommended: bool = False


LANGUAGES: tuple[Language, ...] = (
    Language("tl", "Tagalog / Taglish",
             "Forced Tagalog. Code-switched English is transcribed as spoken.",
             recommended=True),
    Language("en", "English"),
    Language("id", "Indonesian"),
    Language("ms", "Malay"),
    Language("zh", "Chinese"),
    Language("ja", "Japanese"),
    Language("ko", "Korean"),
    Language("es", "Spanish"),
    Language("fr", "French"),
    Language("de", "German"),
    Language("pt", "Portuguese"),
    Language("it", "Italian"),
    Language("nl", "Dutch"),
    Language("ru", "Russian"),
    Language("ar", "Arabic"),
    Language("hi", "Hindi"),
    Language("vi", "Vietnamese"),
    Language("th", "Thai"),
    Language(AUTO, "Auto-detect",
             "Not recommended for Taglish: the decoder picks a language per "
             "window and may translate instead of transcribe. On the Taglish "
             "fixture it reports Indonesian."),
)

BY_CODE = {lang.code: lang for lang in LANGUAGES}
DEFAULT = "tl"


def catalogue(current: str | None) -> list[dict]:
    return [
        {
            "code": lang.code,
            "label": lang.label,
            "note": lang.note,
            "recommended": lang.recommended,
            "auto_detect": lang.code == AUTO,
            "current": lang.code == current,
        }
        for lang in LANGUAGES
    ]
