# Taglish and Filipino speech corpora: which are suitable for Notero

Research report, checked **2026-11-02**. It answers one question: which public speech
resources can Notero use to measure how well it transcribes natural Filipino-English
(Taglish) speech, and which cannot. It is a reading of published licence text and dataset
documentation. It is not legal advice, and where a statement could not be checked it says
**NOT VERIFIED**.

**"Our use"** means: download the data once to one Mac, decode it offline with Notero's models,
score the output against the reference, and publish only aggregate error rates (and at most a few
short error snippets) in this public MIT repository. We never redistribute the data. Nothing in
this change downloaded or processed a new corpus: the only data used is what was already in
`/tmp/notero-data` (Liva AI `en-tl`, FLEURS `fil_ph`), and no audio, transcript or corpus text is
committed.

## How this was checked

Two read-only research passes read dataset cards, README and licence files, API metadata (Hugging
Face `api/datasets/<repo>`, the OSF API, GitHub and Zenodo APIs), paper pages and catalogue pages.
They downloaded no dataset file. One pass did stream the first 3 KB of one Liva transcript record to
its terminal while it checked the file format, and saved nothing. It touched the Liva audio only
with HTTP HEAD requests. (The Liva sample is already this project's CC BY 4.0 test data.)
**Claude (the model that made this change) then re-read these primary fields itself**, with the
same read-only requests. An independent review repeated each of them, and also read the FilSwitch
card text and all 25 of its revisions, the OSF child components and the Liva WAV headers. It found
them as stated.

| Re-read directly on 2026-11-02 | Value |
| --- | --- |
| OSF node `kh862` (CEnTaCS): licence | `CC-By Attribution 4.0 International`, `https://creativecommons.org/licenses/by/4.0/legalcode`; `date_modified` 2026-08-25T11:51:39Z |
| OSF log of `kh862`, `license_changed` | 2026-04-10: `CC-BY Attribution-NonCommercial-ShareAlike 4.0 International`; 2026-08-25: `CC-By Attribution 4.0 International` |
| `qwerttyuiiop/FilSwitch` | sha `e1a2e429…`, `gated: false`, `cardData` = task, language and tags only: **no `license` key** |
| `liva-ai/code-switching-asr` | sha `51b5d0b4…` (2026-07-15), `gated: false`, `license: cc-by-4.0` |
| `google/fleurs` | sha `70bb2e84…` (2026-05-15), `gated: false`, `license: ["cc-by-4.0"]` |
| `SilencioNetwork/tagalog-filipino-speech` | sha `9fd981c7…` (2026-09-22), `gated: false`, `license: cc-by-nc-4.0` |

Everything else below is as the research passes reported it, **and is not re-read**: the CEnTaCS
paper, the FilSwitch Croissant and datasets-server records and preprint, Common Voice, the Mozilla Data
Collective pages, the LDC pages, MLC-SLM, WorldSpeech, and the licences of AMI and the other English
meeting sets. Those reads went through a page summariser for most web pages, so a quotation is a
short string it returned. Where a verdict depends on such a read, the entry says so.
Every statement of the form "there is no X" means "none was found in the checks described here". The
checks were catalogue and search reads, not an exhaustive survey.

## Summary

| Resource | Speech | Size | Licence | Our use | Verdict |
| --- | --- | --- | --- | --- | --- |
| **CEnTaCS** (Ghent University with UP Diliman) | elicited story-retelling monologue, English-Tagalog | 5.40 h, 104 speakers | CC BY 4.0 (OSF) | **yes** | **Suitable: a small open Taglish test set.** Not conversation, no language tags |
| **FilSwitch** (DLSU, Ateneo) | read Philippine news sentences, Filipino-English | 8.9 h; test split 2.04 h, speaker-disjoint | **none stated** | not without permission | Best fit for read Taglish; **ask the authors for written permission first** |
| **Liva AI `en-tl`** sample | conversational Taglish, friends in a game voice chat | 4 files, 40 min (measured) | CC BY 4.0 (card) | yes | Already used. A smoke test, not a benchmark |
| FLEURS `fil_ph`, `ceb_ph` | read, Wikipedia-style sentences | `fil_ph` test 964 recordings | CC BY 4.0 | yes | Already used (`fil_ph`). Read speech only |
| Mozilla Data Collective "Tagalog Voice Notes ASR" | two-party WhatsApp-style voice notes, transcribed | 45-47 h, about 48 speakers | MDC-DLA-1.0 | plausibly, **paid** | Best fit by style; costs about $9,450 plus 5%; phone audio, not far-field |
| UP-DSP Philippine Languages Database | mostly read; about 32 h elicited free speech | 454 h, 10 languages | CC BY-NC 4.0, "solely for research" | unclear | Free, but not conversational and not clearly usable for a product benchmark |
| LDC Babel Tagalog / Cebuano, MATERIAL Tagalog-English | telephone conversation | 213 h / 191 h / about 100 h | LDC non-member fee | unclear, agreement not read | Real conversation but 8 kHz telephone and paid |
| MLC-SLM 2026 (Tagalog; Filipino-accented English) | two-speaker conversations | about 100 h each | challenge Data Use Agreement | no / unclear | Right style, gated by a challenge-only agreement |
| Silencio Tagalog / Cebuano samples | spontaneous prompted monologue | 2.03 h / 3.48 h | CC BY-NC 4.0 | unclear (card says benchmarking a commercial product is commercial) | Too small, NC |
| WorldSpeech `tl_ph` | Philippine House and Senate proceedings | 219 h | CC BY-NC 4.0 | unclear | Formal speech, loose labels: a stress test at most |
| Common Voice | none: no `tl`, `fil` or `ceb` in releases 1.0 to 27.0 | 0 h | CC0 | n/a | Nothing to use |
| YODAS3 `fil` | YouTube with captions | about 120 GB of audio | CC-BY-3.0 (a platform flag) | likely for private scoring | **Not suitable**: references are mostly machine captions |
| AMI, ICSI, NOTSOFAR-1, CHiME-6, DiPCo | **English** far-field meetings | tens of hours | CC BY 4.0 / CC BY-SA 4.0 / CDLA-Permissive 1.0 | yes | English acoustic proxies only. No Filipino speakers verified |
| Text resources (TweetTaglish, CodeSwitch-Reddit, ICE-PHI, LinCE, CALCS) | text | | no licence, academic-only, or no Tagalog | no | Not suitable |

## A correction to an earlier claim

`docs/BENCHMARKS.md` said: *"Real meeting accuracy is unmeasured, because no public conversational
Taglish corpus of a useful size has a licence that allows this use"*. `eval/TIER-RESULTS.md` said
that no permissively licensed corpus of conversational Taglish *meetings* exists, and that FilSwitch
has **no licence stated**.

- **FilSwitch has no licence stated: confirmed.** Claude re-read the API record (no `license` key). The
  independent review read the card text, all 25 revisions and the file list (no licence). The
  Croissant and datasets-server records and the preprint were read only by the research pass. An
  early revision of the card said the licence "will be provided upon release", and a later one
  dropped that line without adding one. The camera-ready paper was not available, so a licence
  there is not excluded.
- **The broader claim was wrong as worded.** Licences that allow our use do exist for public Taglish
  speech: Liva's `en-tl` sample (conversational, CC BY 4.0) and **CEnTaCS (CC BY 4.0, public on
  OSF, no form or fee)**. CEnTaCS was not in the earlier note. Its OSF licence was changed from
  CC BY-NC-SA 4.0 to CC BY 4.0 on 2026-08-25, and the University of Ghent repository record still
  lists the older licence, so archive the OSF licence page and log with any result.
- **The size part of the claim stands.** Nothing found is large, conversational, human-transcribed
  and clearly permissive at once. The permissive conversational set is 40 minutes (Liva `en-tl`);
  CEnTaCS is 5.4 hours of monologue; the large conversational Tagalog collections are paid, gated or
  non-commercial.
- **No public Filipino meeting speech was found, and none that is far-field.** "Real meeting
  accuracy is unmeasured" remains true.

Better wording: *none of the sources checked here is a large, human-transcribed, conversational
Taglish corpus under a clearly permissive licence; two small permissive sets exist (CEnTaCS, 5.4 h of
monologue; Liva `en-tl`, 40 minutes), and none of the sources checked is Filipino meeting speech.*

## Resources suitable for Notero

### CEnTaCS: Corpus of English-Tagalog Code-switching

- **What:** story-retelling recordings of a short animated film, plus cognitive-control and
  questionnaire data. Authors Aaron Santa Maria and Renata Enghels (Ghent University), with UP
  Diliman Linguistics. Scientific Data, DOI `10.1038/s41597-026-08264-2` (an accelerated-preview
  article, September 2026).
- **Size (published):** 104 participants, 104 WAV files, 5.40 hours, 1.3 to 5.3 minutes each.
  Audio is 44.1 kHz stereo, recorded on a hand-held recorder, some in cafes. The paper's word
  count is inconsistent with itself (39,310 in the text, 33,910 in a table).
- **Speech style:** elicited **monologue**. Not conversation, not a meeting, not far-field.
- **Languages:** English and Tagalog, including switches inside a word ("nagpromise").
- **Annotation:** human transcripts in normal orthography, segmented by breath group, each
  utterance numbered with a time stamp; ELAN, text and PDF; participant metadata. **No per-word
  language tags** ("Annotation Unspecified"). Transcripts are lower case.
- **Licence:** CC BY 4.0 on the OSF project, re-read today (above). The paper says the 104
  participants consented to open publication of recordings, transcripts and annotations.
- **Revision:** OSF project `kh862`, DOI `10.17605/OSF.IO/KH862`, last modified 2026-08-25 (no git
  hash exists). Discrepancy: the OSF wiki gives the recording dates as August 5 to September 9
  2026, and the paper says 2025.
- **Access:** public, no login, no form, no fee.
- **Verdict: suitable** as a small, permissive, human-transcribed Taglish test set with real
  intra-sentence and intra-word switching, and the best candidate for hand-tagging a stretch with
  the taxonomy's tagged-text format. **Not processed in this change.** Limits: monologue, 5.4 h,
  one recorder, no tags.

### Liva AI `code-switching-asr`, folder `en-tl/overlapping` (already used)

- **What:** the four-file Taglish part of a vendor sample. "Samples include en-sw, en-pcm, en-yo,
  and en-tl." It is not the vendor's full product.
- **Size:** 4 WAV files, 86,400,102 bytes each. **Measured: 600.0 s each, 40 minutes in
  total** (the decode reports give `durationMs` 599,999). The research pass estimated about 1 h
  from the file size without a sample rate; the measured figure replaces it.
- **Style:** conversational and multi-party, friends in a game voice chat, mixed to one track,
  4-5 speakers per file, overlapping speech. Not a meeting.
- **Annotation:** `Speaker N [hh:mm:ss.mmm - hh:mm:ss.mmm]: text` per turn with speaker labels,
  millisecond times, overlapping turns and audio tags such as `[laughing]`. **No per-word language
  tags.** The card says transcripts are "either AI-generated and then human reviewed, or fully
  human generated, depending on customer request"; which applies here is not stated.
- **Licence:** `license: cc-by-4.0` in the card's YAML at revision `51b5d0b4…`; the body adds no
  terms. The licensor is the vendor that recorded the audio. The recorded users' consent to public
  release is not documented.
- **Access:** public, ungated. Attribution: Liva AI, Code-Switching ASR.
- **Verdict: suitable only as a tiny conversational smoke test.** One group of friends, 40 minutes,
  and its transcripts of overlapping speech leave out or reorder words. Too small for a headline
  number.
- **Not usable:** the sibling `liva-ai/yapdo-convo` is a gated sample of a vendor corpus with no
  licence.

### FLEURS `fil_ph` and `ceb_ph` (already used)

- **What:** Google's 102-language read-speech benchmark. `fil_ph` test: 964 recordings; `ceb_ph`
  (Cebuano) test: 541. Licence `cc-by-4.0` (card; paper states none), revision `70bb2e84…`.
- **Style:** read sentences. **Speakers:** not published; the card has no speaker field.
- **Annotation:** raw and normalised transcripts, gender. No timestamps, speaker ids or
  code-switch tags.
- **Verdict: suitable** as a clean read-speech baseline. It is not Taglish and not a meeting.

## Resources suitable only after a step

### FilSwitch

- **What:** a Filipino-English read-speech dataset for ASR, De La Salle University Manila with
  Ateneo de Manila (O-COCOSDA 2026 preprint). Hugging Face `qwerttyuiiop/FilSwitch`, revision
  `e1a2e429…`.
- **Size (published):** 152 speakers (110 male, 42 female, aged 18-23), 8.9 hours, 3,513
  utterances in the files and the paper (the card says 3,555). Test split 2.04 hours, 804
  utterances, speaker-disjoint. About 1 GB, 16 kHz FLAC.
- **Style:** **read**. News sentences from the CoHFiE corpus (Abante, ABS-CBN, Balita, Bandera, GMA,
  Manila Bulletin, Philstar, Radyo Inquirer), filtered by an LLM for code-switching, read on the
  speakers' own devices. Not conversational. The licence of the source text was **NOT VERIFIED**.
- **Annotation:** utterance-level validated transcripts, an `snr` field. No timestamps or speaker
  ids in the files. The paper reports LLM-generated word-level language tags only as statistics;
  they are not published. The paper's own inter-annotator kappa is 0.10 to 0.22.
- **Licence: none stated, anywhere checked** (card YAML, card text and history, repository files,
  Croissant, datasets-server, preprint). The card states an intended use, "Filipino-English ASR
  fine-tuning, benchmarking, and error analysis", which is not a grant.
- **Access:** public download, no login.
- **Verdict: not usable until the authors give written permission.** The corresponding author is
  named on the card and in the paper. It is the best-matched read Taglish ASR test set found, with
  published baselines, so the request is worth sending. Read news is not conversational Taglish.

## Resources with a real cost or limit

- **Mozilla Data Collective, "Tagalog Voice Notes ASR Dataset (45 hours)"** (id
  `cmuh4ozy804olny07mu2h0kjm`, release 2026-09-25): two-party voice-note conversations on
  messaging apps, 45-47 hours, about 48 speakers, transcribed; code-switch tags and timestamps not
  stated. Licence MDC-DLA-1.0, which allows internal and commercial processing and forbids
  disclosing the data, and permits "models, insights and outputs" that do not disclose it. That
  plausibly covers aggregate scores; a quoted transcript snippet might not. Price on the page:
  $9,450 plus a 5% fee. **The only conversational, human-transcribed Tagalog set over 5 hours
  found whose licence plausibly allows our use**, and the price puts it out of reach here.
- **UP-DSP Philippine Languages Database** (Mozilla Data Collective, release 2026-03-19): "over 454
  hours", ten languages, news, medical, education, tourism and about 32 hours of elicited
  spontaneous speech (one source says speakers answer a question with free speech, and its
  transcripts are NOT VERIFIED). CC BY-NC 4.0, "used solely for research purposes", no
  redistribution. A third-party Hugging Face mirror exists; do not use it. Whether benchmarking a
  free MIT app is "research" is a question for the owner.
- **LDC** Babel Tagalog (LDC2016S13, 213 h), Babel Cebuano (LDC2018S07, 191 h), MATERIAL
  Tagalog-English (LDC2026S05, about 100 h), Call My Net 1 (LDC2024S05): real telephone
  conversation, 8 kHz, paid non-member licences whose text was NOT VERIFIED.
- **MLC-SLM 2026**: about 100 hours each of Tagalog and Filipino-accented English, two-speaker
  conversations at 16 kHz with transcripts and timestamps, under a challenge Data Use Agreement
  limited to the challenge. Not far-field.
- **Silencio** Tagalog (2.03 h, 16 speakers) and Cebuano (3.48 h) samples: spontaneous prompted
  monologue with word timings, CC BY-NC 4.0, and the card says benchmarking a commercial product
  is a commercial use.
- **WorldSpeech `tl_ph`** (219 h, House and Senate): CC BY-NC 4.0, uncertain source terms; labels are
  official records matched loosely to the audio. A rough stress test at most.

## Resources that are not suitable

- **Common Voice:** the official statistics for releases 1.0 to 27.0 contain no Tagalog, Filipino or
  Cebuano, and Spontaneous Speech 5.0 has none. English has about 7,500 clips with a "philippines"
  accent tag (read, CC0, hosted only on Mozilla Data Collective since October 2025).
- **YODAS3 `fil`:** large and labelled CC-BY-3.0 (the uploader's YouTube flag, not a clearance), but
  most references are machine captions and nothing is filtered for Taglish.
- **Vendor teasers:** SpeechDataAI, Nexdata, DataOcean, Defined.ai, MagicHub and the `yapdo-convo`
  card describe large Tagalog conversation corpora that are sold; samples carry no usable
  licence.
- **`sapinsapin` repackagings** (a Filipino speech corpus labelled MIT by the repackager, a
  livestream sample, the PLD mirror): the repackager is not the rights holder.
- **`PixelML/sea-asr-ph-data`**: transcripts only, every one a Whisper output "no person checked".
- **Text:** TweetTaglish (tweet ids, no licence), CodeSwitch-Reddit (no licence, post-level labels),
  ICE-Philippines (academic-only licence, form), LinCE and CALCS (no Tagalog). PinoyBot's word-level
  Filipino-English tags (MIT, but the sentences come from CoHFiE, whose licence was not verified)
  could only seed a word list.

## Far-field and meeting speech

**No public far-field Filipino speech with a licence that fits was found**, and none that is a
meeting. For far-field acoustics only English proxies exist, and none was verified to
include Filipino speakers:

| Corpus | Style | Licence |
| --- | --- | --- |
| AMI (already used for diarization) | English design-team meetings, close and far microphones | CC BY 4.0 (re-checked on the AMI site) |
| ICSI | English meetings, about 70 h | CC BY 4.0 on the Edinburgh copy |
| NOTSOFAR-1 | English meetings, 237 meetings in 30 rooms, plus simulated | CC BY 4.0 (not dev-set-2) |
| CHiME-6 | English multi-channel dinner parties | CC BY-SA 4.0 |
| DiPCo | English dinner parties, five far-field arrays | CDLA-Permissive 1.0 |

Philippine-accented English: Common Voice (read, about 7,500 clips) and MLC-SLM Filipino English
(agreement). L2-ARCTIC has no Tagalog speakers (checked). Whether EdAcc, AMI or the Speech Accent
Archive include Filipino speakers is NOT VERIFIED.

## What is in the repository, and what is not

- This change **added no data.** The synthetic fixtures in `eval/fixtures/taxonomy/` are text written
  for the repository.
- The Liva and FLEURS files used for the taxonomy results stay in `/tmp/notero-data` and are not
  in git. The committed reports under `eval/baselines/taxonomy-2026-11-02/` hold counts and no
  corpus text.
- Attribution if results are published: Liva AI, Code-Switching ASR (CC BY 4.0); Google, FLEURS (CC
  BY 4.0); and, if it is ever used, Santa Maria and Enghels, CEnTaCS (CC BY 4.0).

## NOT VERIFIED

- The licence of CoHFiE, the text corpus behind FilSwitch and PinoyBot.
- Whether the camera-ready FilSwitch paper states a licence.
- The text of the LDC agreements, the MLC-SLM Data Use Agreement and the UP-DSP spontaneous
  transcripts.
- Whether Liva's `en-tl` transcripts are machine-drafted or fully human.
- Any Filipino speaker in EdAcc, AMI or the Speech Accent Archive.
- The licences of PSGC and PhilGEPS (the PSA site returned 403); the Wikidata, Wikipedia and GeoNames
  licences, which are standard, were read.

## What to do next

1. Write to the FilSwitch authors for permission to evaluate on its test split.
2. If the owners agree, fetch CEnTaCS (about 3.4 GB, estimated from the published audio format), decode it, and hand-tag a reviewed stretch with
   [the tagged format](../eval/TAXONOMY.md#reference-formats). That would give the first `verified`
   language labels in this repository.
3. Do not read any number from FLEURS, Liva or CEnTaCS as a meeting number. A real answer needs the
   user's own reviewed meetings ([REAL-TAGLISH-PROTOCOL](../eval/REAL-TAGLISH-PROTOCOL.md)).
