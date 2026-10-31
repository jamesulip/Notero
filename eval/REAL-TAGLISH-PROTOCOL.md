# Producing a real Taglish reference from your own meetings

**Why this exists.** Every accuracy number in this repository comes from either a
synthetic clip (an Indonesian voice reading a Taglish script) or read Tagalog
sentences (FLEURS). Neither is Taglish, and neither is a meeting. The only way to
get a Taglish number is a reference that a person made from real audio. This is
the least work that gives a number you can act on, and how to keep it honest.
Nothing here needs the repository to see your recordings. Everything runs on your
Mac.

## 1. What the app already gives you

**File › Export Corrections as References** (Advanced mode) writes a folder of
every recording that has at least one corrected line:

```
notero-references-<date>/
  audio/<id>.m4a     a copy of the recording
  refs/<id>.txt      the transcript with your corrections applied  (the reference)
  raw/<id>.txt       the transcript as the model wrote it
  edits/<id>.tsv     only the lines you changed, raw beside corrected
  manifest.json      id, audio, ref, title, durationMs
  summary.md         the raw model text scored against your corrections
```

**The trap in that export.** `refs/` is the *whole* transcript with your edits
applied. A line you did not touch counts as a line you approved. If you corrected
only the lines you happened to notice, the reference is the model's own output with
a few fixes, and the raw WER in `summary.md` is **optimistic**: every error you did
not notice is scored as correct. A second configuration, with errors that overlap
the first model's, looks better than it is. The same bias favours any decode that
produces the same words as the model, which is every configuration of the same model.

## 2. The minimum protocol

1. **Choose the audio before you look at any score.** At least 3 meetings and at
   least 30 minutes of speech in total, so that the number is not one meeting's
   accent or one microphone. Include at least one of each setting you care about:
   a headset or close microphone, a room with several people, a call through system
   audio. Write the setting down beside each id (speakers, microphone, room,
   how much English). Aim for at least 5,000 reference words and at least 1,000
   English tokens: see section 4 for what that buys.
2. **Review whole stretches, not lines you noticed.** Pick a stretch of each meeting
   (a 5 to 10 minute block is realistic), play it, and correct **every** line in it
   against the audio. Record the start and end times of what you reviewed. Score
   **only the reviewed stretches**. Delete the rest from the folder (`manifest.json`
   entries, or cut the audio) rather than leaving lines you did not review in the
   reference.
3. **Make a gold slice, to find the noise floor.** For one 5 minute stretch per
   meeting, type the transcript from the audio *without reading the draft* first,
   then compare it with your corrected version with
   `python3 -I eval/langscore.py <corrected.txt> <blind.txt>` (it prints the WER and the
   per-language errors). That word error rate between your two passes is the floor: differences between
   configurations smaller than it are noise. Better still, have a second person
   transcribe the same slice and report both.
4. **Agree the spelling once, and write it down.** Without a convention the scorer
   counts a spelling choice as a recognition error. The harness lower-cases and
   drops punctuation (`score.normalize`) and keeps digits as digits, so fix these
   by hand: numerals as digits; English words in English spelling ("meeting",
   not "miting"); a Tagalog affix on an English stem joined with a hyphen
   ("i-send", "nag-review"); Tagalog particles as spoken ("po", "ho", "naman");
   fillers ("ah", "eh", "uh") either always kept or always dropped, and say which.
   Do not repair grammar the speaker did not use.
5. **Decide the comparisons first.** Write down which configurations you will
   compare (forced `tl` against `auto`; this build against the last; the three tiers)
   and what difference you will act on, before you read a result. A paired
   comparison over utterances (same audio, two configurations) needs far fewer
   words than two separate estimates: see section 4.
6. **Keep it private.** The folder holds real meetings. Work on a copy outside the
   repository (for example `/tmp/notero-data/mine/`), never commit it, never attach
   it to an issue, and run the scripts with `python3 -I`. The decode is offline.

## 3. Scoring it

```bash
# Point the harness at the folder the app wrote. The audio is read where it is, not copied.
python3 -I eval/fleurs_eval.py import-references --refs <folder> --work /tmp/notero-data/mine

# Decode each configuration. --lock-batch 4 holds the shared bench lock once per four decodes.
python3 -I eval/fleurs_eval.py decode --work /tmp/notero-data/mine --set subset --lock-batch 4 \
    --arm "tl|app/.build/release/transcribe|--language tl" \
    --arm "auto|app/.build/release/transcribe|--language auto"

python3 -I eval/fleurs_eval.py score   --work /tmp/notero-data/mine --set subset --arm tl --arm auto
python3 -I eval/fleurs_eval.py compare --work /tmp/notero-data/mine --set subset --a tl --b auto
```

`score` prints WER, CER, the Filipino and English word error rates, the error rate
at code-switch points, retried and dropped windows, and the real-time factor with the
machine load. `compare` prints the paired difference with an interval that resamples
utterances, the utterances where each configuration is better, and the worst
regressions word by word.

`eval/compare_language.py --manifest <folder>/manifest.json` reads the same folder
for the `tl` against `auto` comparison alone.

The word classes come from a heuristic (`eval/langscore.py`): a short list of Tagalog
function words, then the macOS English word list, else Filipino. It is *good enough
to see a trend and wrong on individual words*. Read its output against the words
themselves before you quote it.

## 4. How much is enough

Treat these as rules of thumb for what a result can distinguish, not as guarantees.
The intervals in `score` and `compare` resample utterances and are the better guide.

- An error rate p over N words has a standard error of about `sqrt(p(1-p)/N)` if
  words were independent, which they are not (errors cluster in an utterance), so
  the real interval is wider. For p = 15% over N = 1,000 English tokens that is
  about ±2.2 points before clustering.
- The English-token error rate needs English tokens. The FLEURS references hold 608
  tokens that `langscore` calls English across 349 sentences, and most of them are
  Tagalog words that spell like English ones or foreign proper names. Real meetings
  should give you several times that density; check with `score`'s token list.
- A paired comparison of two configurations needs the same audio decoded by both, and
  is far more sensitive than two separate estimates, because the audio's difficulty
  cancels. Report the utterances where they differ, not only the pooled number.
- Run each configuration more than once on a few utterances before you trust one run.
  The offline decode is deterministic when the first greedy decode passes its gates
  and is not when a window falls back to sampling (docs/FINDINGS.md 15, 16).

## 5. What the number will and will not say

It will say how this model, this build and these settings transcribe **your**
meetings, in **your** rooms, with **your** speakers' accents and mix of languages.
It will not say anything about anyone else's. It is not a benchmark and should not
be quoted as the accuracy of the app.
