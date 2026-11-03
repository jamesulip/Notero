# Benchmarks

Measured performance, with the conditions that produced each number.

**Read the conditions before you use a number.** Most of the results here come
from one 57-second synthetic test clip on one Mac. They are useful to compare
one configuration against another. They are not a promise about your meetings,
your voices or your Mac. [Limitations](#limitations) says where each number
stops being valid.

[FINDINGS.md](FINDINGS.md) holds the numbered findings that these measurements
came from, together with the failures that they exposed.

## The hardware

| | The plan assumed | The measurement Mac |
| --- | --- | --- |
| Machine | Mac mini M2 Pro | **MacBook Pro, Apple M5 Pro** |
| Cores | — | 15 (5 efficiency and 10 performance) |
| RAM | — | 24 GB |
| macOS | — | 26.6.2 |

**The measurement Mac is faster than the memory target.** The app is designed
for a 16 GB M2 Pro. Every measurement here is therefore an upper bound on what
an M2 Pro would do. [ENVIRONMENT.md](ENVIRONMENT.md) is the dated record of
this machine.

## The test material

| Clip | Length | Source | Reference |
| --- | --- | --- | --- |
| `synthetic-taglish` | 57 s | The macOS `say` command with the Indonesian voice, reading a Taglish script. `eval/make-synthetic.sh` builds it. | 123 words, `eval/synthetic-taglish.txt` |
| `meeting01` | 25 s | A real meeting excerpt. | 59 words, hand-kept, `eval/refs/meeting01.txt` |

**Neither clip is a fair test.** `eval/audio/` is not in git, thus these are
the two clips that the maintainer has. The synthetic clip uses an Indonesian
voice, because macOS ships no Filipino voice. It is close in phonology and
wrong in acoustics. It also begins at full amplitude at sample 0 with no
lead-in, which is not how a real recording behaves. The real excerpt is short
and its reference is too poor to draw a conclusion from: the offline WER on it
is 60%, and each live variant sits inside that spread.

**`meeting01` is not on every machine.** `eval/manifest.json` references it, and
on the Mac mini M2 Pro used for the [2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro)
neither its audio nor its reference exists, so only the synthetic clip was
measured there. [Test material that exists](#test-material-that-exists) lists
what is on disk, and [What real data is needed](#what-real-data-is-needed) says
what to collect.

## The method

`transcribe` produces every number below. It calls the same pipeline as the
app, thus a measurement here is a measurement of the shipping code and not of a
test harness. [CLI.md](CLI.md) gives the options.

- **RTF** is the wall-clock decode time divided by the audio duration. Lower is
  faster. 0.10 means 10 times faster than real time.
- **WER** is the word error rate against the reference file. Two scorers exist
  for the tables in this file.
  The WER of the command-line tool splits an intra-word hyphen.
  `eval/langscore.py` keeps it, thus "i-send" stays one Filipino word there.
  The two therefore report different numbers for the same transcript, and each
  table below says which one produced it. For new numbers, use
  [the evaluation framework](#the-evaluation-framework). It records its scoring
  policy in each report.
- **"Peak memory"** is what the older numbers in this file call it, and it is
  neither a peak nor a model's memory. `transcribe` printed `phys_footprint`,
  read once at exit: the footprint of one process at that instant. It leaves
  out the Neural Engine memory that holds the loaded model. Read
  [Which number is which](#which-number-is-which) before you quote any memory
  figure here.
- `eval/out/run-live.sh` is the script that produced the live comparison.
- `eval/compare_language.py` produced the language comparison.

## Which number is which

Several figures in this project share a name and measure different things. Each
row says where the number comes from and what it is not.

### Speed

| Figure | What it is | Where `transcribe` reports it | What it is not |
| --- | --- | --- | --- |
| **Whole-file RTF** | `decodeMs` over the audio length for an **offline** run. It includes voice activity detection, every window and every retry. It excludes the model load and diarization. | `rtf` in the JSON, the `decoded … (RTF …)` line | A live latency. A live hop never decodes the whole file. |
| **Model load time** | Wall time to load the model. The first load after a model or OS change compiles CoreML (284 s once); a cached load took about 10 s. | `loadMs` in the JSON, the `model load … ms` line | Part of any RTF. |
| **Replay RTF** (live) | Wall time of a `--live` replay over the audio length. With every decode awaited it is how fast this Mac replays the file on this schedule. Under `--realtime` it is about 1.0 **by construction**, because the feed is paced at wall-clock speed. | `rtf` in the JSON when `mode` starts with `live` | A per-hop cost. Never compare it with an offline RTF. |
| **Per-decode time** | What one call to the recognizer costs: the model's own `inferMs`, and the wall time around the call. The gap between them is audio conversion and actor hops, which the model's clock leaves out ([The adaptive hop](#the-adaptive-hop)). Reported as median, p95 and max. | `decodeTiming` in the JSON, the `per decode:` line | A whole-file figure. |
| **Per-decode RTF** | Sum of `inferMs` over the sum of audio handed to the model. A live decode reads a window of up to 15 s plus pre-roll to advance the transcript by one 1.5 s hop, so this number is **not** `inferMs` over the hop. | `live.meanRtf`, `decodeTiming.inferRtf` | The cost of a hop. Compare per-decode time with the hop: a p95 decode time above 1500 ms means that real-time pacing drops hops. |
| **Commit latency** | The clock at the moment a word was committed, minus the time that the word ended in the audio. Median, mean, p95 and max over words. The clock is *audio fed so far* (the mechanism: how long the commit policy waits for agreement and for a pause) and, under `--realtime` only, *wall time since the replay began* (adds what the machine costs). | `commitLatency`, `commitLatencyWall`, the `commit latency` line | A measure of when the word appears on screen. A provisional word shows earlier. It is when the word becomes **final**. |
| **Dropped hops** | Hops discarded because the previous decode was still running. Meaningful only under `--realtime`. With awaited decodes it is zero by construction. | `live.droppedHops` | |

### Memory

| Figure | What it is | What it is not |
| --- | --- | --- |
| **Process footprint** (`phys_footprint`) | Dirty and compressed pages of this one process, plus some IOKit mappings. What Activity Monitor shows as Memory. | The memory a model needs. |
| **Lifetime peak footprint** | The highest `phys_footprint` this process has reached, from the kernel's ledger and `/usr/bin/time -l` (`peak memory footprint`). | |
| **Footprint at exit** | `phys_footprint` read once, when `transcribe` finished. **This is what `transcribe` printed as "peak memory" until 2026-11-01.** It is a single reading at the end, so it can sit far below the real peak. | A peak. |
| **Neural Engine memory** | Memory that CoreML placed on the Neural Engine and that the kernel attributes to this process as "neural, nofootprint" (`footprint(1)`; `ledger_tag_neural_nofootprint_*`). **It is not in the footprint.** This is the residency-style figure for a loaded model. | A figure for the whole machine. |
| **System-wide `vm_stat`** | Free, wired and compressed pages of the whole Mac. | Anything about one process. On a shared Mac it moves for reasons that have nothing to do with the model, so no figure in this file quotes a `vm_stat` delta as a model's size. |

**Never present a smaller process footprint as lower model memory.** The model
is not in it. A build can show a smaller footprint and need exactly as much
memory for the model, because the model's memory is somewhere the footprint does
not look. Compare footprints only between stages of one build, and quote the
Neural Engine figure beside them. `eval/residency.py` measures the same stages
from outside the process, with `footprint(1)`, as an independent check on the
in-process figures.

## The evaluation framework

`transcribe --score` and the `Evaluation` module of `TranscriberCore` score
transcripts against references with one written method. Use it for new accuracy
numbers. This section is the method. [CLI.md](CLI.md#score-saved-transcripts)
gives the commands.

**The framework has produced no benchmark result yet.** It was added on
2026-11-02 and tested on synthetic text only. No table in this file comes from
it. The older tables keep the scorer that each one names.

### What the framework guarantees

1. **The same inputs give the same bytes.** The reports contain no clock, no
   random value without a seed, and no absolute path. Two runs on one corpus
   give identical JSON and Markdown files.
2. **The raw text stays unchanged.** The report keeps the reference and the
   hypothesis exactly as supplied, byte for byte. The scorer normalizes a copy.
3. **A metric without ground truth is "unavailable", with a reason.** The
   framework never reports 0, 1 or a blank for a missing value. A WER over an
   empty reference is unavailable. A WER over an empty hypothesis is 100%, and
   it is a real measurement.
4. **Scoring uses no network and no model.** `--score` reads files and writes
   files. It stops before the tool opens an audio device or loads a model.

### The inputs

| Input | Form |
| --- | --- |
| Manifest | The array that `eval/manifest.json` and the corrections export already use, `[{"id", "audio", "ref", "category"}]`. Or the versioned form `{"schemaVersion": 1, "corpusId": "...", "items": [...]}`. Paths are relative to the manifest. |
| Corpus ID | The `corpusId` of a versioned manifest, or `--corpus-id`. An array manifest gets `manifest-sha256:` and the first 16 hex digits of the SHA-256 of its bytes. |
| Reference, plain text | One utterance on each line that is not empty. It has no times, no speakers and no language. The manifest `category` (`tagalog`, `english` or `mixed`) becomes the language of each line. |
| Reference, JSON | `{"schemaVersion": 1, "itemId", "utterances": [...]}`. Each utterance has `id` and `text`. It can also have `startMs`, `endMs`, `speaker`, `overlap`, `language` and `languageSpans`. |
| Hypothesis | `<id>.json`, the `--json` report of a `transcribe` run, or `<id>.txt`, plain text from any system. Only the JSON form has word times and run measurements. |
| Configuration | `eval/evaluation-config.v1.json` is the default. `transcribe --print-eval-config` writes it. A file with an unknown `schemaVersion` is refused. |

`languageSpans` marks the language word by word. The spans of an utterance,
in sequence, must join to its `text` exactly, or the reference is refused. Put
each span boundary between two words. `eval/fixtures/scoring/refs/standup.json`
is an example.

### The scoring policy

A policy changes text into the units that the framework counts. A policy has an
`id`, a `version` and a SHA-256 fingerprint. Each report records all three.
The steps always run in this sequence:

1. Unicode normalization: none, NFC, NFD, NFKC or NFKD.
2. U+2019, U+2018, U+02BC, U+0060 and U+00B4 become the apostrophe U+0027.
3. Case folding, if set.
4. Contraction expansion, if set, from table version 1.
5. Diacritic removal, if set.
6. Tokenization. Letters, combining marks and digits make words. Apostrophes
   and hyphens follow their own settings. All other characters are
   punctuation. Punctuation is removed or kept as separate tokens.

| Policy | Rules | Use |
| --- | --- | --- |
| `notero-standard` | NFKC, case folded, punctuation removed, hyphens split, apostrophes kept inside a word, diacritics kept. | **The default.** It gives the same tokens and the same counts as `eval/score.py`, which produced the 2026-11-01 tables. |
| `notero-keep-hyphens` | As `notero-standard`, but "i-send" stays one word. | Close to `eval/langscore.py`. It is not identical: the two scorers treat en dashes and U+2010 differently. |
| `notero-legacy-cli` | No normalization, case folded, diacritics removed, every character that is not a letter or a digit splits words. | The same tokens as `WordErrorRate`, the scorer of `--reference` in builds before this one. |
| `notero-expand-contractions` | As `notero-standard`, with contractions expanded on both sides. | Compare transcripts that write "ako'y" and "ako ay", or "don't" and "do not", in different ways. |

`notero-standard` and `eval/score.py` differ on four rare inputs. The framework
splits words at an underscore, keeps a combining mark in its word, changes
U+02BC and the backtick to an apostrophe, and lower-cases final sigma as "σ".
The tests record each difference.

Contraction table version 1 expands the English negations ("don't"), the
English pronoun and verb forms ("I'm", "we're", "it's", "I'll", "I've"), the
Tagalog enclitic "'y" ("ako'y" to "ako ay"), and the clipped Tagalog forms
"di", "wag", "yan", "yun", "yon" and "yung", with or without an apostrophe.
It does not expand "'to", because "to" is also an English word. It does not
expand "'d" or "'s", because each has more than one meaning.

### The metrics

- **WER** is (S + D + I) / N, where N is the number of reference words. One
  word alignment covers the whole recording. At each cell the alignment takes
  a match if the two words are equal. Otherwise it takes the first minimum of
  substitution, deletion and insertion, in that sequence. This rule gives the
  same split into S, D and I as `eval/score.py`.
- **The corpus WER** is the sum of the errors of all scored recordings divided
  by the sum of their reference words. It is not a mean of the WER values of
  the recordings.
- **Utterance results** come from the alignment of the recording. A matched or
  substituted word belongs to the utterance of its reference word. An inserted
  word belongs to the utterance of the nearest reference word before it. If no
  reference word comes before it, it belongs to the utterance of the first
  reference word after it. The results of the utterances add up exactly to the
  result of the recording.
- **CER** is the character error rate. For each utterance, the framework aligns
  the characters of its normalized words, joined by single spaces, against the
  characters of the hypothesis words that belong to it. The CER of a recording
  is the sum over its utterances. A character is a grapheme cluster, thus "ñ"
  is one character in NFC and in NFD.
- **By utterance language** gives WER and CER for each language class:
  `tagalog`, `english`, `code-switched`, `other` and `unannotated`. The class
  comes from the language spans, or from the `language` of the utterance, or
  from the manifest category.
- **By word language** needs `languageSpans`, or an utterance that has one
  language. For each language it gives (S + D) / N. An insertion has no
  reference word, thus it has no language and is counted apart. A
  **code-switch point** is a reference word whose language is different from
  the language of the word before it in the same utterance.
- **By speaker overlap** gives the strata `overlap`, `no-overlap` and
  `unknown`. An `overlap` mark in the reference has priority. Without a mark,
  an utterance overlaps if its time intersects the time of an utterance of a
  different speaker. An utterance without a mark, without times or without a
  speaker is `unknown`. The three strata add up to the recording.
- **Deletion bursts** are runs of 3 or more consecutive deleted reference
  words, with the utterance and the time where each run starts. A window that
  did not decode makes this shape.
- **Missing speech** needs reference times and hypothesis word times. The
  framework merges the reference utterances into speech regions. It widens
  each hypothesis word by 200 ms on each side. It checks each region of
  1 second or more. A region is missing if hypothesis words cover less than
  20% of it. The report gives the missing regions, their total duration and
  their share of the checked speech.

A breakdown that needs an annotation covers only the recordings that have the
annotation. The report lists those recordings and adds a warning.

### Confidence intervals

The interval of a corpus WER or CER is a **percentile bootstrap** of the
pooled rate.

- The unit of the resample is the utterance (the default) or the recording.
- The default is 2000 resamples at a 95% level, with seed 20261102.
- The resamples are stratified. With utterance units, the strata are the
  utterance language classes. With recording units, the strata are the
  manifest categories. Each resample keeps the mix of the corpus.
- The generator is SplitMix64. Index draws use rejection sampling. The
  quantiles are type 7, the default of numpy and R. The sequence of draws is
  part of the method, thus the same seed gives the same interval on each Mac
  and with each Swift version.
- **A comparison is paired.** Each resample uses the same units for the
  baseline and the candidate. The report gives the difference (candidate minus
  baseline) and its interval. It also gives the share of resamples in which
  the candidate had the lower rate. That share describes the resamples. It is
  not a p-value.
- The framework refuses a comparison of two reports that have a different
  corpus ID, a different configuration, a different set of scored recordings or
  different references.

**Read the warnings with an interval.** With fewer than 30 units the interval
is rough and too narrow. Utterances of one recording share the speaker, the
room and the microphone. When you resample them as if they were independent,
the interval does not show the variation between recordings. Below 5
recordings the report says so. With fewer than 2 units there is no interval.

### What each report records

| Field | Source |
| --- | --- |
| Corpus ID | The manifest or `--corpus-id`. |
| Configuration | The complete configuration, its `id`, its schema version and its fingerprint. |
| Scoring policy | `id`, `version` and fingerprint. |
| Model | `--model`, or the `model` that all hypothesis reports agree on. |
| Model revision | `--model-revision`, or the Hugging Face commit in the local download cache of the model. The cache keeps it in the first line of each `.metadata` file. The tool reads the file and does not connect to the network. |
| Hardware | The Mac model, the core count, the macOS version and the installed memory. |
| Inference settings | The mode, the language, the prompt, the speaker mode, room mode and the live hop, context and pre-roll. |
| Build | `--build`, for example a commit. |

A field that the inputs do not give is "unavailable", with a reason. The
framework does not guess it. A plain-text hypothesis has no model, no settings
and no measurements.

The **performance** part keeps four figures apart.
[Which number is which](#which-number-is-which) defines them.

| Figure | When the report has it |
| --- | --- |
| Whole-file RTF | Offline runs only. The corpus figure is the total decode time divided by the total audio, and only when each scored recording has both. |
| Live commit latency | Live replays only. With `--realtime` it uses the wall clock. Otherwise it uses the audio fed so far. |
| Process peak footprint | The highest `phys_footprint` of the decoding process. It does not include the model. |
| Model residency | The Neural Engine memory that the model load added. |

### The outputs

`report.json` is the machine-readable report, with sorted keys. Each value that
can be absent has the form `{"status": "available", "value": ...}` or
`{"status": "unavailable", "reason": "..."}`. `report.md` gives the same
results as tables. With `--compare`, the tool writes `baseline`, `candidate` and
`comparison`, each as `.json` and `.md`.

`--score` exits with 0 when it scored at least one recording of each system.
It exits with 3 when a system has no scored recording, with 2 for an input
error and with 1 for an output error or a refused comparison.

### Limitations of the framework

1. **No result yet.** The framework was tested on synthetic fixtures only.
   No real Taglish, Tagalog or English corpus was scored with it.
2. **The language of a word comes from the annotation.** Without
   `languageSpans` or a one-language utterance there is no word-language
   breakdown. `eval/langscore.py` guesses the language from a word list; the
   framework does not.
3. **The utterance of a word is one choice among equal alignments.** When two
   alignments have the same cost, the fixed rule chooses one. A repeated word
   at an utterance boundary can then count against the neighbouring
   utterance. The totals of the recording do not change.
4. **A very long recording has no utterance results and no CER.** Above
   120 million alignment cells (about 11,000 by 11,000 words), the framework
   counts the WER in linear memory. It then reports utterance results, CER,
   breakdowns and deletion bursts as unavailable.
5. **Missing speech depends on the word times of the model.** Whisper word
   times are approximate. The 200 ms padding and the 20% threshold are
   settings. The framework did not calibrate them on real audio.
6. **Corrections references lean toward the model.** The cautions of
   [Corrections exported from the app](#corrections-exported-from-the-app)
   apply without change.

## Tier comparison, 2026-11-02

`eval/tier_benchmark.py` compares the Fast, Balanced and Best tiers on one corpus, under one
plan. The plan is written before the first decode, and it contains the decision gate.
[eval/TIER-RESULTS.md](../eval/TIER-RESULTS.md) gives the conditions, the data, the results and the
error analysis.

**Decision: keep Balanced.** No tier met the gate on either corpus.

| Corpus | Fast | Balanced | Best |
| --- | ---: | ---: | ---: |
| FLEURS `fil_ph`, read Tagalog, 349 sentences, WER | 12.16% | 11.66% | 11.35% |
| Liva AI `en-tl`, conversational Taglish, 40 min, WER (two decodes) | 70.5% / 69.0% | 68.3% / 69.6% | 64.8% / 65.6% |
| Median whole-file RTF (FLEURS / Liva) | 0.086 / 0.258 | 0.067 / 0.153 | 0.247 / 0.606 |
| Neural Engine residency of the model | 878 MB | 1,580 MB | 3,000 MB |

The gate requires all of these:

- at least 10% relative WER improvement over Balanced;
- a 95% interval of the difference below zero;
- a tier that can run live;
- a median whole-file RTF of 0.6 or less;
- a model residency of 3,500 MB or less;
- no more failed decodes than Balanced;
- a difference that holds in a second decode when the decodes are not repeatable.

Read the conditions before you use these numbers:

- **One Mac.** Every number is from the Mac mini M2 Pro, 16 GB.
- **Read speech.** FLEURS is read speech.
- **Not a meeting.** The Liva sample is a gaming voice chat of one group of friends. It is not a meeting, and no transcript of it was identical between two decodes.
- **Meetings are unmeasured.** Real meeting accuracy is unmeasured. No public Filipino meeting speech was found. The small public Taglish sets with a permissive licence (Liva `en-tl`, 40 minutes; CEnTaCS, 5.4 hours of monologue) are not meetings. [TAGLISH-CORPORA.md](TAGLISH-CORPORA.md) gives the research and corrects an earlier statement about licences.

## Error taxonomy of the tier decodes, 2026-11-02

`eval/taxonomy.py` sorts each word error into one kind. It is an optional report. It reads the
transcripts that the tier comparison already saved, decodes nothing, and changes no number above.
[eval/TAXONOMY.md](../eval/TAXONOMY.md) gives the categories, the label rules and the file formats.

**Read this first.**

- **No language label is verified.** No reference in these two corpora has word-level language tags.
  Every language label below is a heuristic from small word lists that an AI model (Claude) wrote.
  No native speaker has reviewed the lists. The `verified` count is zero.
- **The counts show how the decodes fail. They do not measure the speech.**
- **Do not read a difference of less than about 70 words in one category.** The categories partition
  the errors, and the total never changes. But when two alignments have the same cost, the choice
  between them moves words from one category to another. On the Liva first decode, two other
  tie-breaks (`--tie-break`, folders `liva-tiebreak-*` in the baselines) move
  `morphology_error` of Best from 44 to 28 words, `other_insertion` of Best from 52 to 106 words,
  and `boundary_error` of Best from 168 to 140 words. The largest move of any category is 67 words (Balanced `other_substitution`). The `tl_to_en_substitution` gap between
  Balanced and Best moves little: 98 words with the default tie-break, 91 and 89 with the others.
- The totals match the published WER: Liva 3,784 / 3,592 / 3,903 errors for Balanced, Best and
  Fast over 5,537 words; FLEURS 1,121 / 1,091 / 1,169 over 9,613 words. The FLEURS S/D/I of
  Balanced (869 / 123 / 129) equals the `transcribe --score` figures.
- Liva Best differs from the published WER by 0.07 points in the first decode (64.87%) and by 0.08
  in the second (65.69%). The cause is the two backticks that
  [TIER-RESULTS.md](../eval/TIER-RESULTS.md) names.

### Liva AI `en-tl`, error words by category (first decode)

| Category | Fast | Balanced | Best |
| --- | ---: | ---: | ---: |
| `deleted_speech` (runs of 3 or more) | 1,654 | 1,467 | 1,359 |
| `other_substitution` | 1,251 | 1,258 | 1,257 |
| `other_deletion` (isolated) | 272 | 305 | 308 |
| `enclitic_particle` | 201 | 211 | 171 |
| `boundary_error` | 164 | 156 | 168 |
| `tl_to_en_substitution` (heuristic) | 165 | 159 | 61 |
| `proper_noun_error` | 39 | 42 | 35 |
| `morphology_error` | 33 | 37 | 44 |
| `hallucination` | 17 | 40 | 54 |
| `en_to_tl_substitution` (heuristic) | 29 | 16 | 22 |
| `other_insertion` | 30 | 45 | 52 |
| `spelling_variant` | 30 | 30 | 40 |
| `mixed_word_error` | 18 | 18 | 21 |
| **Errors** (reference words 5,537) | **3,903** | **3,784** | **3,592** |

Every row is heuristic or structural. None is verified.

- **Most errors are speech that produced no words.** Runs of three or more deleted words are 38.8% of
  the Balanced errors (230 runs, 1,467 words), and isolated deletions add 8.1%. Insertions are 2.5%
  (93 words; 3.2% and 3.4% with the other two tie-breaks). This agrees with the overlap finding in TIER-RESULTS: the model writes one speaker when
  two talk.
- **Best has fewer errors than Balanced by 192 words (first decode) and 216 (second decode).** Two
  categories hold most of the difference. `tl_to_en_substitution` is 98 words lower in the first
  decode and 95 lower in the second (91 and 89 lower with the other two tie-breaks). Words in deleted
  runs are 108 lower and 50 lower (127 and 127 lower with the other tie-breaks in the first decode).
  The smaller differences are inside the spread and should not be read: `hallucination` words are
  higher for Best (14 and 43 more) and particle errors are lower (40 and 44 fewer). Best has one run of 18 words in the
  first decode and one of 102 words in the second decode that lie outside every reference
  utterance. They are the only two of the 25 inserted runs in the six Liva decodes that the report
  places outside reference speech. The 102-word run matches the longest loop in TIER-RESULTS.
- **The Tagalog-to-English substitutions are short words.** 123 of the 159 Balanced reference words
  have four letters or fewer. They are mostly function words that became short English words
  ("I", "hello", "okay" and similar). The category counts the language of the output word, so it
  cannot tell a mishearing from a translation. No translation was found by hand in TIER-RESULTS.
- **No evidence that code-switch points are worse than other words.** 58.0% of the 495 words at 274
  heuristic switch points are wrong (287 words). The fair comparison is with the other words that
  have a `tl` or `en` label, because a switch point needs two such words: 63.3% of those 3,109 words
  are wrong. The gap is 5.3 points for Balanced, 1.9 for Best (56.4% against 58.3%) and 4.0 for
  Fast. The 274 points are in four recordings of one friend group, and the labels are heuristic. The comparison
  with all other words (67.5%) is biased, because it includes the `unknown`, `ambiguous`, `other`
  and `name` words, which are wrong more often.
- **Word timestamps.** 17.1% of 3,683 aligned word pairs (Balanced) and 12.9% of 3,788 (Best) have a time
  more than one second outside the reference utterance. The reference times belong to whole
  utterances, and the overlapped speech reorders the reference. Read this as an upper bound.
- **Label coverage.** 26.9% of the Balanced reference tokens are `unknown` or `ambiguous`, and 65.1%
  are `tl` or `en`. The word lists do not cover the rest. 50 reference tokens are `mix`
  (Tagalog affix with English stem), so the 18 `mixed_word_error` words are too few to compare.
- **Names are probably over-counted.** 94 of the 95 `name` reference tokens come from the capital-letter
  rule, and many capitalised words in these vendor transcripts are not names (ordinary English words
  that the lists do not contain). Read `proper_noun_error` (42 words) as an upper bound.
- **Second decode.** The same table for the second decode is in
  `eval/baselines/taxonomy-2026-11-02/liva-repeat1/`. The `tl_to_en` gap between Balanced (162) and
  Best (67) repeats. The Fast value does not repeat (165, then 92). The two decodes of one tier
  differ by up to about 70 words in some categories, so a gap of less than about 70 words in one
  category is inside the spread between two decodes of one tier.

### FLEURS `fil_ph`, error words by category (first decode)

| Category | Fast | Balanced | Best |
| --- | ---: | ---: | ---: |
| `other_substitution` | 575 | 561 | 547 |
| `spelling_variant` | 145 | 144 | 139 |
| `proper_noun_error` | 124 | 116 | 111 |
| `morphology_error` | 109 | 97 | 98 |
| `other_insertion` | 84 | 84 | 89 |
| `hallucination` | 33 | 15 | 3 |
| `deleted_speech` | 27 | 30 | 30 |
| `enclitic_particle` | 27 | 29 | 29 |
| `other_deletion` | 42 | 42 | 43 |
| `boundary_error` | 2 | 2 | 1 |
| `tl_to_en_substitution`, `en_to_tl_substitution` | 1 | 1 | 1 |
| **Errors** (reference words 9,613) | **1,169** | **1,121** | **1,091** |

- **This is read Tagalog, and most errors are spelling.** 403 of the 561 Balanced
  `other_substitution` words are near misses (character similarity of 0.6 or more). 138 of the 144
  `spelling_variant` words are words that the model joined or split ("kahalin tulad"). The standard
  WER counts each of these as an error.
- **Names are 10.3% of the errors,** and 98 of the 116 are a near spelling of the right name. The
  name labels come from capital letters in a cased reference, so a capitalised word that is not on
  the word lists is also called a name.
- **Morphology is 8.7%.** The largest subtype is a dropped linker (`ligature_dropped`, 32 words:
  "magandang" written "maganda"). Reduplication is wrong in 24 words (13 dropped, 11 added). For 64
  of the 97 words the shared root is not on the word list (`root_unlisted`), so this category rests
  on the affix rules more than on the lists.
- **Language swaps are almost absent** (1 word per tier), as expected for read Tagalog. The older
  `langscore` heuristic called 608 tokens in these references English (REAL-TAGLISH-PROTOCOL, with its
  own tokenizer). This tool labels 38 of the 9,613 reference tokens `en` and 2,574 `unknown`, because it
  does not guess that an unlisted word is Filipino or English. The two numbers do not count the
  same tokens.
- 29.5% of the Balanced reference tokens are `unknown` or `ambiguous`. There are no reference times,
  so no hallucination is placed in silence and no timestamp is checked.

Reproduce, from the saved decodes:

```bash
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir /tmp/tax/liva
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/run1/plan.json --out-dir /tmp/tax/fleurs
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir /tmp/tax/liva-r1 --repeat 1
python3 -I eval/taxonomy.py plan --plan /tmp/notero-data/tiers/liva-run1/plan.json --out-dir /tmp/tax/liva-t1 --tie-break del-ins-sub
```

The reports contain counts and no corpus text. They are in `eval/baselines/taxonomy-2026-11-02/`.
An independent review recomputed every total and the byte-identity of the reports.

## 2026-11-01 baseline: f022c6e on the Mac mini M2 Pro

The first set of numbers from the hardware that the app targets, and the first
with enough runs per build to show the spread. **It is a baseline for comparing
builds on this clip. It is not a statement about real Taglish**: the only fixture
on this machine is the synthetic clip, and there is no real Taglish reference.
Raw JSON of every run: `/tmp/notero-team/baseline/` (not in git). The collated
figures: `/tmp/notero-team/baseline/baseline-summary.json`.

### Conditions

| | |
| --- | --- |
| Date | 2026-11-01, 00:11 to 01:39 local time (UTC+8). Run while other work shared the Mac: the 1-minute load average at launch was 1.6 to 6.4 in the live sessions (it was not yet recorded in the offline session). |
| Machine | Mac mini, Mac14,12, Apple M2 Pro, 10 cores, 16 GB |
| OS and toolchain | macOS 26.6.2 (25G83), Swift 6.3.3 (swiftlang-6.3.3.1.3), release build |
| Model | `openai_whisper-large-v3-v20240930_turbo` (Balanced), language forced to `tl`, no diarization |
| Dependencies | WhisperKit 1.1.0 (exact pin), FluidAudio 0.15.6 |
| Audio | `synthetic-taglish.wav`, 57 s, SHA-256 `e858bd6a…dd05f25` |
| Reference | `synthetic-taglish.txt`, 123 words by whitespace, **128 by `score.py`** (it splits hyphens), which is what every WER below is divided by |
| Scorer | `eval/score.py`. The CLI's own WER matched it in every run (`cli_wer`). |
| Harness | `eval/bench_runs.py` at commit `1a8ab42` (the offline session ran at `d01f895`, which differs by the load-average field), every launch through `/tmp/notero-team/bench-lock.sh` |

**Two binaries, and why.** The pure build is `transcribe` built from
`git archive f022c6e` in a scratch directory (`/tmp/benchmarks-baseline`,
SHA-256 `88c45191…`). It cannot report commit latency, the model load time or the
memory stages. The second binary adds those, and only those: `f022c6e` plus the
two commits `984e1a5` and `96f5a16` under `app/Sources/TranscriberCLI` and
`BenchmarkRunner.swift` (`/tmp/benchmarks-instrumented`, SHA-256 `b14f7b9c…`).
The decode path is the same code. The two were run **interleaved** (order A B,
B A, A B, …), so that both see the same machine. Every number labelled "pure"
comes from the pure build. The live commit latency, the model load time and
every Neural Engine figure can only come from the instrumented one.

### Commands

```bash
# build (scratch copies, not the repository's .build)
git archive f022c6e | tar -x -C /tmp/benchmarks-baseline
(cd /tmp/benchmarks-baseline/app && swift build -c release --product transcribe)
git archive 96f5a16 app | tar -x -C /tmp/benchmarks-instrumented
(cd /tmp/benchmarks-instrumented/app && swift build -c release --product transcribe)

PURE=/tmp/benchmarks-baseline/app/.build/release/transcribe
INSTR=/tmp/benchmarks-instrumented/app/.build/release/transcribe
AUDIO=/Users/server/Documents/GitHub/Notero/eval/audio/synthetic-taglish.wav
REF=eval/synthetic-taglish.txt

python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode offline \
    --runs 12 --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/offline
python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode live \
    --runs 8  --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/live
python3 eval/bench_runs.py run --bin $INSTR --mode live --realtime \
    --runs 8  --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/live-realtime
python3 eval/residency.py --bin $INSTR --audio $AUDIO --out /tmp/notero-team/baseline/residency-offline.json

# Afterwards: a repeat of the live comparison, and the A/A calibration run
python3 eval/bench_runs.py run --interleave $PURE $INSTR --order abba --mode live \
    --runs 8 --audio $AUDIO --ref $REF --out-dir /tmp/notero-team/baseline/recheck/live
cp -R $(dirname $PURE)/FluidAudio_FluidAudio.bundle /tmp/benchmarks-baseline-copy/
cp $PURE /tmp/benchmarks-baseline-copy/transcribe        # byte-identical copy
python3 eval/bench_runs.py run --interleave $PURE /tmp/benchmarks-baseline-copy/transcribe \
    --order abba --mode live --runs 8 --audio $AUDIO --ref $REF \
    --out-dir /tmp/notero-team/baseline/aa/live
```

`/tmp/notero-team/baseline/run-baseline.sh` holds the first four commands, and
`make-baseline-summary.py` in the same directory writes `baseline-summary.json`.

### Offline, 12 runs of each build

Median, then (minimum–maximum; interquartile range):

| | Pure `f022c6e` | `f022c6e` + CLI instrumentation |
| --- | --- | --- |
| WER | **34.0%** (21.1–57.8%; IQR 5.7) | 28.1% (27.3–57.8%; IQR 6.8) |
| Words, reference 128 | 120 (78–123) | 118 (73–121) |
| **Whole-file RTF** | **0.097** (0.086–0.188; IQR 0.023) | 0.134 (0.091–0.288; IQR 0.065) |
| `decodeMs` | 5514 ms (4867–10669) | 7587 ms (5130–16286) |
| **Collapsed runs** (rule above) | **1 of 12** (run 3: 78 words) | 2 of 12 (runs 9 and 11: 73 and 84 words) |
| Runs with invented-filler phrases | 1 (run 8: 57.0% WER, "welcome to meeting") | 0 |
| Runs where a window needed the retry ladder | 2 of 12 | 7 of 12 |
| Model load | not reported | 8.6 s (8.4–10.9) |

The pure build's WER per run, in order: 31.2, 36.7, 57.8, 32.0, 36.7, 33.6, 34.4,
57.0, 24.2, 35.2, 21.1, 30.5 (%).

**Read this table with the spread in mind, not the medians.**

- The runs are two populations. Most land at 27 to 37%; a run in which a window is
  lost or replaced lands at 57 to 58%. The 8-run range that FINDINGS 15 recorded
  for this build (25.0–57.0%, median 28.1%) lies inside this one (21.1–57.8%,
  median 34.0%), and the medians differ by 6 points because a handful of runs
  decide a median at n = 8 to 12. **Quote the range, and the collapsed count.**
- The collapse rule flagged run 3 (78 words) and not run 8: run 8 has 116 words
  and 57.0% WER, which is the invented-filler failure of FINDINGS 15, but the
  pure arm's best half is at 30.9%, so its threshold is 61.7% and 57.0% stays
  under it. The rule misses a collapse when an arm's ordinary WER is high. That
  is why the filler-phrase count is reported beside it. **That rule has been replaced**
  (see [Collapsed runs](#compare-two-builds): 15 points above a pooled level, or a filler
  phrase): it counts run 8, so this arm has 2 collapsed runs of 12, not 1. The figures in
  this section are as the P6 harness printed them; the committed
  `eval/baselines/p6-f022c6e-synthetic-taglish.json` holds both counts.
- **Whether a window needed the retry ladder separates the runs completely.** A
  window came back empty on its first attempt, and went through the ladder, in 9
  of the 24 runs (2 of 12 pure, 7 of 12 instrumented; the difference between the
  builds is not significant, Fisher p = 0.09). **All 9 of those runs scored 21.1
  to 28.9%. All 15 runs with no retry scored 30.5 to 57.8%, and all four collapses
  are among them.** The perfect separation of 9 against 15 would arise by chance
  about 2 times in 1.3 million. That fits the mechanism proposed in FINDINGS 15:
  the window of about 25 s at the start of the clip came back empty on every
  attempt before the ladder existed (finding 9), so a run is clean when
  WhisperKit's greedy decode and its sampled fallbacks all come back empty and the
  ladder retries with a wider window, and a run goes wrong when a sampled fallback
  produces text that is not empty and not right. **This is an association in 24 runs, not a proof of the
  mechanism.** Logging WhisperKit's per-window fallback count beside each window
  would test it.
- RTF carries the load of the machine: the slowest runs (0.288 and 0.173 for the
  instrumented build, 0.188 for the pure one) are about 2 times the median of
  their arm.

**Compared with each other, the two builds cannot be told apart on WER**
(median difference −5.9 points, permutation p = 0.091, bootstrap 95% interval
−9.4 to +2.0) **or on collapsed runs** (1 against 2 of 12, Fisher p = 1.0). The
instrumented build's RTF was higher (+0.037, p = 0.085); [the section below](#is-the-instrumented-build-slower)
looks at that.

### Live, every decode awaited, 8 runs of each build

Hop 1500 ms, pre-roll 1500 ms, context 15 s. Nothing is dropped by construction.

| | Pure `f022c6e` | `f022c6e` + CLI instrumentation |
| --- | --- | --- |
| WER | 27.3% (24.2–34.4%; IQR 2.9) | 25.8% (22.7–27.3%; IQR 2.0) |
| Words, reference 128 | 122 (120–123) | 119 (118–123) |
| **Replay RTF** | 0.859 (0.712–0.925) | 1.003 (0.882–1.227) |
| Collapsed runs | 0 of 8 | 0 of 8 |
| Dropped hops | 0 | 0 |
| **Forced commits** | 4 (0–9; IQR 5.5) | 7.5 (1–11; IQR 2.3) |
| **Unagreed tail words** | 11 (3–37; IQR 21) | 37 (12–37; IQR 18) |
| **Per-decode RTF** (`meanRtf`) | 0.126 (0.108–0.142) | 0.118 (0.111–0.191) |
| **Model time per hop** (`inferMs`, mean over a run) | 1276 ms (1057–1374) | 1491 ms (1312–1825) |
| Per-decode p95 / max (median over runs of each run's p95 and max) | not reported | 2898 / 3819 ms |
| **Commit latency**, audio clock (median over runs of each run's median word) | not reported | 11.5 s (7.4–12.0) |

**The two columns differ in speed, and that gap is not real.** Replay RTF was
0.859 against 1.003 and the hop 1276 against 1491 ms, but a repeat of this
comparison gave 0.901 against 0.910, and the wrapper cannot change the model's
time. See [Is the instrumented build slower?](#is-the-instrumented-build-slower).

The live WER of 25.8 to 27.3% matches the offline number of the earlier tables,
and it is not significantly different between the builds (permutation p = 0.40).
The forced commits and the unagreed tail words vary a great deal from run to run
(0 to 11, and 3 to 37), which is the same randomness as offline: runs with no
forced commit are also the runs with the fastest hops.

### Live under real-time pacing, 8 runs, instrumented build

The feed is paced at wall-clock speed, so a decode that takes longer than the hop
makes the decoder drop the next hop. Only the instrumented build was run this way.

| | Median (min–max) |
| --- | --- |
| WER | 26.6% (23.4–35.9%; IQR 3.3) |
| Words, reference 128 | 120 (113–123) |
| **Dropped hops** | **8 of 38 (4–11)**; 27 to 34 decodes completed |
| Forced commits | 7 (0–11) |
| Unagreed tail words | 28.5 (3–37) |
| Model time per hop | 1414 ms (1049–1587) |
| Per-decode p95 of `inferMs` (one run's p95) | 1.7 to 3.2 s (runs 3 and 1) |
| **Commit latency, audio clock** (each run's median word) | **12.1 s (5.8–14.4)** |
| Commit latency, wall clock (each run's median word) | 13.8 s in run 1, 7.5 s in run 3 |
| Replay RTF | 1.069 (1.065–1.081), by construction |

On this Mac the **per-decode time sits at the hop**: the mean decode of 1.4 s is
nearly the 1.5 s hop, and the p95 is two to three times it, so real-time pacing
drops 4 to 11 of the 38 hops (the M5 Pro dropped 4 of 38; [Live
transcription](#live-transcription)). Nothing was lost: the WER is the same as
with awaited decodes, because LocalAgreement waits for the next pass.

**The commit latency here is long, and this clip cannot tell you what the product
does.** All 24 live runs had 0 boundaries and 0 final decodes: the voice detector
found no pause of 700 ms in the 57 seconds, so no word was ever committed at an
utterance boundary. Words commit only when two consecutive passes agree on them or
when the window is about to slide and the decoder forces them. The runs split by
the number of forced commits: the three runs with none (3, 5 and 6) have a median
commit latency of 5.8 to 7.1 s, and the five with 5 to 11 forced commits have 12.1
to 14.4 s. Real speech has pauses, so **do not read 12 s as the latency of the
product.** It is the latency of the commit policy on speech that never stops. The
harness reports it so that a change to the commit policy shows up as a change in
this number. Why agreement takes so long on this clip has not been isolated.

### Memory: footprint and the model

Instrumented build, 12 offline and 8 live runs; the figures were the same in
live and offline:

| Stage (median) | Process footprint | Neural Engine memory owned by the process |
| --- | ---: | ---: |
| process start | 1 MB | 0 MB |
| after the audio is mapped, before the model loads | 8–9 MB | 0 MB |
| **after the model loads** | **76–77 MB** | **1580 MB** |
| after the voice model loads | 76–77 MB | 1580 MB |
| end of the run | 85–130 MB | 1580 MB |

| Process figure | Value |
| --- | --- |
| Lifetime peak footprint, `/usr/bin/time -l` (pure build, 12 offline runs) | **150 MB** (149–254) |
| Lifetime peak footprint (instrumented build, 12 offline runs) | 150 MB (142–245) |
| Footprint at exit, what the pure build printed as "peak memory" | 138 MB (89–248) |
| Maximum resident set size, `/usr/bin/time -l` | 274 MB (239–281) |

`footprint(1)`, sampled from outside the process every 0.25 s during an offline
run (`eval/residency.py`), agrees. At the first sample after the model reported
"Ready" it showed 114 MB of footprint and **1581 MB** under "Owned physical
footprint (unmapped) (neural) (nofootprint)", and `neural_peak: 1581 MB`; its
`phys_footprint_peak` was 150 MB, the same figure as the ledger's lifetime peak.
(A hand-run probe at about the same moment of a run showed 77 MB and 1581 MB.) The
in-process stages above read 76 to 77 MB right after the load and before the voice
model and the decode, and the footprint then rises to its peak during the decode.
**The model costs 1.58 GB and a build can show a footprint of 77 MB.** What the
pure build printed, "peak memory 100 MB" in a first run and 138 MB median over
twelve, is a single reading at exit and is neither the peak (the lifetime peak
was 150 MB, up to 254 MB) nor the model.

### Is the instrumented build slower?

**No effect was found, and one session suggested a large one that did not
repeat.** The instrumented build adds a thin wrapper around the recognizer (it
records the wall time of each call and forwards it unchanged), a few memory
readings and one counter. The model's own `inferMs` is measured inside the call
that the wrapper forwards to, so the wrapper cannot lengthen it by construction.
The measurements, each interleaved A B B A …:

| Session | Runs per build | Replay RTF, pure → instrumented | Model time per hop, pure → instrumented | Permutation p (hop) |
| --- | ---: | --- | --- | ---: |
| live, first session (above) | 8 | 0.859 → 1.003 | 1276 → 1491 ms | **0.003** |
| live, repeated later | 8 | 0.901 → 0.910 | 1340 → 1353 ms | 0.73 |
| offline (whole-file RTF) | 12 | 0.097 → 0.134 | not reported | 0.085 |

The first live session gave a 17% slower hop at p = 0.003. The repeat gave 1%.
**A gap of that size between two builds of identical decode code, at p = 0.003,
came from the shared machine and not from the build**, and it is the reason the
verdict line asks for a second session. The pure build's own median per hop was
1276 ms in the first session and 1340 ms in the second; the byte-identical pair
below gave 1387 and 1392 ms. Medians of 8 runs of the same code moved by 8% to 17%
between sessions. Treat a timing difference below about 15% as unresolved until it
repeats, and run timing comparisons when nothing else is running.

### A calibration run: two identical binaries

To see what the harness says when nothing differs, the pure build was copied byte
for byte to a second path (the SHA-256 of both is `88c45191…`) and the two were
run interleaved, live, 8 runs each, with the same command as above:

| | Pure, path 1 | Pure, path 2 (identical copy) | Difference | p |
| --- | --- | --- | ---: | ---: |
| WER | 23.8% (21.9–26.6) | 26.2% (24.2–28.1) | +2.3 points | **0.041** |
| Replay RTF | 0.933 | 0.936 | +0.004 | 0.91 |
| Model time per hop | 1387 ms | 1392 ms | +5 ms | 0.91 |
| Forced commits | 6 (5–10) | 5.5 (0–10) | −0.5 | 0.33 |
| Collapsed runs | 0 of 8 | 0 of 8 | | 1.0 |

**The verdict line called this "SIGNIFICANT"** (permutation p = 0.041, bootstrap
interval +0.4 to +3.9 points, so both criteria passed) for two copies of one
binary. One such result is not a false-positive rate: at a 5% level, one in 20
comparisons is expected to do this, and this was one comparison. It is a
demonstration of what a single significant result at n = 8 is worth, and of how
far the median of 8 runs of the same code can move: the pure build's live WER
median was 27.3% in the first session, 28.9% in the second and 23.8% here.
Hence the line "CONFIRM BEFORE ACTING" on any significant verdict with fewer
than 12 runs per arm. That one comparison was followed by a measurement of the false-positive
rate, and by a stricter rule: see [How often this harness cries wolf](#how-often-this-harness-cries-wolf).

## Headline results

**These headline numbers are from the MacBook Pro M5 Pro.** For the Mac mini M2 Pro,
with n = 12, see [the 2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro).

Whole-file transcription, the Balanced tier, the synthetic Taglish clip:

| Measurement | Result |
| --- | ---: |
| RTF | 0.09 to 0.14 |
| Speed against real time | 7 to 11 times faster |
| WER | 20.3% to 25.8% |
| Peak memory | approximately 300 MB |

These are the numbers in the [README](../README.md). The WER range is from five
runs after the retry ladder in finding 9 was in place. The runs produced 119 to
121 words against the 123 words in the reference, and no dropped window. The
offline WER that this repository recorded for the same clip before that change
is **27.3%**, which the documents treat as the ceiling for this fixture.

## Whole-file transcription

Single runs from `eval/out/run-live.log`, the Balanced tier, no speaker
identification, the command-line scorer:

| Clip | Words | Decode time | RTF | WER |
| --- | ---: | ---: | ---: | ---: |
| `synthetic-taglish` | 121 | 4 s | 0.072 | 27.3% |
| `meeting01` | 51 | 3 s | 0.143 | 60.0% |

The 60% on `meeting01` is the reference and not the model. Read
[The test material](#the-test-material).

### The retry ladder

Before the retry ladder, one window of the synthetic clip returned nothing on
every attempt:

| Window | Decoded |
| --- | --- |
| 0.000–24.876 s | **empty, every attempt** |
| 24.532–49.708 s | 54 words |
| 49.364–57.049 s | 16 words |

**Twenty-five seconds of speech, which is 44% of the clip, disappeared. The
transcript looked short and not broken, and every stage reported success.** The
WER doubled from 27% to 56%. The failure is deterministic: five consecutive
runs produced the identical empty result.

It is the window boundary and not the audio. The same leading audio decoded
correctly at each other length:

| Window length | Result |
| --- | --- |
| 24.876 s | empty |
| 25.500 s | 90 words |
| 26.000 s | 56 words |
| 27.000 s | 60 words |
| 28.000 s | 70 words |

Finding 9 in [FINDINGS.md](FINDINGS.md) gives the mechanism and the fix.

## Live transcription

`transcribe --live` replays a clip through the same `LiveDecoder` that a
recording uses. The synthetic clip separates the variants. A 1.5-second hop and
a 15-second context, scored with the command-line scorer:

| Live variant | WER | Forced commits | Tail words committed unagreed | Deduplicated by text |
| --- | ---: | ---: | ---: | ---: |
| pre-roll 0 (the old context window) | 33.6% | 9 | 33 | 0 |
| **pre-roll 1.5 s** | **27.3%** | **2** | 4 | 5 |
| pre-roll 1.5 s, real-time pacing | 26.6% | 2 | 12 | 7 |
| the offline pass, the same model | 27.3% | — | — | — |

**The live path with pre-roll lands on the offline number.** A cold start at
each commit boundary was costing six WER points. Real-time pacing dropped 4 of
38 hops, which is 11%.

### The pause filter

The paused synthetic clip (87 s, 25 pauses of 1.2 s) exercises the utterance
boundary. On 2026-09-06 the decoder started to drop, from each hypothesis, a
word that starts inside a pause that the voice detector found. Every decode
awaited, Balanced tier:

| Paused clip, live replay | WER | Words | Tail words committed unagreed | Deduplicated by text |
| --- | ---: | ---: | ---: | ---: |
| before the filter | 51.6% | 122 | 59 | 14 |
| **with the filter** | **39.1%** | 127 | 46 | 17 |

The clips with no pause of 700 ms do not change. Finding 12 in
[FINDINGS.md](FINDINGS.md) gives the mechanism.

### A style primer in the prompt

A sentence of Taglish before each window, as a hint for the spelling. Measured
on 2026-09-06 with `transcribe --style-hint`, Balanced tier:

| Clip | Path | No primer | Primer |
| --- | --- | ---: | ---: |
| synthetic | offline | 24.2% | 44.5% |
| synthetic | live | 27.3% | 96.1% |
| meeting01 | offline | 71.7% | 65.0% |
| meeting01 | live | 63.3% | 280.0% |

**The app does not send the primer.** On the live path the model repeats the
primer instead of the room. The Names and terms field of the app is a short
list, and this measurement does not cover short prompts.

### The adaptive hop

Under real-time pacing:

| Real-time replay | Dropped hops | Forced commits | WER |
| --- | ---: | ---: | ---: |
| fixed 1.5 s hop | 4 / 38 | 2 | 26.6% |
| adaptive 1.0–1.5 s | 10 / 46 | 9 | 29.7% |

More drops and more forced commits. The `inferMs` that the model reports
understates the wall-clock cost of a decode, because audio conversion, actor
hops and the main-actor ingest path all sit outside it. **The adaptive hop
stays off by default.** The flag remains for a machine that is faster than this
one.

## Forced `tl` against automatic detection

`eval/compare_language.py` over the manifest, the Balanced tier, offline,
scored with `eval/langscore.py`:

| Clip | Mode | WER | S/D/I | Filipino err | English err | Code-switch err | RTF | Detected |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| synthetic | `tl` | 25.2% | 24/5/2 | 29.8% | 10.3% | 13.0% | 0.145 | tl |
| synthetic | `auto` | 62.6% | 28/48/1 | 67.9% | 48.7% | 53.7% | 0.110 | id ×3 |
| meeting01 | `tl` | 72.9% | 13/30/0 | 75.5% | 60.0% | 64.3% | 0.120 | tl |
| meeting01 | `auto` | 66.1% | 34/1/4 | 63.3% | 40.0% | 50.0% | 0.608 | tl ×1 |
| **all** | `tl` | **40.7%** | 37/35/2 | 46.6% | 20.4% | 23.5% | 0.137 | |
| **all** | `auto` | 63.7% | 62/49/5 | 66.2% | 46.9% | 52.9% | 0.263 | |

On the synthetic clip, `auto` resolves to Indonesian for all three windows and
loses 48 words to deletion. **This fixture is the least fair test of that
failure, because the voice is Indonesian.** On the real excerpt, `auto` is
better than `tl` (66% against 73%) at five times the decode time, and the
reference there is too poor to trust either number.

Pooled, `tl` is 23 points better and costs half the decode time. **The default
stays `tl`.** Run the harness on real Taglish recordings with clean references
before you revisit this.

## Model load time

**The first load of a model compiles CoreML for the Neural Engine, and that
took 284 seconds.** Later loads hit the cache at 9 to 11 seconds. Know this
before you assume that a restart is cheap.

## Memory

Two different questions, two different figures. Read
[Which number is which](#which-number-is-which) first.

| Question | Figure | Value |
| --- | --- | ---: |
| What does the loaded model occupy? | Neural Engine memory owned by the process, large-v3-turbo (Balanced) | approximately 1.6 GB (1580 MB measured on the Mac mini M2 Pro on 2026-11-01, constant across 12 runs) |
| What do the two speaker models occupy? | Neural Engine memory | 0 MB on the Neural Engine, 13 MB on disk and about 23 MB of footprint when loaded (measured on 2026-11-01; the earlier 200 MB was never measured) |
| What does the process cost to run? | Lifetime peak **footprint** of a whole-file run on the test clip | 150 MB median, 142 to 254 MB over 24 runs (Mac mini M2 Pro, 2026-11-01) |

The figure that earlier versions of this file gave for the process, "approximately
300 MB, as `transcribe` reports it", was `phys_footprint` read once at exit. It
was not a peak, and it does not contain the model: on the Mac mini M2 Pro the
footprint after the model loaded was 76 MB, and the 1580 MB of the model sat
beside it in the Neural Engine figure. See
[the 2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro).

**Two hours of audio in a `[Float]` array holds 460 MB.** The app therefore
maps the 16 kHz working copy and reads it in slices. On a Mac that already
holds the model, that difference makes the Mac swap memory to disk.

A background decode that competes for the Neural Engine turns a live hop from
0.9 seconds into 3 seconds. The job queue therefore refuses to start work while
a recording runs.

## Historical results

These numbers came from the retired Python server, not from the native app.
They are here because the design decisions that they produced are still in the
app. Do not compare them to the tables above.

| Path | Window | Median inference | RTF |
| --- | --- | ---: | ---: |
| Sliding (Phase 2 geometry) | 15 s | 891 ms | 0.059 |
| Fixed chunks (Phase 1, end to end) | 5 s | 516 ms | 0.103 |

The 15-second window costs approximately 0.9 seconds to decode. **A 1.0-second
hop therefore drops two thirds of its hops**, and consecutive passes stop being
consecutive, which is exactly what LocalAgreement needs. A 1.5-second hop
landed live accuracy within approximately 1.6 points of the offline ceiling. A
1.0-second hop was 14 points off. A 2.0-second hop was worse again, because the
buffer outruns agreement and starts to force commits instead of earning them.
The hop default of 1500 ms comes from this measurement.

The Python server dropped 15% of its hops at the same hop under real-time
pacing. The native app dropped 11%.

Findings 3, 4, 6 and 7 in [FINDINGS.md](FINDINGS.md) hold the rest, including
the concurrency measurement: partial latency holds to 4 streams, but the number
of commits for each stream falls by approximately one third.

## Compare two builds

**One run proves nothing.** The offline pass is not deterministic: eight
identical runs of the synthetic clip gave WER from 25% to 57%
([FINDINGS.md](FINDINGS.md) entry 15). `eval/bench_runs.py` is the harness that
every claim of "faster" or "more accurate" is judged by. It uses only the Python
standard library and the existing `transcribe` binary, and it scores with
`eval/score.py` and `eval/langscore.py`.

```bash
# Baseline and candidate, alternating, 12 runs each (24 launches)
python3 eval/bench_runs.py run --interleave BASE/transcribe CAND/transcribe \
    --labels base cand --audio eval/audio/synthetic-taglish.wav \
    --ref eval/synthetic-taglish.txt --mode offline --runs 12 --out-dir /tmp/ab-offline

# The same for the live path. Add --realtime to measure drops under real-time pacing.
python3 eval/bench_runs.py run --interleave BASE/transcribe CAND/transcribe \
    --audio ... --ref ... --mode live --runs 8 --out-dir /tmp/ab-live

# Re-print a comparison from the saved summaries
python3 eval/bench_runs.py compare /tmp/ab-offline/A/summary.json /tmp/ab-offline/B/summary.json
```

`--order abba` alternates which build goes first (A B, B A, A B, …) and cancels
a steady drift in temperature or background load that strict `abab` would charge
to the second build. `run` also takes a single `--bin`, for a baseline with no
partner. Every measured launch goes through `/tmp/notero-team/bench-lock.sh`
when that file exists, one launch at a time, and `--no-lock` turns that off.
`--extra …` passes the rest of the line to `transcribe`.

**What the harness writes.** For each run: `run-NN.json` (the command, the
binary's SHA-256, the scores, the live counters, the memory stages, the full
`transcribe` report), `run-NN.report.json` and `run-NN.stderr.txt`. For each arm:
`summary.json` with the median, minimum, maximum and interquartile range of the
WER, the word count, the RTF and `decodeMs`; for live runs the dropped hops, the
forced commits, the unagreed tail words, the per-decode RTF and the commit
latency; the machine's load average at each launch; the environment.
A failed run is reported as a failure and is not silently dropped.

**Collapsed runs, reported apart from the median.** A single collapsed window is
the dominant noise source on the synthetic clip, so every summary and comparison
counts the runs that collapsed, under ONE rule (`benchstats.COLLAPSE_RULE`), which
is printed each time:

> A run is **collapsed** if its WER is more than **15 points** above the
> **reference level**, or if it produced fewer than **75%** of the reference's
> words, or if it contains an **invented-filler phrase** the reference lacks. The
> reference level is the median of the best half (the ceil(n/2) lowest) of the runs
> judged, **pooled over both arms** of a comparison.

Three things changed from the first cycle's rule ("more than 2x the arm's own
best-half median, or fewer than 75% of the words"), and each has a reason in the
data:

* **An additive margin, not a ratio.** At a typical 30% WER the old threshold was
  60%. The 57.0% run of the P6 offline baseline, the one in which Whisper invented
  a filler phrase over a window (finding 15), sat just under it and was never
  counted: the baseline reported 1 collapsed run of 12 where there were 2. Over the
  80 successful runs of the P6 baseline sessions, the largest excess over its level
  of a run that nobody calls collapsed is **+10.9 points**, and the smallest excess
  of a collapsed run is **+26.2 points** (that filler run); the other collapsed runs
  are +26.2 to +30.5. 15 points is in the middle of that empty gap, 4.1 points clear
  of the noisy side. One lost 30 s window of the 128-word clip costs about 25 points.
  `tests/test_baselines.py` recomputes both figures from the committed runs.
* **A pooled level.** Judged against itself, an arm that is bad in every run has no
  collapsed run. Pooling the two arms of a comparison gives one level for both, so a
  uniformly bad candidate is judged by the baseline's good runs (the pooled lowest half
  is the good arm), and a permutation of the arm labels leaves the level unchanged.
  On the lead's pre-P6 A/B (`eval/baselines/p6-lead-ab-main-vs-p6-branch.json`: main
  gave 35.2, 60.9, 63.3, 59.4, 29.7, 57.0% and the P6 branch 24.2% six times) the old
  rule counted 1 of main's 6 runs; this rule counts 4.
* **A filler phrase counts.** A run containing "thank you for watching" or another
  phrase of `FILLER_MARKERS` that the reference lacks is collapsed whatever else it got
  right. Before, it was only an annotation.

The 75% word floor is unchanged (collapsed runs: 57-66% of the reference's words;
every other run: 88% or more).

**What `compare` computes.** One decision rule (`benchstats.decide`), shared by
`bench_runs.py compare` and by `regress.py`:

1. At least 8 successful runs per arm, interleaved in one session; otherwise no verdict.
2. For every metric, a two-sided permutation test on the **rank sum** (exact: up to
   10 against 10 runs, otherwise 100,000 seeded shuffles), and for the collapsed
   runs Fisher's exact test. The difference of medians is the **effect size**, not the
   test statistic: at 8 against 8 the difference of medians ties on so many
   arrangements that its smallest possible p is 0.0031 even for two completely
   separated samples, which makes any correction over 17 or more tests impossible;
   the rank sum reaches 0.00016.
3. **Holm's correction over every tested metric together**, alpha = 0.05. A comparison
   reports a dozen metrics, so "p < 0.05 on any of them" is wrong: read that way, the
   table of an A/A comparison of two identical builds shows a "significant" metric in
   11-24% of sessions (measured below), where the corrected rule gives 2-3%.
4. An **effect-size floor** per metric (`benchstats.METRICS`): WER 2 points, RTF and
   per-hop timing 5%, commit latency 10%, a counter one hop or two words, two collapsed
   runs, words 4 or 3%. A significant difference smaller than that is reported as
   "significant, below floor" and not flagged.
5. **Timing is believed only on a quiet, balanced machine.** A timing metric may be
   flagged only if every run has a load-average record, the median load at launch is
   at most 2.0 in both arms, and the two arms' medians are within 1.0. Otherwise it is
   printed as "indicative only (load)" with the reason, whatever its p-value. The P6
   live session at median load 3.8-4.4 showed the instrumented binary 17% slower (replay RTF 1.003
   against 0.859); the recheck at median 0.5-0.7 showed 1% (0.910 against 0.901).
   `tests/test_baselines.py` pins both. The
   threshold is a policy chosen on that one case, not a fitted constant; it only moves
   wording from "regression" to "indicative", and never touches a WER, count or DER verdict.
6. **One session only suspects.** The verdict says `SUSPECTED REGRESSION`, never "real".
   A second, independent interleaved session of the same pair
   (`regress.py --confirm-with REPORT.json`) tests only the metrics the first one flagged
   (Holm over just those; a flagged metric the second session could not test counts with
   p = 1) and calls a metric **CONFIRMED** when it reproduces in the same direction above
   the floor, and, for a timing metric, on a quiet machine again. It refuses outright when
   the first report compared different binaries or is the session itself. Results at fewer
   than 12 runs per arm need that second session before anyone acts on them; for anything
   that will change a default, so do results at 12.

At n = 8 the rule has little power (below), and "not significant" never means
"equivalent". The tests that carry this are in `tests/test_benchstats.py`; the
reference values are worked out by hand (the rank-sum case of four values, Holm's
adjustment of three p-values) or reproduced by a plain enumeration (the optimized exact
permutation).

**RTF moves with background load.** The lock serializes measured runs only.
Builds and tests by other processes do not take it. In the baseline below, the
machine's load average was 2 to 6 for the whole session, and single offline runs
came out up to 2 times slower than the median. The median and the IQR absorb
that, and the per-run `loadavg_1m_at_launch` in each summary lets you see it. For
a timing claim, run when the Mac is quiet and read the IQR.

## Regression comparison in one command: `eval/regress.py`

`bench_runs.py` runs one clip. A regression gate needs a defined **suite**, two builds
built the same way, one collapse rule, one decision rule and ONE report. That is
`regress.py`; it reuses `bench_runs.py` (a run, its scoring, its records), `benchstats.py`
(the statistics), `der.py` (diarization error) and the fixture driver, and adds no model code.

```bash
# Two builds of any git revision (built from `git archive` into /tmp/notero-regress, never
# inside the repository, cached by full commit sha), or WORKTREE for the working copy,
# or a path to a `transcribe` you already have:
python3 eval/regress.py --base addf5f8 --cand HEAD --suite quick
python3 eval/regress.py --base BASE/transcribe --cand WORKTREE --suite full

# A second, independent session of the same pair, to turn "suspected" into "confirmed":
python3 eval/regress.py --base addf5f8 --cand HEAD --suite quick \
    --confirm-with /tmp/notero-regress/reports/<first session>/report.json

# One build, N runs, one file: is the transcript byte-identical? (the guard for findings 15 and 16)
python3 eval/regress.py determinism --bin HEAD --runs 8
```

**Suites.** `quick`: the synthetic Taglish clip offline and live (8 runs per arm each) and
DER on two synthetic multi-speaker clips (2 rounds per arm and clip). `full` adds the paused
clip live (26 pauses of 1.2 s, so the silence boundary fires), the other five multi-speaker
clips (3 rounds), and a FLEURS Filipino subset when `/tmp/notero-data/fleurs` exists
(8 clips by sha1 of the file name, concatenated; read speech, **not** Taglish and not a
meeting; skipped with a note when absent). Everything else is synthetic. On this Mac a
`quick` session is about 25 minutes of exclusive machine time.

**The lock, once per batch.** Measured runs take `/tmp/notero-team/bench-lock.sh` (when it
exists; otherwise the report says it ran unlocked). A hold covers a whole number of ABBA blocks,
sized to about 4 minutes (`--hold-seconds`), so each arm meets the same machine in every
hold. Taking the lock once per run was tried first: behind five other agents' multi-minute
holds, single runs waited from 3 minutes to over half an hour (7 runs took 35 minutes, and the 8th
had waited 30 minutes when the stream was stopped), so a 320-run stream would have taken most of
a day. A hold of about 4 minutes still waits a full queue cycle, about 25 minutes in a busy
session; `--hold-seconds 600` halves the number of cycles for a long series, at the price of
holding the lock longer each time.

**Per series, the machine is recorded:** the load average at every launch, and `uptime`,
`vm_stat` and `memory_pressure` before and after (pageouts during the series, compressor
pages, free-memory percentage). The decision rule above uses the load record: a timing
difference is never called a regression on a loaded machine, and the report prints why.

**The report** (`report.md`, with `report.json` beside it and the raw runs under it) states the
builds (commit, label, binary sha256), the machine, the model id, the interleave scheme, the
collapse rule and the level both arms were judged by, then per series a table of median [range]
for both arms, the difference, the rank-sum p, the Holm-adjusted p and a status; the collapse
counts with the reason for each collapsed run (`wer`, `words`, `filler`); the load record; the
DER table; the determinism of each arm (distinct transcripts, and where the first one diverges);
warnings; and the verdict. A run or series that failed makes the session **INCOMPLETE**: the
verdict starts with `INCOMPLETE (...)` and the exit code is 1, so a candidate that crashes can
never read as "no significant difference". A metric that only one build reports (an older binary
lacks the commit-latency fields) is listed as not tested, not dropped silently.
`regress.py reanalyze DIR` redoes the analysis from the stored runs, which is what to do when
the rule changes.

**DER** comes from the raw diarizer spans that `transcribe` prints under
`TRANSCRIBE_DEBUG_SPANS=1`, scored by `der.py` against the clip's RTTM. It is not in the Holm
family: DER is a deterministic function of the diarizer's output, so where every run of an arm
agrees a difference is exact, and a change of 2 points or more is reported as one; where the runs
do not agree the row says so and is **descriptive only, never flagged**: two or three rounds of
a varying DER all point the same way by chance on 18-38% of fixtures whose spread is a few
points (simulated), so a varying DER needs `--rounds 8` and a look at the medians, or the
nondeterminism fixed first. This is not `diarbench` (the speaker agent's
tool, on its own branch); it measures the whole `transcribe` path.

**Determinism.** `regress.py determinism --bin X --runs N` (and, automatically, each arm of
every comparison) reports whether the N transcripts are byte-identical, the number of distinct
ones, and the first divergence: the word index, its time, and the decode window it falls in.
The window needs the `windows` list that the offline JSON report now carries (offline only;
older binaries lack it, and the report then says the window is unknown).

**Fixtures** (`eval/fixtures.json`, `eval/fixtures.py`): for each fixture the generator, the
sha256 of the generated audio (regenerating gives identical bytes on this macOS; checked by
generating twice), the reference, a `synthetic` flag, and what a number measured on it can and
cannot support. `python3 eval/fixtures.py generate --out DIR` regenerates them into a scratch
directory; `verify DIR` compares hashes; `list` prints the limits. The generators need macOS
`say`; elsewhere the harness skips those series and says so.

**Baselines** (`--baseline eval/baselines/NAME.json`): the committed P6 baseline, with its
provenance, is in [`eval/baselines/`](../eval/baselines/README.md). `--baseline` names the base
commit when `--base` is omitted, prints today's base arm next to the committed numbers, and warns
on **baseline drift** when the hardware, CPU, memory, macOS release, model id or fixture hash
differs. The committed runs were not interleaved with today's, so they are context and never a test.

**CI.** The Linux job already runs `pytest`; it now also triggers on `eval/**`. The new tests
need no model, no `/usr/bin/time -l` and no macOS command: the platform-dependent parts are
tested with `sys.platform` forced. The real `regress.py` run needs a Mac, a model and the bench lock.

## How often this harness cries wolf

An A/A comparison (one binary against itself) has no true difference, so every flag it raises is
a false positive. `eval/calibrate_aa.py` measures how often the rules do that, two ways.

**Resampling** (2,000 sessions per pool, seed fixed, `eval/baselines/aa-calibration.json`): two
arms of 8 runs are drawn from the P6 runs of ONE binary, the whole rule is applied, and the draw
is repeated. A rate is followed by its Wilson 95% interval.

| Pool of runs of ONE binary (draw) | Metrics tested | Table read naively: any p < 0.05 | P6 verdict (WER and collapsed runs only) | Holm | **Shipped rule** (Holm + floors) | Two sessions agree |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| offline-pure: 12 runs, with replacement (bootstrap) | 4 | 12.7% (11.3–14.2) | 1.7% (1.2–2.4) | 2.8% (2.2–3.6) | **2.4% (1.8–3.2)** | 0.0% (0.0–0.2) |
| offline-instrumented: 12 runs, with replacement (bootstrap) | 4 | 10.8% (9.5–12.2) | 0.8% (0.5–1.3) | 2.4% (1.8–3.2) | **1.8% (1.3–2.4)** | 0.0% (0.0–0.2) |
| live-pure: 32 runs, without replacement | 9 | 20.0% (18.3–21.8) | 1.7% (1.2–2.4) | 2.6% (2.0–3.4) | **2.6% (2.0–3.4)** | 0.0% (0.0–0.2) |
| live-instrumented: 16 runs, without replacement | 10 | 23.8% (21.9–25.7) | 1.0% (0.6–1.5) | 2.2% (1.6–2.9) | **1.7% (1.2–2.3)** | 0.0% (0.0–0.2) |

* **The requirement is met: an A/A session flags any metric at most 5% of the time, all
  reported metrics together** (2.4%, 1.8%, 2.6% and 1.7%; every upper interval end is below 5%).
  The shipped column is an upper bound: it counts timing flags without the load gate, which
  can only remove flags.
* **Read uncorrected, the same sessions show a "significant" metric 11-24% of the time.** Each
  single test is sized correctly (4-5% per metric, `naive_flags_by_metric` in the JSON); it is
  the number of metrics that does it. Holm over the whole table is what removes it.
* **The P6 verdict line was already conservative** on these draws (1-2%), because it tested only
  WER and the collapsed-run count. That makes the one observed A/A "significant" WER
  (p = 0.041, two byte-identical copies, n = 8) an event that resampling gives about 1-2%:
  either chance, or structure that iid draws do not have (drift, order). The real A/A runs below
  are the check on that.
* **Two sessions that must agree: 0 of 2,000** in every pool (upper interval end 0.2%).

**Power, which is the other half of the picture.** Percentage of sessions in which the shipped rule
flags a shift injected into arm B's runs (n = 8 per arm, floors and Holm applied, load gate not):

| Shift injected into arm B | offline-pure | offline-instrumented | live-pure | live-instrumented |
| --- | ---: | ---: | ---: | ---: |
| WER +5 points | 16% | 28% | 48% | 100% |
| WER +10 points | 29% | 63% | 99% | 100% |
| RTF +10% | 9% | 3% | 24% | 5% |
| RTF +20% | 33% | 6% | 77% | 25% |
| mean per-decode RTF +20% | — | — | 38% | 50% |

At n = 8 per arm the rule sees a 10-point WER shift on a tidy series and misses most 5-point shifts
and most timing changes under 20%. That is the price of a 2-3% false-alarm rate across every metric
at once, and it is why "no significant difference" is never "equivalent". The offline pools are the
noisy ones: each holds a collapsed run, so their spread is wide. More runs per arm buy power
(n = 12 is already exact-to-Monte-Carlo and slower); a quieter machine narrows RTF.

**What the resampling cannot show** is slow drift or load between runs: its draws are iid. A real A/A
session on the machine (`regress.py --base X --cand X`) is the check, and `calibrate_aa.py stream`
turns a long stream of real runs into blocks of 8 against 8. **No real A/A session was run this
cycle**: behind the shared bench lock (8 to 10 waiters, about 25 minutes of waiting per hold) it would
have taken hours, and the lead decided the resampling above was the right evidence for the rule. The
false-positive rate in the table is therefore a resampling result, with iid draws.

**The one real session** is kept in `eval/baselines/sessions/quick-ab-addf5f8-vs-57dcc14/` (report,
data, plan, and a README that says what did not run): `regress.py --suite quick`, pre-P6 `addf5f8`
against `57dcc14`, n = 8 per arm, through the lock. Its offline and live halves ran; **its DER half and
the real A/A did not** (lock contention, stopped by the lead). Offline WER 34.4% [30.5-58.6] to 24.2%
[24.2-24.2] (-10.2 points, Holm-adjusted p = 0.002: a suspected improvement), 3 of 8 collapsed runs to
0 (Fisher p = 0.20, not significant at n = 8), 8 distinct transcripts in 8 runs against byte-identical.
The offline RTF gap of -10% is not believed: median load 6.4 against a limit of 2. Live: nothing significant
(WER 28.1% to 26.2%, p = 0.12; replay RTF +5%, p = 0.23, at a quiet median load of 1.2), and **both builds
gave 8 distinct transcripts in 8 live runs**: the P6 branch is deterministic offline only. One session
suspects and does not confirm; this matches the lead's own n = 6 offline A/B.

## Test material that exists

| Clip | Audio on disk | Reference on disk | Notes |
| --- | --- | --- | --- |
| `synthetic-taglish` | `eval/audio/synthetic-taglish.wav`, 57 s, in the maintainer's checkout. `eval/audio/` is git-ignored, so a fresh clone has no audio. `eval/make-synthetic.sh` rebuilds it. | `eval/synthetic-taglish.txt`, tracked | 123 words by whitespace, **128 after `score.py` splits hyphens** ("i-send" is two words). Synthetic, Indonesian voice, starts at full amplitude. |
| `meeting01` | **absent** | **absent** (`eval/refs/` holds only `.gitkeep`) | `eval/manifest.json` references it, so `compare_language.py` prints "skipping clips with no audio or reference on disk: meeting01" and scores one clip. The 25 s excerpt behind the older tables is not on this Mac. |
| the paused clip (87 s) | **absent** | derived from the synthetic text | `eval/make_paused.py` rebuilds it. Not generated here. |
| multi-speaker fixtures | `eval/make_multispeaker.py` rebuilds them (`--set tuning`, `holdout`, `speakers`) | RTTM, exact boundaries | Synthetic text-to-speech voices, 2 to 6 speakers. |
| taxonomy fixture | `eval/fixtures/taxonomy/`, tracked | tagged and plain text, one JSON with times | Synthetic text written for the repository, with expected counts that were worked out from the text. No audio. Exercises every category of `eval/taxonomy.py`. |
| AMI test set, Liva AI en-tl sample | fetched into `/tmp`, not in git | RTTM (AMI manual and forced-alignment references; Liva speaker-labelled transcripts) | Public, CC BY 4.0. Used for the [diarization comparison](#diarization-comparison-2026-11-02). |

There is **no real Taglish meeting recording with a clean reference on any machine
that this project has measured on.** The public sets used since then are read
Tagalog (FLEURS), a Taglish voice chat (Liva AI) and English meetings (AMI). See
[`eval/TIER-RESULTS.md`](../eval/TIER-RESULTS.md) and [DIARIZATION.md](DIARIZATION.md).
The figures above the dated sections are comparisons on a synthetic clip, not claims
about real Taglish.

## What real data is needed

Nothing here is invented. This is the protocol for collecting data that would
let this project make a claim about real speech.

**Amount.** At least 30 minutes of audio in at least 5 recordings of 3 to 10
minutes each. The reason is arithmetic: the synthetic clip has 128 words, and one
collapsed 25-second window of about 40 words moves its WER by 31 points. In a set
of 30 minutes (roughly 4,000 words) the same window moves the pooled WER by one
point, and the set holds enough windows for a rate of collapses to mean something.

**Speakers and rooms.** At least 3 different speakers across the set, with at
least 2 in each recording used for diarization, mixed Tagalog and English as the
speakers really talk. Include the primary case of this app (several people across
a room, far-field) and a close-microphone or headset case. Do not make the
set from one speaker or one room.

**Consent.** Every person on a recording agrees, before it is made, to the
recording **and** to its use as an evaluation reference, in writing. That
includes remote participants of a call. Recordings of anyone who has not agreed
do not enter the set. The audio, the references and every output stay on the
local disk, in `eval/audio/` and `eval/refs/`, which git ignores. They do not go
to a cloud transcription service, to this repository, to an issue or a pull
request, or to a language-model tool. Delete a person's recordings on request.

**Reference format.** One UTF-8 `.txt` file per recording, one utterance per
line, **verbatim as spoken**:

- Spell each word in the language in which it was said, including the English
  words inside a Tagalog sentence. Keep fillers and particles ("ah", "eh",
  "po"), false starts and repeats: the scorer counts them.
- No speaker labels, no timestamps and no stage directions in the `.txt`. A
  label would be scored as a word. Speakers belong in the RTTM file below.
- Punctuation and case do not matter, because both scorers strip them. Write a
  hyphen inside a word as the speakers' written form has it ("i-send"); `score.py`
  splits it and `langscore.py` keeps it.
- Write numbers the way the speaker said them, and do it the same way throughout.
  The scorers do not know that "5" and "lima" are the same word.
- **Two independent transcribers, then adjudication.** Score transcriber 1
  against transcriber 2 with `eval/langscore.py` before adjudicating. That WER is
  the floor of the reference: a model that scores below it cannot be told from
  the reference's own noise. Record it beside the results.

Register each recording in a manifest next to the files, as
`eval/manifest.json` does: `{"id", "audio", "ref", "category"}`, with `category`
one of `tagalog`, `english` or `mixed`, and paths relative to the manifest.

**Diarization ground truth** is a separate annotation of the same recordings,
described in [the DER protocol](#the-der-measurement-protocol).

### Corrections exported from the app

In Advanced mode, **File › Export Corrections as References…** writes a folder
that `eval/compare_language.py --manifest` reads directly. It holds a copy of
each recording that has edits, the transcript with the edits applied as the
reference, and a `manifest.json` with `id`, `audio`, `ref` and `category`
(relative to the manifest), plus `raw`, `edits`, `title` and `durationMs` for the
reader. `ReferenceSet` in `app/Sources/TranscriberCore` writes it.

```bash
python3 eval/compare_language.py --manifest FOLDER/manifest.json \
    --bin app/.build/release/transcribe --arms tl
# One clip, repeated and interleaved, through the benchmark harness:
python3 eval/bench_runs.py run --interleave BASE CAND \
    --audio FOLDER/<audio from the manifest> --ref FOLDER/<ref from the manifest> \
    --mode offline --runs 12 --out-dir /tmp/ab-own
```

Read these references with five cautions:

1. **They lean toward the model.** A line the person did not edit counts as
   accepted, whether it was right or the person did not notice. A WER against a
   corrections reference therefore **understates** the true error, and it is the
   error rate the person *experiences*, not a ground truth.
2. **One reviewer, no adjudication.** There is no inter-annotator floor.
3. **Only recordings with edits are exported.** The set is biased toward the
   meetings where the model did worse.
4. **No speaker labels leave the export**, so it is no diarization ground truth.
5. **Consent still applies** to a folder that you made yourself from a meeting
   with other people in it.

Use corrections references to compare two builds on your own meetings, with the
same n and the same rules as above. Do not use one as the figure for how accurate
the model is.

## The DER measurement protocol

This section defines the protocol only. **The diarization work owns the code**,
in its own worktree, and this repository's benchmark files do not duplicate it:

| File | Owner | What it is |
| --- | --- | --- |
| `eval/der.py`, `tests/test_der.py` | diarization | Frame-level DER scorer; RTTM or `diarbench` JSON in |
| `eval/make_multispeaker.py` | diarization | Synthetic multi-speaker fixtures with exact boundaries |
| `eval/run_diarization_ab.py` | diarization | A/B runner over `diarbench` |
| `app/Sources/DiarizationBench/` (`diarbench`) | diarization | Speaker processing only, no ASR, no VAD |
| `eval/benchstats.py` | benchmark | The statistics below. Import it; do not copy it. |

(File names are those of the diarization worktree's commits `b343fdf` and
`346308b` at the time of writing; they are not in this branch. Since then `der.py` and
`make_multispeaker.py` have been merged here, and `eval/regress.py` uses them: its DER series
runs the whole `transcribe` path on the synthetic multi-speaker clips and scores the raw spans
with `der.py`; see [the regression command](#regression-comparison-in-one-command-evalregresspy).
`diarbench` and `run_diarization_ab.py` have been merged since then, and
`eval/diarization_eval.py` with `eval/diarization_metrics.py` implements this protocol for
whole corpora: see [the comparison of 2026-11-02](#diarization-comparison-2026-11-02).)

**The metric.** Diarization error rate is

```
DER = (missed speech + false alarm + speaker confusion) / total reference speech
```

counted per speaker per frame (two people talking at once count twice), after the
best one-to-one mapping between hypothesis and reference speakers, with a
**0.25 s collar** around every reference turn boundary removed from the score
(the NIST convention). Report the three components and the total, never the total
alone, and add the **speaker count error** (hypothesis speakers minus reference
speakers), because the failure that this app has measured is a fused or a split
speaker (finding 10). Report a collar of 0 s beside the 0.25 s figure.

**Inputs.**

- *Synthetic fixtures* from `make_multispeaker.py`: text-to-speech turns with
  exact boundaries. They support an **A/B comparison on the same file**. They say
  nothing about real meetings: no breath, no room, no crosstalk, and voices more
  consistent than people. State the fixture name, the seed, the voices and the
  macOS version with every number.
- *Real recordings*, when they exist: at least 10 minutes with at least 3
  speakers, including overlap and one-word backchannels, with an RTTM made by
  **two annotators** and reconciled. Same consent rules as above.

**Runs and statistics.**

1. **Establish determinism first.** Run each arm 3 times on each fixture and
   hash the output. If every hash is the same, a single run per fixture is the
   measurement and no statistical test applies; say that "3 identical runs" was
   the evidence. If the outputs differ, a single run proves nothing, as for the
   ASR: run **at least 8 interleaved A/B runs per arm per fixture**, and compare
   the DER with `benchstats.permutation_p_value`, `benchstats.bootstrap_ci` and
   `benchstats.verdict`, which refuses below 8 runs.
2. **Interleave** A and B, and take `/tmp/notero-team/bench-lock.sh` for each
   launch, because speaker models run on the Neural Engine too.
3. **Pool by speech time.** The pooled DER is the sum of all errors over the sum
   of all reference speech across fixtures, not the mean of per-fixture DERs, so
   a long file counts for more than a short one. Print the per-fixture table.
4. **Name every regression.** A candidate that improves the pooled DER and makes
   one fixture worse is not "better": it is better on some fixtures. The
   `two-similar` fixture (two like voices trading short turns, the finding-10
   case) is the one a fusion regression shows on.
5. **Five synthetic fixtures are five data points about the generator.** They do
   not support a claim about meetings, and a gain that appears on them alone is
   an EXPERIMENT, not an IMPLEMENT.

**Resource side.** Report the wall time of the speaker work and the memory, with
the rules of [Which number is which](#which-number-is-which): `diarbench` prints
the process's peak physical footprint, which **does not include the Neural Engine
memory of the speaker models**. Quote the footprint and the Neural Engine figure
together (`transcribe`'s `memory` stages or `eval/residency.py`), and never read a
smaller footprint as smaller models.

## Diarization comparison, 2026-11-02

The shipping speaker backend (pyannote with WeSpeaker, FluidAudio 0.15.6) against an experimental
NVIDIA Nemotron 3 backend (FluidAudio 0.18.0, `experimental/nemotron3/`) on the Mac mini M2 Pro.
[DIARIZATION.md](DIARIZATION.md) has the method, every table and the limits. In short (measured,
pass 1, collar 0.25 s, overlap scored):

| Corpus | pyannote DER | Nemotron 3 DER | Confusion, pyannote / Nemotron 3 | Merged speakers, pyannote / Nemotron 3 |
| --- | ---: | ---: | --- | --- |
| AMI test, 16 meetings, manual references | 23.70% | 24.13% | 9.45% / 0.40% | 19 / 2 |
| Liva AI en-tl, Taglish voice chat, 4 files | 58.13% | 16.07% | 32.12% / 1.73% | 16 / 2 |

- **Decision: the default does not change.** The gate needed 15% on each real corpus, and AMI
  gave none. Nemotron 3 also merged one synthetic voice pair that pyannote kept apart.
- **The AMI result depends on the reference.** Against the forced-alignment AMI references, the
  same outputs score 24.86% and 3.49%.
- Both backends gave identical output in both passes on all 37 files.
- **Memory:** the shipping speaker pass's process footprint grew to 1.68 GB on a 50-minute
  meeting, about 27 MB per minute of audio.

Evidence: [`eval/baselines/diarization-2026-11-02/`](../eval/baselines/diarization-2026-11-02/).

## Live commit latency, 2026-11-02

**Decision: the live configuration does not change, and the feature flag stays off.** No variant
reduced the median commit latency by 20% in both sessions, and none passed every gate.
`eval/live_latency.py` ran six variants, one at a time, against the production configuration. It
replayed real public audio in real time. [FINDINGS.md](FINDINGS.md) entry 38 gives the reasoning.
The plans, the numbers of every run, the analyses and the decision are in
[`eval/baselines/live-latency-2026-11-02/`](../eval/baselines/live-latency-2026-11-02/).

**What the audio is.** Six excerpts of public recordings under CC BY 4.0, 164 to 180 seconds each,
on this Mac and not in git. `eval/fixtures/live-latency-clips.json` lists them with a SHA-256 and
no audio or text.

| Corpus | Excerpts | What it is | Reference |
| --- | --- | --- | --- |
| Liva AI `en-tl` | `liva-a`, `liva-b` | Conversational Taglish: a group of friends in a voice chat, 4 to 5 speakers on one track | Vendor transcripts, 473 and 539 words, with utterance times |
| AMI test set, Mix-Headset | `ami-a`, `ami-b` | English meetings (series TS3003 and EN2002) | Speech activity for each speaker only. **No word reference, so no WER on AMI** |
| FLEURS `fil_ph`, constructed long form | `fleurs-lf1`, `fleurs-lf2` | Read Tagalog, consecutive sentences with seeded gaps of 0.3 to 1.5 s of digital silence | 253 and 256 words, with sentence times |

The rule that chose each excerpt used the reference only: the 3-minute window with the most
reference speech. No decode result was used.

**Is this "real consented evaluation audio"?** Partly, and the limits are these.

- The audio is real speech by real people. It is not synthetic.
- Each corpus is published under CC BY 4.0, which allows this use. The publishers state that the
  speakers agreed to the release (published, and this project did not check it). For Liva AI the
  licence and the vendor's statement are the only evidence on this Mac.
- Nobody agreed to **this project's** use as an evaluation reference in writing. The protocol in
  [What real data is needed](#what-real-data-is-needed) asks for that, and this set does not meet it.
  The audio and the references stayed on the local disk, and nothing was uploaded.
- It is not a meeting of the users of this app. Liva AI is a voice chat of friends. AMI is English.
  FLEURS is read speech. **No real Taglish meeting was measured.**

**The method.**

- **Arms.** The control is the production configuration (context 15 s, hop 1.5 s, pre-roll 1.5 s,
  silence boundary 700 ms, LocalAgreement-2). Each variant changes one setting:
  `HT` head-tolerant agreement (tolerance 3, run of 3); `VAD` boundary 500 ms; `PRE` pre-roll
  3 s; `HOP` hop 1.3 s; `ADA` adaptive hop; `CTX` context 12 s.
- **Blocks.** A block is one clip in one round. Every arm ran in the block, back to back, in a
  seeded random order. **The control ran twice (`C0` and `C1`).** `C1` is the A/A replicate: a
  measure of the noise in every block. A variant is compared with the mean of the two controls.
- **Run.** `transcribe --live --realtime --live-trace --no-diarize`, Balanced tier, under the
  bench lock, with the network denied. The replay follows one absolute clock.
- **Statistic.** For each block, the median commit latency of the variant run divided by the mean of
  the two control medians. The reduction is 1 minus the geometric mean of these ratios over the
  blocks. A pooled median of all words is not used. It sits in a low-density stretch between the
  short clips (3 s) and the Liva clips (17 s), so a few percent of words that cross it move it by
  seconds. **Read it anyway:** pooled that way, `ADA` would be 35.1% and 28.1% faster in the two sessions
  and `HT` 32.8% and 24.0%, which are over 20%. The pooled controls were 3.6% and 6.5% apart at session
  level, and 14% to 23% apart round by round in session 2. The plan fixed the per-block statistic before the
  first run. A reader who prefers the pooled median reaches a different latency verdict, and then the
  decision rests on the safety gates below.
- **Test.** A randomization test with exact size: in each block any of the three runs is as likely to
  be the variant if the arm has no effect. An interval is a t-interval over the blocks. A bootstrap
  over 3 or 4 rounds per clip was simulated first. It covered a true null 80% of the time, so it
  was not used.
- **Gates**, fixed in the plan before the first run: a median reduction of 20% or more, with
  p < 0.05 and the lower bound above 0, no p90 or p95 more than 5% worse, no clip more than 10%
  slower, and a 10% reduction in the time from the end of each reference segment to the commit of
  its last word; WER at most 0.5 point worse on average, with no supported regression; the deletion
  rate, the share of missing speech and the share of omitted speaker turns each at most 0.5 point
  higher, with no supported increase; no more critical hallucinations or ghost words than the mean of
  the two controls; no broken commit invariant in any run; no material increase in dropped hops; the
  same in both sessions. **The safety limits are point-estimate caps.** Read the
  limits at the end of this section.
- **Session 1** (screening): 3 clips, 3 rounds, 8 arms, 72 runs, 3.5 hours. **Session 2** (independent,
  held-out clips): `fleurs-lf2`, `liva-b`, `ami-b`, 3 rounds, `C0`, `C1`, `ADA` and `HT`, 36 runs.

**Results.** Median commit latency, wall clock, reduction against the controls (positive is faster).
The interval is the 95% t-interval over blocks. The last column is the p90 and p95 reduction.

| Variant | Session 1: median [95%] | p | Session 2: median [95%] | p | p90 / p95, session 1 | p90 / p95, session 2 |
| --- | --- | ---: | --- | ---: | --- | --- |
| `C1` against `C0` (A/A) | 0.2% [-3.1, 3.4] | 0.92 | -7.7% [-18.5, 2.2] | 0.16 | -7.5% / -3.3% | -1.4% / -1.5% |
| `HT` | 0.6% [-14.6, 13.7] | 0.58 | 14.5% [2.5, 25.0] | 0.0007 | 27.3% / 23.6% | 7.0% / 3.3% |
| `VAD` | -1.4% [-9.9, 6.4] | 0.71 | not run | | -0.1% / -2.9% | |
| `PRE` | -10.3% [-21.6, -0.1] | 1.00 | not run | | -7.5% / -7.7% | |
| `HOP` | 10.0% [2.6, 16.9] | 0.0003 | not run | | 15.6% / 15.1% | |
| `ADA` | 17.1% [6.5, 26.4] | 0.0003 | 16.7% [1.2, 29.8] | 0.003 | 18.2% / 10.8% | -2.6% / -1.5% |
| `CTX` | 8.2% [-3.2, 18.3] | 0.03 | not run | | 18.2% / 18.2% | |

Median commit latency of all words, by corpus and arm, session 1 (ms):

| Arm | AMI | FLEURS | Liva |
| --- | ---: | ---: | ---: |
| `C0` | 3,468 | 3,612 | 17,442 |
| `C1` | 3,443 | 3,634 | 17,387 |
| `HT` | 3,158 | 3,664 | 16,866 |
| `ADA` | 2,603 | 2,799 | 17,106 |
| `CTX` | 3,498 | 3,706 | 13,662 |

- **Where the latency is.** On the AMI and FLEURS excerpts the median is about 3.4 s, the floor of
  LocalAgreement-2 at a 1.5 s hop (FINDINGS 26). On the Liva excerpts it is about 17 s, which is the
  15 s window cap. In session 1, 23% to 25% of all words of the controls were committed by a forced
  commit. A variant that moves the median must move Liva, and only `CTX` did (24%).
- **`HT` is not reliably faster on the median.** Forced commits fell from 115 and 130 in the controls
  to 89 in session 1, and from 92 and 106 to 62 in session 2. The share of words committed by a
  forced commit fell from 23% to 25% to 16% in session 1, and from 16% to 19% to 10% in session 2.
  The median did not move in session 1 (0.6%). In session 2 it fell 14.5%, but the two controls
  differed from each other by 25% on `ami-b` (`C1` was slower than `C0` in all 3 rounds), and the
  gain on that clip (28%) is inside that spread. Pooled over both sessions (not in the plan): 7.8%
  [-1.3, 16.1]. **The tail gain did not repeat:** p90 fell 27% in session 1 and 7.0% [-7.0, 19.2] in
  session 2 (pooled 17.8%).
- **`ADA` gave about 17% in both sessions,** faster on all 6 clips (pooled over both sessions, not in
  the plan: 16.9% [8.8, 24.2]). It is under the 20% bar. It costs 19% to 26% more decodes (the controls
  ran 30.2 and 31.3 a minute in session 1 and 31.2 and 31.5 in session 2, `ADA` 38.7 and 37.3), and its
  infer RTF rose from 0.61 to 0.64 and from 0.62 to 0.66. CPU time did not rise (11.7 to 11.1 and 11.8 to
  11.9 s per audio minute). **Its gain is on the clips that are not Liva:** 15.8% to 27.4% on AMI and
  FLEURS, and 1.7% and 5.4% on the two Liva clips. The pooled interval, 8.8% to 24.2%, does not exclude a
  true effect of 20%. FINDINGS 11 measured it first, with other results.
- **`PRE` was worse** on latency and on missing speech (deletion rate +8.0 points, p = 0.023 before the
  Holm correction and 0.068 after it). **`VAD`** closed utterances sooner at the median (finalization
  latency 1.12 s against 1.35 s) and later in the tail (p90 2.06 s against 1.59 s and 1.65 s, p95 2.63 s
  against 1.83 s and 1.84 s), with 81 boundaries against 59 and 60. It did not move the median commit
  latency. **`HOP`** gave 10%. **`CTX`** gave 8%, with more critical hallucinations (16 against a control
  mean of 10, cause not found) and a latency anchored on the reference segments that was 6.8% worse. It
  forced **fewer** commits than the controls (97 against 115 and 130, and 17% of words against 23% and 25%):
  the 12 s cap forces sooner, not more often.
- **The Liva regime.** On the controls, WER on `liva-a` was 77.6% and on `liva-b` 69.6%, with 39% and
  43% deletions. Hops dropped on 35% to 37% of attempts, and the decode took a median 1.4 s to 1.5 s with a
  p90 of 3.6 s. Forced commits made 69% and 56% of the words of the two clips, and 0% to 4% of the words
  of the other four. The 23% to 25% quoted above is an average that Liva drives. The WER gate has
  little power on Liva. On FLEURS the controls' WER was 13.6% and 9.7%.
- **Safety, all arms.** The append-only invariant held in all 108 runs and over 33,937 committed
  words: no word was rewritten, dropped, repeated, reordered or timestamped past the audio.
  No decode failed. WER differences were inside the A/A spread (two identical controls differed by up to 4.4 WER points
  in one block of 12).
- **Conditions.** The whole Mac used a median 0.7 of 10 cores (p90 1.2 and 1.0) while the replays
  ran. That includes the replay itself, a median 0.16 and 0.18 cores, so the other jobs used about 0.5.
  The sampler took about three readings in each run. The lock
  wait was a median 1 s. Two blocks of session 1 and one of session 2 were shared with other jobs
  (more than 2 other cores at p90). Every gate was also evaluated without them. The verdicts agree.

| Gate | `HT` session 1 | `HT` session 2 | `ADA` session 1 | `ADA` session 2 |
| --- | --- | --- | --- | --- |
| Median reduction of 20% or more | fail (0.6%) | fail (14.5%) | fail (17.1%) | fail (16.7%) |
| WER | pass | pass | pass | pass |
| Missing speech and omitted turns | fail (deletion +0.9 pt, omitted +0.6 pt) | fail (deletion +0.9 pt) | fail (deletion +1.0 pt, omitted +1.7 pt) | pass |
| Hallucinations and ghost words | pass | fail (3 against 2.5) | fail (ghost words 7 against 4.5) | pass |
| Immutable commits | pass | pass | pass | pass |
| Dropped hops | pass | pass | pass | pass |
| Reproducible | no | | no | |

**Limits of the live-latency experiment.**

- **Three clips and three rounds in session 1.** The A/A spread of one block is about 10%
  (the standard deviation of the log ratio over 18 blocks is 0.098). The worst block was 35%
  (`ami-b`, round 3), and `ami-b` was 25% as a clip. Only an effect of 15% or more is seen reliably.
- **The safety gates are hair-trigger.** They are point-estimate caps (0.5 point), and none of the
  failures was statistically supported (Holm p of 0.74 to 0.98 for the deletion rate of `HT`, 0.74 to
  0.81 for `ADA`). The hallucination gate (no more than the mean of two controls) fails when two identical
  controls are compared in 3 of 4 trials (11 against 9 and 3 against 2 critical hallucinations, 5 against 4
  ghost words). Only the latency gate discriminates. Read the gate table as "no evidence of safety
  at these sample sizes" and not as "unsafe".
- **The conclusion is about the 20% bar.** ADA's roughly 17% is real (p of 0.003 or less in both
  sessions) and a true effect of 20% is not excluded. "No variant is demonstrably 20% faster on the
  per-block median" is supported moderately well. "No variant is useful" is not.
- **The plan changed in three ways, all before the result they affect.** (1) The first plan was
  amended after an independent code review. Four runs of the earlier plan had finished; none was read, and
  they were deleted with their binary. (2) Plan 1 announced six clips for session 2 and session 2 used the
  three held-out clips. (3) `HT` was added to session 2 by the investigator and not by the promotion rule.
  `decision.json` still repeats the sentence "on the clips of session 1 and the held-out clips".
- **Earlier `--realtime` numbers** in this file (the sections above) were measured with the old
  pacing: a 100 ms sleep after each chunk, so a chunk reached the decoder 100 ms early in wall time and the
  replay drifted by the cost of each chunk. The new pacing is in CLI.md.
- **Two controls and one variant per block** make the controls the better-measured side.
- **Session 2 did not use the session 1 clips.** The plan said six clips and used the three that
  session 1 had not used. They are independent clips, not a repeat of the same ones.
- **AMI has no WER**, and the missing-speech check there is time-based.
- **Contention.** Another agent used this Mac. It was sampled, flagged and tested, not removed.
- **One machine.** Mac mini M2 Pro, 16 GB. No other Mac was measured.
- **Latency is measured from the model's own word end times.** A second check, anchored on the
  reference segment ends, is in the gate. It disagrees with the first for `CTX` (8% faster by the
  model's times, 6.8% slower by the reference's).

## Limitations

1. **One machine at a time.** The tables above the dated baseline come from one
   MacBook Pro M5 Pro. The [2026-11-01 baseline](#2026-11-01-baseline-f022c6e-on-the-mac-mini-m2-pro)
   comes from one Mac mini M2 Pro, which is the hardware that the app targets,
   and it is slower. The two sets of numbers are not interchangeable.
2. **One synthetic clip carries most of the conclusions.** The voice is
   Indonesian, the acoustics are wrong, and the clip starts at full amplitude
   with no lead-in.
3. **The real excerpt is 25 seconds and its reference is poor.** A 60% WER on
   it measures the reference.
4. **No far-field room recording was measured.** Several people who speak
   Tagalog across a room is the primary case for this app, and it is also the
   hardest case to reproduce without private data.
5. **Two scorers report different WER for the same transcript.** Check which
   one a number came from before you compare it to another number.
6. **Most accuracy numbers here are the Balanced tier.** The
   [tier comparison](#tier-comparison-2026-11-02) is the only measurement of all three tiers.
   [MODELS.md](MODELS.md) lists which tier promises this project measured,
   and which ones it infers.
7. **One run is not a measurement.** The same build gives a different
   transcript of the same file on different runs. Over eight offline runs of
   the synthetic clip, the WER went from 25% to 57%, because the first window
   sometimes comes back as invented English filler. [FINDINGS.md](FINDINGS.md)
   entry 15 gives the numbers. Run each build several times, and compare the
   spread.
8. **The shared Mac moves the timings.** The bench lock serializes measured
   runs and nothing else. Builds, tests and other agents' work ran at the same
   time as the baseline (load average 1.6 to 6.4), and one agent held the lock
   for long stretches. RTF and per-hop time vary with it. Read the median and the
   interquartile range, and re-run a timing claim on a quiet Mac.
9. **The reference has two word counts, one for each scorer.**
   `synthetic-taglish.txt` has 128 words for `eval/score.py` and for the CLI's
   own scorer, which split "i-send" into two, and 123 for `eval/langscore.py`,
   which keeps the hyphen. The same transcript therefore scores differently: run
   1 of the pure offline baseline is 31.3% by `score.py` and 34.1% by
   `langscore.py`. The tables from 2026-11-01 use `score.py`.
10. **The collapse rule is relative to the arm.** It misses a collapse when an
    arm's ordinary WER is high, and it cannot flag an arm that is bad in every
    run. `compare` adds a check against the baseline's level, and the count of
    invented-filler phrases explains a collapse. Neither is a detector for every
    failure.
11. **Memory figures describe one process.** None describes the whole machine, and
    none of the footprints contains the model. [Which number is which](#which-number-is-which)
    says what each figure is.
12. **The evaluation framework has no results yet.** It exists since
   2026-11-02. [Limitations of the framework](#limitations-of-the-framework)
   gives its own limits.
13. **The findings are engineering results and not product guarantees.** The
   caveat section of [FINDINGS.md](FINDINGS.md) says which findings are
   structural, and which ones must be derived again against your own
   recordings.

## Measure your own audio

**Your corrections are the best references you have.** In Advanced mode,
**File › Export Corrections as References…** writes a folder with a copy of
each recording that has edits, the edited transcript as the reference, and a
`manifest.json`. Point the harness at it:

```bash
python3 eval/compare_language.py --manifest FOLDER/manifest.json \
    --bin app/.build/release/transcribe --models models --arms tl
```

The folder's `summary.md` also gives the raw model text scored against your
corrections, with no new decode. That number is the error rate you experience.

To compare two builds on your own audio, repeat and interleave them, with the
rules of [Compare two builds](#compare-two-builds): a single run of one build
against a single run of another proves nothing.

In the app, press ⇧⌘K for the model benchmark. It measures the three tiers on
your own audio and recommends the slowest tier that stays at real-time speed.
**It ranks the tiers by decode time, and it does not measure accuracy.**

From the command line:

```bash
cd app && swift build -c release --product transcribe
./.build/release/transcribe --audio yours.m4a --reference yours.txt \
    --models ../models --json /tmp/run.json
```

[CLI.md](CLI.md) gives the rest of the options.
