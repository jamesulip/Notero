"""WhisperKit backend, driven as a persistent Swift sidecar.

The sidecar (`sidecar/Sources/asrd`) loads the CoreML model once and stays
resident. Each request is a 4-byte big-endian header length, a JSON header
carrying the PCM byte count plus this request's language and prompt, and then
the PCM16LE itself. Replies are NDJSON.

Language rides with the request rather than being fixed at launch, because the
model is shared across sessions and each session chooses its own.
"""

from __future__ import annotations

import asyncio
import json
import logging
import struct
from pathlib import Path

from .base import ASRAdapter, Result, Token

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parents[2]
SIDECAR_BIN = ROOT / "sidecar" / ".build" / "release" / "asrd"
MODELS_DIR = ROOT / "models"

# Section 2 locks "large-v3-turbo". In WhisperKit's zoo the `_turbo` suffix marks
# a compute variant, not the turbo model -- OpenAI's large-v3-turbo is published
# under the date-stamped name. See docs/ENVIRONMENT.md; picking
# `openai_whisper-large-v3_turbo` here would silently load the full 1.5B model.
DEFAULT_MODEL = "openai_whisper-large-v3-v20240930_turbo"


class SidecarError(RuntimeError):
    pass


class WhisperKitAdapter(ASRAdapter):
    def __init__(
        self,
        model: str = DEFAULT_MODEL,
        language: str = "tl",
        binary: Path = SIDECAR_BIN,
        models_dir: Path = MODELS_DIR,
        fallbacks: int = 2,
        extra_args: list[str] | None = None,
    ) -> None:
        self.model = model
        self.language = language
        self.binary = binary
        self.models_dir = models_dir
        # Section 7 says temperature 0 with no fallback ladder. Taken literally
        # that is silent data loss: WhisperKit discards any window whose first
        # token looks improbable, and with nothing to fall back to the window
        # returns empty rather than being retried. Sliding windows start
        # mid-word every hop, so this fires often. See docs/FINDINGS.md.
        self.fallbacks = fallbacks
        self.extra_args = extra_args or []
        self._proc: asyncio.subprocess.Process | None = None
        self._lock = asyncio.Lock()
        self._stderr_task: asyncio.Task | None = None
        self.load_ms: int | None = None

    # -- lifecycle ---------------------------------------------------------

    async def start(self) -> None:
        if self._proc is not None and self._proc.returncode is None:
            return
        if not self.binary.exists():
            raise SidecarError(
                f"sidecar binary missing at {self.binary}. "
                "Build it with: cd sidecar && swift build -c release"
            )
        self.models_dir.mkdir(parents=True, exist_ok=True)

        log.info("starting sidecar: %s (model=%s)", self.binary, self.model)
        self._proc = await asyncio.create_subprocess_exec(
            str(self.binary),
            "--model", self.model,
            "--language", self.language,
            "--download-base", str(self.models_dir),
            "--fallbacks", str(self.fallbacks),
            *self.extra_args,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self._stderr_task = asyncio.create_task(self._drain_stderr())

        # First model load also downloads ~1.6 GB, so allow a generous window.
        ready = await self._read_message(timeout=1800)
        if ready.get("type") != "ready":
            raise SidecarError(f"sidecar did not become ready: {ready}")
        self.load_ms = ready.get("load_ms")
        log.info("sidecar ready in %s ms", self.load_ms)

    async def stop(self) -> None:
        proc = self._proc
        self._proc = None
        if proc is None or proc.returncode is not None:
            return
        try:
            if proc.stdin is not None:
                proc.stdin.write(struct.pack(">I", 0))  # 0 length == shutdown
                await proc.stdin.drain()
                proc.stdin.close()
            await asyncio.wait_for(proc.wait(), timeout=10)
        except (asyncio.TimeoutError, ConnectionResetError, BrokenPipeError):
            proc.kill()
            await proc.wait()
        finally:
            if self._stderr_task is not None:
                self._stderr_task.cancel()

    # -- transcription -----------------------------------------------------

    async def transcribe(
        self,
        pcm: bytes,
        language: str,
        prompt: str | None = None,
    ) -> Result:
        if self._proc is None or self._proc.returncode is not None:
            raise SidecarError("sidecar is not running")
        if not pcm:
            return Result()

        header = json.dumps({
            "bytes": len(pcm),
            "language": language or self.language,
            "prompt": prompt,
        }).encode("utf-8")

        # One model instance: hops serialise here. The Phase 3 scheduler owns
        # the drop policy; this lock only guarantees framing integrity.
        async with self._lock:
            assert self._proc.stdin is not None
            self._proc.stdin.write(struct.pack(">I", len(header)) + header + pcm)
            await self._proc.stdin.drain()
            message = await self._read_message(timeout=300)

        if message.get("type") == "error":
            raise SidecarError(f"{message.get('code')}: {message.get('message')}")

        tokens = [
            Token(text=w["text"], start_ms=int(w["start_ms"]), end_ms=int(w["end_ms"]))
            for w in message.get("words", [])
        ]
        return Result(
            tokens=tokens,
            audio_ms=int(message.get("audio_ms", 0)),
            infer_ms=int(message.get("infer_ms", 0)),
            language=message.get("language"),
        )

    # -- plumbing ----------------------------------------------------------

    async def _read_message(self, timeout: float) -> dict:
        """Reads the next NDJSON object, skipping any non-protocol chatter."""
        proc = self._proc
        assert proc is not None and proc.stdout is not None
        deadline = asyncio.get_running_loop().time() + timeout
        while True:
            remaining = deadline - asyncio.get_running_loop().time()
            if remaining <= 0:
                raise SidecarError("timed out waiting for sidecar")
            line = await asyncio.wait_for(proc.stdout.readline(), timeout=remaining)
            if not line:
                raise SidecarError(f"sidecar exited (code {proc.returncode})")
            text = line.decode("utf-8", "replace").strip()
            if not text.startswith("{"):
                if text:
                    log.debug("sidecar stdout noise: %s", text)
                continue
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                log.debug("sidecar stdout non-JSON: %s", text)

    async def _drain_stderr(self) -> None:
        proc = self._proc
        if proc is None or proc.stderr is None:
            return
        try:
            while line := await proc.stderr.readline():
                log.info("sidecar: %s", line.decode("utf-8", "replace").rstrip())
        except asyncio.CancelledError:
            pass
