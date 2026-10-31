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


def test_collapse_rule_flags_the_filler_run_and_only_it():
    # FINDINGS 15 shape: seven runs near 26%, one at 57%. Best half (4 lowest)
    # has median 0.255, threshold 0.51; 0.57 is above it, 0.30 is not.
    wers = [0.25, 0.26, 0.25, 0.27, 0.26, 0.30, 0.255, 0.57]
    flags, threshold = bs.classify_collapsed(wers, [120] * 8, ref_words=123)
    assert threshold == pytest.approx(2 * bs.best_half_median(wers))
    assert flags == [False] * 7 + [True]


def test_collapse_rule_short_transcript_is_collapsed_even_at_low_wer():
    # 75% of 100 reference words is 75. 74 words is collapsed, 75 is not.
    flags, _ = bs.classify_collapsed([0.2, 0.2, 0.2], [74, 75, 100], ref_words=100)
    assert flags == [True, False, False]


def test_collapse_rule_boundary_is_strictly_greater_than_twice():
    # best half of [0.1, 0.1, 0.2, 0.3] is [0.1, 0.1] -> 0.1, threshold 0.2.
    # 0.2 is not MORE than 2x; 0.3 is.
    flags, threshold = bs.classify_collapsed([0.1, 0.1, 0.2, 0.3], [100] * 4, ref_words=100)
    assert threshold == pytest.approx(0.2)
    assert flags == [False, False, False, True]


def test_collapse_threshold_can_be_supplied_to_judge_a_second_arm():
    # An arm that is bad in every run has no collapsed run against itself ...
    uniformly_bad = [0.60, 0.61, 0.59, 0.60]
    own, _ = bs.classify_collapsed(uniformly_bad, [100] * 4, ref_words=100)
    assert own == [False] * 4
    # ... but is collapsed against a baseline whose threshold is 0.5.
    shared, threshold = bs.classify_collapsed(uniformly_bad, [100] * 4, ref_words=100,
                                              wer_threshold=0.5)
    assert threshold == 0.5 and shared == [True] * 4


def test_collapse_rule_text_states_the_numbers():
    assert "2x" in bs.COLLAPSE_RULE and "75%" in bs.COLLAPSE_RULE
    assert "best half" in bs.COLLAPSE_RULE


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
