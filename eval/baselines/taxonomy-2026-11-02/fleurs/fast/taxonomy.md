# Error taxonomy: fast

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `fleurs-fil_ph-test-onepersentence-seed7`, manifest SHA-256 `50765003e1bf07bc…`; alignment tie-break `default`
- items scored: 349; missing a hypothesis or reference: 0
- reference formats: {'txt': 349}; hypothesis formats: {'json': 349}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

9613 reference words, 9642 hypothesis words. Substitutions 900, deletions 120, insertions 149; **1169 errors, WER 12.16%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 1169 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `en_to_tl_substitution` | 1 | 1 | 0.1% | 0 | 1 | 0 |
| `boundary_error` | 2 | 2 | 0.2% | 0 | 2 | 0 |
| `morphology_error` | 109 | 109 | 9.3% | 0 | 109 | 0 |
| `proper_noun_error` | 124 | 124 | 10.6% | 0 | 124 | 0 |
| `hallucination` | 7 | 33 | 2.8% | 0 | 0 | 33 |
| `deleted_speech` | 4 | 27 | 2.3% | 0 | 0 | 27 |
| `enclitic_particle` | 27 | 27 | 2.3% | 0 | 27 | 0 |
| `spelling_variant` | 74 | 145 | 12.4% | 0 | 145 | 0 |
| `other_substitution` | 575 | 575 | 49.2% | 0 | 575 | 0 |
| `other_deletion` | 42 | 42 | 3.6% | 0 | 0 | 42 |
| `other_insertion` | 84 | 84 | 7.2% | 0 | 0 | 84 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `anticipation` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `same_language` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_added` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `affix_changed` | 22 | 22 | 0 | 22 | 0 |
| `morphology_error` | `affix_missing` | 19 | 19 | 0 | 19 | 0 |
| `morphology_error` | `ligature_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `ligature_dropped` | 33 | 33 | 0 | 33 | 0 |
| `morphology_error` | `reduplication_added` | 11 | 11 | 0 | 11 | 0 |
| `morphology_error` | `reduplication_dropped` | 17 | 17 | 0 | 17 | 0 |
| `proper_noun_error` | `deleted` | 4 | 4 | 0 | 4 | 0 |
| `proper_noun_error` | `different_word` | 19 | 19 | 0 | 19 | 0 |
| `proper_noun_error` | `near_spelling` | 101 | 101 | 0 | 101 | 0 |
| `hallucination` | `run` | 7 | 33 | 0 | 0 | 33 |
| `deleted_speech` | `run` | 4 | 27 | 0 | 0 | 27 |
| `enclitic_particle` | `deleted` | 3 | 3 | 0 | 3 | 0 |
| `enclitic_particle` | `inserted` | 7 | 7 | 0 | 7 | 0 |
| `enclitic_particle` | `substituted` | 17 | 17 | 0 | 17 | 0 |
| `spelling_variant` | `spacing` | 69 | 140 | 0 | 140 | 0 |
| `spelling_variant` | `variant-table` | 5 | 5 | 0 | 5 | 0 |
| `other_substitution` | `near_miss` | 408 | 408 | 0 | 408 | 0 |
| `other_substitution` | `unrelated` | 167 | 167 | 0 | 167 | 0 |
| `other_deletion` | `isolated` | 42 | 42 | 0 | 0 | 42 |
| `other_insertion` | `isolated` | 84 | 84 | 0 | 0 | 84 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `time_unknown`: the reference has no times, or the hypothesis has no word times; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `en_to_tl_substitution` | `short_reference_word` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `at_boundary` | 2 | 2 | 0 | 2 | 0 |
| `boundary_error` | `short_reference_word` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `root_unlisted` | 71 | 71 | 0 | 71 | 0 |
| `hallucination` | `time_unknown` | 7 | 33 | 0 | 0 | 33 |
| `deleted_speech` | `at_boundary` | 1 | 4 | 0 | 0 | 4 |
| `other_substitution` | `language_unresolved` | 498 | 498 | 0 | 498 | 0 |
| `other_substitution` | `short_reference_word` | 151 | 151 | 0 | 151 | 0 |

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
| heuristic | 6107 | 59 | 4 | 15 | 98 | 265 | 3094 | 9642 |

Heuristic tokens that are `unknown` or `ambiguous`: 3359 of 9642 (34.8%). Heuristic tokens labelled `tl` or `en`: 6166 (63.9%).

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
| heuristic | tl | 141 | 0 | 0 | 1 | 2 | 2 | 64 |
| heuristic | en | 2 | 0 | 0 | 0 | 0 | 0 | 1 |
| heuristic | name | 3 | 2 | 0 | 0 | 0 | 0 | 121 |
| heuristic | other | 19 | 1 | 0 | 0 | 10 | 0 | 12 |
| heuristic | ambiguous | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| heuristic | unknown | 88 | 16 | 1 | 0 | 5 | 2 | 406 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 6013 | 210 | 53 | 4.4% |
| heuristic | en | 38 | 3 | 0 | 7.9% |
| heuristic | mix | 2 | 0 | 0 | 0.0% |
| heuristic | name | 572 | 126 | 5 | 22.9% |
| heuristic | other | 154 | 42 | 10 | 33.8% |
| heuristic | ambiguous | 260 | 1 | 4 | 1.9% |
| heuristic | unknown | 2574 | 518 | 48 | 22.0% |

Inserted words by (heuristic) language: ambiguous 7, en 1, mix 1, other 5, tl 85, unknown 50.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 36.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 60 | 3 | 5.0% |
| elsewhere, labelled `tl` or `en` (heuristic) | 5991 | 263 | 4.4% |
| elsewhere, any label | 9553 | 1017 | 10.6% |

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
