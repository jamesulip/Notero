"""LocalAgreement-n commit policy.

Consecutive overlapping windows are transcribed independently. A token is
committed only once the last `agreement` passes have produced it at the same
position. Committed text is frozen permanently -- that is what makes the
foreground half of section 8's design contract true ("muted text may change,
foreground text never will").

Section 7 starts at 2-pass and escalates to 3 if committed text still visibly
churns, so `agreement` is a parameter rather than a hard-coded pair.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

from .adapters.base import Token

_PUNCT = re.compile(r"[^\w']+", re.UNICODE)


def _key(token: Token) -> str:
    """Comparison form. Whisper varies casing and punctuation between passes on
    identical audio, so comparing raw text would block almost every commit."""
    text = unicodedata.normalize("NFKC", token.text).lower().strip()
    return _PUNCT.sub("", text)


@dataclass
class LocalAgreement:
    agreement: int = 2
    committed: list[Token] = field(default_factory=list)
    #: Absolute ms of audio received so far. Nothing may be timestamped past it.
    ceiling_ms: int | None = None
    _history: list[list[Token]] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.agreement < 2:
            raise ValueError("agreement must be at least 2")

    # -- state -------------------------------------------------------------

    @property
    def committed_end_ms(self) -> int:
        return self.committed[-1].end_ms if self.committed else 0

    @property
    def committed_text(self) -> str:
        return "".join(t.text for t in self.committed).strip()

    @property
    def partial(self) -> str:
        """The provisional tail: newest hypothesis minus what is committed."""
        if not self._history:
            return ""
        return "".join(t.text for t in self._history[-1]).strip()

    # -- policy ------------------------------------------------------------

    def _monotonic(self, tokens: list[Token]) -> list[Token]:
        """Clamps timings so the committed timeline only moves forward.

        Word timings shift by tens of milliseconds between passes, so a token
        committed from a later window can carry a start earlier than the token
        before it. Harmless on screen, not harmless in an SRT file, where cues
        must be ordered and non-overlapping -- and not harmless for Phase 6's
        overlap merge, which attributes speakers by comparing spans.
        """
        out: list[Token] = []
        floor = self.committed_end_ms
        ceiling = self.ceiling_ms
        for token in tokens:
            start = max(token.start_ms, floor)
            end = max(token.end_ms, start)
            if ceiling is not None:
                # Pushing each token past the previous one accumulates, so a
                # long tail of overlapping word timings can ratchet the clock
                # past the end of the audio. Nothing may outlast what was heard.
                start = min(start, ceiling)
                end = min(max(end, start), ceiling)
            out.append(Token(text=token.text, start_ms=start, end_ms=end))
            floor = end
        return out

    def insert(self, hypothesis: list[Token]) -> list[Token]:
        """Feeds one window's transcription. Returns tokens newly committed."""
        pending = self._drop_already_committed(hypothesis)
        self._history.append(pending)
        if len(self._history) > self.agreement:
            self._history.pop(0)
        if len(self._history) < self.agreement:
            return []

        prefix_len = self._agreed_prefix_length(self._history)
        if prefix_len == 0:
            return []

        newly = self._monotonic(self._history[-1][:prefix_len])
        self.committed.extend(newly)
        # Drop the committed prefix from every retained hypothesis so the next
        # pass compares only what is still provisional.
        self._history = [h[prefix_len:] for h in self._history]
        return newly

    def force_commit_before(self, absolute_ms: int) -> list[Token]:
        """Commits pending tokens ending at or before `absolute_ms`, unagreed.

        The escape hatch for the case where the context window has to slide.
        The window can only stay anchored to the last commit while commits keep
        happening; if two passes never agree, audio piles up until the buffer
        hits its cap and the window is forced forward. Once it moves past the
        committed point, consecutive hypotheses start at different words, their
        prefixes stop aligning, and nothing can ever commit again -- the stall
        is permanent, not temporary.

        Forcing here trades the agreement guarantee for liveness on exactly the
        audio about to fall out of the buffer. It is reported as
        `forced_commits` because a high rate means the window and hop are
        mistuned for the material, not that the audio was hard.
        """
        if not self._history:
            return []
        newest = self._history[-1]
        take = [t for t in newest if t.end_ms <= absolute_ms]
        if not take:
            return []
        take = self._monotonic(take)
        self.committed.extend(take)
        keep = len([t for t in newest if t.end_ms <= absolute_ms])
        self._history = [h[keep:] if len(h) >= keep else [] for h in self._history]
        return take

    def flush(self) -> list[Token]:
        """Commits the provisional tail unconditionally.

        Used when VAD reports a speech boundary (section 5: ~700 ms of trailing
        silence forces a segment) and at session end. Without this the last few
        words of every utterance would sit forever in the partial, one pass
        short of agreement.
        """
        if not self._history:
            return []
        tail = self._history[-1]
        self._history.clear()
        if not tail:
            return []
        tail = self._monotonic(tail)
        self.committed.extend(tail)
        return tail

    # -- internals ---------------------------------------------------------

    def _drop_already_committed(self, hypothesis: list[Token]) -> list[Token]:
        """Removes tokens the window re-transcribed from already-committed audio.

        Timestamps do the work, since each window covers audio the previous one
        already saw. The text check behind it catches the case where a pass
        nudges a boundary word's timing by a few milliseconds and it would
        otherwise be committed twice.
        """
        boundary = self.committed_end_ms
        remaining = [t for t in hypothesis if t.end_ms > boundary]

        committed_tail = [_key(t) for t in self.committed[-8:] if _key(t)]
        while remaining and committed_tail:
            head = _key(remaining[0])
            if head and head == committed_tail[-1] and remaining[0].start_ms < boundary:
                remaining = remaining[1:]
                committed_tail = committed_tail[:-1]
            else:
                break
        return remaining

    @staticmethod
    def _agreed_prefix_length(hypotheses: list[list[Token]]) -> int:
        shortest = min(len(h) for h in hypotheses)
        length = 0
        while length < shortest:
            keys = {_key(h[length]) for h in hypotheses}
            if len(keys) != 1 or not next(iter(keys)):
                break
            length += 1
        return length
