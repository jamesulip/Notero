"""Language labels for tokens, and a Tagalog affix analyser, for the error taxonomy.

Two kinds of label exist and they are never merged:

  * `verified`   the reference carries a word-level tag (`taxonomy_io`): a person said so.
                 This module does not check the person.
  * `heuristic`  this module guessed from word lists and spelling rules written for this
                 project (`eval/taxonomy-data/`, provenance in `eval/TAXONOMY.md`).

A heuristic label is one of: tl, en, mix (a Tagalog affix on an English stem), name, other,
`ambiguous` (the word is a word of both languages, or the context disagrees) and `unknown`
(no list or rule matched). `unknown` is the honest answer for most words the lists do not
cover; unlike `langscore.classify` this module never falls back to "Filipino". Every label
carries a `why` naming the rule that produced it, so a count can be audited by rule.
"""

from __future__ import annotations

import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from taxonomy_io import TAG_LANG  # noqa: E402

DATA_DIR = Path(__file__).resolve().parent / "taxonomy-data"

LANGS = ("tl", "en", "mix", "name", "other", "ambiguous", "unknown")

VOWELS = set("aeiou")

#: Tagalog verbal prefixes, longest first so the longest match is tried first. Compound
#: prefixes are listed whole ("nakapag", "ipinag").
PREFIXES = sorted({
    "nakapag", "makapag", "ipinapa", "ipinag", "ipinaka", "pinaka", "pinagka", "pinag", "nagpaka",
    "magpaka", "nagpa", "magpa", "nagsi", "magsi", "nagka", "magka", "nakipag", "makipag", "nakiki",
    "pakiki", "napaka", "naka", "maka", "napa", "mapa", "naki", "maki", "paki", "ipag", "ipang", "ipa",
    "ipina", "pina", "pang", "pam", "pan", "mang", "nang", "mam", "nam", "nag", "mag", "pag", "ika",
    "ka", "pa", "ma", "na", "i",
}, key=lambda p: (-len(p), p))
#: Prefixes that, written alone before a hyphen, mark a Tagalog affix on a stem ("i-send").
AFFIX_PIECES = frozenset(p for p in PREFIXES if p != "ka") | {"ka", "um", "in"}
SUFFIXES = ("han", "hin", "an", "in")
#: Words that are never the root of an affixed form: a decomposition that ends in one of them
#: ("ma" + "nila" = "manila") is an accident, not morphology.
FUNCTION_WORDS = frozenset("""
ang ng mga sa si ni kay kina nina sina ay at o na pa ba po ho ito iyan iyon yan yun yon dito diyan doon
ako ikaw ka siya kami tayo kayo sila ko mo niya namin natin ninyo nyo nila akin iyo kanya amin atin inyo
kanila hindi di huwag wag wala may mayroon meron lang din rin daw raw naman nga pala yata ata muna sana
kasi kaya pero para kung kapag pag habang bago mula tungkol man ano sino saan kailan bakit paano alin ilan
gaano magkano
""".split())
_CONTRACTION_TAILS = {"s", "t", "re", "ve", "ll", "d", "m"}
_CLITIC_TAILS = {"yo", "yun", "yan", "yon", "yung", "to"}
_ACRONYM = re.compile(r"^[A-Z]{2,6}$")


@dataclass(frozen=True, slots=True)
class Label:
    lang: str      # one of LANGS
    basis: str     # "verified" | "heuristic"
    why: str       # the rule, e.g. "tag", "lexicon-tl", "no-match"


def _read_words(path: Path) -> list[str]:
    words: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0]
        for w in line.split():
            words.extend(p for p in w.lower().split("-") if p)
    return words


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Lexicon:
    """The word lists. `english_wordlist` adds a user-supplied file (for example the system
    word list) to the English list; its hash goes into the report because it changes labels."""

    def __init__(self, data_dir: Path = DATA_DIR, english_wordlist: Path | None = None):
        self.data_dir = Path(data_dir)
        self.files: dict[str, dict] = {}
        self.tl = set(self._load("lexicon-tl.txt"))
        self.en = set(self._load("lexicon-en.txt"))
        if english_wordlist is not None:
            extra = [w.strip().lower() for w in Path(english_wordlist).read_text(errors="ignore").split()]
            extra = [w for w in extra if w.isalpha()]
            self.en |= set(extra)
            self.files["english-wordlist (user supplied)"] = {
                "entries": len(set(extra)), "sha256": _sha(Path(english_wordlist)),
                "source": "supplied with --english-wordlist; not part of the repository"}
        self.names = set(self._load("lexicon-names.txt"))
        self.other = set(self._load("lexicon-other.txt"))
        self.particles = set(self._load("particles.txt"))
        self.homographs = set(self._load("homographs.txt"))
        self.variant_of: dict[str, int] = {}
        for n, line in enumerate(self._variant_lines()):
            for w in line:
                self.variant_of.setdefault(w, n)
        self.tl_en_overlap = sorted(self.tl & self.en)
        self.cache: dict[str, "Label"] = {}

    def _load(self, name: str) -> list[str]:
        path = self.data_dir / name
        words = _read_words(path)
        self.files[name] = {"entries": len(set(words)), "sha256": _sha(path),
                            "source": "written for this project by Claude (an AI model); no native-speaker review"}
        return words

    def _variant_lines(self) -> list[list[str]]:
        path = self.data_dir / "spelling-variants.txt"
        self.files["spelling-variants.txt"] = {"entries": 0, "sha256": _sha(path),
                                               "source": "written for this project by Claude (an AI model); no native-speaker review"}
        lines = []
        for line in path.read_text(encoding="utf-8").splitlines():
            words = line.split("#", 1)[0].split()
            if len(words) > 1:
                lines.append([w.lower() for w in words])
        self.files["spelling-variants.txt"]["entries"] = len(lines)
        return lines

    def same_variant(self, a: str, b: str) -> bool:
        return a != b and a in self.variant_of and self.variant_of.get(a) == self.variant_of.get(b)

    def describe(self) -> dict:
        return {name: dict(info) for name, info in sorted(self.files.items())}


# ------------------------------------------------------------------ English inflection

def en_stems(word: str) -> list[str]:
    """Plausible base forms of a regular English inflection, for a lexicon lookup. Long words
    only: a short word that is not listed is not guessed at."""
    if len(word) < 5:
        return []
    out: list[str] = []
    for suffix, repl in (("ies", "y"), ("es", ""), ("s", ""), ("ed", ""), ("ed", "e"), ("ing", ""), ("ing", "e"),
                         ("ly", ""), ("ers", ""), ("er", ""), ("er", "e"), ("est", ""), ("d", "")):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            stem = word[: -len(suffix)] + repl
            out.append(stem)
            if len(stem) > 3 and stem[-1] == stem[-2]:          # stopped -> stop
                out.append(stem[:-1])
    return out


# ------------------------------------------------------------------ Tagalog morphology

@dataclass(frozen=True, slots=True)
class Analysis:
    prefix: str
    infix: str
    redup: str
    root: str
    suffix: str

    @property
    def pieces(self) -> int:
        return sum(1 for p in (self.prefix, self.infix, self.redup, self.suffix) if p)

    def affixes(self) -> tuple[str, str, str]:
        return (self.prefix, self.infix, self.suffix)


def _reduplications(rest: str) -> list[tuple[str, str]]:
    """(reduplicated syllable, remainder) readings of `rest`: Tagalog repeats the first
    consonant and vowel of the root ("kakain", "magtatrabaho") or just its first vowel."""
    out = [("", rest)]
    if len(rest) >= 4:
        if rest[0] in VOWELS:
            if rest[1:].startswith(rest[0]):
                out.append((rest[0], rest[1:]))
        else:
            cv = rest[:2]
            tail = rest[2:]
            if cv[1] in VOWELS and tail[:1] == cv[0]:
                v = next((c for c in tail[1:] if c in VOWELS), "")
                if v == cv[1]:
                    out.append((cv, tail))
    return out


def analyses(word: str, *, min_root: int = 3) -> list[Analysis]:
    """Every way to read `word` as (prefix)(infix)(reduplication) + root + (suffix) with the
    Tagalog affixes above. The word itself is always one reading, with no affix."""
    out = [Analysis("", "", "", word, "")]
    prefixes = [""] + [p for p in PREFIXES if word.startswith(p) and len(word) - len(p) >= min_root]
    for pre in prefixes:
        rest = word[len(pre):]
        shapes: list[tuple[str, str]] = [("", rest)]
        if rest[:1] and rest[0] not in VOWELS:
            for inf in ("um", "in"):
                if rest[1:3] == inf:
                    shapes.append((inf, rest[0] + rest[3:]))
        else:
            for inf in ("um", "in"):
                if rest.startswith(inf):
                    shapes.append((inf, rest[2:]))
        for inf, r in shapes:
            for red, root in _reduplications(r):
                for suf in [""] + [s for s in SUFFIXES if root.endswith(s) and len(root) - len(s) >= min_root]:
                    stem = root[: len(root) - len(suf)] if suf else root
                    if len(stem) < min_root:
                        continue
                    a = Analysis(pre, inf, red, stem, suf)
                    if a not in out:
                        out.append(a)
    return out


def tagalog_root(word: str, lex: Lexicon) -> Analysis | None:
    """The least-affixed reading of `word` whose root is a listed Tagalog word, if any."""
    best: Analysis | None = None
    for a in analyses(word):
        if a.pieces and a.root in lex.tl and a.root not in FUNCTION_WORDS and (best is None or a.pieces < best.pieces):
            best = a
    return best


def morphology_relation(ref: str, hyp: str, lex: Lexicon) -> tuple[str, dict] | None:
    """If `ref` and `hyp` are two forms of one Tagalog root, (subtype, detail), else None.

    Subtypes: ligature_dropped / ligature_added (the linker -ng / -g), reduplication_dropped /
    reduplication_added, affix_missing (the hypothesis has fewer affixes), affix_added,
    affix_changed. Never applied when both words are English words. The root must be a listed
    Tagalog word; with an unlisted root only a root of 4+ letters between two non-English
    words is accepted, and the detail says `root_listed: False`."""
    if ref == hyp or (ref in lex.en and hyp in lex.en):
        return None

    def linker(base: str) -> str | None:
        if len(base) < 3:
            return None
        if base[-1] in VOWELS:
            return base + "ng"
        if base[-1] == "n":
            return base + "g"
        return None

    if linker(hyp) == ref:
        return "ligature_dropped", {"base": hyp, "root_listed": hyp in lex.tl}
    if linker(ref) == hyp:
        return "ligature_added", {"base": ref, "root_listed": ref in lex.tl}

    best: tuple[int, Analysis, Analysis] | None = None
    ar, ah = analyses(ref), analyses(hyp)
    for x in ar:
        for y in ah:
            if x.root != y.root or len(x.root) < 3 or x == y:
                continue
            cost = x.pieces + y.pieces
            if best is None or cost < best[0]:
                best = (cost, x, y)
    if best is None:
        return None
    _, x, y = best
    if x.root in FUNCTION_WORDS:
        return None
    listed = x.root in lex.tl
    if not listed and not (len(x.root) >= 4 and ref not in lex.en and hyp not in lex.en):
        return None
    detail = {"root": x.root, "root_listed": listed}
    if (x.prefix, x.infix, x.suffix) == (y.prefix, y.infix, y.suffix):
        return ("reduplication_dropped" if x.redup else "reduplication_added"), detail
    if x.pieces > y.pieces:
        return "affix_missing", detail
    if x.pieces < y.pieces:
        return "affix_added", detail
    return "affix_changed", detail


def split_mixed(token: str, lex: Lexicon) -> tuple[str, str] | None:
    """(affix, stem) of an unhyphenated Tagalog-affix + English-stem word ("nagmeeting")."""
    for p in PREFIXES:
        if token.startswith(p) and len(token) - len(p) >= 4:
            stem = token[len(p):]
            if stem in lex.en or any(s in lex.en for s in en_stems(stem)):
                return p, stem
    return None


# ------------------------------------------------------------------ word and token labels

def _in_en(word: str, lex: Lexicon) -> str | None:
    if word in lex.en:
        return "lexicon-en"
    if any(s in lex.en for s in en_stems(word)):
        return "en-inflection"
    return None


def _in_tl(word: str, lex: Lexicon) -> str | None:
    if word in lex.tl:
        return "lexicon-tl"
    # The linker: -ng after a vowel, -g after n ("daming" = dami + ng, "luntiang" = luntian + g).
    if word.endswith("ng") and len(word) > 4 and word[-3] in VOWELS and word[:-2] in lex.tl:
        return "tl-ligature"
    if word.endswith("g") and len(word) > 4 and word[-2] == "n" and word[:-1] in lex.tl:
        return "tl-ligature"
    if tagalog_root(word, lex) is not None:
        return "tl-affix-analysis"
    return None


def classify_word(word: str, lex: Lexicon) -> Label:
    """Heuristic label of one normalised word, without case or context."""
    hit = lex.cache.get(word)
    if hit is None:
        hit = lex.cache[word] = _classify_word(word, lex)
    return hit


def _classify_word(word: str, lex: Lexicon) -> Label:
    if word.isdigit():
        return Label("other", "heuristic", "digits")
    if any(ch.isdigit() for ch in word) and any(ch.isalpha() for ch in word):
        return Label("other", "heuristic", "alphanumeric")
    if "'" in word:
        head, _, tail = word.partition("'")
        if tail in _CONTRACTION_TAILS and head:
            return Label("en", "heuristic", "english-contraction")
        if tail == "y" and head and (_in_tl(head, lex) or head in lex.tl):
            return Label("tl", "heuristic", "tagalog-clitic-y")
        if tail in _CLITIC_TAILS and head in lex.tl:
            return Label("tl", "heuristic", "tagalog-clitic")
        return Label("unknown", "heuristic", "apostrophe-no-match")
    if word in lex.other or re.fullmatch(r"(?:ha|he|hi|ho)+", word):
        return Label("other", "heuristic", "filler-or-laughter")
    if word in lex.homographs:
        return Label("ambiguous", "heuristic", "homograph-list")
    if word in lex.names and word not in lex.tl and word not in lex.en:
        return Label("name", "heuristic", "names-lexicon")
    tl, en = _in_tl(word, lex), _in_en(word, lex)
    if tl and en:
        return Label("ambiguous", "heuristic", "in-both-lexicons")
    if tl:
        return Label("tl", "heuristic", tl)
    if en:
        return Label("en", "heuristic", en)
    return Label("unknown", "heuristic", "no-match")


def label_tokens(tokens: list, lex: Lexicon, *, cased: bool, context: bool = True) -> list[Label]:
    """One Label per token. Verified tags win; everything else is `heuristic`."""
    labels: list[Label | None] = [None] * len(tokens)
    # Hyphenated words are judged as a whole before their pieces are judged alone.
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok.group is not None:
            j = i
            while j < len(tokens) and tokens[j].group == tok.group:
                j += 1
            labels[i:j] = _label_group(tokens[i:j], lex, cased)
            i = j
        else:
            labels[i] = _label_token(tok, lex, cased)
            i += 1
    result = [lab if lab is not None else Label("unknown", "heuristic", "no-match") for lab in labels]
    if context:
        result = _resolve_context(tokens, result)
    return result


def _label_token(tok, lex: Lexicon, cased: bool) -> Label:
    if tok.tag:
        return Label(TAG_LANG[tok.tag], "verified", "tag")
    if cased:
        s = tok.surface
        if len(s) >= 2 and _ACRONYM.match(s):
            return Label("other", "heuristic", "acronym")
        if (s[:1].isupper() and not tok.sentence_start and s != "I" and not s.isupper()
                and tok.text not in lex.tl and tok.text not in lex.en and tok.text not in lex.homographs):
            # Conservative: a capitalised word that is an ordinary word of either list ("Naku",
            # "Boss", "Discord") is not called a name; it keeps its language label.
            return Label("name", "heuristic", "capitalised-mid-sentence")
    return classify_word(tok.text, lex)


def _label_group(group: list, lex: Lexicon, cased: bool) -> list[Label]:
    if all(t.tag for t in group):
        return [_label_token(t, lex, cased) for t in group]
    first, stem = group[0], group[-1]
    if len(group) == 2 and first.text in AFFIX_PIECES and not any(t.tag for t in group):
        tl, en = _in_tl(stem.text, lex), _in_en(stem.text, lex)
        if en and not tl:
            return [Label("mix", "heuristic", "affix+english-stem")] * 2
        if tl and not en:
            return [Label("tl", "heuristic", "affix+tagalog-stem")] * 2
        if tl and en:
            return [Label("ambiguous", "heuristic", "affix+stem-in-both-lexicons")] * 2
        return [Label("unknown", "heuristic", "affix+unlisted-stem")] * 2
    return [_label_token(t, lex, cased) for t in group]


def _resolve_context(tokens: list, labels: list[Label]) -> list[Label]:
    """An `ambiguous` word whose two neighbours in the same utterance are both clearly
    Tagalog (or both clearly English) takes that language, marked `context`. One pass, from
    the first-pass labels only, so the result does not depend on the order of resolution."""
    out = list(labels)
    for i, lab in enumerate(labels):
        if lab.lang != "ambiguous" or lab.basis != "heuristic" or lab.why not in ("homograph-list", "in-both-lexicons"):
            continue
        if 0 < i < len(tokens) - 1 and tokens[i - 1].utt == tokens[i].utt == tokens[i + 1].utt:
            a, b = labels[i - 1], labels[i + 1]
            if a.lang == b.lang and a.lang in ("tl", "en"):
                out[i] = Label(a.lang, "heuristic", "context")
    return out
