# Taxonomy baselines, 2026-11-02

Aggregate error-taxonomy reports (`eval/taxonomy.py`, [method](../../TAXONOMY.md)) on the hypotheses
that the 2026-11-02 tier comparison saved. **They hold counts only. No audio, no reference text and
no hypothesis text is in this folder**, except `fixture/`, which is synthetic text written for this
repository.

| Folder | Reference | Hypotheses | Items |
| --- | --- | --- | ---: |
| `liva/{fast,balanced,best}` | Liva AI `en-tl` sample (CC BY 4.0), manifest `liva-en-tl-overlapping-51b5d0b` | first decodes, `liva-run1/hyp/<tier>` | 4 |
| `liva-repeat1/{...}` | same | second decodes, `liva-run1/hyp-repeat1/<tier>` | 4 |
| `liva-tiebreak-del-ins-sub/`, `liva-tiebreak-ins-del-sub/` | same | first decodes, with another choice between equal-cost alignments (`--tie-break`) | 4 |
| `fleurs/{...}` | FLEURS `fil_ph` test, one sentence per recording (CC BY 4.0), seed 7 | `run1/hyp/<tier>` | 349 |
| `fixture/` | `eval/fixtures/taxonomy/` | `eval/fixtures/taxonomy/hyp` | 5 |

Each folder has `taxonomy.json` and `taxonomy.md`; `tiers.md` puts the tiers side by side. The inputs
stay in `/tmp/notero-data/tiers` (not in git). Their SHA-256 values are in each report
(`inputs.manifestSha256`), together with the SHA-256 of every word list and the fingerprint of the
configuration. The tier decodes were made at commit `5f34fbc` on a Mac mini M2 Pro under the bench
lock; this folder re-reads their saved output and decodes nothing.

**The tie-break folders show how far the categories move.** The total of each decode is the same in all three
folders; the split into substitutions, deletions and insertions, and some categories, are not (Liva Best
`other_insertion` 52, 87, 106; `morphology_error` 44, 28, 28; Balanced `tl_to_en_substitution` 158, 148, 147).
Read no difference of less than about 40 words in one category.

Every language label in `liva*` and `fleurs*` is **heuristic**. No reference has word-level tags, so
there is no `verified` count. Do not read a category count as a measurement of the speech.

Reproduce (the same inputs give byte-identical files):

```bash
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir liva
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir liva-repeat1 --repeat 1
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/run1/plan.json --out-dir fleurs
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir liva-tiebreak-del-ins-sub --tie-break del-ins-sub
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir liva-tiebreak-ins-del-sub --tie-break ins-del-sub
python3 -I eval/taxonomy.py report --manifest eval/fixtures/taxonomy/manifest.json \
    --hyp-dir eval/fixtures/taxonomy/hyp --label "synthetic fixture" --out-dir fixture --include-text 3
```
