# Live Tagalog/Taglish Transcription Server — Build Plan v2

> **Design history.** The original build plan for the Python server, kept as
> written. The project diverged from it: the native macOS app under `app/`
> superseded the server, the Vue frontend in section 8 was never built (`client/`
> is a single hand-written page), and the repo layout in section 12 describes
> what was planned rather than what exists. The [README](../README.md) describes
> what was actually built and [FINDINGS.md](FINDINGS.md) records where reality
> contradicted this document. Second-person phrasing and the open items in
> section 15 are as of writing, not instructions to the reader.

*Supersedes v1. Changes: frontend stack fixed, FluidAudio evaluated and scoped, diarization added as Phase 6 with hooks in Phase 4, Swift sidecar fork documented.*

---

## 1. Objective

A private, local, browser-accessible real-time Tagalog/Taglish transcription service running on a Mac mini M2 Pro. Audio and transcripts never leave the machine. Reachable from any device on the network. Exports to TXT, SRT, VTT, JSON. Post-session speaker attribution.

### Priorities, in order

1. Tagalog accuracy
2. Low-latency live transcription
3. Fast performance on the M2 Pro
4. Taglish support
5. Private, local processing
6. Browser + WebSocket access
7. Architecture that survives multiple users
8. Exportable, finalized transcripts

Every trade-off below resolves in favour of the higher-numbered priority losing.

---

## 2. Locked decisions

| Area | Choice | Rationale |
|---|---|---|
| Model | Whisper large-v3-turbo | Already validated on your own Tagalog/Taglish audio |
| ASR runtime | WhisperKit (CoreML -> ANE/GPU/CPU) | Apple-native scheduling; streaming is first-class |
| Orchestrator | Python + FastAPI | Owns VAD, windowing, commit, persistence, exports |
| Frontend | Vue 3 + Vite + shadcn-vue (preset `a29zezQG`) | — |
| Transport | WebSocket, binary PCM16 frames | Lowest practical latency |
| Language tag | Forced `tl` | Auto-detect on Taglish resolves to English and translates |
| VAD | Silero | Mature, cheap, well-understood thresholds |
| Storage | SQLite | Committed segments are the single source of truth |
| Diarization | Post-session, offline | Better accuracy, zero impact on the live path |
| Containers | Reverse proxy only | Containerized inference loses Metal/ANE |
| TLS | Tailscale | HTTPS certs and cross-device access in one move |

**MLX Whisper** stays in the repo as a second adapter — not for production, but so a future Tagalog fine-tune can be evaluated without rebuilding the pipeline.

---

## 3. The core risk

Your measured WER is an **offline** number. Whisper is trained on 30-second windows. Short streaming chunks degrade it badly, and Taglish degrades worst, because the language decision is context-dependent — with a narrow window the decoder flips between Tagalog and English mid-utterance, or silently switches to translating.

**Offline WER is the ceiling. The streaming layer's entire job is to lose as little of it as possible.**

This is a windowing-and-commit project, not a model project. Nearly every parameter in section 7 exists to protect context.

---

## 4. Evaluated and rejected

**FluidAudio (Parakeet family).** Rejected as the ASR core: no Tagalog. Its ASR lineup is Parakeet TDT v3 (25 European languages plus Japanese), Parakeet EOU for streaming (English-only), and SenseVoice/Paraformer for Mandarin. No Whisper backend at all.

Worth noting what we're giving up: Parakeet EOU does streaming ASR with trained end-of-utterance detection — a learned version of the commit boundary we're building by hand out of VAD thresholds and LocalAgreement-2. A model that knows when an utterance ended beats heuristics. It's English-only, so it isn't available to us.

**Retained from FluidAudio:** the offline diarization pipeline (see section 9). Optionally its ANE-resident Silero VAD, if the Swift sidecar fork in section 11 is ever taken.

**Parakeet as a general option.** Same rejection, same reason. Fast on Apple Silicon, wrong languages.

---

## 5. Architecture

```
Browser (AudioWorklet -> 16kHz mono PCM16)
        |  binary WS frames
        v
+-----------------------------------------+
| FastAPI orchestrator                    |
|  |-- Session manager                    |
|  |-- Ring buffer (rolling context)      |
|  |-- Silero VAD                         |
|  |-- Inference scheduler (async queue)  |
|  |-- LocalAgreement-2 commit policy     |
|  |-- SQLite writer                      |
|  |-- WAV archiver  -----------+         |
|  +-- Export renderers         |         |
+----------+--------------------+---------+
           | adapter iface      | (post-session)
           v                    v
   WhisperKit | MLX       Diarizer (batch)
           |                    |
           v                    v
   partial + final ---> SQLite segments (+ speaker_id)
           |
           v
   Browser transcript view
```

### Component contracts

**Ring buffer.** ~15s of trailing audio per session, handed to the model in full each hop. You are deliberately re-transcribing overlapping audio every second. Wasteful in FLOPs, but it's the only way to keep the context Whisper needs. The M2 Pro has the headroom at turbo speeds.

**Silero VAD.** Two jobs, both essential:
- Skip inference during silence. Turbo hallucinates confidently on silence — cheapest quality win available.
- Force a segment boundary after ~700ms trailing silence, flushing the provisional tail to final.

**LocalAgreement-2.** Run inference on consecutive overlapping windows, compare outputs, commit the longest token prefix on which two consecutive passes agree. Committed text is frozen permanently. This is what produces the "doesn't rewrite itself" behaviour and it is the heart of the system.

**Inference scheduler.** One model instance, async queue, per-session backpressure. If a hop can't be served before the next arrives, **drop the older request** rather than queueing — stale partials are worse than fewer partials.

**WAV archiver.** Writes session audio to disk as 16kHz mono PCM (~115MB/hour). Exists solely so diarization and re-transcription are possible after the fact. Without it, both are impossible.

**ASR adapter interface.** Keep it minimal:

```python
transcribe(pcm: bytes, language: str, prompt: str | None) -> list[Token]
```

Anything richer leaks WhisperKit-specific concepts into the orchestrator and kills the MLX swap.

---

## 6. Protocol

**Client -> server**
- Binary frames: raw PCM16LE, 16 kHz, mono
- JSON control: `{"type":"start","session_id","language","prompt"}`, `{"type":"stop"}`

**Server -> client** (all JSON)
- `{"type":"partial","text","since_ms"}` — provisional tail, replaces previous
- `{"type":"final","segment":{id,text,start_ms,end_ms}}` — append-only, never revised
- `{"type":"status","state":"listening|processing|idle"}`
- `{"type":"error","code","message"}`

The partial/final split maps directly to the UI. Finals accumulate as permanent text; the partial renders muted at the end.

---

## 7. Starting parameters

| Knob | Start | Tune when |
|---|---|---|
| Context window | 15s | down to 10s if latency hurts; up if Taglish drifts |
| Hop interval | 1.0s | up to 1.5s if the queue backs up |
| Commit rule | 2-pass agreement | 3-pass if text still visibly churns |
| VAD trailing silence | 700ms | down = snappier finals, up if it clips speakers |
| VAD threshold | 0.5 | up in noisy rooms |
| Beam size | 1 (greedy) | Beam 5 in the offline path only — too slow live |
| `condition_on_previous_text` | **off** | On risks hallucination loops in streaming |
| Temperature | 0.0 | Fallback ladder in offline cleanup only |
| Max concurrent sessions | 3 | Raise only after the Phase 3 load test says so |

---

## 8. Frontend

Two parts carry all the risk; the rest is standard shadcn shell.

**Capture path.** AudioWorklet -> 16kHz PCM16 -> WebSocket. Not MediaRecorder — Opus-in-a-container adds latency you can't recover. Three known traps:
- The worklet must live in `public/`, loaded by URL. Move it into `src/` and Vite transforms it and registration fails.
- `getUserMedia` returns undefined on plain HTTP from anything but `localhost`. Phone testing fails silently until TLS lands.
- Safari and some Bluetooth mics ignore `new AudioContext({sampleRate: 16000})`. Resample defensively in the worklet.

**Transcript renderer.** Finals in foreground text, provisional tail in muted.

> **The design contract: muted text may change, foreground text never will.**

No third "almost final" treatment — it dilutes the signal into noise. This contract is also why diarization is post-session (section 9).

**Supporting details.** Mic level meter — the first diagnostic when nothing appears on screen. Mute transmits silence rather than dropping frames, so timestamps stay aligned to wall-clock and SRT exports don't desync. Reconnect buffers ~30s client-side, with dedupe-by-id so the server can safely replay its segment tail.

**Open item.** Confirm the preset's icon library, and verify muted-vs-foreground contrast is actually distinguishable on the chosen theme. If it isn't, the whole partial/final affordance collapses.

---

## 9. Diarization

**Decision: post-session, offline. Not live.**

The reasoning is asymmetric. Post-session is a self-contained batch job over a saved WAV — addable, removable, and rebuildable without touching the live pipeline. If you later want live labels, none of the work is wasted. Live diarization goes the other way: a second commit policy in the hot path, the Swift sidecar decision forced early, and a broken UX contract, because a committed line's *speaker* could change after you've read it. Backing that out is expensive.

There's also a sequencing argument. Phase 2's accuracy risk is unresolved. Adding a second real-time subsystem before closing that question gives you two moving targets and no way to know which one to blame.

**Pipeline:** FluidAudio's offline diarizer — pyannote Community-1 (powerset segmentation + WeSpeaker + VBx clustering). Reads the archived WAV, produces speaker turns with timestamps.

**Merge rule:** assign each ASR segment the speaker holding the most overlap with it. Get cleverer only if the output is visibly wrong. Straddling turns and mid-segment speaker changes are the failure cases to watch.

**Hooks required in Phase 4** (about an hour of work, saves a rewrite):
1. `speaker_id` nullable column on `segments`
2. Session audio persisted to disk
3. Export renderers speaker-aware from the start, even while the field is always null

**Revisit live diarization only if** someone is reading the transcript *during* the meeting — accessibility, or a remote participant following along. Speaker-blind text of two people going back and forth is much harder to parse than it sounds. Absent that, post-session wins.

---

## 10. Phases

### Phase 1 — Vertical slice
*Goal: measure the real latency budget. Not to be good.*
- FastAPI WS endpoint accepting binary PCM, holding a session
- Browser page: AudioWorklet capture -> WS -> text into a div
- Naive fixed 5s chunks straight to WhisperKit. No VAD, no overlap, no commit policy
- Log per chunk: audio duration, inference wall time, real-time factor

**Exit:** words appear on screen, and you know your RTF at turbo on this machine.

### Phase 2 — Windowing + commit
*The phase that matters. Everything before is scaffolding; everything after is polish.*
- Ring buffer, rolling 15s context, 1s hop
- Silero VAD gating and boundary detection
- LocalAgreement-2 commit; partial/final event split
- **Replay your existing eval audio through the live pipeline** and score it exactly as you scored offline, split by Tagalog-heavy / English-heavy / mixed

**Exit:** live WER within ~5 points of your offline number, and no visible rewriting of committed text.

**If the gap is larger:** tune section 7 before proceeding — widen the context window first, then consider 3-pass commit. Do not build on a lossy pipeline. A persistent gap driven by language drift is the fine-tune trigger.

### Phase 3 — Hardening
- Reconnect and session resume; client buffers audio during disconnect
- Multi-session queue with backpressure and drop policy
- TLS via Tailscale
- Load test at 2, 3, 4 concurrent streams; record the latency degradation curve

**Exit:** two phones and a laptop connect simultaneously over the tailnet, all three see acceptable partials.

### Phase 4 — Persistence + exports + diarization hooks
- SQLite: `sessions`, `segments(id, session_id, start_ms, end_ms, text, text_clean, speaker_id, committed_at)`
- WAV archiver writing session audio to disk
- Export renderers over the segments table: TXT, SRT, VTT, JSON — speaker-aware from day one
- Session list and download endpoints

**Exit:** finish a session, download all four formats, timestamps line up with the audio.

### Phase 5 — Cleanup pass
*Where Taglish starts reading well.*
- Local LLM (MLX or Ollama) over **finalized segments only**, never the live tail
- Punctuation, capitalization, Philippine proper-noun normalization, consistent Tagalog/English orthography
- Store as `text_clean` — never overwrite raw ASR output
- Optional per-session vocabulary prompt fed to WhisperKit's `prompt` param

**Exit:** raw vs cleaned side by side; cleaned is obviously more readable and has invented nothing.

### Phase 6 — Diarization
- FluidAudio offline pipeline over the archived WAV
- Overlap-based merge onto finalized segments
- Speaker labels surfaced in exports and in the session view
- Optional: speaker renaming in the UI

**Exit:** a two-person recording exports as SRT with correct speaker attribution on the large majority of turns.

---

## 11. Open architectural fork

**Python orchestrator with a Swift ASR process, or a mostly-Swift service?**

WhisperKit is Swift. FluidAudio's ANE-resident Silero VAD and its diarizer are Swift. If both VAD and ASR moved into one Swift sidecar, Python would shrink to session management, commit policy, persistence, and exports.

**For:** ANE-resident VAD frees CPU; one process boundary instead of two; access to FluidAudio's streaming VAD events rather than threshold-watching.

**Against:** Swift is a worse language for the commit policy and export logic; it complicates the MLX adapter, which is the fine-tune escape hatch; and it's a bigger change to make before Phase 2's risk is resolved.

**Decide after Phase 2**, not before. If live WER is fine, the fork isn't worth taking. If you end up needing every millisecond, revisit.

---

## 12. Repo layout

```
asr-server/
|-- server/
|   |-- main.py              # FastAPI app, WS endpoint
|   |-- session.py           # per-connection state, ring buffer
|   |-- vad.py               # Silero wrapper
|   |-- commit.py            # LocalAgreement-2
|   |-- scheduler.py         # async inference queue
|   |-- archive.py           # WAV writer
|   |-- store.py             # SQLite
|   |-- adapters/            # base.py, whisperkit.py, mlx.py
|   |-- diarize/             # Phase 6: runner + merge
|   +-- exports/             # txt.py, srt.py, vtt.py, json.py
|-- client/                  # Vue + shadcn-vue; worklet in public/
|-- eval/
|   |-- audio/               # your existing eval set
|   |-- refs/                # ground truth
|   +-- score.py             # jiwer, split TL / EN / mixed
+-- bench/
    +-- latency.py
```

Keep `eval/` in the repo from day one. Phase 2's exit criteria depends on being able to re-score at will.

---

## 13. Risk register

| Risk | Signal | Mitigation |
|---|---|---|
| Live WER >> offline | Phase 2 gap >5pts | Widen context window first, then 3-pass commit |
| Taglish language drift | Segments flip to English mid-sentence | Forced `tl`; if persistent, this is the fine-tune trigger |
| Hallucination on silence | Text appears when nobody speaks | VAD gating, `condition_on_previous_text` off, temp 0 |
| ANE throughput ceiling | Latency spikes at 3+ streams | Documented degradation curve, hard session cap |
| Vocabulary prompt backfires | Better proper nouns, more invented text | A/B against eval set — don't assume it helps |
| Browser mic blocked | Works on the Mac mini, fails from phone | TLS in Phase 3, not later — it blocks real testing |
| Theme kills the partial affordance | Muted ~ foreground on the chosen preset | Check contrast before Phase 2 |
| Diarization misattributes | Speakers swap at turn boundaries | Overlap-majority merge; inspect straddling turns first |
| Disk fills from archived audio | ~115MB per session-hour | Retention policy in Phase 4 |

---

## 14. Definition of done

Speak Taglish into a phone browser on your home network. Words appear within roughly 1–1.5s in muted text, then settle into permanent text that never changes again. Stop, export, and get a timestamped SRT with correct Tagalog spelling, sensible punctuation, and — for multi-speaker recordings — correct speaker labels.

Nothing left the Mac mini.

---

## 15. Open items

- Preset `a29zezQG`: confirm icon library and muted/foreground contrast
- Solo dictation vs. conversations — determines whether Phase 6 is optional or essential
- Swift sidecar fork — decide after Phase 2
- Retention policy for archived session audio
