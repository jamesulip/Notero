# Committed baselines and calibration

`/tmp` is not evidence: it is gone after a reboot, and the first cycle's baseline lived
there. These small files are the evidence, kept in the repository so a later cycle
compares against what was actually measured. **No audio, no transcripts** (only per-run
numbers), and nothing here is a claim about real Taglish: the fixture is synthetic.

| File | What it is | Size |
| --- | --- | --- |
| `p6-f022c6e-synthetic-taglish.json` | The P6 baseline, every arm run by run: pure f022c6e and f022c6e + CLI instrumentation, offline n = 12, live n = 8, the live recheck on a quiet machine, the A/A pair, the real-time replay | ~40 KB |
| `p6-lead-ab-main-vs-p6-branch.json` | The lead's pre-P6 `main` (addf5f8) against the P6 branch, offline, 6 runs each: main collapsed 4 of 6 runs, the P6 branch gave 24.2% six times | 3 KB |
| `aa-calibration.json` | The measured false-positive rate of the decision rule on A/A comparisons: resampling from the P6 runs, and real runs where a stream exists | ~10 KB |
| `import_p6.py` | One-off: how the two `p6-*` files were produced from `/tmp/notero-team/baseline` and `/tmp/notero-team/lead-ab` | |
| `sessions/` | `report.md` and `report.json` of the regression sessions this cycle ran (the validation of `eval/regress.py`) | |

## Provenance of `p6-f022c6e-synthetic-taglish.json`

* **Code measured:** `transcribe` built from commit `f022c6ed28a6777d15e76abcd8a95d44b460c4c0`
  ("pure"), and the same commit plus the CLI's reporting instrumentation. Release builds,
  Balanced tier (`openai_whisper-large-v3-v20240930_turbo`), language forced to `tl`,
  `--no-diarize`.
* **Machine:** Mac mini `Mac14,12`, Apple M2 Pro, 16 GB, macOS 26.6.2, Swift 6.3.3.
* **Date:** 2026-10-31 (UTC 16:17 to 17:40), one session each for offline, live, the A/A
  pair and the quiet recheck.
* **Harness:** `eval/bench_runs.py` at commit `d01f895` with uncommitted changes in `eval/`
  for the first sessions (`harness_eval_dir_dirty` is true in them) and `1a8ab42` for the
  later ones; the final form is `62780a8`. Every measured run took the bench lock. Offline
  and live sessions were interleaved ABBA.
* **Audio:** `eval/audio/synthetic-taglish.wav`, sha256 `e858bd6a1da505428823efb749017a81659b028742810f34deca10dbddd05f25`
  (regenerated identically by `eval/fixtures.py`), reference `eval/synthetic-taglish.txt`,
  128 words by `score.py`.
* **Collapse flags:** `collapsed_by_p6_rule` is what the P6 harness printed;
  `collapsed_by_current_rule` is the rule of `benchstats.COLLAPSE_RULE`, recomputed from the
  per-run numbers. They differ in exactly one arm: offline-pure run 8, the 57.0% run in which
  Whisper invented a filler phrase, which the P6 rule never counted.

## How to use a baseline

```bash
# Re-measure the baseline's commit TODAY, interleaved with the candidate, and compare the
# base arm with the committed numbers (context only: the committed runs were not interleaved
# with today's, so they can never be a test):
python3 eval/regress.py --cand WORKTREE --baseline eval/baselines/p6-f022c6e-synthetic-taglish.json
```

`--baseline` names the base commit when `--base` is omitted, and prints a **baseline drift**
warning when this machine, macOS release (major.minor), memory, CPU, model id or fixture hash
differs from the baseline's. A candidate's numbers from another day are never compared with
a baseline's medians: the P6 recheck showed a 16% RTF "regression" appear in a busy session and
vanish in a quiet one.

To record a new baseline after a cycle: run `regress.py`, then
`python3 eval/regress.py save-baseline REPORT/report.json --name NAME --out eval/baselines/NAME.json`,
and add its provenance (commit, machine, date, harness commit) to this file.

## What `aa-calibration.json` says and how to regenerate it

`python3 eval/calibrate_aa.py simulate --reps 2000 --n 8 --out eval/baselines/aa-calibration.json`
resamples two arms of 8 runs from the P6 runs of one binary, applies the whole decision rule,
and repeats; `calibrate_aa.py stream` does the same on a real stream of runs
(`regress.py stream --bin X --runs N`). The seed is fixed, so the committed numbers regenerate
exactly. `docs/BENCHMARKS.md` ("How often this harness cries wolf") explains how to read it.
