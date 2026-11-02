# Error taxonomy: best

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3914 hypothesis words. Substitutions 1737, deletions 1739, insertions 116; **3592 errors, WER 64.87%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3592 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 61 | 61 | 1.7% | 0 | 61 | 0 |
| `en_to_tl_substitution` | 23 | 23 | 0.6% | 0 | 23 | 0 |
| `boundary_error` | 191 | 191 | 5.3% | 0 | 191 | 0 |
| `mixed_word_error` | 15 | 21 | 0.6% | 0 | 21 | 0 |
| `morphology_error` | 44 | 44 | 1.2% | 0 | 44 | 0 |
| `proper_noun_error` | 34 | 34 | 0.9% | 0 | 34 | 0 |
| `hallucination` | 4 | 54 | 1.5% | 0 | 0 | 54 |
| `deleted_speech` | 215 | 1359 | 37.8% | 0 | 0 | 1359 |
| `enclitic_particle` | 171 | 171 | 4.8% | 0 | 171 | 0 |
| `spelling_variant` | 23 | 40 | 1.1% | 0 | 40 | 0 |
| `other_substitution` | 1235 | 1235 | 34.4% | 0 | 1235 | 0 |
| `other_deletion` | 307 | 307 | 8.5% | 0 | 0 | 307 |
| `other_insertion` | 52 | 52 | 1.4% | 0 | 0 | 52 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 61 | 61 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 23 | 23 |
| `boundary_error` | `anticipation` | 15 | 15 |
| `boundary_error` | `carry_over` | 29 | 29 |
| `boundary_error` | `deleted` | 24 | 24 |
| `boundary_error` | `same_language` | 51 | 51 |
| `boundary_error` | `unresolved` | 72 | 72 |
| `mixed_word_error` | `affix_changed` | 5 | 5 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 |
| `mixed_word_error` | `both_wrong` | 6 | 12 |
| `mixed_word_error` | `stem_changed` | 2 | 2 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 10 | 10 |
| `morphology_error` | `affix_changed` | 6 | 6 |
| `morphology_error` | `affix_missing` | 6 | 6 |
| `morphology_error` | `ligature_added` | 9 | 9 |
| `morphology_error` | `ligature_dropped` | 7 | 7 |
| `morphology_error` | `reduplication_added` | 3 | 3 |
| `morphology_error` | `reduplication_dropped` | 3 | 3 |
| `proper_noun_error` | `deleted` | 3 | 3 |
| `proper_noun_error` | `different_word` | 25 | 25 |
| `proper_noun_error` | `near_spelling` | 6 | 6 |
| `hallucination` | `repetition_loop` | 1 | 30 |
| `hallucination` | `run` | 3 | 24 |
| `deleted_speech` | `run` | 215 | 1359 |
| `enclitic_particle` | `deleted` | 28 | 28 |
| `enclitic_particle` | `inserted` | 9 | 9 |
| `enclitic_particle` | `substituted` | 134 | 134 |
| `spelling_variant` | `spacing` | 14 | 31 |
| `spelling_variant` | `variant-table` | 9 | 9 |
| `other_substitution` | `near_miss` | 182 | 182 |
| `other_substitution` | `unrelated` | 1053 | 1053 |
| `other_deletion` | `isolated` | 307 | 307 |
| `other_insertion` | `isolated` | 52 | 52 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `outside_reference_speech`: at least 80% of the timed inserted words fall outside every padded reference utterance; `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 46 | 46 |
| `en_to_tl_substitution` | `short_reference_word` | 17 | 17 |
| `boundary_error` | `at_boundary` | 191 | 191 |
| `boundary_error` | `short_reference_word` | 137 | 137 |
| `morphology_error` | `at_boundary` | 2 | 2 |
| `morphology_error` | `root_unlisted` | 18 | 18 |
| `hallucination` | `inside_reference_speech` | 3 | 36 |
| `hallucination` | `outside_reference_speech` | 1 | 18 |
| `deleted_speech` | `at_boundary` | 47 | 385 |
| `enclitic_particle` | `at_boundary` | 14 | 14 |
| `spelling_variant` | `at_boundary` | 5 | 12 |
| `other_substitution` | `language_unresolved` | 911 | 911 |
| `other_substitution` | `short_reference_word` | 797 | 797 |

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
| heuristic | 2097 | 509 | 28 | 0 | 146 | 100 | 1034 | 3914 |

Heuristic tokens that are `unknown` or `ambiguous`: 1134 of 3914 (29.0%). Heuristic tokens labelled `tl` or `en`: 2606 (66.6%).

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
| heuristic | tl | 444 | 87 | 5 | 0 | 29 | 17 | 275 |
| heuristic | en | 53 | 36 | 1 | 0 | 10 | 4 | 78 |
| heuristic | mix | 3 | 5 | 2 | 0 | 0 | 1 | 7 |
| heuristic | name | 6 | 3 | 0 | 0 | 2 | 0 | 20 |
| heuristic | other | 48 | 10 | 0 | 0 | 12 | 2 | 24 |
| heuristic | ambiguous | 13 | 7 | 0 | 0 | 2 | 0 | 17 |
| heuristic | unknown | 197 | 60 | 3 | 0 | 19 | 12 | 223 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 857 | 840 | 57.3% |
| heuristic | en | 685 | 182 | 238 | 61.3% |
| heuristic | mix | 52 | 18 | 13 | 59.6% |
| heuristic | name | 89 | 31 | 24 | 61.8% |
| heuristic | other | 299 | 96 | 123 | 73.2% |
| heuristic | ambiguous | 187 | 39 | 77 | 62.0% |
| heuristic | unknown | 1261 | 514 | 424 | 74.4% |

Inserted words by (heuristic) language: ambiguous 4, en 32, mix 1, other 3, tl 51, unknown 25.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 326 | 57.3% |
| elsewhere | 4968 | 3150 | 63.4% |

## Timestamp misalignment (overlay on recognised words)

3788 aligned word pairs in 4 items; **488 (12.9%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 494, '<=2000ms': 152, '<=5000ms': 165, '>5000ms': 171, 'inside': 2806}; largest 24790 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
