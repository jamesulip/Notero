# ami against ami-forced-alignment

References: `/tmp/notero-data/fa-src/AMI/test`. nttcslab-sp/diar-forced-alignment commit 9527b7c, AMI files CC BY 4.0: Montreal Forced Aligner word intervals, the references FluidAudio's own AMI benchmark uses.

| Arm | DER, collar 0.25 s, overlap scored | DER, collar 0.0 s, overlap scored | DER, collar 0.25 s, overlap skipped | Missed | False alarm | Confusion | Merged |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pyannote | 24.86% | 45.44% | 22.80% | 4.88% | 9.57% | 10.41% | 19 |
| nemotron3 | 3.49% | 9.41% | 2.65% | 1.76% | 1.28% | 0.46% | 2 |
| nemotron3-fast128 | 3.56% | 9.53% | 2.71% | 1.81% | 1.33% | 0.43% | 2 |
