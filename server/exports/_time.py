"""Timestamp formatting shared by the subtitle renderers."""

from __future__ import annotations


def clock(ms: int, comma: bool) -> str:
    """`HH:MM:SS,mmm` for SRT, `HH:MM:SS.mmm` for WebVTT."""
    ms = max(0, int(ms))
    hours, rest = divmod(ms, 3_600_000)
    minutes, rest = divmod(rest, 60_000)
    seconds, millis = divmod(rest, 1000)
    sep = "," if comma else "."
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}{sep}{millis:03d}"
