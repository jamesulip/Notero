"""Statistics for A/B benchmark runs. Standard library only, no I/O.

Everything that decides whether a benchmark claim may be called significant is
in this file, so that it can be tested without a model, a Mac or a clock.
`bench_runs.py` runs the binaries and prints; this module only does arithmetic.

Why these tests and not a t-test. A WER sample from `transcribe` is not
Gaussian: on the synthetic clip eight identical runs gave 25% to 57%
(FINDINGS 15), because a window sometimes comes back as invented filler. That
is a mixture of "fine" and "collapsed". A mean and a standard error describe
such a sample badly, so:

  * the location statistic is the MEDIAN, with the IQR for spread;
  * the significance test for a difference of medians is a permutation test,
    exact when the number of arrangements is small, seeded Monte Carlo above;
  * the uncertainty of the difference is a seeded percentile bootstrap;
  * the collapse counts, a 2x2 table, get Fisher's exact test.

None of them assumes a distribution. All of them have little power at n=8, and
the verdict says so: "not significant" is never "equivalent".
"""

from __future__ import annotations

import itertools
import math
import random
from typing import Sequence

#: Below this many successful runs per arm, `verdict` refuses to call anything
#: significant OR not significant. Eight runs of the baseline already spanned
#: 25% to 57% WER, and one collapsed window is the dominant source of noise.
MIN_RUNS_FOR_VERDICT = 8

#: A run is "collapsed" when its WER is more than this multiple of the median
#: of the arm's best half of runs ...
COLLAPSE_WER_FACTOR = 2.0
#: ... or when it produced fewer than this fraction of the reference's words.
COLLAPSE_MIN_WORD_FRACTION = 0.75

#: A significant result with fewer runs than this per arm carries a warning to
#: repeat it. An A/A comparison of two byte-identical binaries at n = 8 came out
#: "significant" on WER (permutation p = 0.041; docs/BENCHMARKS.md), once in
#: one try: that cannot give a false-positive rate, but it shows what one
#: significant result at n = 8 is worth.
CONFIRM_BELOW_RUNS = 12

ALPHA = 0.05
#: Exact permutation enumerates every arrangement up to this many; above it,
#: Monte Carlo with `MC_PERMUTATIONS` seeded shuffles.
MAX_EXACT_ARRANGEMENTS = 250_000
MC_PERMUTATIONS = 100_000
BOOTSTRAP_RESAMPLES = 10_000
DEFAULT_SEED = 20261031

_EPS = 1e-12


# --------------------------------------------------------------------------
# Location and spread
# --------------------------------------------------------------------------

def quantile(values: Sequence[float], q: float) -> float:
    """Linear interpolation between order statistics (Hyndman and Fan type 7:
    the default of numpy and R, and of `RunStats.percentile` in the Swift
    benchmark code, so a number that crosses over means the same thing)."""
    if not values:
        raise ValueError("quantile of an empty sample")
    if not 0.0 <= q <= 1.0:
        raise ValueError("q must be within [0, 1]")
    ordered = sorted(values)
    position = q * (len(ordered) - 1)
    lower = math.floor(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def median(values: Sequence[float]) -> float:
    return quantile(values, 0.5)


def describe(values: Sequence[float]) -> dict | None:
    """n, median, min, max, q1, q3, iqr and mean; None for an empty sample."""
    if not values:
        return None
    q1, q3 = quantile(values, 0.25), quantile(values, 0.75)
    return {
        "n": len(values),
        "median": median(values),
        "min": min(values),
        "max": max(values),
        "q1": q1,
        "q3": q3,
        "iqr": q3 - q1,
        "mean": sum(values) / len(values),
    }


# --------------------------------------------------------------------------
# Collapsed runs
# --------------------------------------------------------------------------

def best_half_median(values: Sequence[float]) -> float:
    """Median of the best half of a sample, where lower is better.

    The best half is the ceil(n/2) lowest values, so for odd n the middle value
    belongs to it. The robust reference level for "what this arm does when it
    works", which a handful of collapsed runs cannot drag upward the way they
    drag the median."""
    if not values:
        raise ValueError("best-half median of an empty sample")
    ordered = sorted(values)
    return median(ordered[: math.ceil(len(ordered) / 2)])


COLLAPSE_RULE = (
    f"a run is COLLAPSED if its WER is more than {COLLAPSE_WER_FACTOR:g}x the median "
    f"WER of the arm's best half of runs (the ceil(n/2) lowest), or if it produced fewer "
    f"than {COLLAPSE_MIN_WORD_FRACTION:.0%} of the reference's words"
)


def classify_collapsed(wers: Sequence[float], hyp_words: Sequence[int], ref_words: int,
                       *, wer_threshold: float | None = None) -> tuple[list[bool], float]:
    """Flag the collapsed runs of one arm. Returns (flags, WER threshold used).

    With `wer_threshold=None` the threshold is the arm's own, the rule stated
    in `COLLAPSE_RULE`. Passing one lets the caller judge a second arm against
    the first arm's level, which catches an arm that is uniformly bad: judged
    only against itself, a candidate that collapses every run has no
    collapsed runs.
    """
    if len(wers) != len(hyp_words):
        raise ValueError("wers and hyp_words differ in length")
    if not wers:
        return [], float("nan")
    threshold = (COLLAPSE_WER_FACTOR * best_half_median(wers)
                 if wer_threshold is None else wer_threshold)
    floor = COLLAPSE_MIN_WORD_FRACTION * ref_words
    flags = [(w > threshold + _EPS) or (n < floor - _EPS) for w, n in zip(wers, hyp_words)]
    return flags, threshold


# --------------------------------------------------------------------------
# Difference of medians: permutation test and bootstrap interval
# --------------------------------------------------------------------------

def median_difference(a: Sequence[float], b: Sequence[float]) -> float:
    """median(b) - median(a). With a = baseline and b = candidate, a negative
    value means the candidate is lower (better, for WER and for time)."""
    return median(b) - median(a)


def permutation_p_value(a: Sequence[float], b: Sequence[float], *,
                        seed: int = DEFAULT_SEED,
                        max_exact: int = MAX_EXACT_ARRANGEMENTS,
                        monte_carlo: int = MC_PERMUTATIONS) -> tuple[float, str]:
    """Two-sided p-value for H0: the two samples come from one distribution,
    with the difference of medians as the test statistic.

    Returns (p, method). The method is "exact" when every one of the
    C(n_a + n_b, n_a) arrangements was enumerated, and otherwise
    "monte-carlo" with `monte_carlo` seeded shuffles and the (k+1)/(N+1)
    estimator, which is a valid p-value and never exactly zero.
    """
    n_a, n_b = len(a), len(b)
    if n_a == 0 or n_b == 0:
        raise ValueError("both samples need at least one value")
    pooled = list(a) + list(b)
    observed = abs(median_difference(a, b))
    arrangements = math.comb(n_a + n_b, n_a)

    if arrangements <= max_exact:
        hits = 0
        indices = range(n_a + n_b)
        for first in itertools.combinations(indices, n_a):
            chosen = set(first)
            group_a = [pooled[i] for i in first]
            group_b = [pooled[i] for i in indices if i not in chosen]
            if abs(median(group_b) - median(group_a)) >= observed - _EPS:
                hits += 1
        return hits / arrangements, "exact"

    rng = random.Random(seed)
    hits = 0
    work = list(pooled)
    for _ in range(monte_carlo):
        rng.shuffle(work)
        if abs(median(work[n_a:]) - median(work[:n_a])) >= observed - _EPS:
            hits += 1
    return (hits + 1) / (monte_carlo + 1), "monte-carlo"


def bootstrap_ci(a: Sequence[float], b: Sequence[float], *,
                 seed: int = DEFAULT_SEED, resamples: int = BOOTSTRAP_RESAMPLES,
                 alpha: float = ALPHA) -> tuple[float, float]:
    """Percentile bootstrap interval for median(b) - median(a), resampling each
    arm with replacement independently. Seeded, so the same inputs print the
    same interval."""
    if not a or not b:
        raise ValueError("both samples need at least one value")
    rng = random.Random(seed)
    diffs = []
    for _ in range(resamples):
        sample_a = [a[rng.randrange(len(a))] for _ in range(len(a))]
        sample_b = [b[rng.randrange(len(b))] for _ in range(len(b))]
        diffs.append(median(sample_b) - median(sample_a))
    return quantile(diffs, alpha / 2), quantile(diffs, 1 - alpha / 2)


# --------------------------------------------------------------------------
# Fisher's exact test
# --------------------------------------------------------------------------

def fisher_exact(a_hit: int, a_miss: int, b_hit: int, b_miss: int) -> float:
    """Two-sided Fisher exact p-value for the 2x2 table
    [[a_hit, a_miss], [b_hit, b_miss]].

    Sums the probability of every table with the same margins that is no more
    likely than the observed one, with a relative tolerance of 1e-7 for
    floating point, the same convention as scipy.stats.fisher_exact.
    """
    for cell in (a_hit, a_miss, b_hit, b_miss):
        if cell < 0:
            raise ValueError("cell counts must not be negative")
    row_a, row_b = a_hit + a_miss, b_hit + b_miss
    hits = a_hit + b_hit
    total = row_a + row_b
    if total == 0:
        return 1.0

    denominator = math.comb(total, hits)

    def probability(x: int) -> float:
        return math.comb(row_a, x) * math.comb(row_b, hits - x) / denominator

    low = max(0, hits - row_b)
    high = min(row_a, hits)
    observed = probability(a_hit)
    p = sum(prob for x in range(low, high + 1)
            if (prob := probability(x)) <= observed * (1 + 1e-7))
    return min(1.0, p)


# --------------------------------------------------------------------------
# The verdict
# --------------------------------------------------------------------------

def verdict(*, n_a: int, n_b: int, wer_diff: float | None, wer_p: float | None,
            wer_ci: tuple[float, float] | None, collapsed_a: int, collapsed_b: int,
            fisher_p: float | None, interleaved: bool = True,
            allow_non_interleaved: bool = False) -> str:
    """One plain sentence. It refuses below `MIN_RUNS_FOR_VERDICT` per arm and
    for runs that were not interleaved, and it never says "equivalent".

    `wer_diff` is median(candidate) - median(baseline) in WER points (a
    fraction here, 0.05 meaning five points); negative means the candidate is
    lower. A WER difference counts as significant only if the permutation test
    gives p < ALPHA AND the bootstrap interval excludes zero: the two methods
    must agree.
    """
    smallest = min(n_a, n_b)
    if smallest < MIN_RUNS_FOR_VERDICT:
        return (f"NO VERDICT: n = {n_a} baseline vs {n_b} candidate; at least "
                f"{MIN_RUNS_FOR_VERDICT} successful runs per arm are required before anything "
                f"here may be called significant or not significant. "
                f"One run proves nothing (FINDINGS 15).")
    if not interleaved and not allow_non_interleaved:
        return ("NO VERDICT: the two arms were not interleaved A/B in one session, so a "
                "difference may be machine drift or another process, not the build. "
                "Re-run with `bench_runs.py run --interleave BASE CAND`.")

    parts = []
    significant = False
    if wer_diff is None or wer_p is None or wer_ci is None:
        parts.append("WER: not computed")
    else:
        direction = "lower" if wer_diff < 0 else "higher" if wer_diff > 0 else "equal"
        ci_excludes_zero = wer_ci[0] > 0 or wer_ci[1] < 0
        if wer_p < ALPHA and ci_excludes_zero:
            significant = True
            parts.append(
                f"WER: candidate median is {abs(wer_diff) * 100:.1f} points {direction} "
                f"(permutation p = {wer_p:.3f}, 95% CI {wer_ci[0] * 100:+.1f} to "
                f"{wer_ci[1] * 100:+.1f}) — SIGNIFICANT at {ALPHA}")
        else:
            parts.append(
                f"WER: candidate median is {abs(wer_diff) * 100:.1f} points {direction} "
                f"(permutation p = {wer_p:.3f}, 95% CI {wer_ci[0] * 100:+.1f} to "
                f"{wer_ci[1] * 100:+.1f}) — not significant: the arms cannot be "
                f"distinguished at this n; that is not evidence they are equivalent")
    if fisher_p is None:
        parts.append("collapsed runs: not computed")
    else:
        rate = (f"{collapsed_a}/{n_a} baseline vs {collapsed_b}/{n_b} candidate "
                f"(Fisher exact p = {fisher_p:.3f})")
        significant = significant or fisher_p < ALPHA
        parts.append(f"collapsed runs: {rate} — "
                     + (f"SIGNIFICANT at {ALPHA}" if fisher_p < ALPHA else "not significant"))
    prefix = "" if interleaved else "NOT INTERLEAVED, treat as indicative only. "
    text = "VERDICT: " + prefix + "; ".join(parts) + "."
    if significant and smallest < CONFIRM_BELOW_RUNS:
        text += (f" CONFIRM BEFORE ACTING: with fewer than {CONFIRM_BELOW_RUNS} runs per arm one "
                 f"significant result is weak evidence. Repeat it in a second interleaved session. "
                 f"Two byte-identical binaries gave p = 0.041 on WER at n = 8 (docs/BENCHMARKS.md).")
    return text


def interleave_schedule(runs: int, scheme: str = "abab") -> list[str]:
    """The order in which two arms run: "abab" strictly alternates A B A B ...;
    "abba" alternates which arm goes first (A B, B A, A B, ...), which cancels
    a steady drift in thermals or background load that "abab" would charge to
    the second arm."""
    if runs < 1:
        raise ValueError("runs must be at least 1")
    if scheme == "abab":
        pair = ["A", "B"]
        return [arm for _ in range(runs) for arm in pair]
    if scheme == "abba":
        order: list[str] = []
        for i in range(runs):
            order += ["A", "B"] if i % 2 == 0 else ["B", "A"]
        return order
    raise ValueError(f"unknown interleave scheme: {scheme}")
