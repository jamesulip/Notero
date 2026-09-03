"""Phase 5 cleanup pass over finalized segments.

Section 10: a local LLM over **finalized segments only, never the live tail**.
Punctuation, capitalization, Philippine proper-noun normalization, consistent
Tagalog/English orthography. Output goes to `text_clean`; raw ASR is never
overwritten, so a bad cleanup is always reversible.

The exit criterion is "obviously more readable and has invented nothing", and
the second half is the hard part. An instruction-tuned model asked to tidy
Taglish will happily translate it, answer it, or complete the sentence. So
every rewrite is checked against its source and rejected if it drifts too far,
which turns a plausible failure into a visible one -- the segment simply keeps
its raw text.
"""

from __future__ import annotations

import logging
import re
import unicodedata
from dataclasses import dataclass

log = logging.getLogger("asr.cleanup")

DEFAULT_MODEL = "mlx-community/Qwen2.5-3B-Instruct-4bit"

SYSTEM_PROMPT = """\
You repair the punctuation and capitalization of Tagalog/Taglish speech-to-text \
output from the Philippines.

Rules, in order of importance:
1. Never add, remove or translate words. Code-switching between Tagalog and \
English is correct and must be preserved exactly as spoken.
2. Fix capitalization, punctuation, and spacing only.
3. Repair obvious run-together or split words (e.g. "kolang" -> "ko lang", \
"panaman" -> "pa naman").
4. Capitalize Philippine proper nouns and personal names.
5. Do not answer, continue, summarize or comment on the text.

Reply with the corrected line and nothing else."""

_PUNCT = re.compile(r"[^\w\s']", re.UNICODE)


def _words(text: str) -> list[str]:
    text = unicodedata.normalize("NFKC", text).lower()
    return _PUNCT.sub(" ", text).split()


def _letters(text: str) -> str:
    """Lowercase letters only -- no case, punctuation, or spacing."""
    text = unicodedata.normalize("NFKC", text).lower()
    return _PUNCT.sub("", text).replace(" ", "").replace("\t", "")


def similarity(raw: str, cleaned: str) -> float:
    """Character-level overlap of the letters alone. 1.0 means identical.

    Compared at character level rather than word level on purpose. The cleanup
    is *supposed* to split run-together words ("kolang" -> "ko lang") and fix
    spelling ("kasih" -> "kasi"), and a word-level comparison scores those as
    heavily changed -- a legitimate repair measured 0.50, below any threshold
    that still catches invention. Ignoring spacing entirely makes those edits
    nearly free while translation and continuation still score low, which is
    the distinction that actually matters here.
    """
    a, b = _letters(raw), _letters(cleaned)
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return 2 * prev[len(b)] / (len(a) + len(b))


def dropped_words(raw: str, cleaned: str, min_length: int = 4) -> list[str]:
    """Raw words that vanished entirely from the rewrite.

    Character similarity cannot see this: losing "zayun" from a 150-character
    segment moves the score by a few percent, while changing what the sentence
    says. Splits and merges are tolerated by matching against the cleaned text
    with spacing removed, so "ko lang" still contains "kolang".
    """
    haystack = _letters(cleaned)
    missing = []
    for word in _words(raw):
        if len(word) < min_length:
            continue          # particles drift legitimately; ignore them
        if _letters(word) not in haystack:
            missing.append(word)
    return missing


@dataclass
class CleanupStats:
    attempted: int = 0
    accepted: int = 0
    rejected_drift: int = 0
    rejected_length: int = 0
    rejected_dropped: int = 0


class CleanupEngine:
    """Wraps a local MLX model. Loaded lazily -- most sessions never clean."""

    def __init__(self, model: str = DEFAULT_MODEL, min_similarity: float = 0.85,
                 max_growth: float = 1.6) -> None:
        self.model_name = model
        self.min_similarity = min_similarity
        self.max_growth = max_growth
        self._model = None
        self._tokenizer = None

    def load(self) -> None:
        if self._model is not None:
            return
        from mlx_lm import load  # heavy import, deferred

        log.info("loading cleanup model %s", self.model_name)
        self._model, self._tokenizer = load(self.model_name)

    def _generate(self, text: str, vocabulary: str | None) -> str:
        from mlx_lm import generate

        system = SYSTEM_PROMPT
        if vocabulary:
            system += (
                "\n\nNames and terms likely to appear, spelled correctly:\n"
                + vocabulary
            )
        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": text},
        ]
        prompt = self._tokenizer.apply_chat_template(
            messages, add_generation_prompt=True, tokenize=False
        )
        # Cap generation relative to the input; a runaway continuation is the
        # most common failure and there is no reason to pay for it.
        budget = min(512, max(32, int(len(self._tokenizer.encode(text)) * 2 + 24)))
        out = generate(self._model, self._tokenizer, prompt=prompt,
                       max_tokens=budget, verbose=False)
        return out.strip().strip('"').strip()

    def clean_text(self, raw: str, vocabulary: str | None = None,
                   stats: CleanupStats | None = None) -> str:
        """Returns cleaned text, or the raw text unchanged if the rewrite drifted."""
        stats = stats or CleanupStats()
        raw = raw.strip()
        if not raw:
            return raw
        self.load()
        stats.attempted += 1

        try:
            candidate = self._generate(raw, vocabulary)
        except Exception:
            log.exception("cleanup generation failed; keeping raw text")
            return raw

        candidate = candidate.splitlines()[0].strip() if candidate else ""
        if not candidate:
            return raw

        if len(candidate) > len(raw) * self.max_growth + 20:
            stats.rejected_length += 1
            log.warning("cleanup rejected (too long): %r -> %r", raw[:60], candidate[:60])
            return raw

        missing = dropped_words(raw, candidate)
        if missing:
            stats.rejected_dropped += 1
            log.warning("cleanup rejected (dropped %s): %r -> %r",
                        missing, raw[:60], candidate[:60])
            return raw

        score = similarity(raw, candidate)
        if score < self.min_similarity:
            stats.rejected_drift += 1
            log.warning("cleanup rejected (similarity %.2f): %r -> %r",
                        score, raw[:60], candidate[:60])
            return raw

        stats.accepted += 1
        return candidate

    def clean_segments(self, segments, vocabulary: str | None = None
                       ) -> tuple[dict[int, str | None], CleanupStats]:
        """Returns {segment_id: cleaned or None}.

        None means "this segment has no valid cleanup" and the caller must
        clear any stored value. Returning only the accepted rewrites would make
        a re-run non-idempotent: a segment accepted under looser guards would
        keep its stale cleaned text forever once the guards tightened, which is
        exactly the case that matters, because the reason to tighten them is
        that the old output was wrong.
        """
        stats = CleanupStats()
        out: dict[int, str | None] = {}
        for segment in segments:
            cleaned = self.clean_text(segment.text, vocabulary, stats)
            if cleaned != segment.text:
                out[segment.id] = cleaned
            elif segment.text_clean is not None:
                out[segment.id] = None      # clear a now-invalid rewrite
        return out, stats
