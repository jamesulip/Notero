# Error taxonomy: best (repeat 1)

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`; alignment tie-break `default`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3957 hypothesis words. Substitutions 1699, deletions 1759, insertions 179; **3637 errors, WER 65.69%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3637 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 67 | 67 | 1.8% | 0 | 67 | 0 |
| `en_to_tl_substitution` | 25 | 25 | 0.7% | 0 | 25 | 0 |
| `boundary_error` | 160 | 160 | 4.4% | 0 | 160 | 0 |
| `mixed_word_error` | 12 | 17 | 0.5% | 0 | 17 | 0 |
| `morphology_error` | 39 | 39 | 1.1% | 0 | 39 | 0 |
| `proper_noun_error` | 34 | 34 | 0.9% | 0 | 34 | 0 |
| `hallucination` | 5 | 115 | 3.2% | 0 | 0 | 115 |
| `deleted_speech` | 220 | 1385 | 38.1% | 0 | 0 | 1385 |
| `enclitic_particle` | 170 | 170 | 4.7% | 0 | 170 | 0 |
| `spelling_variant` | 22 | 38 | 1.0% | 0 | 38 | 0 |
| `other_substitution` | 1234 | 1234 | 33.9% | 0 | 1234 | 0 |
| `other_deletion` | 298 | 298 | 8.2% | 0 | 0 | 298 |
| `other_insertion` | 55 | 55 | 1.5% | 0 | 0 | 55 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 67 | 67 | 0 | 67 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 25 | 25 | 0 | 25 | 0 |
| `boundary_error` | `anticipation` | 13 | 13 | 0 | 13 | 0 |
| `boundary_error` | `carry_over` | 23 | 23 | 0 | 23 | 0 |
| `boundary_error` | `deleted` | 21 | 21 | 0 | 21 | 0 |
| `boundary_error` | `same_language` | 43 | 43 | 0 | 43 | 0 |
| `boundary_error` | `unresolved` | 60 | 60 | 0 | 60 | 0 |
| `mixed_word_error` | `affix_changed` | 4 | 4 | 0 | 4 | 0 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `both_wrong` | 5 | 10 | 0 | 10 | 0 |
| `mixed_word_error` | `stem_changed` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_added` | 11 | 11 | 0 | 11 | 0 |
| `morphology_error` | `affix_changed` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `affix_missing` | 5 | 5 | 0 | 5 | 0 |
| `morphology_error` | `ligature_added` | 7 | 7 | 0 | 7 | 0 |
| `morphology_error` | `ligature_dropped` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `reduplication_added` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `reduplication_dropped` | 4 | 4 | 0 | 4 | 0 |
| `proper_noun_error` | `deleted` | 4 | 4 | 0 | 4 | 0 |
| `proper_noun_error` | `different_word` | 24 | 24 | 0 | 24 | 0 |
| `proper_noun_error` | `near_spelling` | 6 | 6 | 0 | 6 | 0 |
| `hallucination` | `repetition_loop` | 1 | 102 | 0 | 0 | 102 |
| `hallucination` | `run` | 4 | 13 | 0 | 0 | 13 |
| `deleted_speech` | `run` | 220 | 1385 | 0 | 0 | 1385 |
| `enclitic_particle` | `deleted` | 33 | 33 | 0 | 33 | 0 |
| `enclitic_particle` | `inserted` | 9 | 9 | 0 | 9 | 0 |
| `enclitic_particle` | `substituted` | 128 | 128 | 0 | 128 | 0 |
| `spelling_variant` | `spacing` | 13 | 29 | 0 | 29 | 0 |
| `spelling_variant` | `variant-table` | 9 | 9 | 0 | 9 | 0 |
| `other_substitution` | `near_miss` | 191 | 191 | 0 | 191 | 0 |
| `other_substitution` | `unrelated` | 1043 | 1043 | 0 | 1043 | 0 |
| `other_deletion` | `isolated` | 298 | 298 | 0 | 0 | 298 |
| `other_insertion` | `isolated` | 55 | 55 | 0 | 0 | 55 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `outside_reference_speech`: at least 80% of the timed inserted words fall outside every padded reference utterance; `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 55 | 55 | 0 | 55 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 19 | 19 | 0 | 19 | 0 |
| `boundary_error` | `at_boundary` | 160 | 160 | 0 | 160 | 0 |
| `boundary_error` | `short_reference_word` | 111 | 111 | 0 | 111 | 0 |
| `morphology_error` | `at_boundary` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `root_unlisted` | 18 | 18 | 0 | 18 | 0 |
| `hallucination` | `inside_reference_speech` | 4 | 13 | 0 | 0 | 13 |
| `hallucination` | `outside_reference_speech` | 1 | 102 | 0 | 0 | 102 |
| `deleted_speech` | `at_boundary` | 47 | 348 | 0 | 0 | 348 |
| `enclitic_particle` | `at_boundary` | 11 | 11 | 0 | 11 | 0 |
| `spelling_variant` | `at_boundary` | 3 | 8 | 0 | 8 | 0 |
| `other_substitution` | `language_unresolved` | 902 | 902 | 0 | 902 | 0 |
| `other_substitution` | `short_reference_word` | 800 | 800 | 0 | 800 | 0 |

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
| heuristic | 2076 | 569 | 30 | 1 | 152 | 108 | 1021 | 3957 |

Heuristic tokens that are `unknown` or `ambiguous`: 1129 of 3957 (28.5%). Heuristic tokens labelled `tl` or `en`: 2645 (66.8%).

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
| heuristic | tl | 422 | 91 | 5 | 1 | 28 | 22 | 245 |
| heuristic | en | 48 | 44 | 0 | 0 | 10 | 7 | 70 |
| heuristic | mix | 4 | 5 | 1 | 0 | 0 | 0 | 4 |
| heuristic | name | 8 | 3 | 0 | 0 | 2 | 0 | 17 |
| heuristic | other | 42 | 12 | 1 | 0 | 10 | 3 | 26 |
| heuristic | ambiguous | 17 | 9 | 0 | 0 | 2 | 1 | 13 |
| heuristic | unknown | 202 | 52 | 4 | 0 | 21 | 13 | 234 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 814 | 878 | 57.1% |
| heuristic | en | 640 | 179 | 218 | 62.0% |
| heuristic | mix | 50 | 14 | 11 | 50.0% |
| heuristic | name | 95 | 30 | 30 | 63.2% |
| heuristic | other | 299 | 94 | 117 | 70.6% |
| heuristic | ambiguous | 188 | 42 | 73 | 61.2% |
| heuristic | unknown | 1301 | 526 | 432 | 73.6% |

Inserted words by (heuristic) language: ambiguous 3, en 106, mix 1, other 3, tl 42, unknown 24.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 274.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 495 | 282 | 57.0% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3109 | 1807 | 58.1% |
| elsewhere, any label | 5042 | 3176 | 63.0% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3767 aligned word pairs in 4 items; **476 (12.6%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 522, '<=2000ms': 153, '<=5000ms': 159, '>5000ms': 164, 'inside': 2769}; largest 22774 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen. This report used the `default` tie-break (the one of eval/langscore.py, which the older tools use). The total never changes, but a category can move by tens of words under another tie-break (`--tie-break`; 67 words at most in the Liva check): do not read a difference of less than about 70 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
