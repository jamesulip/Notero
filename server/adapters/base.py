"""ASR adapter interface.

Plan section 5 specifies:

    transcribe(pcm: bytes, language: str, prompt: str | None) -> list[Token]

One deviation: transcribe returns a `Result` wrapping the tokens together with
audio/inference durations, rather than a bare list. Phase 1 exists to measure
real-time factor, so timing has to come back from the call that produced it --
stashing it on the adapter would race as soon as the scheduler runs hops
concurrently. Timing is not a WhisperKit concept, so this does not leak the
backend into the orchestrator and the MLX swap stays intact.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Token:
    """One decoded token. Times are relative to the start of the supplied PCM."""

    text: str
    start_ms: int
    end_ms: int

    def __str__(self) -> str:
        return self.text


@dataclass(frozen=True)
class Result:
    tokens: list[Token] = field(default_factory=list)
    audio_ms: int = 0
    infer_ms: int = 0

    @property
    def text(self) -> str:
        return "".join(t.text for t in self.tokens).strip()

    @property
    def rtf(self) -> float:
        """Real-time factor. <1.0 means faster than real time."""
        return (self.infer_ms / self.audio_ms) if self.audio_ms else 0.0


class ASRAdapter(ABC):
    """Backends implement this and nothing more."""

    @abstractmethod
    async def start(self) -> None:
        """Load the model. Must be idempotent."""

    @abstractmethod
    async def stop(self) -> None:
        ...

    @abstractmethod
    async def transcribe(
        self,
        pcm: bytes,
        language: str,
        prompt: str | None = None,
    ) -> Result:
        """Transcribe PCM16LE mono 16 kHz audio."""
