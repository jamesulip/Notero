"""The committed evidence (eval/baselines/): that it is what its README says, that the
numbers quoted in code comments and docs are true of it, and that the measured
false-positive rate meets the requirement the decision rule was chosen for.

If a test here fails after a legitimate change to the rule, regenerate the files
(`calibrate_aa.py simulate`, `import_p6.py`) and update the prose that quotes them."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import benchstats as bs  # noqa: E402
import calibrate_aa as ca  # noqa: E402

BASELINES = Path(__file__).resolve().parents[1] / "eval" / "baselines"
P6 = json.loads((BASELINES / "p6-f022c6e-synthetic-taglish.json").read_text())
LEAD = json.loads((BASELINES / "p6-lead-ab-main-vs-p6-branch.json").read_text())
CALIBRATION = json.loads((BASELINES / "aa-calibration.json").read_text())
REF_WORDS = P6["fixtures"]["synthetic-taglish"]["ref_words"]


def test_the_baseline_names_its_provenance():
    assert P6["base_commit"].startswith("f022c6e")
    env = P6["environment"]
    assert env["hardware_model"] == "Mac14,12" and env["macos"] == "26.6.2" and env["memory_gb"] == 16
    assert P6["model"] == "openai_whisper-large-v3-v20240930_turbo"
    assert len(P6["fixtures"]["synthetic-taglish"]["sha256"]) == 64
    assert "SYNTHETIC" in P6["what"]
    assert set(P6["series"]) == {"offline-synthetic", "live-synthetic"}
    assert P6["provenance"]["harness_commits"]


def test_the_baseline_holds_numbers_not_text_and_stays_small():
    for name in ("p6-f022c6e-synthetic-taglish.json", "p6-lead-ab-main-vs-p6-branch.json", "aa-calibration.json"):
        path = BASELINES / name
        assert path.stat().st_size < 100_000, name
        text = path.read_text()
        for forbidden in ('"transcript"', '"words":', '"text"', "Kumusta", "kailangan"):
            assert forbidden not in text, (name, forbidden)
    assert not list(BASELINES.rglob("*.wav")) and not list(BASELINES.rglob("*.m4a"))


def test_arm_sizes_are_those_the_readme_states():
    sizes = {name: arm["n"] for name, arm in P6["arms"].items()}
    assert sizes["offline-pure"] == 12 and sizes["offline-instrumented"] == 12
    for name in ("live-pure", "live-instrumented", "recheck-live-pure", "recheck-live-instrumented",
                 "aa-live-path1", "aa-live-path2", "realtime-instrumented"):
        assert sizes[name] == 8, name
    assert sum(sizes.values()) == 80
    for arm in P6["arms"].values():
        assert len(arm["rows"]) == arm["n"]


def test_stored_collapse_flags_are_what_the_two_rules_give_on_the_stored_runs():
    for name, arm in P6["arms"].items():
        wers = [r["wer"] for r in arm["rows"]]
        words = [r["hyp_words"] for r in arm["rows"]]
        filler = [bool(r.get("filler")) for r in arm["rows"]]
        flags, _ = bs.classify_collapsed(wers, words, REF_WORDS, filler=filler)
        assert [r["index"] for r, f in zip(arm["rows"], flags) if f] == arm["collapsed_by_current_rule"], name
        threshold = 2 * bs.best_half_median(wers)
        old = [r["index"] for r in arm["rows"]
               if r["wer"] > threshold + 1e-12 or r["hyp_words"] < 0.75 * REF_WORDS - 1e-12]
        assert old == arm["collapsed_by_p6_rule"], name


def test_the_new_rule_flags_the_57_percent_filler_run_the_old_rule_missed():
    arm = P6["arms"]["offline-pure"]
    assert arm["collapsed_by_p6_rule"] == [3] and arm["collapsed_by_current_rule"] == [3, 8]
    run8 = next(r for r in arm["rows"] if r["index"] == 8)
    assert run8["wer"] == pytest.approx(0.5703125) and run8["filler"] is True
    differing = [name for name, a in P6["arms"].items()
                 if a["collapsed_by_p6_rule"] != a["collapsed_by_current_rule"]]
    assert differing == ["offline-pure"]                    # the only arm the change touches


def test_the_numbers_quoted_in_the_collapse_rule_comment_are_true_of_the_80_p6_runs():
    # benchstats.py: "the largest excess of a run that nobody calls collapsed is +10.9 points
    # and the smallest excess of a collapsed run is +26.2 points".
    normal, collapsed = [], []
    for arm in P6["arms"].values():
        wers = [r["wer"] for r in arm["rows"]]
        level = bs.best_half_median(wers)
        for r in arm["rows"]:
            (collapsed if r["index"] in arm["collapsed_by_current_rule"] else normal).append(r["wer"] - level)
    assert len(normal) + len(collapsed) == 80
    assert max(normal) == pytest.approx(0.109, abs=0.001) and min(collapsed) == pytest.approx(0.262, abs=0.001)
    assert max(normal) < bs.COLLAPSE_EXCESS < min(collapsed)
    assert bs.COLLAPSE_EXCESS - max(normal) == pytest.approx(0.041, abs=0.002)        # "4.1 points clear"
    fractions = [r["hyp_words"] / REF_WORDS for arm in P6["arms"].values() for r in arm["rows"]
                 if r["index"] not in arm["collapsed_by_current_rule"]]
    assert min(fractions) >= 0.88 - 0.005 and min(fractions) > bs.COLLAPSE_MIN_WORD_FRACTION


def test_lead_ab_shows_main_collapsing_four_of_six_and_the_branch_never():
    assert LEAD["arms"]["A"]["collapsed_by_p6_rule"] == [6]
    assert LEAD["arms"]["A"]["collapsed_by_current_rule"] == [2, 3, 4, 6]
    assert LEAD["arms"]["B"]["collapsed_by_current_rule"] == []
    assert {r["wer"] for r in LEAD["arms"]["B"]["rows"]} == {0.242188}


def test_the_p6_recheck_is_the_example_of_a_busy_session_inventing_a_timing_gap():
    busy = [P6["arms"][a] for a in ("live-pure", "live-instrumented")]
    quiet = [P6["arms"][a] for a in ("recheck-live-pure", "recheck-live-instrumented")]
    busy_gap = bs.median([r["rtf"] for r in busy[1]["rows"]]) / bs.median([r["rtf"] for r in busy[0]["rows"]]) - 1
    quiet_gap = bs.median([r["rtf"] for r in quiet[1]["rows"]]) / bs.median([r["rtf"] for r in quiet[0]["rows"]]) - 1
    assert busy_gap > 0.10 and abs(quiet_gap) < 0.03                       # +17% busy, +1% quiet
    loads = lambda arms: [r["load"] for a in arms for r in a["rows"]]
    assert bs.median(loads(busy)) > bs.LOAD_QUIET_MEDIAN >= bs.median(loads(quiet))


# ---- the measured false-positive rate -------------------------------------------------

POOLS = CALIBRATION["simulation"]["pools"]


def test_the_calibration_covers_every_pool_with_enough_replicates():
    assert set(POOLS) == set(ca.POOLS)
    assert CALIBRATION["simulation"]["replicates"] >= 2000 and CALIBRATION["simulation"]["n_per_arm"] == 8
    for name, pool in POOLS.items():
        assert pool["replicates"] >= 2000 and pool["family_size"] >= 4, name


def test_the_shipped_rule_flags_an_aa_session_at_most_5_percent_across_all_metrics_together():
    # THE REQUIREMENT. The upper end of the 95% interval, not just the point estimate.
    for name, pool in POOLS.items():
        shipped = pool["any_metric_flagged"]["shipped_ignoring_load"]
        assert shipped["rate"] <= 0.05 and shipped["ci95"][1] <= 0.05, (name, shipped)
        assert pool["any_metric_flagged"]["holm"]["ci95"][1] <= 0.05, name


def test_reading_the_table_uncorrected_would_have_failed_that_requirement():
    for name, pool in POOLS.items():
        naive = pool["any_metric_flagged"]["naive"]
        assert naive["ci95"][0] > 0.05, (name, naive)       # clearly above 5%: the reason for Holm


def test_two_sessions_must_agree_and_that_is_rarer_still():
    for name, pool in POOLS.items():
        confirmed = pool["any_metric_flagged"]["confirmed"]
        assert confirmed["ci95"][1] <= 0.01, (name, confirmed)


def test_the_calibration_states_its_power_honestly():
    for name, pool in POOLS.items():
        power = pool["power_of_shipped_rule"]
        # A 10-point WER shift is the one effect n = 8 reliably sees; small timing shifts are not:
        # the report must not pretend otherwise.
        assert "WER +10 points" in power and "RTF +10%" in power
        assert power["RTF +10%"]["rate"] < 0.5, name


def test_the_simulation_reproduces_the_committed_replicates_exactly_from_its_seed():
    # Recompute the first 80 replicates of a pool from the committed seed and compare WHICH
    # of them each rule flagged with the committed list: not a bound, an exact match.
    reps = 80
    again = ca.simulate(P6, n=8, reps=reps, jobs=1, seed=CALIBRATION["simulation"]["seed"],
                        pools=["offline-pure"], power=False)["offline-pure"]
    committed = POOLS["offline-pure"]["flagged_replicates"]
    for rule, flagged in again["flagged_replicates"].items():
        assert flagged == [i for i in committed[rule] if i < reps], rule
    assert again["family_size"] == POOLS["offline-pure"]["family_size"]
    assert len(committed["naive"]) > len(committed["shipped_ignoring_load"]) > len(committed["confirmed"]) - 1
    assert committed["naive"], "the naive rule must have flagged some replicates, or the check proves nothing"
