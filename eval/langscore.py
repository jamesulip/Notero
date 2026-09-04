"""Word-level scoring split by language class, for Taglish.

A pooled WER hides the failure this project is most exposed to: a language
mode that transcribes the Tagalog fine and mangles the English, or the other
way round, or that breaks exactly where the speaker switches. This module
aligns a hypothesis to its reference word by word and then asks three things
of the alignment:

  * how many Filipino reference words were substituted or deleted,
  * how many English reference words were,
  * how the error rate at code-switch points (a word whose language differs
    from the previous word's) compares with the rate elsewhere.

References carry no language tags, so words are classed heuristically:
a Tagalog affix joined with a hyphen ("i-send", "nag-review") is Filipino, a
curated list of Tagalog function words and everyday vocabulary is Filipino,
digits are "other", anything in the system English lexicon is English, and
what remains -- Tagalog orthography the lexicon does not know -- is Filipino.
The heuristic is stated so it can be argued with; it is not ground truth.

    from langscore import classify_words, score
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import unicodedata

sys.path.insert(0, str(Path(__file__).resolve().parent))


def normalize(text: str) -> list[str]:
    """`score.normalize`, except that a hyphen inside a word survives.

    The pooled scorer splits "i-send" into two tokens, which is fine for a
    WER but throws away the one orthographic cue that marks a Tagalog affix
    on an English stem. WER here can therefore differ from `score.py` by the
    handful of hyphenated words in a clip."""
    text = unicodedata.normalize("NFKC", text).lower()
    text = text.replace("\u2019", "'").replace("\u2018", "'").replace("\u2013", "-").replace("\u2014", " ")
    text = re.sub(r"[^\w\s'-]", " ", text)
    text = re.sub(r"(?<!\w)['-]|['-](?!\w)", " ", text)
    return text.split()

ENGLISH_LEXICON = Path("/usr/share/dict/words")

# Tagalog verbal affixes written with a hyphen before an English (or any) stem.
AFFIX = re.compile(
    r"^(i|na|nag|mag|pa|ma|pina|ipa|ipina|ka|um|in|maka|naka|magpa|nagpa|pag|pinag|mapa|napa|"
    r"pinaka|mang|nang|maki|naki|pakiki|nakiki|makipag|nakipag|ma|mai|nai)-\w+$"
)

# Function words and everyday vocabulary, including the Taglish spellings that
# a dictionary of formal Tagalog would miss. Several ("at", "may", "din",
# "pa", "no", "so") collide with English words; here Tagalog wins, because in
# a Taglish reference those spellings are overwhelmingly the Tagalog word.
TAGALOG = set("""
ang ng mga sa na at ay si ni kay kina nina ko mo niya namin natin ninyo nila ako ikaw ka siya kami
tayo kayo sila ito iyan iyon yan yun yung nito niyan niyon dito diyan doon rito riyan roon
hindi oo opo wala walang may mayroon meron kung kasi para pero tapos lang lamang din rin naman
ba po ho daw raw kaya dahil kailangan pwede puwede dapat gusto ayaw baka siguro talaga sobra
medyo masyado lahat bawat ilan marami konti kaunti isa dalawa tatlo apat lima anim pito walo siyam
sampu una pangalawa pangatlo huli panghuli ngayon kanina mamaya bukas kahapon araw gabi umaga
hapon linggo buwan taon oras minuto sandali muna ulit uli pala nga eh ah ha o kasi kaso saka
sana yata ata daw kung paano bakit sino ano saan kailan alin ilang gaano magkano dito sa
ganito ganyan ganoon ganun ganon kasi kase pag kapag habang bago pagkatapos hanggang mula
tungkol laban ayon gaya tulad para sa kay mismo lalo lalong higit mas pinaka sobrang
ako'y siya'y ika'y tayo'y kami'y sila'y ito'y iyan'y iyon'y wala'y may'y
gawa gawin ginawa gagawin gumawa sabi sinabi sasabihin magsabi kita nakita makita tingin tingnan
alam alamin malaman kilala punta pumunta pupunta bili bumili bibili kain kumain kakain uwi umuwi
uuwi bigay ibigay binigay kuha kunin kinuha dala dalhin dinala tawag tawagin tinawag usap
mag-usap nag-usap pag-usapan hintay hintayin naghihintay tulong tumulong tulungan trabaho
nagtatrabaho magtrabaho pera bahay kotse tao mga tao anak asawa magulang kaibigan kasama 
kumpanya opisina tanong sagot sumagot sagutin problema solusyon ayos sige
salamat pasensya paumanhin pakiusap tama mali totoo tunay sarili sarap ganda mahal mura
malaki maliit mahaba maikli matagal mabilis mabagal madali mahirap bago luma marunong
""".split())

_LEXICON: set[str] | None = None


def english_lexicon() -> set[str] | None:
    """The system word list, lower-cased, or None if this machine has none."""
    global _LEXICON
    if _LEXICON is None:
        if ENGLISH_LEXICON.exists():
            _LEXICON = {w.strip().lower() for w in ENGLISH_LEXICON.read_text(errors="ignore").split()}
        else:
            _LEXICON = set()
    return _LEXICON or None


def classify(word: str, english: set[str] | None) -> str:
    """'tl', 'en' or 'other' for one normalized word."""
    if word.isdigit():
        return "other"
    if AFFIX.match(word):
        return "tl"
    bare = word.strip("'")
    if bare in TAGALOG:
        return "tl"
    if english is not None and (bare in english or bare.rstrip("s") in english):
        return "en"
    return "tl"


def classify_words(words: list[str]) -> list[str]:
    english = english_lexicon()
    return [classify(w, english) for w in words]


def align(ref: list[str], hyp: list[str]) -> list[tuple[str, int | None, int | None]]:
    """Minimum-edit alignment as (op, ref_index, hyp_index) with op in
    eq / sub / del / ins. Same cost model as `score.levenshtein`."""
    n, m = len(ref), len(hyp)
    dist = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dist[i][0] = i
    for j in range(1, m + 1):
        dist[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                dist[i][j] = dist[i - 1][j - 1]
            else:
                dist[i][j] = 1 + min(dist[i - 1][j - 1], dist[i - 1][j], dist[i][j - 1])
    ops: list[tuple[str, int | None, int | None]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1] and dist[i][j] == dist[i - 1][j - 1]:
            ops.append(("eq", i - 1, j - 1))
            i, j = i - 1, j - 1
        elif i > 0 and j > 0 and dist[i][j] == dist[i - 1][j - 1] + 1:
            ops.append(("sub", i - 1, j - 1))
            i, j = i - 1, j - 1
        elif i > 0 and dist[i][j] == dist[i - 1][j] + 1:
            ops.append(("del", i - 1, None))
            i -= 1
        else:
            ops.append(("ins", None, j - 1))
            j -= 1
    ops.reverse()
    return ops


def score(reference: str, hypothesis: str) -> dict:
    ref = normalize(reference)
    hyp = normalize(hypothesis)
    ref_class = classify_words(ref)
    hyp_class = classify_words(hyp)
    ops = align(ref, hyp)

    subs = sum(1 for op, _, _ in ops if op == "sub")
    dels = sum(1 for op, _, _ in ops if op == "del")
    ins = sum(1 for op, _, _ in ops if op == "ins")

    per_class = {c: {"ref_words": 0, "errors": 0, "insertions": 0} for c in ("tl", "en", "other")}
    for c in ref_class:
        per_class[c]["ref_words"] += 1
    for op, ri, hj in ops:
        if op in ("sub", "del") and ri is not None:
            per_class[ref_class[ri]]["errors"] += 1
        elif op == "ins" and hj is not None:
            per_class[hyp_class[hj]]["insertions"] += 1
    for c in per_class:
        n = per_class[c]["ref_words"]
        per_class[c]["error_rate"] = per_class[c]["errors"] / n if n else None

    # Code-switch points: reference positions whose class differs from the
    # previous word's, both being a language (not digits).
    switch_positions = {
        i for i in range(1, len(ref))
        if ref_class[i] != ref_class[i - 1] and "other" not in (ref_class[i], ref_class[i - 1])
    }
    wrong_at = {ri for op, ri, _ in ops if op in ("sub", "del") and ri is not None}
    switch_errors = len(switch_positions & wrong_at)
    non_switch = [i for i in range(len(ref)) if i not in switch_positions]
    non_switch_errors = sum(1 for i in non_switch if i in wrong_at)

    return {
        "ref_words": len(ref),
        "hyp_words": len(hyp),
        "sub": subs,
        "del": dels,
        "ins": ins,
        "wer": (subs + dels + ins) / len(ref) if ref else None,
        "by_class": per_class,
        "code_switch": {
            "positions": len(switch_positions),
            "errors": switch_errors,
            "error_rate": switch_errors / len(switch_positions) if switch_positions else None,
            "non_switch_error_rate": non_switch_errors / len(non_switch) if non_switch else None,
        },
    }


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("hypothesis", type=Path)
    args = parser.parse_args()
    print(json.dumps(score(args.reference.read_text(), args.hypothesis.read_text()), indent=2))
