"""The Taglish error taxonomy (eval/taxonomy*.py): tokens, labels, categories, reports.

Everything here runs on hand-written text. `eval/fixtures/taxonomy/` is synthetic: its
expected counts in `expected.json` were checked by hand against the sentences (the README
beside it lists every case), so these tests assert numbers a person worked out, not a
snapshot of the tool's own output. No corpus text, audio or model is used.
"""

from __future__ import annotations

import io
import json
import random
import sys
from contextlib import redirect_stdout
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "eval"))

import compare_language as cl  # noqa: E402
import score as pooled  # noqa: E402
import taxonomy as tx  # noqa: E402
import taxonomy_io as tio  # noqa: E402
import taxonomy_lex as tlx  # noqa: E402
import tier_benchmark as tb  # noqa: E402

FIXTURE = REPO / "eval" / "fixtures" / "taxonomy"
EXPECTED = json.loads((FIXTURE / "expected.json").read_text())
CFG = tx.load_config()
LEX = tlx.Lexicon()


def run_fixture(**kwargs) -> dict:
    return tx.report_from_manifest(FIXTURE / "manifest.json", FIXTURE / "hyp", label="fixture", **kwargs)


def pair(ref_text: str, hyp_text: str, tmp_path: Path, *, tagged: bool = False):
    rp = tmp_path / ("r.tagged.txt" if tagged else "r.txt")
    hp = tmp_path / "h.txt"
    rp.write_text(ref_text)
    hp.write_text(hyp_text)
    ref, hyp = tio.load_reference(rp), tio.load_hypothesis(hp)
    counts, events, side = tx.analyze_item(ref, hyp, LEX, CFG)
    return counts, events, side


# ---------------------------------------------------------------- tokens

TEXTS = [
    "Ang daming mushroom jan sa gubat natin, sa harapan natin.",
    "Nag-meeting kami; i-share mo ang screen, naka-mute ka pa.",
    "don't can't I'm ako'y sa'yo 'yung 'wag",
    "em—dash and en–dash, ellipsis... ‘quoted’ “double”",
    "NBSP here, full-width ＡＢＣ, digits 3.5 and 12,000, snake_case",
    "İstanbul and Ñandu with ng̃a",
    "- ' -- '' a-b-c-d trailing- -leading",
    "",
    "   ",
    "...",
]


@pytest.mark.parametrize("text", TEXTS)
def test_the_tokens_are_exactly_score_normalize(text):
    assert [t.text for t in tio.tokenize(text, 0)] == pooled.normalize(text)


def test_hyphenated_words_are_groups_and_sentences_are_marked():
    toks = tio.tokenize("Nag-meeting kami. Naka-mute ka!", 0)
    assert [t.text for t in toks] == ["nag", "meeting", "kami", "naka", "mute", "ka"]
    assert [(t.group is not None, t.group_pos, t.group_len) for t in toks][:2] == [(True, 0, 2), (True, 1, 2)]
    assert toks[2].group is None
    assert toks[0].group != toks[3].group
    assert [t.sentence_start for t in toks] == [True, False, False, True, False, False]
    assert toks[0].surface == "Nag" and toks[4].surface == "mute"


def test_a_trailing_or_leading_hyphen_makes_no_group():
    assert all(t.group is None for t in tio.tokenize("naka- -mute", 0))


# ---------------------------------------------------------------- reference formats

def test_tagged_lines_carry_tags_headers_and_times(tmp_path):
    p = tmp_path / "r.tagged.txt"
    p.write_text("# c\n!annotator: me\n[id=u1 spk=A t=100-900 overlap=1] Nag-meeting/mix kami/tl, Andy/ne.\nplain words/en\n")
    ref = tio.load_reference(p)
    assert ref.format == "tagged" and ref.annotation == {"annotator": "me"}
    u1, u2 = ref.utterances
    assert (u1.id, u1.speaker, u1.start_ms, u1.end_ms, u1.overlap, u1.timed) == ("u1", "A", 100, 900, True, True)
    assert u2.id == "line-2" and not u2.timed
    assert [(t.text, t.tag) for t in ref.tokens] == [
        ("nag", "mix"), ("meeting", "mix"), ("kami", "tl"), ("andy", "ne"), ("plain", None), ("words", "en")]
    assert ref.tagged_tokens == 5
    # the tag does not leak into the scored text
    assert [t.text for t in ref.tokens] == pooled.normalize(" ".join(u.text for u in ref.utterances))


def test_a_slash_that_is_not_a_tag_stays_in_the_text_and_a_tag_covers_its_whole_word(tmp_path):
    p = tmp_path / "r.tagged.txt"
    p.write_text("and/or he/she/tl\n")
    ref = tio.load_reference(p)
    assert [(t.text, t.tag) for t in ref.tokens] == [("and", None), ("or", None), ("he", "tl"), ("she", "tl")]


def test_json_spans_label_tokens_and_the_utterance_language_does_not(tmp_path):
    p = tmp_path / "r.json"
    p.write_text(json.dumps({"utterances": [
        {"id": "a", "text": "Simulan na natin ang meeting.", "language": "mixed",
         "languageSpans": [{"text": "Simulan na natin ang ", "language": "tl"}, {"text": "meeting.", "language": "en"}]},
        {"id": "b", "text": "Salamat po.", "language": "tl"},
        {"id": "c", "text": "One two three.", "languageSpans": [{"text": "One two", "language": "en"}]},
    ], "annotation": {"annotator": "x"}}))
    ref = tio.load_reference(p)
    assert [t.tag for t in ref.tokens] == ["tl", "tl", "tl", "tl", "en", None, None, None, None, None]
    assert ref.skipped_spans == 1            # `c`: its spans do not cover its text
    assert ref.annotation == {"annotator": "x"}


def test_plain_text_has_no_tags(tmp_path):
    p = tmp_path / "r.txt"
    p.write_text("Ang laki/en ng bahay\n\nnila\n")
    ref = tio.load_reference(p)
    assert ref.tagged_tokens == 0 and len(ref.utterances) == 2
    assert ref.cased                                  # upper and lower case letters are both present


def test_hypothesis_word_times_follow_the_transcript_even_when_apostrophes_differ(tmp_path):
    words = [{"text": " Sa", "startMs": 0, "endMs": 100}, {"text": " yo", "startMs": 100, "endMs": 200},
             {"text": " na", "startMs": 200, "endMs": 300}]
    p = tmp_path / "h.json"
    p.write_text(json.dumps({"transcript": "sa'yo na", "words": words}))
    hyp = tio.load_hypothesis(p)
    assert [t.text for t in hyp.tokens] == ["sa'yo", "na"]
    assert [(t.start_ms, t.end_ms) for t in hyp.tokens] == [(None, None), (200, 300)]
    assert hyp.timed_tokens == 1


# ---------------------------------------------------------------- language labels

@pytest.mark.parametrize("word,lang,why", [
    ("meeting", "en", "lexicon-en"), ("launching", "en", "en-inflection"), ("don't", "en", "english-contraction"),
    ("natin", "tl", "lexicon-tl"), ("daming", "tl", "tl-ligature"), ("nagluluto", "tl", "tl-affix-analysis"),
    ("ako'y", "tl", "tagalog-clitic-y"), ("at", "ambiguous", "homograph-list"), ("ate", "ambiguous", "homograph-list"),
    ("500", "other", "digits"), ("hahaha", "other", "filler-or-laughter"), ("zzyzx", "unknown", "no-match"),
    ("manila", "name", "names-lexicon"),
])
def test_classify_word(word, lang, why):
    label = tlx.classify_word(word, LEX)
    assert (label.lang, label.why, label.basis) == (lang, why, "heuristic")


def test_an_unlisted_word_is_unknown_and_never_guessed_tagalog():
    assert tlx.classify_word("kalabaw", LEX).lang == "unknown"      # langscore.classify would say "tl"


def test_names_need_a_cased_reference_and_a_mid_sentence_capital():
    toks = tio.tokenize("Sabi ni Andy sa Quartz. Okay na.", 0)
    cased = [(t.text, l.lang) for t, l in zip(toks, tlx.label_tokens(toks, LEX, cased=True))]
    assert ("andy", "name") in cased and ("quartz", "name") in cased
    assert ("sabi", "name") not in cased and ("okay", "name") not in cased       # sentence starts
    # without case there is no capital to go on: Quartz is unknown; Andy is a name only because it is listed
    lower = tio.tokenize("sabi ni Andy sa Quartz", 0)
    got = {t.text: (l.lang, l.why) for t, l in zip(lower, tlx.label_tokens(lower, LEX, cased=False))}
    assert got["quartz"] == ("unknown", "no-match") and got["andy"] == ("name", "names-lexicon")
    assert dict(zip((t.text for t in lower), (l.lang for l in tlx.label_tokens(lower, LEX, cased=True))))["quartz"] == "name"


def test_a_capitalised_ordinary_word_is_not_called_a_name():
    toks = tio.tokenize("Sabi ni Boss sa Discord, Naku po", 0)
    langs = {t.text: l.lang for t, l in zip(toks, tlx.label_tokens(toks, LEX, cased=True))}
    assert langs["boss"] == "en" and langs["discord"] == "en" and langs["naku"] == "tl"


def test_acronyms_are_other_and_i_is_not_a_name():
    toks = tio.tokenize("Gusto ko ng AFK at I am here", 0)
    langs = {t.text: l.lang for t, l in zip(toks, tlx.label_tokens(toks, LEX, cased=True))}
    assert langs["afk"] == "other" and langs["i"] != "name"


def test_hyphenated_affix_groups_are_judged_whole():
    labs = {}
    for text in ("i-share", "nag-usap", "mag-xyzzy", "naka-mute"):
        toks = tio.tokenize(text, 0)
        labs[text] = {(l.lang, l.why) for l in tlx.label_tokens(toks, LEX, cased=False)}
    assert labs["i-share"] == {("mix", "affix+english-stem")}
    assert labs["naka-mute"] == {("mix", "affix+english-stem")}
    assert labs["nag-usap"] == {("tl", "affix+tagalog-stem")}
    assert labs["mag-xyzzy"] == {("unknown", "affix+unlisted-stem")}      # not guessed to be a mixed word


def test_an_ambiguous_word_takes_the_language_of_two_agreeing_neighbours_only():
    toks = tio.tokenize("hindi pa ako", 0)
    labs = tlx.label_tokens(toks, LEX, cased=False)
    assert (labs[1].lang, labs[1].why) == ("tl", "context")
    toks = tio.tokenize("pa ako", 0)
    assert tlx.label_tokens(toks, LEX, cased=False)[0].lang == "ambiguous"       # one neighbour is not enough
    toks = tio.tokenize("hindi pa meeting", 0)
    assert tlx.label_tokens(toks, LEX, cased=False)[1].lang == "ambiguous"       # the neighbours disagree
    assert tlx.label_tokens(toks, LEX, cased=False, context=False)[1].why == "homograph-list"


def test_a_verified_tag_wins_over_the_heuristic():
    toks = tio.tokenize("meeting/tl", 0, chunk_tags=["tl"])
    lab = tlx.label_tokens(toks, LEX, cased=False)[0]
    assert (lab.lang, lab.basis, lab.why) == ("tl", "verified", "tag")


# ---------------------------------------------------------------- morphology

@pytest.mark.parametrize("ref,hyp,subtype", [
    ("kakain", "kain", "reduplication_dropped"), ("kain", "kakain", "reduplication_added"),
    ("magtatrabaho", "magtrabaho", "reduplication_dropped"),
    ("nagluto", "magluto", "affix_changed"), ("umuwi", "uwi", "affix_missing"), ("bili", "bumili", "affix_added"),
    ("kinain", "kumain", "affix_changed"), ("magandang", "maganda", "ligature_dropped"),
    ("bago", "bagong", "ligature_added"), ("kaibigang", "kaibigan", "ligature_dropped"),
])
def test_morphology_relations(ref, hyp, subtype):
    rel = tlx.morphology_relation(ref, hyp, LEX)
    assert rel is not None and rel[0] == subtype


@pytest.mark.parametrize("ref,hyp", [("meeting", "meetings"), ("bahay", "bukid"), ("sa", "ang"), ("na", "pa"),
                                     ("ang", "mang")])
def test_unrelated_or_english_pairs_are_not_morphology(ref, hyp):
    assert tlx.morphology_relation(ref, hyp, LEX) is None


def test_analyses_find_infix_prefix_and_reduplication():
    got = {(a.prefix, a.infix, a.redup, a.root, a.suffix) for a in tlx.analyses("tumatakbo")}
    assert ("", "um", "ta", "takbo", "") in got                # t-um-a-takbo: infix um, copied "ta", root takbo
    got = {(a.prefix, a.infix, a.redup, a.root, a.suffix) for a in tlx.analyses("magtatrabaho")}
    assert ("mag", "", "ta", "trabaho", "") in got
    got = {(a.prefix, a.infix, a.redup, a.root, a.suffix) for a in tlx.analyses("kainin")}
    assert ("", "", "", "kain", "in") in got
    assert tlx.analyses("ab")[0] == tlx.Analysis("", "", "", "ab", "")


# ---------------------------------------------------------------- the fixture, against numbers worked out by hand

def test_fixture_counts_match_the_hand_checked_expectations():
    c = run_fixture()["corpus"]
    for key in ("ref_words", "hyp_words", "sub", "del", "ins", "errors"):
        assert c[key] == EXPECTED[key], key
    got = {k: {"events": v["events"], "error_words": v["error_words"],
               "basis": {b: x["error_words"] for b, x in sorted(v["basis"].items())}}
           for k, v in c["categories"].items()}
    assert got == EXPECTED["categories"]
    assert sum(c["labels"]["reference"]["verified"].values()) == EXPECTED["verified_reference_tokens"]
    assert (c["timestamps"]["pairs"], c["timestamps"]["misaligned"]) == (
        EXPECTED["timestamps"]["pairs"], EXPECTED["timestamps"]["misaligned"])


def test_every_category_has_a_fixture_case():
    assert set(run_fixture()["corpus"]["categories"]) == set(tx.CATEGORIES)


def test_the_categories_partition_the_errors_exactly():
    report = run_fixture()
    c = report["corpus"]
    assert sum(v["error_words"] for v in c["categories"].values()) == c["errors"] == c["standard_policy_errors"]
    for item_id, item in report["items"].items():
        assert sum(item["categories"].values()) == item["errors"], item_id
        assert item["sub"] + item["del"] + item["ins"] == item["errors"]


def test_verified_heuristic_and_structural_counts_are_never_merged():
    c = run_fixture()["corpus"]
    for name, cat in c["categories"].items():
        assert set(cat["basis"]) <= set(tx.BASES), name
        assert sum(b["error_words"] for b in cat["basis"].values()) == cat["error_words"]
        if name in tx.STRUCTURAL:
            assert set(cat["basis"]) == {"structural"}, name
    # a language-direction substitution is heuristic: the hypothesis word is never tagged by a person
    for name in ("tl_to_en_substitution", "en_to_tl_substitution", "morphology_error", "enclitic_particle"):
        assert set(c["categories"][name]["basis"]) == {"heuristic"}
    # the same verified reference tokens feed the verified categories
    assert set(c["categories"]["proper_noun_error"]["basis"]) == {"verified"}
    assert set(c["categories"]["mixed_word_error"]["basis"]) == {"verified"}
    assert set(c["categories"]["boundary_error"]["basis"]) == {"verified"}


def test_subtypes_of_the_hand_checked_cases():
    subs = {k: {s: v["error_words"] for s, v in c["subtypes"].items()}
            for k, c in run_fixture()["corpus"]["categories"].items()}
    assert subs["mixed_word_error"] == {"affix_dropped": 2, "affix_changed": 1, "stem_changed": 1,
                                        "both_wrong": 2, "deleted": 1}
    assert subs["morphology_error"] == {"reduplication_dropped": 1, "affix_changed": 1, "affix_missing": 1,
                                        "affix_added": 1, "ligature_dropped": 1, "ligature_added": 1,
                                        "reduplication_added": 1}
    assert subs["boundary_error"] == {"deleted": 1, "carry_over": 1}
    assert subs["hallucination"] == {"run": 8, "repetition_loop": 4}
    assert subs["enclitic_particle"] == {"deleted": 1, "substituted": 1, "inserted": 1}
    assert subs["proper_noun_error"] == {"near_spelling": 1, "deleted": 1}
    assert subs["spelling_variant"] == {"spacing": 4, "variant-table": 1}


def test_hallucination_in_silence_is_flagged_only_when_the_reference_has_times():
    flags = {k: v for k, v in run_fixture()["corpus"]["categories"]["hallucination"]["flags"].items()}
    assert flags == {"outside_reference_speech": {"events": 2, "error_words": 8},
                     "time_unknown": {"events": 1, "error_words": 4}}


def test_timestamp_misalignment_counts_a_recognised_word_stamped_far_from_its_utterance():
    ts = run_fixture()["corpus"]["timestamps"]
    assert ts["pairs"] == 15 and ts["misaligned"] == 1 and ts["items_checked"] == 1
    assert ts["offset_buckets"] == {"inside": 14, "<=5000ms": 1} and ts["max_offset_ms"] == 4300
    assert ts["items_unavailable"] == {"reference has no utterance times": 4}


def test_a_hypothesis_without_word_times_gives_no_timestamp_numbers(tmp_path):
    hyp = tmp_path / "hyp"
    hyp.mkdir()
    (hyp / "silence.txt").write_text("Magandang umaga po sa inyong lahat")
    items = [{"id": "silence", "ref": "refs/silence.json"}]
    run = tx.run_items(items, FIXTURE, hyp, LEX, CFG, {})
    ts = run["corpus"]["timestamps"]
    assert ts["items_checked"] == 0
    assert ts["items_unavailable"] == {"a plain-text transcript has no word times": 1}


def test_the_json_reference_labels_only_what_its_spans_cover():
    c = run_fixture()["corpus"]["labels"]["reference"]
    # counted by hand: English 10 + 2 + 1, mixed 12, names 2, Tagalog the rest of the 112 tagged tokens
    assert c["verified"] == {"tl": 85, "en": 13, "mix": 12, "name": 2}
    # the plain items, the untagged lines and every hypothesis word are heuristic
    assert c["heuristic"]["unknown"] > 0
    assert "verified" not in run_fixture()["corpus"]["labels"]["hypothesis"]


# ---------------------------------------------------------------- precedence and edge cases

def test_a_join_or_split_of_the_same_letters_is_a_spelling_variant_not_two_errors(tmp_path):
    counts, events, _ = pair("Gusto kong mag-meeting bukas", "Gusto kong magmeeting bukas", tmp_path)
    assert [(e.category, e.subtype, e.error_words) for e in events] == [("spelling_variant", "spacing", 2)]
    counts, events, _ = pair("Gusto kong magmeeting bukas", "Gusto kong mag meeting bukas", tmp_path)
    assert [(e.category, e.error_words) for e in events] == [("spelling_variant", 2)]


def test_a_hyphen_alone_is_never_an_error():
    ref = tio.tokenize("Nag-meeting kami", 0)
    hyp = tio.tokenize("Nag meeting kami", 0)
    assert [t.text for t in ref] == [t.text for t in hyp]


def test_runs_below_the_threshold_are_isolated_words_and_runs_at_it_are_not(tmp_path):
    _, ev2, _ = pair("a b c d e f g", "a b c f g", tmp_path)               # two words deleted
    assert [e.category for e in ev2] == ["other_deletion", "other_deletion"]
    _, ev3, _ = pair("a b c d e f g", "a b f g", tmp_path)                 # three deleted
    assert [(e.category, e.error_words) for e in ev3] == [("deleted_speech", 3)]
    _, ev4, _ = pair("a b c d e", "a b x y c d e", tmp_path)
    assert [e.category for e in ev4] == ["other_insertion", "other_insertion"]
    _, ev5, _ = pair("a b c d e", "a b x y z c d e", tmp_path)
    assert [(e.category, e.error_words) for e in ev5] == [("hallucination", 3)]


def test_a_repetition_loop_is_named(tmp_path):
    _, events, _ = pair("a b c d e", "a b ha ha ha ha c d e", tmp_path)
    assert events[0].category == "hallucination" and events[0].subtype == "repetition_loop"


def test_precedence_a_name_beats_a_boundary_and_a_particle_beats_a_language_swap(tmp_path):
    counts, events, _ = pair("Kausapin/tl mo/tl si/tl Andy/ne tomorrow/en", "Kausapin mo si Andi tomorrow", tmp_path,
                             tagged=True)
    assert [(e.category, e.basis) for e in events] == [("proper_noun_error", "verified")]
    # `lang` is a particle: replaced by an English word it is an enclitic error, not tl_to_en
    counts, events, _ = pair("Sandali lang po", "Sandali moment po", tmp_path)
    assert [e.category for e in events] == ["enclitic_particle"]


def test_empty_sides_do_not_crash(tmp_path):
    counts, events, _ = pair("", "", tmp_path)
    assert counts["errors"] == 0 and events == []
    counts, events, _ = pair("a b c", "", tmp_path)
    assert [(e.category, e.error_words) for e in events] == [("deleted_speech", 3)]
    counts, events, _ = pair("", "a b", tmp_path)
    assert [e.category for e in events] == ["other_insertion", "other_insertion"]


def test_an_oversized_alignment_is_refused_not_attempted(tmp_path):
    small = dict(CFG, maxAlignmentCells=4)
    rp, hp = tmp_path / "r.txt", tmp_path / "h.txt"
    rp.write_text("a b c")
    hp.write_text("a b c")
    with pytest.raises(tx.TooLarge):
        tx.analyze_item(tio.load_reference(rp), tio.load_hypothesis(hp), LEX, small)


def test_random_text_always_partitions_and_never_raises(tmp_path):
    rng = random.Random(20261102)
    vocab = ["ang", "mga", "meeting", "nag", "mag", "meeting", "Andy", "po", "na", "pa", "kakain", "kain", "bahay",
             "house", "bago", "bagong", "the", "report", "i", "share", "xyzzy", "naman", "lang", "ate", "sa"]
    for n in range(60):
        ref = " ".join(rng.choice(vocab) for _ in range(rng.randint(0, 25)))
        hyp = " ".join(rng.choice(vocab) for _ in range(rng.randint(0, 25)))
        counts, events, _ = pair(ref, hyp, tmp_path)
        assert sum(e.error_words for e in events) == counts["errors"] == counts["standard_policy_errors"], (ref, hyp)
        for e in events:
            assert e.category in tx.CATEGORIES and e.basis in tx.BASES


# ---------------------------------------------------------------- adjudications

def test_a_human_decision_overrides_the_category_and_is_verified():
    adj = tx.load_adjudications(FIXTURE / "adjudications.tsv")
    assert adj == {"plain-heuristic": {"r8": ("spelling_variant", "adjudicated")}}
    c = run_fixture(adjudications=FIXTURE / "adjudications.tsv")["corpus"]
    assert c["adjudications_applied"] == 1
    assert c["categories"]["other_substitution"]["error_words"] == 1
    sv = c["categories"]["spelling_variant"]
    assert sv["error_words"] == 6 and sv["basis"]["verified"]["error_words"] == 1
    assert sv["basis"]["heuristic"]["error_words"] == 5
    assert c["errors"] == EXPECTED["errors"]


def test_adjudications_reject_unknown_categories(tmp_path):
    bad = tmp_path / "a.tsv"
    bad.write_text("item\tr1\tnot_a_category\n")
    with pytest.raises(SystemExit):
        tx.load_adjudications(bad)


# ---------------------------------------------------------------- reports

def test_the_report_is_byte_identical_and_independent_of_manifest_order(tmp_path):
    a, b, c = tmp_path / "a", tmp_path / "b", tmp_path / "c"
    run_fixture(out_dir=a)
    run_fixture(out_dir=b)
    manifest = json.loads((FIXTURE / "manifest.json").read_text())
    manifest["items"].reverse()
    shuffled = tmp_path / "shuffled"
    shuffled.mkdir()
    for sub in ("refs",):
        (shuffled / sub).symlink_to(FIXTURE / sub)
    (shuffled / "manifest.json").write_text(json.dumps(manifest))
    tx.report_from_manifest(shuffled / "manifest.json", FIXTURE / "hyp", label="fixture", out_dir=c)
    assert (a / "taxonomy.json").read_bytes() == (b / "taxonomy.json").read_bytes()
    assert (a / "taxonomy.md").read_bytes() == (b / "taxonomy.md").read_bytes()
    # the manifest bytes differ, so its hash does; everything else is the same
    ja, jc = json.loads((a / "taxonomy.json").read_text()), json.loads((c / "taxonomy.json").read_text())
    ja["inputs"].pop("manifestSha256"), jc["inputs"].pop("manifestSha256")
    assert ja == jc
    assert list(ja["items"]) == sorted(ja["items"])


def test_json_is_sorted_and_carries_provenance_but_no_paths_or_clock(tmp_path):
    run_fixture(out_dir=tmp_path)
    text = (tmp_path / "taxonomy.json").read_text()
    data = json.loads(text)
    assert text == json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    assert data["schema"] == tx.SCHEMA and data["config"]["fingerprintSha256"]
    assert set(data["lexicons"]) >= {"lexicon-tl.txt", "lexicon-en.txt", "spelling-variants.txt"}
    assert all(len(v["sha256"]) == 64 for v in data["lexicons"].values())
    assert str(REPO) not in text and "/tmp" not in text
    assert data["inputs"]["corpusId"] == "synthetic-taxonomy-fixture-v1"


def test_a_report_holds_no_corpus_text_unless_asked(tmp_path):
    run_fixture(out_dir=tmp_path / "plain")
    run_fixture(out_dir=tmp_path / "text", include_text=2)
    plain = (tmp_path / "plain" / "taxonomy.json").read_text() + (tmp_path / "plain" / "taxonomy.md").read_text()
    for word in ("kalabaw", "standup", "Marites", "marites", "umaga", "bukas"):
        assert word not in plain, word
    asked = json.loads((tmp_path / "text" / "taxonomy.json").read_text())["text_examples"]
    assert asked["proper_noun_error"][0]["ref"] in ("andy", "marites")
    assert all(len(rows) <= 2 for rows in asked.values())


def test_events_tsv_lists_every_event_with_indexes_a_person_can_adjudicate(tmp_path):
    out = tmp_path / "events.tsv"
    run_fixture(events_path=out)
    rows = [r.split("\t") for r in out.read_text().splitlines()]
    assert rows[0][:5] == ["item", "event", "category", "subtype", "basis"]
    n = sum(v["events"] for v in run_fixture()["corpus"]["categories"].values())
    assert len(rows) - 1 == n


def test_the_markdown_separates_the_bases_and_states_the_unlabelled_share():
    md = tx.render_markdown(run_fixture())
    assert "| verified | heuristic | structural |" in md
    assert "unknown" in md and "ambiguous" in md
    assert "112 of 169 reference tokens carry a word-level tag" in md
    only_heuristic = {"items": [{"id": "plain-heuristic", "ref": "refs/plain-heuristic.txt"}]}
    run = tx.run_items(only_heuristic["items"], FIXTURE, FIXTURE / "hyp", LEX, CFG, {})
    rep = tx.build_report(run, label="h", lex=LEX, cfg=CFG, manifest_sha=None, corpus_id=None, include_text=0,
                          hyp_source="hyp")
    assert "No reference token carries a word-level language tag" in " ".join(rep["caveats"])
    assert "Read the heuristic counts as indications" in tx.render_markdown(rep)


def test_missing_hypotheses_are_reported_not_scored(tmp_path):
    hyp = tmp_path / "hyp"
    hyp.mkdir()
    (hyp / "morphology.txt").write_text((FIXTURE / "hyp" / "morphology.txt").read_text())
    rep = tx.report_from_manifest(FIXTURE / "manifest.json", hyp, label="partial")
    assert rep["inputs"]["items_scored"] == 1
    assert rep["inputs"]["items_missing_hypothesis_or_reference"] == [
        "mixed-words", "plain-heuristic", "silence", "switching"]


def test_the_table_command_puts_reports_side_by_side(tmp_path):
    run_fixture(out_dir=tmp_path / "a")
    out = io.StringIO()
    with redirect_stdout(out):
        assert tx.main(["table", str(tmp_path / "a" / "taxonomy.json"), str(tmp_path / "a" / "taxonomy.json")]) == 0
    assert "| `proper_noun_error` | 2 | 2 |" in out.getvalue()


def test_the_cli_pair_command_prints_markdown_and_json(tmp_path):
    out = io.StringIO()
    with redirect_stdout(out):
        tx.main(["pair", "--reference", str(FIXTURE / "refs" / "mixed-words.tagged.txt"),
                 "--hypothesis", str(FIXTURE / "hyp" / "mixed-words.txt"), "--json"])
    assert json.loads(out.getvalue())["corpus"]["categories"]["mixed_word_error"]["error_words"] == 7


def test_an_extra_english_wordlist_changes_labels_and_its_hash_is_recorded(tmp_path):
    words = tmp_path / "words.txt"
    words.write_text("kalabaw\nzzyzx\n")
    lex = tlx.Lexicon(english_wordlist=words)
    assert tlx.classify_word("kalabaw", lex).lang == "en"
    desc = lex.describe()["english-wordlist (user supplied)"]
    assert desc["entries"] == 2 and len(desc["sha256"]) == 64
    assert tlx.classify_word("kalabaw", LEX).lang == "unknown"       # the shared lexicon is untouched


# ---------------------------------------------------------------- data files and configuration

def test_the_config_agrees_with_the_evaluation_config_it_mirrors():
    ev = json.loads((REPO / "eval" / "evaluation-config.v1.json").read_text())
    assert CFG["deletionRunMinWords"] == ev["deletionBurstMinWords"]
    assert CFG["nonSpeechPaddingMs"] == ev["missingSpeech"]["wordPaddingMs"]


def test_the_word_lists_are_lower_case_and_say_who_wrote_them():
    for name, info in LEX.files.items():
        assert info["source"] in ("written for this project by Claude (an AI model); no native-speaker review",) or name.startswith("english-wordlist")
    for path in (REPO / "eval" / "taxonomy-data").glob("*.txt"):
        text = path.read_text()
        flat = " ".join(text.replace("#", " ").split()).lower()
        assert "written by claude" in flat, path.name
        body = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
        assert body == body.lower(), path.name
    assert {"at", "may", "ate"} <= set(LEX.tl_en_overlap)


def test_the_spelling_variant_groups_have_no_word_in_two_groups():
    seen: dict[str, int] = {}
    for n, line in enumerate((REPO / "eval" / "taxonomy-data" / "spelling-variants.txt").read_text().splitlines()):
        words = line.split("#", 1)[0].split()
        for w in words:
            assert seen.setdefault(w, n) == n or len(words) < 2, w


# ---------------------------------------------------------------- the existing flow is untouched

REFS = {"a": "Simulan na natin ang meeting bukas.", "b": "Salamat po sa lahat."}
HYPS = {"a": "simulan na natin ang miting bukas", "b": "salamat sa lahat po"}


def make_flow(tmp_path: Path) -> tuple[Path, Path]:
    (tmp_path / "refs").mkdir()
    (tmp_path / "hyp").mkdir()
    manifest = []
    for k, text in REFS.items():
        (tmp_path / "refs" / f"{k}.txt").write_text(text)
        (tmp_path / "hyp" / f"{k}.txt").write_text(HYPS[k])
        manifest.append({"id": k, "audio": f"audio/{k}.wav", "ref": f"refs/{k}.txt", "category": "mixed"})
    (tmp_path / "manifest.json").write_text(json.dumps(manifest))
    return tmp_path / "manifest.json", tmp_path / "hyp"


def run_score(*argv: str) -> str:
    out = io.StringIO()
    with redirect_stdout(out):
        old = sys.argv
        sys.argv = ["score.py", *argv]
        try:
            assert pooled.main() == 0
        finally:
            sys.argv = old
    return out.getvalue()


def test_score_py_prints_the_same_table_with_and_without_the_taxonomy_flag(tmp_path):
    manifest, hyp = make_flow(tmp_path)
    base = run_score(str(hyp), "--manifest", str(manifest), "--label", "t")
    extra = run_score(str(hyp), "--manifest", str(manifest), "--label", "t", "--taxonomy-out", str(tmp_path / "tax"))
    assert extra.startswith(base)
    assert extra[len(base):].strip().startswith("taxonomy:")
    # the table's own numbers: 2 substitutions-or-moves in 11 words
    ref = [w for t in REFS.values() for w in pooled.normalize(t)]
    errors = sum(sum(pooled.levenshtein(pooled.normalize(REFS[k]), pooled.normalize(HYPS[k]))) for k in REFS)
    assert f"{errors / len(ref) * 100:.2f}%" in base
    data = json.loads((tmp_path / "tax" / "taxonomy.json").read_text())
    assert data["corpus"]["errors"] == errors and data["corpus"]["ref_words"] == len(ref)


def test_score_py_without_the_flag_writes_nothing_and_never_imports_the_taxonomy(tmp_path):
    manifest, hyp = make_flow(tmp_path)
    sys.modules.pop("taxonomy", None)
    try:
        run_score(str(hyp), "--manifest", str(manifest))
        assert "taxonomy" not in sys.modules
    finally:
        sys.modules["taxonomy"] = tx
    assert not (tmp_path / "tax").exists()


def test_the_tier_benchmark_taxonomy_command_reads_saved_hypotheses_only(tmp_path):
    manifest, hyp = make_flow(tmp_path)
    plan = {"manifest": {"path": str(manifest)}, "tiers": {"balanced": {}, "best": {}}}
    run = tmp_path / "run"
    for tier in plan["tiers"]:
        folder = run / "hyp" / tier
        folder.mkdir(parents=True)
        for k, text in HYPS.items():
            (folder / f"{k}.json").write_text(json.dumps({"transcript": text}))
    (run / "plan.json").write_text(json.dumps(plan))
    out = io.StringIO()
    with redirect_stdout(out):
        assert tb.main(["taxonomy", "--plan", str(run / "plan.json"), "--out-dir", str(tmp_path / "tax")]) == 0
    assert "| **errors** | 3 | 3 |" in out.getvalue()
    assert (tmp_path / "tax" / "balanced" / "taxonomy.json").exists() and (tmp_path / "tax" / "tiers.md").exists()


def test_compare_language_writes_an_optional_taxonomy_per_arm(tmp_path):
    manifest, hyp = make_flow(tmp_path)
    out_dir = tmp_path / "out"
    for arm in ("tl", "auto"):
        (out_dir / "offline" / arm).mkdir(parents=True)
        for k, text in HYPS.items():
            (out_dir / "offline" / arm / f"{k}.txt").write_text(text)
    written = cl.taxonomy_reports(manifest, out_dir, ["tl", "auto"], "offline")
    assert [a for a, _ in written] == ["tl", "auto"] and all(p.exists() for _, p in written)
