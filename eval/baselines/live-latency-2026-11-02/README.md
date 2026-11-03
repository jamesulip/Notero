# Live-latency experiment, 2026-11-02

Numbers only. No audio and no transcript text. [FINDINGS.md](../../../docs/FINDINGS.md) entry 38 and
[BENCHMARKS.md](../../../docs/BENCHMARKS.md#live-commit-latency-2026-11-02) give the reading.

| File | What it is |
| --- | --- |
| `plan-session-1.json`, `plan-session-2.json` | The plan of each session, written and committed before its first run: arms, flags, clips with SHA-256, the seeded order of every run, the statistics and the gate |
| `results-session-N.json` | One record per run: every committed word's commit latency in ms (wall and audio clock) and its reason, the decoder counters, the invariant check, CPU, the machine load sampled during the run |
| `analysis-session-N.json`, `report-session-N.md` | Effects with intervals, the A/A, every gate, by variant. `python3 -I eval/live_latency.py analyze` regenerates them from the plan and the results |
| `decision.json`, `DECISION.md` | The rule of the plan applied to both sessions |

## What differs from what the plans first said

* **The first plan was amended once**, after an independent code review and before any measured result was read.
  Four runs of the earlier plan had finished. None was read or scored. They were deleted with their binary.
* **Session 2 used three clips and not six.** Plan 1 said all six clips. Session 2 used the three that session 1
  had not used (`fleurs-lf2`, `liva-b`, `ami-b`), to save a third of the machine time. `decision.json` still
  repeats the sentence "on the clips of session 1 and the held-out clips", because the gate text is shared.
* **`HT` was in session 2 by the investigator's choice,** not by the promotion rule (it failed the 15% bar in
  session 1). The note of `plan-session-2.json` says why. It cannot change the decision.
* **The pilot** (6 runs on two short clips outside the six) is not in this folder and is not evidence. It
  found that a pooled median of words over clips of 3 s and 17 s is unstable, which fixed the statistic.

## How to reproduce

```bash
python3 -I eval/live_latency.py prepare                     # clips from /tmp/notero-data, to /tmp/notero-p2
python3 -I eval/live_latency.py plan --session 1 ...        # the plan, before any run
python3 -I eval/live_latency.py run --plan PLAN             # real time, under the bench lock
python3 -I eval/live_latency.py score --plan PLAN --out DIR
python3 -I eval/live_latency.py analyze --plan PLAN --out DIR
python3 -I eval/live_latency.py decide --out DIR --sessions 1 2
```

`tests/test_live_latency.py` checks that the analysis and the decision in this folder follow from the results
in this folder.
