"""Silero VAD, wrapped for streaming use.

Section 5 gives it two jobs, both essential:

  1. Skip inference during silence. Turbo hallucinates confidently on silence,
     and it is the cheapest quality win available.
  2. Force a segment boundary after ~700 ms of trailing silence, flushing the
     provisional tail to final.

Silero consumes fixed 512-sample frames at 16 kHz (32 ms). Audio arrives in
whatever sizes the client sends, so this buffers and emits whole frames. Cost is
about 2.8 ms per second of audio -- small enough to run inline.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

FRAME_SAMPLES = 512
SAMPLE_RATE = 16_000
FRAME_MS = int(FRAME_SAMPLES / SAMPLE_RATE * 1000)  # 32


@dataclass(frozen=True)
class VadState:
    last_prob: float
    speech_ms: int
    trailing_silence_ms: int
    frames: int


class SileroVAD:
    """One instance per session -- the underlying model carries RNN state."""

    def __init__(self, threshold: float = 0.5, onnx: bool = True) -> None:
        from silero_vad import load_silero_vad  # imported late; loads a model

        self.threshold = threshold
        self._model = load_silero_vad(onnx=onnx)
        self._buffer = bytearray()
        self._speech_ms = 0
        self._trailing_silence_ms = 0
        self._frames = 0
        self._last_prob = 0.0

    def push(self, pcm: bytes) -> VadState:
        """Feeds PCM16LE mono 16 kHz; processes whatever whole frames it can."""
        import torch

        self._buffer.extend(pcm)
        frame_bytes = FRAME_SAMPLES * 2

        while len(self._buffer) >= frame_bytes:
            raw = bytes(self._buffer[:frame_bytes])
            del self._buffer[:frame_bytes]
            samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            prob = float(self._model(torch.from_numpy(samples), SAMPLE_RATE))

            self._last_prob = prob
            self._frames += 1
            if prob >= self.threshold:
                self._speech_ms += FRAME_MS
                self._trailing_silence_ms = 0
            else:
                self._trailing_silence_ms += FRAME_MS

        return self.state

    @property
    def state(self) -> VadState:
        return VadState(
            last_prob=self._last_prob,
            speech_ms=self._speech_ms,
            trailing_silence_ms=self._trailing_silence_ms,
            frames=self._frames,
        )

    def clear_speech_counter(self) -> None:
        """Resets the speech tally without disturbing the model's RNN state.

        Called after a boundary flush so the next segment's speech is measured
        from zero, while continuity of the underlying model is preserved.
        """
        self._speech_ms = 0
