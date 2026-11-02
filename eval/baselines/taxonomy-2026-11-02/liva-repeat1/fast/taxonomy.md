# Error taxonomy: fast (repeat 1)

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 942, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3506 hypothesis words. Substitutions 1731, deletions 2060, insertions 29; **3820 errors, WER 68.99%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3820 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 91 | 91 | 2.4% | 0 | 91 | 0 |
| `en_to_tl_substitution` | 33 | 33 | 0.9% | 0 | 33 | 0 |
| `boundary_error` | 186 | 186 | 4.9% | 0 | 186 | 0 |
| `mixed_word_error` | 10 | 14 | 0.4% | 0 | 14 | 0 |
| `morphology_error` | 42 | 42 | 1.1% | 0 | 42 | 0 |
| `proper_noun_error` | 38 | 38 | 1.0% | 0 | 38 | 0 |
| `hallucination` | 1 | 3 | 0.1% | 0 | 0 | 3 |
| `deleted_speech` | 247 | 1670 | 43.7% | 0 | 0 | 1670 |
| `enclitic_particle` | 169 | 169 | 4.4% | 0 | 169 | 0 |
| `spelling_variant` | 22 | 37 | 1.0% | 0 | 37 | 0 |
| `other_substitution` | 1206 | 1206 | 31.6% | 0 | 1206 | 0 |
| `other_deletion` | 309 | 309 | 8.1% | 0 | 0 | 309 |
| `other_insertion` | 22 | 22 | 0.6% | 0 | 0 | 22 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 91 | 91 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 33 | 33 |
| `boundary_error` | `anticipation` | 17 | 17 |
| `boundary_error` | `carry_over` | 22 | 22 |
| `boundary_error` | `deleted` | 27 | 27 |
| `boundary_error` | `same_language` | 48 | 48 |
| `boundary_error` | `unresolved` | 72 | 72 |
| `mixed_word_error` | `affix_changed` | 2 | 2 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 |
| `mixed_word_error` | `both_wrong` | 5 | 9 |
| `mixed_word_error` | `stem_changed` | 1 | 1 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 |
| `morphology_error` | `affix_added` | 10 | 10 |
| `morphology_error` | `affix_changed` | 4 | 4 |
| `morphology_error` | `affix_missing` | 11 | 11 |
| `morphology_error` | `ligature_added` | 4 | 4 |
| `morphology_error` | `ligature_dropped` | 8 | 8 |
| `morphology_error` | `reduplication_added` | 2 | 2 |
| `morphology_error` | `reduplication_dropped` | 3 | 3 |
| `proper_noun_error` | `deleted` | 7 | 7 |
| `proper_noun_error` | `different_word` | 30 | 30 |
| `proper_noun_error` | `near_spelling` | 1 | 1 |
| `hallucination` | `run` | 1 | 3 |
| `deleted_speech` | `run` | 247 | 1670 |
| `enclitic_particle` | `deleted` | 29 | 29 |
| `enclitic_particle` | `inserted` | 3 | 3 |
| `enclitic_particle` | `substituted` | 137 | 137 |
| `spelling_variant` | `spacing` | 14 | 29 |
| `spelling_variant` | `variant-table` | 8 | 8 |
| `other_substitution` | `near_miss` | 174 | 174 |
| `other_substitution` | `unrelated` | 1032 | 1032 |
| `other_deletion` | `isolated` | 309 | 309 |
| `other_insertion` | `isolated` | 22 | 22 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: the inserted words fall inside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words |
| --- | --- | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 69 | 69 |
| `en_to_tl_substitution` | `short_reference_word` | 24 | 24 |
| `boundary_error` | `at_boundary` | 186 | 186 |
| `boundary_error` | `short_reference_word` | 127 | 127 |
| `morphology_error` | `at_boundary` | 3 | 3 |
| `morphology_error` | `root_unlisted` | 16 | 16 |
| `hallucination` | `inside_reference_speech` | 1 | 3 |
| `deleted_speech` | `at_boundary` | 64 | 522 |
| `enclitic_particle` | `at_boundary` | 11 | 11 |
| `spelling_variant` | `at_boundary` | 3 | 5 |
| `other_substitution` | `language_unresolved` | 906 | 906 |
| `other_substitution` | `short_reference_word` | 766 | 766 |

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
| heuristic | 1812 | 483 | 22 | 1 | 124 | 93 | 971 | 3506 |

Heuristic tokens that are `unknown` or `ambiguous`: 1064 of 3506 (30.3%). Heuristic tokens labelled `tl` or `en`: 2295 (65.5%).

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
| heuristic | tl | 414 | 112 | 4 | 1 | 40 | 18 | 286 |
| heuristic | en | 63 | 25 | 1 | 0 | 6 | 3 | 85 |
| heuristic | mix | 4 | 1 | 0 | 0 | 1 | 0 | 4 |
| heuristic | name | 13 | 2 | 0 | 0 | 0 | 1 | 15 |
| heuristic | other | 39 | 12 | 0 | 0 | 8 | 5 | 29 |
| heuristic | ambiguous | 28 | 5 | 0 | 0 | 2 | 3 | 14 |
| heuristic | unknown | 188 | 63 | 4 | 0 | 12 | 11 | 209 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 875 | 1057 | 65.2% |
| heuristic | en | 685 | 183 | 247 | 62.8% |
| heuristic | mix | 52 | 10 | 22 | 61.5% |
| heuristic | name | 89 | 31 | 31 | 69.7% |
| heuristic | other | 299 | 93 | 139 | 77.6% |
| heuristic | ambiguous | 187 | 52 | 83 | 72.2% |
| heuristic | unknown | 1261 | 487 | 481 | 76.8% |

Inserted words by (heuristic) language: ambiguous 1, en 2, other 1, tl 20, unknown 5.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 318.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 569 | 343 | 60.3% |
| elsewhere | 4968 | 3448 | 69.4% |

## Timestamp misalignment (overlay on recognised words)

3475 aligned word pairs in 4 items; **589 (16.9%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 355, '<=2000ms': 174, '<=5000ms': 223, '>5000ms': 192, 'inside': 2531}; largest 24790 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
