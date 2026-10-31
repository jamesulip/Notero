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

What decides a regression claim across MANY metrics lives in `decide()` below
(one place, shared by `bench_runs.py compare` and `regress.py`). Its constants
are justified, and its false-positive rate measured, in docs/BENCHMARKS.md and
`eval/baselines/aa-calibration.json`.
"""

from __future__ import annotations

import functools
import itertools
import math
import random
from typing import Sequence

#: Below this many successful runs per arm, `verdict` refuses to call anything
#: significant OR not significant. Eight runs of the baseline already spanned
#: 25% to 57% WER, and one collapsed window is the dominant source of noise.
MIN_RUNS_FOR_VERDICT = 8

#: A run is "collapsed" when its WER is more than this many WER points (0.15 = 15
#: points) above the REFERENCE LEVEL, the median of the best half of the runs
#: being judged (pooled over both arms of a comparison) ...
#:
#: Why an ADDITIVE margin and not the old "2x the best-half median". At a typical
#: level of 30% WER the old threshold was 60%, and the 57%-WER filler run of
#: baseline/offline/A (FINDINGS 15: Whisper invented "thank you for watching"
#: over a window) sat just under it and was never counted. Over the 80 successful
#: runs of the P6 baseline sessions the largest excess of a run that nobody calls
#: collapsed is +10.9 points and the smallest excess of a collapsed run is +26.2
#: points (the filler run); the next four collapsed runs are +26.2 .. +30.5.
#: 15 points sits in the middle of that empty gap, 4.1 points clear of the
#: noisy side. One lost 30 s window of this 128-word clip is about +25 points.
COLLAPSE_EXCESS = 0.15
#: ... or when it produced fewer than this fraction of the reference's words
#: (normal runs: >= 0.88 of the reference; truncated collapses: 0.57 .. 0.66) ...
COLLAPSE_MIN_WORD_FRACTION = 0.75
#: ... or when it contains an invented-filler phrase the reference does not
#: contain (the list is `bench_runs.FILLER_MARKERS`; a window that came back as
#: "thank you for watching" is collapsed whatever else the run got right).

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
    f"a run is COLLAPSED if its WER is more than {COLLAPSE_EXCESS * 100:g} points above the "
    f"reference level (the median of the best half, the ceil(n/2) lowest, of the runs judged, "
    f"pooled over both arms of a comparison), or if it produced fewer than "
    f"{COLLAPSE_MIN_WORD_FRACTION:.0%} of the reference's words, or if it contains an "
    f"invented-filler phrase the reference lacks"
)


def reference_level(*arms: Sequence[float]) -> float:
    """The WER level of "what this build does when it works": the best-half
    median of ALL the runs given, pooled. Pooling over both arms of a comparison
    makes the level symmetric (it does not depend on which arm is called
    baseline, so a permutation of the arm labels leaves it unchanged) and lets a
    candidate that is uniformly bad be judged against the baseline's good runs."""
    pooled = [value for arm in arms for value in arm]
    return best_half_median(pooled)


def collapse_reasons(wers: Sequence[float], hyp_words: Sequence[int], ref_words: int, *,
                     level: float | None = None, filler: Sequence[bool] | None = None,
                     wer_threshold: float | None = None) -> tuple[list[list[str]], float]:
    """For each run, why it is collapsed: a list of "wer", "words", "filler"
    (empty when it is not). Returns (reasons, WER threshold used).

    `level` is the reference level, `reference_level()` of whatever the caller
    pools; None means the series' own best-half median. `wer_threshold` sets the
    WER threshold directly (absolute) and overrides `level`."""
    if len(wers) != len(hyp_words):
        raise ValueError("wers and hyp_words differ in length")
    if filler is not None and len(filler) != len(wers):
        raise ValueError("filler and wers differ in length")
    if not wers:
        return [], float("nan")
    if wer_threshold is not None:
        threshold = wer_threshold
    else:
        threshold = (best_half_median(wers) if level is None else level) + COLLAPSE_EXCESS
    floor = COLLAPSE_MIN_WORD_FRACTION * ref_words
    reasons: list[list[str]] = []
    for i, (w, n) in enumerate(zip(wers, hyp_words)):
        why = []
        if w > threshold + _EPS:
            why.append("wer")
        if n < floor - _EPS:
            why.append("words")
        if filler is not None and filler[i]:
            why.append("filler")
        reasons.append(why)
    return reasons, threshold


def classify_collapsed(wers: Sequence[float], hyp_words: Sequence[int], ref_words: int, *,
                       level: float | None = None, filler: Sequence[bool] | None = None,
                       wer_threshold: float | None = None) -> tuple[list[bool], float]:
    """Flag the collapsed runs of one arm. Returns (flags, WER threshold used).
    See `collapse_reasons` for the arguments and `COLLAPSE_RULE` for the rule."""
    reasons, threshold = collapse_reasons(wers, hyp_words, ref_words, level=level,
                                          filler=filler, wer_threshold=wer_threshold)
    return [bool(r) for r in reasons], threshold


# --------------------------------------------------------------------------
# Difference of medians: permutation test and bootstrap interval
# --------------------------------------------------------------------------

def median_difference(a: Sequence[float], b: Sequence[float]) -> float:
    """median(b) - median(a). With a = baseline and b = candidate, a negative
    value means the candidate is lower (better, for WER and for time)."""
    return median(b) - median(a)


@functools.lru_cache(maxsize=16)
def _arrangements(n_a: int, n_b: int) -> tuple[tuple[tuple[int, ...], tuple[int, ...]], ...]:
    """Every split of the indices 0..n_a+n_b-1 into (group A, group B), both
    increasing. Cached: the table for 8 and 8 has 12,870 rows."""
    indices = range(n_a + n_b)
    rows = []
    for first in itertools.combinations(indices, n_a):
        chosen = set(first)
        rows.append((first, tuple(i for i in indices if i not in chosen)))
    return tuple(rows)


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
        # Same C(n_a + n_b, n_a) arrangements as a plain loop over index subsets,
        # but on the SORTED pool, so that an increasing index tuple is already a
        # sorted group and its median is two table lookups. About 5x faster,
        # which is what lets the A/A calibration run thousands of comparisons.
        ordered = sorted(pooled)
        first_lo, first_hi = (n_a - 1) // 2, n_a // 2
        second_lo, second_hi = (n_b - 1) // 2, n_b // 2
        hits = 0
        for first, second in _arrangements(n_a, n_b):
            median_a = (ordered[first[first_lo]] + ordered[first[first_hi]]) / 2
            median_b = (ordered[second[second_lo]] + ordered[second[second_hi]]) / 2
            if abs(median_b - median_a) >= observed - _EPS:
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


def midranks(values: Sequence[float]) -> list[float]:
    """Ranks 1..N of the values, tied values sharing the mean of their ranks."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        shared = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks[order[k]] = shared
        i = j + 1
    return ranks


def rank_sum_p_value(a: Sequence[float], b: Sequence[float], *,
                     seed: int = DEFAULT_SEED, max_exact: int = MAX_EXACT_ARRANGEMENTS,
                     monte_carlo: int = MC_PERMUTATIONS) -> tuple[float, str]:
    """Two-sided p-value for H0: one distribution, with the RANK SUM of sample A
    as the test statistic (the Mann-Whitney / Wilcoxon rank-sum test, with its
    null distribution from permuting the actual midranks, so ties are exact).

    Why this is the significance test of `decide()` and not the difference of
    medians of `permutation_p_value`: at n = 8 against 8 the difference-of-medians
    statistic ties on so many arrangements that its smallest possible p is 0.0031
    even for two completely separated samples (40 of the 12,870 arrangements
    reach it). Holm's correction over 17 or more tests would then make a flag
    IMPOSSIBLE. The rank sum's smallest p is 2/12,870 = 0.00016. The difference of
    medians stays the EFFECT SIZE (and the floor is applied to it); only the
    significance test changes. Returns (p, method) as `permutation_p_value` does.
    """
    n_a, n_b = len(a), len(b)
    if n_a == 0 or n_b == 0:
        raise ValueError("both samples need at least one value")
    pooled = list(a) + list(b)
    ranks = midranks(pooled)
    expected = n_a * (n_a + n_b + 1) / 2
    observed = abs(sum(ranks[:n_a]) - expected)
    arrangements = math.comb(n_a + n_b, n_a)
    tolerance = 1e-9

    if arrangements <= max_exact:
        ordered = sorted(ranks)
        hits = 0
        for first, _ in _arrangements(n_a, n_b):
            if abs(sum([ordered[i] for i in first]) - expected) >= observed - tolerance:
                hits += 1
        return hits / arrangements, "exact"

    rng = random.Random(seed)
    work = list(ranks)
    hits = 0
    for _ in range(monte_carlo):
        rng.shuffle(work)
        if abs(sum(work[:n_a]) - expected) >= observed - tolerance:
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
    """DEPRECATED: the P6 single-metric verdict, kept for callers outside the harness.
    `bench_runs.py` and `regress.py` use `decide()`, which corrects over every metric.

    One plain sentence. It refuses below `MIN_RUNS_FOR_VERDICT` per arm and
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


# --------------------------------------------------------------------------
# The decision rule for MANY metrics (shared by bench_runs.py and regress.py)
# --------------------------------------------------------------------------
#
# One comparison reports a dozen metrics over several series, so "p < 0.05 on
# any of them" is wrong: with 14 independent tests the chance of at least one
# false hit is 1 - 0.95^14 = 51%. What this rule does instead, and why each part:
#
#   1. n >= MIN_RUNS_FOR_VERDICT per arm, in one interleaved session. Below it,
#      no verdict at all.
#   2. A per-metric two-sided permutation test on the rank sum (exact at n = 8 + 8;
#      why the rank sum and not the difference of medians: `rank_sum_p_value`).
#   3. Holm's step-down correction over EVERY tested metric of the report
#      together (all series, the collapsed-run tests included), alpha = 0.05.
#      That controls the chance of any false flag at <= 5%, and it is uniformly
#      more powerful than Bonferroni.
#   4. An effect-size floor per metric (METRICS below): a difference smaller than
#      a person could act on is "significant but below the floor", not a flag.
#   5. TIMING metrics additionally need a quiet, balanced machine (`assess_load`).
#      Otherwise the difference is "indicative", never "real".
#   6. A flag from ONE session is SUSPECTED. It becomes CONFIRMED only when a
#      second, independent session reproduces the same metric in the same
#      direction (`confirm`). Results at n < 12 per arm need that second session
#      before anyone acts on them; at n >= 12 the second session is still the
#      rule for anything that will change a default.
#
# The false-positive rate of 1-6 together was measured on A/A comparisons: see
# docs/BENCHMARKS.md ("How often this harness cries wolf") and
# eval/baselines/aa-calibration.json, which `eval/calibrate_aa.py` regenerates.

#: Load average (1 minute, at launch) at or below which a run counts as "quiet".
#: Policy, not a fitted constant. The one observed case: the P6 live session at
#: median load 3.8-4.4 showed the instrumented binary 17% slower (replay RTF 1.003
#: against 0.859); the recheck at median 0.5-0.7 showed 1% (docs/BENCHMARKS.md).
#: Our own run puts about 1 on the load average, hence 2.0 rather than 1.0.
LOAD_QUIET_MEDIAN = 2.0
#: The two arms must not have run under different loads: a gap in median load
#: larger than this means one arm paid for somebody else's build.
LOAD_BALANCE_MAX = 1.0

#: The metrics a comparison reports. "kind": quality (an accuracy number),
#: count (a discrete counter), timing (needs `assess_load`), size (a word count).
#: "floor_abs" and "floor_rel": a difference of medians must reach BOTH to be
#: worth acting on (the second is a fraction of the baseline median). "scale" and
#: "unit" are for printing. Lower is better for every metric here except
#: "words", which is a sanity check, so its direction is "neutral".
METRICS: dict[str, dict] = {
    "wer": {"label": "WER", "kind": "quality", "better": "lower",
            "floor_abs": 0.02, "floor_rel": 0.0, "scale": 100.0, "unit": "%"},
    "hyp_words": {"label": "words (normalized)", "kind": "size", "better": "neutral",
                  "floor_abs": 4.0, "floor_rel": 0.03, "scale": 1.0, "unit": ""},
    "rtf": {"label": "RTF", "kind": "timing", "better": "lower",
            "floor_abs": 0.0, "floor_rel": 0.05, "scale": 1.0, "unit": ""},
    "decode_ms": {"label": "decodeMs", "kind": "timing", "better": "lower",
                  "floor_abs": 0.0, "floor_rel": 0.05, "scale": 1.0, "unit": " ms"},
    "live.dropped_hops": {"label": "dropped hops", "kind": "count", "better": "lower",
                          "floor_abs": 1.0, "floor_rel": 0.0, "scale": 1.0, "unit": ""},
    "live.forced_commits": {"label": "forced commits", "kind": "count", "better": "lower",
                            "floor_abs": 1.0, "floor_rel": 0.0, "scale": 1.0, "unit": ""},
    "live.unagreed_tail_words": {"label": "unagreed tail words", "kind": "count",
                                 "better": "lower", "floor_abs": 2.0, "floor_rel": 0.0,
                                 "scale": 1.0, "unit": ""},
    "live.mean_decode_rtf": {"label": "mean per-decode RTF", "kind": "timing", "better": "lower",
                             "floor_abs": 0.0, "floor_rel": 0.05, "scale": 1.0, "unit": ""},
    "live.infer_ms_per_hop": {"label": "infer ms per hop", "kind": "timing", "better": "lower",
                              "floor_abs": 0.0, "floor_rel": 0.05, "scale": 1.0, "unit": " ms"},
    "live.commit_latency_median_ms": {"label": "commit latency median", "kind": "timing",
                                      "better": "lower", "floor_abs": 0.0, "floor_rel": 0.10,
                                      "scale": 1.0, "unit": " ms"},
    "collapsed": {"label": "collapsed runs", "kind": "count", "better": "lower",
                  "floor_abs": 2.0, "floor_rel": 0.0, "scale": 1.0, "unit": ""},
    "der": {"label": "DER", "kind": "quality", "better": "lower",
            "floor_abs": 0.02, "floor_rel": 0.0, "scale": 100.0, "unit": "%"},
}
#: Metrics shown in a table for orientation but never tested: `decode_ms` is
#: `rtf` times the clip's length (the same test twice would double-count it).
UNTESTED_METRICS = frozenset({"decode_ms"})


def holm_adjust(p_values: Sequence[float | None]) -> list[float | None]:
    """Holm's step-down adjusted p-values (None stays None and is not counted).

    Sort the m tested p ascending; the i-th (1-based) is multiplied by (m - i + 1),
    then a running maximum keeps the adjusted values in the same order, and each
    is capped at 1. Rejecting every hypothesis whose adjusted p is below alpha
    keeps the probability of any false rejection at or below alpha, whatever
    the dependence between the tests."""
    indexed = [(p, i) for i, p in enumerate(p_values) if p is not None]
    indexed.sort()
    m = len(indexed)
    out: list[float | None] = [None] * len(p_values)
    running = 0.0
    for rank, (p, i) in enumerate(indexed):
        running = max(running, min(1.0, (m - rank) * p))
        out[i] = running
    return out


def assess_load(loads_a: Sequence[float | None], loads_b: Sequence[float | None]) -> dict:
    """Whether a timing difference may be believed, from the load average at the
    launch of each run. Never raises: a missing record is a finding, not an error."""
    known_a = [x for x in loads_a if x is not None]
    known_b = [x for x in loads_b if x is not None]
    recorded = bool(known_a and known_b) and len(known_a) == len(loads_a) \
        and len(known_b) == len(loads_b)
    out = {"recorded": recorded, "median_a": median(known_a) if known_a else None,
           "median_b": median(known_b) if known_b else None,
           "max_a": max(known_a) if known_a else None,
           "max_b": max(known_b) if known_b else None}
    if not recorded:
        out.update(quiet=False, balanced=False, reliable=False,
                   reason="the load average was not recorded for every run")
        return out
    quiet = out["median_a"] <= LOAD_QUIET_MEDIAN and out["median_b"] <= LOAD_QUIET_MEDIAN
    balanced = abs(out["median_a"] - out["median_b"]) <= LOAD_BALANCE_MAX
    reason = None
    if not quiet:
        reason = (f"the machine was busy: median load average {out['median_a']:.1f} (A) and "
                  f"{out['median_b']:.1f} (B) against a limit of {LOAD_QUIET_MEDIAN:g}")
    elif not balanced:
        reason = (f"the arms ran under different load: median {out['median_a']:.1f} (A) vs "
                  f"{out['median_b']:.1f} (B), more than {LOAD_BALANCE_MAX:g} apart")
    out.update(quiet=quiet, balanced=balanced, reliable=quiet and balanced, reason=reason)
    return out


def metric_test(key: str, a: Sequence[float], b: Sequence[float], *, series: str = "",
                seed: int = DEFAULT_SEED, p: float | None = None,
                p_method: str | None = None) -> dict:
    """One tested metric: the two samples, medians, difference, the floor, and the
    raw p-value (permutation, or the `p` the caller computed, e.g. Fisher)."""
    spec = METRICS[key]
    test = {"series": series, "key": key, "label": spec["label"], "kind": spec["kind"],
            "better": spec["better"], "n_a": len(a), "n_b": len(b),
            "a": describe(a), "b": describe(b), "diff": None, "rel_diff": None,
            "floor_abs": spec["floor_abs"], "floor_rel": spec["floor_rel"],
            "floor_met": False, "p": None, "p_method": None}
    if not a or not b:
        return test
    test["diff"] = median_difference(a, b)
    base = abs(test["a"]["median"])
    test["rel_diff"] = None if base < _EPS else test["diff"] / base
    needed = max(spec["floor_abs"], spec["floor_rel"] * base)
    test["floor_met"] = abs(test["diff"]) >= needed - _EPS and abs(test["diff"]) > _EPS
    if p is None:
        test["p"], test["p_method"] = rank_sum_p_value(a, b, seed=seed)
    else:
        test["p"], test["p_method"] = p, p_method or "given"
    return test


def decide(tests: Sequence[dict], *, load: dict[str, dict] | None = None,
           interleaved: bool = True, alpha: float = ALPHA,
           min_runs: int = MIN_RUNS_FOR_VERDICT) -> dict:
    """Apply the decision rule to a list of `metric_test` dicts (any number of
    series) and return {"tests": [... with p_holm and status], "flagged": [...],
    "counts": {...}, "headline": str}.

    `load` maps a series id to its `assess_load` dict; a TIMING test of a series
    without an entry is treated as unrecorded, hence indicative.

    status is one of
      "no-verdict"          n below the minimum, or arms not interleaved
      "untested"            no p-value (empty sample, or a descriptive-only metric)
      "not-significant"     Holm-adjusted p >= alpha. NOT evidence of equivalence.
      "below-floor"         significant, but smaller than the effect-size floor
      "indicative"          significant and above the floor, timing, machine not quiet
      "regression" / "improvement" / "changed"
                            significant and above the floor; "changed" for a metric
                            with no better direction (words)
    """
    load = load or {}
    out_tests = []
    eligible = []
    for t in tests:
        t = dict(t)
        small = min(t["n_a"], t["n_b"]) < min_runs
        if t["p"] is None or t["key"] in UNTESTED_METRICS:
            t["status"] = "untested"
        elif small or not interleaved:
            t["status"] = "no-verdict"
        else:
            eligible.append(t)
        out_tests.append(t)
    adjusted = holm_adjust([t["p"] for t in eligible])
    for t, p_holm in zip(eligible, adjusted):
        t["p_holm"] = p_holm
        if p_holm >= alpha:
            t["status"] = "not-significant"
        elif not t["floor_met"]:
            t["status"] = "below-floor"
        else:
            worse = (t["diff"] > 0) == (t["better"] == "lower")
            if t["better"] == "neutral":
                direction = "changed"
            else:
                direction = "regression" if worse else "improvement"
            if t["kind"] == "timing":
                assessed = load.get(t["series"])
                if not assessed or not assessed.get("reliable"):
                    t["status"] = "indicative"
                    t["load_reason"] = (assessed or {}).get("reason") or "no load record"
                    t["would_be"] = direction
                    continue
            t["status"] = direction
    flagged = [t for t in out_tests if t["status"] in ("regression", "improvement", "changed")]
    counts: dict[str, int] = {}
    for t in out_tests:
        counts[t["status"]] = counts.get(t["status"], 0) + 1
    return {"tests": out_tests, "flagged": flagged, "counts": counts, "alpha": alpha,
            "family_size": len(eligible), "interleaved": interleaved,
            "headline": headline(out_tests, flagged, len(eligible), interleaved, min_runs)}


def headline(tests: Sequence[dict], flagged: Sequence[dict], family: int,
             interleaved: bool, min_runs: int) -> str:
    """One plain paragraph. SUSPECTED, never REAL: a single session cannot confirm."""
    if not interleaved:
        return ("NO VERDICT: the arms were not interleaved A/B in one session, so a "
                "difference may be machine drift or another process, not the build.")
    if tests and all(t["status"] in ("no-verdict", "untested") for t in tests):
        smallest = min((min(t["n_a"], t["n_b"]) for t in tests), default=0)
        return (f"NO VERDICT: the smallest arm has n = {smallest}; at least {min_runs} successful "
                f"runs per arm are required before anything may be called significant or not "
                f"significant. One run proves nothing (FINDINGS 15).")
    parts = []
    regressions = [t for t in flagged if t["status"] == "regression"]
    improvements = [t for t in flagged if t["status"] == "improvement"]
    changes = [t for t in flagged if t["status"] == "changed"]
    indicative = [t for t in tests if t["status"] == "indicative"]
    if flagged:
        for name, group in (("REGRESSION", regressions), ("IMPROVEMENT", improvements),
                            ("CHANGED", changes)):
            if group:
                parts.append(f"SUSPECTED {name} in " + ", ".join(
                    f"{t['series']}:{t['label']}" for t in group))
        parts.append("a single session cannot confirm: repeat it in a second interleaved "
                     "session (`regress.py --confirm-with THIS_REPORT.json`) before acting")
    else:
        parts.append(f"NO SIGNIFICANT DIFFERENCE in {family} tested metrics at alpha = {ALPHA} "
                     f"(Holm-corrected). This is NOT evidence that the builds are equivalent: "
                     f"at this n only large differences are visible")
    if indicative:
        parts.append("INDICATIVE ONLY, not believed (machine not quiet or load not recorded): "
                     + ", ".join(f"{t['series']}:{t['label']} ({t['would_be']})" for t in indicative))
    below = [t for t in tests if t["status"] == "below-floor"]
    if below:
        parts.append("significant but below the effect-size floor, so not flagged: "
                     + ", ".join(f"{t['series']}:{t['label']}" for t in below))
    return "; ".join(parts) + "."


def confirm(first: dict, second_tests: Sequence[dict], *, load: dict[str, dict] | None = None,
            alpha: float = ALPHA) -> dict:
    """Did a second session reproduce what the first one flagged?

    Only the metrics the first session flagged are tested again (the first session
    chose them; the second is a confirmatory test of those hypotheses), with Holm
    over that WHOLE set: a flagged metric the second session could not test counts
    with p = 1, so a missing metric never makes the others easier to confirm. A
    metric is REPRODUCED if the second session also gives p_holm < alpha, the same
    direction and clears the floor, and, for a TIMING metric, if the second session's
    machine was quiet and balanced too (`load` maps a series id to its `assess_load`).
    Anything else is NOT REPRODUCED, which for a build that really changed means the
    second session is short of power, and for a false flag means it was noise."""
    load = load or {}
    wanted = {(t["series"], t["key"]): t for t in first.get("flagged", [])}
    by_key = {(t["series"], t["key"]): t for t in second_tests
              if t["p"] is not None and min(t["n_a"], t["n_b"]) >= MIN_RUNS_FOR_VERDICT}
    keys = list(wanted)
    adjusted = holm_adjust([by_key[k]["p"] if k in by_key else 1.0 for k in keys])
    results = []
    for key, p_holm in zip(keys, adjusted):
        before, t = wanted[key], by_key.get(key)
        if t is None:
            results.append({"series": key[0], "key": key[1], "label": before["label"],
                            "first_diff": before["diff"], "second_diff": None,
                            "second_p_holm": None, "same_direction": False, "floor_met": False,
                            "reproduced": False, "why_not": "the second session has no usable test of it"})
            continue
        same_direction = (t["diff"] > 0) == (before["diff"] > 0) and t["diff"] != 0
        quiet = True
        if t["kind"] == "timing":
            assessed = load.get(t["series"])
            quiet = bool(assessed and assessed.get("reliable"))
        reproduced = p_holm < alpha and same_direction and t["floor_met"] and quiet
        why = None
        if not reproduced:
            why = ("the second session's machine was not quiet and balanced" if not quiet and p_holm < alpha
                   and same_direction and t["floor_met"] else
                   "opposite direction" if not same_direction else
                   "below the effect-size floor" if not t["floor_met"] else
                   "not significant after Holm in the second session")
        results.append({"series": t["series"], "key": t["key"], "label": t["label"],
                        "first_diff": before["diff"], "second_diff": t["diff"],
                        "second_p_holm": p_holm, "same_direction": same_direction,
                        "floor_met": t["floor_met"], "reproduced": reproduced, "why_not": why})
    return {"results": results,
            "confirmed": [r for r in results if r["reproduced"]],
            "not_reproduced": [r for r in results if not r["reproduced"]]}
