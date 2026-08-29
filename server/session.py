"""Per-connection state: rolling context window and hop scheduling.

Phase 2 replaces Phase 1's fixed non-overlapping chunker with the rolling ring
buffer LocalAgreement needs. Every hop hands the model the whole trailing
context, deliberately re-transcribing audio it has already seen -- wasteful in
FLOPs, but it is the only way to keep the context Whisper needs to decide
between Tagalog and English (section 3).
"""

from __future__ import annotations

from dataclasses import dataclass, field

SAMPLE_RATE = 16_000
BYTES_PER_SAMPLE = 2
BYTES_PER_MS = SAMPLE_RATE * BYTES_PER_SAMPLE // 1000  # 32


def ms_to_bytes(ms: int) -> int:
    return int(SAMPLE_RATE * BYTES_PER_SAMPLE * ms / 1000)


def bytes_to_ms(n: int) -> int:
    return int(n / (SAMPLE_RATE * BYTES_PER_SAMPLE) * 1000)


class RingBuffer:
    """Holds the trailing `context_ms` of audio and tracks absolute time.

    The absolute timeline matters: token timestamps come back relative to the
    window, but segments, exports and (later) diarization all need positions
    relative to the start of the session.
    """

    def __init__(self, context_ms: int = 15_000) -> None:
        self.context_ms = context_ms
        self._buffer = bytearray()
        self._discarded_bytes = 0

    @property
    def capacity_bytes(self) -> int:
        return ms_to_bytes(self.context_ms)

    def push(self, pcm: bytes) -> None:
        self._buffer.extend(pcm)
        overflow = len(self._buffer) - self.capacity_bytes
        if overflow > 0:
            del self._buffer[:overflow]
            self._discarded_bytes += overflow

    def trim_to(self, absolute_ms: int) -> None:
        """Drops audio before `absolute_ms`, anchoring the window to a commit.

        This is what makes LocalAgreement work. If the window is allowed to
        slide freely, consecutive hypotheses begin at different points in the
        audio, their prefixes describe different words, and the agreed prefix is
        empty forever -- the commit rate collapses to nothing while the
        provisional tail grows without bound.

        Anchoring the window start to the last committed word keeps consecutive
        passes describing the same audio from the same origin, which is the
        precondition the whole policy rests on. `context_ms` still caps the
        buffer, so a long stretch without agreement degrades to a sliding
        window rather than growing unbounded.
        """
        target = ms_to_bytes(absolute_ms) - self._discarded_bytes
        if target <= 0:
            return
        drop = min(target, len(self._buffer))
        del self._buffer[:drop]
        self._discarded_bytes += drop

    @property
    def total_ms(self) -> int:
        """Audio received since the session began."""
        return bytes_to_ms(self._discarded_bytes + len(self._buffer))

    @property
    def window_start_ms(self) -> int:
        """Absolute position of the first sample currently held."""
        return bytes_to_ms(self._discarded_bytes)

    @property
    def duration_ms(self) -> int:
        return bytes_to_ms(len(self._buffer))

    def window(self) -> tuple[bytes, int]:
        """The current context and its absolute start."""
        return bytes(self._buffer), self.window_start_ms


@dataclass
class Stats:
    hops: int = 0
    skipped_silent: int = 0
    dropped_hops: int = 0
    forced_commits: int = 0
    empty_results: int = 0
    boundaries: int = 0
    total_audio_ms: int = 0
    total_infer_ms: int = 0

    @property
    def mean_rtf(self) -> float:
        return (self.total_infer_ms / self.total_audio_ms) if self.total_audio_ms else 0.0


@dataclass
class Session:
    """Everything about one connection except the I/O."""

    session_id: str
    language: str = "tl"
    prompt: str | None = None
    context_ms: int = 15_000
    # Section 7 starts at 1.0 s and says to raise it if the queue backs up. It
    # does: a 15 s window costs ~0.9 s, so at a 1 s hop two thirds of hops are
    # dropped and consecutive passes stop being consecutive. Measured on the
    # replay harness, 1.5 s lands live WER within 1.6 points of offline; 1.0 s
    # is 14 points off, and 2.0 s is worse again because the buffer outruns
    # agreement and forces commits instead. See docs/FINDINGS.md.
    hop_ms: int = 1_500
    silence_boundary_ms: int = 700
    min_speech_ms: int = 120

    ring: RingBuffer = field(init=False)
    stats: Stats = field(default_factory=Stats)
    next_segment_id: int = 0
    _ms_since_hop: int = 0
    _boundary_pending: bool = False

    def __post_init__(self) -> None:
        self.ring = RingBuffer(self.context_ms)

    def push_audio(self, pcm: bytes) -> None:
        self.ring.push(pcm)
        self._ms_since_hop += bytes_to_ms(len(pcm))

    def due_for_hop(self) -> bool:
        return self._ms_since_hop >= self.hop_ms

    def mark_hop(self) -> None:
        self._ms_since_hop = 0

    def allocate_segment_id(self) -> int:
        self.next_segment_id += 1
        return self.next_segment_id
