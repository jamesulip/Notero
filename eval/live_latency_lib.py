"""Metrics and statistics for the live-latency experiment. Standard library only, no I/O.

`eval/live_latency.py` drives `transcribe --live --realtime --live-trace` and writes the
plan, the runs and the decision. Everything that turns one run's report into numbers, and
every number into a verdict, is in this file so that a test can pin it without a model.

What one run yields (`run_metrics`): when each committed word was committed and why (the
commit latency, on the wall clock and on the audio clock), the word errors against a
reference where one exists, the speech the transcript left out, the hallucinations, the
counters of the live decoder, the CPU it used and whether committed text was only ever
appended to.

What the statistics assume. A run is not independent of its clip: the same audio gives
similar latencies in every round. The unit of replication is therefore the ROUND within a
CLIP, and the bootstrap resamples rounds inside each clip (stratified), never words. The
clips are a fixed set, so an interval says how sure the effect is ON THESE CLIPS; whether
it carries to other recordings is argued from the spread between clips, which the report
prints. Nothing here uses a distributional assumption.
"""

from __future__ import annotations

import bisect
import itertools
import math
import random
import re
import statistics
from typing import Iterable, Sequence

from score import normalize

REASONS = ("agreed", "forced", "boundaryTail", "finish")

#: Phrases Whisper invents out of silence or a hostile window (the same list the bench
#: harness uses, written out so this file stands alone).
FILLER_MARKERS = (
    "thank you so much for watching",
    "thanks for watching",
    "thank you for watching",
    "please subscribe",
    "like and subscribe",
    "welcome to meeting",
    "thank goodness",
)


# --------------------------------------------------------------------------
# Words, alignment, errors
# --------------------------------------------------------------------------

def align(ref: Sequence[str], hyp: Sequence[str]) -> list[tuple[str, int | None, int | None]]:
    """Edit-distance alignment as a list of (op, ref index, hyp index), in order.

    op is 'ok', 'sub', 'del' or 'ins'. Ties prefer a match or substitution, then a
    deletion, then an insertion, so the split is deterministic. The total distance is the
    Levenshtein distance `score.py` computes; only the S/D/I split of ties can differ."""
    n, m = len(ref), len(hyp)
    # cost[i][j]: distance between ref[:i] and hyp[:j]
    cost = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        cost[i][0] = i
    for j in range(1, m + 1):
        cost[0][j] = j
    for i in range(1, n + 1):
        row, prev = cost[i], cost[i - 1]
        ri = ref[i - 1]
        for j in range(1, m + 1):
            diagonal = prev[j - 1] + (0 if ri == hyp[j - 1] else 1)
            row[j] = min(diagonal, prev[j] + 1, row[j - 1] + 1)
    ops: list[tuple[str, int | None, int | None]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and cost[i][j] == cost[i - 1][j - 1] + (0 if ref[i - 1] == hyp[j - 1] else 1):
            ops.append(("ok" if ref[i - 1] == hyp[j - 1] else "sub", i - 1, j - 1))
            i, j = i - 1, j - 1
        elif i > 0 and cost[i][j] == cost[i - 1][j] + 1:
            ops.append(("del", i - 1, None))
            i -= 1
        else:
            ops.append(("ins", None, j - 1))
            j -= 1
    ops.reverse()
    return ops


def error_counts(ops: Iterable[tuple[str, int | None, int | None]]) -> dict:
    counts = {"ok": 0, "sub": 0, "del": 0, "ins": 0}
    for op, _, _ in ops:
        counts[op] += 1
    return counts


def token_words(tokens: Sequence[dict]) -> tuple[list[str], list[int]]:
    """The normalized words of a token list and, for each, the index of its token. A token
    can hold two words ('i-send' splits) or none (punctuation), so the two lists differ in
    length."""
    words: list[str] = []
    owner: list[int] = []
    for index, token in enumerate(tokens):
        for word in normalize(token.get("text", "")):
            words.append(word)
            owner.append(index)
    return words, owner


# --------------------------------------------------------------------------
# Commit latency
# --------------------------------------------------------------------------

def quantile(values: Sequence[float], q: float) -> float:
    """Linear-interpolated quantile, q in [0, 1]."""
    if not values:
        raise ValueError("quantile of nothing")
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    position = q * (len(ordered) - 1)
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def commit_words(trace: dict) -> list[dict]:
    """One record per committed word, in commit order: its end on the session timeline,
    the wall and audio clocks when it was committed, and why."""
    words: list[dict] = []
    for commit in trace["commits"]:
        reason = commit["reason"]
        for end, start in zip(commit["wordEndMs"], commit["wordStartMs"]):
            words.append({"end": end, "start": start, "wall": commit["wallMs"],
                          "audio": commit["audioFedMs"], "reason": reason})
    return words


def latency_summary(values: Sequence[float]) -> dict | None:
    if not values:
        return None
    return {"n": len(values), "median": quantile(values, 0.5), "p90": quantile(values, 0.9),
            "p95": quantile(values, 0.95), "mean": statistics.fmean(values), "max": max(values)}


# --------------------------------------------------------------------------
# Hallucinations, repeats, omissions
# --------------------------------------------------------------------------

def count_loops(words: Sequence[str], *, min_repeats: int = 4, max_unit: int = 3) -> int:
    """Maximal runs in which a unit of 1..max_unit words repeats at least `min_repeats`
    times in a row ("hello hello hello hello", "ano ba ano ba ano ba ano ba"). Each run
    counts once, as its shortest unit."""
    n = len(words)
    i = 0
    found = 0
    while i < n:
        best_end = None
        for unit in range(1, max_unit + 1):
            if i + unit * min_repeats > n:
                continue
            block = list(words[i:i + unit])
            repeats = 1
            j = i + unit
            while j + unit <= n and list(words[j:j + unit]) == block:
                repeats += 1
                j += unit
            if repeats >= min_repeats:
                best_end = j
                break
        if best_end is None:
            i += 1
        else:
            found += 1
            i = best_end
    return found


def count_repeats(words: Sequence[str], *, max_unit: int = 4) -> int:
    """Places where a unit of 1..max_unit words is immediately said again ("the the",
    "ano ba ano ba"). Informational: speakers repeat themselves, so it is read against the
    reference's own count, not against zero."""
    n = len(words)
    found = 0
    i = 0
    while i < n:
        hit = 0
        for unit in range(1, max_unit + 1):
            if i + 2 * unit <= n and list(words[i:i + unit]) == list(words[i + unit:i + 2 * unit]):
                hit = unit
                break
        if hit:
            found += 1
            i += 2 * hit
        else:
            i += 1
    return found


def filler_hits(ref_words: Sequence[str] | None, hyp_words: Sequence[str]) -> int:
    """Occurrences of an invented-filler phrase in the hypothesis beyond those in the
    reference. Counts nothing when there is no word reference to compare with."""
    if ref_words is None:
        hyp_text = " ".join(hyp_words)
        return sum(hyp_text.count(m) for m in FILLER_MARKERS)
    ref_text, hyp_text = " ".join(ref_words), " ".join(hyp_words)
    return sum(max(0, hyp_text.count(m) - ref_text.count(m)) for m in FILLER_MARKERS)


def insertion_spans(ops: Sequence[tuple[str, int | None, int | None]], *, min_len: int = 6) -> int:
    """Runs of at least `min_len` consecutive inserted words: an invented span."""
    spans = 0
    run = 0
    for op, _, _ in ops:
        if op == "ins":
            run += 1
        else:
            if run >= min_len:
                spans += 1
            run = 0
    if run >= min_len:
        spans += 1
    return spans


def merge_spans(spans: Iterable[Sequence[int]]) -> list[tuple[int, int]]:
    merged: list[list[int]] = []
    for start, end in sorted((int(s), int(e)) for s, e in spans if e > s):
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return [(a, b) for a, b in merged]


def missing_speech(ref_spans: Sequence[Sequence[int]], words: Sequence[dict], *,
                   pad_ms: int = 1000, frame_ms: int = 100) -> dict:
    """The share of reference speech time in which the transcript has no word.

    A 100 ms frame of reference speech counts as covered when some committed word lies
    within `pad_ms` of it (the model's word timings drift by a few hundred ms, and a word
    spoken over a stretch is evidence the stretch was heard). This finds omitted
    STRETCHES of speech; single deleted words are the deletion rate."""
    merged = merge_spans(ref_spans)
    total = 0
    uncovered = 0
    word_spans = sorted((w["start"], w["end"]) for w in words)
    starts = [s for s, _ in word_spans]
    # Running maximum of ends so "some word reaches the frame" is one lookup.
    reach: list[int] = list(itertools.accumulate((e for _, e in word_spans), max)) if word_spans else []
    for lo, hi in merged:
        t = lo
        while t < hi:
            frame_end = min(t + frame_ms, hi)
            total += frame_end - t
            # A word covers the frame if it starts by frame_end + pad and ends no earlier than t - pad.
            k = bisect.bisect_right(starts, frame_end + pad_ms) - 1
            covered = k >= 0 and reach[k] >= t - pad_ms
            if not covered:
                uncovered += frame_end - t
            t = frame_end
    return {"ref_ms": total, "missing_ms": uncovered,
            "share": (uncovered / total) if total else None}


def ghost_words(ref_spans: Sequence[Sequence[int]], words: Sequence[dict], *, pad_ms: int = 1000) -> int:
    """Committed words whose midpoint is more than `pad_ms` from any reference speech."""
    merged = merge_spans(ref_spans)
    count = 0
    for word in words:
        mid = (word["start"] + word["end"]) // 2
        if not any(lo - pad_ms <= mid <= hi + pad_ms for lo, hi in merged):
            count += 1
    return count


# --------------------------------------------------------------------------
# One run
# --------------------------------------------------------------------------

#: Corpora whose word reference is clean enough that an inserted span means invention.
CLEAN_REFERENCE_CORPORA = ("fleurs",)


def run_metrics(report: dict, clip: dict, *, ref_words: Sequence[str] | None = None,
                ref_spans: Sequence[Sequence[int]] | None = None) -> dict:
    """Everything the experiment reads from one `transcribe --live --live-trace` report.

    `clip` is the clip's plan entry (corpus, durationMs, hasWordReference). `ref_words` is
    the normalized reference, None when the clip has none; `ref_spans` the reference speech
    in ms on the clip's timeline. No word of the hypothesis or reference is kept in the
    result."""
    trace = report.get("liveTrace")
    if trace is None:
        raise ValueError("the report has no liveTrace: run transcribe with --live-trace")
    live = report["live"]
    duration_ms = report["durationMs"]
    words = commit_words(trace)
    tokens = report.get("words", [])
    consistent = (len(tokens) == len(words)
                  and all(t["endMs"] == w["end"] for t, w in zip(tokens, words)))

    out: dict = {"duration_ms": duration_ms, "words_committed": len(words),
                 "tokens_match_commits": consistent}

    # Latency, wall (the machine included) and audio (the mechanism alone).
    wall = [w["wall"] - w["end"] for w in words]
    audio = [w["audio"] - w["end"] for w in words]
    out["latency_wall_ms"] = [round(x) for x in wall]
    out["latency_audio_ms"] = [int(x) for x in audio]
    out["reason"] = [REASONS.index(w["reason"]) for w in words]
    out["latency_wall"] = latency_summary(wall)
    out["latency_audio"] = latency_summary(audio)
    out["by_reason"] = {}
    for reason in REASONS:
        picked = [w["wall"] - w["end"] for w in words if w["reason"] == reason]
        out["by_reason"][reason] = {"words": len(picked),
                                    "median_wall_ms": quantile(picked, 0.5) if picked else None}

    # Decoder counters.
    attempts = live["hops"] + live["failedHops"] + live["droppedHops"]
    out["hops"] = live["hops"]
    out["attempts"] = attempts
    out["dropped_hops"] = live["droppedHops"]
    out["dropped_rate"] = (live["droppedHops"] / attempts) if attempts else 0.0
    out["skipped_silent"] = live["skippedSilent"]
    out["empty_hypotheses"] = live["emptyResults"]
    out["failed_hops"] = live["failedHops"]
    out["forced_commits"] = live["forcedCommits"]
    out["boundaries"] = live["boundaries"]
    out["finalizations"] = live["finalizations"]
    out["finalizations_abandoned"] = live["finalizationsAbandoned"]
    out["unagreed_tail_words"] = live["unagreedTailCommits"]
    out["hallucinations_dropped_by_decoder"] = live["hallucinationsDropped"]
    out["head_skips"] = live.get("headSkips", 0)
    out["head_skipped_words"] = live.get("headSkippedWords", 0)
    out["duplicates_dropped"] = live["duplicatesDropped"]

    # Finalization: from the VAD hearing speech end to the tail being committed. Only
    # meaningful when the replay ran at the speed of the audio.
    if trace.get("realtime"):
        fin = [b["wallMs"] - b["speechEndMs"] for b in trace["boundaries"] if b["speechEndMs"] > 0]
        out["finalization_latency_ms"] = [round(x) for x in fin]
        out["finalization"] = latency_summary(fin)
    else:
        out["finalization_latency_ms"] = []
        out["finalization"] = None

    # Cost.
    minutes = duration_ms / 60000
    out["cpu_s_per_audio_min"] = (trace["cpu"]["userMs"] + trace["cpu"]["systemMs"]) / 1000 / minutes
    out["infer_rtf"] = live["totalInferMs"] / duration_ms if duration_ms else None
    decodes = trace["decodes"]
    out["decodes"] = len(decodes)
    out["decodes_per_min"] = len(decodes) / minutes
    out["mean_window_ms"] = statistics.fmean(d["windowMs"] for d in decodes) if decodes else None
    out["decode_wall_median_ms"] = quantile([d["totalMs"] for d in decodes], 0.5) if decodes else None
    out["decode_wall_p90_ms"] = quantile([d["totalMs"] for d in decodes], 0.9) if decodes else None
    out["replay_overrun_ms"] = trace["replayWallMs"] - duration_ms
    out["vad_max_lag_ms"] = trace["vad"]["maxLagMs"]
    out["vad_failures"] = trace["vad"]["failed"]

    # The append-only invariant.
    inv = trace["invariants"]
    out["invariant_violations"] = len(inv["violations"])
    out["invariant_kinds"] = sorted({v["kind"] for v in inv["violations"]})
    out["invariant_words_checked"] = inv["words"]

    # Omissions, in time.
    if ref_spans is not None:
        ms = missing_speech(ref_spans, words)
        out["missing_speech_share"] = ms["share"]
        out["missing_speech_ms"] = ms["missing_ms"]
        out["ref_speech_ms"] = ms["ref_ms"]
        out["ghost_words"] = ghost_words(ref_spans, words)
    else:
        out["missing_speech_share"] = None
        out["ghost_words"] = None

    # Words against the reference.
    hyp_words, owner = token_words(tokens)
    out["hyp_words"] = len(hyp_words)
    loops = count_loops(hyp_words)
    fillers = filler_hits(ref_words, hyp_words)
    if ref_words is not None:
        ops = align(ref_words, hyp_words)
        counts = error_counts(ops)
        n = len(ref_words)
        out.update(ref_words=n, subs=counts["sub"], dels=counts["del"], ins=counts["ins"],
                   wer=(counts["sub"] + counts["del"] + counts["ins"]) / n if n else None,
                   deletion_rate=counts["del"] / n if n else None)
        ref_loops = count_loops(ref_words)
        loops = max(0, loops - ref_loops)
        invented = insertion_spans(ops) if clip.get("corpus") in CLEAN_REFERENCE_CORPORA else 0
        out["repeat_excess"] = count_repeats(hyp_words) - count_repeats(ref_words)
        # Which kind of commit made which errors: attribute each hypothesis word to its token.
        reason_of_token = [w["reason"] for w in words] if consistent else None
        by = {r: {"ok": 0, "sub": 0, "ins": 0} for r in REASONS}
        if reason_of_token is not None:
            for op, _, hyp_index in ops:
                if hyp_index is None:
                    continue
                token_index = owner[hyp_index]
                if token_index < len(reason_of_token):
                    by[reason_of_token[token_index]][op] += 1
        out["errors_by_reason"] = by
    else:
        invented = 0
        out.update(ref_words=None, subs=None, dels=None, ins=None, wer=None, deletion_rate=None,
                   repeat_excess=None, errors_by_reason=None)
    out["repeats"] = count_repeats(hyp_words)
    out["hallucination_fillers"] = fillers
    out["hallucination_loops"] = loops
    out["hallucination_invented_spans"] = invented
    out["hallucinations_critical"] = fillers + loops + invented
    return out


# --------------------------------------------------------------------------
# Statistics
# --------------------------------------------------------------------------

def reduction(logs: Sequence[float]) -> float | None:
    """1 - exp(mean log ratio): the relative reduction as a geometric mean over blocks."""
    return (1 - math.exp(statistics.fmean(logs))) if logs else None


def run_quantiles(block: Sequence[Sequence[float]], q: float) -> list[float | None]:
    """One quantile of each run's word latencies in a block; None for a run with no words."""
    return [quantile(run, q) if run else None for run in block]


def log_ratio(values: Sequence[float | None], observed: int) -> float | None:
    """ln(observed run's quantile / mean of the other runs' quantiles) in one block."""
    mine = values[observed]
    others = [v for j, v in enumerate(values) if j != observed and v is not None]
    if mine is None or mine <= 0 or not others:
        return None
    base = statistics.fmean(others)
    return math.log(mine / base) if base > 0 else None


def randomization_test(blocks: Sequence[Sequence[Sequence[float]]], observed: int, *,
                       quantiles: Sequence[float] = (0.5,), resamples: int = 10_000,
                       seed: int = 20261102, two_sided: bool = False) -> dict:
    """Exact-size test of 'the arms are the same'.

    `blocks[b][j]` is the word latencies of run j of block b; run `observed` is the variant,
    the others are controls. The statistic is the relative reduction of a quantile of the
    commit latency, as the geometric mean over blocks of (the variant run's quantile / the mean
    of the controls' quantiles in the same block). A block is one clip in one round, its arms
    ran back to back in a seeded random order, so under 'no effect of the arm' any run of the
    block is as likely to have been the variant. Each permutation picks one run per block to
    play the variant and recomputes the statistic; the p-value is the share of permutations
    (the real arrangement included) at least as extreme as the real one. No distribution is
    assumed and it does not matter how few blocks there are. (A bootstrap over 3 to 4 rounds
    per clip was simulated first and covered a true null only 80% of the time.)

    Returns, per quantile, the observed reduction and the p-value."""
    rng = random.Random(seed)
    out: dict[float, dict] = {}
    for q in quantiles:
        table = [run_quantiles(block, q) for block in blocks]

        def stat(choice: Sequence[int]) -> float | None:
            logs = [log_ratio(row, c) for row, c in zip(table, choice)]
            return reduction([x for x in logs if x is not None])

        real = stat([observed] * len(table))
        hits = 1
        if real is not None:
            for _ in range(resamples):
                value = stat([rng.randrange(len(row)) for row in table])
                if value is None:
                    continue
                if (abs(value) >= abs(real) - 1e-12) if two_sided else (value >= real - 1e-12):
                    hits += 1
        out[q] = {"reduction": real, "p": hits / (resamples + 1), "resamples": resamples}
    return out


#: One-sided 95% and two-sided 95% critical values of Student's t, by degrees of freedom.
T95_ONE_SIDED = {1: 6.314, 2: 2.920, 3: 2.353, 4: 2.132, 5: 2.015, 6: 1.943, 7: 1.895, 8: 1.860, 9: 1.833,
                 10: 1.812, 11: 1.796, 12: 1.782, 13: 1.771, 14: 1.761, 15: 1.753, 16: 1.746, 17: 1.740,
                 18: 1.734, 19: 1.729, 20: 1.725, 22: 1.717, 24: 1.711, 26: 1.706, 28: 1.701, 30: 1.697}
T95_TWO_SIDED = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262,
                 10: 2.228, 11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 16: 2.120, 17: 2.110,
                 18: 2.101, 19: 2.093, 20: 2.086, 22: 2.074, 24: 2.064, 26: 2.056, 28: 2.048, 30: 2.042}


def t_critical(df: int, table: dict[int, float], limit: float) -> float:
    """The tabulated value at the largest df not above `df` (so slightly conservative between
    rows); `limit` (the normal quantile) from df 31 on."""
    if df > 30:
        return limit
    return table[max(k for k in table if k <= df)]


def block_reduction_interval(blocks: Sequence[Sequence[Sequence[float]]], observed: int, q: float = 0.5) -> dict | None:
    """The same reduction with a t-interval on the per-block log ratios.

    Blocks are the unit, so the interval carries the spread between clips as well as between
    rounds. That makes it wider than an interval conditional on these clips, and so safe to
    gate on. Reported as 1 - exp(mean +- t * se)."""
    logs = [x for x in (log_ratio(run_quantiles(block, q), observed) for block in blocks) if x is not None]
    n = len(logs)
    if n < 2:
        return None
    mean_ = statistics.fmean(logs)
    se = statistics.stdev(logs) / math.sqrt(n)
    one = t_critical(n - 1, T95_ONE_SIDED, 1.645)
    two = t_critical(n - 1, T95_TWO_SIDED, 1.960)
    return {"blocks": n, "reduction": 1 - math.exp(mean_),
            "ci95": [1 - math.exp(mean_ + two * se), 1 - math.exp(mean_ - two * se)],
            "lower95_one_sided": 1 - math.exp(mean_ + one * se),
            "per_block": [1 - math.exp(x) for x in logs]}


def sign_flip_p(deltas: Sequence[float], *, alternative: str = "greater", seed: int = 20261102,
                max_exact: int = 18, mc: int = 100_000) -> float | None:
    """Randomization test of paired differences: under 'no effect' each block's difference
    is as likely to carry either sign (the arm order inside a block was randomized).
    The statistic is the mean. alternative 'greater' tests that the mean is above zero.
    Exact for up to `max_exact` blocks, seeded Monte Carlo above."""
    d = [x for x in deltas if x is not None]
    n = len(d)
    if n == 0:
        return None
    observed = sum(d)
    if all(x == 0 for x in d):
        return 1.0

    def extreme(total: float) -> bool:
        return total >= observed - 1e-12 if alternative == "greater" else total <= observed + 1e-12

    if n <= max_exact:
        hits = 0
        for signs in itertools.product((1, -1), repeat=n):
            if extreme(sum(s * x for s, x in zip(signs, d))):
                hits += 1
        return hits / 2 ** n
    rng = random.Random(seed)
    hits = 0
    for _ in range(mc):
        if extreme(sum(x if rng.random() < 0.5 else -x for x in d)):
            hits += 1
    return (hits + 1) / (mc + 1)


def bootstrap_mean_ci(values: Sequence[float], *, resamples: int = 4000, seed: int = 20261102) -> dict | None:
    d = [x for x in values if x is not None]
    if not d:
        return None
    rng = random.Random(seed)
    means = sorted(statistics.fmean(rng.choice(d) for _ in d) for _ in range(resamples))
    return {"mean": statistics.fmean(d), "n": len(d), "ci90": [quantile(means, 0.05), quantile(means, 0.95)],
            "ci95": [quantile(means, 0.025), quantile(means, 0.975)],
            "upper95_one_sided": quantile(means, 0.95)}


def holm(p_values: Sequence[float | None]) -> list[float | None]:
    """Holm's step-down adjusted p-values (None stays None and is not counted)."""
    indexed = sorted((p, i) for i, p in enumerate(p_values) if p is not None)
    m = len(indexed)
    out: list[float | None] = [None] * len(p_values)
    running = 0.0
    for rank, (p, i) in enumerate(indexed):
        running = max(running, min(1.0, (m - rank) * p))
        out[i] = running
    return out


def round_robin_schedule(items: Sequence[str], rounds: int, seed: int) -> list[list[str]]:
    """For each round a shuffled order of `items`. Seeded and independent of everything else."""
    rng = random.Random(seed)
    out = []
    for _ in range(rounds):
        order = list(items)
        rng.shuffle(order)
        out.append(order)
    return out


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
