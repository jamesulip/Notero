# Error taxonomy: best

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `liva-en-tl-overlapping-51b5d0b`, manifest SHA-256 `9c088855bbb9b42b…`
- items scored: 4; missing a hypothesis or reference: 0
- reference formats: {'json': 4}; hypothesis formats: {'json': 4}
- reference items with word-level language tags: 0 (0 tokens); annotators: none recorded
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

5537 reference words, 3914 hypothesis words. Substitutions 1647, deletions 1784, insertions 161; **3592 errors, WER 64.87%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 3592 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 57 | 57 | 1.6% | 0 | 57 | 0 |
| `en_to_tl_substitution` | 25 | 25 | 0.7% | 0 | 25 | 0 |
| `boundary_error` | 140 | 140 | 3.9% | 0 | 140 | 0 |
| `mixed_word_error` | 13 | 19 | 0.5% | 0 | 19 | 0 |
| `morphology_error` | 28 | 28 | 0.8% | 0 | 28 | 0 |
| `proper_noun_error` | 33 | 33 | 0.9% | 0 | 33 | 0 |
| `hallucination` | 6 | 61 | 1.7% | 0 | 0 | 61 |
| `deleted_speech` | 221 | 1385 | 38.6% | 0 | 0 | 1385 |
| `enclitic_particle` | 152 | 152 | 4.2% | 0 | 152 | 0 |
| `spelling_variant` | 38 | 61 | 1.7% | 0 | 61 | 0 |
| `other_substitution` | 1232 | 1232 | 34.3% | 0 | 1232 | 0 |
| `other_deletion` | 312 | 312 | 8.7% | 0 | 0 | 312 |
| `other_insertion` | 87 | 87 | 2.4% | 0 | 0 | 87 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 57 | 57 | 0 | 57 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 25 | 25 | 0 | 25 | 0 |
| `boundary_error` | `anticipation` | 14 | 14 | 0 | 14 | 0 |
| `boundary_error` | `carry_over` | 17 | 17 | 0 | 17 | 0 |
| `boundary_error` | `deleted` | 28 | 28 | 0 | 28 | 0 |
| `boundary_error` | `same_language` | 30 | 30 | 0 | 30 | 0 |
| `boundary_error` | `unresolved` | 51 | 51 | 0 | 51 | 0 |
| `mixed_word_error` | `affix_changed` | 3 | 3 | 0 | 3 | 0 |
| `mixed_word_error` | `affix_dropped` | 2 | 2 | 0 | 2 | 0 |
| `mixed_word_error` | `both_wrong` | 6 | 12 | 0 | 12 | 0 |
| `mixed_word_error` | `stem_changed` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `affix_added` | 5 | 5 | 0 | 5 | 0 |
| `morphology_error` | `affix_changed` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `affix_missing` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `ligature_added` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `ligature_dropped` | 6 | 6 | 0 | 6 | 0 |
| `morphology_error` | `reduplication_added` | 2 | 2 | 0 | 2 | 0 |
| `morphology_error` | `reduplication_dropped` | 1 | 1 | 0 | 1 | 0 |
| `proper_noun_error` | `deleted` | 5 | 5 | 0 | 5 | 0 |
| `proper_noun_error` | `different_word` | 16 | 16 | 0 | 16 | 0 |
| `proper_noun_error` | `near_spelling` | 12 | 12 | 0 | 12 | 0 |
| `hallucination` | `repetition_loop` | 4 | 55 | 0 | 0 | 55 |
| `hallucination` | `run` | 2 | 6 | 0 | 0 | 6 |
| `deleted_speech` | `run` | 221 | 1385 | 0 | 0 | 1385 |
| `enclitic_particle` | `deleted` | 33 | 33 | 0 | 33 | 0 |
| `enclitic_particle` | `inserted` | 10 | 10 | 0 | 10 | 0 |
| `enclitic_particle` | `substituted` | 109 | 109 | 0 | 109 | 0 |
| `spelling_variant` | `spacing` | 20 | 43 | 0 | 43 | 0 |
| `spelling_variant` | `variant-table` | 18 | 18 | 0 | 18 | 0 |
| `other_substitution` | `near_miss` | 176 | 176 | 0 | 176 | 0 |
| `other_substitution` | `unrelated` | 1056 | 1056 | 0 | 1056 | 0 |
| `other_deletion` | `isolated` | 312 | 312 | 0 | 0 | 312 |
| `other_insertion` | `isolated` | 87 | 87 | 0 | 0 | 87 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `short_reference_word`: the reference word has at most 4 letters (substitution categories); `outside_reference_speech`: at least 80% of the timed inserted words fall outside every padded reference utterance; `inside_reference_speech`: fewer than 80% of the timed inserted words fall outside reference speech; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word; `root_unlisted`: the shared Tagalog root is not on the word list (a 4+ letter root between two non-English words).

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `short_reference_word` | 45 | 45 | 0 | 45 | 0 |
| `en_to_tl_substitution` | `short_reference_word` | 22 | 22 | 0 | 22 | 0 |
| `boundary_error` | `at_boundary` | 140 | 140 | 0 | 140 | 0 |
| `boundary_error` | `short_reference_word` | 99 | 99 | 0 | 99 | 0 |
| `morphology_error` | `root_unlisted` | 12 | 12 | 0 | 12 | 0 |
| `hallucination` | `inside_reference_speech` | 5 | 43 | 0 | 0 | 43 |
| `hallucination` | `outside_reference_speech` | 1 | 18 | 0 | 0 | 18 |
| `deleted_speech` | `at_boundary` | 52 | 400 | 0 | 0 | 400 |
| `enclitic_particle` | `at_boundary` | 10 | 10 | 0 | 10 | 0 |
| `spelling_variant` | `at_boundary` | 7 | 13 | 0 | 13 | 0 |
| `other_substitution` | `language_unresolved` | 924 | 924 | 0 | 924 | 0 |
| `other_substitution` | `short_reference_word` | 804 | 804 | 0 | 804 | 0 |

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
| heuristic | 2097 | 490 | 28 | 0 | 146 | 101 | 1052 | 3914 |

Heuristic tokens that are `unknown` or `ambiguous`: 1153 of 3914 (29.5%). Heuristic tokens labelled `tl` or `en`: 2587 (66.1%).

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
| heuristic | tl | 393 | 78 | 4 | 0 | 27 | 23 | 269 |
| heuristic | en | 47 | 36 | 0 | 0 | 7 | 4 | 61 |
| heuristic | mix | 4 | 4 | 2 | 0 | 1 | 0 | 6 |
| heuristic | name | 5 | 3 | 0 | 0 | 1 | 0 | 19 |
| heuristic | other | 47 | 9 | 0 | 0 | 9 | 1 | 37 |
| heuristic | ambiguous | 21 | 7 | 1 | 0 | 3 | 1 | 17 |
| heuristic | unknown | 187 | 64 | 4 | 0 | 17 | 8 | 220 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| heuristic | tl | 2964 | 794 | 875 | 56.3% |
| heuristic | en | 642 | 155 | 232 | 60.3% |
| heuristic | mix | 50 | 17 | 13 | 60.0% |
| heuristic | name | 95 | 28 | 30 | 61.1% |
| heuristic | other | 299 | 103 | 114 | 72.6% |
| heuristic | ambiguous | 188 | 50 | 63 | 60.1% |
| heuristic | unknown | 1299 | 500 | 457 | 73.7% |

Inserted words by (heuristic) language: ambiguous 1, en 30, mix 1, other 10, tl 83, unknown 36.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 0, heuristic 276.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a heuristic switch point | 498 | 280 | 56.2% |
| elsewhere, labelled `tl` or `en` (heuristic) | 3108 | 1776 | 57.1% |
| elsewhere, any label | 5039 | 3151 | 62.5% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

3743 aligned word pairs in 4 items; **469 (12.5%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=1000ms': 403, '<=2000ms': 140, '<=5000ms': 181, '>5000ms': 148, 'inside': 2871}; largest 33245 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

## Caveats

- No reference token carries a word-level language tag, so every language label in this report is a heuristic guess from small hand-written word lists. Read the heuristic counts as indications, not as measurements of the speech.
- The category counts depend on which of several equal-cost alignments is chosen (this tool uses the same tie-break as eval/langscore.py). The total never changes, but a category of a few dozen words can move by tens of words under another tie-break: do not read a difference of less than about 40 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.
- Utterance-level `language` fields (for example "mixed") are ignored as token labels: only word-level tags count.
