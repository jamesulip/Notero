"""WebVTT. Same cues as SRT, with a header and dot-separated milliseconds."""

from __future__ import annotations

from ._time import clock


def render(session: dict, segments: list) -> str:
    lines = ["WEBVTT", ""]
    for segment in segments:
        end_ms = max(segment.end_ms, segment.start_ms + 1)
        text = segment.display_text
        # WebVTT has a voice span for exactly this.
        if segment.speaker_id:
            text = f"<v {segment.speaker_id}>{text}"
        lines.append(
            f"{clock(segment.start_ms, comma=False)} --> {clock(end_ms, comma=False)}"
        )
        lines.append(text)
        lines.append("")
    return "\n".join(lines)
