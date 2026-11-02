# Error taxonomy: synthetic fixture

Optional report on top of the headline WER (`eval/taxonomy.py`, schema `notero-taxonomy-report/1`, config `notero-taxonomy-v1`). Counts are error *words*; the categories partition them, so they add up to substitutions + deletions + insertions.

**Read the basis columns.** `verified` = the reference carried the word-level tags the category needs. `heuristic` = a guess from small hand-written word lists. `structural` = the alignment alone decides it. They are never added together.

## Inputs

- corpus: `synthetic-taxonomy-fixture-v1`, manifest SHA-256 `b548de9408f2db97…`; alignment tie-break `default`
- items scored: 5; missing a hypothesis or reference: 0
- reference formats: {'json': 1, 'tagged': 2, 'txt': 2}; hypothesis formats: {'json': 1, 'txt': 4}
- reference items with word-level language tags: 3 (112 tokens); annotators: ['Claude, AI model (synthetic text)', 'Claude, AI model (synthetic text; tags written to test the tool, not as linguistic ground truth)']
- word lists: `homographs.txt` 20, `lexicon-en.txt` 936, `lexicon-names.txt` 151, `lexicon-other.txt` 27, `lexicon-tl.txt` 990, `particles.txt` 21, `spelling-variants.txt` 28

## Headline

169 reference words, 173 hypothesis words. Substitutions 22, deletions 11, insertions 15; **48 errors, WER 28.40%** (token policy `notero-standard`, the same as `eval/score.py`). Standard-policy error count from `score.levenshtein`: 48 (equal; only the split between S/D/I can differ, through tie-breaking).

## Error categories

| category | events | error words | share of errors | verified | heuristic | structural |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | 2 | 2 | 4.2% | 0 | 2 | 0 |
| `en_to_tl_substitution` | 1 | 1 | 2.1% | 0 | 1 | 0 |
| `boundary_error` | 2 | 2 | 4.2% | 1 | 1 | 0 |
| `mixed_word_error` | 6 | 7 | 14.6% | 7 | 0 | 0 |
| `morphology_error` | 7 | 7 | 14.6% | 0 | 7 | 0 |
| `proper_noun_error` | 2 | 2 | 4.2% | 2 | 0 | 0 |
| `hallucination` | 3 | 12 | 25.0% | 0 | 0 | 12 |
| `deleted_speech` | 1 | 3 | 6.2% | 0 | 0 | 3 |
| `enclitic_particle` | 3 | 3 | 6.2% | 0 | 3 | 0 |
| `spelling_variant` | 3 | 5 | 10.4% | 0 | 5 | 0 |
| `other_substitution` | 2 | 2 | 4.2% | 0 | 2 | 0 |
| `other_deletion` | 1 | 1 | 2.1% | 0 | 0 | 1 |
| `other_insertion` | 1 | 1 | 2.1% | 0 | 0 | 1 |

Definitions: `tl_to_en_substitution` a Tagalog reference word replaced by an English word (by the output word's language, not the intent); `en_to_tl_substitution` an English reference word replaced by a Tagalog word or Tagalog spelling of it; `boundary_error` a word at a code-switch point (first word after a switch, or last before one) deleted or replaced; `mixed_word_error` a Tagalog affix + English stem word (nag-meeting, i-share, naka-mute) deleted or mangled; `morphology_error` the right Tagalog root with the wrong or missing affix, reduplication or linker (-ng / -g); `proper_noun_error` a reference proper name deleted or replaced; `hallucination` a run of inserted words (3 or more), with no reference word behind it; `deleted_speech` a run of deleted reference words (3 or more), speech that produced no output; `enclitic_particle` an enclitic or particle (po, naman, lang, na, pa, ...) deleted, inserted or replaced; `spelling_variant` the same word with another spelling or spacing; arguably not a recognition error; `other_substitution` a substitution that no rule above explains; `other_deletion` an isolated deleted word (fewer than 3 in a row) that no rule above explains; `other_insertion` an isolated inserted word (fewer than 3 in a row) that no rule above explains.

### Subtypes

| category | subtype | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tl_to_en_substitution` | `heuristic-hypothesis-language` | 2 | 2 | 0 | 2 | 0 |
| `en_to_tl_substitution` | `heuristic-hypothesis-language` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `carry_over` | 1 | 1 | 0 | 1 | 0 |
| `boundary_error` | `deleted` | 1 | 1 | 1 | 0 | 0 |
| `mixed_word_error` | `affix_changed` | 1 | 1 | 1 | 0 | 0 |
| `mixed_word_error` | `affix_dropped` | 2 | 2 | 2 | 0 | 0 |
| `mixed_word_error` | `both_wrong` | 1 | 2 | 2 | 0 | 0 |
| `mixed_word_error` | `deleted` | 1 | 1 | 1 | 0 | 0 |
| `mixed_word_error` | `stem_changed` | 1 | 1 | 1 | 0 | 0 |
| `morphology_error` | `affix_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_changed` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `affix_missing` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `ligature_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `ligature_dropped` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `reduplication_added` | 1 | 1 | 0 | 1 | 0 |
| `morphology_error` | `reduplication_dropped` | 1 | 1 | 0 | 1 | 0 |
| `proper_noun_error` | `deleted` | 1 | 1 | 1 | 0 | 0 |
| `proper_noun_error` | `near_spelling` | 1 | 1 | 1 | 0 | 0 |
| `hallucination` | `repetition_loop` | 1 | 4 | 0 | 0 | 4 |
| `hallucination` | `run` | 2 | 8 | 0 | 0 | 8 |
| `deleted_speech` | `run` | 1 | 3 | 0 | 0 | 3 |
| `enclitic_particle` | `deleted` | 1 | 1 | 0 | 1 | 0 |
| `enclitic_particle` | `inserted` | 1 | 1 | 0 | 1 | 0 |
| `enclitic_particle` | `substituted` | 1 | 1 | 0 | 1 | 0 |
| `spelling_variant` | `spacing` | 2 | 4 | 0 | 4 | 0 |
| `spelling_variant` | `variant-table` | 1 | 1 | 0 | 1 | 0 |
| `other_substitution` | `near_miss` | 1 | 1 | 0 | 1 | 0 |
| `other_substitution` | `unrelated` | 1 | 1 | 0 | 1 | 0 |
| `other_deletion` | `isolated` | 1 | 1 | 0 | 0 | 1 |
| `other_insertion` | `isolated` | 1 | 1 | 0 | 0 | 1 |

### Flags (overlays; a word can carry several)

`at_boundary`: the reference word is next to a code-switch point (any category); `outside_reference_speech`: at least 80% of the timed inserted words fall outside every padded reference utterance; `time_unknown`: the reference has no times, or the hypothesis has no word times; `language_unresolved`: the reference or hypothesis word is ambiguous, unknown, other, a name or a mixed word.

| category | flag | events | error words | verified | heuristic | structural |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `boundary_error` | `at_boundary` | 2 | 2 | 1 | 1 | 0 |
| `hallucination` | `outside_reference_speech` | 2 | 8 | 0 | 0 | 8 |
| `hallucination` | `time_unknown` | 1 | 4 | 0 | 0 | 4 |
| `deleted_speech` | `at_boundary` | 1 | 3 | 0 | 0 | 3 |
| `spelling_variant` | `at_boundary` | 1 | 2 | 0 | 2 | 0 |
| `other_substitution` | `language_unresolved` | 1 | 1 | 0 | 1 | 0 |

## Language labels

**Reference tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | 85 | 13 | 12 | 2 | 0 | 0 | 0 | 112 |
| heuristic | 55 | 0 | 0 | 0 | 0 | 0 | 2 | 57 |

Heuristic tokens that are `unknown` or `ambiguous`: 2 of 57 (3.5%). Heuristic tokens labelled `tl` or `en`: 55 (96.5%).

**Hypothesis tokens** (a hypothesis word is never verified)

| basis | tl | en | mix | name | other | ambiguous | unknown | total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heuristic | 139 | 26 | 0 | 0 | 0 | 1 | 7 | 173 |

Heuristic tokens that are `unknown` or `ambiguous`: 8 of 173 (4.6%). Heuristic tokens labelled `tl` or `en`: 165 (95.4%).

Heuristic reference labels by rule:

| label | rule | tokens |
| --- | --- | ---: |
| tl | `lexicon-tl` | 51 |
| tl | `affix+tagalog-stem` | 2 |
| tl | `tl-ligature` | 2 |
| unknown | `no-match` | 2 |

## Substitutions by language (reference row, hypothesis column)

| reference basis | reference label | tl | en | mix | name | other | ambiguous | unknown |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| verified | tl | 3 | 1 | 0 | 0 | 0 | 0 | 0 |
| verified | en | 2 | 1 | 0 | 0 | 0 | 0 | 0 |
| verified | mix | 0 | 1 | 0 | 0 | 0 | 1 | 3 |
| verified | name | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| heuristic | tl | 7 | 1 | 0 | 0 | 0 | 0 | 0 |
| heuristic | unknown | 0 | 0 | 0 | 0 | 0 | 0 | 1 |

The hypothesis column is always a heuristic label. This matrix covers every substitution; the `tl_to_en_substitution` / `en_to_tl_substitution` categories hold only those no earlier rule claimed.

## Error rate by reference label

| basis | label | words | substitutions | deletions | error rate (S+D)/words |
| --- | --- | ---: | ---: | ---: | ---: |
| verified | tl | 85 | 4 | 4 | 9.4% |
| verified | en | 13 | 3 | 2 | 38.5% |
| verified | mix | 12 | 5 | 4 | 75.0% |
| verified | name | 2 | 1 | 1 | 100.0% |
| heuristic | tl | 55 | 8 | 0 | 14.5% |
| heuristic | unknown | 2 | 1 | 0 | 50.0% |

Inserted words by (heuristic) language: en 13, tl 2.

## Code-switch points

Switch points (adjacent clearly-Tagalog and clearly-English words in one utterance): verified 10, heuristic 0.

| word position | words | errors (S+D) | rate |
| --- | ---: | ---: | ---: |
| at a verified switch point | 16 | 6 | 37.5% |
| elsewhere, labelled `tl` or `en` (verified) | 82 | 7 | 8.5% |
| elsewhere, labelled `tl` or `en` (heuristic) | 55 | 8 | 14.5% |
| elsewhere, any label | 153 | 27 | 17.6% |

A switch point needs two words that are clearly Tagalog and English, so the fair comparison is with other words that carry such a label (the first rows). "Any label" includes `unknown`, `ambiguous`, `other` and `name` words, which are wrong more often.

## Timestamp misalignment (overlay on recognised words)

15 aligned word pairs in 1 items; **1 (6.7%) have a hypothesis time more than 1000 ms outside the reference utterance**. Offsets: {'<=5000ms': 1, 'inside': 14}; largest 4300 ms. Reference times are per utterance, not per word, and an alignment that drifts across an overlapped or reordered stretch also shows up here.

Items without it: 4 × reference has no utterance times.

## Caveats

- 112 of 169 reference tokens carry a word-level tag supplied by the reference annotation (the tool does not check the annotator). The remaining tokens, and every hypothesis token, are heuristic. The two are kept apart in every table.
- The category counts depend on which of several equal-cost alignments is chosen. This report used the `default` tie-break (the one of eval/langscore.py, which the older tools use). The total never changes, but a category can move by tens of words under another tie-break (`--tie-break`; 67 words at most in the Liva check): do not read a difference of less than about 70 words in one category.
- Hypothesis words are never tagged by a person, so tl_to_en / en_to_tl substitutions rest on a heuristic label for the hypothesis word even when the reference word is verified.
- The word lists are small and were written by an AI model (Claude) without a native speaker's review: `unknown` is the largest honest answer for words they do not cover, and the ambiguous/unknown shares are reported rather than hidden.
- Categories partition the word errors by a first-match rule list; a word that fits two rules is counted under the earlier one. Which rule fired is a design choice, not a linguistic finding.
- When a reference interleaves speakers (overlapping speech) the words do not follow one time order, so some substitutions, deletions and insertions are ordering artefacts, not recognition errors.

## Examples (corpus text; do not commit for third-party data)

**boundary_error**

- `switching` deleted [verified]: ref `schedule` → hyp ``
- `switching` carry_over [heuristic]: ref `meeting` → hyp `usapan`

**deleted_speech**

- `silence` run [structural]: ref `ang meeting ngayon` → hyp ``

**en_to_tl_substitution**

- `switching` heuristic-hypothesis-language [heuristic]: ref `before` → hyp `bago`

**enclitic_particle**

- `switching` deleted [heuristic]: ref `po` → hyp ``
- `switching` substituted [heuristic]: ref `naman` → hyp `lang`
- `switching` inserted [heuristic]: ref `` → hyp `po`

**hallucination**

- `plain-heuristic` run [structural]: ref `` → hyp `thank you for watching`
- `silence` run [structural]: ref `` → hyp `thank you for watching`
- `silence` repetition_loop [structural]: ref `` → hyp `hello hello hello hello`

**mixed_word_error**

- `mixed-words` affix_dropped [verified]: ref `i` → hyp ``
- `mixed-words` affix_changed [verified]: ref `nag` → hyp `mag`
- `mixed-words` stem_changed [verified]: ref `mute` → hyp `mud`

**morphology_error**

- `morphology` reduplication_dropped [heuristic]: ref `kakain` → hyp `kain`
- `morphology` affix_changed [heuristic]: ref `nagluto` → hyp `magluto`
- `morphology` affix_missing [heuristic]: ref `umuwi` → hyp `uwi`

**other_deletion**

- `switching` isolated [structural]: ref `kayo` → hyp ``

**other_insertion**

- `switching` isolated [structural]: ref `` → hyp `talaga`

**other_substitution**

- `plain-heuristic` near_miss [heuristic]: ref `kalabaw` → hyp `kalabao`
- `switching` unrelated [heuristic]: ref `bahay` → hyp `bukid`

**proper_noun_error**

- `switching` near_spelling [verified]: ref `andy` → hyp `andi`
- `switching` deleted [verified]: ref `marites` → hyp ``

**spelling_variant**

- `mixed-words` spacing [heuristic]: ref `mag update` → hyp `magupdate`
- `switching` spacing [heuristic]: ref `standup` → hyp `stand up`
- `switching` variant-table [heuristic]: ref `pwede` → hyp `puwede`

**tl_to_en_substitution**

- `plain-heuristic` heuristic-hypothesis-language [heuristic]: ref `bahay` → hyp `house`
- `switching` heuristic-hypothesis-language [heuristic]: ref `umaga` → hyp `morning`
