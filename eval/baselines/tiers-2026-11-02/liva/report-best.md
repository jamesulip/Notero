# ASR evaluation: best

| | |
| --- | --- |
| Corpus | `liva-en-tl-overlapping-51b5d0b` |
| Items scored | 4 of 4 |
| Configuration | `notero-eval-v1` (schema 1), fingerprint `96fdf032732a3b31` |
| Scoring policy | `notero-standard` v1, fingerprint `5c0946fada2f868b` |
| System | best |
| Model | `openai_whisper-large-v3_turbo` |
| Model revision | `0f63a7800b00dd0226abd051b906c246e1907482` |
| Build | `5f34fbcffa1a756b2dcdc9cf1fc20ecb53970c78` |
| Hardware | Mac14,12 · 10 cores · macOS 26.6, 16 GB |
| Inference | mode offline, language tl, diarization off, roomMode false, styleHint false |

Policy: Unicode NFKC, case folded, diacritics kept, punctuation removed, hyphens split words, intra-word apostrophes kept, contractions as written.

## Warnings

- utterances from 4 recording(s) are resampled as if independent; utterances of one recording share speaker, room and microphone, so the interval understates the variation between recordings

## Accuracy

| Metric | Value | 95% interval | N | Sub | Del | Ins |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| WER | 64.80% | 62.52% to 67.22% | 5537 | 1735 | 1739 | 114 |
| CER | 50.61% | 48.08% to 53.34% | 26429 | 3227 | 8626 | 1522 |

Interval: percentile bootstrap of the pooled rate ΣE/ΣN, type-7 quantiles, SplitMix64; 2000 resamples of 1245 utterances, seed 20261102, stratified by utterance language class.

### By utterance language

| Stratum | Utterances | WER | CER | N | Sub | Del | Ins |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| code-switched | 1245 | 64.80% | 50.61% | 5537 | 1735 | 1739 | 114 |

### By word language

Unavailable: the reference has no language annotation.

### By speaker overlap

Covers 4 of 4 scored items: liva-en-tl-C_001_007, liva-en-tl-C_001_009, liva-en-tl-C_001_015, liva-en-tl-C_001_016. An utterance overlaps when the reference marks it so, or, with no mark, when its time intersects a turn of another speaker. "unknown" holds the utterances that have neither a mark nor a timed speaker turn.

| Stratum | Utterances | WER | CER | N | Sub | Del | Ins |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| overlap | 784 | 68.76% | 56.69% | 3579 | 1015 | 1410 | 36 |
| no-overlap | 461 | 57.56% | 39.62% | 1958 | 720 | 329 | 78 |

## Deletions and missing speech

Deletion bursts (at least 3 consecutive reference words deleted): 215, 1360 words, 1739 deletions in all.

| Item | First utterance | Words | Time | Deleted |
| --- | --- | ---: | --- | --- |
| liva-en-tl-C_001_007 | line-27 | 3 | 23.98 s–26.11 s | sa discord hindi |
| liva-en-tl-C_001_007 | line-127 | 3 | 158.78 s–162.53 s | mali sige hayae |
| liva-en-tl-C_001_007 | line-137 | 3 | 166.30 s–168.49 s | scarf yan sige |
| liva-en-tl-C_001_007 | line-145 | 5 | 169.48 s–173.34 s | uy saan scarf yan sige |
| liva-en-tl-C_001_007 | line-163 | 7 | 177.77 s–178.60 s | ko may move ba daw ayun nga |
| liva-en-tl-C_001_007 | line-191 | 4 | 208.70 s–217.96 s | tangina nag noise kapag |
| liva-en-tl-C_001_007 | line-207 | 4 | 225.10 s–227.37 s | may trade pag may |
| liva-en-tl-C_001_007 | line-281 | 3 | 307.98 s–312.92 s | ano hold your |
| liva-en-tl-C_001_007 | line-319 | 5 | 342.15 s–343.40 s | nagkaganyan na rin yung akin |
| liva-en-tl-C_001_007 | line-327 | 5 | 347.24 s–349.35 s | eighteen kailangan ko yung mga |
| liva-en-tl-C_001_007 | line-393 | 8 | 397.43 s–398.75 s | rinig ko pala yung kapitbahay wait nga ahh |
| liva-en-tl-C_001_007 | line-397 | 8 | 398.15 s–404.23 s | sige let your voice be heard by everyone |
| liva-en-tl-C_001_007 | line-511 | 5 | 488.63 s–489.26 s | yan wala akong nung wired |
| liva-en-tl-C_001_007 | line-535 | 3 | 502.22 s–504.22 s | madaming items jan |
| liva-en-tl-C_001_007 | line-553 | 6 | 523.59 s–525.07 s | tanginang snap hook yan ayaw mo |
| liva-en-tl-C_001_007 | line-567 | 5 | 530.79 s–534.54 s | yan yan tanginang yan wag |
| liva-en-tl-C_001_007 | line-585 | 3 | 551.26 s–555.48 s | wo wow paldo |
| liva-en-tl-C_001_007 | line-605 | 7 | 562.76 s–567.61 s | nood tayo oh nood tayo oh boy |
| liva-en-tl-C_001_007 | line-607 | 3 | 562.99 s–567.61 s | ay na leak |
| liva-en-tl-C_001_007 | line-613 | 7 | 569.26 s–571.92 s | tangina mamayang gabi mamayang gabi tapos comment |
| liva-en-tl-C_001_009 | line-5 | 8 | 2.23 s–27.20 s | joke lang mahigit kulang kulang ito wow na |
| liva-en-tl-C_001_009 | line-15 | 7 | 24.38 s–28.70 s | buckwheat ang binigay adjust san mo na |
| liva-en-tl-C_001_009 | line-25 | 7 | 32.41 s–35.48 s | men yung cat bed don't wag wag |
| liva-en-tl-C_001_009 | line-49 | 4 | 47.76 s–48.34 s | ayan na ah sa |
| liva-en-tl-C_001_009 | line-55 | 4 | 49.02 s–50.42 s | nag iba kasi ang |
| liva-en-tl-C_001_009 | line-69 | 3 | 55.86 s–58.88 s | naka save gago |
| liva-en-tl-C_001_009 | line-103 | 3 | 77.58 s–79.74 s | isang daliri ano |
| liva-en-tl-C_001_009 | line-115 | 10 | 92.32 s–100.34 s | hindi seven one wala ng maliit mali san oo naman |
| liva-en-tl-C_001_009 | line-135 | 7 | 110.76 s–113.42 s | ano yan tangina naman nag quit pa |
| liva-en-tl-C_001_009 | line-147 | 4 | 117.60 s–124.00 s | taas sa taas sa |
| liva-en-tl-C_001_009 | line-155 | 3 | 124.94 s–127.78 s | dati ano yun |
| liva-en-tl-C_001_009 | line-183 | 5 | 141.24 s–145.59 s | exit ko muna to oooohhh |
| liva-en-tl-C_001_009 | line-199 | 4 | 159.86 s–163.84 s | ay ano pwede kang |
| liva-en-tl-C_001_009 | line-211 | 3 | 173.12 s–174.24 s | hindi na hinihintay |
| liva-en-tl-C_001_009 | line-225 | 4 | 185.56 s–186.48 s | tandaan mo pa din |
| liva-en-tl-C_001_009 | line-243 | 3 | 199.16 s–201.38 s | kang mag accept |
| liva-en-tl-C_001_009 | line-247 | 3 | 200.35 s–200.84 s | ang dami pa |
| liva-en-tl-C_001_009 | line-317 | 10 | 258.94 s–261.62 s | yang pang rat eh eh ano yan guys stack ang |
| liva-en-tl-C_001_009 | line-371 | 7 | 304.78 s–309.52 s | running no kapag sumasama ako sa jump |
| liva-en-tl-C_001_009 | line-411 | 4 | 348.85 s–353.52 s | nung ano nya play |
| liva-en-tl-C_001_009 | line-425 | 3 | 367.47 s–368.47 s | kino connect uh |
| liva-en-tl-C_001_009 | line-457 | 7 | 381.87 s–382.37 s | pa lang kino connect ah oo punta |
| liva-en-tl-C_001_009 | line-461 | 5 | 382.10 s–386.94 s | ako dun ahhh oo hmmm |
| liva-en-tl-C_001_009 | line-497 | 3 | 402.68 s–406.34 s | libre nakita ko |
| liva-en-tl-C_001_009 | line-517 | 24 | 416.47 s–422.17 s | hoy hoy hoy hoy hoy baka ma ban tayo baka ma ban … (+12) |
| liva-en-tl-C_001_009 | line-537 | 4 | 426.09 s–430.40 s | jops ako'y magre recording |
| liva-en-tl-C_001_009 | line-555 | 9 | 437.35 s–440.59 s | ang buhay laruin kita laro tayo ah send ako |
| liva-en-tl-C_001_009 | line-581 | 7 | 455.67 s–457.79 s | boy ano na na ano na na |
| liva-en-tl-C_001_009 | line-595 | 12 | 462.88 s–465.56 s | jops may may may 5 5 dollars pa ako 9 night or |
| liva-en-tl-C_001_009 | line-609 | 5 | 467.65 s–468.49 s | may 5 dollars pa ako |
| liva-en-tl-C_001_009 | line-613 | 5 | 469.44 s–472.24 s | pa oo 5 dollars mas |
| liva-en-tl-C_001_009 | line-625 | 12 | 474.48 s–476.14 s | wait kita mo naman kita mo naman ang loot ko eh nine |
| liva-en-tl-C_001_009 | line-631 | 9 | 478.17 s–479.18 s | ari nag leader clinick ko yung leaderboards ang sarap |
| liva-en-tl-C_001_009 | line-635 | 10 | 479.97 s–481.57 s | 1 ka na oo si si si jops pa rin |
| liva-en-tl-C_001_009 | line-649 | 8 | 486.04 s–494.71 s | putang ina oo tangina ang daya ah kanina |
| liva-en-tl-C_001_009 | line-655 | 24 | 489.38 s–497.33 s | yan yeah titingnan naten right i ano mo nga hindi pero ara … (+12) |
| liva-en-tl-C_001_009 | line-665 | 15 | 496.56 s–501.93 s | mo yan ma ca cash out pacheck mo nga h pacheck nga … (+3) |
| liva-en-tl-C_001_009 | line-679 | 8 | 504.97 s–505.77 s | ito ko pa na aano mamaya ako tangina |
| liva-en-tl-C_001_009 | line-685 | 3 | 505.33 s–505.86 s | good luck boss |
| liva-en-tl-C_001_009 | line-689 | 7 | 509.48 s–518.49 s | wav tangina wag naman malala nababawasan minsan |
| liva-en-tl-C_001_009 | line-751 | 3 | 544.50 s–545.74 s | ay sya papa |
| liva-en-tl-C_001_009 | line-753 | 4 | 547.09 s–548.99 s | sya palagay ng ano |
| liva-en-tl-C_001_009 | line-755 | 9 | 547.28 s–550.81 s | eeehhh sing hello po masaya akong pumapaldo si joco |
| liva-en-tl-C_001_009 | line-765 | 5 | 550.27 s–554.30 s | refer eh eh si woover |
| liva-en-tl-C_001_009 | line-791 | 8 | 567.48 s–571.85 s | journey asan ba ang mga sige ang naghiwalay |
| liva-en-tl-C_001_009 | line-803 | 5 | 572.13 s–574.83 s | mamaya oo naghiwalay wa wag |
| liva-en-tl-C_001_009 | line-819 | 3 | 579.12 s–582.05 s | mic stand ulol |
| liva-en-tl-C_001_009 | line-823 | 3 | 581.20 s–582.38 s | dam battlegrounds rinig |
| liva-en-tl-C_001_009 | line-843 | 4 | 594.90 s–596.94 s | play mo lang oo |
| liva-en-tl-C_001_015 | line-1 | 3 | 0.60 s–2.11 s | bakit anong bakit |
| liva-en-tl-C_001_015 | line-11 | 3 | 2.72 s–4.20 s | why why hayop |
| liva-en-tl-C_001_015 | line-17 | 12 | 4.95 s–8.68 s | your confirmed pagod even if it's turn back in tagalog why why |
| liva-en-tl-C_001_015 | line-57 | 4 | 20.92 s–26.30 s | tatanga eh tripod bakit |
| liva-en-tl-C_001_015 | line-73 | 3 | 29.98 s–31.33 s | shield field depot |
| liva-en-tl-C_001_015 | line-79 | 3 | 31.66 s–35.78 s | ano pa to |
| liva-en-tl-C_001_015 | line-91 | 5 | 46.99 s–48.93 s | dali ng services ng approved |
| liva-en-tl-C_001_015 | line-119 | 4 | 67.14 s–67.79 s | ba't ka anjan bili |
| liva-en-tl-C_001_015 | line-131 | 7 | 74.30 s–76.41 s | ang lakas ng pagsabog narinig sa bahaging |
| liva-en-tl-C_001_015 | line-135 | 4 | 76.66 s–77.64 s | pano mo nacheck yun |
| liva-en-tl-C_001_015 | line-143 | 8 | 81.85 s–85.29 s | sabihin mo sit fruits of your labor wow |
| liva-en-tl-C_001_015 | line-153 | 16 | 87.31 s–92.57 s | jops tang inang yan easy ka lang boy basta may masabi putang … (+4) |
| liva-en-tl-C_001_015 | line-173 | 5 | 94.54 s–97.20 s | ang lala ewa ewa ewan |
| liva-en-tl-C_001_015 | line-209 | 5 | 108.77 s–112.21 s | eh no kailangan mo pa |
| liva-en-tl-C_001_015 | line-227 | 4 | 113.44 s–114.28 s | kailangan pang i announce |
| liva-en-tl-C_001_015 | line-231 | 9 | 115.61 s–122.32 s | di ba naku babagsak na yun oy ang galing |
| liva-en-tl-C_001_015 | line-241 | 13 | 119.65 s–124.82 s | ito gusto ko to ayun oh o di ga gara yan p're … (+1) |
| liva-en-tl-C_001_015 | line-261 | 3 | 127.47 s–133.03 s | oh ako yung |
| liva-en-tl-C_001_015 | line-271 | 3 | 140.47 s–140.75 s | the fuck eh |
| liva-en-tl-C_001_015 | line-285 | 10 | 152.17 s–161.57 s | o no cloak general low general yon blue sa yeah |
| liva-en-tl-C_001_015 | line-291 | 3 | 160.30 s–163.06 s | eh ano ang |
| liva-en-tl-C_001_015 | line-301 | 8 | 168.05 s–170.16 s | mamaya mamaya mawawala na naman ako sa discord |
| liva-en-tl-C_001_015 | line-309 | 8 | 175.85 s–177.56 s | tayo babalik dapat ako'y nag upgrade ng ano |
| liva-en-tl-C_001_015 | line-333 | 9 | 201.34 s–202.64 s | i ride join me in the ship don't know |
| liva-en-tl-C_001_015 | line-341 | 5 | 211.22 s–214.22 s | cornered now stop me not |
| liva-en-tl-C_001_015 | line-347 | 3 | 217.46 s–223.84 s | na gumagawa ka |
| liva-en-tl-C_001_015 | line-351 | 7 | 222.72 s–224.54 s | agad ng ace ang gahaman nito ah |
| liva-en-tl-C_001_015 | line-357 | 5 | 225.24 s–227.10 s | gahaman nitong teammate na to |
| liva-en-tl-C_001_015 | line-381 | 3 | 244.14 s–245.33 s | ka eh nag |
| liva-en-tl-C_001_015 | line-401 | 5 | 265.50 s–268.12 s | congratulation you just found 997 |
| liva-en-tl-C_001_015 | line-407 | 12 | 270.03 s–275.21 s | ga game fifty what the fuck oo si minion na lang ina |
| liva-en-tl-C_001_015 | line-421 | 3 | 285.17 s–286.77 s | ah bobo ka |
| liva-en-tl-C_001_015 | line-429 | 3 | 289.56 s–290.06 s | ah ano nga |
| liva-en-tl-C_001_015 | line-435 | 7 | 296.12 s–298.49 s | wag mong sabihing hindi pangit niyo eh |
| liva-en-tl-C_001_015 | line-443 | 6 | 301.59 s–311.67 s | what the oh may sensor disability |
| liva-en-tl-C_001_015 | line-449 | 5 | 310.14 s–313.88 s | osob meatballs circles nasa may |
| liva-en-tl-C_001_015 | line-467 | 3 | 319.97 s–320.64 s | anong flowed map |
| liva-en-tl-C_001_015 | line-493 | 6 | 331.99 s–336.25 s | ay sila pala yan meron si |
| liva-en-tl-C_001_015 | line-497 | 12 | 333.90 s–340.67 s | ano mina tohakwa basta may interaction basta may interaction no asakano ganyan |
| liva-en-tl-C_001_015 | line-507 | 11 | 338.17 s–344.74 s | sa bleep app gago may napindot akong guts tangina niyo di |
| liva-en-tl-C_001_015 | line-545 | 6 | 355.68 s–360.55 s | soldier corners at streetways ay sayang |
| liva-en-tl-C_001_015 | line-561 | 5 | 366.86 s–372.56 s | pang tang ina kang trap |
| liva-en-tl-C_001_015 | line-587 | 14 | 379.10 s–389.63 s | ano ba't mania ahhh kaliwa gago ano yan ba't ganyan ba't ganyan … (+2) |
| liva-en-tl-C_001_015 | line-617 | 4 | 394.73 s–397.64 s | ano yun oh ba't |
| liva-en-tl-C_001_015 | line-627 | 5 | 398.87 s–399.15 s | ikaw ang nakaka hit wala |
| liva-en-tl-C_001_015 | line-639 | 3 | 403.95 s–405.34 s | oh one yung |
| liva-en-tl-C_001_015 | line-647 | 6 | 411.02 s–412.46 s | masasapok na tayo ni hadji ayon |
| liva-en-tl-C_001_015 | line-655 | 4 | 415.58 s–419.65 s | e eks ilang minutes |
| liva-en-tl-C_001_015 | line-683 | 24 | 432.79 s–437.99 s | rj 1280x720 oo nga kulang sa stamina sayang i need a stamina … (+12) |
| liva-en-tl-C_001_015 | line-703 | 3 | 443.88 s–446.66 s | lagi ka na |
| liva-en-tl-C_001_015 | line-707 | 4 | 449.30 s–450.00 s | ang hirap naman nito |
| liva-en-tl-C_001_015 | line-711 | 3 | 451.38 s–455.28 s | napuputot ako ah |
| liva-en-tl-C_001_015 | line-725 | 3 | 458.95 s–459.92 s | oo ha ha |
| liva-en-tl-C_001_015 | line-781 | 4 | 485.69 s–489.85 s | ay hindi ba maka |
| liva-en-tl-C_001_015 | line-783 | 3 | 486.86 s–488.97 s | ang tanga kasi |
| liva-en-tl-C_001_015 | line-785 | 10 | 488.61 s–494.35 s | galing nga eh oh ohhhh grabe lo galing galing galing |
| liva-en-tl-C_001_015 | line-795 | 6 | 493.59 s–497.58 s | ngayon oo oh sayang sayang sayang |
| liva-en-tl-C_001_015 | line-817 | 9 | 500.58 s–504.14 s | eh tang ina anong ako anong ako ang ingay |
| liva-en-tl-C_001_015 | line-891 | 3 | 535.47 s–538.22 s | na lang yun |
| liva-en-tl-C_001_015 | line-891 | 3 | 535.47 s–538.22 s | ano kina catch |
| liva-en-tl-C_001_015 | line-895 | 3 | 538.93 s–541.10 s | na catch na |
| liva-en-tl-C_001_015 | line-911 | 8 | 545.65 s–548.74 s | ng ano paano ba to pabilisin pang ar |
| liva-en-tl-C_001_015 | line-931 | 4 | 561.46 s–562.19 s | aba hindi ko tanda |
| liva-en-tl-C_001_015 | line-935 | 9 | 562.79 s–565.57 s | kini click kina catch yan dito ah he ah |
| liva-en-tl-C_001_015 | line-959 | 7 | 575.08 s–577.64 s | ano orange maraming banana no tang ina |
| liva-en-tl-C_001_015 | line-981 | 3 | 585.38 s–592.52 s | new year salad |
| liva-en-tl-C_001_015 | line-987 | 6 | 587.72 s–591.50 s | eh may straw may strawberry may |
| liva-en-tl-C_001_015 | line-997 | 5 | 595.90 s–597.46 s | pero nakain si marine ay |
| liva-en-tl-C_001_016 | line-5 | 4 | 0.81 s–5.60 s | ahhh hmp uy ayun |
| liva-en-tl-C_001_016 | line-17 | 4 | 7.49 s–14.13 s | ng ano ano ba |
| liva-en-tl-C_001_016 | line-17 | 10 | 7.49 s–15.74 s | ari ano over hindi ako baka ikaw ano jo jowa |
| liva-en-tl-C_001_016 | line-69 | 13 | 34.91 s–35.79 s | boy ang ganda nung yun oh yun oh type ko type ko … (+1) |
| liva-en-tl-C_001_016 | line-79 | 12 | 39.28 s–44.20 s | di ba paldo ooohh ganun talaga daga yun sa fil sa eh |
| liva-en-tl-C_001_016 | line-89 | 8 | 46.74 s–50.04 s | nice one 59 pesos oo nga boss oo |
| liva-en-tl-C_001_016 | line-99 | 9 | 53.06 s–56.90 s | oo ah oo nga boss tama yes yes omsim |
| liva-en-tl-C_001_016 | line-109 | 7 | 56.83 s–62.69 s | oh tangina ang angas oo oo kaya |
| liva-en-tl-C_001_016 | line-113 | 5 | 60.92 s–65.93 s | yes boss yes boss oh |
| liva-en-tl-C_001_016 | line-119 | 8 | 66.70 s–67.49 s | oh di ba di ba pokemon cards oh |
| liva-en-tl-C_001_016 | line-143 | 6 | 77.26 s–84.88 s | pwede tangina naman tong hayop pinaghirapan |
| liva-en-tl-C_001_016 | line-151 | 3 | 81.08 s–83.61 s | ng isang si |
| liva-en-tl-C_001_016 | line-157 | 4 | 85.38 s–89.44 s | card tanginang yan pinokemon |
| liva-en-tl-C_001_016 | line-239 | 9 | 134.45 s–135.94 s | ang galing ah pang shoot bigla ng baril ano |
| liva-en-tl-C_001_016 | line-251 | 3 | 143.11 s–144.07 s | ano ang pwe |
| liva-en-tl-C_001_016 | line-259 | 5 | 145.95 s–148.05 s | si don't shoot mga iba |
| liva-en-tl-C_001_016 | line-269 | 3 | 150.27 s–151.64 s | yes ang lala |
| liva-en-tl-C_001_016 | line-275 | 3 | 152.70 s–154.60 s | ah oo hindi |
| liva-en-tl-C_001_016 | line-281 | 7 | 155.54 s–169.58 s | tama tama si bro ang lala anong |
| liva-en-tl-C_001_016 | line-291 | 16 | 163.32 s–169.01 s | hadji my pc tang ina baka sadyang nag s stream oh my … (+4) |
| liva-en-tl-C_001_016 | line-295 | 5 | 165.23 s–172.42 s | niya ulit my p nagla |
| liva-en-tl-C_001_016 | line-303 | 6 | 169.30 s–170.49 s | kaya pala nag lag ang ano |
| liva-en-tl-C_001_016 | line-311 | 6 | 174.20 s–177.37 s | na kaawa awa eh pano naman |
| liva-en-tl-C_001_016 | line-319 | 5 | 180.35 s–181.22 s | tapos nanonod pa ng gp |
| liva-en-tl-C_001_016 | line-327 | 3 | 187.64 s–190.32 s | nga yon alin |
| liva-en-tl-C_001_016 | line-361 | 12 | 208.98 s–214.41 s | six seven six seven six seven six seven six seven kaya nga |
| liva-en-tl-C_001_016 | line-387 | 4 | 225.37 s–226.14 s | karaoke party okay yan |
| liva-en-tl-C_001_016 | line-399 | 6 | 229.47 s–231.43 s | ano tayo magkakantahan tayo ano to |
| liva-en-tl-C_001_016 | line-403 | 21 | 230.84 s–241.05 s | kantahan kantahan kantahan kantahan kantahan may karaoke ba jan ha ano to … (+9) |
| liva-en-tl-C_001_016 | line-429 | 3 | 240.35 s–242.79 s | putang ina ano |
| liva-en-tl-C_001_016 | line-431 | 18 | 241.43 s–253.65 s | lang tang ina ha hello hello hello tang ina di ba't bawal … (+6) |
| liva-en-tl-C_001_016 | line-461 | 3 | 257.07 s–262.18 s | ge wag na |
| liva-en-tl-C_001_016 | line-461 | 5 | 257.07 s–259.46 s | ulit tayo uwe hindi pwede |
| liva-en-tl-C_001_016 | line-471 | 8 | 260.63 s–265.19 s | ba pwede waiting for the host anong i |
| liva-en-tl-C_001_016 | line-485 | 10 | 268.25 s–270.09 s | wait wait kapag na void down ah ari ari ari |
| liva-en-tl-C_001_016 | line-495 | 8 | 270.77 s–274.50 s | layers oo ikaw ang ano anong gagawin ko |
| liva-en-tl-C_001_016 | line-507 | 5 | 279.03 s–279.96 s | ano na naman yan oo |
| liva-en-tl-C_001_016 | line-513 | 10 | 281.38 s–286.20 s | wala hindi i x mo lang yan hindi meron ma |
| liva-en-tl-C_001_016 | line-523 | 4 | 290.30 s–294.94 s | wala kailangan mo i |
| liva-en-tl-C_001_016 | line-525 | 3 | 290.91 s–294.94 s | yan may pindotan |
| liva-en-tl-C_001_016 | line-533 | 14 | 298.68 s–303.68 s | my pc full cream ano to anong pinag gagawa niyo dito my … (+2) |
| liva-en-tl-C_001_016 | line-545 | 5 | 305.46 s–306.33 s | pindotin mo yang full screen |
| liva-en-tl-C_001_016 | line-553 | 7 | 309.38 s–313.08 s | nga yung full screen ano dito loading |
| liva-en-tl-C_001_016 | line-563 | 3 | 316.16 s–317.48 s | hindi ko din |
| liva-en-tl-C_001_016 | line-563 | 3 | 316.16 s–318.11 s | din makita anyare |
| liva-en-tl-C_001_016 | line-571 | 7 | 319.27 s–324.30 s | wait wait hindi hindi hindi ano ay |
| liva-en-tl-C_001_016 | line-579 | 9 | 322.78 s–326.89 s | ilalaro okay meron jan tingnan natin tingnan natin tingnan |
| liva-en-tl-C_001_016 | line-617 | 3 | 348.40 s–349.51 s | hoy pwede to |
| liva-en-tl-C_001_016 | line-619 | 10 | 348.90 s–351.15 s | battle tops pwede to laughing kaso dalawahan lang ano yan |
| liva-en-tl-C_001_016 | line-631 | 5 | 353.56 s–354.23 s | di ko alam kung dalawahan |
| liva-en-tl-C_001_016 | line-633 | 13 | 354.14 s–359.40 s | to minecraft yun la ang hindi 1 to 20 1 to 20 … (+1) |
| liva-en-tl-C_001_016 | line-647 | 3 | 361.96 s–364.09 s | nga anong ginagawa |
| liva-en-tl-C_001_016 | line-653 | 4 | 364.67 s–365.21 s | hindi ko nga rin |
| liva-en-tl-C_001_016 | line-661 | 6 | 374.01 s–382.13 s | ganun magpaparamihan kayo ng troops ayun |
| liva-en-tl-C_001_016 | line-683 | 10 | 391.35 s–394.80 s | ah ah stop time to react wish your battle continue |
| liva-en-tl-C_001_016 | line-695 | 3 | 401.43 s–403.96 s | pinindot ko ang |
| liva-en-tl-C_001_016 | line-697 | 4 | 401.52 s–403.24 s | battle discord yung discord |
| liva-en-tl-C_001_016 | line-717 | 9 | 416.62 s–420.66 s | nag send sino pa ba mag i invite okay |
| liva-en-tl-C_001_016 | line-731 | 4 | 425.69 s–429.09 s | eh yan na ba |
| liva-en-tl-C_001_016 | line-759 | 3 | 442.64 s–446.08 s | ah oo ano |
| liva-en-tl-C_001_016 | line-769 | 4 | 451.54 s–454.05 s | na tayo eh ayan |
| liva-en-tl-C_001_016 | line-771 | 7 | 452.98 s–453.94 s | nga tayo paano nga yun kaya nga |
| liva-en-tl-C_001_016 | line-791 | 9 | 470.65 s–474.00 s | normal meron ai ge ikaw na ikaw boy ikaw |
| liva-en-tl-C_001_016 | line-825 | 4 | 487.96 s–493.02 s | change fleet putang ina |
| liva-en-tl-C_001_016 | line-833 | 5 | 497.88 s–498.83 s | battle ships to iba pala |
| liva-en-tl-C_001_016 | line-847 | 6 | 507.47 s–509.44 s | eh dalawahan lang hindi ko ge |
| liva-en-tl-C_001_016 | line-849 | 4 | 507.94 s–509.35 s | rin gets gago ito |
| liva-en-tl-C_001_016 | line-877 | 11 | 527.24 s–528.85 s | ay alam niyo yung code names online sobrang ligaw ko dine |
| liva-en-tl-C_001_016 | line-901 | 8 | 545.10 s–550.23 s | sa but there is spam in what kind |
| liva-en-tl-C_001_016 | line-915 | 16 | 558.60 s–559.83 s | ano to anong tong time ni ruel time ni ruel zombie in … (+4) |
| liva-en-tl-C_001_016 | line-923 | 8 | 565.93 s–566.91 s | a apat ano to s s ay gago |
| liva-en-tl-C_001_016 | line-933 | 4 | 569.30 s–570.17 s | hindi hindi hindi lahat |
| liva-en-tl-C_001_016 | line-939 | 3 | 571.48 s–574.45 s | a ari ga |
| liva-en-tl-C_001_016 | line-947 | 4 | 582.63 s–586.63 s | carts ari oh 1 |
| liva-en-tl-C_001_016 | line-957 | 9 | 589.71 s–591.26 s | ay ayan oh ayan oh ayan ah hindi ah |
| liva-en-tl-C_001_016 | line-963 | 3 | 590.08 s–592.48 s | ay lima ba |
| liva-en-tl-C_001_016 | line-967 | 3 | 594.86 s–595.78 s | pili kayong team |
| liva-en-tl-C_001_016 | line-975 | 4 | 598.78 s–600.02 s | walang class ay hindi |

Missing speech (reference regions of at least 1.00 s with less than 20% covered by hypothesis words, padded 200 ms): 14 of 486 regions, 19.20 s of 1249.66 s checked speech (1.54%), in 4 item(s). Uncovered speech in all checked regions: 181.62 s.

| Item | Region | Covered | Utterances |
| --- | --- | ---: | --- |
| liva-en-tl-C_001_007 | 420.55 s–422.71 s | 0% | line-421, line-423 |
| liva-en-tl-C_001_007 | 425.60 s–427.58 s | 0% | line-429 |
| liva-en-tl-C_001_007 | 530.79 s–532.26 s | 0% | line-567, line-569 |
| liva-en-tl-C_001_009 | 308.27 s–309.52 s | 0% | line-375 |
| liva-en-tl-C_001_015 | 19.60 s–20.65 s | 0% | line-53, line-55 |
| liva-en-tl-C_001_015 | 158.51 s–159.56 s | 0% | line-289 |
| liva-en-tl-C_001_015 | 222.72 s–224.54 s | 5.5% | line-351, line-353 |
| liva-en-tl-C_001_015 | 266.96 s–268.12 s | 0% | line-405 |
| liva-en-tl-C_001_015 | 321.78 s–322.96 s | 0% | line-475 |
| liva-en-tl-C_001_015 | 346.81 s–348.46 s | 0% | line-521 |
| liva-en-tl-C_001_016 | 49.75 s–50.83 s | 0% | line-91, line-93 |
| liva-en-tl-C_001_016 | 246.59 s–247.63 s | 0% | line-439 |
| liva-en-tl-C_001_016 | 298.68 s–299.92 s | 0% | line-533, line-535 |
| liva-en-tl-C_001_016 | 452.98 s–454.05 s | 0% | line-771, line-773 |

## Performance

Four different figures. A smaller process footprint is not a smaller model: the model's Neural Engine memory is not in the footprint.

| Item | Whole-file RTF (offline) | Live commit latency | Process peak footprint | Model residency |
| --- | --- | --- | --- | --- |
| **Corpus** | 0.614 | | | |
| liva-en-tl-C_001_007 | 0.566 | unavailable: an offline run has no commit latency | 262 MB | 3000 MB |
| liva-en-tl-C_001_009 | 0.608 | unavailable: an offline run has no commit latency | 266 MB | 3000 MB |
| liva-en-tl-C_001_015 | 0.603 | unavailable: an offline run has no commit latency | 273 MB | 3000 MB |
| liva-en-tl-C_001_016 | 0.680 | unavailable: an offline run has no commit latency | 271 MB | 3000 MB |

## Items

| Item | Category | WER | CER | N | Sub | Del | Ins |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| liva-en-tl-C_001_007 | mixed | 62.24% | 46.49% | 1017 | 414 | 163 | 56 |
| liva-en-tl-C_001_009 | mixed | 59.29% | 44.37% | 1474 | 407 | 445 | 22 |
| liva-en-tl-C_001_015 | mixed | 70.18% | 57.21% | 1405 | 483 | 492 | 11 |
| liva-en-tl-C_001_016 | mixed | 66.73% | 53.34% | 1641 | 431 | 639 | 25 |

## Utterances

| Item | Utterance | Language | Speaker | Overlap | Time | WER | CER | N | Sub | Del | Ins |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| liva-en-tl-C_001_007 | line-5 | code-switched | Speaker 5 | no | 2.47 s–2.73 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-9 | code-switched | Speaker 1 | no | 4.66 s–5.10 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-11 | code-switched | Speaker 1 | no | 5.68 s–9.66 s | 62.50% | 28.09% | 16 | 7 | 2 | 1 |
| liva-en-tl-C_001_007 | line-19 | code-switched | Speaker 1 | no | 12.26 s–13.76 s | 33.33% | 12.50% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-21 | code-switched | Speaker 1 | no | 16.07 s–18.54 s | 61.54% | 31.75% | 13 | 5 | 2 | 1 |
| liva-en-tl-C_001_007 | line-27 | code-switched | Speaker 1 | no | 23.98 s–25.23 s | 60.00% | 50.00% | 5 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-29 | code-switched | Speaker 5 | no | 25.85 s–26.11 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-33 | code-switched | Speaker 5 | yes | 28.43 s–29.21 s | 33.33% | 5.88% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-35 | code-switched | Speaker 1 | yes | 29.12 s–31.10 s | 28.57% | 18.52% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-37 | code-switched | Speaker 5 | no | 31.97 s–32.54 s | 50.00% | 8.33% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-39 | code-switched | Speaker 3 | no | 32.95 s–34.29 s | 75.00% | 50.00% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-41 | code-switched | Speaker 1 | no | 34.77 s–35.59 s | 33.33% | 17.65% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-43 | code-switched | Speaker 1 | no | 37.06 s–37.36 s | 50.00% | 25.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-47 | code-switched | Speaker 1 | no | 39.38 s–41.50 s | 33.33% | 6.06% | 6 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-49 | code-switched | Speaker 1 | no | 43.10 s–44.54 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-51 | code-switched | Speaker 1 | no | 45.08 s–46.30 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-53 | code-switched | Speaker 1 | no | 47.91 s–48.68 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-55 | code-switched | Speaker 1 | no | 49.62 s–49.92 s | 100.00% | 80.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-57 | code-switched | Speaker 1 | no | 50.74 s–52.20 s | 100.00% | 91.67% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-61 | code-switched | Speaker 5 | no | 54.65 s–54.88 s | 100.00% | 87.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-63 | code-switched | Speaker 1 | no | 54.94 s–56.36 s | 100.00% | 66.67% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-65 | code-switched | Speaker 1 | no | 57.25 s–58.30 s | 100.00% | 72.41% | 5 | 5 | 0 | 0 |
| liva-en-tl-C_001_007 | line-69 | code-switched | Speaker 3 | no | 59.94 s–62.61 s | 62.50% | 32.65% | 8 | 5 | 0 | 0 |
| liva-en-tl-C_001_007 | line-73 | code-switched | Speaker 3 | no | 63.63 s–64.98 s | 60.00% | 19.35% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-75 | code-switched | Speaker 1 | no | 67.19 s–70.56 s | 55.56% | 36.00% | 9 | 3 | 1 | 1 |
| liva-en-tl-C_001_007 | line-77 | code-switched | Speaker 1 | no | 72.36 s–73.22 s | 100.00% | 77.78% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-79 | code-switched | Speaker 1 | no | 83.94 s–85.04 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-83 | code-switched | Speaker 1 | no | 86.29 s–88.08 s | 60.00% | 34.62% | 5 | 2 | 0 | 1 |
| liva-en-tl-C_001_007 | line-85 | code-switched | Speaker 1 | no | 88.85 s–90.08 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-87 | code-switched | Speaker 1 | no | 95.22 s–96.57 s | 100.00% | 19.05% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-89 | code-switched | Speaker 1 | no | 110.26 s–112.82 s | 53.85% | 34.48% | 13 | 6 | 1 | 0 |
| liva-en-tl-C_001_007 | line-91 | code-switched | Speaker 1 | no | 113.32 s–114.52 s | 40.00% | 16.67% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-93 | code-switched | Speaker 5 | no | 115.28 s–116.37 s | 50.00% | 39.13% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-97 | code-switched | Speaker 3 | no | 117.47 s–120.35 s | 33.33% | 20.00% | 9 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-99 | code-switched | Speaker 3 | no | 121.41 s–121.95 s | 100.00% | 85.71% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-101 | code-switched | Speaker 1 | yes | 130.28 s–130.97 s | 100.00% | 72.73% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-103 | code-switched | Speaker 3 | yes | 130.49 s–132.46 s | 25.00% | 9.09% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-105 | code-switched | Speaker 3 | no | 132.99 s–133.65 s | 66.67% | 27.27% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-109 | code-switched | Speaker 3 | no | 135.04 s–136.27 s | 100.00% | 90.91% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-111 | code-switched | Speaker 3 | no | 136.94 s–137.57 s | 100.00% | 58.82% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-113 | code-switched | Speaker 1 | no | 141.53 s–143.26 s | 66.67% | 26.67% | 6 | 3 | 1 | 0 |
| liva-en-tl-C_001_007 | line-117 | code-switched | Speaker 6 | no | 145.83 s–147.05 s | 40.00% | 23.08% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-123 | code-switched | Speaker 3 | no | 149.99 s–150.23 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-127 | code-switched | Speaker 1 | no | 158.78 s–160.38 s | 20.00% | 20.83% | 5 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-133 | code-switched | Speaker 1 | no | 161.90 s–162.53 s | 100.00% | 92.31% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-137 | code-switched | Speaker 5 | no | 166.30 s–167.07 s | 66.67% | 76.92% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-139 | code-switched | Speaker 1 | no | 168.23 s–168.49 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-141 | code-switched | Speaker 3 | yes | 169.14 s–172.91 s | 50.00% | 44.23% | 12 | 4 | 1 | 1 |
| liva-en-tl-C_001_007 | line-145 | code-switched | Speaker 5 | yes | 169.48 s–169.59 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-151 | code-switched | Speaker 1 | yes | 171.49 s–172.57 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_007 | line-153 | code-switched | Speaker 1 | yes | 173.19 s–173.34 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-155 | code-switched | Speaker 5 | yes | 173.21 s–173.52 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-157 | code-switched | Speaker 5 | no | 175.06 s–176.21 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-159 | code-switched | Speaker 1 | no | 176.32 s–177.43 s | 20.00% | 15.38% | 5 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-163 | code-switched | Speaker 3 | yes | 177.77 s–179.02 s | 42.86% | 16.13% | 7 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-165 | code-switched | Speaker 6 | yes | 177.94 s–178.49 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_007 | line-167 | code-switched | Speaker 5 | yes | 178.22 s–178.60 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-169 | code-switched | Speaker 3 | no | 179.61 s–181.58 s | 0.00% | 0.00% | 7 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-171 | code-switched | Speaker 3 | no | 182.59 s–184.31 s | 55.56% | 37.21% | 9 | 5 | 0 | 0 |
| liva-en-tl-C_001_007 | line-175 | code-switched | Speaker 5 | no | 186.10 s–189.01 s | 42.86% | 14.81% | 14 | 5 | 0 | 1 |
| liva-en-tl-C_001_007 | line-177 | code-switched | Speaker 3 | no | 190.64 s–191.94 s | 57.14% | 30.77% | 7 | 3 | 1 | 0 |
| liva-en-tl-C_001_007 | line-181 | code-switched | Speaker 5 | no | 193.92 s–195.06 s | 20.00% | 15.38% | 5 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-183 | code-switched | Speaker 5 | yes | 196.93 s–201.61 s | 30.00% | 16.04% | 20 | 3 | 2 | 1 |
| liva-en-tl-C_001_007 | line-185 | code-switched | Speaker 3 | yes | 197.50 s–197.73 s | 100.00% | 80.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-187 | code-switched | Speaker 5 | no | 202.26 s–203.37 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-191 | code-switched | Speaker 6 | no | 208.70 s–209.35 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_007 | line-195 | code-switched | Speaker 1 | no | 215.20 s–217.96 s | 44.44% | 29.27% | 9 | 3 | 1 | 0 |
| liva-en-tl-C_001_007 | line-199 | code-switched | Speaker 1 | no | 220.98 s–221.58 s | 100.00% | 40.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-201 | code-switched | Speaker 3 | no | 221.99 s–222.44 s | 100.00% | 42.86% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-205 | code-switched | Speaker 1 | no | 223.24 s–224.39 s | 40.00% | 22.73% | 5 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-207 | code-switched | Speaker 3 | no | 225.10 s–225.50 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-211 | code-switched | Speaker 1 | yes | 226.51 s–227.37 s | 100.00% | 69.23% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-213 | code-switched | Speaker 5 | yes | 226.69 s–226.88 s | 100.00% | 112.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-215 | code-switched | Speaker 3 | no | 227.98 s–228.48 s | 50.00% | 50.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-217 | code-switched | Speaker 1 | no | 228.59 s–230.21 s | 57.14% | 42.42% | 7 | 3 | 1 | 0 |
| liva-en-tl-C_001_007 | line-221 | code-switched | Speaker 3 | no | 231.85 s–232.21 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-223 | code-switched | Speaker 1 | no | 232.90 s–236.31 s | 16.67% | 7.94% | 12 | 1 | 0 | 1 |
| liva-en-tl-C_001_007 | line-227 | code-switched | Speaker 1 | no | 237.21 s–237.82 s | 50.00% | 27.27% | 2 | 0 | 0 | 1 |
| liva-en-tl-C_001_007 | line-229 | code-switched | Speaker 1 | no | 238.52 s–240.32 s | 100.00% | 22.58% | 5 | 2 | 0 | 3 |
| liva-en-tl-C_001_007 | line-235 | code-switched | Speaker 5 | no | 241.84 s–242.55 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-241 | code-switched | Speaker 1 | no | 243.22 s–243.82 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-243 | code-switched | Speaker 3 | no | 245.55 s–247.41 s | 71.43% | 52.78% | 7 | 2 | 3 | 0 |
| liva-en-tl-C_001_007 | line-253 | code-switched | Speaker 5 | no | 253.12 s–254.27 s | 87.50% | 44.44% | 8 | 6 | 0 | 1 |
| liva-en-tl-C_001_007 | line-257 | code-switched | Speaker 1 | no | 258.74 s–261.92 s | 0.00% | 0.00% | 8 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-259 | code-switched | Speaker 1 | no | 263.02 s–265.96 s | 66.67% | 31.25% | 6 | 2 | 0 | 2 |
| liva-en-tl-C_001_007 | line-263 | code-switched | Speaker 5 | no | 270.80 s–272.56 s | 50.00% | 15.79% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-265 | code-switched | Speaker 1 | no | 275.97 s–276.49 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-267 | code-switched | Speaker 5 | no | 278.02 s–278.40 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-269 | code-switched | Speaker 5 | no | 280.39 s–280.91 s | 100.00% | 87.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-273 | code-switched | Speaker 5 | no | 288.72 s–289.27 s | 100.00% | 38.46% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-275 | code-switched | Speaker 3 | no | 291.66 s–291.95 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-279 | code-switched | Speaker 1 | no | 303.74 s–306.62 s | 85.71% | 33.33% | 7 | 4 | 0 | 2 |
| liva-en-tl-C_001_007 | line-281 | code-switched | Speaker 1 | no | 307.98 s–309.70 s | 16.67% | 13.79% | 6 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-285 | code-switched | Speaker 1 | no | 310.84 s–312.92 s | 42.86% | 37.50% | 7 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-287 | code-switched | Speaker 1 | no | 314.08 s–314.50 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-289 | code-switched | Speaker 1 | no | 316.47 s–323.47 s | 38.89% | 14.71% | 18 | 5 | 2 | 0 |
| liva-en-tl-C_001_007 | line-295 | code-switched | Speaker 5 | no | 327.24 s–328.53 s | 100.00% | 32.00% | 5 | 4 | 1 | 0 |
| liva-en-tl-C_001_007 | line-297 | code-switched | Speaker 5 | no | 329.39 s–330.20 s | 100.00% | 57.14% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-299 | code-switched | Speaker 1 | no | 331.72 s–334.58 s | 54.55% | 29.31% | 11 | 5 | 1 | 0 |
| liva-en-tl-C_001_007 | line-301 | code-switched | Speaker 1 | no | 336.14 s–337.34 s | 50.00% | 42.86% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-307 | code-switched | Speaker 3 | no | 338.10 s–338.71 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-311 | code-switched | Speaker 3 | no | 339.88 s–340.67 s | 50.00% | 53.85% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-315 | code-switched | Speaker 6 | no | 341.29 s–341.56 s | 100.00% | 85.71% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-319 | code-switched | Speaker 3 | yes | 342.15 s–343.40 s | 83.33% | 82.86% | 6 | 0 | 5 | 0 |
| liva-en-tl-C_001_007 | line-321 | code-switched | Speaker 1 | yes | 342.41 s–342.85 s | 100.00% | 92.31% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-325 | code-switched | Speaker 1 | no | 344.27 s–346.22 s | 40.00% | 30.00% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-327 | code-switched | Speaker 3 | yes | 347.24 s–350.18 s | 50.00% | 72.00% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-329 | code-switched | Speaker 1 | yes | 347.50 s–349.35 s | 100.00% | 100.00% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_007 | line-333 | code-switched | Speaker 3 | no | 353.16 s–353.59 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-337 | code-switched | Speaker 3 | no | 354.81 s–355.21 s | 100.00% | 75.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-341 | code-switched | Speaker 1 | no | 358.92 s–362.50 s | 72.73% | 32.00% | 11 | 6 | 2 | 0 |
| liva-en-tl-C_001_007 | line-347 | code-switched | Speaker 1 | no | 363.84 s–365.68 s | 80.00% | 32.14% | 5 | 2 | 2 | 0 |
| liva-en-tl-C_001_007 | line-349 | code-switched | Speaker 5 | yes | 366.49 s–366.90 s | 100.00% | 87.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-351 | code-switched | Speaker 1 | yes | 366.53 s–367.75 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-353 | code-switched | Speaker 5 | no | 368.85 s–369.46 s | 66.67% | 66.67% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-355 | code-switched | Speaker 5 | no | 372.08 s–372.75 s | 75.00% | 86.67% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-359 | code-switched | Speaker 1 | no | 377.68 s–379.84 s | 44.44% | 14.29% | 9 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-361 | code-switched | Speaker 1 | yes | 380.97 s–381.64 s | 100.00% | 133.33% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-363 | code-switched | Speaker 3 | yes | 381.63 s–382.76 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-365 | code-switched | Speaker 1 | no | 383.27 s–383.96 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-367 | code-switched | Speaker 3 | no | 384.11 s–385.16 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-369 | code-switched | Speaker 1 | no | 386.11 s–386.46 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-373 | code-switched | Speaker 1 | no | 387.11 s–387.86 s | 100.00% | 66.67% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-375 | code-switched | Speaker 5 | yes | 388.37 s–389.07 s | 60.00% | 36.84% | 5 | 2 | 0 | 1 |
| liva-en-tl-C_001_007 | line-377 | code-switched | Speaker 3 | yes | 388.57 s–389.46 s | 100.00% | 71.43% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-379 | code-switched | Speaker 6 | yes | 388.97 s–389.93 s | 100.00% | 100.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-381 | code-switched | Speaker 1 | yes | 389.78 s–390.97 s | 100.00% | 80.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-385 | code-switched | Speaker 3 | yes | 393.12 s–395.44 s | 42.86% | 18.92% | 7 | 2 | 1 | 0 |
| liva-en-tl-C_001_007 | line-387 | code-switched | Speaker 1 | yes | 393.33 s–393.74 s | 100.00% | 87.50% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-389 | code-switched | Speaker 5 | yes | 394.68 s–397.14 s | 33.33% | 21.95% | 9 | 2 | 1 | 0 |
| liva-en-tl-C_001_007 | line-393 | code-switched | Speaker 6 | yes | 397.43 s–398.57 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_007 | line-395 | code-switched | Speaker 1 | yes | 397.55 s–398.75 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_007 | line-397 | code-switched | Speaker 3 | yes | 398.15 s–402.38 s | 25.00% | 17.50% | 8 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-399 | code-switched | Speaker 1 | yes | 402.14 s–404.23 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_007 | line-401 | code-switched | Speaker 5 | yes | 402.44 s–402.98 s | 100.00% | 100.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-403 | code-switched | Speaker 3 | yes | 403.25 s–405.15 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-405 | code-switched | Speaker 5 | yes | 404.42 s–407.02 s | 50.00% | 27.66% | 10 | 4 | 1 | 0 |
| liva-en-tl-C_001_007 | line-407 | code-switched | Speaker 1 | yes | 406.40 s–409.92 s | 27.27% | 8.96% | 11 | 2 | 0 | 1 |
| liva-en-tl-C_001_007 | line-409 | code-switched | Speaker 3 | no | 410.02 s–411.24 s | 620.00% | 836.36% | 5 | 1 | 0 | 30 |
| liva-en-tl-C_001_007 | line-413 | code-switched | Speaker 6 | yes | 413.14 s–413.74 s | 100.00% | 95.00% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-415 | code-switched | Speaker 1 | yes | 413.53 s–420.46 s | 26.67% | 23.75% | 15 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-419 | code-switched | Speaker 5 | yes | 417.70 s–418.90 s | 100.00% | 100.00% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-421 | code-switched | Speaker 3 | yes | 420.55 s–422.71 s | 100.00% | 109.68% | 7 | 7 | 0 | 0 |
| liva-en-tl-C_001_007 | line-423 | code-switched | Speaker 1 | yes | 421.42 s–421.92 s | 100.00% | 112.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-425 | code-switched | Speaker 6 | no | 424.22 s–424.84 s | 100.00% | 125.00% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-429 | code-switched | Speaker 1 | no | 425.60 s–427.58 s | 100.00% | 100.00% | 7 | 7 | 0 | 0 |
| liva-en-tl-C_001_007 | line-437 | code-switched | Speaker 3 | no | 433.10 s–433.53 s | 100.00% | 150.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-443 | code-switched | Speaker 1 | no | 439.88 s–441.19 s | 100.00% | 125.00% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-447 | code-switched | Speaker 3 | yes | 441.94 s–444.62 s | 100.00% | 93.18% | 8 | 8 | 0 | 0 |
| liva-en-tl-C_001_007 | line-449 | code-switched | Speaker 1 | yes | 442.78 s–443.97 s | 100.00% | 106.67% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-455 | code-switched | Speaker 3 | yes | 447.18 s–448.76 s | 100.00% | 96.67% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_007 | line-457 | code-switched | Speaker 1 | yes | 447.62 s–448.72 s | 100.00% | 120.00% | 5 | 5 | 0 | 0 |
| liva-en-tl-C_001_007 | line-459 | code-switched | Speaker 3 | no | 450.32 s–451.74 s | 100.00% | 94.12% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_007 | line-461 | code-switched | Speaker 5 | no | 452.16 s–452.47 s | 100.00% | 250.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-463 | code-switched | Speaker 5 | no | 453.49 s–453.88 s | 100.00% | 80.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-467 | code-switched | Speaker 1 | no | 456.43 s–457.51 s | 100.00% | 90.48% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-469 | code-switched | Speaker 3 | no | 459.36 s–460.49 s | 100.00% | 68.42% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-471 | code-switched | Speaker 1 | no | 462.19 s–463.54 s | 140.00% | 108.00% | 5 | 4 | 0 | 3 |
| liva-en-tl-C_001_007 | line-473 | code-switched | Speaker 3 | no | 464.37 s–465.07 s | 100.00% | 75.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-477 | code-switched | Speaker 6 | no | 467.26 s–467.94 s | 100.00% | 70.00% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-479 | code-switched | Speaker 3 | no | 468.09 s–468.87 s | 100.00% | 133.33% | 4 | 3 | 0 | 1 |
| liva-en-tl-C_001_007 | line-481 | code-switched | Speaker 1 | no | 469.44 s–470.00 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-483 | code-switched | Speaker 3 | no | 471.57 s–473.31 s | 100.00% | 118.75% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_007 | line-491 | code-switched | Speaker 1 | yes | 474.98 s–479.65 s | 100.00% | 78.16% | 16 | 16 | 0 | 0 |
| liva-en-tl-C_001_007 | line-493 | code-switched | Speaker 3 | yes | 475.57 s–476.28 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-499 | code-switched | Speaker 3 | yes | 478.23 s–484.50 s | 53.85% | 27.59% | 13 | 3 | 4 | 0 |
| liva-en-tl-C_001_007 | line-501 | code-switched | Speaker 1 | yes | 483.34 s–484.85 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-503 | code-switched | Speaker 1 | no | 485.37 s–486.06 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-507 | code-switched | Speaker 5 | no | 487.48 s–487.98 s | 100.00% | 90.91% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-509 | code-switched | Speaker 1 | yes | 488.48 s–489.20 s | 100.00% | 77.78% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-511 | code-switched | Speaker 3 | yes | 488.63 s–490.69 s | 28.57% | 14.29% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-513 | code-switched | Speaker 5 | yes | 488.70 s–489.26 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_007 | line-515 | code-switched | Speaker 5 | no | 490.84 s–492.32 s | 28.57% | 12.90% | 7 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-519 | code-switched | Speaker 1 | no | 492.64 s–493.54 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-521 | code-switched | Speaker 1 | no | 494.48 s–498.82 s | 56.25% | 25.30% | 16 | 7 | 0 | 2 |
| liva-en-tl-C_001_007 | line-533 | code-switched | Speaker 1 | yes | 502.09 s–503.94 s | 28.57% | 18.75% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-535 | code-switched | Speaker 3 | yes | 502.22 s–504.22 s | 100.00% | 69.23% | 9 | 6 | 3 | 0 |
| liva-en-tl-C_001_007 | line-539 | code-switched | Speaker 1 | no | 508.00 s–510.03 s | 37.50% | 23.26% | 8 | 1 | 2 | 0 |
| liva-en-tl-C_001_007 | line-541 | code-switched | Speaker 3 | no | 511.13 s–514.60 s | 30.77% | 24.59% | 13 | 2 | 2 | 0 |
| liva-en-tl-C_001_007 | line-545 | code-switched | Speaker 1 | no | 516.44 s–519.02 s | 42.86% | 26.32% | 7 | 2 | 1 | 0 |
| liva-en-tl-C_001_007 | line-549 | code-switched | Speaker 1 | no | 519.58 s–519.82 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-551 | code-switched | Speaker 3 | no | 520.53 s–521.42 s | 66.67% | 33.33% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-553 | code-switched | Speaker 1 | yes | 523.59 s–525.01 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_007 | line-555 | code-switched | Speaker 3 | yes | 524.11 s–525.07 s | 100.00% | 53.33% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_007 | line-559 | code-switched | Speaker 3 | no | 525.62 s–528.27 s | 12.50% | 11.76% | 8 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-567 | code-switched | Speaker 6 | yes | 530.79 s–531.50 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-569 | code-switched | Speaker 1 | yes | 531.18 s–532.26 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-571 | code-switched | Speaker 6 | no | 534.30 s–534.54 s | 100.00% | 100.00% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-573 | code-switched | Speaker 3 | no | 535.90 s–538.07 s | 100.00% | 58.82% | 7 | 7 | 0 | 0 |
| liva-en-tl-C_001_007 | line-575 | code-switched | Speaker 3 | no | 542.54 s–544.59 s | 33.33% | 21.21% | 9 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-577 | code-switched | Speaker 6 | no | 545.32 s–545.63 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-581 | code-switched | Speaker 6 | no | 548.42 s–548.62 s | 100.00% | 100.00% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-583 | code-switched | Speaker 1 | yes | 550.98 s–553.17 s | 60.00% | 34.48% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_007 | line-585 | code-switched | Speaker 3 | yes | 551.26 s–552.19 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-587 | code-switched | Speaker 3 | yes | 554.25 s–555.48 s | 50.00% | 54.55% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-589 | code-switched | Speaker 6 | yes | 555.15 s–556.63 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-591 | code-switched | Speaker 1 | yes | 555.74 s–556.80 s | 40.00% | 18.18% | 5 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-593 | code-switched | Speaker 3 | no | 557.44 s–558.22 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-595 | code-switched | Speaker 1 | yes | 558.88 s–559.63 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-597 | code-switched | Speaker 3 | yes | 558.98 s–561.89 s | 50.00% | 39.22% | 10 | 4 | 0 | 1 |
| liva-en-tl-C_001_007 | line-601 | code-switched | Speaker 6 | yes | 561.07 s–561.82 s | 100.00% | 112.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-603 | code-switched | Speaker 1 | yes | 562.54 s–563.56 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-605 | code-switched | Speaker 5 | yes | 562.76 s–564.01 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_007 | line-607 | code-switched | Speaker 3 | yes | 562.99 s–567.61 s | 57.89% | 45.78% | 19 | 5 | 6 | 0 |
| liva-en-tl-C_001_007 | line-609 | code-switched | Speaker 5 | yes | 564.49 s–565.00 s | 100.00% | 92.31% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_007 | line-611 | code-switched | Speaker 1 | yes | 567.19 s–568.51 s | 25.00% | 25.00% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-613 | code-switched | Speaker 3 | yes | 569.26 s–570.00 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-615 | code-switched | Speaker 5 | yes | 569.38 s–571.92 s | 100.00% | 79.63% | 8 | 2 | 6 | 0 |
| liva-en-tl-C_001_007 | line-617 | code-switched | Speaker 1 | yes | 571.03 s–571.36 s | 100.00% | 57.14% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-619 | code-switched | Speaker 3 | yes | 571.32 s–571.68 s | 100.00% | 125.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_007 | line-621 | code-switched | Speaker 1 | no | 572.84 s–575.18 s | 0.00% | 0.00% | 6 | 0 | 0 | 0 |
| liva-en-tl-C_001_007 | line-625 | code-switched | Speaker 5 | no | 575.40 s–575.66 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_007 | line-627 | code-switched | Speaker 1 | no | 575.73 s–577.83 s | 66.67% | 12.50% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-633 | code-switched | Speaker 1 | yes | 579.43 s–581.04 s | 33.33% | 11.11% | 6 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-635 | code-switched | Speaker 3 | yes | 580.43 s–582.41 s | 71.43% | 33.33% | 7 | 5 | 0 | 0 |
| liva-en-tl-C_001_007 | line-637 | code-switched | Speaker 1 | yes | 582.88 s–585.30 s | 22.22% | 6.67% | 9 | 2 | 0 | 0 |
| liva-en-tl-C_001_007 | line-639 | code-switched | Speaker 6 | yes | 583.24 s–583.45 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-641 | code-switched | Speaker 3 | yes | 583.44 s–584.16 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_007 | line-643 | code-switched | Speaker 1 | no | 585.82 s–586.62 s | 33.33% | 25.00% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-1 | code-switched | Speaker 1 | no | 0.00 s–1.03 s | 100.00% | 83.33% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-5 | code-switched | Speaker 1 | no | 2.23 s–3.98 s | 57.14% | 51.52% | 7 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-7 | code-switched | Speaker 3 | no | 10.72 s–12.32 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-15 | code-switched | Speaker 3 | no | 24.38 s–27.20 s | 85.71% | 84.21% | 7 | 1 | 5 | 0 |
| liva-en-tl-C_001_009 | line-17 | code-switched | Speaker 6 | yes | 28.08 s–28.70 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-19 | code-switched | Speaker 5 | yes | 28.32 s–30.89 s | 91.67% | 70.00% | 12 | 10 | 1 | 0 |
| liva-en-tl-C_001_009 | line-21 | code-switched | Speaker 6 | yes | 30.96 s–31.86 s | 80.00% | 66.67% | 5 | 3 | 1 | 0 |
| liva-en-tl-C_001_009 | line-23 | code-switched | Speaker 1 | yes | 31.42 s–31.98 s | 100.00% | 75.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-25 | code-switched | Speaker 6 | yes | 32.41 s–33.71 s | 75.00% | 86.67% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-27 | code-switched | Speaker 5 | yes | 33.03 s–33.71 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-29 | code-switched | Speaker 3 | yes | 34.62 s–35.13 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-31 | code-switched | Speaker 1 | yes | 34.73 s–35.48 s | 100.00% | 90.91% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_009 | line-35 | code-switched | Speaker 1 | no | 36.67 s–38.00 s | 100.00% | 103.45% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_009 | line-37 | code-switched | Speaker 6 | no | 38.97 s–39.37 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-39 | code-switched | Speaker 3 | yes | 40.75 s–41.53 s | 100.00% | 66.67% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-41 | code-switched | Speaker 6 | yes | 40.79 s–41.36 s | 100.00% | 73.33% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-43 | code-switched | Speaker 1 | no | 43.36 s–45.28 s | 50.00% | 16.22% | 8 | 3 | 1 | 0 |
| liva-en-tl-C_001_009 | line-45 | code-switched | Speaker 6 | no | 45.34 s–45.60 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-47 | code-switched | Speaker 3 | no | 46.39 s–47.12 s | 33.33% | 26.32% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-49 | code-switched | Speaker 3 | yes | 47.76 s–48.03 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-51 | code-switched | Speaker 5 | yes | 47.77 s–48.34 s | 100.00% | 92.31% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_009 | line-53 | code-switched | Speaker 1 | yes | 48.15 s–49.61 s | 60.00% | 42.11% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-55 | code-switched | Speaker 6 | yes | 49.02 s–50.42 s | 100.00% | 76.00% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_009 | line-59 | code-switched | Speaker 3 | yes | 51.47 s–53.13 s | 40.00% | 70.83% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-63 | code-switched | Speaker 6 | yes | 53.01 s–53.28 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-65 | code-switched | Speaker 3 | no | 53.90 s–54.60 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-67 | code-switched | Speaker 1 | yes | 55.45 s–56.08 s | 100.00% | 128.57% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-69 | code-switched | Speaker 6 | yes | 55.86 s–57.26 s | 71.43% | 40.62% | 7 | 2 | 3 | 0 |
| liva-en-tl-C_001_009 | line-73 | code-switched | Speaker 3 | no | 58.19 s–58.88 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-77 | code-switched | Speaker 1 | no | 59.72 s–60.94 s | 75.00% | 64.71% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-79 | code-switched | Speaker 1 | no | 62.70 s–63.03 s | 100.00% | 125.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-81 | code-switched | Speaker 3 | no | 64.11 s–65.08 s | 80.00% | 47.37% | 5 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-87 | code-switched | Speaker 3 | no | 66.63 s–67.39 s | 66.67% | 64.29% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-91 | code-switched | Speaker 3 | no | 68.48 s–71.64 s | 28.57% | 17.14% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-95 | code-switched | Speaker 3 | no | 72.45 s–74.93 s | 33.33% | 20.00% | 9 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-101 | code-switched | Speaker 1 | yes | 77.20 s–81.02 s | 0.00% | 0.00% | 6 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-103 | code-switched | Speaker 3 | yes | 77.58 s–79.74 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-105 | code-switched | Speaker 3 | no | 81.88 s–82.30 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-109 | code-switched | Speaker 1 | no | 83.83 s–86.75 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-111 | code-switched | Speaker 3 | no | 87.39 s–87.82 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-113 | code-switched | Speaker 1 | yes | 91.41 s–93.73 s | 33.33% | 21.62% | 9 | 2 | 0 | 1 |
| liva-en-tl-C_001_009 | line-115 | code-switched | Speaker 6 | yes | 92.32 s–92.90 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-117 | code-switched | Speaker 6 | no | 93.84 s–94.44 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-121 | code-switched | Speaker 6 | no | 95.60 s–95.91 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-123 | code-switched | Speaker 3 | no | 98.22 s–98.43 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-125 | code-switched | Speaker 3 | no | 99.68 s–100.34 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-127 | code-switched | Speaker 1 | no | 101.33 s–102.76 s | 75.00% | 52.94% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-131 | code-switched | Speaker 5 | no | 106.26 s–107.78 s | 33.33% | 19.23% | 6 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-133 | code-switched | Speaker 1 | no | 109.64 s–109.92 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-135 | code-switched | Speaker 6 | no | 110.76 s–110.93 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-139 | code-switched | Speaker 6 | yes | 111.65 s–113.42 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_009 | line-141 | code-switched | Speaker 1 | yes | 112.97 s–113.37 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-143 | code-switched | Speaker 5 | no | 114.38 s–116.39 s | 14.29% | 13.16% | 7 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-147 | code-switched | Speaker 1 | yes | 117.60 s–123.56 s | 38.89% | 29.41% | 18 | 3 | 4 | 0 |
| liva-en-tl-C_001_009 | line-149 | code-switched | Speaker 3 | yes | 119.94 s–120.56 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-153 | code-switched | Speaker 3 | yes | 123.05 s–124.00 s | 50.00% | 42.86% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-155 | code-switched | Speaker 1 | yes | 124.94 s–128.61 s | 42.86% | 23.38% | 14 | 2 | 4 | 0 |
| liva-en-tl-C_001_009 | line-161 | code-switched | Speaker 6 | yes | 127.52 s–127.78 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-165 | code-switched | Speaker 3 | yes | 128.59 s–130.17 s | 40.00% | 29.17% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-167 | code-switched | Speaker 3 | no | 130.71 s–132.10 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-171 | code-switched | Speaker 3 | no | 132.66 s–133.68 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-173 | code-switched | Speaker 3 | no | 134.45 s–136.45 s | 50.00% | 11.11% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-175 | code-switched | Speaker 3 | yes | 137.38 s–138.18 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-177 | code-switched | Speaker 5 | yes | 137.76 s–138.91 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-181 | code-switched | Speaker 3 | yes | 140.87 s–143.36 s | 11.11% | 1.85% | 9 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-183 | code-switched | Speaker 6 | yes | 141.24 s–142.08 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-187 | code-switched | Speaker 5 | yes | 144.32 s–145.59 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-189 | code-switched | Speaker 1 | yes | 144.88 s–150.42 s | 56.25% | 27.71% | 16 | 6 | 3 | 0 |
| liva-en-tl-C_001_009 | line-191 | code-switched | Speaker 3 | yes | 151.42 s–155.40 s | 73.33% | 32.43% | 15 | 9 | 2 | 0 |
| liva-en-tl-C_001_009 | line-195 | code-switched | Speaker 1 | yes | 154.86 s–155.35 s | 100.00% | 90.91% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-197 | code-switched | Speaker 1 | yes | 156.59 s–160.26 s | 46.15% | 22.06% | 13 | 6 | 0 | 0 |
| liva-en-tl-C_001_009 | line-199 | code-switched | Speaker 3 | yes | 159.86 s–163.84 s | 60.00% | 42.42% | 15 | 2 | 7 | 0 |
| liva-en-tl-C_001_009 | line-203 | code-switched | Speaker 3 | no | 164.34 s–166.86 s | 0.00% | 0.00% | 8 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-205 | code-switched | Speaker 1 | yes | 167.16 s–168.80 s | 100.00% | 55.56% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-207 | code-switched | Speaker 3 | yes | 168.74 s–170.68 s | 66.67% | 34.38% | 6 | 3 | 1 | 0 |
| liva-en-tl-C_001_009 | line-209 | code-switched | Speaker 3 | yes | 171.93 s–174.25 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-211 | code-switched | Speaker 1 | yes | 173.12 s–174.24 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-213 | code-switched | Speaker 3 | no | 174.95 s–175.87 s | 50.00% | 20.00% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-217 | code-switched | Speaker 3 | yes | 177.53 s–181.13 s | 20.00% | 28.00% | 10 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-219 | code-switched | Speaker 1 | yes | 179.42 s–181.10 s | 33.33% | 11.11% | 6 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-221 | code-switched | Speaker 3 | no | 182.17 s–184.40 s | 50.00% | 27.59% | 6 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-223 | code-switched | Speaker 3 | yes | 185.22 s–186.17 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-225 | code-switched | Speaker 1 | yes | 185.56 s–186.48 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-227 | code-switched | Speaker 3 | yes | 186.78 s–189.02 s | 0.00% | 0.00% | 7 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-231 | code-switched | Speaker 1 | yes | 188.53 s–188.83 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-233 | code-switched | Speaker 1 | yes | 189.86 s–190.88 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-235 | code-switched | Speaker 3 | yes | 190.70 s–192.25 s | 28.57% | 25.71% | 7 | 0 | 1 | 1 |
| liva-en-tl-C_001_009 | line-237 | code-switched | Speaker 1 | no | 195.84 s–196.81 s | 100.00% | 85.71% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-239 | code-switched | Speaker 1 | yes | 198.08 s–199.46 s | 0.00% | 0.00% | 6 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-241 | code-switched | Speaker 3 | yes | 198.11 s–198.28 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-243 | code-switched | Speaker 3 | yes | 199.16 s–201.38 s | 63.64% | 53.33% | 11 | 3 | 4 | 0 |
| liva-en-tl-C_001_009 | line-245 | code-switched | Speaker 1 | yes | 200.16 s–201.45 s | 16.67% | 13.79% | 6 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-247 | code-switched | Speaker 5 | yes | 200.35 s–200.84 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-253 | code-switched | Speaker 5 | no | 204.01 s–205.37 s | 28.57% | 6.90% | 7 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-257 | code-switched | Speaker 1 | yes | 206.08 s–207.24 s | 60.00% | 55.56% | 5 | 1 | 2 | 0 |
| liva-en-tl-C_001_009 | line-259 | code-switched | Speaker 3 | yes | 206.63 s–207.05 s | 100.00% | 77.78% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-261 | code-switched | Speaker 3 | no | 207.60 s–211.04 s | 35.71% | 9.23% | 14 | 4 | 1 | 0 |
| liva-en-tl-C_001_009 | line-263 | code-switched | Speaker 3 | no | 211.67 s–212.87 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-265 | code-switched | Speaker 3 | no | 214.84 s–215.90 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-269 | code-switched | Speaker 3 | no | 217.95 s–219.71 s | 42.86% | 31.43% | 7 | 1 | 1 | 1 |
| liva-en-tl-C_001_009 | line-271 | code-switched | Speaker 3 | no | 220.21 s–220.86 s | 33.33% | 28.57% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-275 | code-switched | Speaker 1 | no | 222.18 s–222.80 s | 100.00% | 68.75% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-277 | code-switched | Speaker 3 | no | 224.58 s–225.25 s | 40.00% | 30.00% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-279 | code-switched | Speaker 3 | no | 226.00 s–229.14 s | 50.00% | 15.62% | 12 | 2 | 0 | 4 |
| liva-en-tl-C_001_009 | line-283 | code-switched | Speaker 1 | no | 230.10 s–233.80 s | 45.45% | 23.33% | 11 | 3 | 0 | 2 |
| liva-en-tl-C_001_009 | line-285 | code-switched | Speaker 3 | yes | 236.34 s–236.55 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-287 | code-switched | Speaker 1 | yes | 236.51 s–237.21 s | 100.00% | 46.15% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-289 | code-switched | Speaker 1 | no | 238.57 s–240.19 s | 33.33% | 33.33% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-293 | code-switched | Speaker 3 | no | 242.12 s–243.04 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-295 | code-switched | Speaker 3 | no | 243.74 s–244.22 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-297 | code-switched | Speaker 1 | no | 245.31 s–247.33 s | 22.22% | 13.33% | 9 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-301 | code-switched | Speaker 3 | yes | 248.81 s–249.22 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-303 | code-switched | Speaker 6 | yes | 248.87 s–248.98 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-305 | code-switched | Speaker 3 | yes | 249.74 s–250.40 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-307 | code-switched | Speaker 6 | yes | 250.05 s–250.10 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-309 | code-switched | Speaker 1 | yes | 250.12 s–250.54 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-311 | code-switched | Speaker 1 | no | 251.87 s–253.46 s | 71.43% | 35.48% | 7 | 4 | 0 | 1 |
| liva-en-tl-C_001_009 | line-313 | code-switched | Speaker 1 | no | 254.15 s–256.99 s | 20.00% | 10.71% | 10 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-315 | code-switched | Speaker 3 | no | 257.88 s–258.26 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-317 | code-switched | Speaker 3 | yes | 258.94 s–260.90 s | 71.43% | 64.52% | 7 | 0 | 5 | 0 |
| liva-en-tl-C_001_009 | line-321 | code-switched | Speaker 1 | yes | 259.76 s–261.62 s | 100.00% | 76.09% | 8 | 3 | 5 | 0 |
| liva-en-tl-C_001_009 | line-323 | code-switched | Speaker 3 | no | 262.02 s–268.31 s | 44.44% | 23.08% | 18 | 4 | 4 | 0 |
| liva-en-tl-C_001_009 | line-327 | code-switched | Speaker 3 | no | 268.88 s–269.44 s | 50.00% | 26.67% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-329 | code-switched | Speaker 3 | no | 270.28 s–270.55 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-331 | code-switched | Speaker 3 | yes | 271.06 s–272.03 s | 25.00% | 4.55% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-333 | code-switched | Speaker 1 | yes | 271.38 s–271.45 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-335 | code-switched | Speaker 1 | yes | 271.96 s–272.87 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-337 | code-switched | Speaker 3 | yes | 273.31 s–273.94 s | 50.00% | 28.57% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-339 | code-switched | Speaker 1 | yes | 273.55 s–273.90 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-341 | code-switched | Speaker 3 | yes | 274.51 s–275.22 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-343 | code-switched | Speaker 1 | yes | 274.87 s–277.40 s | 75.00% | 33.33% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-349 | code-switched | Speaker 1 | no | 279.31 s–281.31 s | 62.50% | 28.57% | 8 | 4 | 1 | 0 |
| liva-en-tl-C_001_009 | line-351 | code-switched | Speaker 3 | no | 282.16 s–284.27 s | 12.50% | 3.03% | 8 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-357 | code-switched | Speaker 3 | no | 284.98 s–286.76 s | 100.00% | 47.73% | 8 | 7 | 1 | 0 |
| liva-en-tl-C_001_009 | line-359 | code-switched | Speaker 1 | no | 287.08 s–290.37 s | 53.85% | 22.73% | 13 | 6 | 0 | 1 |
| liva-en-tl-C_001_009 | line-361 | code-switched | Speaker 3 | no | 292.82 s–293.46 s | 100.00% | 77.78% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-363 | code-switched | Speaker 6 | no | 297.58 s–297.80 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-369 | code-switched | Speaker 6 | yes | 304.05 s–304.85 s | 100.00% | 106.25% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_009 | line-371 | code-switched | Speaker 1 | yes | 304.78 s–306.38 s | 50.00% | 48.00% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-373 | code-switched | Speaker 1 | no | 307.25 s–307.58 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-375 | code-switched | Speaker 6 | no | 308.27 s–309.52 s | 100.00% | 94.29% | 7 | 2 | 5 | 0 |
| liva-en-tl-C_001_009 | line-381 | code-switched | Speaker 3 | no | 313.42 s–313.74 s | 100.00% | 75.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-383 | code-switched | Speaker 1 | no | 315.78 s–320.44 s | 81.82% | 27.54% | 11 | 8 | 0 | 1 |
| liva-en-tl-C_001_009 | line-389 | code-switched | Speaker 1 | no | 323.90 s–326.26 s | 81.82% | 37.93% | 11 | 7 | 1 | 1 |
| liva-en-tl-C_001_009 | line-391 | code-switched | Speaker 5 | no | 327.86 s–328.70 s | 50.00% | 52.38% | 4 | 1 | 0 | 1 |
| liva-en-tl-C_001_009 | line-393 | code-switched | Speaker 1 | no | 329.57 s–331.31 s | 71.43% | 47.22% | 7 | 4 | 1 | 0 |
| liva-en-tl-C_001_009 | line-395 | code-switched | Speaker 5 | no | 331.64 s–332.14 s | 66.67% | 58.33% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-397 | code-switched | Speaker 5 | no | 333.06 s–333.35 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-399 | code-switched | Speaker 1 | no | 333.95 s–336.02 s | 62.50% | 24.44% | 8 | 4 | 0 | 1 |
| liva-en-tl-C_001_009 | line-401 | code-switched | Speaker 1 | no | 337.17 s–338.94 s | 75.00% | 47.62% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-403 | code-switched | Speaker 1 | no | 339.50 s–341.58 s | 100.00% | 57.14% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_009 | line-409 | code-switched | Speaker 1 | no | 346.40 s–346.76 s | 50.00% | 66.67% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-411 | code-switched | Speaker 1 | no | 348.85 s–350.27 s | 80.00% | 72.73% | 5 | 1 | 3 | 0 |
| liva-en-tl-C_001_009 | line-413 | code-switched | Speaker 3 | no | 350.65 s–353.52 s | 50.00% | 11.11% | 6 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-415 | code-switched | Speaker 5 | yes | 359.10 s–359.77 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-417 | code-switched | Speaker 1 | yes | 359.73 s–361.07 s | 75.00% | 45.00% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-425 | code-switched | Speaker 5 | yes | 367.47 s–370.84 s | 57.14% | 29.17% | 14 | 5 | 2 | 1 |
| liva-en-tl-C_001_009 | line-429 | code-switched | Speaker 3 | yes | 368.34 s–368.47 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-431 | code-switched | Speaker 3 | yes | 369.10 s–369.43 s | 100.00% | 333.33% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-435 | code-switched | Speaker 5 | no | 371.36 s–373.11 s | 33.33% | 18.60% | 9 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-439 | code-switched | Speaker 1 | yes | 374.36 s–374.68 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-441 | code-switched | Speaker 3 | yes | 374.59 s–376.14 s | 100.00% | 54.55% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_009 | line-443 | code-switched | Speaker 1 | no | 377.18 s–378.12 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-445 | code-switched | Speaker 5 | no | 378.23 s–379.60 s | 25.00% | 10.53% | 4 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-451 | code-switched | Speaker 1 | yes | 380.36 s–381.49 s | 50.00% | 50.00% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-453 | code-switched | Speaker 6 | yes | 380.61 s–380.89 s | 100.00% | 90.00% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-457 | code-switched | Speaker 5 | yes | 381.87 s–385.54 s | 40.91% | 29.35% | 22 | 5 | 4 | 0 |
| liva-en-tl-C_001_009 | line-459 | code-switched | Speaker 2 | yes | 381.97 s–382.24 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-461 | code-switched | Speaker 6 | yes | 382.10 s–382.37 s | 75.00% | 87.50% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-469 | code-switched | Speaker 2 | yes | 384.11 s–384.39 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-471 | code-switched | Speaker 1 | yes | 384.21 s–384.48 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-475 | code-switched | Speaker 1 | no | 386.64 s–386.94 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-477 | code-switched | Speaker 3 | no | 386.94 s–388.89 s | 30.00% | 6.98% | 10 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-483 | code-switched | Speaker 5 | no | 390.29 s–391.61 s | 40.00% | 31.82% | 5 | 1 | 0 | 1 |
| liva-en-tl-C_001_009 | line-485 | code-switched | Speaker 2 | no | 395.55 s–396.42 s | 66.67% | 35.00% | 3 | 1 | 0 | 1 |
| liva-en-tl-C_001_009 | line-487 | code-switched | Speaker 3 | no | 397.46 s–398.15 s | 133.33% | 150.00% | 3 | 2 | 0 | 2 |
| liva-en-tl-C_001_009 | line-489 | code-switched | Speaker 1 | no | 399.45 s–401.51 s | 33.33% | 17.14% | 6 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-493 | code-switched | Speaker 2 | yes | 402.10 s–403.07 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-495 | code-switched | Speaker 5 | yes | 402.31 s–402.75 s | 50.00% | 100.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-497 | code-switched | Speaker 1 | yes | 402.68 s–404.22 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-499 | code-switched | Speaker 2 | no | 404.28 s–406.34 s | 88.89% | 56.82% | 9 | 6 | 2 | 0 |
| liva-en-tl-C_001_009 | line-503 | code-switched | Speaker 5 | yes | 407.64 s–409.50 s | 14.29% | 5.56% | 7 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-505 | code-switched | Speaker 1 | yes | 407.86 s–408.12 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-513 | code-switched | Speaker 5 | no | 414.42 s–415.87 s | 50.00% | 36.36% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-517 | code-switched | Speaker 1 | no | 416.47 s–417.91 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_009 | line-519 | code-switched | Speaker 2 | yes | 418.57 s–419.90 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_009 | line-523 | code-switched | Speaker 3 | yes | 419.18 s–420.55 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_009 | line-525 | code-switched | Speaker 1 | yes | 419.56 s–422.17 s | 100.00% | 86.05% | 10 | 4 | 6 | 0 |
| liva-en-tl-C_001_009 | line-527 | code-switched | Speaker 3 | yes | 421.21 s–422.86 s | 14.29% | 9.38% | 7 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-531 | code-switched | Speaker 6 | no | 424.35 s–424.60 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-537 | code-switched | Speaker 3 | yes | 426.09 s–430.40 s | 71.43% | 52.56% | 14 | 5 | 5 | 0 |
| liva-en-tl-C_001_009 | line-539 | code-switched | Speaker 5 | yes | 426.37 s–427.36 s | 100.00% | 72.73% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-541 | code-switched | Speaker 6 | no | 431.33 s–431.82 s | 66.67% | 100.00% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-543 | code-switched | Speaker 2 | yes | 431.86 s–433.37 s | 100.00% | 75.00% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-545 | code-switched | Speaker 6 | yes | 432.40 s–432.76 s | 100.00% | 91.67% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-547 | code-switched | Speaker 3 | yes | 432.95 s–433.79 s | 100.00% | 85.71% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-551 | code-switched | Speaker 2 | yes | 434.94 s–438.43 s | 42.86% | 44.23% | 7 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-555 | code-switched | Speaker 3 | yes | 437.35 s–439.12 s | 71.43% | 58.33% | 7 | 2 | 3 | 0 |
| liva-en-tl-C_001_009 | line-557 | code-switched | Speaker 6 | yes | 437.68 s–438.76 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-559 | code-switched | Speaker 6 | yes | 439.86 s–440.59 s | 100.00% | 84.21% | 5 | 2 | 3 | 0 |
| liva-en-tl-C_001_009 | line-561 | code-switched | Speaker 3 | yes | 440.07 s–445.51 s | 46.67% | 21.52% | 15 | 6 | 1 | 0 |
| liva-en-tl-C_001_009 | line-565 | code-switched | Speaker 2 | yes | 445.27 s–445.31 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-567 | code-switched | Speaker 3 | yes | 446.31 s–449.63 s | 60.00% | 42.37% | 10 | 5 | 1 | 0 |
| liva-en-tl-C_001_009 | line-569 | code-switched | Speaker 1 | yes | 446.46 s–446.57 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-575 | code-switched | Speaker 2 | yes | 451.26 s–454.64 s | 71.43% | 39.29% | 7 | 3 | 2 | 0 |
| liva-en-tl-C_001_009 | line-577 | code-switched | Speaker 1 | yes | 451.80 s–452.30 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-579 | code-switched | Speaker 3 | yes | 453.78 s–454.10 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-581 | code-switched | Speaker 1 | yes | 455.67 s–459.40 s | 60.00% | 48.84% | 10 | 5 | 1 | 0 |
| liva-en-tl-C_001_009 | line-583 | code-switched | Speaker 3 | yes | 456.00 s–456.26 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-585 | code-switched | Speaker 2 | yes | 456.15 s–457.79 s | 100.00% | 92.00% | 7 | 2 | 5 | 0 |
| liva-en-tl-C_001_009 | line-587 | code-switched | Speaker 3 | yes | 459.00 s–460.04 s | 16.67% | 4.00% | 6 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-589 | code-switched | Speaker 2 | yes | 459.22 s–460.10 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-595 | code-switched | Speaker 5 | yes | 462.88 s–463.60 s | 50.00% | 35.29% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-597 | code-switched | Speaker 2 | yes | 463.29 s–465.56 s | 100.00% | 100.00% | 8 | 0 | 8 | 0 |
| liva-en-tl-C_001_009 | line-599 | code-switched | Speaker 3 | yes | 463.40 s–463.74 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-603 | code-switched | Speaker 5 | yes | 464.74 s–465.56 s | 100.00% | 91.67% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_009 | line-605 | code-switched | Speaker 1 | yes | 464.97 s–467.11 s | 50.00% | 20.51% | 8 | 4 | 0 | 0 |
| liva-en-tl-C_001_009 | line-607 | code-switched | Speaker 3 | yes | 467.43 s–467.88 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-609 | code-switched | Speaker 2 | yes | 467.65 s–468.49 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_009 | line-611 | code-switched | Speaker 5 | yes | 468.19 s–469.19 s | 66.67% | 17.65% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-613 | code-switched | Speaker 3 | no | 469.44 s–469.91 s | 33.33% | 27.27% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-615 | code-switched | Speaker 2 | yes | 470.48 s–471.28 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-617 | code-switched | Speaker 1 | yes | 470.54 s–472.24 s | 55.56% | 32.61% | 9 | 3 | 2 | 0 |
| liva-en-tl-C_001_009 | line-621 | code-switched | Speaker 3 | no | 473.70 s–474.38 s | 33.33% | 31.25% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-623 | code-switched | Speaker 1 | yes | 474.43 s–478.04 s | 37.50% | 21.05% | 8 | 3 | 0 | 0 |
| liva-en-tl-C_001_009 | line-625 | code-switched | Speaker 5 | yes | 474.48 s–476.53 s | 100.00% | 100.00% | 11 | 0 | 11 | 0 |
| liva-en-tl-C_001_009 | line-627 | code-switched | Speaker 2 | yes | 476.01 s–476.14 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-629 | code-switched | Speaker 3 | yes | 478.09 s–479.17 s | 50.00% | 50.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-631 | code-switched | Speaker 2 | yes | 478.17 s–479.98 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_009 | line-633 | code-switched | Speaker 5 | yes | 478.87 s–479.18 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-635 | code-switched | Speaker 3 | yes | 479.97 s–481.66 s | 42.86% | 42.11% | 7 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-637 | code-switched | Speaker 6 | yes | 480.24 s–480.37 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-639 | code-switched | Speaker 2 | yes | 480.52 s–481.57 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_009 | line-643 | code-switched | Speaker 6 | yes | 481.10 s–481.84 s | 66.67% | 75.00% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-645 | code-switched | Speaker 6 | yes | 482.50 s–483.82 s | 75.00% | 87.50% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-647 | code-switched | Speaker 5 | yes | 482.53 s–483.62 s | 33.33% | 26.09% | 6 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-649 | code-switched | Speaker 3 | yes | 486.04 s–488.91 s | 55.56% | 48.00% | 9 | 1 | 4 | 0 |
| liva-en-tl-C_001_009 | line-651 | code-switched | Speaker 2 | yes | 488.13 s–489.30 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-653 | code-switched | Speaker 6 | yes | 489.18 s–489.92 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-655 | code-switched | Speaker 1 | yes | 489.38 s–494.71 s | 43.75% | 23.68% | 16 | 5 | 2 | 0 |
| liva-en-tl-C_001_009 | line-659 | code-switched | Speaker 3 | yes | 493.34 s–496.18 s | 100.00% | 100.00% | 8 | 0 | 8 | 0 |
| liva-en-tl-C_001_009 | line-661 | code-switched | Speaker 2 | yes | 494.66 s–495.67 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-663 | code-switched | Speaker 6 | yes | 495.07 s–497.33 s | 92.31% | 95.16% | 13 | 0 | 12 | 0 |
| liva-en-tl-C_001_009 | line-665 | code-switched | Speaker 1 | yes | 496.56 s–500.52 s | 66.67% | 48.44% | 15 | 2 | 8 | 0 |
| liva-en-tl-C_001_009 | line-667 | code-switched | Speaker 3 | yes | 498.02 s–498.72 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-669 | code-switched | Speaker 3 | yes | 499.28 s–500.33 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-671 | code-switched | Speaker 6 | yes | 499.46 s–501.93 s | 60.00% | 46.00% | 10 | 4 | 2 | 0 |
| liva-en-tl-C_001_009 | line-673 | code-switched | Speaker 2 | yes | 500.96 s–501.40 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-677 | code-switched | Speaker 3 | no | 503.34 s–503.99 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-679 | code-switched | Speaker 2 | yes | 504.97 s–506.29 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_009 | line-681 | code-switched | Speaker 1 | yes | 505.09 s–505.77 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-683 | code-switched | Speaker 3 | yes | 505.33 s–506.11 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-685 | code-switched | Speaker 6 | yes | 505.33 s–505.86 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-687 | code-switched | Speaker 6 | no | 506.77 s–508.47 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-689 | code-switched | Speaker 1 | no | 509.48 s–512.34 s | 16.67% | 10.81% | 6 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-697 | code-switched | Speaker 3 | yes | 513.04 s–515.73 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-703 | code-switched | Speaker 2 | yes | 515.35 s–515.65 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-705 | code-switched | Speaker 2 | yes | 516.22 s–518.49 s | 100.00% | 81.40% | 6 | 4 | 2 | 0 |
| liva-en-tl-C_001_009 | line-707 | code-switched | Speaker 3 | yes | 516.36 s–517.31 s | 66.67% | 57.14% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-711 | code-switched | Speaker 2 | no | 519.62 s–520.50 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-715 | code-switched | Speaker 2 | no | 521.33 s–522.64 s | 50.00% | 41.38% | 4 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-717 | code-switched | Speaker 3 | no | 523.90 s–525.34 s | 71.43% | 48.15% | 7 | 5 | 0 | 0 |
| liva-en-tl-C_001_009 | line-721 | code-switched | Speaker 3 | no | 526.24 s–527.71 s | 50.00% | 38.71% | 6 | 1 | 2 | 0 |
| liva-en-tl-C_001_009 | line-725 | code-switched | Speaker 2 | no | 529.41 s–529.78 s | 66.67% | 69.23% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-727 | code-switched | Speaker 3 | no | 530.73 s–531.96 s | 25.00% | 17.65% | 4 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-731 | code-switched | Speaker 3 | no | 532.54 s–535.25 s | 66.67% | 23.53% | 9 | 4 | 0 | 2 |
| liva-en-tl-C_001_009 | line-735 | code-switched | Speaker 2 | no | 536.49 s–538.91 s | 70.00% | 37.50% | 10 | 4 | 3 | 0 |
| liva-en-tl-C_001_009 | line-739 | code-switched | Speaker 1 | yes | 538.98 s–541.09 s | 50.00% | 25.00% | 8 | 4 | 0 | 0 |
| liva-en-tl-C_001_009 | line-745 | code-switched | Speaker 2 | yes | 540.88 s–541.05 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-747 | code-switched | Speaker 2 | no | 543.09 s–543.44 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-749 | code-switched | Speaker 3 | yes | 544.25 s–546.71 s | 14.29% | 8.57% | 7 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-751 | code-switched | Speaker 2 | yes | 544.50 s–545.74 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-753 | code-switched | Speaker 2 | yes | 547.09 s–548.99 s | 62.50% | 48.72% | 8 | 1 | 4 | 0 |
| liva-en-tl-C_001_009 | line-755 | code-switched | Speaker 5 | yes | 547.28 s–547.86 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-757 | code-switched | Speaker 6 | yes | 547.48 s–547.82 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-761 | code-switched | Speaker 5 | yes | 548.95 s–549.29 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-763 | code-switched | Speaker 6 | yes | 549.26 s–550.81 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_009 | line-765 | code-switched | Speaker 3 | yes | 550.27 s–552.87 s | 9.09% | 12.24% | 11 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-771 | code-switched | Speaker 2 | no | 552.96 s–554.30 s | 100.00% | 85.00% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_009 | line-773 | code-switched | Speaker 6 | yes | 554.61 s–555.16 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-775 | code-switched | Speaker 3 | yes | 555.04 s–555.23 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-777 | code-switched | Speaker 6 | yes | 555.66 s–558.41 s | 38.46% | 28.77% | 13 | 4 | 1 | 0 |
| liva-en-tl-C_001_009 | line-779 | code-switched | Speaker 2 | yes | 557.48 s–557.98 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-781 | code-switched | Speaker 3 | yes | 557.83 s–563.58 s | 50.00% | 39.34% | 12 | 3 | 3 | 0 |
| liva-en-tl-C_001_009 | line-783 | code-switched | Speaker 6 | yes | 559.36 s–559.59 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-785 | code-switched | Speaker 3 | no | 564.08 s–564.81 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-787 | code-switched | Speaker 1 | no | 566.11 s–566.82 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-791 | code-switched | Speaker 5 | yes | 567.48 s–568.81 s | 33.33% | 30.00% | 6 | 1 | 1 | 0 |
| liva-en-tl-C_001_009 | line-793 | code-switched | Speaker 1 | yes | 567.69 s–568.67 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_009 | line-795 | code-switched | Speaker 1 | no | 569.43 s–570.52 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-799 | code-switched | Speaker 3 | yes | 571.08 s–571.85 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-801 | code-switched | Speaker 2 | yes | 571.28 s–572.80 s | 100.00% | 76.47% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_009 | line-803 | code-switched | Speaker 1 | yes | 572.13 s–573.90 s | 75.00% | 83.33% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-805 | code-switched | Speaker 5 | yes | 572.34 s–572.80 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-807 | code-switched | Speaker 3 | yes | 572.81 s–573.68 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_009 | line-809 | code-switched | Speaker 5 | yes | 574.23 s–574.83 s | 100.00% | 68.75% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-811 | code-switched | Speaker 3 | yes | 574.25 s–575.12 s | 33.33% | 5.26% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-813 | code-switched | Speaker 5 | no | 575.63 s–576.52 s | 50.00% | 11.76% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_009 | line-815 | code-switched | Speaker 1 | yes | 576.70 s–582.66 s | 30.00% | 18.33% | 10 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-819 | code-switched | Speaker 6 | yes | 579.12 s–579.52 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_009 | line-821 | code-switched | Speaker 5 | yes | 579.96 s–582.05 s | 100.00% | 72.73% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-823 | code-switched | Speaker 3 | yes | 581.20 s–584.10 s | 66.67% | 74.36% | 6 | 2 | 2 | 0 |
| liva-en-tl-C_001_009 | line-825 | code-switched | Speaker 6 | yes | 581.70 s–582.38 s | 100.00% | 100.00% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_009 | line-827 | code-switched | Speaker 1 | yes | 584.09 s–584.72 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_009 | line-831 | code-switched | Speaker 3 | no | 585.50 s–588.32 s | 45.45% | 31.37% | 11 | 3 | 2 | 0 |
| liva-en-tl-C_001_009 | line-837 | code-switched | Speaker 1 | no | 589.59 s–594.32 s | 18.75% | 7.14% | 16 | 2 | 1 | 0 |
| liva-en-tl-C_001_009 | line-841 | code-switched | Speaker 3 | yes | 594.67 s–598.51 s | 50.00% | 15.38% | 8 | 1 | 3 | 0 |
| liva-en-tl-C_001_009 | line-843 | code-switched | Speaker 5 | yes | 594.90 s–595.33 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_009 | line-845 | code-switched | Speaker 1 | yes | 595.91 s–596.94 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-1 | code-switched | Speaker 1 | no | 0.60 s–1.24 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-3 | code-switched | Speaker 2 | yes | 1.28 s–2.11 s | 66.67% | 70.59% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-5 | code-switched | Speaker 3 | yes | 1.39 s–2.37 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-7 | code-switched | Speaker 1 | yes | 1.81 s–3.26 s | 25.00% | 15.00% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-11 | code-switched | Speaker 2 | yes | 2.72 s–3.35 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-13 | code-switched | Speaker 2 | yes | 3.89 s–4.20 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-15 | code-switched | Speaker 1 | yes | 3.94 s–6.24 s | 50.00% | 19.23% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-17 | code-switched | Speaker 2 | yes | 4.95 s–5.61 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-21 | code-switched | Speaker 3 | no | 7.21 s–7.56 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-23 | code-switched | Speaker 3 | yes | 8.08 s–10.47 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_015 | line-25 | code-switched | Speaker 2 | yes | 8.13 s–8.68 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-27 | code-switched | Speaker 1 | yes | 8.50 s–11.47 s | 28.57% | 15.91% | 7 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-29 | code-switched | Speaker 3 | yes | 12.02 s–13.55 s | 100.00% | 68.18% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_015 | line-33 | code-switched | Speaker 2 | yes | 12.37 s–12.92 s | 66.67% | 80.00% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-37 | code-switched | Speaker 1 | no | 14.46 s–16.00 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-41 | code-switched | Speaker 2 | yes | 16.32 s–16.76 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-43 | code-switched | Speaker 5 | yes | 16.37 s–18.14 s | 75.00% | 65.00% | 4 | 1 | 2 | 0 |
| liva-en-tl-C_001_015 | line-45 | code-switched | Speaker 2 | yes | 17.28 s–17.55 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-53 | code-switched | Speaker 2 | yes | 19.60 s–20.65 s | 100.00% | 83.33% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-55 | code-switched | Speaker 5 | yes | 19.71 s–20.01 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-57 | code-switched | Speaker 3 | no | 20.92 s–22.18 s | 66.67% | 84.62% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-61 | code-switched | Speaker 2 | no | 24.18 s–24.57 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-65 | code-switched | Speaker 1 | no | 24.67 s–26.30 s | 100.00% | 76.19% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_015 | line-67 | code-switched | Speaker 2 | no | 26.59 s–27.20 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-69 | code-switched | Speaker 3 | no | 28.04 s–28.95 s | 100.00% | 87.50% | 2 | 1 | 0 | 1 |
| liva-en-tl-C_001_015 | line-71 | code-switched | Speaker 3 | yes | 29.83 s–30.83 s | 20.00% | 21.74% | 5 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-73 | code-switched | Speaker 5 | yes | 29.98 s–30.17 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-75 | code-switched | Speaker 5 | yes | 30.74 s–31.33 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-79 | code-switched | Speaker 3 | no | 31.66 s–35.78 s | 68.75% | 32.00% | 16 | 5 | 6 | 0 |
| liva-en-tl-C_001_015 | line-83 | code-switched | Speaker 3 | no | 40.28 s–41.70 s | 50.00% | 33.33% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-91 | code-switched | Speaker 3 | yes | 46.99 s–48.93 s | 87.50% | 82.50% | 8 | 2 | 5 | 0 |
| liva-en-tl-C_001_015 | line-93 | code-switched | Speaker 2 | yes | 47.11 s–48.44 s | 100.00% | 92.86% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-97 | code-switched | Speaker 3 | yes | 54.73 s–56.67 s | 33.33% | 29.41% | 6 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-99 | code-switched | Speaker 5 | yes | 56.48 s–58.11 s | 33.33% | 23.33% | 6 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-103 | code-switched | Speaker 2 | yes | 59.29 s–59.69 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-105 | code-switched | Speaker 3 | yes | 59.35 s–60.28 s | 100.00% | 66.67% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-107 | code-switched | Speaker 5 | no | 60.32 s–60.38 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-109 | code-switched | Speaker 5 | no | 60.96 s–62.01 s | 50.00% | 10.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-111 | code-switched | Speaker 2 | no | 62.95 s–63.04 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-113 | code-switched | Speaker 3 | no | 63.29 s–63.94 s | 50.00% | 75.00% | 2 | 0 | 0 | 1 |
| liva-en-tl-C_001_015 | line-117 | code-switched | Speaker 5 | no | 64.50 s–65.83 s | 40.00% | 24.00% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-119 | code-switched | Speaker 6 | yes | 67.14 s–67.79 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-121 | code-switched | Speaker 3 | yes | 67.58 s–68.63 s | 16.67% | 11.11% | 6 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-125 | code-switched | Speaker 6 | no | 69.11 s–69.13 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-127 | code-switched | Speaker 2 | yes | 71.18 s–71.45 s | 100.00% | 133.33% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-129 | code-switched | Speaker 5 | yes | 71.40 s–73.35 s | 50.00% | 20.00% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-131 | code-switched | Speaker 2 | yes | 74.30 s–76.41 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_015 | line-133 | code-switched | Speaker 3 | yes | 74.57 s–75.23 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-135 | code-switched | Speaker 1 | yes | 76.66 s–77.64 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-137 | code-switched | Speaker 3 | yes | 76.92 s–80.80 s | 20.00% | 3.75% | 15 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-139 | code-switched | Speaker 2 | yes | 80.40 s–80.52 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-141 | code-switched | Speaker 5 | yes | 81.65 s–83.92 s | 14.29% | 13.33% | 7 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-143 | code-switched | Speaker 2 | yes | 81.85 s–82.22 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-147 | code-switched | Speaker 6 | yes | 82.91 s–83.77 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-149 | code-switched | Speaker 6 | yes | 84.89 s–85.29 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-151 | code-switched | Speaker 1 | yes | 85.08 s–86.52 s | 33.33% | 6.67% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-153 | code-switched | Speaker 5 | yes | 87.31 s–88.73 s | 66.67% | 42.86% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-155 | code-switched | Speaker 3 | yes | 87.65 s–89.18 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-157 | code-switched | Speaker 2 | yes | 87.74 s–90.82 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_015 | line-161 | code-switched | Speaker 6 | yes | 88.33 s–90.57 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-165 | code-switched | Speaker 5 | yes | 90.54 s–92.57 s | 100.00% | 100.00% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_015 | line-167 | code-switched | Speaker 3 | yes | 92.11 s–94.22 s | 33.33% | 5.88% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-171 | code-switched | Speaker 5 | yes | 93.85 s–95.82 s | 33.33% | 18.18% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-173 | code-switched | Speaker 2 | yes | 94.54 s–95.16 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-175 | code-switched | Speaker 6 | yes | 94.62 s–97.20 s | 55.56% | 41.18% | 9 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-183 | code-switched | Speaker 3 | yes | 96.88 s–97.97 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-185 | code-switched | Speaker 1 | no | 98.18 s–100.08 s | 100.00% | 84.38% | 8 | 8 | 0 | 0 |
| liva-en-tl-C_001_015 | line-191 | code-switched | Speaker 2 | yes | 100.35 s–101.17 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-193 | code-switched | Speaker 3 | yes | 100.83 s–102.24 s | 100.00% | 100.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-197 | code-switched | Speaker 1 | no | 102.41 s–102.48 s | 100.00% | 133.33% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-199 | code-switched | Speaker 6 | no | 103.33 s–104.00 s | 100.00% | 60.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-203 | code-switched | Speaker 3 | no | 104.44 s–104.88 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-205 | code-switched | Speaker 5 | yes | 104.95 s–108.47 s | 25.00% | 20.51% | 8 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-207 | code-switched | Speaker 3 | yes | 105.48 s–106.09 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-209 | code-switched | Speaker 3 | no | 108.77 s–109.66 s | 50.00% | 42.86% | 4 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-215 | code-switched | Speaker 6 | yes | 110.55 s–112.21 s | 85.71% | 79.41% | 7 | 2 | 4 | 0 |
| liva-en-tl-C_001_015 | line-217 | code-switched | Speaker 3 | yes | 111.04 s–112.54 s | 71.43% | 43.75% | 7 | 3 | 2 | 0 |
| liva-en-tl-C_001_015 | line-219 | code-switched | Speaker 2 | yes | 111.47 s–111.56 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-223 | code-switched | Speaker 5 | yes | 113.16 s–113.77 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-227 | code-switched | Speaker 6 | yes | 113.44 s–114.28 s | 100.00% | 89.66% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_015 | line-229 | code-switched | Speaker 5 | yes | 115.28 s–116.18 s | 100.00% | 93.75% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-231 | code-switched | Speaker 1 | yes | 115.61 s–118.52 s | 45.45% | 17.31% | 11 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-233 | code-switched | Speaker 3 | yes | 115.89 s–116.41 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-239 | code-switched | Speaker 2 | yes | 119.43 s–120.14 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-241 | code-switched | Speaker 6 | yes | 119.65 s–122.32 s | 88.89% | 87.50% | 9 | 1 | 7 | 0 |
| liva-en-tl-C_001_015 | line-243 | code-switched | Speaker 3 | yes | 119.91 s–121.38 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-249 | code-switched | Speaker 3 | yes | 122.79 s–123.33 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-253 | code-switched | Speaker 5 | yes | 123.27 s–124.82 s | 100.00% | 81.82% | 5 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-257 | code-switched | Speaker 6 | yes | 126.43 s–128.07 s | 100.00% | 77.14% | 7 | 7 | 0 | 0 |
| liva-en-tl-C_001_015 | line-259 | code-switched | Speaker 1 | yes | 126.80 s–127.80 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-261 | code-switched | Speaker 3 | yes | 127.47 s–133.03 s | 45.45% | 29.41% | 11 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-265 | code-switched | Speaker 3 | no | 134.08 s–136.70 s | 0.00% | 0.00% | 7 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-267 | code-switched | Speaker 1 | no | 136.96 s–139.18 s | 50.00% | 35.48% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-269 | code-switched | Speaker 2 | no | 139.44 s–139.92 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-271 | code-switched | Speaker 2 | yes | 140.47 s–140.75 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-273 | code-switched | Speaker 3 | yes | 140.53 s–141.88 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-275 | code-switched | Speaker 6 | no | 143.53 s–145.46 s | 50.00% | 35.71% | 8 | 2 | 2 | 0 |
| liva-en-tl-C_001_015 | line-279 | code-switched | Speaker 1 | yes | 146.95 s–148.81 s | 50.00% | 36.36% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-281 | code-switched | Speaker 3 | yes | 147.92 s–148.25 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-283 | code-switched | Speaker 3 | yes | 150.48 s–153.78 s | 28.57% | 11.76% | 7 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-285 | code-switched | Speaker 2 | yes | 152.17 s–152.21 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-287 | code-switched | Speaker 2 | yes | 153.04 s–154.86 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-289 | code-switched | Speaker 1 | no | 158.51 s–159.56 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-291 | code-switched | Speaker 3 | no | 160.30 s–161.57 s | 83.33% | 53.57% | 6 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-293 | code-switched | Speaker 1 | no | 162.56 s–163.06 s | 100.00% | 90.91% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-295 | code-switched | Speaker 3 | no | 165.00 s–166.31 s | 20.00% | 21.43% | 5 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-297 | code-switched | Speaker 1 | no | 166.88 s–167.10 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-299 | code-switched | Speaker 3 | yes | 167.70 s–168.71 s | 66.67% | 23.08% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-301 | code-switched | Speaker 6 | yes | 168.05 s–170.16 s | 100.00% | 100.00% | 8 | 0 | 8 | 0 |
| liva-en-tl-C_001_015 | line-303 | code-switched | Speaker 3 | no | 171.08 s–172.69 s | 16.67% | 2.78% | 6 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-307 | code-switched | Speaker 1 | yes | 175.52 s–176.78 s | 50.00% | 33.33% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-309 | code-switched | Speaker 3 | yes | 175.85 s–177.56 s | 100.00% | 100.00% | 8 | 0 | 8 | 0 |
| liva-en-tl-C_001_015 | line-313 | code-switched | Speaker 1 | no | 178.48 s–179.86 s | 50.00% | 50.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-319 | code-switched | Speaker 3 | no | 184.88 s–185.90 s | 100.00% | 54.55% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-321 | code-switched | Speaker 3 | no | 186.80 s–188.47 s | 71.43% | 36.36% | 7 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-325 | code-switched | Speaker 1 | no | 192.64 s–194.17 s | 100.00% | 100.00% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-327 | code-switched | Speaker 3 | no | 194.30 s–196.48 s | 62.50% | 27.27% | 8 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-329 | code-switched | Speaker 1 | no | 198.88 s–200.04 s | 50.00% | 50.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-331 | code-switched | Speaker 3 | yes | 201.04 s–202.19 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-333 | code-switched | Speaker 2 | yes | 201.34 s–202.64 s | 100.00% | 100.00% | 9 | 0 | 9 | 0 |
| liva-en-tl-C_001_015 | line-335 | code-switched | Speaker 3 | no | 204.24 s–206.31 s | 28.57% | 14.29% | 7 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-339 | code-switched | Speaker 3 | yes | 210.50 s–211.69 s | 25.00% | 12.50% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-341 | code-switched | Speaker 2 | yes | 211.22 s–211.69 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-343 | code-switched | Speaker 2 | no | 213.55 s–214.22 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-345 | code-switched | Speaker 3 | no | 216.30 s–216.73 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-347 | code-switched | Speaker 3 | no | 217.46 s–221.18 s | 50.00% | 30.00% | 16 | 5 | 2 | 1 |
| liva-en-tl-C_001_015 | line-351 | code-switched | Speaker 2 | yes | 222.72 s–223.84 s | 83.33% | 92.31% | 6 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-353 | code-switched | Speaker 5 | yes | 223.27 s–224.54 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-355 | code-switched | Speaker 3 | yes | 225.12 s–227.43 s | 50.00% | 33.33% | 8 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-357 | code-switched | Speaker 5 | yes | 225.24 s–227.10 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-359 | code-switched | Speaker 1 | no | 229.59 s–230.16 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-361 | code-switched | Speaker 5 | yes | 230.91 s–234.10 s | 30.77% | 21.05% | 13 | 3 | 1 | 0 |
| liva-en-tl-C_001_015 | line-365 | code-switched | Speaker 3 | yes | 234.09 s–236.36 s | 50.00% | 30.77% | 8 | 3 | 1 | 0 |
| liva-en-tl-C_001_015 | line-369 | code-switched | Speaker 5 | no | 236.88 s–237.13 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-371 | code-switched | Speaker 3 | no | 238.03 s–238.52 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-373 | code-switched | Speaker 2 | no | 238.61 s–240.24 s | 100.00% | 75.86% | 7 | 6 | 1 | 0 |
| liva-en-tl-C_001_015 | line-375 | code-switched | Speaker 5 | no | 240.80 s–241.56 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-377 | code-switched | Speaker 3 | yes | 242.89 s–243.35 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-379 | code-switched | Speaker 1 | yes | 243.27 s–243.70 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-381 | code-switched | Speaker 5 | yes | 244.14 s–245.00 s | 80.00% | 41.67% | 5 | 2 | 2 | 0 |
| liva-en-tl-C_001_015 | line-383 | code-switched | Speaker 1 | yes | 244.41 s–245.33 s | 50.00% | 43.75% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-385 | code-switched | Speaker 3 | no | 246.00 s–247.00 s | 50.00% | 28.00% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-387 | code-switched | Speaker 1 | no | 248.06 s–248.99 s | 50.00% | 20.00% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-389 | code-switched | Speaker 3 | no | 249.53 s–250.38 s | 40.00% | 22.22% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-391 | code-switched | Speaker 3 | no | 253.35 s–255.10 s | 83.33% | 31.03% | 6 | 4 | 0 | 1 |
| liva-en-tl-C_001_015 | line-393 | code-switched | Speaker 3 | no | 256.83 s–257.84 s | 50.00% | 90.91% | 4 | 1 | 0 | 1 |
| liva-en-tl-C_001_015 | line-395 | code-switched | Speaker 3 | no | 258.62 s–260.12 s | 100.00% | 65.00% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-399 | code-switched | Speaker 3 | yes | 265.28 s–266.45 s | 50.00% | 33.33% | 6 | 2 | 0 | 1 |
| liva-en-tl-C_001_015 | line-401 | code-switched | Speaker 2 | yes | 265.50 s–266.10 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-405 | code-switched | Speaker 2 | no | 266.96 s–268.12 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-407 | code-switched | Speaker 3 | no | 270.03 s–272.12 s | 75.00% | 80.00% | 8 | 0 | 6 | 0 |
| liva-en-tl-C_001_015 | line-409 | code-switched | Speaker 6 | no | 273.59 s–274.35 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-411 | code-switched | Speaker 6 | no | 275.05 s–275.21 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-413 | code-switched | Speaker 2 | no | 277.63 s–277.74 s | 100.00% | 166.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-417 | code-switched | Speaker 2 | no | 280.68 s–281.16 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-419 | code-switched | Speaker 3 | no | 282.78 s–284.11 s | 37.50% | 35.90% | 8 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-421 | code-switched | Speaker 2 | no | 285.17 s–285.22 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-423 | code-switched | Speaker 5 | yes | 286.09 s–286.77 s | 100.00% | 75.00% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_015 | line-425 | code-switched | Speaker 3 | yes | 286.22 s–287.07 s | 33.33% | 21.43% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-429 | code-switched | Speaker 6 | no | 289.56 s–289.73 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-431 | code-switched | Speaker 2 | no | 289.73 s–290.06 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-433 | code-switched | Speaker 3 | no | 292.46 s–293.67 s | 50.00% | 5.88% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-435 | code-switched | Speaker 2 | no | 296.12 s–296.61 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-437 | code-switched | Speaker 6 | no | 298.22 s–298.49 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-439 | code-switched | Speaker 3 | yes | 299.20 s–302.23 s | 83.33% | 60.34% | 12 | 10 | 0 | 0 |
| liva-en-tl-C_001_015 | line-443 | code-switched | Speaker 2 | yes | 301.59 s–302.10 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-447 | code-switched | Speaker 1 | yes | 309.74 s–311.67 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-449 | code-switched | Speaker 3 | yes | 310.14 s–311.11 s | 33.33% | 33.33% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-451 | code-switched | Speaker 3 | yes | 313.23 s–314.34 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-455 | code-switched | Speaker 6 | yes | 313.62 s–313.88 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-457 | code-switched | Speaker 6 | no | 315.16 s–316.00 s | 100.00% | 105.56% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-461 | code-switched | Speaker 1 | no | 316.00 s–317.99 s | 50.00% | 27.78% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-463 | code-switched | Speaker 3 | no | 318.90 s–319.23 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-467 | code-switched | Speaker 2 | yes | 319.97 s–320.64 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-469 | code-switched | Speaker 3 | yes | 320.21 s–320.44 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-475 | code-switched | Speaker 1 | no | 321.78 s–322.96 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-479 | code-switched | Speaker 5 | no | 324.29 s–324.99 s | 66.67% | 33.33% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-481 | code-switched | Speaker 3 | yes | 326.02 s–328.74 s | 27.27% | 12.96% | 11 | 1 | 1 | 1 |
| liva-en-tl-C_001_015 | line-485 | code-switched | Speaker 1 | yes | 328.38 s–329.06 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-489 | code-switched | Speaker 2 | no | 330.30 s–331.01 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-493 | code-switched | Speaker 3 | yes | 331.99 s–332.90 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-495 | code-switched | Speaker 2 | yes | 332.12 s–332.27 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-497 | code-switched | Speaker 3 | yes | 333.90 s–336.25 s | 83.33% | 85.19% | 6 | 1 | 4 | 0 |
| liva-en-tl-C_001_015 | line-499 | code-switched | Speaker 2 | yes | 333.92 s–334.55 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-505 | code-switched | Speaker 2 | yes | 337.94 s–338.92 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-507 | code-switched | Speaker 3 | yes | 338.17 s–340.67 s | 83.33% | 90.32% | 6 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-515 | code-switched | Speaker 3 | yes | 342.71 s–346.34 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_015 | line-519 | code-switched | Speaker 2 | yes | 343.07 s–344.74 s | 75.00% | 50.00% | 8 | 4 | 2 | 0 |
| liva-en-tl-C_001_015 | line-521 | code-switched | Speaker 2 | no | 346.81 s–348.46 s | 100.00% | 74.29% | 8 | 8 | 0 | 0 |
| liva-en-tl-C_001_015 | line-531 | code-switched | Speaker 6 | yes | 349.28 s–350.45 s | 100.00% | 88.00% | 5 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-533 | code-switched | Speaker 3 | yes | 349.61 s–351.73 s | 100.00% | 78.38% | 7 | 7 | 0 | 0 |
| liva-en-tl-C_001_015 | line-535 | code-switched | Speaker 2 | yes | 350.72 s–352.03 s | 100.00% | 80.00% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-539 | code-switched | Speaker 3 | no | 352.87 s–353.13 s | 100.00% | 266.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-545 | code-switched | Speaker 3 | yes | 355.68 s–359.74 s | 50.00% | 56.34% | 12 | 2 | 4 | 0 |
| liva-en-tl-C_001_015 | line-551 | code-switched | Speaker 2 | yes | 358.96 s–360.55 s | 100.00% | 93.10% | 7 | 5 | 2 | 0 |
| liva-en-tl-C_001_015 | line-553 | code-switched | Speaker 3 | no | 363.02 s–363.25 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-557 | code-switched | Speaker 2 | no | 364.48 s–364.63 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-559 | code-switched | Speaker 3 | no | 365.32 s–365.53 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-561 | code-switched | Speaker 1 | no | 366.86 s–367.74 s | 50.00% | 62.50% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-567 | code-switched | Speaker 1 | yes | 369.40 s–372.56 s | 100.00% | 95.45% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_015 | line-569 | code-switched | Speaker 6 | yes | 372.32 s–373.16 s | 100.00% | 75.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-575 | code-switched | Speaker 6 | no | 373.86 s–374.39 s | 100.00% | 125.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-579 | code-switched | Speaker 3 | no | 375.86 s–376.18 s | 100.00% | 233.33% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-581 | code-switched | Speaker 3 | no | 376.75 s–378.45 s | 77.78% | 44.19% | 9 | 5 | 2 | 0 |
| liva-en-tl-C_001_015 | line-587 | code-switched | Speaker 2 | yes | 379.10 s–381.78 s | 77.78% | 60.98% | 9 | 4 | 3 | 0 |
| liva-en-tl-C_001_015 | line-589 | code-switched | Speaker 3 | yes | 379.17 s–379.75 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-591 | code-switched | Speaker 1 | yes | 379.48 s–380.28 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-595 | code-switched | Speaker 2 | yes | 382.72 s–383.03 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-597 | code-switched | Speaker 1 | yes | 382.96 s–384.39 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-599 | code-switched | Speaker 3 | yes | 383.08 s–384.62 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-605 | code-switched | Speaker 1 | yes | 388.64 s–389.63 s | 66.67% | 75.00% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-607 | code-switched | Speaker 2 | yes | 388.70 s–389.08 s | 100.00% | 77.78% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-609 | code-switched | Speaker 3 | yes | 388.72 s–389.99 s | 66.67% | 67.74% | 6 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-613 | code-switched | Speaker 1 | no | 392.52 s–394.28 s | 66.67% | 54.84% | 6 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-617 | code-switched | Speaker 2 | yes | 394.73 s–395.81 s | 25.00% | 22.22% | 4 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-619 | code-switched | Speaker 3 | yes | 395.24 s–395.53 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-621 | code-switched | Speaker 2 | yes | 396.45 s–397.64 s | 100.00% | 84.62% | 5 | 4 | 1 | 0 |
| liva-en-tl-C_001_015 | line-623 | code-switched | Speaker 3 | yes | 396.49 s–397.02 s | 66.67% | 37.50% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-625 | code-switched | Speaker 1 | yes | 398.71 s–401.76 s | 58.33% | 35.48% | 12 | 6 | 1 | 0 |
| liva-en-tl-C_001_015 | line-627 | code-switched | Speaker 2 | yes | 398.87 s–399.68 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-629 | code-switched | Speaker 6 | yes | 398.95 s–399.15 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-633 | code-switched | Speaker 2 | no | 402.82 s–403.21 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-637 | code-switched | Speaker 3 | no | 403.50 s–403.87 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-639 | code-switched | Speaker 2 | yes | 403.95 s–405.34 s | 100.00% | 64.00% | 6 | 3 | 3 | 0 |
| liva-en-tl-C_001_015 | line-641 | code-switched | Speaker 6 | yes | 404.10 s–404.68 s | 100.00% | 91.67% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-645 | code-switched | Speaker 3 | no | 406.53 s–407.93 s | 40.00% | 15.38% | 5 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-647 | code-switched | Speaker 1 | yes | 411.02 s–412.31 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-649 | code-switched | Speaker 3 | yes | 411.69 s–412.46 s | 100.00% | 81.82% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-653 | code-switched | Speaker 1 | yes | 415.16 s–416.45 s | 60.00% | 61.54% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-655 | code-switched | Speaker 3 | yes | 415.58 s–419.26 s | 47.06% | 17.57% | 17 | 3 | 5 | 0 |
| liva-en-tl-C_001_015 | line-657 | code-switched | Speaker 6 | yes | 419.13 s–419.65 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-661 | code-switched | Speaker 3 | no | 420.91 s–421.55 s | 100.00% | 66.67% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-663 | code-switched | Speaker 3 | no | 422.60 s–423.06 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-673 | code-switched | Speaker 2 | no | 427.03 s–427.37 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-677 | code-switched | Speaker 3 | yes | 429.46 s–431.69 s | 83.33% | 45.45% | 6 | 3 | 2 | 0 |
| liva-en-tl-C_001_015 | line-679 | code-switched | Speaker 1 | yes | 429.48 s–430.44 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-683 | code-switched | Speaker 1 | yes | 432.79 s–436.98 s | 50.00% | 42.11% | 10 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-685 | code-switched | Speaker 2 | yes | 432.92 s–434.29 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_015 | line-687 | code-switched | Speaker 3 | yes | 432.97 s–434.13 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-689 | code-switched | Speaker 2 | yes | 435.14 s–435.98 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-691 | code-switched | Speaker 3 | yes | 436.10 s–437.92 s | 100.00% | 100.00% | 9 | 0 | 9 | 0 |
| liva-en-tl-C_001_015 | line-693 | code-switched | Speaker 2 | yes | 436.48 s–437.99 s | 100.00% | 121.43% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_015 | line-695 | code-switched | Speaker 2 | no | 438.51 s–440.18 s | 83.33% | 36.00% | 6 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-699 | code-switched | Speaker 3 | yes | 441.19 s–445.20 s | 58.33% | 36.51% | 12 | 7 | 0 | 0 |
| liva-en-tl-C_001_015 | line-701 | code-switched | Speaker 2 | yes | 442.01 s–442.43 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-703 | code-switched | Speaker 2 | yes | 443.88 s–446.66 s | 62.50% | 45.71% | 8 | 2 | 3 | 0 |
| liva-en-tl-C_001_015 | line-707 | code-switched | Speaker 6 | yes | 449.30 s–450.00 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-709 | code-switched | Speaker 3 | yes | 449.56 s–451.41 s | 62.50% | 33.33% | 8 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-711 | code-switched | Speaker 6 | yes | 451.38 s–452.37 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-713 | code-switched | Speaker 2 | yes | 451.98 s–455.28 s | 50.00% | 34.78% | 10 | 3 | 2 | 0 |
| liva-en-tl-C_001_015 | line-715 | code-switched | Speaker 1 | yes | 452.10 s–452.42 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-717 | code-switched | Speaker 1 | yes | 453.18 s–453.41 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-721 | code-switched | Speaker 3 | yes | 455.28 s–459.47 s | 52.94% | 21.33% | 17 | 7 | 0 | 2 |
| liva-en-tl-C_001_015 | line-725 | code-switched | Speaker 2 | yes | 458.95 s–459.28 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-727 | code-switched | Speaker 1 | yes | 459.32 s–459.48 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-729 | code-switched | Speaker 2 | no | 459.87 s–459.92 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-733 | code-switched | Speaker 2 | yes | 460.62 s–463.84 s | 83.33% | 44.64% | 12 | 10 | 0 | 0 |
| liva-en-tl-C_001_015 | line-743 | code-switched | Speaker 1 | yes | 463.16 s–464.25 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-755 | code-switched | Speaker 1 | no | 469.12 s–469.80 s | 100.00% | 125.00% | 2 | 1 | 0 | 1 |
| liva-en-tl-C_001_015 | line-761 | code-switched | Speaker 2 | no | 472.98 s–473.45 s | 100.00% | 62.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-763 | code-switched | Speaker 1 | no | 474.18 s–475.20 s | 100.00% | 60.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-767 | code-switched | Speaker 2 | yes | 476.77 s–480.08 s | 85.71% | 65.52% | 7 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-771 | code-switched | Speaker 1 | yes | 478.82 s–478.93 s | 100.00% | 300.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-773 | code-switched | Speaker 1 | no | 481.04 s–481.85 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-777 | code-switched | Speaker 3 | yes | 483.13 s–487.16 s | 78.57% | 44.00% | 14 | 10 | 1 | 0 |
| liva-en-tl-C_001_015 | line-781 | code-switched | Speaker 2 | yes | 485.69 s–489.85 s | 91.67% | 67.31% | 12 | 7 | 4 | 0 |
| liva-en-tl-C_001_015 | line-783 | code-switched | Speaker 1 | yes | 486.86 s–488.97 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-785 | code-switched | Speaker 3 | yes | 488.61 s–492.99 s | 75.00% | 73.33% | 8 | 2 | 4 | 0 |
| liva-en-tl-C_001_015 | line-789 | code-switched | Speaker 2 | yes | 490.79 s–491.76 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-791 | code-switched | Speaker 1 | yes | 492.62 s–493.85 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-793 | code-switched | Speaker 2 | yes | 493.30 s–494.35 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-795 | code-switched | Speaker 3 | yes | 493.59 s–495.09 s | 60.00% | 94.74% | 5 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-797 | code-switched | Speaker 2 | yes | 495.25 s–497.58 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-799 | code-switched | Speaker 6 | yes | 495.71 s–496.49 s | 100.00% | 100.00% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-803 | code-switched | Speaker 3 | yes | 496.22 s–497.06 s | 100.00% | 45.45% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-807 | code-switched | Speaker 1 | yes | 498.04 s–499.30 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-811 | code-switched | Speaker 3 | yes | 498.82 s–502.10 s | 10.00% | 9.09% | 10 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-813 | code-switched | Speaker 2 | yes | 499.40 s–500.06 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-817 | code-switched | Speaker 6 | yes | 500.58 s–501.37 s | 50.00% | 29.41% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-821 | code-switched | Speaker 1 | yes | 502.24 s–503.42 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-823 | code-switched | Speaker 2 | yes | 502.70 s–504.01 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_015 | line-825 | code-switched | Speaker 6 | yes | 503.04 s–504.14 s | 100.00% | 78.95% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_015 | line-827 | code-switched | Speaker 3 | yes | 503.20 s–507.24 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-833 | code-switched | Speaker 5 | yes | 504.76 s–505.34 s | 75.00% | 55.56% | 4 | 1 | 2 | 0 |
| liva-en-tl-C_001_015 | line-843 | code-switched | Speaker 3 | no | 508.50 s–509.79 s | 50.00% | 50.00% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_015 | line-845 | code-switched | Speaker 2 | no | 510.32 s–511.42 s | 80.00% | 73.08% | 5 | 2 | 2 | 0 |
| liva-en-tl-C_001_015 | line-851 | code-switched | Speaker 3 | no | 513.14 s–515.05 s | 33.33% | 90.91% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-857 | code-switched | Speaker 3 | no | 516.06 s–518.10 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-861 | code-switched | Speaker 3 | no | 520.28 s–523.12 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-865 | code-switched | Speaker 1 | yes | 523.22 s–524.80 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-867 | code-switched | Speaker 3 | yes | 524.08 s–525.32 s | 75.00% | 20.00% | 4 | 2 | 0 | 1 |
| liva-en-tl-C_001_015 | line-875 | code-switched | Speaker 3 | yes | 527.96 s–530.10 s | 66.67% | 50.00% | 6 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-877 | code-switched | Speaker 2 | yes | 528.46 s–529.58 s | 100.00% | 50.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-885 | code-switched | Speaker 3 | no | 531.99 s–533.47 s | 75.00% | 55.00% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_015 | line-891 | code-switched | Speaker 3 | no | 535.47 s–538.22 s | 66.67% | 41.82% | 12 | 2 | 6 | 0 |
| liva-en-tl-C_001_015 | line-895 | code-switched | Speaker 2 | yes | 538.93 s–541.10 s | 63.64% | 53.33% | 11 | 2 | 5 | 0 |
| liva-en-tl-C_001_015 | line-899 | code-switched | Speaker 6 | yes | 539.29 s–540.34 s | 100.00% | 66.67% | 6 | 5 | 1 | 0 |
| liva-en-tl-C_001_015 | line-907 | code-switched | Speaker 2 | yes | 542.10 s–543.64 s | 100.00% | 68.75% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-909 | code-switched | Speaker 3 | yes | 543.51 s–545.60 s | 85.71% | 54.55% | 7 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-911 | code-switched | Speaker 2 | yes | 545.65 s–550.39 s | 42.11% | 25.00% | 19 | 4 | 4 | 0 |
| liva-en-tl-C_001_015 | line-913 | code-switched | Speaker 6 | yes | 547.42 s–548.74 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_015 | line-915 | code-switched | Speaker 3 | yes | 548.03 s–548.13 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-917 | code-switched | Speaker 3 | yes | 549.94 s–550.90 s | 66.67% | 27.27% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-921 | code-switched | Speaker 2 | no | 552.08 s–553.01 s | 80.00% | 42.86% | 5 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-923 | code-switched | Speaker 3 | no | 553.49 s–555.94 s | 100.00% | 85.71% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-925 | code-switched | Speaker 3 | no | 556.55 s–556.93 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-927 | code-switched | Speaker 2 | yes | 559.06 s–560.19 s | 100.00% | 44.83% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-929 | code-switched | Speaker 3 | yes | 559.89 s–560.82 s | 40.00% | 57.14% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_015 | line-931 | code-switched | Speaker 6 | yes | 561.46 s–561.92 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-933 | code-switched | Speaker 3 | yes | 561.58 s–562.19 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-935 | code-switched | Speaker 6 | yes | 562.79 s–564.02 s | 85.71% | 86.11% | 7 | 0 | 6 | 0 |
| liva-en-tl-C_001_015 | line-937 | code-switched | Speaker 2 | yes | 563.04 s–563.21 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-941 | code-switched | Speaker 2 | yes | 565.05 s–565.57 s | 75.00% | 72.22% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_015 | line-945 | code-switched | Speaker 3 | yes | 565.22 s–566.01 s | 100.00% | 76.19% | 5 | 3 | 2 | 0 |
| liva-en-tl-C_001_015 | line-949 | code-switched | Speaker 3 | yes | 568.43 s–570.24 s | 85.71% | 32.56% | 7 | 6 | 0 | 0 |
| liva-en-tl-C_001_015 | line-951 | code-switched | Speaker 2 | yes | 568.78 s–569.00 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-953 | code-switched | Speaker 2 | no | 570.79 s–571.19 s | 100.00% | 60.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-955 | code-switched | Speaker 3 | no | 572.82 s–573.80 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-959 | code-switched | Speaker 2 | yes | 575.08 s–579.04 s | 70.00% | 57.78% | 10 | 4 | 3 | 0 |
| liva-en-tl-C_001_015 | line-961 | code-switched | Speaker 3 | yes | 575.56 s–576.36 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-963 | code-switched | Speaker 6 | yes | 576.75 s–577.64 s | 75.00% | 81.25% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_015 | line-965 | code-switched | Speaker 3 | yes | 578.83 s–578.86 s | 100.00% | 200.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_015 | line-971 | code-switched | Speaker 3 | no | 580.00 s–581.64 s | 0.00% | 0.00% | 6 | 0 | 0 | 0 |
| liva-en-tl-C_001_015 | line-979 | code-switched | Speaker 1 | yes | 584.25 s–586.51 s | 83.33% | 65.00% | 6 | 3 | 2 | 0 |
| liva-en-tl-C_001_015 | line-981 | code-switched | Speaker 6 | yes | 585.38 s–586.49 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_015 | line-983 | code-switched | Speaker 3 | yes | 585.72 s–592.52 s | 100.00% | 57.58% | 6 | 5 | 1 | 0 |
| liva-en-tl-C_001_015 | line-987 | code-switched | Speaker 1 | yes | 587.72 s–589.52 s | 25.00% | 17.65% | 4 | 0 | 1 | 0 |
| liva-en-tl-C_001_015 | line-989 | code-switched | Speaker 2 | yes | 589.78 s–591.50 s | 100.00% | 88.10% | 7 | 2 | 5 | 0 |
| liva-en-tl-C_001_015 | line-991 | code-switched | Speaker 2 | no | 592.56 s–594.39 s | 50.00% | 35.90% | 8 | 4 | 0 | 0 |
| liva-en-tl-C_001_015 | line-995 | code-switched | Speaker 3 | yes | 595.62 s–598.62 s | 71.43% | 68.00% | 7 | 5 | 0 | 0 |
| liva-en-tl-C_001_015 | line-997 | code-switched | Speaker 1 | yes | 595.90 s–597.46 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_015 | line-1003 | code-switched | Speaker 3 | no | 599.32 s–600.02 s | 50.00% | 30.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-1 | code-switched | Speaker 3 | yes | 0.00 s–4.11 s | 66.67% | 43.75% | 15 | 6 | 4 | 0 |
| liva-en-tl-C_001_016 | line-5 | code-switched | Speaker 2 | yes | 0.81 s–1.18 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-7 | code-switched | Speaker 2 | yes | 1.72 s–1.79 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-9 | code-switched | Speaker 2 | yes | 3.86 s–4.92 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-11 | code-switched | Speaker 6 | yes | 4.88 s–5.60 s | 40.00% | 34.78% | 5 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-13 | code-switched | Speaker 2 | yes | 5.55 s–5.66 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-15 | code-switched | Speaker 3 | no | 5.73 s–5.87 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-17 | code-switched | Speaker 2 | yes | 7.49 s–14.13 s | 68.18% | 42.57% | 22 | 7 | 8 | 0 |
| liva-en-tl-C_001_016 | line-19 | code-switched | Speaker 3 | yes | 7.62 s–7.91 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-27 | code-switched | Speaker 3 | yes | 11.34 s–15.99 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-31 | code-switched | Speaker 6 | yes | 14.64 s–15.74 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-37 | code-switched | Speaker 1 | no | 17.46 s–18.32 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-39 | code-switched | Speaker 3 | no | 18.37 s–21.77 s | 80.00% | 49.06% | 10 | 7 | 1 | 0 |
| liva-en-tl-C_001_016 | line-45 | code-switched | Speaker 3 | no | 23.48 s–23.65 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-47 | code-switched | Speaker 3 | no | 25.28 s–26.46 s | 83.33% | 26.09% | 6 | 3 | 2 | 0 |
| liva-en-tl-C_001_016 | line-49 | code-switched | Speaker 3 | no | 26.98 s–28.41 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-53 | code-switched | Speaker 5 | yes | 29.08 s–29.69 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-55 | code-switched | Speaker 1 | yes | 29.23 s–30.69 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-61 | code-switched | Speaker 3 | no | 31.02 s–31.73 s | 100.00% | 62.50% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-63 | code-switched | Speaker 2 | no | 31.74 s–31.78 s | 100.00% | 300.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-65 | code-switched | Speaker 2 | yes | 32.29 s–33.62 s | 66.67% | 56.67% | 6 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-67 | code-switched | Speaker 1 | yes | 32.45 s–33.31 s | 100.00% | 77.78% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-69 | code-switched | Speaker 1 | yes | 34.91 s–37.48 s | 85.71% | 89.09% | 14 | 0 | 12 | 0 |
| liva-en-tl-C_001_016 | line-71 | code-switched | Speaker 3 | yes | 34.96 s–35.79 s | 100.00% | 83.33% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-73 | code-switched | Speaker 2 | yes | 35.53 s–36.70 s | 100.00% | 166.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-75 | code-switched | Speaker 3 | yes | 36.49 s–37.97 s | 80.00% | 60.87% | 5 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-77 | code-switched | Speaker 2 | no | 38.03 s–38.46 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-79 | code-switched | Speaker 3 | yes | 39.28 s–42.59 s | 36.36% | 33.33% | 11 | 1 | 3 | 0 |
| liva-en-tl-C_001_016 | line-81 | code-switched | Speaker 2 | yes | 41.84 s–45.89 s | 100.00% | 100.00% | 8 | 0 | 8 | 0 |
| liva-en-tl-C_001_016 | line-83 | code-switched | Speaker 3 | yes | 43.12 s–44.20 s | 100.00% | 83.33% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-85 | code-switched | Speaker 5 | yes | 43.36 s–43.93 s | 100.00% | 40.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-87 | code-switched | Speaker 3 | yes | 46.11 s–49.14 s | 42.86% | 14.29% | 7 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-89 | code-switched | Speaker 2 | yes | 46.74 s–48.64 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-91 | code-switched | Speaker 1 | yes | 49.75 s–50.83 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-93 | code-switched | Speaker 3 | yes | 49.75 s–50.04 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-95 | code-switched | Speaker 3 | yes | 51.58 s–55.67 s | 31.58% | 14.46% | 19 | 3 | 2 | 1 |
| liva-en-tl-C_001_016 | line-99 | code-switched | Speaker 2 | yes | 53.06 s–53.50 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-103 | code-switched | Speaker 2 | yes | 54.74 s–54.85 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-105 | code-switched | Speaker 1 | yes | 56.03 s–58.42 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-107 | code-switched | Speaker 2 | yes | 56.41 s–56.90 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-109 | code-switched | Speaker 3 | yes | 56.83 s–61.92 s | 33.33% | 32.84% | 15 | 1 | 4 | 0 |
| liva-en-tl-C_001_016 | line-111 | code-switched | Speaker 2 | yes | 59.54 s–62.69 s | 76.92% | 50.00% | 13 | 7 | 3 | 0 |
| liva-en-tl-C_001_016 | line-113 | code-switched | Speaker 1 | yes | 60.92 s–61.80 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-115 | code-switched | Speaker 1 | yes | 63.48 s–64.41 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-117 | code-switched | Speaker 3 | yes | 63.59 s–65.93 s | 44.44% | 17.02% | 9 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-119 | code-switched | Speaker 1 | yes | 66.70 s–68.86 s | 70.00% | 53.85% | 10 | 2 | 5 | 0 |
| liva-en-tl-C_001_016 | line-121 | code-switched | Speaker 2 | yes | 66.88 s–67.65 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-123 | code-switched | Speaker 3 | yes | 66.90 s–67.49 s | 33.33% | 37.50% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-127 | code-switched | Speaker 3 | yes | 68.36 s–70.07 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-129 | code-switched | Speaker 2 | yes | 68.72 s–69.21 s | 100.00% | 91.67% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-131 | code-switched | Speaker 3 | no | 70.81 s–72.09 s | 50.00% | 23.08% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-133 | code-switched | Speaker 1 | no | 72.90 s–73.08 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-135 | code-switched | Speaker 3 | no | 73.79 s–74.59 s | 100.00% | 33.33% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-141 | code-switched | Speaker 3 | yes | 76.69 s–78.11 s | 50.00% | 29.63% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-143 | code-switched | Speaker 2 | yes | 77.26 s–77.63 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-151 | code-switched | Speaker 3 | yes | 81.08 s–84.88 s | 88.89% | 75.81% | 9 | 1 | 7 | 0 |
| liva-en-tl-C_001_016 | line-153 | code-switched | Speaker 2 | yes | 82.32 s–83.61 s | 100.00% | 162.50% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-157 | code-switched | Speaker 3 | yes | 85.38 s–87.72 s | 66.67% | 49.02% | 9 | 4 | 2 | 0 |
| liva-en-tl-C_001_016 | line-161 | code-switched | Speaker 6 | yes | 87.59 s–89.44 s | 85.71% | 73.17% | 7 | 3 | 3 | 0 |
| liva-en-tl-C_001_016 | line-163 | code-switched | Speaker 1 | yes | 88.22 s–92.49 s | 55.56% | 27.45% | 9 | 5 | 0 | 0 |
| liva-en-tl-C_001_016 | line-165 | code-switched | Speaker 3 | no | 92.99 s–94.44 s | 100.00% | 61.54% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-175 | code-switched | Speaker 3 | no | 96.11 s–96.92 s | 100.00% | 57.14% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-177 | code-switched | Speaker 3 | yes | 97.90 s–101.07 s | 100.00% | 75.00% | 6 | 6 | 0 | 0 |
| liva-en-tl-C_001_016 | line-181 | code-switched | Speaker 2 | yes | 100.34 s–100.96 s | 100.00% | 100.00% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-185 | code-switched | Speaker 1 | no | 101.88 s–105.29 s | 28.57% | 4.35% | 7 | 1 | 0 | 1 |
| liva-en-tl-C_001_016 | line-191 | code-switched | Speaker 3 | no | 106.41 s–107.92 s | 100.00% | 72.73% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-197 | code-switched | Speaker 3 | no | 108.44 s–108.67 s | 100.00% | 200.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-199 | code-switched | Speaker 3 | no | 109.25 s–109.90 s | 100.00% | 42.86% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-201 | code-switched | Speaker 3 | no | 110.75 s–114.62 s | 16.67% | 10.53% | 12 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-209 | code-switched | Speaker 3 | no | 117.36 s–117.52 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-215 | code-switched | Speaker 3 | yes | 121.58 s–125.61 s | 26.32% | 15.38% | 19 | 5 | 0 | 0 |
| liva-en-tl-C_001_016 | line-217 | code-switched | Speaker 1 | yes | 121.87 s–122.60 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-221 | code-switched | Speaker 5 | no | 127.21 s–128.09 s | 50.00% | 31.25% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-223 | code-switched | Speaker 5 | no | 128.86 s–131.15 s | 90.00% | 59.65% | 10 | 7 | 2 | 0 |
| liva-en-tl-C_001_016 | line-229 | code-switched | Speaker 5 | yes | 132.98 s–133.32 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-231 | code-switched | Speaker 1 | yes | 132.99 s–133.55 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-235 | code-switched | Speaker 3 | yes | 134.03 s–134.44 s | 100.00% | 250.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-237 | code-switched | Speaker 1 | yes | 134.23 s–135.86 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-239 | code-switched | Speaker 5 | yes | 134.45 s–135.26 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-241 | code-switched | Speaker 2 | yes | 134.74 s–136.51 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-243 | code-switched | Speaker 3 | yes | 134.94 s–135.94 s | 50.00% | 57.14% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-245 | code-switched | Speaker 1 | yes | 136.51 s–137.63 s | 100.00% | 92.86% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-247 | code-switched | Speaker 3 | yes | 136.56 s–139.96 s | 71.43% | 20.83% | 7 | 5 | 0 | 0 |
| liva-en-tl-C_001_016 | line-249 | code-switched | Speaker 5 | no | 141.03 s–142.35 s | 66.67% | 9.09% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-251 | code-switched | Speaker 2 | yes | 143.11 s–144.07 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-253 | code-switched | Speaker 1 | yes | 143.29 s–145.45 s | 33.33% | 11.11% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-255 | code-switched | Speaker 2 | yes | 144.84 s–144.94 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-257 | code-switched | Speaker 3 | yes | 145.74 s–149.54 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-259 | code-switched | Speaker 5 | yes | 145.95 s–146.91 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-261 | code-switched | Speaker 1 | yes | 146.23 s–146.84 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-263 | code-switched | Speaker 1 | yes | 147.62 s–148.05 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-265 | code-switched | Speaker 2 | yes | 148.91 s–151.53 s | 25.00% | 7.14% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-269 | code-switched | Speaker 1 | yes | 150.27 s–151.22 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-271 | code-switched | Speaker 5 | yes | 150.68 s–151.64 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-273 | code-switched | Speaker 1 | yes | 151.82 s–154.54 s | 37.50% | 26.32% | 8 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-275 | code-switched | Speaker 3 | yes | 152.70 s–153.23 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-277 | code-switched | Speaker 3 | yes | 154.21 s–154.60 s | 100.00% | 50.00% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-279 | code-switched | Speaker 3 | yes | 155.36 s–159.14 s | 25.00% | 6.41% | 16 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-281 | code-switched | Speaker 2 | yes | 155.54 s–156.17 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-287 | code-switched | Speaker 2 | yes | 161.49 s–162.00 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-289 | code-switched | Speaker 1 | yes | 161.68 s–163.48 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-291 | code-switched | Speaker 3 | yes | 163.32 s–169.58 s | 76.47% | 68.83% | 17 | 2 | 11 | 0 |
| liva-en-tl-C_001_016 | line-295 | code-switched | Speaker 5 | yes | 165.23 s–169.01 s | 90.91% | 80.00% | 11 | 2 | 8 | 0 |
| liva-en-tl-C_001_016 | line-299 | code-switched | Speaker 2 | yes | 166.87 s–167.31 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-301 | code-switched | Speaker 1 | yes | 168.08 s–172.42 s | 50.00% | 21.95% | 8 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-303 | code-switched | Speaker 2 | yes | 169.30 s–170.49 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-305 | code-switched | Speaker 5 | yes | 169.58 s–170.95 s | 100.00% | 68.75% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-307 | code-switched | Speaker 1 | yes | 172.92 s–175.54 s | 60.00% | 33.33% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-309 | code-switched | Speaker 3 | yes | 173.84 s–174.11 s | 100.00% | 150.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-311 | code-switched | Speaker 2 | yes | 174.20 s–174.67 s | 66.67% | 70.00% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-313 | code-switched | Speaker 3 | yes | 174.62 s–177.37 s | 83.33% | 80.00% | 6 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-315 | code-switched | Speaker 3 | no | 178.48 s–179.35 s | 100.00% | 37.50% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-317 | code-switched | Speaker 1 | yes | 180.35 s–182.78 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-319 | code-switched | Speaker 3 | yes | 180.35 s–181.22 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-321 | code-switched | Speaker 3 | no | 182.99 s–185.40 s | 28.57% | 23.08% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-327 | code-switched | Speaker 1 | no | 187.64 s–188.88 s | 33.33% | 29.63% | 6 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-329 | code-switched | Speaker 2 | yes | 190.22 s–190.32 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-331 | code-switched | Speaker 1 | yes | 190.31 s–190.92 s | 100.00% | 125.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-333 | code-switched | Speaker 1 | yes | 191.96 s–194.66 s | 0.00% | 0.00% | 5 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-335 | code-switched | Speaker 2 | yes | 192.58 s–192.62 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-341 | code-switched | Speaker 1 | no | 196.64 s–198.50 s | 12.50% | 10.81% | 8 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-343 | code-switched | Speaker 3 | yes | 200.16 s–201.61 s | 0.00% | 0.00% | 6 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-345 | code-switched | Speaker 2 | yes | 200.66 s–200.91 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-347 | code-switched | Speaker 1 | no | 202.87 s–203.47 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-353 | code-switched | Speaker 3 | no | 204.41 s–205.54 s | 40.00% | 31.82% | 5 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-355 | code-switched | Speaker 3 | no | 206.13 s–207.88 s | 66.67% | 33.33% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-359 | code-switched | Speaker 1 | yes | 208.22 s–209.71 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-361 | code-switched | Speaker 2 | yes | 208.98 s–212.08 s | 66.67% | 83.33% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-363 | code-switched | Speaker 3 | yes | 211.32 s–212.40 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-365 | code-switched | Speaker 5 | yes | 211.40 s–212.69 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-367 | code-switched | Speaker 2 | yes | 212.67 s–213.47 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-369 | code-switched | Speaker 1 | yes | 212.87 s–214.71 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-371 | code-switched | Speaker 3 | yes | 213.28 s–214.41 s | 100.00% | 93.75% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-379 | code-switched | Speaker 3 | no | 217.43 s–218.53 s | 100.00% | 90.91% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-381 | code-switched | Speaker 2 | no | 219.78 s–220.64 s | 100.00% | 87.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-387 | code-switched | Speaker 2 | yes | 225.37 s–226.44 s | 50.00% | 63.64% | 4 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-389 | code-switched | Speaker 1 | yes | 225.64 s–226.14 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-391 | code-switched | Speaker 2 | yes | 227.08 s–227.94 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-395 | code-switched | Speaker 3 | yes | 227.87 s–228.74 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-397 | code-switched | Speaker 5 | yes | 229.26 s–230.25 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-399 | code-switched | Speaker 1 | yes | 229.47 s–231.82 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-401 | code-switched | Speaker 2 | yes | 230.72 s–231.43 s | 100.00% | 88.89% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-403 | code-switched | Speaker 5 | yes | 230.84 s–236.23 s | 60.00% | 71.21% | 10 | 1 | 5 | 0 |
| liva-en-tl-C_001_016 | line-405 | code-switched | Speaker 3 | yes | 232.23 s–233.47 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-407 | code-switched | Speaker 1 | yes | 232.35 s–232.54 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-409 | code-switched | Speaker 2 | yes | 232.59 s–232.86 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-413 | code-switched | Speaker 2 | yes | 233.73 s–236.78 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-417 | code-switched | Speaker 3 | yes | 235.95 s–241.05 s | 100.00% | 64.29% | 8 | 3 | 5 | 0 |
| liva-en-tl-C_001_016 | line-419 | code-switched | Speaker 5 | yes | 237.63 s–239.20 s | 100.00% | 30.77% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-429 | code-switched | Speaker 5 | yes | 240.35 s–243.27 s | 33.33% | 36.67% | 6 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-431 | code-switched | Speaker 2 | yes | 241.43 s–242.79 s | 80.00% | 81.82% | 5 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-433 | code-switched | Speaker 3 | yes | 242.73 s–243.47 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-435 | code-switched | Speaker 1 | no | 244.56 s–244.77 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-439 | code-switched | Speaker 5 | no | 246.59 s–247.63 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-443 | code-switched | Speaker 2 | no | 248.10 s–248.60 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-445 | code-switched | Speaker 3 | yes | 249.70 s–251.72 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-447 | code-switched | Speaker 1 | yes | 250.41 s–251.44 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-451 | code-switched | Speaker 5 | yes | 252.63 s–253.65 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-453 | code-switched | Speaker 1 | yes | 252.89 s–253.70 s | 50.00% | 75.00% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-455 | code-switched | Speaker 3 | yes | 253.10 s–253.26 s | 100.00% | 200.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-457 | code-switched | Speaker 3 | yes | 254.17 s–256.57 s | 50.00% | 33.33% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-459 | code-switched | Speaker 2 | yes | 255.87 s–256.32 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-461 | code-switched | Speaker 1 | yes | 257.07 s–262.18 s | 50.00% | 29.76% | 18 | 3 | 6 | 0 |
| liva-en-tl-C_001_016 | line-463 | code-switched | Speaker 2 | yes | 257.30 s–257.35 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-465 | code-switched | Speaker 5 | yes | 258.72 s–259.46 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-467 | code-switched | Speaker 2 | yes | 258.84 s–259.38 s | 100.00% | 116.67% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-469 | code-switched | Speaker 5 | yes | 260.18 s–261.09 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-471 | code-switched | Speaker 2 | yes | 260.63 s–260.91 s | 50.00% | 50.00% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-473 | code-switched | Speaker 5 | no | 262.55 s–263.81 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-477 | code-switched | Speaker 2 | no | 263.91 s–265.19 s | 100.00% | 50.00% | 5 | 3 | 2 | 0 |
| liva-en-tl-C_001_016 | line-479 | code-switched | Speaker 3 | yes | 266.58 s–267.35 s | 33.33% | 23.53% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-481 | code-switched | Speaker 5 | yes | 266.89 s–267.18 s | 100.00% | 75.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-483 | code-switched | Speaker 5 | yes | 267.76 s–268.87 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-485 | code-switched | Speaker 2 | yes | 268.25 s–268.52 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-487 | code-switched | Speaker 3 | yes | 268.44 s–269.52 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-489 | code-switched | Speaker 2 | yes | 269.16 s–270.09 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-491 | code-switched | Speaker 5 | yes | 270.62 s–271.34 s | 50.00% | 31.25% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-495 | code-switched | Speaker 2 | yes | 270.77 s–271.51 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-497 | code-switched | Speaker 2 | no | 272.20 s–273.19 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-501 | code-switched | Speaker 1 | no | 273.65 s–274.50 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-503 | code-switched | Speaker 2 | no | 275.72 s–275.98 s | 100.00% | 75.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-505 | code-switched | Speaker 5 | no | 277.11 s–278.95 s | 55.56% | 32.65% | 9 | 3 | 2 | 0 |
| liva-en-tl-C_001_016 | line-507 | code-switched | Speaker 3 | yes | 279.03 s–280.41 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-509 | code-switched | Speaker 2 | yes | 279.05 s–279.96 s | 100.00% | 50.00% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-511 | code-switched | Speaker 2 | no | 280.80 s–280.93 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-513 | code-switched | Speaker 1 | yes | 281.38 s–283.78 s | 57.14% | 34.62% | 7 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-515 | code-switched | Speaker 5 | yes | 283.57 s–284.89 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-517 | code-switched | Speaker 2 | yes | 284.25 s–286.20 s | 75.00% | 43.59% | 12 | 5 | 4 | 0 |
| liva-en-tl-C_001_016 | line-519 | code-switched | Speaker 5 | no | 286.33 s–287.59 s | 75.00% | 50.00% | 4 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-521 | code-switched | Speaker 3 | no | 288.66 s–289.84 s | 33.33% | 12.50% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-523 | code-switched | Speaker 1 | yes | 290.30 s–291.61 s | 25.00% | 22.73% | 4 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-525 | code-switched | Speaker 3 | yes | 290.91 s–294.94 s | 84.62% | 56.67% | 13 | 4 | 7 | 0 |
| liva-en-tl-C_001_016 | line-527 | code-switched | Speaker 1 | yes | 293.98 s–297.35 s | 53.85% | 27.94% | 13 | 6 | 1 | 0 |
| liva-en-tl-C_001_016 | line-529 | code-switched | Speaker 5 | yes | 294.31 s–294.62 s | 100.00% | 80.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-531 | code-switched | Speaker 2 | yes | 297.33 s–298.46 s | 20.00% | 7.41% | 5 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-533 | code-switched | Speaker 6 | yes | 298.68 s–299.92 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-535 | code-switched | Speaker 3 | yes | 298.77 s–299.68 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-537 | code-switched | Speaker 6 | yes | 300.53 s–302.35 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_016 | line-539 | code-switched | Speaker 3 | yes | 301.33 s–302.94 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-541 | code-switched | Speaker 2 | yes | 303.31 s–303.68 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-543 | code-switched | Speaker 5 | yes | 303.55 s–305.07 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-545 | code-switched | Speaker 2 | yes | 305.46 s–306.33 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-547 | code-switched | Speaker 6 | yes | 305.49 s–306.49 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-549 | code-switched | Speaker 1 | yes | 305.62 s–308.64 s | 75.00% | 55.00% | 8 | 3 | 3 | 0 |
| liva-en-tl-C_001_016 | line-553 | code-switched | Speaker 2 | no | 309.38 s–311.53 s | 85.71% | 72.22% | 7 | 2 | 4 | 0 |
| liva-en-tl-C_001_016 | line-555 | code-switched | Speaker 6 | yes | 312.30 s–313.08 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-557 | code-switched | Speaker 2 | yes | 312.35 s–313.05 s | 100.00% | 138.46% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-559 | code-switched | Speaker 1 | yes | 313.15 s–315.94 s | 50.00% | 49.09% | 12 | 4 | 2 | 0 |
| liva-en-tl-C_001_016 | line-561 | code-switched | Speaker 2 | yes | 314.85 s–315.15 s | 100.00% | 160.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-563 | code-switched | Speaker 2 | yes | 316.16 s–317.48 s | 55.56% | 58.54% | 9 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-567 | code-switched | Speaker 6 | yes | 317.40 s–318.11 s | 100.00% | 70.00% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-569 | code-switched | Speaker 1 | yes | 318.98 s–320.73 s | 42.86% | 9.09% | 7 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-571 | code-switched | Speaker 2 | yes | 319.27 s–319.55 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-575 | code-switched | Speaker 2 | yes | 322.38 s–322.83 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-579 | code-switched | Speaker 3 | yes | 322.78 s–324.30 s | 66.67% | 75.00% | 6 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-581 | code-switched | Speaker 3 | yes | 324.82 s–326.06 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-583 | code-switched | Speaker 2 | yes | 325.40 s–326.89 s | 100.00% | 97.56% | 6 | 1 | 5 | 0 |
| liva-en-tl-C_001_016 | line-585 | code-switched | Speaker 5 | yes | 326.36 s–329.24 s | 72.73% | 57.69% | 11 | 5 | 3 | 0 |
| liva-en-tl-C_001_016 | line-587 | code-switched | Speaker 1 | yes | 326.84 s–327.41 s | 100.00% | 84.62% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-591 | code-switched | Speaker 3 | no | 329.76 s–330.54 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-597 | code-switched | Speaker 2 | yes | 332.88 s–333.58 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-599 | code-switched | Speaker 3 | yes | 333.26 s–333.99 s | 33.33% | 6.67% | 3 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-603 | code-switched | Speaker 1 | no | 334.60 s–338.40 s | 38.46% | 16.18% | 13 | 4 | 1 | 0 |
| liva-en-tl-C_001_016 | line-607 | code-switched | Speaker 3 | no | 339.65 s–340.64 s | 100.00% | 70.59% | 3 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-609 | code-switched | Speaker 1 | yes | 343.04 s–344.06 s | 100.00% | 100.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-611 | code-switched | Speaker 2 | yes | 343.48 s–344.34 s | 100.00% | 100.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-613 | code-switched | Speaker 1 | no | 345.06 s–346.34 s | 50.00% | 33.33% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-615 | code-switched | Speaker 5 | no | 346.78 s–347.60 s | 33.33% | 35.29% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-617 | code-switched | Speaker 5 | yes | 348.40 s–349.51 s | 60.00% | 54.17% | 5 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-619 | code-switched | Speaker 3 | yes | 348.90 s–349.76 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-621 | code-switched | Speaker 5 | yes | 350.21 s–351.10 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-623 | code-switched | Speaker 2 | yes | 350.41 s–351.40 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-625 | code-switched | Speaker 3 | yes | 350.85 s–351.15 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-627 | code-switched | Speaker 5 | yes | 351.95 s–352.67 s | 50.00% | 7.14% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-629 | code-switched | Speaker 1 | yes | 352.06 s–353.12 s | 50.00% | 7.69% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-631 | code-switched | Speaker 2 | yes | 353.56 s–354.23 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-633 | code-switched | Speaker 1 | yes | 354.14 s–358.21 s | 40.00% | 33.33% | 10 | 1 | 3 | 0 |
| liva-en-tl-C_001_016 | line-635 | code-switched | Speaker 3 | yes | 354.55 s–355.33 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-637 | code-switched | Speaker 2 | yes | 356.91 s–359.40 s | 100.00% | 89.66% | 10 | 2 | 8 | 0 |
| liva-en-tl-C_001_016 | line-643 | code-switched | Speaker 3 | yes | 360.59 s–360.88 s | 100.00% | 250.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-645 | code-switched | Speaker 5 | yes | 360.62 s–361.77 s | 25.00% | 17.65% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-647 | code-switched | Speaker 3 | no | 361.96 s–362.78 s | 75.00% | 47.83% | 4 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-649 | code-switched | Speaker 3 | no | 363.32 s–364.09 s | 100.00% | 94.44% | 3 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-651 | code-switched | Speaker 1 | yes | 364.33 s–366.82 s | 25.00% | 9.68% | 8 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-653 | code-switched | Speaker 2 | yes | 364.67 s–365.21 s | 100.00% | 90.48% | 5 | 1 | 4 | 0 |
| liva-en-tl-C_001_016 | line-655 | code-switched | Speaker 1 | yes | 368.21 s–372.13 s | 0.00% | 0.00% | 9 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-657 | code-switched | Speaker 3 | yes | 372.06 s–372.75 s | 75.00% | 46.67% | 4 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-659 | code-switched | Speaker 2 | no | 373.24 s–373.70 s | 100.00% | 100.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-661 | code-switched | Speaker 1 | no | 374.01 s–380.75 s | 55.56% | 48.39% | 18 | 5 | 5 | 0 |
| liva-en-tl-C_001_016 | line-665 | code-switched | Speaker 6 | no | 381.33 s–382.13 s | 66.67% | 71.43% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-667 | code-switched | Speaker 3 | yes | 382.17 s–384.19 s | 100.00% | 75.00% | 4 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-669 | code-switched | Speaker 6 | yes | 384.13 s–384.21 s | 100.00% | 400.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-673 | code-switched | Speaker 2 | yes | 385.61 s–386.19 s | 100.00% | 93.75% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_016 | line-675 | code-switched | Speaker 1 | yes | 385.88 s–388.18 s | 40.00% | 21.62% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-679 | code-switched | Speaker 2 | no | 389.74 s–390.29 s | 100.00% | 72.73% | 2 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-681 | code-switched | Speaker 3 | yes | 390.72 s–393.27 s | 75.00% | 44.74% | 8 | 6 | 0 | 0 |
| liva-en-tl-C_001_016 | line-683 | code-switched | Speaker 2 | yes | 391.35 s–394.80 s | 100.00% | 100.00% | 10 | 0 | 10 | 0 |
| liva-en-tl-C_001_016 | line-685 | code-switched | Speaker 3 | yes | 394.49 s–395.65 s | 100.00% | 76.92% | 3 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-687 | code-switched | Speaker 5 | no | 396.05 s–396.50 s | 50.00% | 12.50% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-689 | code-switched | Speaker 5 | no | 397.08 s–397.81 s | 50.00% | 46.67% | 2 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-691 | code-switched | Speaker 2 | no | 397.81 s–398.36 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-693 | code-switched | Speaker 2 | no | 399.68 s–400.00 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-695 | code-switched | Speaker 3 | yes | 401.43 s–403.96 s | 100.00% | 73.91% | 7 | 4 | 3 | 0 |
| liva-en-tl-C_001_016 | line-697 | code-switched | Speaker 2 | yes | 401.52 s–403.01 s | 50.00% | 48.39% | 4 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-699 | code-switched | Speaker 1 | yes | 401.78 s–403.24 s | 66.67% | 68.42% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-703 | code-switched | Speaker 3 | no | 406.48 s–407.75 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-705 | code-switched | Speaker 2 | yes | 408.35 s–409.92 s | 85.71% | 23.08% | 7 | 5 | 1 | 0 |
| liva-en-tl-C_001_016 | line-707 | code-switched | Speaker 1 | yes | 409.84 s–410.58 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-709 | code-switched | Speaker 1 | no | 411.19 s–411.76 s | 50.00% | 33.33% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-711 | code-switched | Speaker 3 | no | 413.55 s–414.46 s | 66.67% | 37.50% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-713 | code-switched | Speaker 2 | no | 414.56 s–415.27 s | 60.00% | 63.64% | 5 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-717 | code-switched | Speaker 3 | yes | 416.62 s–419.18 s | 50.00% | 32.61% | 10 | 2 | 3 | 0 |
| liva-en-tl-C_001_016 | line-719 | code-switched | Speaker 1 | yes | 416.69 s–417.53 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-723 | code-switched | Speaker 2 | no | 420.38 s–420.66 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-725 | code-switched | Speaker 5 | yes | 423.09 s–423.76 s | 50.00% | 56.25% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-727 | code-switched | Speaker 6 | yes | 423.20 s–423.35 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-729 | code-switched | Speaker 2 | no | 424.17 s–425.17 s | 75.00% | 54.17% | 4 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-731 | code-switched | Speaker 6 | no | 425.69 s–427.27 s | 66.67% | 52.17% | 6 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-733 | code-switched | Speaker 2 | yes | 428.58 s–429.09 s | 100.00% | 100.00% | 4 | 1 | 3 | 0 |
| liva-en-tl-C_001_016 | line-735 | code-switched | Speaker 3 | yes | 428.98 s–430.61 s | 50.00% | 21.88% | 8 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-737 | code-switched | Speaker 3 | no | 431.15 s–432.70 s | 60.00% | 20.83% | 5 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-739 | code-switched | Speaker 1 | yes | 433.71 s–434.58 s | 0.00% | 0.00% | 4 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-741 | code-switched | Speaker 5 | yes | 434.00 s–434.17 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-743 | code-switched | Speaker 5 | yes | 436.08 s–436.99 s | 75.00% | 43.75% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-745 | code-switched | Speaker 1 | yes | 436.54 s–439.10 s | 20.00% | 12.12% | 5 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-747 | code-switched | Speaker 3 | yes | 436.60 s–437.04 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-749 | code-switched | Speaker 2 | yes | 438.77 s–438.87 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-751 | code-switched | Speaker 5 | yes | 439.16 s–440.43 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-753 | code-switched | Speaker 2 | yes | 439.41 s–439.56 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-757 | code-switched | Speaker 3 | no | 440.95 s–441.61 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-759 | code-switched | Speaker 2 | no | 442.64 s–442.83 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-761 | code-switched | Speaker 3 | no | 442.95 s–446.08 s | 50.00% | 29.03% | 12 | 3 | 3 | 0 |
| liva-en-tl-C_001_016 | line-763 | code-switched | Speaker 5 | no | 446.35 s–449.36 s | 50.00% | 20.51% | 8 | 3 | 1 | 0 |
| liva-en-tl-C_001_016 | line-765 | code-switched | Speaker 2 | yes | 450.80 s–451.66 s | 60.00% | 26.32% | 5 | 1 | 2 | 0 |
| liva-en-tl-C_001_016 | line-767 | code-switched | Speaker 5 | yes | 451.20 s–451.28 s | 100.00% | 125.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-769 | code-switched | Speaker 6 | yes | 451.54 s–452.15 s | 75.00% | 78.57% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-771 | code-switched | Speaker 5 | yes | 452.98 s–454.05 s | 85.71% | 93.33% | 7 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-773 | code-switched | Speaker 3 | yes | 453.26 s–453.94 s | 66.67% | 69.23% | 3 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-775 | code-switched | Speaker 3 | no | 455.07 s–458.22 s | 40.00% | 27.66% | 10 | 1 | 3 | 0 |
| liva-en-tl-C_001_016 | line-777 | code-switched | Speaker 2 | no | 458.24 s–459.42 s | 50.00% | 48.15% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-779 | code-switched | Speaker 3 | yes | 460.70 s–461.45 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-781 | code-switched | Speaker 5 | yes | 461.07 s–463.20 s | 100.00% | 77.78% | 7 | 6 | 0 | 1 |
| liva-en-tl-C_001_016 | line-783 | code-switched | Speaker 3 | yes | 464.93 s–466.43 s | 50.00% | 17.24% | 6 | 2 | 0 | 1 |
| liva-en-tl-C_001_016 | line-785 | code-switched | Speaker 1 | yes | 464.96 s–465.92 s | 66.67% | 55.56% | 3 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-789 | code-switched | Speaker 5 | no | 468.11 s–470.29 s | 50.00% | 37.93% | 6 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-791 | code-switched | Speaker 3 | yes | 470.65 s–471.26 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-793 | code-switched | Speaker 5 | yes | 470.83 s–471.23 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-795 | code-switched | Speaker 2 | yes | 472.99 s–474.00 s | 100.00% | 100.00% | 6 | 0 | 6 | 0 |
| liva-en-tl-C_001_016 | line-797 | code-switched | Speaker 3 | yes | 473.08 s–474.73 s | 25.00% | 19.51% | 8 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-799 | code-switched | Speaker 1 | yes | 475.65 s–476.39 s | 0.00% | 0.00% | 2 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-801 | code-switched | Speaker 2 | yes | 475.92 s–476.16 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-803 | code-switched | Speaker 3 | no | 477.23 s–477.61 s | 50.00% | 14.29% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-807 | code-switched | Speaker 5 | yes | 479.28 s–479.92 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-809 | code-switched | Speaker 1 | yes | 479.73 s–480.22 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-811 | code-switched | Speaker 2 | no | 480.93 s–481.61 s | 50.00% | 35.29% | 4 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-813 | code-switched | Speaker 5 | no | 483.35 s–484.56 s | 75.00% | 87.50% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-817 | code-switched | Speaker 2 | yes | 485.47 s–486.28 s | 100.00% | 80.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-819 | code-switched | Speaker 3 | yes | 485.90 s–486.26 s | 100.00% | 66.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-823 | code-switched | Speaker 1 | yes | 487.62 s–488.72 s | 25.00% | 33.33% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-825 | code-switched | Speaker 3 | yes | 487.96 s–488.51 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-827 | code-switched | Speaker 5 | no | 492.32 s–493.02 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-829 | code-switched | Speaker 5 | no | 493.56 s–494.91 s | 0.00% | 0.00% | 7 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-831 | code-switched | Speaker 1 | no | 495.22 s–497.49 s | 22.22% | 2.50% | 9 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-833 | code-switched | Speaker 5 | yes | 497.88 s–498.98 s | 75.00% | 84.21% | 4 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-835 | code-switched | Speaker 3 | yes | 497.96 s–498.83 s | 100.00% | 81.25% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-839 | code-switched | Speaker 5 | no | 500.44 s–501.77 s | 50.00% | 22.86% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-841 | code-switched | Speaker 1 | yes | 502.14 s–505.10 s | 55.56% | 27.03% | 9 | 5 | 0 | 0 |
| liva-en-tl-C_001_016 | line-843 | code-switched | Speaker 5 | yes | 502.32 s–502.98 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-845 | code-switched | Speaker 1 | yes | 505.88 s–507.66 s | 40.00% | 23.08% | 5 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-847 | code-switched | Speaker 6 | yes | 507.47 s–508.25 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-849 | code-switched | Speaker 3 | yes | 507.94 s–509.44 s | 62.50% | 65.62% | 8 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-851 | code-switched | Speaker 5 | yes | 508.31 s–509.35 s | 100.00% | 70.59% | 4 | 2 | 2 | 0 |
| liva-en-tl-C_001_016 | line-855 | code-switched | Speaker 5 | yes | 510.24 s–512.50 s | 50.00% | 16.67% | 6 | 3 | 0 | 0 |
| liva-en-tl-C_001_016 | line-857 | code-switched | Speaker 1 | yes | 511.72 s–515.27 s | 192.86% | 145.83% | 14 | 7 | 0 | 20 |
| liva-en-tl-C_001_016 | line-859 | code-switched | Speaker 6 | yes | 513.24 s–513.52 s | 100.00% | 71.43% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-861 | code-switched | Speaker 3 | yes | 513.38 s–514.43 s | 100.00% | 91.67% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-863 | code-switched | Speaker 1 | yes | 518.15 s–521.23 s | 10.00% | 11.76% | 10 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-865 | code-switched | Speaker 6 | yes | 518.43 s–518.48 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-869 | code-switched | Speaker 5 | no | 522.43 s–522.84 s | 100.00% | 112.50% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-871 | code-switched | Speaker 5 | no | 523.72 s–525.10 s | 28.57% | 21.43% | 7 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-875 | code-switched | Speaker 3 | no | 526.00 s–526.86 s | 25.00% | 5.56% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-877 | code-switched | Speaker 2 | yes | 527.24 s–528.53 s | 100.00% | 100.00% | 7 | 0 | 7 | 0 |
| liva-en-tl-C_001_016 | line-879 | code-switched | Speaker 3 | yes | 527.83 s–528.85 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-881 | code-switched | Speaker 3 | no | 530.44 s–530.66 s | 100.00% | 50.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-885 | code-switched | Speaker 2 | no | 531.29 s–531.84 s | 100.00% | 110.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-887 | code-switched | Speaker 3 | yes | 533.35 s–533.96 s | 100.00% | 110.00% | 2 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-889 | code-switched | Speaker 1 | yes | 533.66 s–533.94 s | 100.00% | 160.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-891 | code-switched | Speaker 2 | no | 535.12 s–536.03 s | 100.00% | 38.89% | 4 | 4 | 0 | 0 |
| liva-en-tl-C_001_016 | line-895 | code-switched | Speaker 2 | no | 536.60 s–538.68 s | 22.22% | 13.64% | 9 | 1 | 0 | 1 |
| liva-en-tl-C_001_016 | line-897 | code-switched | Speaker 2 | no | 541.83 s–542.42 s | 0.00% | 0.00% | 3 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-899 | code-switched | Speaker 2 | no | 543.67 s–543.75 s | 100.00% | 100.00% | 1 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-901 | code-switched | Speaker 2 | yes | 545.10 s–546.43 s | 60.00% | 27.27% | 5 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-903 | code-switched | Speaker 6 | yes | 545.48 s–546.30 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-905 | code-switched | Speaker 6 | no | 549.73 s–550.23 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |
| liva-en-tl-C_001_016 | line-909 | code-switched | Speaker 1 | no | 553.88 s–556.45 s | 50.00% | 35.00% | 4 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-915 | code-switched | Speaker 5 | no | 558.60 s–558.93 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-917 | code-switched | Speaker 3 | yes | 559.00 s–561.68 s | 100.00% | 100.00% | 9 | 0 | 9 | 0 |
| liva-en-tl-C_001_016 | line-919 | code-switched | Speaker 1 | yes | 559.12 s–559.83 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-921 | code-switched | Speaker 5 | no | 563.98 s–564.95 s | 25.00% | 5.26% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-923 | code-switched | Speaker 6 | yes | 565.93 s–567.79 s | 66.67% | 57.69% | 6 | 1 | 3 | 0 |
| liva-en-tl-C_001_016 | line-925 | code-switched | Speaker 1 | yes | 566.21 s–567.12 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-927 | code-switched | Speaker 5 | yes | 566.23 s–566.91 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-929 | code-switched | Speaker 2 | yes | 566.49 s–566.71 s | 100.00% | 125.00% | 1 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-931 | code-switched | Speaker 5 | yes | 568.88 s–569.57 s | 50.00% | 11.11% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-933 | code-switched | Speaker 2 | yes | 569.30 s–570.17 s | 100.00% | 100.00% | 4 | 0 | 4 | 0 |
| liva-en-tl-C_001_016 | line-935 | code-switched | Speaker 2 | no | 570.84 s–571.09 s | 50.00% | 33.33% | 2 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-939 | code-switched | Speaker 3 | no | 571.48 s–574.45 s | 62.50% | 35.48% | 8 | 2 | 3 | 0 |
| liva-en-tl-C_001_016 | line-941 | code-switched | Speaker 2 | no | 575.23 s–577.12 s | 77.78% | 39.02% | 9 | 6 | 1 | 0 |
| liva-en-tl-C_001_016 | line-943 | code-switched | Speaker 3 | no | 578.94 s–580.02 s | 66.67% | 32.14% | 6 | 4 | 0 | 0 |
| liva-en-tl-C_001_016 | line-945 | code-switched | Speaker 3 | no | 581.08 s–581.85 s | 66.67% | 25.00% | 3 | 2 | 0 | 0 |
| liva-en-tl-C_001_016 | line-947 | code-switched | Speaker 3 | no | 582.63 s–583.66 s | 33.33% | 50.00% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-949 | code-switched | Speaker 5 | yes | 585.06 s–585.60 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-951 | code-switched | Speaker 3 | yes | 585.32 s–586.63 s | 75.00% | 40.00% | 4 | 2 | 1 | 0 |
| liva-en-tl-C_001_016 | line-955 | code-switched | Speaker 5 | no | 586.71 s–589.01 s | 20.00% | 17.24% | 5 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-957 | code-switched | Speaker 2 | yes | 589.71 s–590.28 s | 100.00% | 100.00% | 5 | 0 | 5 | 0 |
| liva-en-tl-C_001_016 | line-959 | code-switched | Speaker 5 | yes | 589.88 s–590.36 s | 100.00% | 100.00% | 2 | 0 | 2 | 0 |
| liva-en-tl-C_001_016 | line-961 | code-switched | Speaker 1 | yes | 590.07 s–591.26 s | 83.33% | 62.50% | 6 | 2 | 3 | 0 |
| liva-en-tl-C_001_016 | line-963 | code-switched | Speaker 3 | yes | 590.08 s–592.48 s | 71.43% | 62.96% | 7 | 1 | 4 | 0 |
| liva-en-tl-C_001_016 | line-965 | code-switched | Speaker 2 | no | 592.66 s–592.87 s | 0.00% | 0.00% | 1 | 0 | 0 | 0 |
| liva-en-tl-C_001_016 | line-967 | code-switched | Speaker 2 | yes | 594.86 s–595.78 s | 100.00% | 88.46% | 5 | 2 | 3 | 0 |
| liva-en-tl-C_001_016 | line-969 | code-switched | Speaker 1 | yes | 595.19 s–596.54 s | 25.00% | 6.67% | 4 | 1 | 0 | 0 |
| liva-en-tl-C_001_016 | line-971 | code-switched | Speaker 2 | no | 596.57 s–597.09 s | 33.33% | 25.00% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-973 | code-switched | Speaker 6 | no | 597.94 s–598.52 s | 50.00% | 42.11% | 4 | 1 | 1 | 0 |
| liva-en-tl-C_001_016 | line-975 | code-switched | Speaker 2 | yes | 598.78 s–600.02 s | 33.33% | 43.75% | 3 | 0 | 1 | 0 |
| liva-en-tl-C_001_016 | line-977 | code-switched | Speaker 1 | yes | 599.15 s–600.02 s | 100.00% | 100.00% | 3 | 0 | 3 | 0 |

The raw reference and hypothesis of each item are in the JSON report, unchanged.
