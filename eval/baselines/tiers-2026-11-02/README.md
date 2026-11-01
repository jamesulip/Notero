# Tier comparison baselines, 2026-11-02

The plans, decisions and Markdown reports of the tier comparison in
[`eval/TIER-RESULTS.md`](../../TIER-RESULTS.md). There is no audio and no raw transcript here. The
utterance tables in the reports give counts only.

| Folder | Corpus | Source and licence |
| --- | --- | --- |
| `fleurs/` | FLEURS `fil_ph` test, 349 sentences | Google, FLEURS, CC-BY-4.0 |
| `liva/` | Liva AI `en-tl` sample, 4 × 10 min | Liva AI, Code-Switching ASR, https://huggingface.co/datasets/liva-ai/code-switching-asr, CC-BY-4.0 |

Each `plan.json` was written before the first decode of its run, and it contains the decision
gate. The `decision.md` files come from the stricter gate of `eval/tier_benchmark.py` at the time
of the commit. The `repeat1-*` files in `liva/` compare the second decode of each recording.
