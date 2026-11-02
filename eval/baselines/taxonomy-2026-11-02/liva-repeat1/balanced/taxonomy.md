# Error taxonomy: balanced (repeat 1)

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3830 hypothesis words. Substitutions 1920, deletions 1820, insertions 113; **3853 errors, WER 69.59%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3853 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 160 | 160 | 4.2% | 0 | 160 | 0 |
| `en_to_tl_substitution` | 22 | 22 | 0.6% | 0 | 22 | 0 |
| `boundary_error` | 199 | 199 | 5.2% | 0 | 199 | 0 |
| `mixed_word_error` | 16 | 25 | 0.6% | 0 | 25 | 0 |
| `morphology_error` | 38 | 38 | 1.0% | 0 | 38 | 0 |
| `proper_noun_error` | 42 | 42 | 1.1% | 0 | 42 | 0 |
| `hallucination` | 4 | 72 | 1.9% | 0 | 0 | 72 |
| `deleted_speech` | 226 | 1435 | 37.2% | 0 | 0 | 1435 |
| `enclitic_particle` | 214 | 214 | 5.6% | 0 | 214 | 0 |
| `spelling_variant` | 24 | 39 | 1.0% | 0 | 39 | 0 |
| `other_substitution` | 1264 | 1264 | 32.8% | 0 | 1264 | 0 |
| `other_deletion` | 308 | 308 | 8.0% | 0 | 0 | 308 |
| `other_insertion` | 35 | 35 | 0.9% | 0 | 0 | 35 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 160 | 160 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 22 | 22 |
| `boundary_error` | `anticipation` | 20 | 20 |
| `boundary_error` | `carry_over` | 30 | 30 |
| `boundary_error` | `deleted` | 20 | 20 |
| `boundary_error` | `same_language` | 52 | 52 |
| `boundary_error` | `unresolved` | 77 | 77 |
| `mixed_word_error` | `affix_changed` | 4 | 4 |
| `mixed_word_error` | `both_wrong` | 10 | 19 |
| `mixed_word_error` | `stem_changed` | 1 | 1 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 1 | 1 |
| `morphology_error` | `affix_changed` | 7 | 7 |
| `morphology_error` | `affix_missing` | 10 | 10 |
| `morphology_error` | `ligature_added` | 11 | 11 |
| `morphology_error` | `ligature_dropped` | 5 | 5 |
| `morphology_error` | `reduplication_added` | 1 | 1 |
| `morphology_error` | `reduplication_dropped` | 3 | 3 |
| `proper_noun_error` | `deleted` | 7 | 7 |
| `proper_noun_error` | `different_word` | 30 | 30 |
| `proper_noun_error` | `near_spelling` | 5 | 5 |
| `hallucination` | `repetition_loop` | 1 | 54 |
| `hallucination` | `run` | 3 | 18 |
| `deleted_speech` | `run` | 226 | 1435 |
| `enclitic_particle` | `deleted` | 32 | 32 |
| `enclitic_particle` | `inserted` | 5 | 5 |
| `enclitic_particle` | `substituted` | 177 | 177 |
| `spelling_variant` | `spacing` | 14 | 29 |
| `spelling_variant` | `variant-table` | 10 | 10 |
| `other_substitution` | `near_miss` | 169 | 169 |
| `other_substitution` | `unrelated` | 1095 | 1095 |
| `other_deletion` | `isolated` | 308 | 308 |
| `other_insertion` | `isolated` | 35 | 35 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 125 | 125 |
| `en_to_tl_substitution` | `short_reference_word` | 13 | 13 |
| `boundary_error` | `at_boundary` | 199 | 199 |
| `boundary_error` | `short_reference_word` | 133 | 133 |
| `morphology_error` | `at_boundary` | 2 | 2 |
| `morphology_error` | `root_unlisted` | 14 | 14 |
| `hallucination` | `inside_reference_speech` | 4 | 72 |
| `deleted_speech` | `at_boundary` | 60 | 523 |
| `enclitic_particle` | `at_boundary` | 16 | 16 |
| `spelling_variant` | `at_boundary` | 4 | 6 |
| `other_substitution` | `language_unresolved` | 964 | 964 |
| `other_substitution` | `short_reference_word` | 816 | 816 |

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
| heuristic | 1751 | 759 | 18 | 4 | 176 | 113 | 1009 | 3830 |

Heuristic tokens that are `unknown` or `ambiguous`: 1122 of 3830 (29.3%). Heuristic tokens labelled `tl` or `en`: 2510 (65.5%).

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
| heuristic | tl | 386 | 224 | 0 | 2 | 54 | 31 | 311 |
| heuristic | en | 46 | 54 | 0 | 0 | 11 | 3 | 81 |
| heuristic | mix | 7 | 4 | 2 | 0 | 3 | 0 | 5 |
| heuristic | name | 10 | 4 | 0 | 0 | 1 | 1 | 19 |
| heuristic | other | 31 | 22 | 0 | 1 | 10 | 5 | 23 |
| heuristic | ambiguous | 12 | 15 | 0 | 0 | 1 | 4 | 19 |
| heuristic | unknown | 159 | 109 | 3 | 1 | 25 | 13 | 208 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 1008 | 896 | 64.2% |
| heuristic | en | 685 | 195 | 233 | 62.5% |
| heuristic | mix | 52 | 21 | 12 | 63.5% |
| heuristic | name | 89 | 35 | 30 | 73.0% |
| heuristic | other | 299 | 92 | 127 | 73.2% |
| heuristic | ambiguous | 187 | 51 | 79 | 69.5% |
| heuristic | unknown | 1261 | 518 | 443 | 76.2% |

Inserted words by (heuristic) language: ambiguous 3, en 65, other 4, tl 27, unknown 14.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 348 | 61.2% |
| elsewhere | 4968 | 3392 | 68.3% |

## Timestamp misalignment (overlay on recognised words)

3713 aligned word pairs in 4 items; **638 (17.2%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 381, '<=2000ms': 211, '<=5000ms': 262, '>5000ms': 165, 'inside': 2694}; largest 26268 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
