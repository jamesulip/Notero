"""Forced `tl` against `auto`, on the same clips, side by side.

Runs the Swift CLI once per language mode per manifest clip, scores each
transcript against its reference with `langscore`, and prints one table:
WER with its S/D/I, the Filipino and English word error rates, the error rate
at code-switch points, decode time and RTF, and -- for `auto` -- what the
decoder thought the language was, window by window.

    ./.venv/bin/python eval/compare_language.py --models models --tier balanced
    ./.venv/bin/python eval/compare_language.py --bin app/.build/release/transcribe --live

Nothing here changes the app's default. That is a decision for whoever reads
the table, and only on real audio: the synthetic fixture is an Indonesian TTS
voice reading a Taglish script, which is the worst possible clip for judging
whether auto-detect wrongly hears Indonesian.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from langscore import score  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
EVAL = REPO / "eval"


def build_cli() -> Path:
    subprocess.run(
        ["swift", "build", "-c", "release", "--product", "transcribe", "--package-path", str(REPO / "app")],
        check=True,
    )
    return REPO / "app" / ".build" / "release" / "transcribe"


def run_arm(binary: Path, audio: Path, ref: Path, language: str, out_dir: Path,
            clip_id: str, models: Path | None, tier: str, live: bool, extra: list[str]) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / f"{clip_id}.json"
    txt_path = out_dir / f"{clip_id}.txt"
    cmd = [str(binary), "--audio", str(audio), "--reference", str(ref), "--language", language,
           "--no-diarize", "--tier", tier, "--out", str(txt_path), "--json", str(json_path)]
    if models:
        cmd += ["--models", str(models)]
    if live:
        cmd += ["--live"]
    cmd += extra
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(f"{clip_id} [{language}] failed with {proc.returncode}")
    report = json.loads(json_path.read_text())
    report["scores"] = score(ref.read_text(), report["transcript"])
    return report


def pct(value: float | None) -> str:
    return "—" if value is None else f"{value * 100:5.1f}%"


def histogram(languages: list[str | None]) -> str:
    counts: dict[str, int] = {}
    for lang in languages:
        if lang:
            counts[lang] = counts.get(lang, 0) + 1
    return " ".join(f"{k}×{v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])) or "—"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", type=Path, default=EVAL / "manifest.json")
    parser.add_argument("--models", type=Path, default=None, help="models directory (default: the app's)")
    parser.add_argument("--tier", default="balanced")
    parser.add_argument("--bin", type=Path, default=None, help="prebuilt transcribe binary")
    parser.add_argument("--arms", default="tl,auto", help="comma-separated language modes")
    parser.add_argument("--live", action="store_true", help="replay through the live path instead of offline")
    parser.add_argument("--out-dir", type=Path, default=EVAL / "out")
    parser.add_argument("--extra", nargs=argparse.REMAINDER, default=[],
                        help="passed through to the CLI (e.g. --extra --pre-roll 0)")
    args = parser.parse_args()

    entries = json.loads(args.manifest.read_text())
    base = args.manifest.parent
    present = [e for e in entries if (base / e["audio"]).exists() and (base / e["ref"]).exists()]
    missing = [e["id"] for e in entries if e not in present]
    if missing:
        print(f"skipping clips with no audio or reference on disk: {', '.join(missing)}", file=sys.stderr)
    if not present:
        print("no clips to score", file=sys.stderr)
        return 1

    binary = args.bin or build_cli()
    arms = [a.strip() for a in args.arms.split(",") if a.strip()]
    mode = "live" if args.live else "offline"

    rows = []
    pooled: dict[str, dict] = {}
    for entry in present:
        for arm in arms:
            report = run_arm(binary, base / entry["audio"], base / entry["ref"], arm,
                             args.out_dir / mode / arm, entry["id"], args.models, args.tier,
                             args.live, args.extra)
            s = report["scores"]
            rows.append((entry["id"], arm, report, s))
            acc = pooled.setdefault(arm, {"sub": 0, "del": 0, "ins": 0, "ref": 0,
                                          "tl_err": 0, "tl_ref": 0, "en_err": 0, "en_ref": 0,
                                          "sw_err": 0, "sw_pos": 0, "decode_ms": 0, "duration_ms": 0})
            acc["sub"] += s["sub"]; acc["del"] += s["del"]; acc["ins"] += s["ins"]; acc["ref"] += s["ref_words"]
            acc["tl_err"] += s["by_class"]["tl"]["errors"]; acc["tl_ref"] += s["by_class"]["tl"]["ref_words"]
            acc["en_err"] += s["by_class"]["en"]["errors"]; acc["en_ref"] += s["by_class"]["en"]["ref_words"]
            acc["sw_err"] += s["code_switch"]["errors"]; acc["sw_pos"] += s["code_switch"]["positions"]
            acc["decode_ms"] += report["decodeMs"]; acc["duration_ms"] += report["durationMs"]

    header = "| clip | mode | WER | S/D/I | ref words | Filipino err | English err | code-switch err | decode | RTF | detected |"
    print(f"\n### `tl` vs `auto` — {mode}, tier {args.tier}\n")
    print(header)
    print("|" + "---|" * (header.count("|") - 1))
    for clip_id, arm, report, s in rows:
        tl = s["by_class"]["tl"]; en = s["by_class"]["en"]; sw = s["code_switch"]
        print(f"| {clip_id} | {arm} | {pct(s['wer'])} | {s['sub']}/{s['del']}/{s['ins']} | {s['ref_words']} "
              f"| {pct(tl['error_rate'])} ({tl['errors']}/{tl['ref_words']}) "
              f"| {pct(en['error_rate'])} ({en['errors']}/{en['ref_words']}) "
              f"| {pct(sw['error_rate'])} ({sw['errors']}/{sw['positions']}; elsewhere {pct(sw['non_switch_error_rate'])}) "
              f"| {report['decodeMs'] / 1000:.1f} s | {report['rtf']:.3f} "
              f"| {histogram(report.get('windowLanguages') or []) if arm == 'auto' else arm} |")
    for arm, acc in pooled.items():
        wer = (acc["sub"] + acc["del"] + acc["ins"]) / acc["ref"] if acc["ref"] else None
        tl_rate = acc["tl_err"] / acc["tl_ref"] if acc["tl_ref"] else None
        en_rate = acc["en_err"] / acc["en_ref"] if acc["en_ref"] else None
        sw_rate = acc["sw_err"] / acc["sw_pos"] if acc["sw_pos"] else None
        rtf = acc["decode_ms"] / acc["duration_ms"] if acc["duration_ms"] else 0
        print(f"| **ALL** | {arm} | {pct(wer)} | {acc['sub']}/{acc['del']}/{acc['ins']} | {acc['ref']} "
              f"| {pct(tl_rate)} ({acc['tl_err']}/{acc['tl_ref']}) | {pct(en_rate)} ({acc['en_err']}/{acc['en_ref']}) "
              f"| {pct(sw_rate)} ({acc['sw_err']}/{acc['sw_pos']}) | {acc['decode_ms'] / 1000:.1f} s | {rtf:.3f} | |")

    summary_path = args.out_dir / f"compare-language-{mode}.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(
        [{"clip": c, "arm": a, "decodeMs": r["decodeMs"], "durationMs": r["durationMs"], "rtf": r["rtf"],
          "windowLanguages": r.get("windowLanguages"), "live": r.get("live"), "scores": s}
         for c, a, r, s in rows], indent=2))
    print(f"\nwrote {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
