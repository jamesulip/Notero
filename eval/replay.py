"""Replay eval audio through the live pipeline and write hypotheses to score.

Phase 2's exit criterion is "live WER within ~5 points of your offline number".
That comparison is only meaningful if the live number comes from the real
streaming path -- ring buffer, VAD gating, commit policy and all -- rather than
from a single offline call. This runs exactly that path, without a browser or a
socket, and writes one hypothesis file per clip.

    ./.venv/bin/python eval/replay.py --out /tmp/live      # live path
    ./.venv/bin/python eval/replay.py --out /tmp/off --offline

Then:

    ./.venv/bin/python eval/score.py /tmp/off --label offline
    ./.venv/bin/python eval/score.py /tmp/live --label live

Default pacing is real time, because dropped hops are part of what the live
path costs you; `--fast` removes that and will flatter the result.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server.main as server_main  # noqa: E402
from server.adapters.whisperkit import WhisperKitAdapter  # noqa: E402
from server.main import Pipeline  # noqa: E402
from server.scheduler import InferenceScheduler  # noqa: E402
from server.session import SAMPLE_RATE, Session  # noqa: E402

EVAL_DIR = Path(__file__).resolve().parent
FRAME_MS = 100


def load_wav(path: Path) -> bytes:
    with wave.open(str(path), "rb") as w:
        if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, SAMPLE_RATE):
            raise SystemExit(
                f"{path}: need mono 16-bit {SAMPLE_RATE} Hz. Convert with:\n"
                f"  ffmpeg -i {path} -ac 1 -ar {SAMPLE_RATE} -c:a pcm_s16le out.wav"
            )
        return w.readframes(w.getnframes())


async def replay_live(adapter, audio: bytes, language: str, fast: bool,
                      hop_ms: int = 1000, context_ms: int = 15000,
                      agreement: int = 2) -> str:
    collected: list[str] = []
    errors: list[str] = []

    async def send(payload: dict) -> None:
        if payload.get("type") == "final":
            collected.append(payload["segment"]["text"])
        elif payload.get("type") == "error":
            # A harness that ignores these writes an empty hypothesis and
            # scores it as ~100% WER with no hint that nothing ever ran.
            errors.append(payload.get("message", payload.get("code", "?")))

    # Pipeline hops go through the module-level scheduler, exactly as they do
    # under the server. It has to exist here and the session has to be
    # registered, or every hop dies with an AssertionError that the pipeline's
    # error handling turns into an error frame.
    scheduler = InferenceScheduler(adapter, max_sessions=1)
    await scheduler.start()
    server_main.scheduler = scheduler
    scheduler.register("replay")

    session = Session(session_id="replay", language=language,
                      hop_ms=hop_ms, context_ms=context_ms)
    pipeline = Pipeline(session, send, agreement=agreement)

    try:
        frame = int(SAMPLE_RATE * 2 * FRAME_MS / 1000)
        for i in range(0, len(audio), frame):
            await pipeline.feed(audio[i:i + frame])
            if not fast:
                await asyncio.sleep(FRAME_MS / 1000)
        await pipeline.finish()
    finally:
        await scheduler.stop()
        server_main.scheduler = None

    if errors:
        raise SystemExit(
            f"replay produced {len(errors)} error frame(s); first: {errors[0]}"
        )

    s = session.stats
    print(f"    {s.hops} hops, {s.dropped_hops} dropped, {s.empty_results} empty, "
          f"{s.forced_commits} forced, {s.boundaries} boundaries, RTF {s.mean_rtf:.3f}")
    return " ".join(collected)


async def replay_offline(adapter, audio: bytes, language: str) -> str:
    """One call over the whole clip -- the ceiling the live path is measured against."""
    result = await adapter.transcribe(audio, language)
    return result.text


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=EVAL_DIR / "manifest.json")
    parser.add_argument("--language", default="tl")
    parser.add_argument("--offline", action="store_true",
                        help="single whole-clip call instead of the streaming path")
    parser.add_argument("--fast", action="store_true",
                        help="replay as fast as possible (flatters the live result)")
    parser.add_argument("--hop", type=int, default=1000, help="hop interval in ms")
    parser.add_argument("--context", type=int, default=15000, help="context window in ms")
    parser.add_argument("--agreement", type=int, default=2, help="passes that must agree")
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"no manifest at {args.manifest} -- see eval/score.py for its shape",
              file=sys.stderr)
        return 1

    entries = json.loads(args.manifest.read_text())
    args.out.mkdir(parents=True, exist_ok=True)

    adapter = WhisperKitAdapter()
    print(f"loading {adapter.model}...")
    await adapter.start()
    server_main.adapter = adapter          # Pipeline reads the module-level adapter

    mode = ("offline" if args.offline else
            f"live hop={args.hop}ms ctx={args.context}ms n={args.agreement}")
    for entry in entries:
        audio = load_wav(EVAL_DIR / entry["audio"])
        print(f"  {entry['id']} ({len(audio) / (SAMPLE_RATE * 2):.1f}s, {mode})")
        text = (await replay_offline(adapter, audio, args.language) if args.offline
                else await replay_live(adapter, audio, args.language, args.fast,
                                       args.hop, args.context, args.agreement))
        (args.out / f"{entry['id']}.txt").write_text(text)

    await adapter.stop()
    print(f"\nwrote {len(entries)} hypotheses to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
