"""SubRip. Cues are renumbered from 1 and must not overlap."""

from __future__ import annotations

from ._time import clock


def render(session: dict, segments: list) -> str:
    blocks = []
    for index, segment in enumerate(segments, start=1):
        # A zero-length cue is legal but invisible in most players.
        end_ms = max(segment.end_ms, segment.start_ms + 1)
        text = segment.display_text
        if segment.speaker_id:
            text = f"[{segment.speaker_id}] {text}"
        blocks.append(
            f"{index}\n"
            f"{clock(segment.start_ms, comma=True)} --> {clock(end_ms, comma=True)}\n"
            f"{text}\n"
        )
    return "\n".join(blocks)
