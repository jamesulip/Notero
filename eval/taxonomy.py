"""Error taxonomy for Taglish transcripts: what kind of mistake was each word error?

A WER says how many words were wrong. For Filipino-English code-switching the useful
question is which kind of wrong: a Tagalog word written in English, a missing affix, a lost
name, a run of invented words in a silence, a stretch of speech that was never decoded. This
tool aligns a hypothesis to its reference with the same tokens and the same edit distance as
the headline WER (`score.normalize`, `langscore.align`), so **the categories partition the
errors: their error words add up to substitutions + deletions + insertions, exactly**. Nothing
here changes an existing number; it is an optional report on top of them.

Categories (a word error belongs to exactly one; first match wins; eval/TAXONOMY.md has the
exact order and the subtypes)::

    spelling_variant      a join/split of the same letters ("nagmeeting" / "nag meeting")
    deleted_speech        a run of >= 3 reference words with no hypothesis word
    hallucination         a run of >= 3 inserted words (repetition loops flagged; flagged
                          `outside_reference_speech` when the reference has times)
    mixed_word_error      a Tagalog affix + English stem ("nag-meeting", "i-share", "naka-mute")
    proper_noun_error     a reference name deleted or replaced
    spelling_variant      the same word spelled another way (a listed variant)
    morphology_error      same Tagalog root, wrong or missing affix, reduplication or linker
    enclitic_particle     po, naman, lang, na, pa, ... deleted, inserted or replaced
    boundary_error        a word at a code-switch point deleted or replaced
    tl_to_en_substitution / en_to_tl_substitution
                          a Tagalog word replaced by an English one, or the reverse
    other_substitution / other_deletion / other_insertion

(A name, a mixed word and a listed variant are mutually exclusive in practice, so their relative
order does not change a count.)

`timestamp_misalignment` is not a category: it is an overlay on words that were recognised
(a correct or substituted word whose hypothesis time lies outside its reference utterance)
and is reported on its own, only when both sides have times.

Every event carries a `basis`, and every count is split by it:

    verified    the reference carries the word-level tags the category needs
    heuristic   the label came from the word lists and rules in taxonomy_lex.py
    structural  the alignment alone decides it (runs of missing or invented words)

`heuristic` and `verified` are never added together. A language label for a hypothesis
word is always heuristic, so a language-direction substitution is heuristic unless a person
adjudicated it (`--adjudications`).

    python3 -I eval/taxonomy.py report --manifest M.json --hyp-dir DIR --out-dir OUT
    python3 -I eval/taxonomy.py pair --reference R.tagged.txt --hypothesis H.txt
    python3 -I eval/taxonomy.py plan --plan PLAN.json --out-dir OUT
    python3 -I eval/taxonomy.py table A.json B.json
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(EVAL_DIR))

import langscore  # noqa: E402
import score as pooled  # noqa: E402
import taxonomy_io as tio  # noqa: E402
import taxonomy_lex as tlx  # noqa: E402

TOOL_VERSION = 1
SCHEMA = "notero-taxonomy-report/1"
CONFIG_PATH = EVAL_DIR / "taxonomy-config.v1.json"

#: category -> one-line definition. Order is the order of every table.
CATEGORIES: dict[str, str] = {
    "tl_to_en_substitution": "a Tagalog reference word replaced by an English word (by the output word's language, not the intent)",
    "en_to_tl_substitution": "an English reference word replaced by a Tagalog word or Tagalog spelling of it",
    "boundary_error": "a word at a code-switch point (first word after a switch, or last before one) deleted or replaced",
    "mixed_word_error": "a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled",
    "morphology_error": "the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g)",
    "proper_noun_error": "a reference proper name deleted or replaced",
    "hallucination": "a run of inserted words (3 or more), with no reference word behind it",
    "deleted_speech": "a run of deleted reference words (3 or more), speech that produced no output",
    "enclitic_particle": "an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced",
    "spelling_variant": "the same word with another spelling or spacing; arguably not a recognition error",
    "other_substitution": "a substitution that no rule above explains",
    "other_deletion": "an isolated deleted word (fewer than 3 in a row) that no rule above explains",
    "other_insertion": "an isolated inserted word (fewer than 3 in a row) that no rule above explains",
}
FLAG_MEANING = {
    "at_boundary": "the reference word is next to a code-switch point (any category)",
    "short_reference_word": f"the reference word has at most {4} letters (substitution categories)",
    "outside_reference_speech": "at least 80% of the timed inserted words fall outside every padded reference utterance",
    "inside_reference_speech": "fewer than 80% of the timed inserted words fall outside reference speech",
    "time_unknown": "the reference has no times, or the hypothesis has no word times",
    "language_unresolved": "the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word",
    "root_unlisted": "the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words)",
}
#: Substitution categories that also say whether the reference word was short (<= 4 letters):
#: most Tagalog function words are, and a short word is easy to mishear.
SHORT_WORD = 4
SHORT_WORD_CATEGORIES = {"tl_to_en_substitution", "en_to_tl_substitution", "boundary_error", "other_substitution"}
STRUCTURAL = {"hallucination", "deleted_speech", "other_deletion", "other_insertion"}
BASES = ("verified", "heuristic", "structural")


class TooLarge(Exception):
    pass


#: Which of several equal-cost alignments the backtrace takes. The total never changes; the split into
#: substitutions, deletions and insertions, and therefore some category counts, does. "default" is
#: `langscore.align` (the order sub, del, ins), the aligner of the older tools.
TIE_BREAKS = {"default": ("sub", "del", "ins"), "del-ins-sub": ("del", "ins", "sub"),
              "ins-del-sub": ("ins", "del", "sub")}


def align(ref: list[str], hyp: list[str], tie_break: str = "default") -> list[tuple]:
    if tie_break == "default":
        return langscore.align(ref, hyp)
    order = TIE_BREAKS[tie_break]
    n, m = len(ref), len(hyp)
    dist = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        dist[i][0] = i
    for j in range(1, m + 1):
        dist[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            dist[i][j] = dist[i - 1][j - 1] if ref[i - 1] == hyp[j - 1] else 1 + min(
                dist[i - 1][j - 1], dist[i - 1][j], dist[i][j - 1])
    ops: list[tuple] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1] and dist[i][j] == dist[i - 1][j - 1]:
            ops.append(("eq", i - 1, j - 1))
            i, j = i - 1, j - 1
            continue
        for kind in order:
            if kind == "sub" and i > 0 and j > 0 and dist[i][j] == dist[i - 1][j - 1] + 1:
                ops.append(("sub", i - 1, j - 1))
                i, j = i - 1, j - 1
                break
            if kind == "del" and i > 0 and dist[i][j] == dist[i - 1][j] + 1:
                ops.append(("del", i - 1, None))
                i -= 1
                break
            if kind == "ins" and j > 0 and dist[i][j] == dist[i][j - 1] + 1:
                ops.append(("ins", None, j - 1))
                j -= 1
                break
    ops.reverse()
    return ops


# ------------------------------------------------------------------ configuration

def load_config(path: Path | None = None) -> dict:
    cfg = json.loads(Path(path or CONFIG_PATH).read_text())
    canonical = json.dumps(cfg, sort_keys=True, separators=(",", ":"))
    cfg = dict(cfg)
    cfg["fingerprintSha256"] = hashlib.sha256(canonical.encode()).hexdigest()
    return cfg


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# ------------------------------------------------------------------ small helpers

def char_similarity(a: str, b: str) -> float:
    """1 - (character edit distance / longer length): 1.0 identical, 0.0 nothing shared."""
    if a == b:
        return 1.0
    n, m = len(a), len(b)
    if not n or not m:
        return 0.0
    prev = list(range(m + 1))
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        for j in range(1, m + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return 1 - prev[m] / max(n, m)


def merge(dst: dict, src: dict) -> dict:
    """Add the numeric leaves of `src` into `dst` (`max_*` keys take the maximum)."""
    for k, v in src.items():
        if isinstance(v, dict):
            merge(dst.setdefault(k, {}), v)
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            if k.startswith("max_"):
                dst[k] = max(dst.get(k, v), v)
            else:
                dst[k] = dst.get(k, 0) + v
    return dst


def bump(d: dict, *path, by: int = 1) -> None:
    for key in path[:-1]:
        d = d.setdefault(key, {})
    d[path[-1]] = d.get(path[-1], 0) + by


def ratio(a: int, b: int) -> float | None:
    return round(a / b, 6) if b else None


@dataclass
class Event:
    category: str
    subtype: str
    basis: str
    ref_idx: list[int]
    hyp_idx: list[int]
    error_words: int
    flags: list[str] = field(default_factory=list)
    adjudicated_from: str | None = None


# ------------------------------------------------------------------ reference speech and boundaries

def speech_intervals(ref: tio.Reference, cfg: dict) -> list[tuple[int, int]]:
    pad = cfg["nonSpeechPaddingMs"]
    spans = sorted((u.start_ms - pad, u.end_ms + pad) for u in ref.utterances if u.timed)
    merged: list[list[int]] = []
    for s, e in spans:
        if merged and s <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged]


def inside(intervals: list[tuple[int, int]], t: float) -> bool:
    i = bisect.bisect_right(intervals, (t, float("inf"))) - 1
    return i >= 0 and intervals[i][0] <= t <= intervals[i][1]


def code_switch_points(tokens: list, labels: list) -> tuple[dict[int, list], list]:
    """Switch points between two adjacent tokens of one utterance that are clearly Tagalog and
    clearly English. `info[i]` lists (role, neighbour, basis) for each switch token i, where
    role is "in" (first word after the switch) or "out" (last word before it)."""
    info: dict[int, list] = {}
    points = []
    for i in range(1, len(tokens)):
        a, b = labels[i - 1], labels[i]
        if (tokens[i].utt == tokens[i - 1].utt and a.lang in ("tl", "en") and b.lang in ("tl", "en")
                and a.lang != b.lang):
            basis = "verified" if a.basis == b.basis == "verified" else "heuristic"
            points.append((i - 1, i, basis))
            info.setdefault(i, []).append(("in", i - 1, basis))
            info.setdefault(i - 1, []).append(("out", i, basis))
    return info, points


def repetition_loop(words: list[str], cfg: dict) -> bool:
    rl = cfg["repetitionLoop"]
    run = 1
    for a, b in zip(words, words[1:]):
        run = run + 1 if a == b else 1
        if run >= rl["minIdenticalRun"]:
            return True
    return len(words) >= rl["minLength"] and len(set(words)) / len(words) <= rl["maxDistinctShare"]


# ------------------------------------------------------------------ the analysis of one item

def analyze_item(ref: tio.Reference, hyp: tio.Hypothesis, lex: tlx.Lexicon, cfg: dict,
                 adjudications: dict | None = None) -> tuple[dict, list[Event], dict]:
    """(counts, events, side data). `counts` is plain nested numbers, safe to add across items."""
    R = [t.text for t in ref.tokens]
    H = [t.text for t in hyp.tokens]
    if len(R) * len(H) > cfg["maxAlignmentCells"]:
        raise TooLarge(f"{len(R)} reference x {len(H)} hypothesis words is more than "
                       f"{cfg['maxAlignmentCells']} alignment cells; split the item by utterance")
    ops = align(R, H, cfg.get("tieBreak", "default"))
    rl = tlx.label_tokens(ref.tokens, lex, cased=ref.cased, context=cfg["contextResolution"])
    # A hypothesis word's capital letter is the model's choice, not evidence about the word, so
    # the capitalisation rule (names, acronyms) is applied to references only.
    hl = tlx.label_tokens(hyp.tokens, lex, cased=False, context=cfg["contextResolution"])
    bound, points = code_switch_points(ref.tokens, rl)
    intervals = speech_intervals(ref, cfg) if ref.has_times else []

    consumed = [False] * len(ops)
    op_of_ref = {ri: k for k, (_, ri, _) in enumerate(ops) if ri is not None}
    events: list[Event] = []

    def emit(category, subtype, basis, ks, flags=()):
        for k in ks:
            consumed[k] = True
        ref_idx = sorted({ops[k][1] for k in ks if ops[k][1] is not None})
        hyp_idx = sorted({ops[k][2] for k in ks if ops[k][2] is not None})
        flag_list = list(flags)
        if any(ri in bound for ri in ref_idx) and "at_boundary" not in flag_list:
            flag_list.append("at_boundary")
        if category in SHORT_WORD_CATEGORIES and ref_idx and all(len(R[i]) <= SHORT_WORD for i in ref_idx):
            flag_list.append("short_reference_word")
        events.append(Event(category, subtype, basis, ref_idx, hyp_idx, len(ks), sorted(set(flag_list))))

    # ---- regions: maximal runs of non-equal operations
    regions, cur = [], []
    for k, (op, _, _) in enumerate(ops):
        if op == "eq":
            if cur:
                regions.append(cur)
                cur = []
        else:
            cur.append(k)
    if cur:
        regions.append(cur)

    for region in regions:
        # A. the same letters split or joined differently: "nagmeeting" / "nag meeting".
        pos = 0
        while pos < len(region):
            for length in (2, 3, 4):
                win = region[pos:pos + length]
                if len(win) < length or any(consumed[k] for k in win):
                    continue
                rw = [R[ops[k][1]] for k in win if ops[k][1] is not None]
                hw = [H[ops[k][2]] for k in win if ops[k][2] is not None]
                if rw and hw and rw != hw and "".join(rw) == "".join(hw):
                    emit("spelling_variant", "spacing", "heuristic", win)
                    pos += length - 1
                    break
            pos += 1

        # B. runs of deleted or inserted words.
        for kind, minimum, category in (("del", cfg["deletionRunMinWords"], "deleted_speech"),
                                        ("ins", cfg["hallucinationMinWords"], "hallucination")):
            run: list[int] = []
            for k in region + [None]:
                if k is not None and ops[k][0] == kind and not consumed[k]:
                    run.append(k)
                    continue
                if len(run) >= minimum:
                    flags: list[str] = []
                    subtype = "run"
                    if kind == "ins":
                        words = [H[ops[x][2]] for x in run]
                        if repetition_loop(words, cfg):
                            subtype = "repetition_loop"
                        timed = [hyp.tokens[ops[x][2]] for x in run if hyp.tokens[ops[x][2]].start_ms is not None]
                        if not ref.has_times:
                            flags.append("time_unknown")
                        elif not timed:
                            flags.append("time_unknown")
                        else:
                            out = sum(1 for t in timed if not inside(intervals, (t.start_ms + t.end_ms) / 2))
                            flags.append("outside_reference_speech" if out / len(timed) >= cfg["outsideSpeechFraction"]
                                         else "inside_reference_speech")
                    emit(category, subtype, "structural", run, flags)
                run = []

        # C. a Tagalog-affix + English-stem word that was hyphenated in the reference.
        done_groups: set[int] = set()
        for k in region:
            if consumed[k] or ops[k][1] is None:
                continue
            tok = ref.tokens[ops[k][1]]
            if tok.group is None or tok.group in done_groups or rl[ops[k][1]].lang != "mix":
                continue
            done_groups.add(tok.group)
            members = [i for i in range(ops[k][1] - tok.group_pos, ops[k][1] - tok.group_pos + tok.group_len)]
            status = {i: (ops[op_of_ref[i]][0] if i in op_of_ref else "eq") for i in members}
            error_ks = [op_of_ref[i] for i in members if i in op_of_ref and ops[op_of_ref[i]][0] != "eq"
                        and not consumed[op_of_ref[i]]]
            if len(members) == 2:
                pair = (status[members[0]], status[members[1]])
                subtype = {("del", "eq"): "affix_dropped", ("sub", "eq"): "affix_changed",
                           ("eq", "del"): "stem_dropped", ("eq", "sub"): "stem_changed"}.get(pair, "both_wrong")
            else:
                subtype = "other"
            basis = "verified" if all(rl[i].basis == "verified" for i in members) else "heuristic"
            emit("mixed_word_error", subtype, basis, error_ks)

        # D. everything left, one word at a time.
        for k in region:
            if consumed[k]:
                continue
            op, ri, hj = ops[k]
            category, subtype, basis, flags = classify(op, ri, hj, ref, hyp, rl, hl, bound, lex, cfg)
            emit(category, subtype, basis, [k], flags)

    events.sort(key=lambda e: (e.ref_idx[0] if e.ref_idx else 10**9, e.hyp_idx[0] if e.hyp_idx else 10**9,
                               e.category))
    applied = 0
    keys_used: set[str] = set()
    if adjudications:
        for e in events:
            keys = [f"r{i}" for i in e.ref_idx] + [f"h{j}" for j in e.hyp_idx]
            matched = [k for k in keys if k in adjudications]
            keys_used.update(matched)
            if matched:
                hit = adjudications[matched[0]]
                e.adjudicated_from = e.category
                e.category, e.subtype, e.basis = hit[0], hit[1] or "adjudicated", "verified"
                applied += 1

    counts = _count_item(ref, hyp, ops, events, rl, hl, bound, points, intervals, cfg, applied, len(keys_used))
    return counts, events, {"ops": ops, "ref_labels": rl, "hyp_labels": hl}


def classify(op, ri, hj, ref, hyp, rl, hl, bound, lex, cfg):
    """(category, subtype, basis, flags) for one operation that no group rule took."""
    flags: list[str] = []
    if op == "ins":
        h = hyp.tokens[hj]
        if h.text in lex.particles:
            return "enclitic_particle", "inserted", "heuristic", flags
        return "other_insertion", "isolated", "structural", flags
    r = ref.tokens[ri]
    lab = rl[ri]
    if op == "del":
        if lab.lang == "name":
            return "proper_noun_error", "deleted", lab.basis, flags
        if lab.lang == "mix":
            return "mixed_word_error", "deleted", lab.basis, flags
        if r.text in lex.particles:
            return "enclitic_particle", "deleted", "heuristic", flags
        if ri in bound:
            return "boundary_error", "deleted", _boundary_basis(bound[ri]), flags
        return "other_deletion", "isolated", "structural", flags
    h = hyp.tokens[hj]
    hlab = hl[hj]
    if lab.lang == "name":
        near = char_similarity(r.text, h.text) >= cfg["nearMissSimilarity"]
        return "proper_noun_error", "near_spelling" if near else "different_word", lab.basis, flags
    if lex.same_variant(r.text, h.text):
        return "spelling_variant", "variant-table", "heuristic", flags
    if lab.lang == "mix":
        return "mixed_word_error", _mixed_subtype(r.text, h.text, lex), lab.basis, flags
    rel = tlx.morphology_relation(r.text, h.text, lex)
    if rel:
        subtype, detail = rel
        if not detail.get("root_listed", True):
            flags.append("root_unlisted")
        return "morphology_error", subtype, "heuristic", flags
    if r.text in lex.particles:
        return "enclitic_particle", "substituted", "heuristic", flags
    if ri in bound:
        role, nbr, _ = bound[ri][0]
        other = rl[nbr].lang
        if hlab.lang == other and hlab.lang in ("tl", "en"):
            subtype = "carry_over" if role == "in" else "anticipation"
        elif hlab.lang == lab.lang:
            subtype = "same_language"
        else:
            subtype = "unresolved"
        # The category (a switch point next to this word) rests on the reference tags, but the
        # subtype reads the hypothesis word's language, which no person tagged.
        return "boundary_error", subtype, "heuristic", flags
    if lab.lang in ("tl", "en") and hlab.lang in ("tl", "en") and lab.lang != hlab.lang:
        return f"{lab.lang}_to_{hlab.lang}_substitution", "heuristic-hypothesis-language", "heuristic", flags
    near = char_similarity(r.text, h.text) >= cfg["nearMissSimilarity"]
    if lab.lang not in ("tl", "en") or hlab.lang not in ("tl", "en"):
        flags.append("language_unresolved")
    return "other_substitution", "near_miss" if near else "unrelated", "heuristic", flags


def _boundary_basis(entries: list) -> str:
    return "verified" if all(b == "verified" for _, _, b in entries) else "heuristic"


def _mixed_subtype(ref_word: str, hyp_word: str, lex: tlx.Lexicon) -> str:
    split = tlx.split_mixed(ref_word, lex)
    if split is None:
        return "unspecified"
    affix, stem = split
    if hyp_word == stem:
        return "affix_dropped"
    hs = tlx.split_mixed(hyp_word, lex)
    if (hs and hs[1] == stem) or hyp_word.endswith(stem):
        return "affix_changed"
    if hyp_word.startswith(affix):
        return "stem_changed"
    return "replaced"


# ------------------------------------------------------------------ counting

def _count_item(ref, hyp, ops, events, rl, hl, bound, points, intervals, cfg, adjudicated, keys_used=0) -> dict:
    n = len(ref.tokens)
    s = sum(1 for op, _, _ in ops if op == "sub")
    d = sum(1 for op, _, _ in ops if op == "del")
    i = sum(1 for op, _, _ in ops if op == "ins")
    pooled_s, pooled_d, pooled_i = pooled.levenshtein([t.text for t in ref.tokens], [t.text for t in hyp.tokens])
    c: dict = {"items": 1, "ref_words": n, "hyp_words": len(hyp.tokens), "sub": s, "del": d, "ins": i,
               "errors": s + d + i, "standard_policy_errors": pooled_s + pooled_d + pooled_i,
               "adjudications_applied": adjudicated, "adjudication_keys_used": keys_used, "categories": {}}
    for e in events:
        cat = c["categories"].setdefault(e.category, {"events": 0, "error_words": 0, "basis": {}, "subtypes": {},
                                                      "flags": {}})
        cat["events"] += 1
        cat["error_words"] += e.error_words
        bump(cat, "basis", e.basis, "events")
        bump(cat, "basis", e.basis, "error_words", by=e.error_words)
        bump(cat, "subtypes", e.subtype, "events")
        bump(cat, "subtypes", e.subtype, "error_words", by=e.error_words)
        bump(cat, "subtypes", e.subtype, "basis", e.basis, by=e.error_words)
        for f in e.flags:
            bump(cat, "flags", f, "events")
            bump(cat, "flags", f, "error_words", by=e.error_words)
            bump(cat, "flags", f, "basis", e.basis, by=e.error_words)

    # language labels
    labels: dict = {"reference": {}, "reference_why": {}, "hypothesis": {}, "hypothesis_why": {}}
    for lab in rl:
        bump(labels["reference"], lab.basis, lab.lang)
        if lab.basis == "heuristic":
            bump(labels["reference_why"], lab.lang, lab.why)
    for lab in hl:
        bump(labels["hypothesis"], lab.basis, lab.lang)
        bump(labels["hypothesis_why"], lab.lang, lab.why)
    c["labels"] = labels

    # substitution language matrix and inserted-word languages
    matrix: dict = {}
    by_label: dict = {}
    inserted: dict = {}
    wrong_at: dict[int, str] = {}
    for op, ri, hj in ops:
        if op == "sub":
            bump(matrix, rl[ri].basis, rl[ri].lang, hl[hj].lang)
            wrong_at[ri] = "substitutions"
        elif op == "del":
            wrong_at[ri] = "deletions"
        elif op == "ins":
            bump(inserted, hl[hj].lang)
    for idx, lab in enumerate(rl):
        key = f"{lab.basis}|{lab.lang}"
        bump(by_label, key, "words")
        if idx in wrong_at:
            bump(by_label, key, wrong_at[idx])
    c["substitution_matrix"] = matrix
    c["by_reference_label"] = by_label
    c["inserted_by_hypothesis_language"] = inserted

    # code-switch points
    cs: dict = {"switch_points": {}, "boundary_words": {}, "boundary_errors": {}, "other_words": 0,
                "other_errors": 0, "labelled_other_words": {}, "labelled_other_errors": {}}
    for _, _, basis in points:
        bump(cs["switch_points"], basis)
    for idx in range(n):
        if idx in bound:
            basis = _boundary_basis(bound[idx])
            bump(cs["boundary_words"], basis)
            if idx in wrong_at:
                bump(cs["boundary_errors"], basis)
        else:
            cs["other_words"] += 1
            cs["other_errors"] += idx in wrong_at
            if rl[idx].lang in ("tl", "en"):      # the matched control: words a switch point could have been
                bump(cs["labelled_other_words"], rl[idx].basis)
                if idx in wrong_at:
                    bump(cs["labelled_other_errors"], rl[idx].basis)
    c["code_switch"] = cs

    # timestamps
    c["timestamps"] = _timestamps(ref, hyp, ops, cfg)
    return c


def _timestamps(ref, hyp, ops, cfg) -> dict:
    out: dict = {"items_checked": 0, "pairs": 0, "misaligned": 0, "offset_buckets": {}, "items_unavailable": {}}
    if not ref.has_times:
        out["items_unavailable"]["reference has no utterance times"] = 1
        return out
    if not hyp.timed_tokens:
        out["items_unavailable"][hyp.time_note or "hypothesis has no word times"] = 1
        return out
    out["items_checked"] = 1
    tol = cfg["timestampToleranceMs"]
    edges = cfg["timestampBucketsMs"]
    for op, ri, hj in ops:
        if op not in ("eq", "sub"):
            continue
        u = ref.utterances[ref.tokens[ri].utt]
        t = hyp.tokens[hj]
        if not u.timed or t.start_ms is None:
            continue
        mid = (t.start_ms + t.end_ms) / 2
        offset = max(0.0, u.start_ms - mid, mid - u.end_ms)
        out["pairs"] += 1
        if offset > tol:
            out["misaligned"] += 1
        label = "inside"
        if offset > 0:
            label = next((f"<={e}ms" for e in edges[1:] if offset <= e), f">{edges[-1]}ms")
        bump(out["offset_buckets"], label)
        out["max_offset_ms"] = max(out.get("max_offset_ms", 0), int(offset))
    return out


# ------------------------------------------------------------------ corpus runs

def load_manifest(path: Path) -> tuple[list[dict], dict]:
    data = json.loads(Path(path).read_text())
    if isinstance(data, dict):
        return list(data["items"]), {"corpusId": data.get("corpusId")}
    return list(data), {"corpusId": None}


def load_adjudications(path: Path | None) -> dict[str, dict]:
    """TSV: item <tab> r<ref index> | h<hyp index> <tab> category <tab> subtype <tab> note."""
    out: dict[str, dict] = {}
    if path is None:
        return out
    for n, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3 or parts[2] not in CATEGORIES or not parts[1][:1] in ("r", "h") or not parts[1][1:].isdigit():
            raise SystemExit(f"{path}:{n}: expected item<TAB>r12|h7<TAB>category[<TAB>subtype[<TAB>note]] with a known category")
        out.setdefault(parts[0], {})[parts[1]] = (parts[2], parts[3] if len(parts) > 3 else "")
    return out


def run_items(items: list[dict], base: Path, hyp_dir: Path, lex, cfg, adjudications, *, ref_path_of=None,
              hyp_path_of=None) -> dict:
    """Analyse each item; returns {"corpus": counts, "items": {id: counts}, "events": {id: [...]}, ...}."""
    corpus: dict = {}
    per_item: dict[str, dict] = {}
    events_by_item: dict[str, tuple] = {}
    missing: list[str] = []
    formats: dict[str, int] = {}
    tagged_items = tagged_tokens = skipped_spans = 0
    annotators: set[str] = set()
    hyp_formats: dict[str, int] = {}
    ids = [e["id"] for e in items]
    if len(set(ids)) != len(ids):
        dup = sorted({i for i in ids if ids.count(i) > 1})
        raise SystemExit(f"duplicate item ids in the manifest: {dup[:5]}")
    failed: dict[str, str] = {}
    adj_given = sum(len(v) for v in (adjudications or {}).values())
    adj_used = 0
    odd_tags = 0
    for entry in sorted(items, key=lambda e: e["id"]):
        item_id = entry["id"]
        ref_path = ref_path_of(entry) if ref_path_of else base / entry["ref"]
        hyp_path = hyp_path_of(entry) if hyp_path_of else _hyp_path(hyp_dir, item_id)
        if not ref_path.exists() or hyp_path is None:
            missing.append(item_id)
            continue
        try:
            ref = tio.load_reference(ref_path)
            hyp = tio.load_hypothesis(hyp_path)
            counts, events, side = analyze_item(ref, hyp, lex, cfg, (adjudications or {}).get(item_id))
        except (KeyError, TypeError, ValueError, OSError, IndexError, TooLarge) as exc:
            failed[item_id] = f"{type(exc).__name__}: {exc}"
            continue
        adj_used += counts["adjudication_keys_used"]
        odd_tags += ref.odd_tags
        formats[ref.format] = formats.get(ref.format, 0) + 1
        hyp_formats[hyp_path.suffix.lstrip(".")] = hyp_formats.get(hyp_path.suffix.lstrip("."), 0) + 1
        if ref.tagged_tokens:
            tagged_items += 1
            tagged_tokens += ref.tagged_tokens
        skipped_spans += ref.skipped_spans
        if ref.annotation.get("annotator"):
            annotators.add(ref.annotation["annotator"])
        merge(corpus, counts)
        per_item[item_id] = counts
        events_by_item[item_id] = (ref, hyp, events, side)
    adj_unused = adj_given - adj_used
    meta = {"items_scored": len(per_item), "items_missing_hypothesis_or_reference": sorted(missing),
            "items_failed": dict(sorted(failed.items())), "tagged_words_with_an_unrecognised_tag": odd_tags,
            "adjudications_given": adj_given,
            "reference_formats": dict(sorted(formats.items())), "hypothesis_formats": dict(sorted(hyp_formats.items())),
            "items_with_word_tags": tagged_items, "word_tagged_reference_tokens": tagged_tokens,
            "annotators": sorted(annotators), "language_spans_that_did_not_match_text": skipped_spans,
            "adjudications_unused": adj_unused}
    return {"corpus": corpus, "items": per_item, "events": events_by_item, "meta": meta}


def _hyp_path(hyp_dir: Path, item_id: str) -> Path | None:
    for ext in ("json", "txt"):
        p = hyp_dir / f"{item_id}.{ext}"
        if p.exists():
            return p
    return None


def build_report(run: dict, *, label: str, lex, cfg, manifest_sha: str | None, corpus_id: str | None,
                 include_text: int, hyp_source: str) -> dict:
    corpus = run["corpus"]
    meta = run["meta"]
    report = {
        "schema": SCHEMA,
        "label": label,
        "tool": {"name": "eval/taxonomy.py", "version": TOOL_VERSION, "tokenPolicy": "notero-standard (score.normalize)",
                 "tieBreak": cfg.get("tieBreak", "default")},
        "config": {k: v for k, v in sorted(cfg.items())},
        "lexicons": lex.describe(),
        "inputs": {"corpusId": corpus_id, "manifestSha256": manifest_sha, "hypotheses": hyp_source, **meta},
        "categories": {name: CATEGORIES[name] for name in CATEGORIES},
        "corpus": corpus,
        "items": {k: _compact(v) for k, v in sorted(run["items"].items())},
        "caveats": caveats(corpus, meta, cfg),
    }
    if include_text:
        report["text_examples"] = text_examples(run, include_text)
    return report


def _compact(c: dict) -> dict:
    return {"ref_words": c["ref_words"], "errors": c["errors"], "sub": c["sub"], "del": c["del"], "ins": c["ins"],
            "categories": {k: v["error_words"] for k, v in sorted(c["categories"].items())}}


def caveats(corpus: dict, meta: dict, cfg: dict) -> list[str]:
    out = []
    verified = corpus.get("labels", {}).get("reference", {}).get("verified", {})
    n_verified = sum(verified.values())
    n_ref = corpus.get("ref_words", 0)
    if not n_verified:
        out.append("No reference token carries a word-level language tag, so every language label in this "
                   "report is a heuristic guess from small hand-written word lists. Read the heuristic "
                   "counts as indications, not as measurements of the speech.")
    else:
        out.append(f"{n_verified} of {n_ref} reference tokens carry a word-level tag supplied by the reference "
                   "annotation (the tool does not check the annotator). The remaining tokens, and every "
                   "hypothesis token, are heuristic. The two are kept apart in every table.")
    if meta.get("items_failed"):
        out.append(f"{len(meta['items_failed'])} item(s) could not be read and are not in any count: "
                   + "; ".join(f"{k} ({v})" for k, v in list(meta["items_failed"].items())[:3]) + ".")
    if meta.get("tagged_words_with_an_unrecognised_tag"):
        out.append(f"{meta['tagged_words_with_an_unrecognised_tag']} word(s) in tagged references end in "
                   "`/letters` that is not a tag (tl, en, mix, ne, oth). They stayed in the text as words, "
                   "which changes the reference length. Check for a mistyped tag.")
    if meta.get("adjudications_unused"):
        out.append(f"{meta['adjudications_unused']} of {meta['adjudications_given']} adjudication line(s) matched "
                   "no event (wrong item, index or a second line for an event that was already decided).")
    out.append("The category counts depend on which of several equal-cost alignments is chosen (this tool "
               "uses the same tie-break as eval/langscore.py). The total never changes, but a category of a "
               "few dozen words can move by tens of words under another tie-break: do not read a "
               "difference of less than about 40 words in one category.")
    out.append("Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a "
               "heuristic label for the hypothesis word even when the reference word is verified.")
    out.append("The word lists are small and were written by an AI model (Claude) without a native "
               "speaker's review: `unknown` is the largest honest answer for words they do not cover, and the "
               "ambiguous/unknown shares are reported rather than hidden.")
    if corpus.get("sub", 0) + corpus.get("del", 0) + corpus.get("ins", 0) != corpus.get("standard_policy_errors", 0):
        out.append("The alignment's error count differs from the standard-policy count: investigate.")
    out.append("Categories partition the word errors by a first-match rule list; a word that fits two rules is "
               "counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.")
    out.append("When a reference interleaves speakers (overlapping speech) the words do not follow one time "
               "order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.")
    if meta["items_with_word_tags"] == 0 and any(f == "json" for f in meta["reference_formats"]):
        out.append("Utterance-level `language` fields (for example \"mixed\") are ignored as token labels: "
                   "only word-level tags count.")
    return out


def text_examples(run: dict, limit: int) -> dict:
    """Up to `limit` events per category, with their words. Corpus text: only with --include-text."""
    out: dict[str, list] = {}
    for item_id in sorted(run["events"]):
        ref, hyp, events, _ = run["events"][item_id]
        for e in events:
            bucket = out.setdefault(e.category, [])
            if len(bucket) >= limit:
                continue
            bucket.append({"item": item_id, "subtype": e.subtype, "basis": e.basis, "flags": e.flags,
                           "ref_index": e.ref_idx, "hyp_index": e.hyp_idx,
                           "ref": " ".join(ref.tokens[i].text for i in e.ref_idx),
                           "hyp": " ".join(hyp.tokens[j].text for j in e.hyp_idx)})
    return {k: out[k] for k in sorted(out)}


def events_tsv(run: dict) -> str:
    rows = ["item\tevent\tcategory\tsubtype\tbasis\tflags\tref_index\thyp_index\tref_words\thyp_words"]
    for item_id in sorted(run["events"]):
        ref, hyp, events, _ = run["events"][item_id]
        for n, e in enumerate(events, 1):
            rows.append("\t".join([
                item_id, str(n), e.category, e.subtype, e.basis, ",".join(e.flags),
                ",".join(f"r{i}" for i in e.ref_idx), ",".join(f"h{j}" for j in e.hyp_idx),
                " ".join(ref.tokens[i].text for i in e.ref_idx), " ".join(hyp.tokens[j].text for j in e.hyp_idx)]))
    return "\n".join(rows) + "\n"


# ------------------------------------------------------------------ rendering

def pct(x: float | None, digits: int = 1) -> str:
    return "n/a" if x is None else f"{x * 100:.{digits}f}%"


def render_markdown(report: dict) -> str:
    c = report["corpus"]
    meta = report["inputs"]
    lines: list[str] = []
    w = lines.append
    w(f"# Error taxonomy: {report['label']}")
    w("")
    w("Optional report on top of the headline WER (`eval/taxonomy.py`, schema "
      f"`{report['schema']}`, config `{report['config']['id']}`). Counts are error *words*; the categories "
      "partition them, so they add up to substitutions + deletions + insertions.")
    w("")
    w("**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. "
      "`heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. "
      "They are never added together.")
    w("")
    w("## Inputs")
    w("")
    w(f"- corpus: `{meta['corpusId']}`, manifest SHA-256 `{(meta['manifestSha256'] or 'n/a')[:16]}…`")
    w(f"- items scored: {meta['items_scored']}; missing a hypothesis or reference: "
      f"{len(meta['items_missing_hypothesis_or_reference'])}")
    w(f"- reference formats: {meta['reference_formats']}; hypothesis formats: {meta['hypothesis_formats']}")
    w(f"- reference items with word-level language tags: {meta['items_with_word_tags']} "
      f"({meta['word_tagged_reference_tokens']} tokens); annotators: {meta['annotators'] or 'none recorded'}")
    w(f"- word lists: " + ", ".join(f"`{k}` {v['entries']}" for k, v in report["lexicons"].items()))
    w("")
    n = c.get("ref_words", 0)
    errors = c.get("errors", 0)
    w("## Headline")
    w("")
    w(f"{n} reference words, {c.get('hyp_words', 0)} hypothesis words. "
      f"Substitutions {c.get('sub', 0)}, deletions {c.get('del', 0)}, insertions {c.get('ins', 0)}; "
      f"**{errors} errors, WER {pct(ratio(errors, n), 2)}** (token policy `notero-standard`, the same as "
      f"`eval/score.py`). Standard-policy error count from `score.levenshtein`: {c.get('standard_policy_errors', 0)} "
      f"({'equal' if errors == c.get('standard_policy_errors') else 'DIFFERENT'}; only the split between S/D/I "
      "can differ, through tie-breaking).")
    w("")
    w("## Error categories")
    w("")
    w("| category | events | error words | share of errors | verified | heuristic | structural |")
    w("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    cats = c.get("categories", {})
    for name in CATEGORIES:
        v = cats.get(name)
        if not v:
            continue
        b = v["basis"]
        w(f"| `{name}` | {v['events']} | {v['error_words']} | {pct(ratio(v['error_words'], errors))} | "
          + " | ".join(str(b.get(x, {}).get("error_words", 0)) for x in BASES) + " |")
    w("")
    w("Definitions: " + "; ".join(f"`{k}` {v}" for k, v in CATEGORIES.items()) + ".")
    w("")
    w("### Subtypes")
    w("")
    w("| category | subtype | events | error words | verified | heuristic | structural |")
    w("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for name in CATEGORIES:
        v = cats.get(name)
        if not v:
            continue
        for sub, sv in sorted(v["subtypes"].items()):
            w(f"| `{name}` | `{sub}` | {sv['events']} | {sv['error_words']} | "
              + " | ".join(str(sv.get("basis", {}).get(x, 0)) for x in BASES) + " |")
    w("")
    flagged = [(name, f, fv) for name in CATEGORIES for f, fv in sorted(cats.get(name, {}).get("flags", {}).items())]
    if flagged:
        w("### Flags (overlays; a word can carry several)")
        w("")
        w("; ".join(f"`{k}`: {v}" for k, v in FLAG_MEANING.items() if any(f == k for _, f, _ in flagged)) + ".")
        w("")
        w("| category | flag | events | error words | verified | heuristic | structural |")
        w("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
        for name, f, fv in flagged:
            w(f"| `{name}` | `{f}` | {fv['events']} | {fv['error_words']} | "
              + " | ".join(str(fv.get("basis", {}).get(x, 0)) for x in BASES) + " |")
        w("")
    lab = c.get("labels", {})
    w("## Language labels")
    w("")
    for side, title in (("reference", "Reference tokens"), ("hypothesis", "Hypothesis tokens")):
        w(f"**{title}** (a hypothesis word is never verified)")
        w("")
        w("| basis | " + " | ".join(tlx.LANGS) + " | total |")
        w("| --- | " + " | ".join("---:" for _ in tlx.LANGS) + " | ---: |")
        for basis in ("verified", "heuristic"):
            row = lab.get(side, {}).get(basis, {})
            total = sum(row.values())
            if side == "hypothesis" and basis == "verified":
                continue
            w(f"| {basis} | " + " | ".join(str(row.get(x, 0)) for x in tlx.LANGS) + f" | {total} |")
        heur = lab.get(side, {}).get("heuristic", {})
        total_h = sum(heur.values())
        unres = heur.get("unknown", 0) + heur.get("ambiguous", 0)
        w("")
        w(f"Heuristic tokens that are `unknown` or `ambiguous`: {unres} of {total_h} ({pct(ratio(unres, total_h))}). "
          f"Heuristic tokens labelled `tl` or `en`: {heur.get('tl', 0) + heur.get('en', 0)} "
          f"({pct(ratio(heur.get('tl', 0) + heur.get('en', 0), total_h))}).")
        w("")
    why = lab.get("reference_why", {})
    if why:
        w("Heuristic reference labels by rule:")
        w("")
        w("| label | rule | tokens |")
        w("| --- | --- | ---: |")
        for lang in tlx.LANGS:
            for rule, count in sorted(why.get(lang, {}).items(), key=lambda kv: (-kv[1], kv[0])):
                w(f"| {lang} | `{rule}` | {count} |")
        w("")
    w("## Substitutions by language (reference row, hypothesis column)")
    w("")
    matrix = c.get("substitution_matrix", {})
    w("| reference basis | reference label | " + " | ".join(tlx.LANGS) + " |")
    w("| --- | --- | " + " | ".join("---:" for _ in tlx.LANGS) + " |")
    for basis in ("verified", "heuristic"):
        for rlang in tlx.LANGS:
            row = matrix.get(basis, {}).get(rlang)
            if row:
                w(f"| {basis} | {rlang} | " + " | ".join(str(row.get(x, 0)) for x in tlx.LANGS) + " |")
    w("")
    w("The hypothesis column is always a heuristic label. This matrix covers every substitution; the "
      "`tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.")
    w("")
    w("## Error rate by reference label")
    w("")
    w("| basis | label | words | substitutions | deletions | error rate (S+D)/words |")
    w("| --- | --- | ---: | ---: | ---: | ---: |")
    for basis in ("verified", "heuristic"):
        for lang in tlx.LANGS:
            v = c.get("by_reference_label", {}).get(f"{basis}|{lang}")
            if v:
                e = v.get("substitutions", 0) + v.get("deletions", 0)
                w(f"| {basis} | {lang} | {v['words']} | {v.get('substitutions', 0)} | {v.get('deletions', 0)} | "
                  f"{pct(ratio(e, v['words']))} |")
    ins = c.get("inserted_by_hypothesis_language", {})
    if ins:
        w("")
        w("Inserted words by (heuristic) language: " + ", ".join(f"{k} {v}" for k, v in sorted(ins.items())) + ".")
    w("")
    cs = c.get("code_switch", {})
    w("## Code-switch points")
    w("")
    sp = cs.get("switch_points", {})
    w(f"Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): "
      f"verified {sp.get('verified', 0)}, heuristic {sp.get('heuristic', 0)}.")
    w("")
    w("| word position | words | errors (S+D) | rate |")
    w("| --- | ---: | ---: | ---: |")
    for basis in ("verified", "heuristic"):
        bw, be = cs.get("boundary_words", {}).get(basis, 0), cs.get("boundary_errors", {}).get(basis, 0)
        if bw:
            w(f"| at a {basis} switch point | {bw} | {be} | {pct(ratio(be, bw))} |")
    for basis in ("verified", "heuristic"):
        lw, le = cs.get("labelled_other_words", {}).get(basis, 0), cs.get("labelled_other_errors", {}).get(basis, 0)
        if lw:
            w(f"| elsewhere, labelled `tl` or `en` ({basis}) | {lw} | {le} | {pct(ratio(le, lw))} |")
    w(f"| elsewhere, any label | {cs.get('other_words', 0)} | {cs.get('other_errors', 0)} | "
      f"{pct(ratio(cs.get('other_errors', 0), cs.get('other_words', 0)))} |")
    w("")
    w("A switch point needs two words that are clearly Tagalog and English, so the fair comparison is "
      "with other words that carry such a label (the first rows). \"Any label\" includes `unknown`, "
      "`ambiguous`, `other` and `name` words, which are wrong more often.")
    w("")
    ts = c.get("timestamps", {})
    w("## Timestamp misalignment (overlay on recognised words)")
    w("")
    if ts.get("items_checked", 0):
        w(f"{ts['pairs']} aligned word pairs in {ts['items_checked']} items; **{ts['misaligned']} "
          f"({pct(ratio(ts['misaligned'], ts['pairs']))}) have a hypothesis time more than "
          f"{report['config']['timestampToleranceMs']} ms outside the reference utterance**. "
          f"Offsets: {dict(sorted(ts['offset_buckets'].items()))}; largest {ts.get('max_offset_ms', 0)} ms. "
          "Reference times are per utterance, not per word, and an alignment that drifts across an "
          "overlapped or reordered stretch also shows up here.")
    else:
        w("Not available.")
    if ts.get("items_unavailable"):
        w("")
        w("Items without it: " + "; ".join(f"{v} × {k}" for k, v in sorted(ts["items_unavailable"].items())) + ".")
    w("")
    w("## Caveats")
    w("")
    for cv in report["caveats"]:
        w(f"- {cv}")
    if "text_examples" in report:
        w("")
        w("## Examples (corpus text; do not commit for third-party data)")
        w("")
        for cat, rows in report["text_examples"].items():
            w(f"**{cat}**")
            w("")
            for r in rows:
                w(f"- `{r['item']}` {r['subtype']} [{r['basis']}]: ref `{r['ref']}` → hyp `{r['hyp']}`")
            w("")
    return "\n".join(lines).rstrip() + "\n"


def dump_json(value) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def write_report(report: dict, out_dir: Path, stem: str = "taxonomy") -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    jp, mp = out_dir / f"{stem}.json", out_dir / f"{stem}.md"
    jp.write_text(dump_json(report), encoding="utf-8")
    mp.write_text(render_markdown(report), encoding="utf-8")
    return jp, mp


def render_table(reports: list[dict]) -> str:
    """Side-by-side error words per category for several reports."""
    head = "| category | " + " | ".join(r["label"] for r in reports) + " |"
    rows = [head, "| --- | " + " | ".join("---:" for _ in reports) + " |"]
    for name in CATEGORIES:
        vals = [r["corpus"].get("categories", {}).get(name, {}).get("error_words", 0) for r in reports]
        if any(vals):
            rows.append(f"| `{name}` | " + " | ".join(str(v) for v in vals) + " |")
    rows.append("| **errors** | " + " | ".join(str(r["corpus"].get("errors", 0)) for r in reports) + " |")
    rows.append("| reference words | " + " | ".join(str(r["corpus"].get("ref_words", 0)) for r in reports) + " |")
    return "\n".join(rows) + "\n"


# ------------------------------------------------------------------ entry points

def report_from_manifest(manifest: Path, hyp_dir: Path, *, label: str, out_dir: Path | None = None,
                         include_text: int = 0, adjudications: Path | None = None,
                         english_wordlist: Path | None = None, events_path: Path | None = None,
                         config: Path | None = None, stem: str = "taxonomy", tie_break: str = "default") -> dict:
    cfg = load_config(config)
    cfg["tieBreak"] = tie_break
    lex = tlx.Lexicon(english_wordlist=english_wordlist)
    items, info = load_manifest(manifest)
    run = run_items(items, Path(manifest).parent, Path(hyp_dir), lex, cfg, load_adjudications(adjudications))
    report = build_report(run, label=label, lex=lex, cfg=cfg, manifest_sha=sha256_file(Path(manifest)),
                          corpus_id=info["corpusId"], include_text=include_text, hyp_source=Path(hyp_dir).name)
    if out_dir:
        write_report(report, Path(out_dir), stem)
    if events_path:
        Path(events_path).write_text(events_tsv(run), encoding="utf-8")
    return report


def command_report(args) -> int:
    report = report_from_manifest(args.manifest, args.hyp_dir, label=args.label, out_dir=args.out_dir,
                                  include_text=args.include_text, adjudications=args.adjudications,
                                  english_wordlist=args.english_wordlist, events_path=args.events_tsv,
                                  config=args.config, tie_break=args.tie_break)
    c = report["corpus"]
    print(f"{args.label}: {c.get('errors', 0)} errors over {c.get('ref_words', 0)} reference words "
          f"-> {args.out_dir}/taxonomy.json, taxonomy.md")
    return 0


def command_pair(args) -> int:
    cfg = load_config(args.config)
    cfg["tieBreak"] = args.tie_break
    lex = tlx.Lexicon(english_wordlist=args.english_wordlist)
    ref, hyp = tio.load_reference(args.reference), tio.load_hypothesis(args.hypothesis)
    counts, events, _ = analyze_item(ref, hyp, lex, cfg)
    run = {"corpus": dict(counts), "items": {"pair": counts}, "events": {"pair": (ref, hyp, events, {})},
           "meta": {"items_scored": 1, "items_missing_hypothesis_or_reference": [],
                    "reference_formats": {ref.format: 1}, "hypothesis_formats": {Path(args.hypothesis).suffix.lstrip("."): 1},
                    "items_failed": {}, "tagged_words_with_an_unrecognised_tag": ref.odd_tags, "adjudications_given": 0,
                    "items_with_word_tags": 1 if ref.tagged_tokens else 0,
                    "word_tagged_reference_tokens": ref.tagged_tokens, "annotators": [],
                    "language_spans_that_did_not_match_text": ref.skipped_spans, "adjudications_unused": 0}}
    report = build_report(run, label=args.label, lex=lex, cfg=cfg, manifest_sha=None, corpus_id=None,
                          include_text=args.include_text, hyp_source=Path(args.hypothesis).name)
    print(dump_json(report) if args.json else render_markdown(report), end="")
    return 0


def command_plan(args) -> int:
    """Taxonomy of every tier's saved hypotheses in a tier_benchmark plan (no decoding)."""
    plan_path = Path(args.plan).resolve()
    plan = json.loads(plan_path.read_text())
    manifest = Path(plan["manifest"]["path"])
    if not manifest.exists():
        print(f"stop: manifest {manifest} is not on this machine", file=sys.stderr)
        return 2
    folder = "hyp" if args.repeat == 0 else f"hyp-repeat{args.repeat}"
    reports = []
    for tier in sorted(plan["tiers"]):
        hyp_dir = plan_path.parent / folder / tier
        if not hyp_dir.exists():
            print(f"skip {tier}: no {hyp_dir}", file=sys.stderr)
            continue
        label = tier if args.repeat == 0 else f"{tier} (repeat {args.repeat})"
        reports.append(report_from_manifest(manifest, hyp_dir, label=label, out_dir=Path(args.out_dir) / tier,
                                            include_text=args.include_text, english_wordlist=args.english_wordlist,
                                            tie_break=args.tie_break,
                                            events_path=(Path(args.out_dir) / tier / "events.tsv") if args.events_tsv else None))
    if reports:
        (Path(args.out_dir) / "tiers.md").write_text(render_table(reports), encoding="utf-8")
        print(render_table(reports), end="")
    return 0


def command_table(args) -> int:
    reports = [json.loads(Path(p).read_text()) for p in args.reports]
    print(render_table(reports), end="")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p):
        p.add_argument("--english-wordlist", type=Path, default=None,
                       help="extra English words (one per line), e.g. /usr/share/dict/words; its hash is recorded")
        p.add_argument("--tie-break", choices=sorted(TIE_BREAKS), default="default",
                       help="which equal-cost alignment to take; the total is the same, some category counts move")
        p.add_argument("--include-text", type=int, default=0, metavar="N",
                       help="add up to N example events per category WITH corpus text (never commit third-party text)")

    p = sub.add_parser("report", help="taxonomy of a manifest's references against a directory of hypotheses")
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--hyp-dir", type=Path, required=True, help="<id>.json (transcribe --json) or <id>.txt per item")
    p.add_argument("--label", default="system")
    p.add_argument("--out-dir", type=Path, required=True)
    p.add_argument("--adjudications", type=Path, default=None, help="TSV of human category decisions")
    p.add_argument("--events-tsv", type=Path, default=None, help="write every event with its words (corpus text)")
    p.add_argument("--config", type=Path, default=None)
    common(p)
    p.set_defaults(func=command_report)

    p = sub.add_parser("pair", help="one reference file against one hypothesis file, printed")
    p.add_argument("--reference", type=Path, required=True)
    p.add_argument("--hypothesis", type=Path, required=True)
    p.add_argument("--label", default="pair")
    p.add_argument("--json", action="store_true")
    p.add_argument("--config", type=Path, default=None)
    common(p)
    p.set_defaults(func=command_pair)

    p = sub.add_parser("plan", help="taxonomy of each tier in a tier_benchmark plan, from the saved hypotheses")
    p.add_argument("--plan", type=Path, required=True)
    p.add_argument("--out-dir", type=Path, required=True)
    p.add_argument("--repeat", type=int, default=0, help="0 = first decode, 1 = hyp-repeat1")
    p.add_argument("--events-tsv", action="store_true")
    common(p)
    p.set_defaults(func=command_plan)

    p = sub.add_parser("table", help="side-by-side category counts from several taxonomy.json files")
    p.add_argument("reports", nargs="+", type=Path)
    p.set_defaults(func=command_table)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
