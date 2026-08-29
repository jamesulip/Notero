# Live Tagalog/Taglish Transcription Server

Private, local, real-time Tagalog/Taglish transcription. Audio never leaves the
machine. See [docs/PLAN.md](docs/PLAN.md) for the full build plan and
[docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) for verified machine facts.

**Status: Phase 1 complete.** Fixed 5 s chunks, no VAD, no overlap, no commit
policy — the point of this phase was to measure the real-time factor, not to
transcribe well. Audio streams end to end and words come back.

Measured RTF: **0.059** at a 15 s window, **0.103** at 5 s chunks.

Phase 1 turned up three things that change the plan — a model-ID trap, silent
decode drops, and a concurrency ceiling well below section 7's cap of 3. Read
[docs/FINDINGS.md](docs/FINDINGS.md) before starting Phase 2.

## Layout

```
server/     FastAPI orchestrator; adapters/ holds the ASR backends
sidecar/    Swift: persistent WhisperKit process (asrd)
client/     Browser capture page; worklet in public/
eval/       Eval set + scorer -- Phase 2's exit criterion depends on it
bench/      Latency / RTF measurement
```

## Why a Swift sidecar

WhisperKit is Swift, and loading the CoreML model takes seconds. Shelling out to
`whisperkit-cli` per chunk would reload the model every hop and make the RTF
number meaningless, so `asrd` loads once and stays resident, speaking
length-prefixed PCM in and NDJSON out. Plan section 11 already assumes a Python
orchestrator plus a Swift ASR process; the open fork is whether *VAD* moves
across too, which is a Phase 2 decision.

## Setup

Build the sidecar (once):

```bash
cd sidecar && swift build -c release
```

Python environment:

```bash
python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
```

## Run

```bash
./.venv/bin/uvicorn server.main:app --host 0.0.0.0 --port 8000
```

Then open <http://localhost:8000>. The first start downloads ~1.6 GB of CoreML
weights into `models/`.

Microphone capture needs a secure context. `localhost` is fine; testing from a
phone will fail silently until TLS lands in Phase 3.

## Measure

```bash
./.venv/bin/python bench/latency.py eval/audio/your-clip.wav
```

Use real 16 kHz mono speech. Synthetic tones decode to almost no tokens, and
decode time scales with token count, so they only give an RTF floor.

## Score

```bash
./.venv/bin/python eval/score.py <hyp-dir> --label offline
```

Needs `eval/manifest.json` and `eval/refs/<id>.txt`. Results split by
tagalog / english / mixed, because section 3 predicts Taglish degrades worst
under streaming and a pooled number would hide it.

## Model

Locked to `openai_whisper-large-v3-v20240930_turbo`. WhisperKit's `_turbo`
suffix marks a compute variant, **not** OpenAI's large-v3-turbo model —
`openai_whisper-large-v3_turbo` is the full 1.5B large-v3 and is 5.3x heavier in
the decoder. See docs/ENVIRONMENT.md.
