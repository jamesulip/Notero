# Real session: `regress.py --suite quick`, pre-P6 `addf5f8` against `57dcc14`

The one real validation of `eval/regress.py` this cycle: both builds built by the tool from
`git archive` into `/tmp/notero-regress`, run interleaved ABBA through the bench lock, n = 8 per arm.
Date 2026-10-31/11-01 (UTC), Mac mini `Mac14,12`, M2 Pro, 16 GB, macOS 26.6.2, model
`openai_whisper-large-v3-v20240930_turbo`. `report.md` is the report, `report.json` its data,
`plan.json` how it was run. The raw runs (full transcripts of the synthetic clip) were not kept.

**What ran:** the offline series and the live series on the synthetic Taglish clip, 8 runs per arm each.
**What did NOT run, and why:**

* **The DER half** (two synthetic multi-speaker clips). Its first lock hold was still queued when the
  session was stopped, by the lead's decision, because the single Neural Engine was contended
  (about 25 minutes of waiting per hold with 8 to 10 waiters). The report therefore starts with
  `INCOMPLETE`: that is the harness saying so, not a fault. DER was exercised once on a real binary
  outside this session (a smoke run, 6.1% on `two-distinct`), not compared.
* **The real A/A session** (`57dcc14` against itself). Not run, by the lead's decision. The false-positive
  evidence for the decision rule is the resampling calibration in `../../aa-calibration.json`.
* **A determinism run of a build that lists decode windows.** Neither binary here has the `windows`
  field, so the first diverging window is reported as unknown; word index and time are exact.

**Load record (the report prints it per series):**

| Series | Median load average at launch, base / candidate | Max | Machine |
| --- | --- | --- | --- |
| offline | 6.37 / 6.37 | 8.30 / 7.29 | busy: the timing difference is printed as *indicative only* |
| live | 1.21 / 1.18 | 2.46 / 2.52 | quiet and balanced |

**What it says (single session: suspected, not confirmed):**

* Offline WER 34.4% [30.5–58.6] against 24.2% [24.2–24.2], −10.2 points, rank-sum p < 0.001,
  Holm-adjusted p = 0.002 over 13 tested metrics: a suspected improvement. Collapsed runs 3 of 8 against
  0 of 8 (runs 3, 5 and 8 of the base; run 8 is the filler run), Fisher p = 0.20: not significant at n = 8.
* Offline RTF −10% (p_Holm 0.002) is **not believed**: median load 6.4.
* Live: nothing significant. WER 28.1% against 26.2% (p = 0.12), replay RTF +5% (p = 0.23), no collapsed run
  in either arm; commit latency exists only in the candidate's report and is listed as not tested.
* Determinism: offline, the base gave 8 distinct transcripts in 8 runs and the candidate was byte-identical.
  Live, **both** builds gave 8 distinct transcripts in 8 runs: the P6 branch is deterministic offline only.

This matches the lead's own n = 6 offline A/B (`../../p6-lead-ab-main-vs-p6-branch.json`).
