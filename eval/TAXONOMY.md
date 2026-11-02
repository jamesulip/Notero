# Error taxonomy for Taglish transcripts

`eval/taxonomy.py` answers the question a WER cannot: **what kind of mistake was each word
error?** It is an optional report on top of the existing evaluation. It reads the same
manifests, references and hypotheses, uses the same tokens and the same edit distance as the
headline WER, and changes no existing number or file.

It is a measuring tool with a heuristic part. Read [What the labels are](#what-the-labels-are)
before you quote a category count.

```bash
# A manifest (eval/manifest.json form, or the versioned form with a corpusId) and a directory
# of hypotheses: <id>.json (transcribe --json) or <id>.txt
python3 -I eval/taxonomy.py report --manifest eval/fixtures/taxonomy/manifest.json \
    --hyp-dir eval/fixtures/taxonomy/hyp --label fixture --out-dir /tmp/taxonomy

python3 -I eval/taxonomy.py pair --reference R.tagged.txt --hypothesis H.txt      # one file against one
python3 -I eval/taxonomy.py report ... --tie-break del-ins-sub    # how far the categories move (see below)
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir /tmp/tax
python3 -I eval/taxonomy.py table /tmp/tax/balanced/taxonomy.json /tmp/tax/best/taxonomy.json

# The same report from the existing tools (optional; their own output is unchanged):
python3 -I eval/score.py HYP_DIR --label x --taxonomy-out /tmp/taxonomy
python3 -I eval/tier_benchmark.py taxonomy --plan PLAN.json --out-dir /tmp/tax
python3 -I eval/compare_language.py --taxonomy ...
```

`report` writes `taxonomy.json` and `taxonomy.md`. `--include-text N` adds up to N example events
per category **with the reference and hypothesis words**. Without it the report holds no corpus
text, so it can be committed. With it, it must not be committed for third-party data.
`--events-tsv` writes every event with its words and indexes, for adjudication (below).

Nothing here needs a network, a model or a GPU. The tool never writes a clock time, a path or a
host name, and sorts every list, so **the same inputs give byte-identical files**. There is no
randomness. An alignment of more than 40 million cells is refused (`maxAlignmentCells`): split
the item by utterance.

## The tokens

The tokens are exactly `score.normalize`'s (`notero-standard`: NFKC, lower case, punctuation
dropped, hyphens split, apostrophes inside a word kept). That has two consequences that matter:

- **The categories partition the errors.** Each substitution, deletion and insertion is in exactly
  one event, so the error words of all categories add up to S + D + I, and that equals the
  standard-policy error count. The report prints both and says if they differ.
  The total cannot change. **The split between S, D and I can, and so can some category counts:**
  where two alignments have the same cost, the tie-break moves words between categories. The tool
  uses `langscore.align`'s tie-break (the older tools' choice). `--tie-break del-ins-sub` and
  `ins-del-sub` show the spread. On the Liva first decode it moved a category by up to 67
  words (Balanced `other_substitution` 1,258 to 1,191; Best `other_insertion` 52 to 106). Read no
  difference of less than about 70 words in one category: of the Best-against-Balanced differences, only
  the Tagalog-to-English substitutions and the deleted runs are larger. FLEURS moved by at most 8 words
  in a check that is not committed.
- **A hyphen is never an error.** "nag-meeting" is the tokens "nag" and "meeting", kept as one
  group so a mixed-language word can be recognised. "nagmeeting" and "nag meeting" are a
  join/split of the same letters, and are counted as `spelling_variant`.

## The categories

A word error belongs to the first rule that matches, in this order. Counts are **error words**
(and `events`: one event can be several words).

| # | Category | A word error is in it when |
| --- | --- | --- |
| 1 | `spelling_variant` (spacing) | a window of up to 4 operations has the same letters on both sides ("standup" / "stand up") |
| 2 | `deleted_speech` | it is in a run of 3 or more deleted reference words |
| 3 | `hallucination` | it is in a run of 3 or more inserted words. Flags: `repetition_loop` (3 identical words in a row, or 6+ words with at most 34% distinct), and with times `outside_reference_speech` (80% or more of the timed words fall outside every padded reference utterance) or `inside_reference_speech` (fewer). `time_unknown` if the reference or hypothesis has no times |
| 4 | `mixed_word_error` | a Tagalog-affix + English-stem word (a hyphen group of two tokens, or one token) labelled `mix` is deleted or mangled. Subtypes: `affix_dropped`, `affix_changed`, `stem_dropped`, `stem_changed`, `both_wrong`, `deleted` |
| 5 | `proper_noun_error` | a reference word labelled `name` is deleted or replaced (`near_spelling`, `different_word`, `deleted`) |
| 6 | `spelling_variant` (table) | reference and hypothesis are in one group of `eval/taxonomy-data/spelling-variants.txt` ("jan" / "dyan") |
| 7 | `morphology_error` | the two words share a Tagalog root and differ in affix, reduplication or linker: `affix_missing`, `affix_added`, `affix_changed`, `reduplication_dropped`, `reduplication_added`, `ligature_dropped`, `ligature_added` |
| 8 | `enclitic_particle` | a particle (`particles.txt`: po, ho, naman, lang, na, pa, din, rin, daw, raw, nga, pala, yata, ata, ba, muna, kaya, sana, kasi, man) is deleted, inserted or replaced |
| 9 | `boundary_error` | the reference word is the first word after, or the last word before, a code-switch point and it is deleted or replaced. Subtypes: `deleted`, `carry_over` (the hypothesis kept the language across the switch), `anticipation` (it switched early), `same_language` (the word is the right language and wrong: a misrecognition at a switch, not a failure to switch), `unresolved` |
| 10 | `tl_to_en_substitution`, `en_to_tl_substitution` | a clearly Tagalog reference word became a clearly English hypothesis word, or the reverse. This labels the **output word's** language, not the intent: it cannot tell a translation from a mishearing |
| 11 | `other_substitution`, `other_deletion`, `other_insertion` | nothing above applied |

A few rules are order-dependent on purpose: a name beats a boundary, a particle beats a language
swap, and `deleted_speech` takes any word of a long run whatever it is. A word that fits two rules
is counted under the earlier one. That is a design choice and not a linguistic finding. Every
event also carries overlay flags that do not change its category (`at_boundary`,
`short_reference_word`, `language_unresolved`, `root_unlisted`).

The same report lists **every** substitution by reference and hypothesis language (a matrix),
the error rate by reference label, and the error rate at code-switch points against elsewhere.
Those tables are not limited by the precedence above. A switch point needs two words that are
clearly Tagalog and English, so the fair comparison for a switch-point word is with other
`tl`- or `en`-labelled words; the report prints that control and the rate for all other words
(which includes the `unknown`, `ambiguous`, `other` and `name` words, and is biased against the
control).

`timestamp_misalignment` is **not a category**. It is an overlay on recognised words (equal or
substituted): the hypothesis word's time is more than `timestampToleranceMs` (1,000 ms) outside
its reference utterance. It needs word times in the hypothesis and utterance times in the
reference, and it says "not available" with the reason when either is missing. The reference
times are per utterance, so a word inside a long utterance is never misaligned, and an alignment
that drifts across overlapped speech also shows up. The tolerance is a setting and was not
calibrated.

## What the labels are

Every token has a language label, and every label has a **basis**:

| Basis | Meaning |
| --- | --- |
| `verified` | the reference carries a word-level tag for this token (below). A person said so. This tool does not check the person |
| `heuristic` | the tool guessed, from small word lists and rules (below) |
| `structural` | no language judgement is needed: a run of missing or invented words, an isolated extra or missing word, a timestamp |

`verified` and `heuristic` are **never added together**: every category row, every subtype and flag
row, every language table and the switch-point table is split by basis. A hypothesis word is never
tagged by a person, so a language-direction substitution (`tl_to_en`, `en_to_tl`) is `heuristic`
even when its reference word is `verified`. The same holds for a boundary event: only `deleted`
can be `verified` (it needs the reference tags of the word and its neighbour); `carry_over`,
`anticipation`, `same_language` and `unresolved` read the hypothesis word's language and are
`heuristic`. `spelling_variant` is `heuristic`: it is decided by letter equality or a list, with no
language judgement, but the list is a heuristic. A human decision about a whole event
(adjudication) is `verified`.

Labels: `tl`, `en`, `mix` (a Tagalog affix on an English stem), `name`, `other` (digits, fillers,
laughter, acronyms), `ambiguous` and `unknown`. **`unknown` is the answer for any word the lists
do not cover.** The old `eval/langscore.py` calls every unlisted word Filipino; this tool does
not, and the report states how many tokens are `unknown` or `ambiguous`.

The heuristic, in order (the report counts tokens by the rule that fired):

1. digits, fillers (`lexicon-other.txt`), laughter: `other`;
2. an apostrophe form: an English contraction (`don't`, `it's`, `I'm`; for `'t` the head must end
   in "n") is `en`; Tagalog `'y` (`ako'y`) is `tl`; any other (`ba't`, `hangga't`) is `unknown`;
3. a word on `homographs.txt`, or on both the Tagalog and the English list: `ambiguous`;
4. a name on `lexicon-names.txt` that is on neither list: `name`;
5. the Tagalog list, a Tagalog affix analysis (below) whose root is listed, or the linker
   (-ng / -g): `tl`; the English list or a regular English inflection: `en`;
6. a hyphenated two-piece word whose first piece is a Tagalog affix: stem English: `mix`; stem
   Tagalog: `tl`; stem on both lists: `ambiguous`; stem on neither: `unknown` (not guessed);
7. in a **cased** reference only: a capitalised word in the middle of a sentence that is on neither
   list is a `name`, and a 2-6 letter all-capitals word is `other`. The reference's case is the
   transcriber's, so a reference in lower case gets no capitalisation labels. A hypothesis's capital
   letters are never used;
8. an `ambiguous` word whose two neighbours in the same utterance are both clearly Tagalog (or both
   clearly English) takes that language, marked `context`.

### Word lists

All lists are in `eval/taxonomy-data/`, **written by Claude (the AI model that made this change) from general
knowledge, for this project**. They were not copied from a dictionary, a corpus, a frequency list or
the system word list. An independent check found no sign of a copy (an independent count found 194 entries of the English list that the system
word list does not contain, which argues against a copy of that list only), but a model writing from memory cannot
prove that its sources are clean, so treat "no third-party licence" as an assertion and not a
finding. They are offered under this repository's MIT licence. They have not been reviewed by a
native speaker, and they are small: about 990 Tagalog, 940 English and 150 name entries at the time
of writing. The report records each list's
size and SHA-256. A list can be extended with `--english-wordlist FILE` (for example
`/usr/share/dict/words`); its hash is recorded, and the change of labels is real, so say so when
you quote the result.

**These lists are not blind to the Liva corpus.** The model that wrote them had already read the Liva
error analysis of the tier comparison. The first English list had a line of game words (including
"mushroom", "discord", "lag", "ping", "forest") that matched that corpus; they were removed before the
committed reports were made, and the English list still has generic game and streaming words. The first
batch of lists was written before any corpus was scored by this tool. These changes were made after
looking at its output, and they are disclosed because they are tuning:
(1) the homograph list was shortened to words that are real words in both languages; (2) a capitalised
word that is on either list is no longer called a name; (3) a set of function words ("ano", "man",
pronouns, markers) can no longer be the root of an affix analysis ("ma" + "nila" had made "Manila"
Tagalog, "na" + "man" had made "naman" an affixed word); (4) `'t` is English only after "n" (Tagalog
"ba't" had been called English); (5) a linker pair cannot contain an English word ("meeting" /
"meetin"); (6) the corpus-flavoured English entries above. No change added words because they were
frequent in a corpus.

### The affix analyser

`taxonomy_lex.analyses` reads a word as (prefix)(infix `um`/`in`)(reduplication) + root +
(suffix `-in`, `-hin`, `-an`, `-han`), with about 60 prefixes (`mag-`, `nag-`, `ma-`, `na-`,
`maka-`, `naka-`, `magpa-`, `ipa-`, `pinag-`, `ka-`, `pa-`, `i-`, ...). The reduplicated syllable
is the root's first consonant and vowel, or its first vowel ("ka" + kain, "ta" + trabaho, "a" +
aral). Two words are related when some reading of each gives the same root of 3 or more letters
and that root is a listed Tagalog word (otherwise a root of 4 or more letters between two
non-English words, flagged `root_unlisted`). It does not know irregular forms, sound changes
(d/r, the nasal assimilation of `pang-`), full-word reduplication ("araw-araw") or stress.

## Reference formats

All are local files a person can edit. No service is involved.

| Form | Notes |
| --- | --- |
| `<id>.txt` | plain text, one utterance per line, no language information |
| `<id>.tagged.txt` | plain text with inline per-word tags (below) |
| `<id>.json` | the repository's reference form: `utterances` with `startMs`, `endMs`, `speaker`, `overlap`, `language` and word-level `languageSpans` (`tl`, `fil`, `en`, plus the extensions `mix`, `ne`, `oth`). Spans must concatenate to `text`; an utterance whose spans do not is counted and left untagged. Optional top-level `annotation` object, recorded in the report |

**Only word-level tags label tokens.** An utterance-level `language` ("tl", "mixed") is kept as
metadata and does not label any token: a line tagged `tl` can hold English words, and treating it
as a word label would be an unsupported claim. The Liva references have only that.

The tagged text form:

```
# a comment
!annotator: free text, recorded in the report
[id=u1 spk=A t=0-3200] Simulan/tl na/tl natin/tl ang/tl standup/en.
[id=u2 t=3400-7600] Pakisend/tl yung/tl file/en, nag-meeting/mix kami/tl kay/tl Andy/ne.
Sige, i-follow/mix up/mix ko yan.            (no header: the id is the line number; untagged words are heuristic)
```

A tag is `/tl`, `/en`, `/mix`, `/ne` (a proper name) or `/oth` (any case), written directly after a
word and before its trailing punctuation. It tags every token of that whitespace-separated word, so
`nag-meeting/mix` tags both pieces. A word that ends in `/letters` that is not a tag (a typo such as
`natin/xx`) stays in the text, and **the report counts it and says so**, because it changes the
reference length. A leading `[...]` is a header only when every part is `key=value`; `[laughing]` is
text. Header keys: `id`, `spk`, `t` (start-end in ms), `overlap=1`. Times are optional and are only
used for the hallucination-in-silence and timestamp reports.

**Keep tagged and JSON references out of any manifest that `score.py`, `compare_language.py` or
`transcribe --score` reads.** `score.py` reads a reference as plain text and would count the tags as
words; `score.py --taxonomy-out` refuses such a manifest. Use a manifest of its own with
`taxonomy.py report`. When a hypothesis directory has both `<id>.json` and `<id>.txt`, the taxonomy
reads the `.json`, and `score.py` reads the `.txt`. The tool needs Python 3.10 or newer.

### Adjudications

Run with `--events-tsv events.tsv`, read the events (indexes `r<n>` for a reference token and
`h<n>` for a hypothesis token), and write the decisions you disagree with:

```
# item<TAB>r12|h7<TAB>category<TAB>subtype<TAB>note
plain-heuristic	r8	spelling_variant	adjudicated	same word, spelling only
```

`--adjudications FILE` then moves that event to your category with basis `verified`, and the
report counts how many were applied and how many matched nothing. An unknown category is an
error. The same total, the same partition.

## Configuration

`eval/taxonomy-config.v1.json` (fingerprinted in every report): run lengths (3 and 3, equal to
the evaluation config's `deletionBurstMinWords`; a test keeps them equal), the 200 ms speech
padding (equal to `missingSpeech.wordPaddingMs`), the 80% outside-speech threshold, the 1,000 ms
timestamp tolerance, the 0.6 near-miss similarity, and the loop rule. These are settings, not
measurements. `eval/evaluation-config.v1.json` is not touched, so the evaluation fingerprint is
unchanged.

## What this does not tell you

- **It is not ground truth.** With no tagged reference, every language label is a heuristic from
  small lists. The report says so at the top when that is the case.
- **The category counts depend on the tie-break** between equal-cost alignments (above).
- **The capitalisation rule over-calls names** in references whose capitals are not all names. Read a
  `proper_noun_error` count from a cased vendor transcript as an upper bound.
- **It is not a benchmark of a corpus.** The Liva and FLEURS numbers in
  [BENCHMARKS.md](../docs/BENCHMARKS.md#error-taxonomy-of-the-tier-decodes-2026-11-02) are from one
  friend group and one read-speech set. They say how these decodes fail, not how Notero fails on
  your meetings.
- **Overlapped speech breaks the reading order.** A reference that interleaves speakers has no
  single word order, so part of its substitutions, deletions and insertions are alignment
  artefacts.
- **Heuristic precision was not measured.** Claude read 24 morphology events from each of the two
  corpora and judged 44 plausible, 2 wrong ("ano" read as "nag" + "ano", "naman" as "na" + "man";
  both fixed by keeping function words from being roots) and 2 doubtful. Those readings were not
  saved, so treat them as an anecdote. An independent review scanned the pairs the lists can make
  and found no clear error in an 80-pair sample. No native speaker has reviewed the lists.
- **No claim of representativeness.** None of the data used here is a meeting, and none is
  far-field.

## Files

| File | What |
| --- | --- |
| `eval/taxonomy.py` | alignment to events, counting, reports, CLI |
| `eval/taxonomy_io.py` | tokenizer, the reference and hypothesis formats |
| `eval/taxonomy_lex.py` | word lists, language labels, the affix analyser |
| `eval/taxonomy-config.v1.json` | settings |
| `eval/taxonomy-data/` | the word lists (provenance above) |
| `eval/fixtures/taxonomy/` | synthetic fixtures with expected counts worked out from the sentences |
| `eval/baselines/taxonomy-2026-11-02/` | aggregate reports on the local Liva and FLEURS decodes, with two other tie-breaks (no corpus text) |
| `tests/test_taxonomy.py` | the tests |
