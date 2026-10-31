"""The benchmark harness around the statistics: parsing, scoring, summarizing,
comparing, and one end-to-end pass against a fake `transcribe` that needs no
model. The real binary is exercised by the baseline in docs/BENCHMARKS.md."""

import json
import os
import stat
import sys
import textwrap
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import bench_runs as br  # noqa: E402
import benchstats as bs  # noqa: E402

REFERENCE = ("kailangan natin i-send ang report bago mag-meeting bukas "
             "at dapat maayos ang schedule para sa lahat ng team")


# ---- stderr parsing ------------------------------------------------------

OLD_STDERR = """preparing 16 kHz working copy…
audio: 0:56 (906099 samples)
model: openai_whisper-large-v3-v20240930_turbo
speech: 3 regions, 0:56 in 3 windows
  1 window(s) needed a warmer retry
decoded 120 words in 0:06 (RTF 0.118)
WER 0.2891 (28.9%)
peak memory 100 MB, total 0:17
        7.35 real         6.5 user         0.9 sys
           412762112  maximum resident set size
           301989888  peak memory footprint
"""

NEW_STDERR = """speech: 3 regions, 0:56 in 3 windows
  WARNING 2 window(s) never decoded — audio is missing from this transcript
model load 9123 ms (not in the RTF)
memory (one process, not model residency): footprint at exit 123 MB, lifetime peak footprint 456 MB, resident 789 MB; after model load 120 MB (before 80 MB)
neural engine memory owned by this process, NOT in the footprint: 1500 MB now, 1581 MB peak; after model load 1581 MB (before 0 MB)
"""


def test_parse_stderr_old_binary():
    info = br.parse_stderr(OLD_STDERR)
    assert info["regions"] == 3 and info["windows"] == 3
    assert info["retried_windows"] == 1
    assert info["cli_footprint_at_exit_mb"] == 100
    assert info["time_max_rss_bytes"] == 412762112
    assert info["time_peak_footprint_bytes"] == 301989888
    assert "dropped_windows" not in info and "load_ms" not in info


def test_parse_stderr_new_binary():
    info = br.parse_stderr(NEW_STDERR)
    assert info["dropped_windows"] == 2
    assert info["load_ms"] == 9123
    assert info["cli_footprint_at_exit_mb"] == 123
    assert info["cli_lifetime_peak_footprint_mb"] == 456
    assert info["cli_neural_at_exit_mb"] == 1500
    assert info["cli_neural_peak_mb"] == 1581


def test_parse_stderr_guesses_nothing():
    assert br.parse_stderr("nothing useful here") == {}


# ---- scoring -------------------------------------------------------------

def test_score_run_perfect_and_deleted_words():
    perfect = br.score_run(REFERENCE, {"transcript": REFERENCE, "wer": 0.0})
    assert perfect["wer"] == 0 and perfect["hyp_words"] == perfect["ref_words"]
    # i-send splits into two words in score.py, as it does in the CLI scorer.
    assert perfect["ref_words"] == len(REFERENCE.replace("-", " ").split())
    dropped = br.score_run(REFERENCE, {"transcript": "kailangan natin i-send ang report", "wer": 0.8})
    assert dropped["del"] == dropped["ref_words"] - dropped["hyp_words"]
    assert dropped["wer"] == pytest.approx(dropped["del"] / dropped["ref_words"])
    assert dropped["cli_wer"] == 0.8


def test_filler_markers_only_count_what_the_reference_does_not_say():
    hyp = "kailangan natin Thank you so much for watching."
    assert br.filler_markers(REFERENCE, hyp) == ["thank you so much for watching"]
    assert br.filler_markers("thank you so much for watching everyone", hyp) == []
    assert br.filler_markers(REFERENCE, REFERENCE) == []


def test_live_metrics_derives_per_hop_figures():
    report = {"live": {"hops": 4, "droppedHops": 1, "forcedCommits": 2, "unagreedTailCommits": 3,
                       "totalInferMs": 2000, "totalAudioMs": 40000, "peakMemoryMB": 150},
              "commitLatency": {"medianMs": 2100.0, "p95Ms": 3500.0, "maxMs": 4000}}
    live = br.live_metrics(report)
    assert live["dropped_hops"] == 1 and live["forced_commits"] == 2
    assert live["mean_decode_rtf"] == pytest.approx(0.05)
    assert live["infer_ms_per_hop"] == pytest.approx(500)
    assert live["commit_latency_median_ms"] == 2100.0
    assert br.live_metrics({}) == {}


# ---- summarizing ---------------------------------------------------------

def make_record(index, wer, words, *, rtf=0.12, decode_ms=6800, ok=True, live=None,
                footprint=100, collapsed_windows=None):
    if not ok:
        return {"index": index, "ok": False, "returncode": 1, "error": "exit code 1",
                "stderr_tail": "boom"}
    return {
        "index": index, "ok": True, "mode": "offline",
        "report": {"rtf": rtf, "decodeMs": decode_ms, "durationMs": 56631, "model": "m"},
        "score": {"wer": wer, "hyp_words": words, "ref_words": 123, "cli_wer": wer,
                  "filler_markers": ["thanks for watching"] if wer > 0.5 else [],
                  "tl_error_rate": 0.3, "en_error_rate": 0.1},
        "stderr_info": {"cli_footprint_at_exit_mb": footprint, "retried_windows": 1,
                        "time_peak_footprint_bytes": footprint * 2**20},
        "live": live or {}, "memory": {},
    }


META = {"label": "base", "mode": "offline",
        "audio": {"sha256": "aa"}, "reference": {"sha256": "rr", "words": 123}}


def test_summary_counts_the_collapsed_run_and_keeps_the_rest_honest():
    wers = [0.25, 0.26, 0.25, 0.27, 0.26, 0.30, 0.255, 0.57]
    records = [make_record(i + 1, w, 120 if w < 0.5 else 70) for i, w in enumerate(wers)]
    summary = br.summarize_records(records, meta=META)
    assert summary["runs_ok"] == 8 and summary["runs_failed"] == 0
    assert summary["collapse"]["collapsed_runs"] == 1
    assert summary["collapse"]["collapsed_indices"] == [8]
    assert summary["collapse"]["runs_with_filler_markers"] == 1
    assert summary["collapse"]["runs_with_retried_window"] == 8
    assert "runs with invented-filler phrases: 1" in br.format_summary(summary)
    assert summary["collapse"]["rule"] == bs.COLLAPSE_RULE
    # sorted: .25 .25 .255 .26 .26 .27 .30 .57 -> median of the 4th and 5th = 0.26
    assert summary["wer"]["median"] == pytest.approx(0.26)
    assert summary["wer"]["min"] == 0.25 and summary["wer"]["max"] == 0.57
    assert summary["memory"]["meaning"].startswith("PROCESS FOOTPRINT, not model residency")
    assert summary["memory"]["time_peak_footprint_mb"]["median"] == pytest.approx(100)
    assert "whole-file RTF" in summary["rtf_meaning"]


def test_failed_runs_are_reported_and_excluded_from_statistics():
    records = [make_record(1, 0.25, 120), make_record(2, 0, 0, ok=False), make_record(3, 0.27, 120)]
    summary = br.summarize_records(records, meta=META)
    assert summary["runs_attempted"] == 3 and summary["runs_ok"] == 2 and summary["runs_failed"] == 1
    assert summary["failures"][0]["index"] == 2
    assert summary["wer"]["n"] == 2


def test_summary_with_no_successful_run_does_not_crash():
    summary = br.summarize_records([make_record(1, 0, 0, ok=False)], meta=META)
    assert summary["runs_ok"] == 0 and summary["wer"] is None
    assert "no successful runs" in br.format_summary(summary)


def test_live_summary_separates_replay_rtf_from_per_decode_rtf():
    live = {"dropped_hops": 0, "forced_commits": 2, "unagreed_tail_words": 4,
            "mean_decode_rtf": 0.06, "infer_ms_per_hop": 900.0, "hops": 38}
    records = [make_record(i, 0.27, 121, rtf=0.15, live=live) for i in range(1, 4)]
    meta = dict(META, mode="live")
    summary = br.summarize_records(records, meta=meta)
    assert "REPLAY RTF" in summary["rtf_meaning"]
    assert summary["live"]["mean_decode_rtf"]["median"] == pytest.approx(0.06)
    assert summary["rtf"]["median"] == pytest.approx(0.15)
    assert summary["live_series"]["forced_commits"] == [2, 2, 2]


# ---- comparing -----------------------------------------------------------

def arm(label, wers, *, session="s1", which="A", words=None, mode="offline", audio="aa"):
    records = [make_record(i + 1, w, (words or [120] * len(wers))[i]) for i, w in enumerate(wers)]
    meta = dict(META, label=label, mode=mode, audio={"sha256": audio},
                interleave={"id": session, "arm": which} if session else None)
    return br.summarize_records(records, meta=meta)


def test_compare_calls_a_collapse_difference_and_a_wer_difference():
    base = arm("base", [0.25, 0.26, 0.27, 0.25, 0.26, 0.28, 0.57, 0.58])
    cand = arm("cand", [0.25, 0.26, 0.27, 0.25, 0.26, 0.28, 0.27, 0.26], which="B")
    result = br.compare_summaries(base, cand)
    assert result["interleaved"] and result["baseline"]["n"] == 8
    assert result["collapsed"] == {"baseline": 2, "candidate": 0,
                                   "fisher_p": pytest.approx(bs.fisher_exact(2, 6, 0, 8))}
    text = br.format_comparison(result)
    assert "WER" in text and "collapsed runs" in text and "VERDICT" in text
    assert bs.COLLAPSE_RULE in text


def test_compare_below_minimum_n_gives_no_verdict_whatever_the_difference():
    base = arm("base", [0.25] * 7)
    cand = arm("cand", [0.60] * 7, which="B")
    result = br.compare_summaries(base, cand)
    assert result["verdict"].startswith("NO VERDICT")


def test_compare_flags_a_uniformly_bad_candidate_against_the_baseline_level():
    base = arm("base", [0.25, 0.26, 0.25, 0.27, 0.26, 0.25, 0.26, 0.27])
    cand = arm("cand", [0.60, 0.61, 0.62, 0.60, 0.59, 0.61, 0.60, 0.62], which="B")
    result = br.compare_summaries(base, cand)
    assert result["collapsed"]["candidate"] == 0          # not collapsed against itself
    assert result["collapsed_vs_baseline_threshold"]["candidate"] == 8   # but against the baseline
    assert "SIGNIFICANT" in result["verdict"].split("collapsed")[0]


def test_compare_requires_interleaving_unless_allowed():
    base = arm("base", [0.25] * 8, session=None)
    cand = arm("cand", [0.30] * 8, session=None, which="B")
    assert br.compare_summaries(base, cand)["verdict"].startswith("NO VERDICT: the two arms were not")
    allowed = br.compare_summaries(base, cand, allow_non_interleaved=True)
    assert "NOT INTERLEAVED" in allowed["verdict"]
    # Two sessions are not one interleave.
    other = arm("cand", [0.30] * 8, session="s2", which="B")
    assert not br.compare_summaries(arm("base", [0.25] * 8, session="s1"), other)["interleaved"]


def test_compare_refuses_unlike_inputs():
    base = arm("base", [0.25] * 8)
    with pytest.raises(ValueError, match="audio"):
        br.compare_summaries(base, arm("cand", [0.25] * 8, which="B", audio="zz"))
    with pytest.raises(ValueError, match="mode"):
        br.compare_summaries(base, arm("cand", [0.25] * 8, which="B", mode="live"))


def test_compare_live_includes_live_rows():
    live_a = {"dropped_hops": 0, "forced_commits": 6, "unagreed_tail_words": 9,
              "mean_decode_rtf": 0.06, "infer_ms_per_hop": 900.0}
    live_b = dict(live_a, forced_commits=2)
    base = br.summarize_records([make_record(i, 0.27, 120, live=live_a) for i in range(1, 9)],
                                meta=dict(META, mode="live", interleave={"id": "s", "arm": "A"}))
    cand = br.summarize_records([make_record(i, 0.27, 120, live=live_b) for i in range(1, 9)],
                                meta=dict(META, mode="live", interleave={"id": "s", "arm": "B"}))
    result = br.compare_summaries(base, cand)
    row = next(r for r in result["rows"] if r["metric"] == "forced commits")
    assert row["baseline"]["median"] == 6 and row["candidate"]["median"] == 2
    assert row["diff"] == -4
    assert "forced commits" in br.format_comparison(result)


# ---- end to end against a fake binary ------------------------------------

FAKE = textwrap.dedent('''\
    #!{python}
    import json, sys
    from pathlib import Path
    args = sys.argv[1:]
    def val(flag):
        return args[args.index(flag) + 1]
    counter = Path(__file__).with_suffix(".count")
    n = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(n))
    ref = Path(val("--reference")).read_text()
    words = ref.split()
    # {label}: every {every}th call drops its second half, like a collapsed window.
    if n % {every} == 0:
        words = words[: len(words) // 2]
    live = "--live" in args
    report = {{"audio": val("--audio"), "mode": "live" if live else "offline", "model": "fake-model",
              "language": "tl", "windowLanguages": [], "durationMs": 56000, "decodeMs": 6000 + n,
              "rtf": (6000 + n) / 56000, "wordCount": len(words), "transcript": " ".join(words),
              "words": [], "wer": None}}
    if live:
        report["live"] = {{"hops": 10, "droppedHops": 0, "forcedCommits": {forced},
                           "unagreedTailCommits": 1, "totalInferMs": 5000, "totalAudioMs": 100000,
                           "peakMemoryMB": 90}}
    Path(val("--json")).write_text(json.dumps(report))
    print("peak memory 64 MB, total 0:07", file=sys.stderr)
''')


def fake_binary(directory: Path, name: str, *, every: int, forced: int = 2) -> Path:
    path = directory / name
    path.write_text(FAKE.format(python=sys.executable, every=every, forced=forced, label=name))
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


@pytest.fixture
def clip(tmp_path):
    audio = tmp_path / "clip.wav"
    audio.write_bytes(b"RIFFfake")
    ref = tmp_path / "ref.txt"
    ref.write_text(REFERENCE)
    return audio, ref


def test_run_interleaves_two_binaries_and_compares(tmp_path, clip):
    audio, ref = clip
    base = fake_binary(tmp_path, "base", every=3)     # collapses on calls 3, 6
    cand = fake_binary(tmp_path, "cand", every=1000)  # never collapses
    out = tmp_path / "ab"
    code = br.main(["run", "--interleave", str(base), str(cand), "--labels", "base", "cand",
                    "--audio", str(audio), "--ref", str(ref), "--runs", "8",
                    "--out-dir", str(out), "--no-lock"])
    assert code == 0
    timeline = json.loads((out / "interleave.json").read_text())["timeline"]
    assert [step["arm"] for step in timeline] == list("ABABABABABABABAB")
    assert len(list((out / "A").glob("run-*.json"))) > 0
    for arm_dir in ("A", "B"):
        assert len(list((out / arm_dir).glob("run-[0-9][0-9].json"))) == 8
        assert len(list((out / arm_dir).glob("run-[0-9][0-9].stderr.txt"))) == 8
    summary_a = json.loads((out / "A" / "summary.json").read_text())
    summary_b = json.loads((out / "B" / "summary.json").read_text())
    assert summary_a["runs_ok"] == 8 and summary_b["runs_ok"] == 8
    assert summary_a["collapse"]["collapsed_runs"] == 2   # calls 3 and 6
    assert summary_b["collapse"]["collapsed_runs"] == 0
    assert summary_a["interleave"]["id"] == summary_b["interleave"]["id"]
    assert summary_a["binary"]["sha256"] != summary_b["binary"]["sha256"]
    assert summary_a["lock_used"] is False

    result = br.compare_summaries(summary_a, summary_b)
    assert result["interleaved"] and result["collapsed"]["baseline"] == 2

    # The compare subcommand works on the saved files and writes JSON.
    out_json = tmp_path / "cmp.json"
    assert br.main(["compare", str(out / "A" / "summary.json"), str(out / "B" / "summary.json"),
                    "--json", str(out_json)]) == 0
    assert json.loads(out_json.read_text())["collapsed"]["candidate"] == 0


def test_run_single_binary_live_mode_records_live_counters(tmp_path, clip):
    audio, ref = clip
    binary = fake_binary(tmp_path, "solo", every=1000, forced=5)
    out = tmp_path / "live"
    assert br.main(["run", "--bin", str(binary), "--audio", str(audio), "--ref", str(ref),
                    "--mode", "live", "--runs", "3", "--out-dir", str(out), "--no-lock"]) == 0
    summary = json.loads((out / "summary.json").read_text())
    assert summary["mode"] == "live" and summary["interleave"] is None
    assert summary["live"]["forced_commits"]["median"] == 5
    assert summary["live"]["mean_decode_rtf"]["median"] == pytest.approx(0.05)
    assert summary["memory"]["cli_footprint_at_exit_mb"]["median"] == 64


def test_run_refuses_to_overwrite_an_existing_run_directory(tmp_path, clip):
    audio, ref = clip
    binary = fake_binary(tmp_path, "solo", every=1000)
    args = ["run", "--bin", str(binary), "--audio", str(audio), "--ref", str(ref),
            "--runs", "1", "--out-dir", str(tmp_path / "o"), "--no-lock"]
    assert br.main(args) == 0
    assert br.main(args) == 2


def test_a_crashing_binary_is_a_reported_failure_not_a_lost_run(tmp_path, clip):
    audio, ref = clip
    crash = tmp_path / "crash"
    crash.write_text("#!/bin/sh\necho 'model exploded' >&2\nexit 1\n")
    crash.chmod(0o755)
    out = tmp_path / "c"
    assert br.main(["run", "--bin", str(crash), "--audio", str(audio), "--ref", str(ref),
                    "--runs", "2", "--out-dir", str(out), "--no-lock"]) == 1
    summary = json.loads((out / "summary.json").read_text())
    assert summary["runs_failed"] == 2 and summary["runs_ok"] == 0
    assert "model exploded" in summary["failures"][0]["stderr_tail"]


def test_summarize_rebuilds_the_summary_from_run_files(tmp_path, clip):
    audio, ref = clip
    binary = fake_binary(tmp_path, "solo", every=1000)
    out = tmp_path / "s"
    br.main(["run", "--bin", str(binary), "--audio", str(audio), "--ref", str(ref),
             "--runs", "3", "--out-dir", str(out), "--no-lock"])
    original = json.loads((out / "summary.json").read_text())
    (out / "summary.json").unlink()
    assert br.main(["summarize", str(out)]) == 0
    rebuilt = json.loads((out / "summary.json").read_text())
    assert rebuilt["wer"] == original["wer"] and rebuilt["runs_ok"] == 3


def test_lock_script_is_used_when_present(tmp_path):
    cmd = br.build_command(Path("/b"), Path("/a.wav"), Path("/r.txt"), Path("/o.json"),
                           mode="live-realtime", extra=["--hop", "1000"], use_lock=True,
                           use_time=True)
    assert cmd[0] == str(br.LOCK_SCRIPT) and cmd[1:3] == ["/usr/bin/time", "-l"]
    assert "--live" in cmd and "--realtime" in cmd and cmd[-2:] == ["--hop", "1000"]
    assert "--no-diarize" in cmd
    plain = br.build_command(Path("/b"), Path("/a.wav"), Path("/r.txt"), Path("/o.json"),
                             mode="offline", extra=[], use_lock=False, use_time=False)
    assert plain[0] == "/b" and "--live" not in plain


def test_parse_stderr_reads_both_wordings_of_the_retry_line():
    # Builds before 2026-11-01 said "a warmer retry"; the lead-in retry made that
    # wrong, and the line now names what a retry is.
    new = "  2 window(s) needed a retry (a lead-in of silence, wider audio or half the window)\n"
    assert br.parse_stderr(new)["retried_windows"] == 2
    assert br.parse_stderr("  1 window(s) needed a warmer retry\n")["retried_windows"] == 1
