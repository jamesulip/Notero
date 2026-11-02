# Error taxonomy: fast

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3587 hypothesis words. Substitutions 1805, deletions 2024, insertions 74; **3903 errors, WER 70.49%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3903 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 169 | 169 | 4.3% | 0 | 169 | 0 |
| `en_to_tl_substitution` | 20 | 20 | 0.5% | 0 | 20 | 0 |
| `boundary_error` | 149 | 149 | 3.8% | 0 | 149 | 0 |
| `mixed_word_error` | 13 | 20 | 0.5% | 0 | 20 | 0 |
| `morphology_error` | 36 | 36 | 0.9% | 0 | 36 | 0 |
| `proper_noun_error` | 44 | 44 | 1.1% | 0 | 44 | 0 |
| `hallucination` | 5 | 27 | 0.7% | 0 | 0 | 27 |
| `deleted_speech` | 243 | 1661 | 42.6% | 0 | 0 | 1661 |
| `enclitic_particle` | 183 | 183 | 4.7% | 0 | 183 | 0 |
| `spelling_variant` | 24 | 39 | 1.0% | 0 | 39 | 0 |
| `other_substitution` | 1235 | 1235 | 31.6% | 0 | 1235 | 0 |
| `other_deletion` | 279 | 279 | 7.1% | 0 | 0 | 279 |
| `other_insertion` | 41 | 41 | 1.1% | 0 | 0 | 41 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 169 | 169 | 0 | 169 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 20 | 20 | 0 | 20 | 0 |
| `boundary_error` | `anticipation` | 18 | 18 | 0 | 18 | 0 |
| `boundary_error` | `carry_over` | 15 | 15 | 0 | 15 | 0 |
| `boundary_error` | `deleted` | 27 | 27 | 0 | 27 | 0 |
| `boundary_error` | `same_language` | 34 | 34 | 0 | 34 | 0 |
| `boundary_error` | `unresolved` | 55 | 55 | 0 | 55 | 0 |
| `mixed_word_error` | `affix_changed` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `affix_dropped` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `both_wrong` | 8 | 15 | 0 | 15 | 0 |
| `mixed_word_error` | `stem_changed` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `affix_added` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `affix_changed` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `affix_missing` | 8 | 8 | 0 | 8 | 0 |
| `morphology_error` | `ligature_added` | 9 | 9 | 0 | 9 | 0 |
| `morphology_error` | `ligature_dropped` | 10 | 10 | 0 | 10 | 0 |
| `morphology_error` | `reduplication_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `reduplication_dropped` | 2 | 2 | 0 | 2 | 0 |
| `proper_noun_error` | `deleted` | 8 | 8 | 0 | 8 | 0 |
| `proper_noun_error` | `different_word` | 30 | 30 | 0 | 30 | 0 |
| `proper_noun_error` | `near_spelling` | 6 | 6 | 0 | 6 | 0 |
| `hallucination` | `repetition_loop` | 1 | 9 | 0 | 0 | 9 |
| `hallucination` | `run` | 4 | 18 | 0 | 0 | 18 |
| `deleted_speech` | `run` | 243 | 1661 | 0 | 0 | 1661 |
| `enclitic_particle` | `deleted` | 32 | 32 | 0 | 32 | 0 |
| `enclitic_particle` | `inserted` | 5 | 5 | 0 | 5 | 0 |
| `enclitic_particle` | `substituted` | 146 | 146 | 0 | 146 | 0 |
| `spelling_variant` | `spacing` | 14 | 29 | 0 | 29 | 0 |
| `spelling_variant` | `variant-table` | 10 | 10 | 0 | 10 | 0 |
| `other_substitution` | `near_miss` | 157 | 157 | 0 | 157 | 0 |
| `other_substitution` | `unrelated` | 1078 | 1078 | 0 | 1078 | 0 |
| `other_deletion` | `isolated` | 279 | 279 | 0 | 0 | 279 |
| `other_insertion` | `isolated` | 41 | 41 | 0 | 0 | 41 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 127 | 127 | 0 | 127 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 14 | 14 | 0 | 14 | 0 |
| `boundary_error` | `at_boundary` | 149 | 149 | 0 | 149 | 0 |
| `boundary_error` | `short_reference_word` | 108 | 108 | 0 | 108 | 0 |
| `morphology_error` | `at_boundary` | 3 | 3 | 0 | 3 | 0 |
| `morphology_error` | `root_unlisted` | 14 | 14 | 0 | 14 | 0 |
| `hallucination` | `inside_reference_speech` | 5 | 27 | 0 | 0 | 27 |
| `deleted_speech` | `at_boundary` | 68 | 544 | 0 | 0 | 544 |
| `enclitic_particle` | `at_boundary` | 13 | 13 | 0 | 13 | 0 |
| `spelling_variant` | `at_boundary` | 2 | 4 | 0 | 4 | 0 |
| `other_substitution` | `language_unresolved` | 993 | 993 | 0 | 993 | 0 |
| `other_substitution` | `short_reference_word` | 755 | 755 | 0 | 755 | 0 |

## Language labels

**Reference tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| heuristic | 2964 | 642 | 50 | 95 | 299 | 188 | 1299 | 5537 |

Heuristic tokens that are `unknown` or `ambiguous`: 1487 of 5537 (26.9%). Heuristic tokens labelled `tl` or `en`: 3606 (65.1%).

**Hypothesis tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | 1636 | 692 | 20 | 0 | 157 | 90 | 992 | 3587 |

Heuristic tokens that are `unknown` or `ambiguous`: 1082 of 3587 (30.2%). Heuristic tokens labelled `tl` or `en`: 2328 (64.9%).

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
| en | `english-contraction` | 14 |
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
| unknown | `apostrophe-no-match` | 20 |

## Substitutions by language (reference row, hypothesis column)

| reference basis | reference label | tl | en | mix | name | other | ambiguous | unknown |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | tl | 311 | 218 | 4 | 0 | 35 | 19 | 317 |
| heuristic | en | 37 | 48 | 2 | 0 | 14 | 5 | 64 |
| heuristic | mix | 3 | 6 | 0 | 0 | 1 | 0 | 7 |
| heuristic | name | 7 | 7 | 0 | 0 | 1 | 0 | 21 |
| heuristic | other | 35 | 20 | 0 | 0 | 11 | 2 | 27 |
| heuristic | ambiguous | 28 | 15 | 0 | 0 | 3 | 2 | 14 |
| heuristic | unknown | 152 | 123 | 2 | 0 | 32 | 14 | 198 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 904 | 1048 | 65.9% |
| heuristic | en | 642 | 170 | 229 | 62.1% |
| heuristic | mix | 50 | 17 | 16 | 66.0% |
| heuristic | name | 95 | 36 | 31 | 70.5% |
| heuristic | other | 299 | 95 | 132 | 75.9% |
| heuristic | ambiguous | 188 | 62 | 77 | 73.9% |
| heuristic | unknown | 1299 | 521 | 491 | 77.9% |

Inserted words by (heuristic) language: ambiguous 2, en 7, other 1, tl 41, unknown 23.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 276.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 498 | 306 | 61.4% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3108 | 2045 | 65.8% |
| elsewhere, any label | 5039 | 3523 | 69.9% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3510 aligned word pairs in 4 items; **676 (19.3%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 300, '<=2000ms': 183, '<=5000ms': 254, '>5000ms': 239, 'inside': 2534}; largest 30371 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen (this tool uses the same tie-break as eval/langscore.py). The total never changes, but a category of a few dozen words can move by tens of words under another tie-break: do not read a difference of less than about 40 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
