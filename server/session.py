"""Per-connection state.

Phase 1 only: a fixed, non-overlapping chunker. Phase 2 replaces this with the
rolling ring buffer (15 s context, 1 s hop) that LocalAgreement-2 needs. The
seam is deliberate -- nothing outside this module should assume chunks are
non-overlapping.
"""

from __future__ import annotations

from dataclasses import dataclass, field

SAMPLE_RATE = 16_000
BYTES_PER_SAMPLE = 2


def ms_to_bytes(ms: int) -> int:
    return int(SAMPLE_RATE * BYTES_PER_SAMPLE * ms / 1000)


def bytes_to_ms(n: int) -> int:
    return int(n / (SAMPLE_RATE * BYTES_PER_SAMPLE) * 1000)


@dataclass
class FixedChunker:
    """Accumulates PCM and yields fixed-size chunks. Phase 1 scaffolding."""

    chunk_ms: int = 5_000
    _buffer: bytearray = field(default_factory=bytearray)
    _emitted_bytes: int = 0

    @property
    def chunk_bytes(self) -> int:
        return ms_to_bytes(self.chunk_ms)

    def push(self, pcm: bytes) -> list[tuple[bytes, int]]:
        """Adds audio; returns any complete (chunk, start_ms) pairs."""
        self._buffer.extend(pcm)
        out: list[tuple[bytes, int]] = []
        while len(self._buffer) >= self.chunk_bytes:
            chunk = bytes(self._buffer[: self.chunk_bytes])
            del self._buffer[: self.chunk_bytes]
            out.append((chunk, bytes_to_ms(self._emitted_bytes)))
            self._emitted_bytes += self.chunk_bytes
        return out

    def flush(self) -> tuple[bytes, int] | None:
        """Returns the trailing partial chunk, if any, at session end."""
        if not self._buffer:
            return None
        chunk = bytes(self._buffer)
        start_ms = bytes_to_ms(self._emitted_bytes)
        self._emitted_bytes += len(chunk)
        self._buffer.clear()
        return chunk, start_ms


@dataclass
class Session:
    session_id: str
    language: str = "tl"
    prompt: str | None = None
    chunker: FixedChunker = field(default_factory=FixedChunker)
    next_segment_id: int = 0
    total_audio_ms: int = 0
    total_infer_ms: int = 0
    chunks: int = 0

    def allocate_segment_id(self) -> int:
        self.next_segment_id += 1
        return self.next_segment_id

    @property
    def mean_rtf(self) -> float:
        return (self.total_infer_ms / self.total_audio_ms) if self.total_audio_ms else 0.0
