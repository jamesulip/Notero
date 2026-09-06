"""Measure an MLX language model as a note-taker on one of your own meetings.

The app's automatic notes read the transcript in parts, ask a model for a
summary and typed notes per part, then write one summary of the whole
meeting. This harness does the same with `mlx_lm` so a candidate model can
be measured before it is wired into the app. The prompt text mirrors
`NotesPrompt` in `TranscriberCore/MeetingNotes.swift`; change both together.

Input is the app's JSON export of a recording (File > Export > JSON), which
carries the transcript, the speakers and the hand-written notes. Output is a
draft you can read and a report you can compare:

  * grounding: the share of each note's content words that occur in the
    transcript within two minutes of the note's timestamp. Low means the model
    invented. English notes about Tagalog speech score lower by construction.
  * language: the Tagalog share of the transcript and of the notes, by the
    heuristic in `langscore.py`.
  * coverage: how many hand-written notes the draft also has, and how many
    draft notes match a hand-written one, by content-word overlap.
  * failures: parts whose answer was not JSON, and parts that ran over the
    token budget.

    ./.venv/bin/python eval/notes_eval.py --document meeting.json \
        --model mlx-community/Qwen3-4B-Instruct-2507-4bit --style english \
        --out eval/out/notes

The document holds a real meeting. Do not attach it, or the output folder,
to a public issue.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import langscore  # noqa: E402

KINDS = ["keyPoint", "decision", "actionItem", "question", "followUp"]
KIND_LABEL = {"keyPoint": "Key Points", "decision": "Decisions", "actionItem": "Action Items",
              "question": "Questions", "followUp": "Follow-ups"}
MAX_TURN_MS = 30_000
GAP_MS = 1_500

STOP = set("""
the and for that this with have from are was were will would can could should they them their
there here what when where which who whom how why not but all any some also into onto about
then than been being does did doing has had our you your his her its out over under after
before because while just very more most much many such only same other another each both
ang mga ito iyan iyon yan yun yung nito dito diyan doon hindi wala walang may mayroon meron
kung kasi para pero tapos lang lamang din rin naman daw raw kaya dahil pwede puwede dapat
baka siguro talaga medyo masyado lahat bawat ngayon kanina mamaya muna ulit pala nga kaso
saka sana yata kapag habang bago hanggang mula tungkol ganito ganyan ganun ganon mas sobrang
ako ikaw siya kami tayo kayo sila natin namin ninyo nila niya kita nyo kayong ating
""".split())


def instructions(style: str) -> str:
    language = ("Write the notes in English." if style == "english"
                else "Write the notes in the same mix of languages that the speakers used.")
    return (
        "You take notes for a meeting. The transcript is from a business meeting in the Philippines. "
        "The speakers mix Tagalog and English. Each line starts with a timestamp in square brackets "
        f"and the name of the speaker. {language} Write only what the transcript supports. Do not "
        "invent a name, a number or a decision. Keep names, product names and numbers exactly as "
        "written. A decision is something the group agreed. An action item is a task that one "
        "person agreed to do. A question is one that was asked and not answered. A follow-up is "
        "something to return to later. A key point is a fact or a position worth keeping."
    )


def request(index: int, text: str, max_items: int = 10) -> str:
    return (
        f"Transcript, part {index + 1}:\n\n{text}\n\n"
        "Answer with one JSON object and nothing else, in this form:\n"
        '{"summary": "two or three sentences on what this part was about", '
        '"items": [{"kind": "keyPoint|decision|actionItem|question|followUp", '
        '"text": "the note in one sentence", "at": "the timestamp of the line it comes from, '
        'copied exactly, for example 12:34"}]}\n'
        f"Give at most {max_items} items. Leave the list empty when this part has nothing worth keeping."
    )


def summary_request(parts: list[str], title: str) -> str:
    numbered = "\n".join(f"Part {i + 1}: {s}" for i, s in enumerate(parts))
    return (
        f'These are the summaries of the parts of the meeting "{title}", in order:\n\n{numbered}\n\n'
        "Write one summary of the whole meeting in three to six sentences: what it was about, "
        "what was decided, and what is still open. Answer with the summary only."
    )


def stamp(ms: int) -> str:
    s = max(0, ms) // 1000
    return f"{s // 3600}:{(s % 3600) // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


def parse_stamp(text) -> int | None:
    if text is None:
        return None
    digits = re.sub(r"[^0-9:]", "", str(text))
    if ":" not in digits:
        return None
    parts = digits.split(":")
    if len(parts) > 3 or any(p == "" for p in parts):
        return None
    values = [int(p) for p in parts]
    if any(v >= 60 for v in values[1:]):
        return None
    seconds = 0
    for v in values:
        seconds = seconds * 60 + v
    return seconds * 1000


def content_words(text: str) -> set[str]:
    out = set()
    for raw in re.split(r"[^\w'-]+", text.lower()):
        word = raw.strip("-'")
        if len(word) >= 3 and word not in STOP:
            out.add(word)
    return out


def turns(document: dict) -> list[dict]:
    names = {s["id"]: s["displayName"] for s in document.get("speakers", [])}
    out: list[dict] = []
    for seg in sorted(document["segments"], key=lambda s: s["startMs"]):
        text = (seg.get("textClean") or seg["text"]).strip()
        if not text:
            continue
        spk = seg.get("speakerId")
        if out and out[-1]["speakerId"] == spk and seg["startMs"] - out[-1]["endMs"] <= GAP_MS \
                and seg["endMs"] - out[-1]["startMs"] <= MAX_TURN_MS:
            out[-1]["endMs"] = seg["endMs"]
            out[-1]["text"] += " " + text
        else:
            digits = "".join(ch for ch in (spk or "") if ch.isdigit())
            name = names.get(spk) or (f"Speaker {int(digits)}" if digits else spk)
            out.append({"startMs": seg["startMs"], "endMs": seg["endMs"], "speakerId": spk,
                        "speaker": name, "text": text, "segmentId": seg["id"]})
    return out


def render(turn: dict) -> str:
    who = f"{turn['speaker']}: " if turn["speaker"] else ""
    return f"[{stamp(turn['startMs'])}] {who}{turn['text']}"


def chunks(turn_list: list[dict], end_ms: int, max_chars: int) -> list[dict]:
    out: list[dict] = []
    bucket: list[dict] = []
    count = 0
    for t in turn_list:
        cost = len(render(t)) + 1
        if bucket and count + cost > max_chars:
            out.append({"lines": bucket, "endMs": t["startMs"]})
            bucket, count = [], 0
        bucket.append(t)
        count += cost
    if bucket:
        out.append({"lines": bucket, "endMs": end_ms})
    for i, c in enumerate(out):
        c["index"] = i
        c["startMs"] = c["lines"][0]["startMs"]
        c["text"] = "\n".join(render(t) for t in c["lines"])
    return out


def parse_item(raw) -> dict | None:
    if not isinstance(raw, dict) or not raw.get("text"):
        return None
    key = re.sub(r"[^a-z]", "", str(raw.get("kind", "")).lower())
    kind = next((k for k in KINDS if k.lower() == key or KIND_LABEL[k].lower().replace(" ", "") == key), None)
    if kind is None:
        kind = {"action": "actionItem", "task": "actionItem", "followup": "followUp",
                "key": "keyPoint", "point": "keyPoint", "agreed": "decision"}.get(key)
    if kind is None:
        return None
    return {"kind": kind, "text": str(raw["text"]).strip(), "at": raw.get("at")}


def parse_notes(text: str) -> dict | None:
    """The answer as JSON, or, when the brackets are broken, the summary
    string and each item object read on their own. Qwen2.5-3B closed 8 of 14
    answers with `}}}` and no `]`; every one held usable items."""
    open_ = text.find("{")
    close = text.rfind("}")
    if open_ >= 0 and close > open_:
        try:
            obj = json.loads(text[open_:close + 1])
            if isinstance(obj, dict):
                items = [i for i in (parse_item(r) for r in obj.get("items") or []) if i]
                return {"summary": str(obj.get("summary") or "").strip(), "items": items}
        except json.JSONDecodeError:
            pass
    if '"summary"' not in text and '"items"' not in text:
        return None
    summary = ""
    m = re.search(r'"summary"\s*:\s*("(?:[^"\\]|\\.)*")', text)
    if m:
        try:
            summary = str(json.loads(m.group(1))).strip()
        except json.JSONDecodeError:
            summary = ""
    items = []
    for obj_text in re.findall(r"\{[^{}]*\}", text):
        if '"text"' not in obj_text:
            continue
        try:
            item = parse_item(json.loads(obj_text))
        except json.JSONDecodeError:
            continue
        if item:
            items.append(item)
    if not summary and not items:
        return None
    return {"summary": summary, "items": items}


def resolve(notes: dict, chunk: dict) -> list[dict]:
    out = []
    for item in notes["items"]:
        ms = parse_stamp(item.get("at"))
        source = None
        if ms is not None and chunk["startMs"] <= ms <= chunk["endMs"]:
            line = next((t for t in reversed(chunk["lines"]) if t["startMs"] <= ms), chunk["lines"][0])
            source = line["startMs"]
        out.append({"kind": item["kind"], "text": item["text"], "sourceMs": source, "at": item.get("at")})
    return out


def dedupe(items: list[dict], threshold: float = 0.7) -> list[dict]:
    kept: list[tuple[dict, set[str]]] = []
    for item in items:
        words = content_words(item["text"])
        dup = False
        for prev, pw in kept:
            if prev["kind"] != item["kind"]:
                continue
            union = pw | words
            if not union or len(pw & words) / len(union) >= threshold:
                dup = True
                break
        if not dup:
            kept.append((item, words))
    return [k for k, _ in kept]


def grounding(items: list[dict], segments: list[dict], window_ms: int = 120_000) -> dict:
    segs = sorted(segments, key=lambda s: s["startMs"])
    whole = content_words(" ".join(s.get("textClean") or s["text"] for s in segs))
    overlaps = []
    for item in items:
        words = content_words(item["text"])
        if not words:
            continue
        if item.get("sourceMs") is not None:
            at = item["sourceMs"]
            near = content_words(" ".join(s.get("textClean") or s["text"] for s in segs
                                          if s["endMs"] >= at - window_ms and s["startMs"] <= at + window_ms))
        else:
            near = whole
        overlaps.append(len(words & near) / len(words))
    return {"itemsScored": len(overlaps),
            "meanOverlap": sum(overlaps) / len(overlaps) if overlaps else 0.0,
            "ungrounded": sum(1 for o in overlaps if o < 0.4)}


def language_mix(text: str) -> dict:
    words = langscore.normalize(text)
    if not words:
        return {"words": 0, "tagalogShare": 0.0}
    cls = langscore.classify_words(words)
    return {"words": len(words), "tagalogShare": sum(c == "tl" for c in cls) / len(words)}


def coverage(reference: list[dict], draft: list[dict], threshold: float = 0.5) -> dict:
    ref_words = [content_words(r["text"]) for r in reference]
    draft_words = [content_words(d["text"]) for d in draft]
    matched: set[int] = set()
    covered = 0
    for words in ref_words:
        if not words:
            continue
        hit = False
        for i, cand in enumerate(draft_words):
            if len(words & cand) / len(words) >= threshold:
                hit = True
                matched.add(i)
        covered += hit
    return {"reference": len(reference), "covered": covered, "draft": len(draft), "matched": len(matched)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--document", type=Path, required=True, help="the app's JSON export of one recording")
    ap.add_argument("--model", required=True, help="an mlx-community model id, or a local path")
    ap.add_argument("--style", choices=["english", "spoken"], default="english")
    ap.add_argument("--max-chars", type=int, default=5000, help="characters of transcript per part")
    ap.add_argument("--max-tokens", type=int, default=800, help="answer budget per part")
    ap.add_argument("--max-chunks", type=int, default=0, help="stop after this many parts (0 = all)")
    ap.add_argument("--temperature", type=float, default=0.2)
    ap.add_argument("--out", type=Path, default=Path("eval/out/notes"))
    ap.add_argument("--rescore", action="store_true",
                    help="read the saved raw.json of an earlier run instead of asking the model again; "
                         "for a change to the parser or the scores")
    ap.add_argument("--max-items", type=int, default=10, help="the item cap the prompt states per part")
    ap.add_argument("--tag", default="", help="a suffix for the output folder, to keep two runs of one model apart")
    args = ap.parse_args()

    document = json.loads(args.document.read_text())
    turn_list = turns(document)
    end_ms = max(s["endMs"] for s in document["segments"])
    parts = chunks(turn_list, end_ms, args.max_chars)
    if args.max_chunks:
        parts = parts[:args.max_chunks]
    slug = args.model.rstrip("/").split("/")[-1]
    out_dir = args.out / f"{slug}-{args.style}{args.tag}"
    out_dir.mkdir(parents=True, exist_ok=True)
    system = instructions(args.style)

    if args.rescore:
        saved = {r["part"]: r for r in json.loads((out_dir / "raw.json").read_text())}
        old_report = json.loads((out_dir / "report.json").read_text())
        load_s = old_report.get("loadSeconds", 0.0)
        if "summary" not in saved:
            # A run from before the summary was saved: take it from the draft.
            draft_text = (out_dir / "draft.md").read_text()
            m = re.search(r"## Summary\n\n(.*?)\n\n## ", draft_text, re.S)
            saved["summary"] = {"raw": m.group(1) if m else "", "seconds": old_report.get("summarySeconds", 0.0)}

        def ask(user: str, max_tokens: int) -> tuple[str, float]:
            # The part index is in the request's first line; the summary
            # request has none and is read from the saved summary.
            m = re.match(r"Transcript, part (\d+):", user)
            if m:
                entry = saved[int(m.group(1)) - 1]
                return entry["raw"], entry["seconds"]
            return saved["summary"]["raw"], saved["summary"]["seconds"]
    else:
        from mlx_lm import load, generate
        from mlx_lm.sample_utils import make_sampler

        t0 = time.time()
        model, tokenizer = load(args.model)
        load_s = time.time() - t0
        sampler = make_sampler(temp=args.temperature)

    def ask_model(user: str, max_tokens: int) -> tuple[str, float]:
        messages = [{"role": "system", "content": system}, {"role": "user", "content": user}]
        kwargs = {}
        if "qwen3" in args.model.lower():
            kwargs["enable_thinking"] = False
        try:
            prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, **kwargs)
        except Exception:
            # Gemma has no system role: fold the instructions into the turn.
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": system + "\n\n" + user}], add_generation_prompt=True)
        started = time.time()
        text = generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens, sampler=sampler, verbose=False)
        return text, time.time() - started

    if not args.rescore:
        ask = ask_model

    part_summaries: list[str] = []
    items: list[dict] = []
    failures = 0
    truncated = 0
    part_times: list[float] = []
    raw_log = []
    for chunk in parts:
        text, seconds = ask(request(chunk["index"], chunk["text"], args.max_items), args.max_tokens)
        part_times.append(seconds)
        raw_log.append({"part": chunk["index"], "seconds": seconds, "raw": text})
        notes = parse_notes(text)
        if notes is None:
            failures += 1
            if not args.rescore and len(tokenizer.encode(text)) >= args.max_tokens - 2:
                truncated += 1
            print(f"  part {chunk['index'] + 1}/{len(parts)}: no JSON ({seconds:.0f}s)", flush=True)
            continue
        part_summaries.append(notes["summary"])
        resolved = resolve(notes, chunk)
        items.extend(resolved)
        print(f"  part {chunk['index'] + 1}/{len(parts)}: {len(resolved)} items ({seconds:.0f}s)", flush=True)

    items = dedupe(items)
    if len(part_summaries) == 1:
        summary = part_summaries[0]
        summary_s = 0.0
    elif part_summaries:
        summary, summary_s = ask(summary_request(part_summaries, document["title"]), 400)
        summary = summary.strip()
        raw_log.append({"part": "summary", "seconds": summary_s, "raw": summary})
    else:
        summary, summary_s = "", 0.0

    transcript_text = " ".join(t["text"] for t in turn_list)
    notes_text = summary + " " + " ".join(i["text"] for i in items)
    report = {
        "model": args.model,
        "style": args.style,
        "document": document["title"],
        "durationMs": document["durationMs"],
        "parts": len(parts),
        "maxChars": args.max_chars,
        "maxItems": args.max_items,
        "loadSeconds": round(load_s, 1),
        "partSeconds": {"mean": round(sum(part_times) / len(part_times), 1) if part_times else 0,
                        "total": round(sum(part_times), 1)},
        "summarySeconds": round(summary_s, 1),
        "failures": {"noJSON": failures, "truncated": truncated},
        "items": {k: sum(1 for i in items if i["kind"] == k) for k in KINDS},
        "itemsTotal": len(items),
        "withSource": sum(1 for i in items if i.get("sourceMs") is not None),
        "grounding": grounding(items, document["segments"]),
        "language": {"transcript": language_mix(transcript_text), "notes": language_mix(notes_text)},
        "coverage": coverage(document.get("items", []), items),
        # The same at a looser match, for notes that say the same thing in
        # other words. A hand-written note and a draft note rarely share half
        # their content words when one is a paraphrase of the other.
        "coverageLoose": coverage(document.get("items", []), items, threshold=0.3),
        "referenceSummaryChars": len(document.get("summary", "")),
    }
    (out_dir / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    (out_dir / "raw.json").write_text(json.dumps(raw_log, indent=2, ensure_ascii=False))

    lines = [f"# {document['title']} — {args.model} ({args.style})", "", "## Summary", "", summary, ""]
    for kind in KINDS:
        rows = [i for i in items if i["kind"] == kind]
        if not rows:
            continue
        lines.append(f"## {KIND_LABEL[kind]}")
        for i in rows:
            where = f" *({stamp(i['sourceMs'])})*" if i.get("sourceMs") is not None else ""
            lines.append(f"- {i['text']}{where}")
        lines.append("")
    (out_dir / "draft.md").write_text("\n".join(lines))

    g = report["grounding"]
    c = report["coverage"]
    cl = report["coverageLoose"]
    print(f"{slug} {args.style}: {len(parts)} parts, {report['partSeconds']['mean']}s/part, "
          f"{failures} no-JSON; {len(items)} items ({report['withSource']} with source); "
          f"grounding {g['meanOverlap']:.2f} ({g['ungrounded']} under 0.4); "
          f"Tagalog share transcript {report['language']['transcript']['tagalogShare']:.0%} -> "
          f"notes {report['language']['notes']['tagalogShare']:.0%}; "
          f"coverage {c['covered']}/{c['reference']} hand-written notes at 0.5, {cl['covered']} at 0.3; "
          f"{c['matched']}/{c['draft']} draft notes match one at 0.5, {cl['matched']} at 0.3")
    print(f"wrote {out_dir}/draft.md and report.json")


if __name__ == "__main__":
    main()
