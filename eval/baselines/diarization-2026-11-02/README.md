# Diarization comparison, 2026-11-02

Evidence for [docs/DIARIZATION.md](../../../docs/DIARIZATION.md). It holds no audio and no
transcript text.

| File | What it is |
| --- | --- |
| `plan.json` | Arms, items, run order, scoring rules and the gate, written before the first run |
| `run-log.jsonl` | One line per run: exit code, wall time |
| `scores.json.gz` | Every metric of every run (`eval/diarization_metrics.py`) |
| `report.md` | The tables made from the scores |
| `identity.json` | Name-carry re-runs on changed audio |
| `residency.json` | `footprint(1)` sampled from outside, longest AMI meeting |
| `rescore-ami-forced-alignment.*` | The AMI outputs against the forced-alignment references (secondary) |
| `decision.*` | The gate applied |
| `manifest-*.json` | Items, durations, speaker counts and SHA-256 of the prepared audio |

Paths inside point to `/tmp/notero-data/diar/`, where the data was. Attribution: AMI Meeting
Corpus (University of Edinburgh and partners), CC BY 4.0; Liva AI, Code-Switching ASR (en-tl),
CC BY 4.0; AMI forced-alignment references by NTT CS Labs (`nttcslab-sp/diar-forced-alignment`),
CC BY 4.0. The AMI and Liva audio was resampled to 16 kHz mono.
