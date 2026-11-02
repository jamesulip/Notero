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

5537 reference words, 3587 hypothesis words. Substitutions 1853, deletions 2000, insertions 50; **3903 errors, WER 70.49%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3903 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 165 | 165 | 4.2% | 0 | 165 | 0 |
| `en_to_tl_substitution` | 29 | 29 | 0.7% | 0 | 29 | 0 |
| `boundary_error` | 167 | 167 | 4.3% | 0 | 167 | 0 |
| `mixed_word_error` | 12 | 18 | 0.5% | 0 | 18 | 0 |
| `morphology_error` | 33 | 33 | 0.8% | 0 | 33 | 0 |
| `proper_noun_error` | 39 | 39 | 1.0% | 0 | 39 | 0 |
| `hallucination` | 3 | 17 | 0.4% | 0 | 0 | 17 |
| `deleted_speech` | 244 | 1654 | 42.4% | 0 | 0 | 1654 |
| `enclitic_particle` | 201 | 201 | 5.1% | 0 | 201 | 0 |
| `spelling_variant` | 17 | 30 | 0.8% | 0 | 30 | 0 |
| `other_substitution` | 1248 | 1248 | 32.0% | 0 | 1248 | 0 |
| `other_deletion` | 272 | 272 | 7.0% | 0 | 0 | 272 |
| `other_insertion` | 30 | 30 | 0.8% | 0 | 0 | 30 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 165 | 165 | 0 | 165 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 29 | 29 | 0 | 29 | 0 |
| `boundary_error` | `anticipation` | 24 | 24 | 0 | 24 | 0 |
| `boundary_error` | `carry_over` | 22 | 22 | 0 | 22 | 0 |
| `boundary_error` | `deleted` | 17 | 17 | 0 | 17 | 0 |
| `boundary_error` | `same_language` | 44 | 44 | 0 | 44 | 0 |
| `boundary_error` | `unresolved` | 60 | 60 | 0 | 60 | 0 |
| `mixed_word_error` | `affix_changed` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `both_wrong` | 7 | 13 | 0 | 13 | 0 |
| `mixed_word_error` | `stem_changed` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_added` | 3 | 3 | 0 | 3 | 0 |
| `morphology_error` | `affix_changed` | 7 | 7 | 0 | 7 | 0 |
| `morphology_error` | `affix_missing` | 8 | 8 | 0 | 8 | 0 |
| `morphology_error` | `ligature_added` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `ligature_dropped` | 7 | 7 | 0 | 7 | 0 |
| `morphology_error` | `reduplication_added` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `reduplication_dropped` | 2 | 2 | 0 | 2 | 0 |
| `proper_noun_error` | `deleted` | 8 | 8 | 0 | 8 | 0 |
| `proper_noun_error` | `different_word` | 30 | 30 | 0 | 30 | 0 |
| `proper_noun_error` | `near_spelling` | 1 | 1 | 0 | 1 | 0 |
| `hallucination` | `repetition_loop` | 1 | 8 | 0 | 0 | 8 |
| `hallucination` | `run` | 2 | 9 | 0 | 0 | 9 |
| `deleted_speech` | `run` | 244 | 1654 | 0 | 0 | 1654 |
| `enclitic_particle` | `deleted` | 33 | 33 | 0 | 33 | 0 |
| `enclitic_particle` | `inserted` | 2 | 2 | 0 | 2 | 0 |
| `enclitic_particle` | `substituted` | 166 | 166 | 0 | 166 | 0 |
| `spelling_variant` | `spacing` | 12 | 25 | 0 | 25 | 0 |
| `spelling_variant` | `variant-table` | 5 | 5 | 0 | 5 | 0 |
| `other_substitution` | `near_miss` | 162 | 162 | 0 | 162 | 0 |
| `other_substitution` | `unrelated` | 1086 | 1086 | 0 | 1086 | 0 |
| `other_deletion` | `isolated` | 272 | 272 | 0 | 0 | 272 |
| `other_insertion` | `isolated` | 30 | 30 | 0 | 0 | 30 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 131 | 131 | 0 | 131 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 21 | 21 | 0 | 21 | 0 |
| `boundary_error` | `at_boundary` | 167 | 167 | 0 | 167 | 0 |
| `boundary_error` | `short_reference_word` | 123 | 123 | 0 | 123 | 0 |
| `morphology_error` | `at_boundary` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `root_unlisted` | 16 | 16 | 0 | 16 | 0 |
| `hallucination` | `inside_reference_speech` | 3 | 17 | 0 | 0 | 17 |
| `deleted_speech` | `at_boundary` | 61 | 461 | 0 | 0 | 461 |
| `enclitic_particle` | `at_boundary` | 16 | 16 | 0 | 16 | 0 |
| `spelling_variant` | `at_boundary` | 2 | 4 | 0 | 4 | 0 |
| `other_substitution` | `language_unresolved` | 984 | 984 | 0 | 984 | 0 |
| `other_substitution` | `short_reference_word` | 790 | 790 | 0 | 790 | 0 |

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
| heuristic | tl | 335 | 224 | 3 | 0 | 53 | 19 | 304 |
| heuristic | en | 53 | 46 | 1 | 0 | 13 | 1 | 70 |
| heuristic | mix | 4 | 5 | 0 | 0 | 1 | 0 | 4 |
| heuristic | name | 8 | 7 | 0 | 0 | 0 | 1 | 15 |
| heuristic | other | 28 | 19 | 0 | 0 | 11 | 3 | 31 |
| heuristic | ambiguous | 15 | 15 | 0 | 0 | 1 | 3 | 19 |
| heuristic | unknown | 160 | 121 | 4 | 0 | 22 | 15 | 219 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 938 | 1024 | 66.2% |
| heuristic | en | 642 | 184 | 216 | 62.3% |
| heuristic | mix | 50 | 14 | 20 | 68.0% |
| heuristic | name | 95 | 31 | 36 | 70.5% |
| heuristic | other | 299 | 92 | 139 | 77.3% |
| heuristic | ambiguous | 188 | 53 | 87 | 74.5% |
| heuristic | unknown | 1299 | 541 | 478 | 78.4% |

Inserted words by (heuristic) language: ambiguous 3, en 9, other 1, tl 21, unknown 16.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 276.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 498 | 310 | 62.2% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3108 | 2052 | 66.0% |
| elsewhere, any label | 5039 | 3543 | 70.3% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3534 aligned word pairs in 4 items; **739 (20.9%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 364, '<=2000ms': 181, '<=5000ms': 261, '>5000ms': 297, 'inside': 2431}; largest 25005 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen (this tool uses the same tie-break as eval/langscore.py). The total never changes, but a category of a few dozen words can move by tens of words under another tie-break: do not read a difference of less than about 40 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
