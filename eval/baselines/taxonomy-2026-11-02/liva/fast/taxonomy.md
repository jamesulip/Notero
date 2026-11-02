# Error taxonomy: fast

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3587 hypothesis words. Substitutions 1853, deletions 2000, insertions 50; **3903 errors, WER 70.49%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3903 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 162 | 162 | 4.2% | 0 | 162 | 0 |
| `en_to_tl_substitution` | 29 | 29 | 0.7% | 0 | 29 | 0 |
| `boundary_error` | 194 | 194 | 5.0% | 0 | 194 | 0 |
| `mixed_word_error` | 12 | 18 | 0.5% | 0 | 18 | 0 |
| `morphology_error` | 33 | 33 | 0.8% | 0 | 33 | 0 |
| `proper_noun_error` | 37 | 37 | 0.9% | 0 | 37 | 0 |
| `hallucination` | 3 | 17 | 0.4% | 0 | 0 | 17 |
| `deleted_speech` | 244 | 1654 | 42.4% | 0 | 0 | 1654 |
| `enclitic_particle` | 201 | 201 | 5.1% | 0 | 201 | 0 |
| `spelling_variant` | 17 | 30 | 0.8% | 0 | 30 | 0 |
| `other_substitution` | 1226 | 1226 | 31.4% | 0 | 1226 | 0 |
| `other_deletion` | 272 | 272 | 7.0% | 0 | 0 | 272 |
| `other_insertion` | 30 | 30 | 0.8% | 0 | 0 | 30 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 162 | 162 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 29 | 29 |
| `boundary_error` | `anticipation` | 26 | 26 |
| `boundary_error` | `carry_over` | 27 | 27 |
| `boundary_error` | `deleted` | 18 | 18 |
| `boundary_error` | `same_language` | 54 | 54 |
| `boundary_error` | `unresolved` | 69 | 69 |
| `mixed_word_error` | `affix_changed` | 2 | 2 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 |
| `mixed_word_error` | `both_wrong` | 7 | 13 |
| `mixed_word_error` | `stem_changed` | 1 | 1 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 3 | 3 |
| `morphology_error` | `affix_changed` | 7 | 7 |
| `morphology_error` | `affix_missing` | 8 | 8 |
| `morphology_error` | `ligature_added` | 4 | 4 |
| `morphology_error` | `ligature_dropped` | 7 | 7 |
| `morphology_error` | `reduplication_added` | 2 | 2 |
| `morphology_error` | `reduplication_dropped` | 2 | 2 |
| `proper_noun_error` | `deleted` | 7 | 7 |
| `proper_noun_error` | `different_word` | 29 | 29 |
| `proper_noun_error` | `near_spelling` | 1 | 1 |
| `hallucination` | `repetition_loop` | 1 | 8 |
| `hallucination` | `run` | 2 | 9 |
| `deleted_speech` | `run` | 244 | 1654 |
| `enclitic_particle` | `deleted` | 33 | 33 |
| `enclitic_particle` | `inserted` | 2 | 2 |
| `enclitic_particle` | `substituted` | 166 | 166 |
| `spelling_variant` | `spacing` | 12 | 25 |
| `spelling_variant` | `variant-table` | 5 | 5 |
| `other_substitution` | `near_miss` | 159 | 159 |
| `other_substitution` | `unrelated` | 1067 | 1067 |
| `other_deletion` | `isolated` | 272 | 272 |
| `other_insertion` | `isolated` | 30 | 30 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 131 | 131 |
| `en_to_tl_substitution` | `short_reference_word` | 21 | 21 |
| `boundary_error` | `at_boundary` | 194 | 194 |
| `boundary_error` | `short_reference_word` | 140 | 140 |
| `morphology_error` | `at_boundary` | 2 | 2 |
| `morphology_error` | `root_unlisted` | 16 | 16 |
| `hallucination` | `inside_reference_speech` | 3 | 17 |
| `deleted_speech` | `at_boundary` | 68 | 508 |
| `enclitic_particle` | `at_boundary` | 17 | 17 |
| `spelling_variant` | `at_boundary` | 3 | 5 |
| `other_substitution` | `language_unresolved` | 968 | 968 |
| `other_substitution` | `short_reference_word` | 774 | 774 |

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
| heuristic | 1636 | 711 | 20 | 0 | 157 | 90 | 973 | 3587 |

Heuristic tokens that are `unknown` or `ambiguous`: 1063 of 3587 (29.6%). Heuristic tokens labelled `tl` or `en`: 2347 (65.4%).

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
| heuristic | tl | 335 | 226 | 3 | 0 | 53 | 19 | 302 |
| heuristic | en | 56 | 50 | 1 | 0 | 13 | 2 | 80 |
| heuristic | mix | 4 | 5 | 0 | 0 | 1 | 0 | 4 |
| heuristic | name | 8 | 7 | 0 | 0 | 0 | 1 | 14 |
| heuristic | other | 28 | 19 | 0 | 0 | 11 | 3 | 31 |
| heuristic | ambiguous | 15 | 15 | 0 | 0 | 1 | 3 | 19 |
| heuristic | unknown | 157 | 119 | 4 | 0 | 22 | 14 | 208 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 938 | 1024 | 66.2% |
| heuristic | en | 685 | 202 | 226 | 62.5% |
| heuristic | mix | 52 | 14 | 22 | 69.2% |
| heuristic | name | 89 | 30 | 34 | 71.9% |
| heuristic | other | 299 | 92 | 139 | 77.3% |
| heuristic | ambiguous | 187 | 53 | 86 | 74.3% |
| heuristic | unknown | 1261 | 524 | 469 | 78.7% |

Inserted words by (heuristic) language: ambiguous 3, en 9, other 1, tl 21, unknown 16.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 353 | 62.0% |
| elsewhere | 4968 | 3500 | 70.5% |

## Timestamp misalignment (overlay on recognised words)

3534 aligned word pairs in 4 items; **739 (20.9%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 364, '<=2000ms': 181, '<=5000ms': 261, '>5000ms': 297, 'inside': 2431}; largest 25005 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
