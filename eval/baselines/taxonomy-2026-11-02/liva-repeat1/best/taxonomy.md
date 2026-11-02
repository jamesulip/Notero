# Error taxonomy: best (repeat 1)

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3957 hypothesis words. Substitutions 1699, deletions 1759, insertions 179; **3637 errors, WER 65.69%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3637 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 67 | 67 | 1.8% | 0 | 67 | 0 |
| `en_to_tl_substitution` | 25 | 25 | 0.7% | 0 | 25 | 0 |
| `boundary_error` | 191 | 191 | 5.3% | 0 | 191 | 0 |
| `mixed_word_error` | 12 | 17 | 0.5% | 0 | 17 | 0 |
| `morphology_error` | 39 | 39 | 1.1% | 0 | 39 | 0 |
| `proper_noun_error` | 33 | 33 | 0.9% | 0 | 33 | 0 |
| `hallucination` | 5 | 115 | 3.2% | 0 | 0 | 115 |
| `deleted_speech` | 220 | 1385 | 38.1% | 0 | 0 | 1385 |
| `enclitic_particle` | 170 | 170 | 4.7% | 0 | 170 | 0 |
| `spelling_variant` | 22 | 38 | 1.0% | 0 | 38 | 0 |
| `other_substitution` | 1206 | 1206 | 33.2% | 0 | 1206 | 0 |
| `other_deletion` | 296 | 296 | 8.1% | 0 | 0 | 296 |
| `other_insertion` | 55 | 55 | 1.5% | 0 | 0 | 55 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 67 | 67 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 25 | 25 |
| `boundary_error` | `anticipation` | 13 | 13 |
| `boundary_error` | `carry_over` | 28 | 28 |
| `boundary_error` | `deleted` | 24 | 24 |
| `boundary_error` | `same_language` | 55 | 55 |
| `boundary_error` | `unresolved` | 71 | 71 |
| `mixed_word_error` | `affix_changed` | 4 | 4 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 |
| `mixed_word_error` | `both_wrong` | 5 | 10 |
| `mixed_word_error` | `stem_changed` | 1 | 1 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 11 | 11 |
| `morphology_error` | `affix_changed` | 4 | 4 |
| `morphology_error` | `affix_missing` | 5 | 5 |
| `morphology_error` | `ligature_added` | 7 | 7 |
| `morphology_error` | `ligature_dropped` | 6 | 6 |
| `morphology_error` | `reduplication_added` | 2 | 2 |
| `morphology_error` | `reduplication_dropped` | 4 | 4 |
| `proper_noun_error` | `deleted` | 3 | 3 |
| `proper_noun_error` | `different_word` | 24 | 24 |
| `proper_noun_error` | `near_spelling` | 6 | 6 |
| `hallucination` | `repetition_loop` | 1 | 102 |
| `hallucination` | `run` | 4 | 13 |
| `deleted_speech` | `run` | 220 | 1385 |
| `enclitic_particle` | `deleted` | 33 | 33 |
| `enclitic_particle` | `inserted` | 9 | 9 |
| `enclitic_particle` | `substituted` | 128 | 128 |
| `spelling_variant` | `spacing` | 13 | 29 |
| `spelling_variant` | `variant-table` | 9 | 9 |
| `other_substitution` | `near_miss` | 187 | 187 |
| `other_substitution` | `unrelated` | 1019 | 1019 |
| `other_deletion` | `isolated` | 296 | 296 |
| `other_insertion` | `isolated` | 55 | 55 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `outside_reference_speech`: at least 80% of the timed inserted words fall outside every padded reference utterance; `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 55 | 55 |
| `en_to_tl_substitution` | `short_reference_word` | 19 | 19 |
| `boundary_error` | `at_boundary` | 191 | 191 |
| `boundary_error` | `short_reference_word` | 134 | 134 |
| `morphology_error` | `at_boundary` | 4 | 4 |
| `morphology_error` | `root_unlisted` | 18 | 18 |
| `hallucination` | `inside_reference_speech` | 4 | 13 |
| `hallucination` | `outside_reference_speech` | 1 | 102 |
| `deleted_speech` | `at_boundary` | 55 | 385 |
| `enclitic_particle` | `at_boundary` | 13 | 13 |
| `spelling_variant` | `at_boundary` | 3 | 8 |
| `other_substitution` | `language_unresolved` | 883 | 883 |
| `other_substitution` | `short_reference_word` | 780 | 780 |

## Language labels

**Reference tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| heuristic | 2964 | 685 | 52 | 89 | 299 | 187 | 1261 | 5537 |

Heuristic tokens that are `unknown` or `ambiguous`: 1448 of 5537 (26.2%). Heuristic tokens labelled `tl` or `en`: 3649 (65.9%).

**Hypothesis tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | 2076 | 588 | 30 | 1 | 152 | 107 | 1003 | 3957 |

Heuristic tokens that are `unknown` or `ambiguous`: 1110 of 3957 (28.1%). Heuristic tokens labelled `tl` or `en`: 2664 (67.3%).

Heuristic reference labels by rule:

| label | rule | tokens |
| --- | --- | ---: |
| tl | `lexicon-tl` | 2747 |
| tl | `tl-affix-analysis` | 71 |
| tl | `tl-ligature` | 67 |
| tl | `context` | 44 |
| tl | `affix+tagalog-stem` | 30 |
| tl | `tagalog-clitic-y` | 5 |
| en | `lexicon-en` | 605 |
| en | `en-inflection` | 47 |
| en | `english-contraction` | 27 |
| en | `context` | 6 |
| mix | `affix+english-stem` | 52 |
| name | `capitalised-mid-sentence` | 88 |
| name | `names-lexicon` | 1 |
| other | `filler-or-laughter` | 233 |
| other | `digits` | 37 |
| other | `acronym` | 23 |
| other | `alphanumeric` | 6 |
| ambiguous | `homograph-list` | 187 |
| unknown | `no-match` | 1106 |
| unknown | `affix+unlisted-stem` | 148 |
| unknown | `apostrophe-no-match` | 7 |

## Substitutions by language (reference row, hypothesis column)

| reference basis | reference label | tl | en | mix | name | other | ambiguous | unknown |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | tl | 422 | 91 | 5 | 1 | 28 | 22 | 245 |
| heuristic | en | 53 | 47 | 1 | 0 | 10 | 8 | 76 |
| heuristic | mix | 4 | 5 | 1 | 0 | 0 | 0 | 4 |
| heuristic | name | 8 | 3 | 0 | 0 | 2 | 0 | 17 |
| heuristic | other | 42 | 12 | 1 | 0 | 10 | 3 | 26 |
| heuristic | ambiguous | 17 | 9 | 0 | 0 | 2 | 1 | 13 |
| heuristic | unknown | 197 | 51 | 3 | 0 | 21 | 12 | 226 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 814 | 878 | 57.1% |
| heuristic | en | 685 | 195 | 230 | 62.0% |
| heuristic | mix | 52 | 14 | 13 | 51.9% |
| heuristic | name | 89 | 30 | 27 | 64.0% |
| heuristic | other | 299 | 94 | 117 | 70.6% |
| heuristic | ambiguous | 187 | 42 | 73 | 61.5% |
| heuristic | unknown | 1261 | 510 | 421 | 73.8% |

Inserted words by (heuristic) language: ambiguous 3, en 106, mix 1, other 3, tl 42, unknown 24.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 329 | 57.8% |
| elsewhere | 4968 | 3129 | 63.0% |

## Timestamp misalignment (overlay on recognised words)

3767 aligned word pairs in 4 items; **476 (12.6%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 522, '<=2000ms': 153, '<=5000ms': 159, '>5000ms': 164, 'inside': 2769}; largest 22774 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
