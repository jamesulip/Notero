"""The statistics that decide whether a benchmark claim may be called significant.

Every expected value below is either worked out by hand (the derivation is in
the comment) or a published reference value, so these tests do not just restate
the implementation.
"""

import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import benchstats as bs  # noqa: E402


# ---- location and spread -------------------------------------------------

def test_quantile_matches_numpy_type7():
    # numpy.quantile([1, 2, 3, 4], q) -> 1.75, 2.5, 3.25
    assert bs.quantile([1, 2, 3, 4], 0.25) == pytest.approx(1.75)
    assert bs.quantile([4, 3, 2, 1], 0.5) == pytest.approx(2.5)
    assert bs.quantile([1, 2, 3, 4], 0.75) == pytest.approx(3.25)
    assert bs.quantile([5], 0.9) == 5
    assert bs.quantile([1, 2, 3, 4], 0) == 1
    assert bs.quantile([1, 2, 3, 4], 1) == 4


def test_quantile_matches_the_swift_percentile():
    # RunMetricsTests.percentiles pins the same numbers on the Swift side.
    assert bs.quantile([10, 20, 30, 40], 0.95) == pytest.approx(38.5)


def test_quantile_rejects_bad_input():
    with pytest.raises(ValueError):
        bs.quantile([], 0.5)
    with pytest.raises(ValueError):
        bs.quantile([1], 1.5)


def test_describe_has_median_range_and_iqr():
    d = bs.describe([25.0, 26.0, 27.0, 28.0, 57.0])
    assert d["n"] == 5 and d["median"] == 27.0
    assert (d["min"], d["max"]) == (25.0, 57.0)
    assert d["q1"] == 26.0 and d["q3"] == 28.0 and d["iqr"] == 2.0
    assert d["mean"] == pytest.approx(32.6)
    assert bs.describe([]) is None


# ---- collapsed runs ------------------------------------------------------

def test_best_half_median():
    # odd n: the middle value belongs to the best half. [10, 20, 30] -> 20
    assert bs.best_half_median([50, 10, 30, 20, 40]) == 20
    # even n: the two lowest of four. [10, 20] -> 15
    assert bs.best_half_median([40, 10, 30, 20]) == 15
    assert bs.best_half_median([7]) == 7
    with pytest.raises(ValueError):
        bs.best_half_median([])


# The runs below are the REAL offline series of the P6 baseline (12 runs of the pure
# f022c6e build, FINDINGS 15), in WER and normalized-word count, from
# eval/baselines/p6-f022c6e-synthetic-taglish.json. Run 8 is the 57.0% run in which
# Whisper invented a filler phrase. The old rule (2x the best-half median) put its
# threshold at 61.7% and never counted it.
P6_OFFLINE_PURE_WER = [0.3125, 0.3671875, 0.578125, 0.3203125, 0.3671875, 0.3359375,
                       0.34375, 0.5703125, 0.2421875, 0.3515625, 0.2109375, 0.3046875]
P6_OFFLINE_PURE_WORDS = [119, 121, 78, 120, 115, 123, 122, 116, 119, 121, 121, 121]


def test_collapse_rule_flags_the_57_percent_filler_run_the_old_rule_missed():
    flags, threshold = bs.classify_collapsed(P6_OFFLINE_PURE_WER, P6_OFFLINE_PURE_WORDS, ref_words=128)
    collapsed = [i + 1 for i, f in enumerate(flags) if f]
    assert collapsed == [3, 8]
    # run 3 is caught by WER and by the word floor (78 of 128 words), run 8 by WER alone:
    reasons, _ = bs.collapse_reasons(P6_OFFLINE_PURE_WER, P6_OFFLINE_PURE_WORDS, ref_words=128)
    assert reasons[2] == ["wer", "words"] and reasons[7] == ["wer"]
    # The P6 rule, reproduced here so the test states what it replaces:
    old_threshold = 2.0 * bs.best_half_median(P6_OFFLINE_PURE_WER)
    assert P6_OFFLINE_PURE_WER[7] < old_threshold          # 57.0% under a 61.7% threshold
    assert threshold == pytest.approx(bs.best_half_median(P6_OFFLINE_PURE_WER) + 0.15)


def test_collapse_rule_margin_is_the_gap_in_the_p6_data():
    # No run that nobody calls collapsed is more than 10.9 points above its level, and
    # the filler run is 26.2 above: 15 points sits inside that gap (docs/BENCHMARKS.md).
    level = bs.best_half_median(P6_OFFLINE_PURE_WER)
    excess = sorted(w - level for w in P6_OFFLINE_PURE_WER)
    assert excess[-1] == pytest.approx(0.578125 - level)       # the worst run
    assert excess[-3] < bs.COLLAPSE_EXCESS < excess[-2]        # normal runs below, collapsed above
    assert excess[-2] == pytest.approx(0.5703125 - level)


def test_collapse_rule_boundary_is_strictly_more_than_15_points():
    # level 0.30 (best half of these four is [0.30, 0.30]); threshold 0.45.
    flags, threshold = bs.classify_collapsed([0.30, 0.30, 0.45, 0.46], [100] * 4, ref_words=100)
    assert threshold == pytest.approx(0.45)
    assert flags == [False, False, False, True]


def test_collapse_rule_short_transcript_is_collapsed_even_at_low_wer():
    # 75% of 100 reference words is 75. 74 words is collapsed, 75 is not.
    flags, _ = bs.classify_collapsed([0.2, 0.2, 0.2], [74, 75, 100], ref_words=100)
    assert flags == [True, False, False]


def test_collapse_rule_counts_an_invented_filler_phrase_at_any_wer():
    # A filler phrase in a window that cost only 4 points of WER is still a collapsed window.
    flags, _ = bs.classify_collapsed([0.25, 0.25, 0.29], [100] * 3, ref_words=100,
                                     filler=[False, False, True])
    assert flags == [False, False, True]
    reasons, _ = bs.collapse_reasons([0.25, 0.25, 0.29], [100] * 3, 100, filler=[False, False, True])
    assert reasons[2] == ["filler"]


def test_reference_level_pools_the_arms_so_a_uniformly_bad_arm_is_judged_by_the_good_one():
    good = [0.25, 0.26, 0.25, 0.27, 0.26, 0.25, 0.26, 0.27]
    bad = [0.60, 0.61, 0.62, 0.60, 0.59, 0.61, 0.60, 0.62]
    # Alone, the bad arm is not collapsed: its own level is 0.60.
    own, _ = bs.classify_collapsed(bad, [100] * 8, ref_words=100)
    assert own == [False] * 8
    level = bs.reference_level(good, bad)
    assert level == pytest.approx(bs.median(good))   # the lowest half of the pool IS the good arm
    shared, _ = bs.classify_collapsed(bad, [100] * 8, ref_words=100, level=level)
    assert shared == [True] * 8
    # Symmetric: which arm is called baseline does not change the level.
    assert bs.reference_level(bad, good) == level


def test_collapse_rule_catches_the_lead_ab_pre_p6_runs():
    # lead A/B (docs/BENCHMARKS.md): main gave 35.2, 60.9, 63.3, 59.4, 29.7, 57.0 % and the
    # P6 branch 24.2 six times. Pooled level 24.2 -> threshold 39.2: four of main's six.
    main = [0.3515625, 0.609375, 0.6328125, 0.59375, 0.296875, 0.5703125]
    branch = [0.2421875] * 6
    level = bs.reference_level(main, branch)
    flags, threshold = bs.classify_collapsed(main, [120, 134, 121, 123, 118, 90], 128, level=level)
    assert threshold == pytest.approx(0.2421875 + 0.15)
    assert flags == [False, True, True, True, False, True]
    assert bs.classify_collapsed(branch, [120] * 6, 128, level=level)[0] == [False] * 6


def test_explicit_wer_threshold_overrides_the_level():
    flags, threshold = bs.classify_collapsed([0.60, 0.61, 0.59], [100] * 3, 100, wer_threshold=0.5)
    assert threshold == 0.5 and flags == [True] * 3


def test_collapse_rule_text_states_the_numbers():
    assert "15 points" in bs.COLLAPSE_RULE and "75%" in bs.COLLAPSE_RULE
    assert "best half" in bs.COLLAPSE_RULE and "filler" in bs.COLLAPSE_RULE


# ---- permutation test ----------------------------------------------------

def test_permutation_exact_p_matches_hand_enumeration():
    # a = {1,2,3}, b = {4,5,6}. Of the C(6,3) = 20 ways to split {1..6} into two
    # triples, exactly four give |median difference| >= 3 (the observed value):
    # {1,2,3}|{4,5,6}, {4,5,6}|{1,2,3}, {1,2,4}|{3,5,6}, {3,5,6}|{1,2,4}. p = 4/20.
    p, method = bs.permutation_p_value([1, 2, 3], [4, 5, 6])
    assert method == "exact"
    assert p == pytest.approx(0.2)


def test_permutation_identical_samples_give_p_of_one():
    p, method = bs.permutation_p_value([3, 3, 3, 3], [3, 3, 3, 3])
    assert p == 1.0 and method == "exact"


def test_permutation_is_symmetric_in_its_arguments():
    a, b = [0.25, 0.26, 0.28, 0.27, 0.57], [0.30, 0.31, 0.33, 0.29, 0.32]
    assert bs.permutation_p_value(a, b)[0] == bs.permutation_p_value(b, a)[0]


def test_permutation_complete_separation_at_n8_is_significant():
    p, method = bs.permutation_p_value(list(range(1, 9)), list(range(9, 17)))
    assert method == "exact" and p < 0.05


def test_permutation_overlapping_samples_are_not_significant():
    p, _ = bs.permutation_p_value([1, 4, 5, 8, 9, 12, 13, 16], [2, 3, 6, 7, 10, 11, 14, 15])
    assert p > 0.5


def test_permutation_monte_carlo_agrees_with_exact_and_is_seeded():
    exact, _ = bs.permutation_p_value([1, 2, 3], [4, 5, 6])
    mc, method = bs.permutation_p_value([1, 2, 3], [4, 5, 6], max_exact=0, seed=1)
    assert method == "monte-carlo"
    assert abs(mc - exact) < 0.01
    again, _ = bs.permutation_p_value([1, 2, 3], [4, 5, 6], max_exact=0, seed=1)
    assert again == mc
    # The estimator is (k+1)/(N+1): never exactly zero.
    far, _ = bs.permutation_p_value(list(range(20)), list(range(100, 120)),
                                    max_exact=0, monte_carlo=1000, seed=3)
    assert far == pytest.approx(1 / 1001)


def test_permutation_uses_monte_carlo_above_the_exact_limit():
    # C(24, 12) = 2,704,156 arrangements is above MAX_EXACT_ARRANGEMENTS.
    a = [0.25 + 0.001 * i for i in range(12)]
    b = [0.40 + 0.001 * i for i in range(12)]
    p, method = bs.permutation_p_value(a, b, monte_carlo=2000)
    assert method == "monte-carlo" and p < 0.01


def test_permutation_rejects_empty():
    with pytest.raises(ValueError):
        bs.permutation_p_value([], [1])


# ---- bootstrap interval --------------------------------------------------

def test_bootstrap_is_degenerate_for_constant_samples():
    lo, hi = bs.bootstrap_ci([1.0] * 8, [3.0] * 8)
    assert lo == pytest.approx(2.0) and hi == pytest.approx(2.0)


def test_bootstrap_excludes_zero_for_clearly_separated_arms():
    a = [0.25, 0.26, 0.27, 0.25, 0.26, 0.28, 0.27, 0.26]
    b = [0.40, 0.41, 0.42, 0.40, 0.43, 0.41, 0.42, 0.44]
    lo, hi = bs.bootstrap_ci(a, b)
    assert lo > 0 and hi > lo
    assert lo <= bs.median_difference(a, b) <= hi


def test_bootstrap_includes_zero_for_interleaved_arms():
    a = [1, 4, 5, 8, 9, 12, 13, 16]
    b = [2, 3, 6, 7, 10, 11, 14, 15]
    lo, hi = bs.bootstrap_ci(a, b)
    assert lo < 0 < hi


def test_bootstrap_is_seeded():
    a, b = [1, 2, 3, 9], [2, 3, 4, 5]
    assert bs.bootstrap_ci(a, b, seed=7) == bs.bootstrap_ci(a, b, seed=7)


# ---- Fisher exact --------------------------------------------------------

def test_fisher_matches_published_values():
    # scipy.stats.fisher_exact([[3, 1], [1, 3]])[1] = 0.4857142857...
    assert bs.fisher_exact(3, 1, 1, 3) == pytest.approx(34 / 70)
    # Wikipedia, "Fisher's exact test": [[1, 9], [11, 3]] -> two-sided 0.002759
    assert bs.fisher_exact(1, 9, 11, 3) == pytest.approx(0.002759, abs=2e-6)
    # Complete separation, 8 against 8: the two extreme tables, 2 / C(16, 8).
    assert bs.fisher_exact(8, 0, 0, 8) == pytest.approx(2 / 12870)


def test_fisher_reproduces_finding_15():
    # FINDINGS 15: first window collapsed in 1 of 8 runs on 1.1.0 and 5 of 8 on
    # 1.1.1, "Fisher exact, two-sided, p = 0.12". By hand: margins give
    # P(x) = C(8,x) C(8,6-x) / 8008 for x = 0..6, i.e. 28, 448, 1960, 3136, 1960,
    # 448, 28. The observed x = 1 has 448; tables no likelier: x = 0, 1, 5, 6.
    # (28 + 448 + 448 + 28) / 8008 = 952 / 8008 = 0.1189.
    assert bs.fisher_exact(1, 7, 5, 3) == pytest.approx(952 / 8008)
    assert round(bs.fisher_exact(1, 7, 5, 3), 2) == 0.12


def test_fisher_is_symmetric_and_bounded():
    assert bs.fisher_exact(2, 6, 5, 3) == pytest.approx(bs.fisher_exact(5, 3, 2, 6))
    assert bs.fisher_exact(2, 6, 2, 6) == pytest.approx(1.0)
    assert 0 < bs.fisher_exact(0, 8, 0, 8) <= 1.0
    assert bs.fisher_exact(0, 0, 0, 0) == 1.0


def test_fisher_rejects_negative_counts():
    with pytest.raises(ValueError):
        bs.fisher_exact(-1, 2, 3, 4)


# ---- the verdict ---------------------------------------------------------

def _verdict(**overrides):
    args = dict(n_a=8, n_b=8, wer_diff=-0.10, wer_p=0.002, wer_ci=(-0.14, -0.06),
                collapsed_a=3, collapsed_b=0, fisher_p=0.2, interleaved=True)
    args.update(overrides)
    return bs.verdict(**args)


def test_verdict_refuses_below_minimum_n_even_for_a_huge_difference():
    for n_a, n_b in ((7, 8), (8, 7), (3, 3), (1, 1)):
        text = _verdict(n_a=n_a, n_b=n_b, wer_p=1e-9, fisher_p=1e-9)
        assert text.startswith("NO VERDICT")
        assert "SIGNIFICANT" not in text.replace("NO VERDICT", "")
        assert str(bs.MIN_RUNS_FOR_VERDICT) in text


def test_verdict_calls_a_clear_difference_significant_at_n8():
    text = _verdict()
    assert "SIGNIFICANT" in text and "not significant" not in text.split("collapsed")[0]
    assert "10.0 points lower" in text


def test_verdict_asks_for_a_repeat_when_significant_below_12_runs():
    text = _verdict(n_a=8, n_b=8)
    assert "SIGNIFICANT" in text and "CONFIRM BEFORE ACTING" in text
    assert "0.041" in text
    # Enough runs: no warning. Not significant: no warning either.
    assert "CONFIRM" not in _verdict(n_a=12, n_b=12)
    assert "CONFIRM" not in _verdict(wer_p=0.5, wer_ci=(-0.05, 0.05), fisher_p=0.5)
    # A significant collapse count alone also triggers it.
    only_collapse = _verdict(wer_p=0.5, wer_ci=(-0.05, 0.05), fisher_p=0.01)
    assert "CONFIRM BEFORE ACTING" in only_collapse


def test_verdict_needs_permutation_and_bootstrap_to_agree():
    # p < 0.05 but the interval touches zero -> not significant.
    text = _verdict(wer_p=0.04, wer_ci=(-0.12, 0.01))
    assert "not significant" in text.split("collapsed")[0]


def test_verdict_never_claims_equivalence():
    text = _verdict(wer_diff=0.001, wer_p=0.9, wer_ci=(-0.02, 0.02), fisher_p=1.0,
                    collapsed_a=1, collapsed_b=1)
    assert "not significant" in text
    assert "not evidence they are equivalent" in text
    assert "equivalent" not in text.replace("not evidence they are equivalent", "")


def test_verdict_refuses_non_interleaved_runs_unless_told_otherwise():
    assert _verdict(interleaved=False).startswith("NO VERDICT: the two arms were not interleaved")
    allowed = _verdict(interleaved=False, allow_non_interleaved=True)
    assert "NOT INTERLEAVED" in allowed and "SIGNIFICANT" in allowed


def test_verdict_collapsed_counts_use_fisher():
    text = _verdict(collapsed_a=1, collapsed_b=5, fisher_p=0.119)
    assert "1/8 baseline vs 5/8 candidate" in text
    assert "p = 0.119" in text and text.endswith(".")


# ---- interleaving schedule -----------------------------------------------

def test_interleave_schedule_abab():
    assert bs.interleave_schedule(3) == ["A", "B", "A", "B", "A", "B"]


def test_interleave_schedule_abba_balances_who_goes_first():
    order = bs.interleave_schedule(4, "abba")
    assert order == list("ABBAABBA")
    assert order.count("A") == order.count("B") == 4


def test_interleave_schedule_rejects_bad_input():
    with pytest.raises(ValueError):
        bs.interleave_schedule(0)
    with pytest.raises(ValueError):
        bs.interleave_schedule(2, "aabb")


# ---- rank-sum permutation test --------------------------------------------

def test_rank_sum_exact_p_matches_hand_enumeration():
    # a = [1, 2], b = [3, 4]: ranks 1..4, six arrangements, A's rank sums are
    # 3, 4, 5, 5, 6, 7 around the expectation 5. |S - 5| >= 2 for 3 and 7 -> 2/6.
    p, method = bs.rank_sum_p_value([1, 2], [3, 4])
    assert method == "exact" and p == pytest.approx(2 / 6)


def test_rank_sum_ties_use_midranks_and_identical_samples_give_one():
    assert bs.rank_sum_p_value([1] * 8, [1] * 8)[0] == 1.0
    assert bs.midranks([5, 1, 5, 3]) == [3.5, 1.0, 3.5, 2.0]


def test_rank_sum_can_reach_far_smaller_p_than_the_median_difference_at_n8():
    separated_a, separated_b = list(range(8)), list(range(10, 18))
    p_rank, _ = bs.rank_sum_p_value(separated_a, separated_b)
    p_median, _ = bs.permutation_p_value(separated_a, separated_b)
    assert p_rank == pytest.approx(2 / math.comb(16, 8))     # 0.000155
    # The reason `decide` uses the rank sum: the difference-of-medians statistic ties on
    # 40 arrangements even for completely separated samples, so its smallest p is 0.0031 and
    # Holm over 17 or more tests (alpha / 17 = 0.0029) could never flag anything at n = 8.
    assert 0.0030 < p_median < 0.0032
    assert bs.ALPHA / 17 < p_median


def test_rank_sum_is_symmetric_and_monte_carlo_agrees_with_exact():
    a, b = [1, 3, 5, 7, 9, 11], [2, 4, 6, 8, 10, 30]
    assert bs.rank_sum_p_value(a, b)[0] == pytest.approx(bs.rank_sum_p_value(b, a)[0])
    exact, _ = bs.rank_sum_p_value(a, b)
    estimate, method = bs.rank_sum_p_value(a, b, max_exact=10, monte_carlo=40_000)
    assert method == "monte-carlo" and estimate == pytest.approx(exact, abs=0.02)


def test_exact_permutation_matches_a_plain_enumeration():
    # The optimized exact test must give the answer of the obvious loop.
    import itertools
    a, b = [0.3, 0.1, 0.25, 0.4, 0.2], [0.35, 0.5, 0.45, 0.15, 0.6, 0.55]
    pooled = a + b
    observed = abs(bs.median(b) - bs.median(a))
    hits = total = 0
    for chosen in itertools.combinations(range(len(pooled)), len(a)):
        group_a = [pooled[i] for i in chosen]
        group_b = [pooled[i] for i in range(len(pooled)) if i not in chosen]
        total += 1
        hits += abs(bs.median(group_b) - bs.median(group_a)) >= observed - 1e-12
    assert bs.permutation_p_value(a, b)[0] == pytest.approx(hits / total)


# ---- Holm ------------------------------------------------------------------

def test_holm_adjusts_in_order_and_keeps_none():
    # sorted 0.01, 0.03, 0.04 times 3, 2, 1 -> 0.03, 0.06, 0.04; the running maximum lifts the last to 0.06.
    assert bs.holm_adjust([0.01, 0.04, 0.03, None]) == pytest.approx([0.03, 0.06, 0.06, None])
    assert bs.holm_adjust([0.5]) == [0.5]
    assert bs.holm_adjust([0.9, 0.8]) == [1.0, 1.0]       # capped at 1


# ---- load assessment ----------------------------------------------------------

def test_assess_load_quiet_and_balanced_is_reliable():
    load = bs.assess_load([0.5, 0.7, 1.1], [0.6, 0.8, 0.9])
    assert load["recorded"] and load["quiet"] and load["balanced"] and load["reliable"]
    assert load["reason"] is None and load["median_a"] == 0.7


def test_assess_load_busy_machine_is_not_reliable_and_says_why():
    load = bs.assess_load([4.0, 4.5, 3.9], [4.2, 4.4, 4.1])
    assert not load["reliable"] and "busy" in load["reason"] and "2" in load["reason"]


def test_assess_load_arms_under_different_load_are_not_reliable():
    load = bs.assess_load([0.2, 0.3, 0.2], [1.9, 1.8, 1.9])    # both quiet, 1.6 apart
    assert load["quiet"] and not load["balanced"] and not load["reliable"]
    assert "different load" in load["reason"]


def test_assess_load_missing_record_is_a_finding_not_an_error():
    load = bs.assess_load([0.5, None], [0.5, 0.6])
    assert not load["recorded"] and not load["reliable"] and "not recorded" in load["reason"]
    assert bs.assess_load([], [])["reliable"] is False


# ---- the decision rule ------------------------------------------------------------

def separated(low, high, n=8, jitter=0.0005):
    return ([low + i * jitter for i in range(n)], [high + i * jitter for i in range(n)])


def build_family(series, **metrics):
    return [bs.metric_test(key, a, b, series=series) for key, (a, b) in metrics.items()]


QUIET = {"s": {"recorded": True, "reliable": True, "reason": None}}


def test_decide_flags_a_large_wer_regression_and_is_suspected_not_confirmed():
    a, b = separated(0.25, 0.35)
    flat = [1.0 + i * 0.001 for i in range(8)]
    result = bs.decide(build_family("s", wer=(a, b), rtf=(flat, list(flat))), load=QUIET)
    wer = next(t for t in result["tests"] if t["key"] == "wer")
    assert wer["status"] == "regression" and wer["p_holm"] < bs.ALPHA
    assert next(t for t in result["tests"] if t["key"] == "rtf")["status"] == "not-significant"
    assert "SUSPECTED REGRESSION" in result["headline"] and "CONFIRMED" not in result["headline"]
    assert "second" in result["headline"]


def test_decide_does_not_flag_fourteen_p_values_of_0_04_that_a_naive_reading_would():
    # Fourteen independent metrics each at p = 0.04: the chance that at least one is below
    # 0.05 by luck is 1 - 0.95^14 = 51%. After Holm none is.
    flat = [1.0 + i * 0.001 for i in range(8)]
    keys = ["wer", "hyp_words", "rtf", "live.dropped_hops", "live.forced_commits",
            "live.unagreed_tail_words", "live.mean_decode_rtf", "live.infer_ms_per_hop",
            "live.commit_latency_median_ms"] * 2
    tests = [bs.metric_test(k, flat, [x + 0.5 for x in flat], series=f"s{i}", p=0.04, p_method="given")
             for i, k in enumerate(keys[:14])]
    assert all(t["p"] < bs.ALPHA for t in tests)                     # naive: all "significant"
    result = bs.decide(tests)
    assert result["flagged"] == [] and result["family_size"] == 14
    assert all(t["status"] == "not-significant" for t in result["tests"])


def test_decide_significant_but_below_the_floor_is_not_flagged():
    a, b = separated(0.250, 0.255)            # a 0.5-point difference, completely separated
    result = bs.decide(build_family("s", wer=(a, b)), load=QUIET)
    t = result["tests"][0]
    assert t["p_holm"] < bs.ALPHA and not t["floor_met"] and t["status"] == "below-floor"
    assert result["flagged"] == []


def test_decide_refuses_below_the_minimum_n():
    a, b = separated(0.25, 0.60, n=7)
    result = bs.decide(build_family("s", wer=(a, b)), load=QUIET)
    assert result["tests"][0]["status"] == "no-verdict" and result["headline"].startswith("NO VERDICT")


def test_decide_refuses_arms_that_were_not_interleaved():
    a, b = separated(0.25, 0.60)
    result = bs.decide(build_family("s", wer=(a, b)), interleaved=False)
    assert result["tests"][0]["status"] == "no-verdict" and "not interleaved" in result["headline"]


def test_decide_timing_difference_needs_a_quiet_balanced_machine():
    a, b = separated(0.90, 1.10, jitter=0.001)       # +22% RTF, completely separated
    unrecorded = bs.decide(build_family("s", rtf=(a, b)))
    t = unrecorded["tests"][0]
    assert t["status"] == "indicative" and t["would_be"] == "regression"
    assert unrecorded["flagged"] == [] and "INDICATIVE ONLY" in unrecorded["headline"]
    busy = bs.decide(build_family("s", rtf=(a, b)),
                     load={"s": bs.assess_load([5.0] * 8, [5.0] * 8)})
    assert busy["tests"][0]["status"] == "indicative" and "busy" in busy["tests"][0]["load_reason"]
    quiet = bs.decide(build_family("s", rtf=(a, b)), load={"s": bs.assess_load([0.4] * 8, [0.5] * 8)})
    assert quiet["tests"][0]["status"] == "regression"
    # A WER difference never needs a load record:
    wa, wb = separated(0.25, 0.35)
    assert bs.decide(build_family("s", wer=(wa, wb)))["tests"][0]["status"] == "regression"


def test_decide_improvement_and_the_neutral_metric_direction():
    a, b = separated(0.35, 0.25)
    assert bs.decide(build_family("s", wer=(a, b)))["tests"][0]["status"] == "improvement"
    words_a, words_b = separated(100, 120, jitter=0.1)
    assert bs.decide(build_family("s", hyp_words=(words_a, words_b)))["tests"][0]["status"] == "changed"


def test_decide_untested_metrics_stay_out_of_the_family():
    a, b = separated(6000, 7000, jitter=1)
    result = bs.decide(build_family("s", decode_ms=(a, b), wer=separated(0.25, 0.25)))
    assert next(t for t in result["tests"] if t["key"] == "decode_ms")["status"] == "untested"
    assert result["family_size"] == 1


def test_confirm_requires_the_same_metric_in_the_same_direction_again():
    a, b = separated(0.25, 0.35)
    first = bs.decide(build_family("s", wer=(a, b)), load=QUIET)
    same = bs.decide(build_family("s", wer=separated(0.26, 0.36)), load=QUIET)
    assert [r["label"] for r in bs.confirm(first, same["tests"])["confirmed"]] == ["WER"]
    flipped = bs.decide(build_family("s", wer=separated(0.36, 0.26)), load=QUIET)
    assert bs.confirm(first, flipped["tests"])["confirmed"] == []          # opposite direction
    flat = [0.3 + i * 0.001 for i in range(8)]
    quiet = bs.decide(build_family("s", wer=(flat, list(flat))), load=QUIET)
    result = bs.confirm(first, quiet["tests"])
    assert result["confirmed"] == [] and not result["not_reproduced"][0]["reproduced"]
    missing = bs.confirm(first, [])                                          # metric absent in session 2
    assert missing["confirmed"] == [] and len(missing["not_reproduced"]) == 1


def test_metric_test_floor_is_the_larger_of_absolute_and_relative():
    # words: floor 4 words and 3% of the baseline median (120 -> 3.6): the larger, 4.
    assert not bs.metric_test("hyp_words", [120] * 8, [123] * 8)["floor_met"]
    assert bs.metric_test("hyp_words", [120] * 8, [124] * 8)["floor_met"]
    # RTF: 5% of the baseline median.
    assert not bs.metric_test("rtf", [1.0] * 8, [1.04] * 8)["floor_met"]
    assert bs.metric_test("rtf", [1.0] * 8, [1.06] * 8)["floor_met"]


def test_decide_can_still_flag_a_completely_separated_metric_among_twenty_tests():
    # The reason the decision rule uses the rank sum: with 20 tests Holm needs p < 0.0025 for the
    # smallest one. Completely separated samples at n = 8 give 0.000155 under the rank sum (x 20 =
    # 0.0031, flagged) but 0.0031 under the difference of medians (x 20 = 0.062, NEVER flagged).
    flat = [1.0 + i * 0.001 for i in range(8)]
    a, b = separated(0.25, 0.35)
    tests = [bs.metric_test("wer", a, b, series="s0")]
    tests += [bs.metric_test("wer", flat, list(flat), series=f"s{i}") for i in range(1, 20)]
    result = bs.decide(tests)
    assert result["family_size"] == 20
    assert result["tests"][0]["status"] == "regression" and result["tests"][0]["p_holm"] < bs.ALPHA
    assert 20 * bs.permutation_p_value(a, b)[0] > bs.ALPHA       # the alternative could not have done it


def test_confirm_does_not_confirm_a_timing_result_from_a_busy_second_session():
    a, b = separated(0.90, 1.10, jitter=0.001)                 # +22% RTF, completely separated
    quiet = {"s": bs.assess_load([0.4] * 8, [0.5] * 8)}
    busy = {"s": bs.assess_load([6.0] * 8, [6.0] * 8)}
    first = bs.decide(build_family("s", rtf=(a, b)), load=quiet)
    assert first["tests"][0]["status"] == "regression"
    second = bs.decide(build_family("s", rtf=separated(0.91, 1.11, jitter=0.001)), load=busy)
    assert second["tests"][0]["status"] == "indicative"        # the second session does not believe it ...
    result = bs.confirm(first, second["tests"], load=busy)
    assert result["confirmed"] == []                           # ... so it cannot confirm it (it used to)
    assert "not quiet" in result["not_reproduced"][0]["why_not"]
    again = bs.confirm(first, second["tests"], load=quiet)     # the same numbers on a quiet machine do
    assert [r["label"] for r in again["confirmed"]] == ["RTF"]


def test_confirm_counts_a_flagged_metric_the_second_session_could_not_test():
    # Two metrics flagged in session 1; session 2 can test only one of them. Holm over BOTH
    # (the missing one with p = 1) doubles the surviving p-value instead of leaving it alone.
    a, b = separated(0.25, 0.35)
    wa, wb = separated(100, 130, jitter=0.1)
    first = bs.decide(build_family("s", wer=(a, b), hyp_words=(wa, wb)), load=QUIET)
    assert {t["key"] for t in first["flagged"]} == {"wer", "hyp_words"}
    second = bs.decide(build_family("s", wer=separated(0.26, 0.36)), load=QUIET)
    result = bs.confirm(first, second["tests"], load=QUIET)
    wer = next(r for r in result["results"] if r["label"] == "WER")
    raw = next(t for t in second["tests"] if t["key"] == "wer")["p"]
    assert wer["second_p_holm"] == pytest.approx(2 * raw) and wer["reproduced"]
    missing = next(r for r in result["results"] if r["key"] == "hyp_words")
    assert not missing["reproduced"] and "no usable test" in missing["why_not"]
