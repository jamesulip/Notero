"""The regression harness: planning, builds, the machine record, the DER series, the
whole comparison end to end against a FAKE `transcribe` (no model, no Mac needed), the
second-session confirmation, baseline drift and the determinism check.

Everything here runs on Linux: no `/usr/bin/time -l`, no macOS-only command without a
guard, and the platform-dependent pieces are exercised with `sys.platform` forced.
A passing test is not evidence by itself, so the ones that matter assert their own
precondition (counts of runs, of lock holds) and were each shown to FAIL against the old
behaviour (see the notes in docs/BENCHMARKS.md).
"""

import json
import os
import stat
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import bench_runs as br  # noqa: E402
import benchstats as bs  # noqa: E402
import regress as rg  # noqa: E402
import regresslib as rl  # noqa: E402

REFERENCE = ("kailangan natin i-send ang report bago mag-meeting bukas "
             "at dapat maayos ang schedule para sa lahat ng team")
REF_WORDS = len(REFERENCE.split()) + 2          # score.py splits the two hyphenated words

# --------------------------------------------------------------------------
# A fake `transcribe`
# --------------------------------------------------------------------------

FAKE = textwrap.dedent('''\
    #!{python}
    import json, os, sys
    from pathlib import Path
    args = sys.argv[1:]
    me = Path(__file__)
    config = json.loads(me.with_suffix(".json").read_text())
    counter = me.with_suffix(".count")
    n = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(n))
    def val(flag):
        return args[args.index(flag) + 1]
    if config.get("fail_every") and n % config["fail_every"] == 0:
        print("simulated failure", file=sys.stderr)
        sys.exit(3)

    if "--reference" not in args:
        me.with_suffix(".args").write_text(" ".join(args))
        # diarization series: print the reference turns, shifted, as raw spans
        audio = Path(val("--audio"))
        rttm = audio.with_suffix(".rttm").read_text().splitlines()
        shift = config.get("span_shift_s", 0.0)
        print("speech: 1 regions, 0:30 in 1 windows", file=sys.stderr)
        for line in rttm:
            f = line.split()
            start, dur, spk = float(f[3]) + shift, float(f[4]), f[7]
            print("  span %7.2f-%7.2f %s q=0.90" % (start, start + dur, spk), file=sys.stderr)
        if "--out" in args:
            Path(val("--out")).write_text("x")
        sys.exit(0)

    words = Path(val("--reference")).read_text().split()
    if config.get("collapse_every") and n % config["collapse_every"] == 0:
        words = words[: len(words) // 2]
    if config.get("vary_after") is not None:      # nondeterministic: a different word at a position
        words = list(words)
        words[config["vary_after"]] = "w%d" % (n % 3)
    live = "--live" in args
    rtf = config.get("rtf", 0.1) * (1 + 0.001 * (n % 5))
    report = {{"audio": val("--audio"), "mode": "live" if live else "offline", "model": "fake-model",
              "language": "tl", "windowLanguages": ["tl", "tl"], "durationMs": 56000,
              "windows": [{{"startMs": 0, "endMs": 28000}}, {{"startMs": 28000, "endMs": 56000}}],
              "decodeMs": int(rtf * 56000), "loadMs": 9000, "rtf": rtf, "wordCount": len(words),
              "transcript": " ".join(words),
              "words": [{{"text": w, "startMs": i * 1000, "endMs": i * 1000 + 900}} for i, w in enumerate(words)],
              "wer": None}}
    if live:
        report["live"] = {{"hops": 10, "droppedHops": config.get("dropped", 0), "forcedCommits": config.get("forced", 2),
                           "unagreedTailCommits": 1, "totalInferMs": 5000, "totalAudioMs": 100000,
                           "peakMemoryMB": 90}}
        if config.get("commit_latency"):
            report["commitLatency"] = {{"medianMs": config["commit_latency"], "p95Ms": 9000, "maxMs": 9500}}
    Path(val("--json")).write_text(json.dumps(report))
    print("peak memory 64 MB, total 0:07", file=sys.stderr)
''')


def fake_binary(directory: Path, name: str, **config) -> Path:
    path = directory / name
    # the config goes into the file too: two fakes with different behaviour are different binaries
    path.write_text(FAKE.format(python=sys.executable) + f"# {name} {json.dumps(config, sort_keys=True)}\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    path.with_suffix(".json").write_text(json.dumps(config))
    return path


RTTM = ("SPEAKER ms-a 1 0.000 8.000 <NA> <NA> S1 <NA> <NA>\n"
        "SPEAKER ms-a 1 8.000 8.000 <NA> <NA> S2 <NA> <NA>\n"
        "SPEAKER ms-a 1 16.000 8.000 <NA> <NA> S1 <NA> <NA>\n")


@pytest.fixture
def world(tmp_path, monkeypatch):
    """Fixtures on disk, the fixture resolver replaced, no bench lock, a private scratch."""
    audio = tmp_path / "clip.wav"
    audio.write_bytes(b"RIFFfake")
    ref = tmp_path / "ref.txt"
    ref.write_text(REFERENCE)
    for name in ("ms-a", "ms-b"):
        (tmp_path / f"{name}.wav").write_bytes(b"RIFFfake")
        (tmp_path / f"{name}.rttm").write_text(RTTM.replace("ms-a", name))

    def collect(args, series_id, definition, scratch):
        if definition["kind"] == "der":
            return {"files": {f"ms-{i}": {"audio": str(tmp_path / f"ms-{i}.wav"),
                                          "rttm": str(tmp_path / f"ms-{i}.rttm"),
                                          "sha256": "dd", "matches_manifest": True}
                              for i in ("a", "b")}}
        return {"audio": str(audio), "reference": str(ref), "sha256": "aa", "id": "synthetic-taglish",
                "synthetic": True, "matches_manifest": True, "reference_sha256": "rr"}

    monkeypatch.setattr(rg, "collect_fixtures", collect)
    monkeypatch.setattr(br, "LOCK_SCRIPT", tmp_path / "no-such-lock.sh")
    monkeypatch.setenv("NOTERO_REGRESS_SCRATCH", str(tmp_path / "scratch"))
    return tmp_path


def run_compare(world, base, cand, *extra, out="out"):
    out_dir = world / out
    code = rg.main(["--base", str(base), "--cand", str(cand), "--only", "offline-synthetic",
                    "live-synthetic", "der-quick", "--runs", "8", "--out-dir", str(out_dir),
                    "--no-lock", *extra])
    return code, out_dir, json.loads((out_dir / "report.json").read_text())


# --------------------------------------------------------------------------
# Planning, parsing, the machine
# --------------------------------------------------------------------------

def test_plan_batches_cut_on_whole_abba_blocks_and_cover_the_schedule():
    schedule = bs.interleave_schedule(8, "abba")
    batches = rg.plan_batches(schedule, est_s=16, hold_seconds=240)
    assert [len(b) for b in batches] == [12, 4]                    # 240 // 16 = 15 -> 12
    assert [arm for batch in batches for arm in batch] == schedule
    assert all(batch.count("A") == batch.count("B") for batch in batches)
    # a long run still gets one block per hold, never less than a block
    assert [len(b) for b in rg.plan_batches(schedule, est_s=500, hold_seconds=240)] == [4, 4, 4, 4]
    with pytest.raises(ValueError):
        rg.plan_batches(schedule, est_s=0, hold_seconds=240)


def test_der_chunks_cut_on_fixture_boundaries_and_keep_both_arms_equal():
    schedule = bs.interleave_schedule(3, "abab")                    # A B A B A B: 6 runs per fixture
    items = [(fixture, arm) for fixture in "xyzuvwt" for arm in schedule]
    chunks = rg.plan_der_chunks(items, len(schedule), est_s=25, hold_seconds=240)
    assert [len(c) for c in chunks] == [6, 6, 6, 6, 6, 6, 6]       # 240 // 25 = 9 -> 6: one fixture per hold
    assert [i for c in chunks for i in c] == items
    for chunk in chunks:
        assert len({fixture for fixture, _ in chunk}) == 1
        assert [arm for _, arm in chunk].count("A") == [arm for _, arm in chunk].count("B")
    quick = [(f, arm) for f in "xy" for arm in bs.interleave_schedule(2, "abba")]      # 4 runs per fixture
    assert [len(c) for c in rg.plan_der_chunks(quick, 4, est_s=25, hold_seconds=240)] == [8]   # one 8-run hold
    assert [len(c) for c in rg.plan_der_chunks(quick, 4, est_s=200, hold_seconds=240)] == [4, 4]
    with pytest.raises(ValueError):
        rg.plan_der_chunks(quick, 0, est_s=25, hold_seconds=240)


VM_STAT = """Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                    79211.
Pages active:                                 242401.
Pages inactive:                               238332.
Pages wired down:                              98314.
Pages occupied by compressor:                  50012.
Pageouts:                                     225442.
"""


def test_vm_stat_and_memory_pressure_parsing():
    parsed = rg.parse_vm_stat(VM_STAT)
    assert parsed["page_size"] == 16384 and parsed["free_pages"] == 79211
    assert parsed["pageouts"] == 225442 and parsed["compressed_pages"] == 50012
    assert rg.parse_memory_pressure("The system has 17179869184\nSystem-wide memory free percentage: 55%\n") == 55
    assert rg.parse_memory_pressure("nothing here") is None


def test_system_snapshot_on_darwin_reads_vm_stat_and_memory_pressure(monkeypatch):
    outputs = {"vm_stat": VM_STAT, "memory_pressure": "System-wide memory free percentage: 41%\n",
               "uptime": " 3:00  up 1 day, load averages: 1.00 2.00 3.00\n"}
    monkeypatch.setattr(rg, "_run_text", lambda cmd, timeout=20: outputs.get(cmd[0]))
    snap = rg.system_snapshot("darwin")
    assert snap["memory"]["pageouts"] == 225442 and snap["memory"]["free_percentage"] == 41
    assert "load averages" in snap["uptime"]


def test_system_snapshot_on_linux_has_load_but_asks_for_no_macos_command(monkeypatch):
    asked = []
    monkeypatch.setattr(rg, "_run_text", lambda cmd, timeout=20: asked.append(cmd[0]) or None)
    snap = rg.system_snapshot("linux")
    assert "memory" not in snap
    assert "vm_stat" not in asked and "memory_pressure" not in asked   # macOS-only: never asked for


def test_system_summary_reports_the_pageout_delta():
    before = {"memory": {"pageouts": 100}}
    after = {"memory": {"pageouts": 160}}
    assert rg.system_summary(before, after)["pageouts_delta"] == 60
    assert "pageouts_delta" not in rg.system_summary({}, {})


SPANS = """speech: 1 regions, 0:30 in 1 windows
  span    0.00-   8.00 S1 q=0.91
  span    8.00-  16.25 S2 q=-1.00
  decoded 120 words
"""


def test_parse_spans_reads_the_debug_lines_only():
    spans = rg.parse_spans(SPANS)
    assert [(s.start, s.end, s.speaker) for s in spans] == [(0.0, 8.0, "S1"), (8.0, 16.25, "S2")]
    assert rg.parse_spans("nothing") == []


def der_rows(*values, speakers=2):
    return [{"ok": True, "der": v, "hyp_speakers": speakers} for v in values]


def test_analyze_der_exact_change_no_change_and_noise():
    result = rg.analyze_der(
        {"same": der_rows(0.1, 0.1), "worse": der_rows(0.1, 0.1), "tiny": der_rows(0.100, 0.100),
         "noisy": der_rows(0.10, 0.20, 0.30), "better": der_rows(0.30, 0.30)},
        {"same": der_rows(0.1, 0.1), "worse": der_rows(0.25, 0.25), "tiny": der_rows(0.105, 0.105),
         "noisy": der_rows(0.30, 0.05, 0.31), "better": der_rows(0.10, 0.10)})
    by_id = {r["id"]: r for r in result["fixtures"]}
    assert by_id["same"]["status"] == "no change" and by_id["same"]["deterministic"]
    assert by_id["worse"]["changed"] and by_id["worse"]["worse"] and "exact" in by_id["worse"]["status"]
    assert "floor" in by_id["tiny"]["status"] and not by_id["tiny"]["changed"]
    assert not by_id["noisy"]["changed"] and "descriptive" in by_id["noisy"]["status"]
    assert by_id["better"]["changed"] and not by_id["better"]["worse"]
    assert result["changed"] == ["worse", "better"]


def test_analyze_der_does_not_flag_noise_that_happens_to_point_one_way():
    # Both arms vary run to run (so it is not an exact comparison) and every round happens to
    # be higher in the candidate. With two or three rounds that is what noise does often: by
    # simulation, an 18-38% false "CHANGED" rate per fixture whose spread is a few points.
    result = rg.analyze_der({"x": der_rows(0.10, 0.12, 0.11)}, {"x": der_rows(0.20, 0.24, 0.21)})
    row = result["fixtures"][0]
    assert row["diff"] == pytest.approx(0.10) and row["deterministic"] is False
    assert not row["changed"] and "descriptive only" in row["status"] and result["changed"] == []


def test_analyze_der_handles_a_side_with_no_successful_run():
    result = rg.analyze_der({"x": [{"ok": False}]}, {"x": der_rows(0.1)})
    assert "no successful runs" in result["fixtures"][0]["status"]


# --------------------------------------------------------------------------
# Resolving a build
# --------------------------------------------------------------------------

def make_repo(tmp_path):
    repo = tmp_path / "repo"
    (repo / "app").mkdir(parents=True)
    (repo / "app" / "Package.swift").write_text("// v1\n")
    for cmd in (["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"],
                ["add", "."], ["commit", "-q", "-m", "first build"]):
        subprocess.run(["git", "-C", str(repo), *cmd], check=True, capture_output=True)
    sha = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                         capture_output=True, text=True).stdout.strip()
    return repo, sha


class FakeSwift:
    """Stands in for `swift build`: leaves an executable where the build would."""
    def __init__(self):
        self.calls = []

    def __call__(self, cmd, cwd=None, stdout=None, stderr=None):
        self.calls.append((cmd, Path(cwd), (Path(cwd) / "Package.swift").read_text()))
        binary = Path(cwd) / ".build" / "release" / "transcribe"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/sh\n")
        binary.chmod(0o755)
        return subprocess.CompletedProcess(cmd, 0)


def test_resolve_binary_builds_the_committed_tree_not_the_working_copy(tmp_path, monkeypatch):
    repo, sha = make_repo(tmp_path)
    (repo / "app" / "Package.swift").write_text("// v2, uncommitted\n")     # the working copy moved on
    monkeypatch.setattr(rg.sys, "platform", "darwin")
    swift = FakeSwift()
    info = rg.resolve_binary(sha[:7], scratch=tmp_path / "scratch", repo=repo, runner=swift)
    assert info["built"] and info["commit"] == sha and "first build" in info["label"]
    assert len(swift.calls) == 1
    cmd, cwd, package = swift.calls[0]
    assert cmd == ["swift", "build", "-c", "release", "--product", "transcribe"]
    assert package == "// v1\n"                        # git archive: the commit, not the working tree
    assert str(cwd).startswith(str(tmp_path / "scratch"))          # outside the repository
    assert not str(cwd).startswith(str(repo))
    again = rg.resolve_binary(sha, scratch=tmp_path / "scratch", repo=repo, runner=swift)
    assert not again["built"] and len(swift.calls) == 1            # cached by full commit sha


def test_resolve_binary_worktree_is_built_from_the_working_copy_and_keyed_by_content(tmp_path, monkeypatch):
    repo, _ = make_repo(tmp_path)
    (repo / "app" / "Package.swift").write_text("// working copy\n")
    monkeypatch.setattr(rg.sys, "platform", "darwin")
    swift = FakeSwift()
    first = rg.resolve_binary("WORKTREE", scratch=tmp_path / "scratch", repo=repo, runner=swift)
    assert swift.calls[0][2] == "// working copy\n" and "WORKTREE" in first["label"]
    (repo / "app" / "Package.swift").write_text("// edited again\n")
    rg.resolve_binary("WORKTREE", scratch=tmp_path / "scratch", repo=repo, runner=swift)
    assert len(swift.calls) == 2                       # a changed working copy is a new build


def test_resolve_binary_accepts_an_executable_and_rejects_nonsense(tmp_path):
    binary = fake_binary(tmp_path, "tool")
    info = rg.resolve_binary(str(binary), scratch=tmp_path / "s", repo=tmp_path)
    assert info["path"] == str(binary.resolve()) and not info["built"]
    repo, _ = make_repo(tmp_path)
    with pytest.raises(RuntimeError, match="neither an executable file nor a git revision"):
        rg.resolve_binary("no-such-rev", scratch=tmp_path / "s", repo=repo)
    plain = tmp_path / "plain.txt"
    plain.write_text("x")
    with pytest.raises(RuntimeError, match="not executable"):
        rg.resolve_binary(str(plain), scratch=tmp_path / "s", repo=repo)


def test_resolve_binary_cannot_build_off_macos_and_says_so(tmp_path, monkeypatch):
    repo, sha = make_repo(tmp_path)
    monkeypatch.setattr(rg.sys, "platform", "linux")
    with pytest.raises(RuntimeError, match="needs macOS"):
        rg.resolve_binary(sha, scratch=tmp_path / "scratch", repo=repo, runner=FakeSwift())
    with pytest.raises(RuntimeError, match="no-build"):
        rg.resolve_binary(sha, scratch=tmp_path / "scratch", repo=repo, build=False)


def test_default_scratch_is_the_shared_tmp_directory_not_the_per_user_one(monkeypatch):
    monkeypatch.delenv("NOTERO_REGRESS_SCRATCH", raising=False)
    # On macOS the system temp directory is /var/folders/...; a build cache there moves
    # with $TMPDIR and rebuilds for nothing.
    assert rg.default_scratch() == Path("/tmp/notero-regress")
    monkeypatch.setenv("NOTERO_REGRESS_SCRATCH", "/somewhere/else")
    assert rg.default_scratch() == Path("/somewhere/else")


# --------------------------------------------------------------------------
# The whole comparison, against a fake binary
# --------------------------------------------------------------------------

def test_a_vs_a_flags_nothing_and_says_it_is_an_a_a(world):
    tool = fake_binary(world, "tool")
    code, out, report = run_compare(world, tool, tool)
    assert code == 0
    assert report["decision"]["flagged"] == []
    assert any("SAME binary" in w for w in report["warnings"])
    assert (out / "report.md").is_file() and (out / "plan.json").is_file()
    ids = [s["id"] for s in report["series"]]
    assert ids == ["offline-synthetic", "live-synthetic"] and report["der"]["series"] == "der-quick"
    for series in report["series"]:
        assert series["arms"]["A"]["n"] == 8 and series["arms"]["B"]["n"] == 8     # the precondition
        assert series["collapse"]["A"]["count"] == 0 and series["collapse"]["B"]["count"] == 0
    assert report["der"]["changed"] == []
    text = (out / "report.md").read_text()
    assert "A/A" in text and "Decision rule" in text and bs.COLLAPSE_RULE in text
    assert "Determinism" in text and "byte-identical" in text


def test_a_regression_is_suspected_with_one_collapse_rule_and_der_change(world):
    base = fake_binary(world, "base", collapse_every=1)      # every run loses half its words
    cand = fake_binary(world, "cand", span_shift_s=5.0)      # diarization shifted: DER up
    code, out, report = run_compare(world, base, cand)
    assert code == 0
    by_key = {(t["series"], t["key"]): t for s in report["series"] for t in s["tests"]}
    wer = by_key[("offline-synthetic", "wer")]
    assert wer["status"] == "improvement"                     # base is the broken one: cand is better
    collapsed = by_key[("offline-synthetic", "collapsed")]
    assert collapsed["a"]["count"] == 8 and collapsed["b"]["count"] == 0
    assert collapsed["status"] == "improvement" and collapsed["p"] < 0.001
    der = {r["id"]: r for r in report["der"]["fixtures"]}
    assert all(r["changed"] and r["worse"] and r["deterministic"] for r in der.values())
    headline = report["decision"]["headline"]
    assert "SUSPECTED IMPROVEMENT" in headline and "DER HIGHER (worse)" in headline
    assert "CONFIRMED" not in headline
    # the one collapse rule is stated in the report, with the level it judged both arms by
    text = (out / "report.md").read_text()
    assert "Collapsed runs (level " in text and "word floor" in text
    assert "Why: A#1 wer+words" in text                                     # the reason per collapsed run


def test_reverse_the_arms_and_it_is_a_regression(world):
    good = fake_binary(world, "good")
    broken = fake_binary(world, "broken", collapse_every=1)
    _, _, report = run_compare(world, good, broken)
    by_key = {(t["series"], t["key"]): t for s in report["series"] for t in s["tests"]}
    assert by_key[("offline-synthetic", "wer")]["status"] == "regression"
    assert by_key[("live-synthetic", "wer")]["status"] == "regression"
    assert "SUSPECTED REGRESSION" in report["decision"]["headline"]


def set_loads(directory: Path, value: float) -> int:
    """Rewrite the load average recorded at launch in every stored run of a session:
    the worker runs in its own process, so a test cannot fake the machine's load, but it
    can replay the same runs under a different recorded load with `reanalyze`."""
    count = 0
    for path in directory.rglob("run-*.json"):
        if path.name.endswith(".report.json"):
            continue
        record = json.loads(path.read_text())
        record["loadavg_1m_at_launch"] = value
        path.write_text(json.dumps(record))
        count += 1
    return count


def rtf_test(report):
    return next(t for s in report["series"] if s["id"] == "offline-synthetic"
                for t in s["tests"] if t["key"] == "rtf")


def test_timing_difference_is_indicative_when_the_load_was_not_quiet_and_flagged_when_it_was(world):
    slow = fake_binary(world, "slow", rtf=0.2)
    fast = fake_binary(world, "fast", rtf=0.1)
    _, out, _ = run_compare(world, fast, slow)

    assert set_loads(out, 6.0) == 40          # the precondition: 16 offline + 16 live + 8 DER runs rewritten
    assert rg.main(["reanalyze", str(out)]) == 0
    busy = json.loads((out / "report.json").read_text())
    rtf = rtf_test(busy)
    assert rtf["p_holm"] < bs.ALPHA and rtf["floor_met"]            # a real, large difference ...
    assert rtf["status"] == "indicative"                            # ... not believed on a busy machine
    assert "busy" in rtf["load_reason"] and rtf["would_be"] == "regression"
    assert "INDICATIVE ONLY" in busy["decision"]["headline"]
    assert "SUSPECTED REGRESSION in offline-synthetic:RTF" not in busy["decision"]["headline"]
    assert "load average (1 min) at launch" in (out / "report.md").read_text()
    assert "NOT reliable" in (out / "report.md").read_text()

    set_loads(out, 0.4)                                             # the same runs, recorded quiet
    assert rg.main(["reanalyze", str(out)]) == 0
    quiet = json.loads((out / "report.json").read_text())
    assert rtf_test(quiet)["status"] == "regression"
    assert "SUSPECTED REGRESSION" in quiet["decision"]["headline"]


def test_timing_is_indicative_when_the_load_record_is_missing(world):
    slow = fake_binary(world, "slow", rtf=0.2)
    fast = fake_binary(world, "fast", rtf=0.1)
    _, out, _ = run_compare(world, fast, slow)
    for path in out.rglob("run-*.json"):
        if not path.name.endswith(".report.json"):
            record = json.loads(path.read_text())
            record.pop("loadavg_1m_at_launch", None)
            path.write_text(json.dumps(record))
    assert rg.main(["reanalyze", str(out)]) == 0
    rtf = rtf_test(json.loads((out / "report.json").read_text()))
    assert rtf["status"] == "indicative" and "not recorded" in rtf["load_reason"]


def test_the_bench_lock_is_taken_once_per_batch_not_once_per_run(world, monkeypatch):
    lock = world / "fake-lock.sh"
    log = world / "lock.log"
    lock.write_text(f'#!/bin/bash\necho "hold $$" >> {log}\n"$@"\n')
    lock.chmod(0o755)
    monkeypatch.setattr(br, "LOCK_SCRIPT", lock)
    tool = fake_binary(world, "tool")
    out_dir = world / "locked"
    code = rg.main(["--base", str(tool), "--cand", str(tool), "--only", "offline-synthetic",
                    "--runs", "8", "--out-dir", str(out_dir)])
    assert code == 0
    holds = log.read_text().splitlines()
    runs = len(list((out_dir / "offline-synthetic" / "A").glob("run-*.json"))) \
        + len(list((out_dir / "offline-synthetic" / "B").glob("run-*.json")))
    assert runs == 32            # 16 runs, each leaving run-NN.json and run-NN.report.json
    assert len(holds) == 2       # 16 runs in 2 lock holds [12, 4], where one ticket per run was 16
    assert json.loads((out_dir / "report.json").read_text())["lock_used"] is True


def test_the_report_says_when_no_lock_was_used(world):
    tool = fake_binary(world, "tool")
    _, out, report = run_compare(world, tool, tool)
    assert report["lock_used"] is False
    assert any("bench lock was not used" in w for w in report["warnings"])
    assert "NOT USED" in (out / "report.md").read_text()


def test_dry_run_prints_the_plan_and_runs_nothing(world, capsys):
    tool = fake_binary(world, "tool")
    code = rg.main(["--base", str(tool), "--cand", str(tool), "--only", "offline-synthetic",
                    "--out-dir", str(world / "dry"), "--no-lock", "--dry-run"])
    assert code == 0
    assert "offline-synthetic: asr 8 runs per arm in 2 lock holds [12, 4]" in capsys.readouterr().out
    assert not tool.with_suffix(".count").exists()


def test_a_series_whose_fixture_is_missing_is_skipped_and_said_so(world, monkeypatch, capsys):
    real = rg.collect_fixtures

    def picky(args, series_id, definition, scratch):
        if series_id == "live-synthetic":
            raise rg.fx.FixtureUnavailable("FLEURS not found: nothing there (optional fixture)")
        return real(args, series_id, definition, scratch)

    monkeypatch.setattr(rg, "collect_fixtures", picky)
    tool = fake_binary(world, "tool")
    _, out, report = run_compare(world, tool, tool)
    assert [s["id"] for s in report["series"]] == ["offline-synthetic"]
    assert any("live-synthetic" in note for note in report["skipped"])
    assert "skipped: live-synthetic" in (out / "report.md").read_text()


def test_reanalyze_rebuilds_the_same_report_from_the_stored_runs(world):
    base = fake_binary(world, "base", collapse_every=1)
    cand = fake_binary(world, "cand")
    _, out, report = run_compare(world, base, cand)
    before = (base.with_suffix(".count").read_text(), cand.with_suffix(".count").read_text())
    assert rg.main(["reanalyze", str(out)]) == 0
    again = json.loads((out / "report.json").read_text())
    assert again == report                                      # the whole report, not only the headline
    # reanalysis ran no binary: the call counters did not move
    assert (base.with_suffix(".count").read_text(), cand.with_suffix(".count").read_text()) == before


def test_second_session_confirms_a_real_regression_and_not_a_noise_flag(world):
    good = fake_binary(world, "good")
    broken = fake_binary(world, "broken", collapse_every=1)
    _, first_dir, first = run_compare(world, good, broken, out="s1")
    assert "SUSPECTED REGRESSION" in first["decision"]["headline"]
    _, _, second = run_compare(world, good, broken, "--confirm-with", str(first_dir / "report.json"), out="s2")
    confirmed = [r["label"] for r in second["confirmation"]["confirmed"]]
    assert "WER" in confirmed and "collapsed runs" in confirmed
    assert "CONFIRMED (reproduced)" in (world / "s2" / "report.md").read_text()

def test_confirmation_is_refused_for_a_different_pair_and_for_the_session_itself(world):
    good = fake_binary(world, "good")
    broken = fake_binary(world, "broken", collapse_every=1)
    _, first_dir, first = run_compare(world, good, broken, out="s1")
    assert first["decision"]["flagged"]
    # a different pair (good against good) cannot confirm good against broken:
    _, _, other = run_compare(world, good, good, "--confirm-with", str(first_dir / "report.json"), out="s3")
    assert other["confirmation"]["refused"].startswith("the first session compared different binaries")
    assert other["confirmation"]["confirmed"] == [] and "REFUSED" in (world / "s3" / "report.md").read_text()
    # a session cannot confirm itself:
    assert rg.main(["reanalyze", str(first_dir), "--confirm-with", str(first_dir / "report.json")]) == 0
    itself = json.loads((first_dir / "report.json").read_text())
    assert "does not confirm itself" in itself["confirmation"]["refused"]
    assert itself["confirmation"]["confirmed"] == []


def test_baseline_drift_is_warned_about_and_names_the_base_commit(world, monkeypatch):
    # Off macOS there is no hardware model or OS version to read, so pin the environment: the
    # test must give the same answer on a Linux runner.
    monkeypatch.setattr(rg, "environment_record", lambda: {
        "hardware_model": "Mac14,12", "cpu": "Apple M2 Pro", "memory_gb": 16, "macos": "26.6.2",
        "date_utc": "2026-11-01T00:00:00+00:00"})
    tool = fake_binary(world, "tool")
    baseline = world / "baseline.json"
    baseline.write_text(json.dumps({
        "name": "old", "base_commit": str(tool), "model": "other-model",
        "environment": {"hardware_model": "Mac99,1", "cpu": "Apple M9", "memory_gb": 64,
                        "macos": "13.0", "date_utc": "2020-01-01"},
        "series": {"offline-synthetic": {"stats": {"wer": {"n": 12, "median": 0.9, "min": 0.8, "max": 1.0},
                                                   "rtf": {"n": 12, "median": 5.0, "min": 4.0, "max": 6.0}}}}}))
    out_dir = world / "drift"
    code = rg.main(["--cand", str(tool), "--baseline", str(baseline), "--only", "offline-synthetic",
                    "--runs", "8", "--out-dir", str(out_dir), "--no-lock"])      # no --base: from the baseline
    assert code == 0
    report = json.loads((out_dir / "report.json").read_text())
    warnings = " ".join(report["warnings"])
    assert "model id 'fake-model' here, 'other-model' in the baseline" in warnings
    assert "baseline drift: macOS" in warnings and "hardware model" in warnings
    check = " ".join(report["baseline_check"])
    assert "OUTSIDE the committed range" in check and "not interleaved" in check
    assert "Committed baseline" in (out_dir / "report.md").read_text()


def test_missing_base_without_a_baseline_is_a_usage_error(world, capsys):
    tool = fake_binary(world, "tool")
    assert rg.main(["--cand", str(tool), "--no-lock"]) == 2
    assert "--base" in capsys.readouterr().err


def test_a_candidate_that_fails_every_run_makes_the_session_incomplete_and_exit_nonzero(world):
    tool = fake_binary(world, "tool")
    broken = world / "broken"
    broken.write_text("#!/bin/sh\nexit 3\n")
    broken.chmod(0o755)
    code = rg.main(["--base", str(tool), "--cand", str(broken), "--only", "offline-synthetic",
                    "--runs", "8", "--out-dir", str(world / "bad"), "--no-lock"])
    assert code == 1                                            # was 0: "NO SIGNIFICANT DIFFERENCE in 0 metrics"
    report = json.loads((world / "bad" / "report.json").read_text())
    assert report["series"] == []                               # nothing to compare against
    assert any("no successful runs on the candidate side" in w for w in report["warnings"])
    assert report["incomplete"] and report["decision"]["headline"].startswith("INCOMPLETE")
    assert "INCOMPLETE" in (world / "bad" / "report.md").read_text()


def test_some_failed_runs_are_named_in_the_verdict_not_only_in_a_warning(world):
    steady = fake_binary(world, "steady")
    flaky = fake_binary(world, "flaky", fail_every=4)           # 4 of its 16 calls fail
    code, out, report = run_compare(world, steady, flaky)
    assert code == 1
    assert any("failed and are excluded" in line for line in report["incomplete"])
    assert report["decision"]["headline"].startswith("INCOMPLETE (offline-synthetic: 2 candidate run(s)")
    offline = next(s for s in report["series"] if s["id"] == "offline-synthetic")
    assert offline["arms"]["B"]["n"] == 6                       # the n the tests really used
    assert {t["status"] for t in offline["tests"]} <= {"no-verdict", "untested"}   # n = 6: no verdict


def test_a_metric_only_one_build_reports_is_listed_not_silently_dropped(world):
    old = fake_binary(world, "old")                             # reports no commit latency (an older binary)
    new = fake_binary(world, "new", commit_latency=2100)
    code, out, report = run_compare(world, old, new)
    live = next(s for s in report["series"] if s["id"] == "live-synthetic")
    assert live["skipped_metrics"] == [{"key": "live.commit_latency_median_ms",
                                        "label": "commit latency median", "missing_in": "base"}]
    assert all(t["key"] != "live.commit_latency_median_ms" for t in live["tests"])
    assert any("commit latency median is reported by only one build" in w for w in report["warnings"])
    assert "Not tested, reported by only one build: commit latency median (missing in the base)" \
        in (out / "report.md").read_text()


def test_diarization_runs_receive_models_and_extra_arguments(world):
    tool = fake_binary(world, "tool")
    rg.main(["--base", str(tool), "--cand", str(tool), "--only", "der-quick", "--out-dir",
             str(world / "dermodels"), "--no-lock", "--models", "/some/models"])
    assert "--models /some/models" in tool.with_suffix(".args").read_text()


# --------------------------------------------------------------------------
# Determinism
# --------------------------------------------------------------------------

def report_with(words, windows=None):
    out = {"transcript": " ".join(words),
           "words": [{"text": w, "startMs": i * 1000, "endMs": i * 1000 + 900} for i, w in enumerate(words)]}
    if windows:
        out["windows"] = windows
    return out


WINDOWS = [{"startMs": 0, "endMs": 4000}, {"startMs": 4000, "endMs": 9000}]


def test_determinism_identical_runs():
    result = rl.analyze_determinism([report_with(["a", "b", "c"])] * 4)
    assert result["identical"] and result["distinct"] == 1 and result["group_sizes"] == [4]
    assert result["first_divergence"] is None


def test_determinism_reports_distinct_transcripts_and_the_first_diverging_window():
    words = ["a", "b", "c", "d", "e", "f", "g"]
    other = ["a", "b", "c", "d", "X", "f", "g"]
    third = ["a", "b", "c", "d", "Y", "f", "g"]
    reports = [report_with(words, WINDOWS), report_with(other, WINDOWS), report_with(words, WINDOWS),
               report_with(third, WINDOWS)]
    result = rl.analyze_determinism(reports)
    assert not result["identical"] and result["distinct"] == 3 and result["group_sizes"] == [2, 1, 1]
    first = result["first_divergence"]
    assert (first["run_a"], first["run_b"], first["word_index"], first["time_ms"]) == (1, 2, 4, 4000)
    assert first["window_index"] == 1 and (first["window_start_ms"], first["window_end_ms"]) == (4000, 9000)
    assert "e" in first["a_context"] and "X" in first["b_context"]


def test_determinism_without_window_list_says_the_window_is_unknown():
    result = rl.analyze_determinism([report_with(["a", "b"]), report_with(["a", "Z"])])
    first = result["first_divergence"]
    assert first["word_index"] == 1 and first["window_index"] is None
    assert "window unknown" in rl.format_determinism(result)


def test_determinism_one_transcript_a_prefix_of_the_other():
    result = rl.analyze_determinism([report_with(["a", "b", "c"]), report_with(["a", "b"])])
    first = result["first_divergence"]
    assert first["word_index"] == 2 and not result["identical"]


def test_determinism_command_on_a_binary_that_varies(world, capsys):
    nondeterministic = fake_binary(world, "varies", vary_after=5)
    code = rg.main(["determinism", "--bin", str(nondeterministic), "--runs", "6", "--audio",
                    str(world / "clip.wav"), "--ref", str(world / "ref.txt"),
                    "--out-dir", str(world / "det"), "--no-lock"])
    out = capsys.readouterr().out
    assert code == 1                                            # not identical: the guard fires
    saved = json.loads((world / "det" / "determinism.json").read_text())
    assert saved["n"] == 6 and saved["distinct"] == 3           # w0, w1, w2 by n % 3
    assert saved["first_divergence"]["word_index"] == 5 and saved["first_divergence"]["window_index"] == 0
    assert "NOT identical: 3 distinct transcripts" in out


def test_determinism_command_on_a_deterministic_binary_exits_zero(world):
    tool = fake_binary(world, "steady")
    code = rg.main(["determinism", "--bin", str(tool), "--runs", "5", "--audio", str(world / "clip.wav"),
                    "--ref", str(world / "ref.txt"), "--out-dir", str(world / "det2"), "--no-lock"])
    assert code == 0
    assert json.loads((world / "det2" / "determinism.json").read_text())["identical"] is True
    assert tool.with_suffix(".count").read_text() == "5"        # five runs happened


def test_determinism_refuses_to_mix_runs_into_an_old_directory(world):
    one = fake_binary(world, "one")
    two = fake_binary(world, "two", vary_after=5)
    common = ["--runs", "3", "--audio", str(world / "clip.wav"), "--ref", str(world / "ref.txt"),
              "--out-dir", str(world / "det3"), "--no-lock"]
    assert rg.main(["determinism", "--bin", str(one), *common]) == 0
    assert rg.main(["determinism", "--bin", str(two), *common]) == 2         # was: 3 + 3 runs, one verdict
    assert len(list((world / "det3").glob("run-*.json"))) == 6               # 3 runs + 3 reports, untouched


def test_stream_resumes_its_own_runs_and_refuses_another_binary(world, capsys):
    one = fake_binary(world, "one")
    two = fake_binary(world, "two", rtf=0.5)
    out = world / "stream"
    args = lambda b, n: ["stream", "--bin", str(b), "--runs", str(n), "--out-dir", str(out), "--no-lock"]
    assert rg.main(args(one, 3)) == 0
    assert len([p for p in out.glob("run-*.json") if not p.name.endswith(".report.json")]) == 3
    assert rg.main(args(one, 5)) == 0                                         # the same stream continues
    assert len([p for p in out.glob("run-*.json") if not p.name.endswith(".report.json")]) == 5
    assert rg.main(args(two, 8)) == 2                                         # another binary: refused
    assert "different binary" in capsys.readouterr().err
    assert len([p for p in out.glob("run-*.json") if not p.name.endswith(".report.json")]) == 5


def test_work_files_are_unique_per_batch_and_cleaned_up(world):
    tool = fake_binary(world, "tool")
    run_compare(world, tool, tool, out="w1")
    run_compare(world, tool, tool, out="w1b")
    leftover = list((world / "scratch" / "work").glob("*.json"))
    assert leftover == []                                                    # none left to be shared or confused
    names = set()
    real = rg.uuid.uuid4
    items = [{"kind": "asr", "arm": "A", "index": 1, "binary": str(tool), "audio": str(world / "clip.wav"),
              "ref": str(world / "ref.txt"), "mode": "offline", "extra": [], "out_dir": str(world / "wf"),
              "timeout": 60}]
    for _ in range(2):
        rg.run_batch(items, scratch=world / "scratch", use_lock=False, tag="same-tag")
    assert len(list((world / "wf").glob("run-01.json"))) == 1                # the same slot rewritten, no crash
    assert rg.uuid.uuid4 is real and not names


def test_build_lock_clears_a_dead_holder_and_blocks_a_live_one(tmp_path):
    lock = tmp_path / ".lock"
    dead = subprocess.Popen([sys.executable, "-c", "pass"])
    dead.wait()
    lock.mkdir()
    (lock / "pid").write_text(str(dead.pid))
    with rg._BuildLock(lock, poll=0.01, limit=0.2):                          # stale: cleared, then held
        assert (lock / "pid").read_text() == str(os.getpid())
    assert not lock.exists()                                                 # released on exit
    lock.mkdir()
    (lock / "pid").write_text(str(os.getpid()))                              # a live holder (this process)
    with pytest.raises(RuntimeError, match="has been building here"):
        with rg._BuildLock(lock, poll=0.01, limit=0.05):
            pass
    assert lock.exists()                                                     # the live holder's lock is untouched


def test_a_second_process_waits_for_the_first_build_instead_of_deleting_it(tmp_path, monkeypatch):
    repo, sha = make_repo(tmp_path)
    monkeypatch.setattr(rg.sys, "platform", "darwin")
    builds = tmp_path / "scratch" / "builds"
    binary = builds / sha / "app" / ".build" / "release" / "transcribe"

    class SlowSwift(FakeSwift):
        """While 'building', another resolver arrives; it must wait and then find the binary."""
        def __call__(self, cmd, cwd=None, stdout=None, stderr=None):
            holder = rg._BuildLock(builds / f".{sha}.lock", poll=0.01, limit=0.05)
            with pytest.raises(RuntimeError, match="has been building here"):
                holder.__enter__()                                           # blocked while we build
            return super().__call__(cmd, cwd=cwd, stdout=stdout, stderr=stderr)

    info = rg.resolve_binary(sha, scratch=tmp_path / "scratch", repo=repo, runner=SlowSwift())
    assert info["built"] and binary.is_file()
    assert not (builds / f".{sha}.lock").exists()


# --------------------------------------------------------------------------
# Baselines
# --------------------------------------------------------------------------

def test_save_baseline_keeps_numbers_only(world, tmp_path):
    tool = fake_binary(world, "tool")
    _, out, report = run_compare(world, tool, tool)
    target = tmp_path / "saved.json"
    assert rg.main(["save-baseline", str(out / "report.json"), "--name", "t", "--out", str(target)]) == 0
    saved = json.loads(target.read_text())
    assert saved["name"] == "t" and "offline-synthetic" in saved["series"]
    assert saved["series"]["offline-synthetic"]["stats"]["wer"]["n"] == 8
    assert "transcript" not in target.read_text()               # no text, only numbers
    # The fixtures map is keyed by FIXTURE id, which is what drift_warnings reads: a baseline made
    # by this tool must be able to report that the fixture changed.
    assert saved["fixtures"] == {"synthetic-taglish": {"sha256": "aa", "synthetic": True}}
    drift = rl.drift_warnings(saved, saved["environment"], model=saved["model"],
                              fixture_hashes={"synthetic-taglish": "bb"})
    assert drift and "fixture synthetic-taglish" in drift[0]
    assert rl.drift_warnings(saved, saved["environment"], model=saved["model"],
                             fixture_hashes={"synthetic-taglish": "aa"}) == []


def test_drift_warnings_compare_machine_os_model_and_fixture():
    baseline = {"environment": {"hardware_model": "Mac14,12", "cpu": "Apple M2 Pro", "memory_gb": 16,
                                "macos": "26.6.2"},
                "model": "m1", "fixtures": {"synthetic-taglish": {"sha256": "aaaa1111"}}}
    same = {"hardware_model": "Mac14,12", "cpu": "Apple M2 Pro", "memory_gb": 16, "macos": "26.6.2"}
    assert rl.drift_warnings(baseline, same, model="m1", fixture_hashes={"synthetic-taglish": "aaaa1111"}) == []
    minor = dict(same, macos="26.6.3")
    assert rl.drift_warnings(baseline, minor, model="m1")[0].startswith("baseline drift (minor)")
    major = dict(same, macos="27.0", hardware_model="Mac15,1", memory_gb=32)
    text = " ".join(rl.drift_warnings(baseline, major, model="m2",
                                      fixture_hashes={"synthetic-taglish": "bbbb2222"}))
    for expected in ("hardware model", "memory (GB)", "macOS 27.0", "model id 'm2'", "fixture synthetic-taglish"):
        assert expected in text
