# Error taxonomy: best

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `fleurs-fil_ph-test-onepersentence-seed7`, manifest SHA-256 `50765003e1bf07bc…`; alignment tie-break `default`
- items scored: 349; missing a hypothesis or reference: 0
- reference formats: {'txt': 349}; hypothesis formats: {'json': 349}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

9613 reference words, 9614 hypothesis words. Substitutions 842, deletions 124, insertions 125; **1091 errors, WER 11.35%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 1091 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 1 | 1 | 0.1% | 0 | 1 | 0 |
| `boundary_error` | 1 | 1 | 0.1% | 0 | 1 | 0 |
| `morphology_error` | 98 | 98 | 9.0% | 0 | 98 | 0 |
| `proper_noun_error` | 111 | 111 | 10.2% | 0 | 111 | 0 |
| `hallucination` | 1 | 3 | 0.3% | 0 | 0 | 3 |
| `deleted_speech` | 5 | 30 | 2.7% | 0 | 0 | 30 |
| `enclitic_particle` | 29 | 29 | 2.7% | 0 | 29 | 0 |
| `spelling_variant` | 71 | 139 | 12.7% | 0 | 139 | 0 |
| `other_substitution` | 547 | 547 | 50.1% | 0 | 547 | 0 |
| `other_deletion` | 43 | 43 | 3.9% | 0 | 0 | 43 |
| `other_insertion` | 89 | 89 | 8.2% | 0 | 0 | 89 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `anticipation` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_added` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `affix_changed` | 19 | 19 | 0 | 19 | 0 |
| `morphology_error` | `affix_missing` | 19 | 19 | 0 | 19 | 0 |
| `morphology_error` | `ligature_added` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `ligature_dropped` | 24 | 24 | 0 | 24 | 0 |
| `morphology_error` | `reduplication_added` | 11 | 11 | 0 | 11 | 0 |
| `morphology_error` | `reduplication_dropped` | 15 | 15 | 0 | 15 | 0 |
| `proper_noun_error` | `deleted` | 3 | 3 | 0 | 3 | 0 |
| `proper_noun_error` | `different_word` | 17 | 17 | 0 | 17 | 0 |
| `proper_noun_error` | `near_spelling` | 91 | 91 | 0 | 91 | 0 |
| `hallucination` | `run` | 1 | 3 | 0 | 0 | 3 |
| `deleted_speech` | `run` | 5 | 30 | 0 | 0 | 30 |
| `enclitic_particle` | `deleted` | 5 | 5 | 0 | 5 | 0 |
| `enclitic_particle` | `inserted` | 9 | 9 | 0 | 9 | 0 |
| `enclitic_particle` | `substituted` | 15 | 15 | 0 | 15 | 0 |
| `spelling_variant` | `spacing` | 66 | 134 | 0 | 134 | 0 |
| `spelling_variant` | `variant-table` | 5 | 5 | 0 | 5 | 0 |
| `other_substitution` | `near_miss` | 382 | 382 | 0 | 382 | 0 |
| `other_substitution` | `unrelated` | 165 | 165 | 0 | 165 | 0 |
| `other_deletion` | `isolated` | 43 | 43 | 0 | 0 | 43 |
| `other_insertion` | `isolated` | 89 | 89 | 0 | 0 | 89 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `time_unknown`: the reference has no times, or the hypothesis has no word times; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `at_boundary` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `short_reference_word` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `root_unlisted` | 72 | 72 | 0 | 72 | 0 |
| `hallucination` | `time_unknown` | 1 | 3 | 0 | 0 | 3 |
| `deleted_speech` | `at_boundary` | 1 | 4 | 0 | 0 | 4 |
| `other_substitution` | `language_unresolved` | 475 | 475 | 0 | 475 | 0 |
| `other_substitution` | `short_reference_word` | 134 | 134 | 0 | 134 | 0 |

## Language labels

**Reference tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| heuristic | 6013 | 38 | 2 | 572 | 154 | 260 | 2574 | 9613 |

Heuristic tokens that are `unknown` or `ambiguous`: 2834 of 9613 (29.5%). Heuristic tokens labelled `tl` or `en`: 6051 (62.9%).

**Hypothesis tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | 6086 | 60 | 6 | 17 | 108 | 262 | 3075 | 9614 |

Heuristic tokens that are `unknown` or `ambiguous`: 3337 of 9614 (34.7%). Heuristic tokens labelled `tl` or `en`: 6146 (63.9%).

Heuristic reference labels by rule:

| label | rule | tokens |
| --- | --- | ---: |
| tl | `lexicon-tl` | 5195 |
| tl | `tl-ligature` | 380 |
| tl | `tl-affix-analysis` | 299 |
| tl | `context` | 76 |
| tl | `affix+tagalog-stem` | 62 |
| tl | `tagalog-clitic-y` | 1 |
| en | `lexicon-en` | 36 |
| en | `en-inflection` | 1 |
| en | `english-contraction` | 1 |
| mix | `affix+english-stem` | 2 |
| name | `capitalised-mid-sentence` | 569 |
| name | `names-lexicon` | 3 |
| other | `digits` | 107 |
| other | `acronym` | 34 |
| other | `alphanumeric` | 12 |
| other | `filler-or-laughter` | 1 |
| ambiguous | `homograph-list` | 259 |
| ambiguous | `in-both-lexicons` | 1 |
| unknown | `no-match` | 2471 |
| unknown | `affix+unlisted-stem` | 68 |
| unknown | `apostrophe-no-match` | 35 |

## Substitutions by language (reference row, hypothesis column)

| reference basis | reference label | tl | en | mix | name | other | ambiguous | unknown |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | tl | 125 | 1 | 0 | 1 | 2 | 1 | 58 |
| heuristic | en | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| heuristic | name | 3 | 2 | 0 | 0 | 0 | 0 | 109 |
| heuristic | other | 9 | 1 | 0 | 0 | 10 | 0 | 10 |
| heuristic | ambiguous | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| heuristic | unknown | 95 | 13 | 2 | 0 | 5 | 4 | 388 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 6013 | 188 | 57 | 4.1% |
| heuristic | en | 38 | 1 | 2 | 7.9% |
| heuristic | mix | 2 | 0 | 0 | 0.0% |
| heuristic | name | 572 | 114 | 5 | 20.8% |
| heuristic | other | 154 | 30 | 11 | 26.6% |
| heuristic | ambiguous | 260 | 2 | 6 | 3.1% |
| heuristic | unknown | 2574 | 507 | 43 | 21.4% |

Inserted words by (heuristic) language: ambiguous 6, en 2, mix 2, other 7, tl 68, unknown 40.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 36.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 60 | 2 | 3.3% |
| elsewhere, labelled `tl` or `en` (heuristic) | 5991 | 246 | 4.1% |
| elsewhere, any label | 9553 | 964 | 10.1% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

Not available.

Items without it: 349 × reference has no utterance times.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen. This report used the `default` tie-break (the one of eval/langscore.py, which the older tools use). The total never changes, but a category can move by tens of words under another tie-break (`--tie-break`; 67 words at most in the Liva check): do not read a difference of less than about 70 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
