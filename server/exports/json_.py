"""JSON: the lossless one. Keeps raw and cleaned text side by side."""

from __future__ import annotations

import json


def render(session: dict, segments: list) -> str:
    return json.dumps(
        {
            "session": {
                "id": session.get("id"),
                "started_at": session.get("started_at"),
                "ended_at": session.get("ended_at"),
                "language": session.get("language"),
                "duration_ms": session.get("duration_ms"),
            },
            "segments": [
                {
                    "id": s.id,
                    "start_ms": s.start_ms,
                    "end_ms": s.end_ms,
                    "text": s.text,
                    "text_clean": s.text_clean,
                    "speaker_id": s.speaker_id,
                }
                for s in segments
            ],
        },
        ensure_ascii=False,
        indent=2,
    ) + "\n"
