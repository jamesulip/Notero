"""Plain text: one paragraph per speaker turn, or one block if undiarized."""

from __future__ import annotations


def render(session: dict, segments: list) -> str:
    if not segments:
        return ""

    if not any(s.speaker_id for s in segments):
        return " ".join(s.display_text for s in segments).strip() + "\n"

    lines, current, buffer = [], object(), []
    for segment in segments:
        speaker = segment.speaker_id or "UNKNOWN"
        if speaker != current:
            if buffer:
                lines.append(f"{current}: {' '.join(buffer)}")
            current, buffer = speaker, []
        buffer.append(segment.display_text)
    if buffer:
        lines.append(f"{current}: {' '.join(buffer)}")
    return "\n\n".join(lines) + "\n"
