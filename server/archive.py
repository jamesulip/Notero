"""Session audio archiver.

Writes 16 kHz mono PCM to disk (~115 MB/hour). Section 5: this exists solely so
diarization and re-transcription are possible after the fact. Without it both
are impossible -- Phase 6 has nothing to read and a bad transcript cannot be
re-run with better settings.

Frames are appended raw and the RIFF header is written on close, so a crashed
session leaves a file that is recoverable rather than one that is merely
truncated.
"""

from __future__ import annotations

import asyncio
import logging
import struct
from pathlib import Path

log = logging.getLogger("asr.archive")

SAMPLE_RATE = 16_000
CHANNELS = 1
BITS = 16


def _riff_header(data_bytes: int) -> bytes:
    byte_rate = SAMPLE_RATE * CHANNELS * BITS // 8
    block_align = CHANNELS * BITS // 8
    return b"".join([
        b"RIFF", struct.pack("<I", 36 + data_bytes), b"WAVE",
        b"fmt ", struct.pack("<IHHIIHH", 16, 1, CHANNELS, SAMPLE_RATE,
                             byte_rate, block_align, BITS),
        b"data", struct.pack("<I", data_bytes),
    ])


class WavArchiver:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self.path, "wb")
        self._file.write(_riff_header(0))     # placeholder, rewritten on close
        self._bytes = 0
        self._closed = False

    @property
    def duration_ms(self) -> int:
        return int(self._bytes / (SAMPLE_RATE * CHANNELS * BITS // 8) * 1000)

    async def write(self, pcm: bytes) -> None:
        if self._closed:
            return
        await asyncio.to_thread(self._write, pcm)

    def _write(self, pcm: bytes) -> None:
        self._file.write(pcm)
        self._bytes += len(pcm)

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        await asyncio.to_thread(self._close)
        log.info("archived %.1f MB to %s", self._bytes / 1e6, self.path)

    def _close(self) -> None:
        self._file.flush()
        self._file.seek(0)
        self._file.write(_riff_header(self._bytes))
        self._file.close()


def repair(path: Path) -> int:
    """Rewrites the header of a WAV left behind by a crash. Returns byte count."""
    size = path.stat().st_size - 44
    if size <= 0:
        return 0
    with open(path, "r+b") as fh:
        fh.write(_riff_header(size))
    return size
