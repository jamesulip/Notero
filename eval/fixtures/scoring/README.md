# Scoring fixture

Synthetic text for the evaluation framework (`transcribe --score`). It contains
no audio and no recording. A person wrote every line for this fixture.

| File | Contents |
| --- | --- |
| `manifest.json` | The versioned manifest form, corpus ID `synthetic-scoring-fixture-v1`. |
| `refs/standup.json` | A JSON reference with times, speakers, an `overlap` mark, utterance languages and word-level `languageSpans`. |
| `refs/review.txt` | A plain-text reference with a blank line. Its manifest category is `mixed`. |
| `hyp-baseline/standup.json` | A hand-written `transcribe --json` report, with word times and memory snapshots. The figures in it are invented for the test. They are not measurements. |
| `hyp-baseline/review.txt`, `hyp-candidate/*.txt` | Plain-text hypotheses. The candidate is the reference text. |

The item `unreferenced` has no reference on purpose. The report must show it as
unavailable.

```bash
cd app && swift build --product transcribe
./.build/debug/transcribe --score ../eval/fixtures/scoring/manifest.json \
    --hypotheses ../eval/fixtures/scoring/hyp-baseline \
    --compare ../eval/fixtures/scoring/hyp-candidate --out-dir /tmp/scoring-fixture
```

`CorpusEvaluationTests` in `app/Tests/TranscriberCoreTests/Evaluation` reads
these files.
