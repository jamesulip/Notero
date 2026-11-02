"""Tokens, references and hypotheses for the Taglish error taxonomy.

The token sequence is exactly `score.normalize`'s (hyphens split, apostrophes kept inside a
word), so the taxonomy counts the same errors as the headline WER and every error lands in
exactly one category. On top of that each token remembers what `score.normalize` throws away:
its surface form (case), whether it opens a sentence, and whether it was one piece of a
hyphenated word ("nag-meeting" is the tokens "nag" and "meeting" in one group).

References come in three forms, all local files a person can edit:

  * `<id>.txt`           plain text, one utterance per line, no language information;
  * `<id>.tagged.txt`    the same, plus per-word tags (see TAGGED below);
  * `<id>.json`          the repository's reference form: utterances with optional times,
                         speakers and word-level `languageSpans`.

Only word-level tags (inline tags or `languageSpans`) label tokens. An utterance-level
`language` such as "tl" or "mixed" is kept as metadata and does not: a line tagged "tl" can
hold English words, and treating it as a word label would be an unsupported claim.

TAGGED format::

    # a comment
    !annotator: free text kept in the report            (optional header lines, `!key: value`)
    [id=u1 spk=A t=0-3200] Good/en morning/en team/en. Simulan/tl na/tl natin/tl ang/tl standup/en.
    [id=u2 t=3400-7600] Kahapon, tinapos ko na yung/tl deployment/en script/en.
    Sige, i-follow/mix up/mix ko yan/tl mamaya.        (no header: id is the line number)

A tag is `/tl`, `/en`, `/mix` (a Tagalog affix on an English stem), `/ne` (a proper name) or
`/oth` (filler, laughter, digits, anything that is neither language), written directly after a
word and before its trailing punctuation. A tag applies to every token of that
whitespace-separated word, so `nag-meeting/mix` tags both "nag" and "meeting". A word with
no tag is left to the heuristic. The header keys are `id`, `spk`, `t` (start-end in ms) and
`overlap` (1).
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import langscore  # noqa: E402
import score as pooled  # noqa: E402

#: Verified tag -> language label. `ne` is a proper name, which is not a language.
TAG_LANG = {"tl": "tl", "en": "en", "mix": "mix", "ne": "name", "oth": "other"}
#: Span `language` codes of the JSON reference form -> label. Anything else is "other".
SPAN_LANG = {"tl": "tl", "fil": "tl", "tagalog": "tl", "filipino": "tl", "en": "en", "english": "en",
             "mix": "mix", "mixed": "mix", "ne": "name", "name": "name", "oth": "other", "other": "other"}

_TAG_RE = re.compile(r"^(?P<word>.+?)/(?P<tag>tl|en|mix|ne|oth)(?P<tail>[^\w/]*)$")
_HEADER_RE = re.compile(r"^\[(?P<attrs>[^\]]*)\]\s*(?P<text>.*)$")
_SENTENCE_END = re.compile(r"[.?!…][\"'”’)\]]*$")
_HYPHEN_IN_WORD = re.compile(r"(?<=\w)-(?=\w)")
_ELLIPSIS_ONLY = re.compile(r"^[.…]+$")


@dataclass(slots=True)
class Token:
    text: str                  # `score.normalize` form
    surface: str               # as written (case kept); equals `text` when unknown
    utt: int                   # utterance index
    sentence_start: bool
    group: int | None = None   # hyphenated-word id, unique within the reference/hypothesis
    group_pos: int = 0
    group_len: int = 1
    tag: str | None = None     # verified label from the reference annotation, else None
    start_ms: int | None = None
    end_ms: int | None = None


@dataclass
class Utterance:
    id: str
    speaker: str | None = None
    start_ms: int | None = None
    end_ms: int | None = None
    overlap: bool | None = None
    language: str | None = None     # utterance-level tag: metadata only
    text: str = ""

    @property
    def timed(self) -> bool:
        return self.start_ms is not None and self.end_ms is not None and self.end_ms > self.start_ms


@dataclass
class Reference:
    path: str
    format: str                      # txt | tagged | json
    utterances: list[Utterance]
    tokens: list[Token]
    annotation: dict = field(default_factory=dict)
    skipped_spans: int = 0           # utterances whose languageSpans did not match their text
    cased: bool = False              # the text has both upper- and lower-case letters

    @property
    def has_times(self) -> bool:
        return any(u.timed for u in self.utterances)

    @property
    def tagged_tokens(self) -> int:
        return sum(1 for t in self.tokens if t.tag)


@dataclass
class Hypothesis:
    path: str
    tokens: list[Token]
    cased: bool = False
    timed_tokens: int = 0
    time_note: str = ""              # why times are missing, when they are


# ------------------------------------------------------------------ tokenizer

def _surfaces(piece: str) -> list[str]:
    """The tokens of `score.normalize` on `piece`, but with case kept."""
    text = unicodedata.normalize("NFKC", piece).replace("’", "'").replace("‘", "'")
    text = re.sub(r"[^\w\s']", " ", text)
    text = re.sub(r"(?<!\w)'|'(?!\w)", " ", text)
    return text.split()


def tokenize(text: str, utt: int, *, first_is_sentence_start: bool = True,
             group_base: int = 0, chunk_tags: list[str | None] | None = None) -> list[Token]:
    """Tokens of one utterance, equal to `score.normalize(text)` word for word.

    `chunk_tags` holds one verified tag (or None) for each whitespace-separated chunk of the
    NFKC-normalised text; a chunk's tag goes to all of its tokens. `group_base` makes group
    ids unique across utterances."""
    text = unicodedata.normalize("NFKC", text)
    chunks = text.split()
    tokens: list[Token] = []
    sentence_start = first_is_sentence_start
    for ci, chunk in enumerate(chunks):
        tag = chunk_tags[ci] if chunk_tags and ci < len(chunk_tags) else None
        pieces = _HYPHEN_IN_WORD.split(chunk)
        group_tokens: list[Token] = []
        for piece in pieces:
            normal = pooled.normalize(piece)
            surf = _surfaces(piece)
            if len(surf) != len(normal) or [s.lower() for s in surf] != normal:
                surf = list(normal)      # an odd character: no case information for this piece
            for n, s in zip(normal, surf):
                tok = Token(text=n, surface=s, utt=utt, sentence_start=sentence_start, tag=tag)
                sentence_start = False
                tokens.append(tok)
                group_tokens.append(tok)
        if len(pieces) > 1 and len(group_tokens) > 1:
            for pos, tok in enumerate(group_tokens):
                tok.group = group_base + ci
                tok.group_pos = pos
                tok.group_len = len(group_tokens)
        if not _ELLIPSIS_ONLY.match(chunk):
            sentence_start = bool(_SENTENCE_END.search(chunk))
    return tokens


def is_cased(text: str) -> bool:
    return any(c.isupper() for c in text) and any(c.islower() for c in text)


# ------------------------------------------------------------------ references

def parse_tagged_line(line: str) -> tuple[dict, str, list[str | None]]:
    """(header attributes, text without tags, one tag per whitespace chunk)."""
    attrs: dict[str, str] = {}
    m = _HEADER_RE.match(line)
    if m:
        for part in m.group("attrs").split():
            if "=" in part:
                k, v = part.split("=", 1)
                attrs[k] = v
        line = m.group("text")
    words, tags = [], []
    for chunk in line.split():
        tm = _TAG_RE.match(chunk)
        if tm:
            words.append(tm.group("word") + tm.group("tail"))
            tags.append(tm.group("tag"))
        else:
            words.append(chunk)
            tags.append(None)
    return attrs, " ".join(words), tags


def _times(spec: str | None) -> tuple[int | None, int | None]:
    if not spec or "-" not in spec:
        return None, None
    a, _, b = spec.partition("-")
    try:
        return int(a), int(b)
    except ValueError:
        return None, None


def load_reference(path: Path) -> Reference:
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    name = path.name
    if name.endswith(".json"):
        return _load_json_reference(path, text)
    if name.endswith(".tagged.txt"):
        return _load_tagged_reference(path, text)
    return _load_plain_reference(path, text)


def _finish(ref: Reference) -> Reference:
    ref.cased = is_cased(" ".join(u.text for u in ref.utterances))
    return ref


def _load_plain_reference(path: Path, text: str) -> Reference:
    utts, tokens = [], []
    for n, line in enumerate((ln for ln in text.splitlines() if ln.strip()), 1):
        utts.append(Utterance(id=f"line-{n}", text=line.strip()))
        tokens.extend(tokenize(line, len(utts) - 1, group_base=len(tokens) * 1000))
    return _finish(Reference(str(path), "txt", utts, tokens))


def _load_tagged_reference(path: Path, text: str) -> Reference:
    annotation: dict[str, str] = {}
    utts, tokens = [], []
    n = 0
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("!") and ":" in line:
            key, _, value = line[1:].partition(":")
            annotation[key.strip()] = value.strip()
            continue
        n += 1
        attrs, clean, tags = parse_tagged_line(line)
        start, end = _times(attrs.get("t"))
        utts.append(Utterance(id=attrs.get("id", f"line-{n}"), speaker=attrs.get("spk"), start_ms=start,
                              end_ms=end, overlap=(attrs.get("overlap") == "1") if "overlap" in attrs else None,
                              text=clean))
        tokens.extend(tokenize(clean, len(utts) - 1, group_base=len(tokens) * 1000, chunk_tags=tags))
    return _finish(Reference(str(path), "tagged", utts, tokens, annotation))


def _load_json_reference(path: Path, text: str) -> Reference:
    data = json.loads(text)
    items = data["utterances"] if isinstance(data, dict) else data
    annotation = dict(data.get("annotation", {})) if isinstance(data, dict) else {}
    utts, tokens, skipped = [], [], 0
    for n, u in enumerate(items, 1):
        utt = Utterance(id=str(u.get("id", f"line-{n}")), speaker=u.get("speaker"), start_ms=u.get("startMs"),
                        end_ms=u.get("endMs"), overlap=u.get("overlap"), language=u.get("language"),
                        text=u["text"])
        utts.append(utt)
        index = len(utts) - 1
        toks = tokenize(utt.text, index, group_base=len(tokens) * 1000)
        spans = u.get("languageSpans")
        if spans:
            per_span = [(pooled.normalize(s["text"]), SPAN_LANG.get(str(s.get("language", "")).lower(), "other"))
                        for s in spans]
            flat = [w for words, _ in per_span for w in words]
            if flat == [t.text for t in toks]:
                labels = [lang for words, lang in per_span for _ in words]
                for tok, lang in zip(toks, labels):
                    tok.tag = {"tl": "tl", "en": "en", "mix": "mix", "name": "ne", "other": "oth"}[lang]
            else:
                skipped += 1
        tokens.extend(toks)
    return _finish(Reference(str(path), "json", utts, tokens, annotation, skipped_spans=skipped))


# ------------------------------------------------------------------ hypotheses

def load_hypothesis(path: Path) -> Hypothesis:
    """A plain-text transcript, or a `transcribe --json` report (its `transcript`, with the
    word times of `words` when they agree with it)."""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    if not path.name.endswith(".json"):
        tokens: list[Token] = []
        for n, line in enumerate(ln for ln in text.splitlines() if ln.strip()):
            tokens.extend(tokenize(line, n, group_base=len(tokens) * 1000))
        return Hypothesis(str(path), tokens, is_cased(text), 0, "a plain-text transcript has no word times")
    report = json.loads(text)
    transcript = report.get("transcript", "")
    tokens = tokenize(transcript, 0)
    words = report.get("words") or []
    hyp = Hypothesis(str(path), tokens, is_cased(transcript))
    if not words:
        hyp.time_note = "the report has no word times"
        return hyp
    timed: list[tuple[str, int, int]] = []
    for w in words:
        for t in pooled.normalize(w.get("text", "")):
            timed.append((t, int(w["startMs"]), int(w["endMs"])))
    if [t for t, _, _ in timed] == [t.text for t in tokens]:
        for tok, (_, s, e) in zip(tokens, timed):
            tok.start_ms, tok.end_ms = s, e
    else:
        # The word list and the transcript differ in a few apostrophes: pair them by alignment
        # and leave the rest untimed.
        for op, ri, hj in langscore.align([t for t, _, _ in timed], [t.text for t in tokens]):
            if op == "eq":
                tokens[hj].start_ms, tokens[hj].end_ms = timed[ri][1], timed[ri][2]
    hyp.timed_tokens = sum(1 for t in tokens if t.start_ms is not None)
    if not hyp.timed_tokens:
        hyp.time_note = "no word time could be matched to the transcript"
    return hyp
