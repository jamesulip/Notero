"""Phase 3 load test: how does latency degrade with concurrent streams?

Each simulated client streams the same clip at real-time pace over its own
WebSocket. The number that matters is *lag*: how far behind the audio the
committed transcript is running. A stream that stays near zero is keeping up;
one that climbs is falling behind and will keep falling behind.

    ./.venv/bin/python bench/load.py --streams 1 2 3 4 --seconds 30

Run the server with ASR_MAX_SESSIONS set high enough, or streams past the cap
are refused (which is the correct behaviour, just not what this measures).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
import wave
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[1]
FRAME_MS = 100
SAMPLE_RATE = 16_000


async def one_stream(url: str, audio: bytes, index: int) -> dict:
    lags: list[float] = []
    partial_lags: list[float] = []
    finals = 0
    sent_ms = 0.0
    frame = int(SAMPLE_RATE * 2 * FRAME_MS / 1000)

    async with websockets.connect(url, max_size=None) as ws:
        await ws.send(json.dumps({"type": "start", "language": "tl",
                                  "session_id": f"load-{index}"}))
        started = time.monotonic()
        done = asyncio.Event()

        async def reader():
            nonlocal finals
            async for raw in ws:
                m = json.loads(raw)
                if m["type"] == "partial" and m.get("text"):
                    # Section 14's number: how long until *something* appears
                    # for the audio just sent. This is the muted-text latency.
                    partial_lags.append((time.monotonic() - started) - sent_ms / 1000)
                elif m["type"] == "final":
                    finals += 1
                    # How far behind the audio this commit landed.
                    lags.append((time.monotonic() - started)
                                - m["segment"]["end_ms"] / 1000)
                elif m["type"] == "error" and m.get("code") == "at_capacity":
                    print(f"  stream {index}: refused ({m['message']})")
                    done.set(); return
                elif m["type"] == "status" and m["state"] == "idle":
                    done.set(); return

        task = asyncio.create_task(reader())
        for i in range(0, len(audio), frame):
            await ws.send(audio[i:i + frame])
            sent_ms = (i + frame) / (SAMPLE_RATE * 2) * 1000
            await asyncio.sleep(FRAME_MS / 1000)
        await ws.send(json.dumps({"type": "stop"}))
        try:
            await asyncio.wait_for(done.wait(), timeout=120)
        except asyncio.TimeoutError:
            pass
        task.cancel()

    return {"index": index, "finals": finals, "lags": lags,
            "partial_lags": partial_lags}


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="ws://127.0.0.1:8000/ws")
    parser.add_argument("--audio", type=Path,
                        default=ROOT / "eval/audio/synthetic-taglish.wav")
    parser.add_argument("--streams", type=int, nargs="+", default=[1, 2, 3, 4])
    parser.add_argument("--seconds", type=float, default=30.0)
    args = parser.parse_args()

    with wave.open(str(args.audio), "rb") as w:
        audio = w.readframes(int(args.seconds * SAMPLE_RATE))

    print(f"clip {len(audio) / (SAMPLE_RATE * 2):.0f}s, real-time pacing\n")
    header = (f"{'streams':>8} {'finals/ea':>10} {'partial p50':>12} "
              f"{'partial p90':>12} {'final p50':>11} {'final max':>11}")
    print(header)
    print("-" * len(header))

    for count in args.streams:
        results = await asyncio.gather(
            *(one_stream(args.url, audio, i) for i in range(count))
        )
        lags = sorted(lag for r in results for lag in r["lags"])
        plags = sorted(lag for r in results for lag in r["partial_lags"])
        finals = sum(r["finals"] for r in results)
        if not lags and not plags:
            print(f"{count:>8} {finals:>10}   (nothing came back -- refused or stalled)")
            continue
        pc = lambda xs, q: xs[min(len(xs) - 1, int(len(xs) * q))] if xs else float("nan")
        print(f"{count:>8} {finals / count:>10.1f} {pc(plags, .5):>11.2f}s "
              f"{pc(plags, .9):>11.2f}s {pc(lags, .5):>10.2f}s "
              f"{(max(lags) if lags else 0):>10.2f}s")
        await asyncio.sleep(2)      # let the server settle between runs

    print("\npartial = how long until text appears at all (section 14 targets\n"
          "1-1.5s). final = how far behind the audio a commit landed. Flat across\n"
          "stream counts means headroom; climbing means the model is saturated.\n"
          "finals/ea falling is the clearer signal: the same audio yielding fewer\n"
          "commits per stream means hops are being dropped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
