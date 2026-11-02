# Error taxonomy: fast (repeat 1)

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`; alignment tie-break `default`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3506 hypothesis words. Substitutions 1731, deletions 2060, insertions 29; **3820 errors, WER 68.99%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3820 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 92 | 92 | 2.4% | 0 | 92 | 0 |
| `en_to_tl_substitution` | 32 | 32 | 0.8% | 0 | 32 | 0 |
| `boundary_error` | 152 | 152 | 4.0% | 0 | 152 | 0 |
| `mixed_word_error` | 10 | 14 | 0.4% | 0 | 14 | 0 |
| `morphology_error` | 42 | 42 | 1.1% | 0 | 42 | 0 |
| `proper_noun_error` | 40 | 40 | 1.0% | 0 | 40 | 0 |
| `hallucination` | 1 | 3 | 0.1% | 0 | 0 | 3 |
| `deleted_speech` | 247 | 1670 | 43.7% | 0 | 0 | 1670 |
| `enclitic_particle` | 169 | 169 | 4.4% | 0 | 169 | 0 |
| `spelling_variant` | 22 | 37 | 1.0% | 0 | 37 | 0 |
| `other_substitution` | 1238 | 1238 | 32.4% | 0 | 1238 | 0 |
| `other_deletion` | 309 | 309 | 8.1% | 0 | 0 | 309 |
| `other_insertion` | 22 | 22 | 0.6% | 0 | 0 | 22 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 92 | 92 | 0 | 92 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 32 | 32 | 0 | 32 | 0 |
| `boundary_error` | `anticipation` | 13 | 13 | 0 | 13 | 0 |
| `boundary_error` | `carry_over` | 18 | 18 | 0 | 18 | 0 |
| `boundary_error` | `deleted` | 26 | 26 | 0 | 26 | 0 |
| `boundary_error` | `same_language` | 37 | 37 | 0 | 37 | 0 |
| `boundary_error` | `unresolved` | 58 | 58 | 0 | 58 | 0 |
| `mixed_word_error` | `affix_changed` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `affix_dropped` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `both_wrong` | 5 | 9 | 0 | 9 | 0 |
| `mixed_word_error` | `stem_changed` | 1 | 1 | 0 | 1 | 0 |
| `mixed_word_error` | `stem_dropped` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_added` | 10 | 10 | 0 | 10 | 0 |
| `morphology_error` | `affix_changed` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `affix_missing` | 11 | 11 | 0 | 11 | 0 |
| `morphology_error` | `ligature_added` | 4 | 4 | 0 | 4 | 0 |
| `morphology_error` | `ligature_dropped` | 8 | 8 | 0 | 8 | 0 |
| `morphology_error` | `reduplication_added` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `reduplication_dropped` | 3 | 3 | 0 | 3 | 0 |
| `proper_noun_error` | `deleted` | 8 | 8 | 0 | 8 | 0 |
| `proper_noun_error` | `different_word` | 31 | 31 | 0 | 31 | 0 |
| `proper_noun_error` | `near_spelling` | 1 | 1 | 0 | 1 | 0 |
| `hallucination` | `run` | 1 | 3 | 0 | 0 | 3 |
| `deleted_speech` | `run` | 247 | 1670 | 0 | 0 | 1670 |
| `enclitic_particle` | `deleted` | 29 | 29 | 0 | 29 | 0 |
| `enclitic_particle` | `inserted` | 3 | 3 | 0 | 3 | 0 |
| `enclitic_particle` | `substituted` | 137 | 137 | 0 | 137 | 0 |
| `spelling_variant` | `spacing` | 14 | 29 | 0 | 29 | 0 |
| `spelling_variant` | `variant-table` | 8 | 8 | 0 | 8 | 0 |
| `other_substitution` | `near_miss` | 179 | 179 | 0 | 179 | 0 |
| `other_substitution` | `unrelated` | 1059 | 1059 | 0 | 1059 | 0 |
| `other_deletion` | `isolated` | 309 | 309 | 0 | 0 | 309 |
| `other_insertion` | `isolated` | 22 | 22 | 0 | 0 | 22 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 70 | 70 | 0 | 70 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 23 | 23 | 0 | 23 | 0 |
| `boundary_error` | `at_boundary` | 152 | 152 | 0 | 152 | 0 |
| `boundary_error` | `short_reference_word` | 103 | 103 | 0 | 103 | 0 |
| `morphology_error` | `at_boundary` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `root_unlisted` | 16 | 16 | 0 | 16 | 0 |
| `hallucination` | `inside_reference_speech` | 1 | 3 | 0 | 0 | 3 |
| `deleted_speech` | `at_boundary` | 60 | 503 | 0 | 0 | 503 |
| `enclitic_particle` | `at_boundary` | 10 | 10 | 0 | 10 | 0 |
| `spelling_variant` | `at_boundary` | 2 | 4 | 0 | 4 | 0 |
| `other_substitution` | `language_unresolved` | 929 | 929 | 0 | 929 | 0 |
| `other_substitution` | `short_reference_word` | 789 | 789 | 0 | 789 | 0 |

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
| heuristic | 1812 | 467 | 22 | 1 | 124 | 93 | 987 | 3506 |

Heuristic tokens that are `unknown` or `ambiguous`: 1080 of 3506 (30.8%). Heuristic tokens labelled `tl` or `en`: 2279 (65.0%).

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
| heuristic | tl | 414 | 111 | 4 | 1 | 40 | 18 | 287 |
| heuristic | en | 56 | 23 | 1 | 0 | 6 | 2 | 72 |
| heuristic | mix | 4 | 1 | 0 | 0 | 1 | 0 | 4 |
| heuristic | name | 13 | 2 | 0 | 0 | 0 | 1 | 16 |
| heuristic | other | 39 | 12 | 0 | 0 | 8 | 5 | 29 |
| heuristic | ambiguous | 28 | 5 | 0 | 0 | 2 | 3 | 14 |
| heuristic | unknown | 195 | 64 | 4 | 0 | 12 | 12 | 222 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 875 | 1057 | 65.2% |
| heuristic | en | 640 | 160 | 239 | 62.3% |
| heuristic | mix | 50 | 10 | 20 | 60.0% |
| heuristic | name | 95 | 32 | 33 | 68.4% |
| heuristic | other | 299 | 93 | 139 | 77.6% |
| heuristic | ambiguous | 188 | 52 | 84 | 72.3% |
| heuristic | unknown | 1301 | 509 | 488 | 76.6% |

Inserted words by (heuristic) language: ambiguous 1, en 2, other 1, tl 20, unknown 5.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 274.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 495 | 298 | 60.2% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3109 | 2033 | 65.4% |
| elsewhere, any label | 5042 | 3493 | 69.3% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3475 aligned word pairs in 4 items; **589 (16.9%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 355, '<=2000ms': 174, '<=5000ms': 223, '>5000ms': 192, 'inside': 2531}; largest 24790 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen. This report used the `default` tie-break (the one of eval/langscore.py, which the older tools use). The total never changes, but a category can move by tens of words under another tie-break (`--tie-break`; 67 words at most in the Liva check): do not read a difference of less than about 70 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
