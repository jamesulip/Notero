# Decision

**keep pyannote: nemotron3 does not pass the gate**

## nemotron3: does not pass

| Check | Pass | Detail |
| --- | --- | --- |
| relativeDerImprovement:ami | **no** | `{"baselineDer": 0.236958, "candidateDer": 0.241324, "relative": -0.0184}` |
| relativeDerImprovement:liva | yes | `{"baselineDer": 0.581295, "candidateDer": 0.16071, "relative": 0.7235}` |
| noNewMerges | **no** | `{"files": ["synth-holdout-h-four-voices"]}` |
| timestampsValid | yes | `{"files": []}` |
| peakFootprint | yes | `{"maxMB": 94.3}` |
| realTimeFactor | yes | `{"median": 0.00281}` |
| repeatStable | yes | `{"maxSpread": 0.0, "pairs": 37}` |
| allRunsScored | yes | `{"failed": [], "missing": []}` |
| speakerNamesCarry | yes | `{"baselineWrongPct": 27.87, "candidateWrongPct": 7.17, "runs": 64}` |

## nemotron3-fast128: does not pass

| Check | Pass | Detail |
| --- | --- | --- |
| relativeDerImprovement:ami | **no** | `{"baselineDer": 0.236958, "candidateDer": 0.241531, "relative": -0.0193}` |
| relativeDerImprovement:liva | yes | `{"baselineDer": 0.581295, "candidateDer": 0.179905, "relative": 0.6905}` |
| noNewMerges | **no** | `{"files": ["synth-holdout-h-four-voices"]}` |
| timestampsValid | yes | `{"files": []}` |
| peakFootprint | yes | `{"maxMB": 79.2}` |
| realTimeFactor | yes | `{"median": 0.00355}` |
| repeatStable | yes | `{"maxSpread": 0.0, "pairs": 37}` |
| allRunsScored | yes | `{"failed": [], "missing": []}` |
| speakerNamesCarry | yes | `{"baselineWrongPct": 27.87, "candidateWrongPct": 7.93, "runs": 64}` |

