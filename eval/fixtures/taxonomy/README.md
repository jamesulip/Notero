# Taxonomy fixture

Synthetic text for the error taxonomy (`eval/taxonomy.py`). **Claude (an AI model) wrote every
sentence for this fixture. None of it is corpus text, and there is no audio.** The language tags
in the `.tagged.txt` references were written with the sentences and exist to test the tool; they
are not linguistic ground truth, and no native speaker has reviewed them. The word times in `refs/silence.json` and `hyp/silence.json` are invented.

`expected.json` holds the counts the tests assert. They were worked out from the
sentences below, not copied from the tool's output. The error words are counted below; an event can span several words.

| Item | Reference | What it exercises |
| --- | --- | --- |
| `switching` | `refs/switching.tagged.txt` (all words tagged) | `spelling_variant` spacing ("standup" / "stand up", 2 words); `tl_to_en_substitution` (umaga / morning; with the heuristic hypothesis label); `en_to_tl_substitution` (before / bago); `boundary_error` deleted (schedule) and `carry_over` (meeting / usapan); `proper_noun_error` `near_spelling` (Andy / Andi) and `deleted` (Marites); `enclitic_particle` deleted (po), substituted (naman / lang) and inserted (po); `spelling_variant` from the table (pwede / puwede); `other_substitution` (bahay / bukid); `other_deletion` (kayo); `other_insertion` (talaga). 15 error words |
| `mixed-words` | `refs/mixed-words.tagged.txt` | `mixed_word_error`: `affix_dropped` (i-share / share), `affix_changed` (nag-meeting / mag meeting), `stem_changed` (naka-mute / naka mud), `both_wrong` (i-click / ikot, 2 words), `affix_dropped` and `deleted` on an unhyphenated "nagmeeting"; and `spelling_variant` spacing for mag-update / magupdate (2 words, not a mixed-word error: the letters are the same). 9 error words |
| `morphology` | `refs/morphology.txt` (untagged) | `morphology_error`: `reduplication_dropped` (kakain / kain), `affix_changed` (nagluto / magluto), `affix_missing` (umuwi / uwi), `affix_added` (bili / bumili), `ligature_dropped` (magandang / maganda), `ligature_added` (bago / bagong), `reduplication_added` (kain / kakain). 7 error words |
| `silence` | `refs/silence.json` (utterance times; word spans on its second utterance; utterance `language` fields that must be ignored) | `hallucination` in silence ("thank you for watching" at 6 to 8 s, `outside_reference_speech`, 4 words), a `repetition_loop` after the last utterance (4 words), `deleted_speech` (a run of 3), and one recognised word stamped 4.3 s before its utterance (`timestamp_misalignment`). 11 error words |
| `plain-heuristic` | `refs/plain-heuristic.txt` (untagged) | the same machinery with no verified tags: a heuristic `tl_to_en_substitution` (bahay / house), an `other_substitution` of two `unknown` words with `language_unresolved`, and a `hallucination` in a hypothesis with no times (`time_unknown`). 6 error words |

Totals: 169 reference words, 173 hypothesis words, 22 substitutions, 11 deletions, 15 insertions,
48 error words. 112 reference tokens carry a verified tag. Every category has at least one case.

`adjudications.tsv` moves the `kalabaw` / `kalabao` event to `spelling_variant` as a person's
decision (basis `verified`).

```bash
python3 -I eval/taxonomy.py report --manifest eval/fixtures/taxonomy/manifest.json \
    --hyp-dir eval/fixtures/taxonomy/hyp --label fixture --out-dir /tmp/taxonomy --include-text 3
```

The cases are separated by enough matching words that the minimum-edit alignment has one
reasonable answer. A deleted run directly beside an inserted run of similar length would be
aligned as substitutions, which is correct for an edit distance and is why `silence` keeps them
apart.
