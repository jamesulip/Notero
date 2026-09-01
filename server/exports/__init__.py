"""Export renderers over the segments table.

Speaker-aware from day one (section 9's hook 3). `speaker_id` is null until
Phase 6, and every renderer already handles both cases -- so adding diarization
later changes the data, not the renderers.
"""

from __future__ import annotations

from .json_ import render as render_json
from .srt import render as render_srt
from .txt import render as render_txt
from .vtt import render as render_vtt

RENDERERS = {
    "txt": (render_txt, "text/plain; charset=utf-8"),
    "srt": (render_srt, "application/x-subrip; charset=utf-8"),
    "vtt": (render_vtt, "text/vtt; charset=utf-8"),
    "json": (render_json, "application/json; charset=utf-8"),
}

__all__ = ["RENDERERS", "render_txt", "render_srt", "render_vtt", "render_json"]
