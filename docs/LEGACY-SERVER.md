# The legacy Python server

> **This is prior architecture and not the product.** The native macOS app in
> `app/` is the current product. The [README](../README.md) describes it, and
> [ARCHITECTURE.md](ARCHITECTURE.md) gives its design. The Python server is the
> first build of this project. The code is still in the repository and it still
> works. Nothing in the app needs it.

The first build was a FastAPI orchestrator, a resident Swift WhisperKit
sidecar, and a browser capture page. The native app replaces all three.

## The directories

```
server/     FastAPI orchestrator. adapters/ holds the ASR backends.
sidecar/    Swift. A persistent WhisperKit process (asrd).
client/     The browser capture page
eval/       The evaluation set and the scorer
bench/      Latency and RTF measurement
```

**`eval/` and `bench/` are still useful.** `eval/compare_language.py` drives
the Swift command-line tool of the native app, and it produced the language
comparison in [BENCHMARKS.md](BENCHMARKS.md).

## Security: read this first

**The server has no authentication of any kind.** A person who can reach the
port can do all of this:

- Open a session and record audio.
- Read each stored transcript.
- Delete the archived audio.

**Bind the server to the loopback interface with `--host 127.0.0.1`.** To reach
it from another device, use an SSH tunnel, or put TLS and a password in front
of it. [DEPLOY.md](DEPLOY.md) gives a procedure for each case.

**Do not change the bind address to reach the server from another device. Do
not open a port on your router. Do not put the server on the public internet.**

`server/main.py` validates each session id against `SESSION_ID_RE`, because a
session id becomes a filename, an SQLite key and an HTTP header value. **Do not
make that pattern less strict.** The id `../../x` would then write and delete
files outside the archive directory.

**The microphone does not work over plain HTTP.** On plain HTTP,
`getUserMedia` returns undefined for each host except `localhost`, and it gives
no error message. The capture page shows a message when this happens.

## Setup

```bash
cd sidecar && swift build -c release
cd .. && python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/uvicorn server.main:app --host 127.0.0.1 --port 8000
```

Then open <http://127.0.0.1:8000> for the capture page. The browser reads
`127.0.0.1` as a secure origin, thus the microphone works, and nothing listens
on the network.

Python 3.11 or later is necessary. The maintainer developed on 3.14.

## Environment variables

The server reads two environment variables. Both defaults work, and
[`.env.example`](../.env.example) records them and is safe to copy.

| Variable | Function |
| --- | --- |
| `ASR_MODEL` | The WhisperKit model to load at startup. The default is `openai_whisper-large-v3-v20240930_turbo`. `server/models.py` holds the catalogue of ids that this variable accepts. **Read [MODELS.md](MODELS.md) before you change this value.** |
| `ASR_MAX_SESSIONS` | The number of concurrent live sessions. The default is 3. The server refuses a session above the limit with the error `at_capacity`. It does not put the session in a queue. |

```bash
cp .env.example .env
./.venv/bin/uvicorn server.main:app --env-file .env --host 127.0.0.1 --port 8000
```

Nothing reads `.env` automatically. You can also export the variables yourself.
**This project contains no secrets, no accounts and no API keys.**

One session already uses most of one model instance, thus the useful limit is
low. Finding 7 in [FINDINGS.md](FINDINGS.md) gives the measured degradation:
partial latency holds to 4 streams, but the number of commits for each stream
falls by approximately one third.

## The components

### `server/` — the FastAPI orchestrator

`main.py` holds the application. It serves the capture page, a WebSocket at
`/ws` for a live session, and HTTP endpoints for the health check, the model
list, the language list, the model selection, the sessions, the exports, the
audio download, the cleanup pass, the session deletion and the retention pass.

The other modules are `session.py` and `scheduler.py` (the live path),
`commit.py` (the commit policy), `vad.py`, `archive.py` (the audio files),
`store.py` (SQLite), `cleanup.py`, `models.py`, `languages.py`, `registry.py`
and `exports/` (TXT, SRT, VTT and JSON). `adapters/` holds the ASR backends
behind `base.py`.

### `sidecar/` — the Swift WhisperKit process

`sidecar/Sources/asrd/ASRD.swift` is a persistent WhisperKit process. It exists
because a new process for each decode pays the model load cost every time.
Build it with `swift build -c release` before you start the server.

### `client/` — the browser capture page

`client/index.html` and `client/public/` make the capture page. It opens the
microphone, streams the audio to `/ws`, and shows the partial text and the
committed text.

## Tests

```bash
./.venv/bin/pip install -r requirements-dev.txt
./.venv/bin/python -m pytest -q
```

There are 75 tests in `tests/`: `test_cleanup.py`, `test_commit.py`,
`test_models.py`, `test_persistence.py`, `test_protocol.py`,
`test_scheduler.py` and `test_session.py`. They need no model weights and no
microphone.

## Retention

One hour of one session archives approximately 115 MB of audio.

```bash
curl -X POST "http://127.0.0.1:8000/maintenance/retention?days=30"
```

This request deletes each session that is older than `days`, its segments and
its WAV files. **Nothing calls this endpoint automatically.** Add it to a
launchd timer or to a cron job.

The server writes its data to `data/`, which is not in git.

## The evaluation tools

`eval/` compares transcripts to the references in `eval/refs/`. Both `eval/`
and `bench/` read audio from `eval/audio/`, **which is not in git**.

Run `eval/make-synthetic.sh` first to make the synthetic Taglish test clip that
the default paths point to. The script needs no ffmpeg. It uses the `say` and
`afconvert` commands that macOS supplies. **The clip is a speed fixture and not
an accuracy fixture.** macOS ships no Filipino voice, thus the script uses the
Indonesian one. The phonology is close and the acoustics are wrong.

| Tool | Function |
| --- | --- |
| `eval/make-synthetic.sh` | Makes the synthetic Taglish clip. |
| `eval/make_paused.py` | Copies a clip with 1.2 s of silence after each sentence, so that utterance finalization has something to do. |
| `eval/replay.py` | Replays the clips through the live pipeline and writes one hypothesis file for each clip. |
| `eval/score.py` | Scores the hypotheses against the references. |
| `eval/langscore.py` | Scores word by word, split into Filipino and English, and at each code-switch point. |
| `eval/compare_language.py` | Runs forced `tl` against `auto` over the manifest and prints one table. It drives the Swift command-line tool. |
| `eval/manifest.json` | The clip list and the reference for each clip. |

```bash
./.venv/bin/python eval/replay.py --out /tmp/off --offline
./.venv/bin/python eval/replay.py --out /tmp/live --hop 1500
./.venv/bin/python eval/score.py /tmp/off  --label offline
./.venv/bin/python eval/score.py /tmp/live --label live
```

## The benchmark tools

| Tool | Function |
| --- | --- |
| `bench/latency.py` | Sweeps window sizes through the ASR adapter and reports the RTF for each window. |
| `bench/load.py` | Streams a clip over several concurrent WebSockets and reports how far behind the audio each committed transcript runs. |

```bash
./.venv/bin/python bench/latency.py                       # synthetic audio
./.venv/bin/python bench/latency.py eval/audio/sample.wav # real audio
./.venv/bin/python bench/load.py --streams 1 2 3 4 --seconds 30
```

**Give `bench/latency.py` real 16 kHz mono WAV where you can.** Silence and
tones decode to almost no tokens, and decode time scales with the token count,
thus synthetic audio flatters the result.

For `bench/load.py`, set `ASR_MAX_SESSIONS` high enough. Streams above the cap
are refused, which is the correct behaviour and not what the test measures.

## Related documents

- [DEPLOY.md](DEPLOY.md) — how to run the server on the same Mac, through an
  SSH tunnel, or behind a TLS proxy.
- [BENCHMARKS.md](BENCHMARKS.md) — the measurements, including the historical
  ones from this server.
- [FINDINGS.md](FINDINGS.md) — the numbered findings. Findings 1 to 8 came from
  this server.
- [PLAN.md](PLAN.md) — the original build plan. It is design history.
