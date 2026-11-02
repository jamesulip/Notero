# Error taxonomy: balanced

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`; alignment tie-break `del-ins-sub`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3782 hypothesis words. Substitutions 1789, deletions 1875, insertions 120; **3784 errors, WER 68.34%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3784 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 148 | 148 | 3.9% | 0 | 148 | 0 |
| `en_to_tl_substitution` | 30 | 30 | 0.8% | 0 | 30 | 0 |
| `boundary_error` | 155 | 155 | 4.1% | 0 | 155 | 0 |
| `mixed_word_error` | 13 | 19 | 0.5% | 0 | 19 | 0 |
| `morphology_error` | 40 | 40 | 1.1% | 0 | 40 | 0 |
| `proper_noun_error` | 43 | 43 | 1.1% | 0 | 43 | 0 |
| `hallucination` | 7 | 39 | 1.0% | 0 | 0 | 39 |
| `deleted_speech` | 236 | 1512 | 40.0% | 0 | 0 | 1512 |
| `enclitic_particle` | 190 | 190 | 5.0% | 0 | 190 | 0 |
| `spelling_variant` | 27 | 42 | 1.1% | 0 | 42 | 0 |
| `other_substitution` | 1210 | 1210 | 32.0% | 0 | 1210 | 0 |
| `other_deletion` | 289 | 289 | 7.6% | 0 | 0 | 289 |
| `other_insertion` | 67 | 67 | 1.8% | 0 | 0 | 67 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 148 | 148 | 0 | 148 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 30 | 30 | 0 | 30 | 0 |
| `boundary_error` | `anticipation` | 17 | 17 | 0 | 17 | 0 |
| `boundary_error` | `carry_over` | 19 | 19 | 0 | 19 | 0 |
| `boundary_error` | `deleted` | 20 | 20 | 0 | 20 | 0 |
| `boundary_error` | `same_language` | 35 | 35 | 0 | 35 | 0 |
| `boundary_error` | `unresolved` | 64 | 64 | 0 | 64 | 0 |
| `mixed_word_error` | `affix_changed` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `affix_dropped` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `both_wrong` | 6 | 12 | 0 | 12 | 0 |
| `mixed_word_error` | `stem_changed` | 3 | 3 | 0 | 3 | 0 |
| `morphology_error` | `affix_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_changed` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `affix_missing` | 10 | 10 | 0 | 10 | 0 |
| `morphology_error` | `ligature_added` | 7 | 7 | 0 | 7 | 0 |
| `morphology_error` | `ligature_dropped` | 11 | 11 | 0 | 11 | 0 |
| `morphology_error` | `reduplication_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `reduplication_dropped` | 4 | 4 | 0 | 4 | 0 |
| `proper_noun_error` | `deleted` | 8 | 8 | 0 | 8 | 0 |
| `proper_noun_error` | `different_word` | 27 | 27 | 0 | 27 | 0 |
| `proper_noun_error` | `near_spelling` | 8 | 8 | 0 | 8 | 0 |
| `hallucination` | `repetition_loop` | 1 | 11 | 0 | 0 | 11 |
| `hallucination` | `run` | 6 | 28 | 0 | 0 | 28 |
| `deleted_speech` | `run` | 236 | 1512 | 0 | 0 | 1512 |
| `enclitic_particle` | `deleted` | 31 | 31 | 0 | 31 | 0 |
| `enclitic_particle` | `inserted` | 12 | 12 | 0 | 12 | 0 |
| `enclitic_particle` | `substituted` | 147 | 147 | 0 | 147 | 0 |
| `spelling_variant` | `spacing` | 14 | 29 | 0 | 29 | 0 |
| `spelling_variant` | `variant-table` | 13 | 13 | 0 | 13 | 0 |
| `other_substitution` | `near_miss` | 178 | 178 | 0 | 178 | 0 |
| `other_substitution` | `unrelated` | 1032 | 1032 | 0 | 1032 | 0 |
| `other_deletion` | `isolated` | 289 | 289 | 0 | 0 | 289 |
| `other_insertion` | `isolated` | 67 | 67 | 0 | 0 | 67 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 110 | 110 | 0 | 110 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 19 | 19 | 0 | 19 | 0 |
| `boundary_error` | `at_boundary` | 155 | 155 | 0 | 155 | 0 |
| `boundary_error` | `short_reference_word` | 101 | 101 | 0 | 101 | 0 |
| `morphology_error` | `at_boundary` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `root_unlisted` | 13 | 13 | 0 | 13 | 0 |
| `hallucination` | `inside_reference_speech` | 7 | 39 | 0 | 0 | 39 |
| `deleted_speech` | `at_boundary` | 61 | 530 | 0 | 0 | 530 |
| `enclitic_particle` | `at_boundary` | 9 | 9 | 0 | 9 | 0 |
| `spelling_variant` | `at_boundary` | 3 | 6 | 0 | 6 | 0 |
| `other_substitution` | `language_unresolved` | 946 | 946 | 0 | 946 | 0 |
| `other_substitution` | `short_reference_word` | 787 | 787 | 0 | 787 | 0 |

## Language labels

**Reference tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| heuristic | 2964 | 640 | 50 | 95 | 299 | 188 | 1301 | 5537 |

Heuristic tokens that are `unknown` or `ambiguous`: 1489 of 5537 (26.9%). Heuristic tokens labelled `tl` or `en`: 3604 (65.1%).

**Hypothesis tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | 1790 | 663 | 24 | 4 | 169 | 110 | 1022 | 3782 |

Heuristic tokens that are `unknown` or `ambiguous`: 1132 of 3782 (29.9%). Heuristic tokens labelled `tl` or `en`: 2453 (64.9%).

Heuristic reference labels by rule:

| label | rule | tokens |
| --- | --- | ---: |
| tl | `lexicon-tl` | 2747 |
| tl | `tl-affix-analysis` | 71 |
| tl | `tl-ligature` | 67 |
| tl | `context` | 44 |
| tl | `affix+tagalog-stem` | 30 |
| tl | `tagalog-clitic-y` | 5 |
| en | `lexicon-en` | 575 |
| en | `en-inflection` | 48 |
| en | `english-contraction` | 12 |
| en | `context` | 5 |
| mix | `affix+english-stem` | 50 |
| name | `capitalised-mid-sentence` | 94 |
| name | `names-lexicon` | 1 |
| other | `filler-or-laughter` | 233 |
| other | `digits` | 37 |
| other | `acronym` | 23 |
| other | `alphanumeric` | 6 |
| ambiguous | `homograph-list` | 188 |
| unknown | `no-match` | 1129 |
| unknown | `affix+unlisted-stem` | 150 |
| unknown | `apostrophe-no-match` | 22 |

## Substitutions by language (reference row, hypothesis column)

| reference basis | reference label | tl | en | mix | name | other | ambiguous | unknown |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | tl | 351 | 192 | 3 | 2 | 41 | 27 | 282 |
| heuristic | en | 50 | 47 | 0 | 0 | 11 | 8 | 72 |
| heuristic | mix | 3 | 2 | 3 | 0 | 3 | 0 | 6 |
| heuristic | name | 5 | 7 | 0 | 0 | 0 | 1 | 22 |
| heuristic | other | 31 | 17 | 1 | 0 | 6 | 4 | 23 |
| heuristic | ambiguous | 19 | 15 | 0 | 0 | 4 | 3 | 15 |
| heuristic | unknown | 139 | 109 | 2 | 2 | 25 | 13 | 223 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 898 | 947 | 62.2% |
| heuristic | en | 640 | 188 | 201 | 60.8% |
| heuristic | mix | 50 | 17 | 12 | 58.0% |
| heuristic | name | 95 | 35 | 31 | 69.5% |
| heuristic | other | 299 | 82 | 132 | 71.6% |
| heuristic | ambiguous | 188 | 56 | 80 | 72.3% |
| heuristic | unknown | 1301 | 513 | 472 | 75.7% |

Inserted words by (heuristic) language: ambiguous 4, en 18, mix 1, other 7, tl 60, unknown 30.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 274.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 495 | 285 | 57.6% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3109 | 1949 | 62.7% |
| elsewhere, any label | 5042 | 3379 | 67.0% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3657 aligned word pairs in 4 items; **684 (18.7%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 279, '<=2000ms': 177, '<=5000ms': 263, '>5000ms': 244, 'inside': 2694}; largest 28181 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen. This report used the `del-ins-sub` tie-break (not the default). The total never changes, but a category can move by tens of words under another tie-break (`--tie-break`; 67 words at most in the Liva check): do not read a difference of less than about 70 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
