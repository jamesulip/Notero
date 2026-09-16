"""Score a `transcribe --json` run against a UCLASS syllable CHAT transcript.

UCLASS (UCL Archive of Stuttered Speech) publishes time-aligned syllable
transcripts for four monologues. This scorer turns one into two references:

  verbatim  every token the speaker produced, fillers and repetitions included
  cleaned   fillers, aborted fragments and immediate repetitions removed

The pair separates mishearing from transcription convention, which is the
whole question on disfluent speech.

Three corrections are applied, all mechanical:
  - reference tokens whose audio is silent are dropped (UCLASS redacts names
    and postcodes in the wav, so no system can be scored on them);
  - hypothesis words inside a gap longer than GAP_MS between subject tokens are
    dropped (the wav contains the interviewer, the transcript does not);
  - one text normalizer runs over reference and hypothesis alike, mapping
    UCLASS pronunciation spelling and ASR orthography onto one form.

Usage:
  python3 eval/uclass_score.py AUDIO.wav TRANSCRIPT.cha label=run.json [...]
"""
import re, json, wave, struct, math, sys

SILENCE_RMS = 200          # below this a reference token's audio is redacted
PAD_MS      = 700          # tolerance around a subject span
RMS_PAD_MS  = 250          # widen the window that tests a token for silence          # tolerance when testing hypothesis words against subject spans

FILLER = {"um", "er", "erm", "uh", "mm"}

def load_chat(path):
    ents, cur = [], None
    for ln in open(path).read().splitlines():
        m = re.search(r'%snd:_"[^"]+"_(\d+)_(\d+)', ln)
        if m:
            cur = (int(m.group(1)), int(m.group(2)))
        elif ln.startswith('%pho:') and cur:
            ents.append((cur[0], cur[1], ln.split(':', 1)[1].strip().rstrip('.')))
            cur = None
    return ents

def split_stutter(tok):
    """UCLASS fuses a prolongation onto its word: RAre -> RA + re."""
    m = re.fullmatch(r'([A-Z]{2,})([a-z].*)', tok)
    return [m.group(1), m.group(2)] if m else [tok]

def join_syllables(ents):
    """Fold '-xxx' continuation syllables into the preceding word."""
    ents = [(a, b, p) for a, b, t in ents for p in split_stutter(t)]
    out = []
    for a, b, tok in ents:
        if tok.startswith('-') and out and not re.fullmatch(r'-?xxx+', tok):
            s, _, t = out[-1]
            out[-1] = (s, b, t + tok[1:])
        else:
            out.append((a, b, tok))
    return out

def rms_fn(wav):
    w = wave.open(wav); sr = w.getframerate()
    total = w.getnframes()
    def rms(a_ms, b_ms):
        start = min(max(0, int(a_ms / 1000 * sr)), total - 1)
        n = max(1, min(int((b_ms - a_ms) / 1000 * sr), total - start))
        w.setpos(start)
        raw = w.readframes(n)
        s = struct.unpack(f"<{len(raw)//2}h", raw)
        return math.sqrt(sum(x * x for x in s) / max(1, len(s)))
    return rms, w.getnframes() / sr * 1000

NUMBERS = {"2":"two","6":"six","7":"seven","8":"eight","11":"eleven","30":"thirty","44":"four four"}
CONTRACT = {"im":"i am","ill":"i will","cant":"can not","dont":"do not","its":"it is",
            "thats":"that is","whats":"what is","ive":"i have","id":"i would"}
# UCLASS writes pronunciation and splits names into syllables; the models write
# standard orthography. Both sides are mapped onto one spelling before scoring.
PHRASES = [
    ("es us ex", "ssx"), ("sled storm", "sledstorm"), ("play station", "playstation"),
    ("wipe outs", "wipeout"), ("wipe out", "wipeout"), ("o clock", "oclock"),
    ("a clock", "oclock"), ("aclock", "oclock"), ("trikee", "tricky"), ("chissick", "chiswick"),
    ("favrite", "favourite"), ("favorite", "favourite"), ("diffrent", "different"),
    ("mem ber", "remember"), ("member", "remember"), ("fussion", "fusion"),
    ("peeee", "pe"), ("pee ee", "pe"), ("umm", "um"), ("sladstone", "sledstorm"),
]

def normalize(text):
    """One text normalizer for reference and hypothesis alike."""
    t = text.replace("/", "'").lower()
    t = re.sub(r"[^a-z0-9'\s]", " ", t)
    toks = []
    for w in t.split():
        w = NUMBERS.get(w, w)
        toks.append(w)
    t = " ".join(toks)
    for a, b in PHRASES:
        t = re.sub(rf"\b{a}\b", b, t)
    t = t.replace("'", "")
    t = " ".join(CONTRACT.get(w, w) for w in t.split())
    return t.split()

def light(tok):
    """Per-token clean, before the phrase-level normalizer runs on the join."""
    import re as _re
    return _re.sub(r"[^a-z0-9']", "", tok.replace("/", "'").lower())

def build_refs(words):
    """Return (verbatim, cleaned) token lists plus the stutter tokens removed."""
    verbatim, cleaned, removed = [], [], []
    for raw in words:
        if raw.startswith('(') or raw.startswith('{'):           # (UM) (ER) (u laughs) {U BLOCKS}
            inner = raw.strip('(){}').lower()
            if 'laugh' in inner or 'block' in inner:
                continue                                          # non-speech, in neither
            verbatim.append('um' if inner.startswith('u') else 'er')
            removed.append(raw)
            continue
        aborted = raw.endswith('-')                               # HE-  NI-
        t = light(raw)
        if not t:
            continue
        verbatim.append(t)
        if aborted:
            removed.append(raw); continue
        if t in FILLER:
            removed.append(raw); continue
        if cleaned and cleaned[-1] == t:                          # i i / my my / and and
            removed.append(raw); continue
        cleaned.append(t)
    return normalize(" ".join(verbatim)), normalize(" ".join(cleaned)), removed

def fit_offset(ents, words):
    """UCLASS aligned some transcripts against a master with a longer lead-in
    than the released wav. Recover the constant offset from the words that the
    reference and the hypothesis share. The scale is 1.0 for every published
    file, so only a shift is fitted."""
    import difflib, statistics
    A = [light(t) for _, _, t in ents]
    B = [light(w['text']) for w in words]
    rt = [(a + b) / 2 for a, b, _ in ents]
    ht = [(w['startMs'] + w['endMs']) / 2 for w in words]
    pairs = []
    for blk in difflib.SequenceMatcher(a=A, b=B, autojunk=False).get_matching_blocks():
        for k in range(blk.size):
            pairs.append((rt[blk.a + k], ht[blk.b + k]))
    if len(pairs) < 10:
        return 0.0, 0, 0.0
    shifts = [h - r for r, h in pairs]
    off = statistics.median(shifts)
    resid = statistics.median(abs(s - off) for s in shifts)
    return off, len(pairs), resid


def wer(ref, hyp):
    n, m = len(ref), len(hyp)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): d[i][0] = i
    for j in range(m + 1): d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1,
                          d[i-1][j-1] + (ref[i-1] != hyp[j-1]))
    return d[n][m] / max(1, n), d[n][m]

def main(wav, cha, hyp_json, label, offset=None):
    ents = join_syllables(load_chat(cha))
    rms, dur = rms_fn(wav)
    d0 = json.load(open(hyp_json))

    if offset is None:
        offset, n_anchor, resid = fit_offset(ents, d0['words'])
    else:
        n_anchor = resid = None
    ents = [(a + offset, b + offset, t) for a, b, t in ents]
    ents = [e for e in ents if e[1] > 0 and e[0] < dur]      # drop what the wav does not hold

    kept, dropped = [], []
    for a, b, tok in ents:
        if re.fullmatch(r'-?x+', tok.lower()):
            dropped.append((a, b, tok)); continue
        # Measure a padded window. A redaction runs for a second or more, so it
        # still reads as silent. A short word does not trip the test because the
        # time fit is only accurate to ~100 ms.
        if rms(a - RMS_PAD_MS, b + RMS_PAD_MS) < SILENCE_RMS:
            dropped.append((a, b, tok)); continue
        kept.append((a, b, tok))

    GAP_MS = 3000
    gaps = []
    for (_, prev_end, _), (next_start, _, _) in zip(kept, kept[1:]):
        if next_start - prev_end > GAP_MS:
            gaps.append((prev_end + PAD_MS, next_start - PAD_MS))

    d = d0
    inside, outside = [], []
    for w in d['words']:
        mid = (w['startMs'] + w['endMs']) / 2
        (outside if any(s <= mid <= e for s, e in gaps) else inside).append(w)

    hyp = normalize(" ".join(w['text'] for w in inside))
    verbatim, cleaned, removed = build_refs([t for _, _, t in kept])
    hyp_clean = [h for h in hyp if h not in FILLER]
    hyp_clean = [h for i, h in enumerate(hyp_clean) if i == 0 or h != hyp_clean[i-1]]

    wv, ev = wer(verbatim, hyp)
    wc, ec = wer(cleaned, hyp_clean)
    print(f"\n=== {label} ===")
    if n_anchor is not None:
        print(f"  time offset      {offset/1000:+.2f} s from {n_anchor} shared words, median residual {resid:.0f} ms")
    print(f"  model            {d['model']}")
    print(f"  decode           {d['decodeMs']/1000:.1f} s   RTF {d['rtf']:.3f}")
    print(f"  ref tokens       {len(ents)} syll -> {len(kept)} scored ({len(dropped)} in redacted/silent audio)")
    print(f"  hyp words        {len(d['words'])} -> {len(inside)} inside subject spans ({len(outside)} interviewer/outside)")
    print(f"  verbatim WER     {wv*100:5.1f}%   ({ev} errors / {len(verbatim)} ref words)")
    print(f"  cleaned  WER     {wc*100:5.1f}%   ({ec} errors / {len(cleaned)} ref words)")
    print(f"  excluded as interviewer: {' '.join(w['text'].strip() for w in outside)[:200]}")
    return dict(label=label, verbatim=wv, cleaned=wc, ev=ev, ec=ec, offset=offset,
                nv=len(verbatim), nc=len(cleaned), decode=d['decodeMs']/1000, rtf=d['rtf'])

if __name__ == '__main__':
    wav, cha = sys.argv[1], sys.argv[2]
    shared = None
    for i, pair in enumerate(sys.argv[3:]):
        label, path = pair.split('=', 1)
        # Fit the offset once, on the first run, and reuse it for the rest so
        # that no model is scored against a timeline tuned to itself.
        r = main(wav, cha, path, label, offset=shared)
        if shared is None:
            shared = r['offset']
