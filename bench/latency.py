"""Phase 1 exit criterion: what is the real-time factor on this machine?

Sweeps window sizes through the ASR adapter and reports RTF per window. The
numbers feed section 7 directly -- the context window can only be as wide as
RTF allows, and the hop interval has to exceed the inference time for that
window or the queue backs up.

    ./.venv/bin/python bench/latency.py                       # synthetic audio
    ./.venv/bin/python bench/latency.py eval/audio/sample.wav # real audio

Real 16 kHz mono WAV is strongly preferred: silence and tones decode to almost
no tokens, and decode time scales with token count, so synthetic audio flatters
the RTF. Treat the synthetic run as a floor, not a measurement.
"""

from __future__ import annotations

import asyncio
import math
import statistics
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from server.adapters.whisperkit import WhisperKitAdapter  # noqa: E402
from server.session import SAMPLE_RATE, ms_to_bytes  # noqa: E402

WINDOWS_MS = [2_500, 5_000, 10_000, 15_000, 30_000]
REPEATS = 3


def synthetic(ms: int) -> bytes:
    n = int(SAMPLE_RATE * ms / 1000)
    return b"".join(
        struct.pack("<h", int(0.05 * 32767 * math.sin(2 * math.pi * 220 * i / SAMPLE_RATE)))
        for i in range(n)
    )


def load_wav(path: Path) -> bytes:
    with wave.open(str(path), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise SystemExit(
                f"{path}: need mono 16-bit PCM, got {w.getnchannels()}ch "
                f"{w.getsampwidth() * 8}-bit"
            )
        if w.getframerate() != SAMPLE_RATE:
            raise SystemExit(
                f"{path}: need {SAMPLE_RATE} Hz, got {w.getframerate()}. "
                f"Convert with: ffmpeg -i in.wav -ac 1 -ar {SAMPLE_RATE} -c:a pcm_s16le out.wav"
            )
        return w.readframes(w.getnframes())


async def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if source is not None:
        audio = load_wav(source)
        label = f"{source.name} ({len(audio) / (SAMPLE_RATE * 2):.1f}s)"
    else:
        audio = None
        label = "synthetic tone (RTF floor only)"

    adapter = WhisperKitAdapter()
    print(f"source : {label}")
    print(f"model  : {adapter.model}")
    print("loading model (first run downloads it)...", flush=True)
    await adapter.start()
    print(f"loaded in {adapter.load_ms} ms\n")

    header = f"{'window':>9} {'runs':>5} {'median':>9} {'min':>8} {'max':>8} {'RTF':>7} {'chars':>6}"
    print(header)
    print("-" * len(header))

    for window_ms in WINDOWS_MS:
        need = ms_to_bytes(window_ms)
        if audio is not None:
            if len(audio) < need:
                print(f"{window_ms/1000:>7.1f}s  (audio shorter than window, skipped)")
                continue
            pcm = audio[:need]
        else:
            pcm = synthetic(window_ms)

        timings, chars = [], 0
        for _ in range(REPEATS):
            result = await adapter.transcribe(pcm, "tl")
            timings.append(result.infer_ms)
            chars = len(result.text)

        median = statistics.median(timings)
        print(
            f"{window_ms/1000:>8.1f}s {REPEATS:>5} {median:>8.0f}ms {min(timings):>7.0f}ms "
            f"{max(timings):>7.0f}ms {median/window_ms:>7.3f} {chars:>6}"
        )

    await adapter.stop()
    print(
        "\nRTF < 1.0 means faster than real time. For section 7's defaults the\n"
        "15 s window must finish well inside the 1.0 s hop, i.e. RTF < 0.067 at\n"
        "15 s, or hops start colliding and the scheduler drops them."
    )


if __name__ == "__main__":
    asyncio.run(main())
