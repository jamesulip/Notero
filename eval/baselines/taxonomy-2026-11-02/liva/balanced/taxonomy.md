# Error taxonomy: balanced

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3782 hypothesis words. Substitutions 1843, deletions 1848, insertions 93; **3784 errors, WER 68.34%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3784 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 159 | 159 | 4.2% | 0 | 159 | 0 |
| `en_to_tl_substitution` | 17 | 17 | 0.4% | 0 | 17 | 0 |
| `boundary_error` | 183 | 183 | 4.8% | 0 | 183 | 0 |
| `mixed_word_error` | 13 | 18 | 0.5% | 0 | 18 | 0 |
| `morphology_error` | 37 | 37 | 1.0% | 0 | 37 | 0 |
| `proper_noun_error` | 40 | 40 | 1.1% | 0 | 40 | 0 |
| `hallucination` | 8 | 40 | 1.1% | 0 | 0 | 40 |
| `deleted_speech` | 230 | 1467 | 38.8% | 0 | 0 | 1467 |
| `enclitic_particle` | 211 | 211 | 5.6% | 0 | 211 | 0 |
| `spelling_variant` | 17 | 30 | 0.8% | 0 | 30 | 0 |
| `other_substitution` | 1233 | 1233 | 32.6% | 0 | 1233 | 0 |
| `other_deletion` | 304 | 304 | 8.0% | 0 | 0 | 304 |
| `other_insertion` | 45 | 45 | 1.2% | 0 | 0 | 45 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 159 | 159 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 17 | 17 |
| `boundary_error` | `anticipation` | 22 | 22 |
| `boundary_error` | `carry_over` | 22 | 22 |
| `boundary_error` | `deleted` | 23 | 23 |
| `boundary_error` | `same_language` | 45 | 45 |
| `boundary_error` | `unresolved` | 71 | 71 |
| `mixed_word_error` | `affix_changed` | 4 | 4 |
| `mixed_word_error` | `both_wrong` | 6 | 11 |
| `mixed_word_error` | `stem_changed` | 2 | 2 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 4 | 4 |
| `morphology_error` | `affix_changed` | 6 | 6 |
| `morphology_error` | `affix_missing` | 8 | 8 |
| `morphology_error` | `ligature_added` | 9 | 9 |
| `morphology_error` | `ligature_dropped` | 6 | 6 |
| `morphology_error` | `reduplication_added` | 1 | 1 |
| `morphology_error` | `reduplication_dropped` | 3 | 3 |
| `proper_noun_error` | `deleted` | 8 | 8 |
| `proper_noun_error` | `different_word` | 31 | 31 |
| `proper_noun_error` | `near_spelling` | 1 | 1 |
| `hallucination` | `repetition_loop` | 2 | 12 |
| `hallucination` | `run` | 6 | 28 |
| `deleted_speech` | `run` | 230 | 1467 |
| `enclitic_particle` | `deleted` | 31 | 31 |
| `enclitic_particle` | `inserted` | 7 | 7 |
| `enclitic_particle` | `substituted` | 173 | 173 |
| `spelling_variant` | `spacing` | 12 | 25 |
| `spelling_variant` | `variant-table` | 5 | 5 |
| `other_substitution` | `near_miss` | 165 | 165 |
| `other_substitution` | `unrelated` | 1068 | 1068 |
| `other_deletion` | `isolated` | 304 | 304 |
| `other_insertion` | `isolated` | 45 | 45 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 123 | 123 |
| `en_to_tl_substitution` | `short_reference_word` | 11 | 11 |
| `boundary_error` | `at_boundary` | 183 | 183 |
| `boundary_error` | `short_reference_word` | 121 | 121 |
| `morphology_error` | `at_boundary` | 3 | 3 |
| `morphology_error` | `root_unlisted` | 11 | 11 |
| `hallucination` | `inside_reference_speech` | 8 | 40 |
| `deleted_speech` | `at_boundary` | 59 | 484 |
| `enclitic_particle` | `at_boundary` | 15 | 15 |
| `spelling_variant` | `at_boundary` | 3 | 5 |
| `other_substitution` | `language_unresolved` | 965 | 965 |
| `other_substitution` | `short_reference_word` | 792 | 792 |

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
| heuristic | 1790 | 684 | 24 | 4 | 169 | 109 | 1002 | 3782 |

Heuristic tokens that are `unknown` or `ambiguous`: 1111 of 3782 (29.4%). Heuristic tokens labelled `tl` or `en`: 2474 (65.4%).

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
| heuristic | tl | 364 | 212 | 3 | 2 | 50 | 29 | 299 |
| heuristic | en | 41 | 44 | 1 | 0 | 6 | 5 | 78 |
| heuristic | mix | 5 | 1 | 3 | 0 | 4 | 0 | 3 |
| heuristic | name | 11 | 3 | 0 | 0 | 1 | 1 | 16 |
| heuristic | other | 37 | 19 | 0 | 1 | 8 | 6 | 20 |
| heuristic | ambiguous | 21 | 5 | 0 | 0 | 2 | 5 | 19 |
| heuristic | unknown | 164 | 105 | 3 | 1 | 22 | 10 | 213 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 959 | 905 | 62.9% |
| heuristic | en | 685 | 175 | 243 | 61.0% |
| heuristic | mix | 52 | 16 | 15 | 59.6% |
| heuristic | name | 89 | 32 | 31 | 70.8% |
| heuristic | other | 299 | 91 | 126 | 72.6% |
| heuristic | ambiguous | 187 | 52 | 86 | 73.8% |
| heuristic | unknown | 1261 | 518 | 442 | 76.1% |

Inserted words by (heuristic) language: ambiguous 5, en 23, other 7, tl 35, unknown 23.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 330 | 58.0% |
| elsewhere | 4968 | 3361 | 67.7% |

## Timestamp misalignment (overlay on recognised words)

3683 aligned word pairs in 4 items; **630 (17.1%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 360, '<=2000ms': 202, '<=5000ms': 214, '>5000ms': 214, 'inside': 2693}; largest 26268 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
