"""Insert pauses into a clip so utterance finalization has something to do.

The synthetic Taglish fixture is read by a TTS voice with sub-700 ms gaps, so
the live path's silence boundary never fires on it. This copies the clip with
1.2 s of silence after every word the model ended with a full stop, question
mark or comma, using the word timings from a previous live/offline run's JSON.
The reference text is unchanged.
"""
import json, sys, wave
src, words_json, dst = sys.argv[1], sys.argv[2], sys.argv[3]
pause_ms = int(sys.argv[4]) if len(sys.argv) > 4 else 1200
words = json.load(open(words_json))["words"]
cuts = sorted({w["endMs"] for w in words if w["text"].strip().endswith((".", "?", ","))})
with wave.open(src, "rb") as r:
    assert r.getnchannels() == 1 and r.getsampwidth() == 2 and r.getframerate() == 16000
    pcm = r.readframes(r.getnframes())
out = bytearray(); last = 0
for ms in cuts:
    b = min(len(pcm), ms * 32)
    out += pcm[last:b]; out += bytes(pause_ms * 32); last = b
out += pcm[last:]
with wave.open(dst, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(bytes(out))
print(f"{len(cuts)} pauses of {pause_ms} ms inserted; {len(out)//32/1000:.1f} s written to {dst}")
