"""The live-latency experiment: the metrics of one run, the statistics, the plan and the gate.

None of this needs a model. The real binary and the real corpora are exercised by the
sessions in eval/baselines/live-latency-2026-11-02/."""

import json
import math
import random
import sys
from pathlib import Path

import pytest

EVAL = Path(__file__).resolve().parents[1] / "eval"
sys.path.insert(0, str(EVAL))

import live_latency as lat  # noqa: E402
import live_latency_lib as ll  # noqa: E402
from score import levenshtein, normalize  # noqa: E402


# ---- words, alignment ----------------------------------------------------

def test_align_agrees_with_the_levenshtein_distance_of_score_py():
    rng = random.Random(7)
    vocab = ["ang", "mga", "ba", "po", "report", "bukas", "sige", "ok", "meeting", "na"]
    for _ in range(200):
        ref = [rng.choice(vocab) for _ in range(rng.randint(0, 25))]
        hyp = [rng.choice(vocab) for _ in range(rng.randint(0, 25))]
        counts = ll.error_counts(ll.align(ref, hyp))
        s, d, i = levenshtein(ref, hyp)
        assert counts["sub"] + counts["del"] + counts["ins"] == s + d + i
        assert counts["ok"] + counts["sub"] + counts["del"] == len(ref)
        assert counts["ok"] + counts["sub"] + counts["ins"] == len(hyp)


def test_align_known_answers():
    assert ll.align(["a", "b", "c"], ["a", "c"]) == [("ok", 0, 0), ("del", 1, None), ("ok", 2, 1)]
    assert ll.align(["a", "c"], ["a", "b", "c"]) == [("ok", 0, 0), ("ins", None, 1), ("ok", 1, 2)]
    assert ll.align(["a", "b", "c"], ["a", "x", "c"]) == [("ok", 0, 0), ("sub", 1, 1), ("ok", 2, 2)]
    assert ll.align([], ["a"]) == [("ins", None, 0)]
    assert ll.align(["a"], []) == [("del", 0, None)]


def test_a_token_that_splits_into_two_words_owns_both():
    words, owner = ll.token_words([{"text": " i-send"}, {"text": " ang"}, {"text": " ,"}, {"text": " po"}])
    assert words == ["i", "send", "ang", "po"]
    assert owner == [0, 0, 1, 3]


# ---- latency ---------------------------------------------------------------

def test_quantile_known_answers():
    assert ll.quantile([1, 2, 3, 4], 0.5) == 2.5
    assert ll.quantile([10], 0.9) == 10
    assert ll.quantile(list(range(101)), 0.95) == 95
    with pytest.raises(ValueError):
        ll.quantile([], 0.5)


def trace_of(commits, *, realtime=True, boundaries=(), decodes=None, dropped=0):
    return {"realtime": realtime, "replayWallMs": 20_000.0, "commits": commits,
            "boundaries": list(boundaries), "abandoned": [], "skippedSilent": 0, "dropped": [],
            "decodes": decodes if decodes is not None else [
                {"windowMs": 6000, "totalMs": 800.0}, {"windowMs": 8000, "totalMs": 1000.0}],
            "vad": {"batches": 10, "failed": 0, "maxLagMs": 3.0, "meanLagMs": 1.0},
            "cpu": {"userMs": 9000.0, "systemMs": 1000.0},
            "invariants": {"batches": len(commits), "words": sum(len(c["wordEndMs"]) for c in commits),
                           "violations": []}}


def commit(wall, audio, reason, ends, starts=None):
    starts = starts or [e - 300 for e in ends]
    return {"wallMs": wall, "audioFedMs": audio, "reason": reason, "wordEndMs": ends, "wordStartMs": starts}


def live_stats(**over):
    base = {"hops": 10, "failedHops": 0, "droppedHops": 2, "skippedSilent": 1, "emptyResults": 1,
            "forcedCommits": 1, "boundaries": 1, "finalizations": 1, "finalizationsAbandoned": 0,
            "unagreedTailCommits": 2, "hallucinationsDropped": 0, "duplicatesDropped": 0,
            "headSkips": 0, "headSkippedWords": 0, "totalInferMs": 6000}
    base.update(over)
    return base


def report_of(words, trace, **over):
    tokens = []
    for commit_ in trace["commits"]:
        for text_end in commit_["wordEndMs"]:
            tokens.append({"endMs": text_end})
    for token, text in zip(tokens, words):
        token["text"] = " " + text
        token["startMs"] = token["endMs"] - 300
    rep = {"durationMs": 15_000, "live": live_stats(), "liveTrace": trace, "words": tokens}
    rep.update(over)
    return rep


CLIP_TEXT = {"id": "c", "corpus": "fleurs"}
CLIP_SPEECH = {"id": "c", "corpus": "ami"}


def test_word_latencies_come_from_wall_and_audio_clocks_and_carry_their_reason():
    trace = trace_of([commit(4_000, 3_000, "agreed", [1_000, 1_500]),
                      commit(9_000, 8_000, "forced", [2_000]),
                      commit(15_000, 15_000, "boundaryTail", [12_000])])
    m = ll.run_metrics(report_of(["a", "b", "c", "d"], trace), CLIP_TEXT, ref_words=["a", "b", "c", "d"], ref_spans=[[0, 15_000]])
    assert m["latency_wall_ms"] == [3_000, 2_500, 7_000, 3_000]
    assert m["latency_audio_ms"] == [2_000, 1_500, 6_000, 3_000]
    assert m["reason"] == [0, 0, 1, 2]
    assert m["latency_wall"]["median"] == 3_000
    assert m["by_reason"]["forced"] == {"words": 1, "median_wall_ms": 7_000.0}
    assert m["wer"] == 0 and m["deletion_rate"] == 0
    assert m["tokens_match_commits"] is True


def test_decoder_counters_and_cost_are_read_from_the_report():
    trace = trace_of([commit(4_000, 3_000, "agreed", [1_000])])
    m = ll.run_metrics(report_of(["a"], trace), CLIP_TEXT, ref_words=["a"], ref_spans=[[0, 1_000]])
    assert m["attempts"] == 12 and m["dropped_hops"] == 2
    assert m["dropped_rate"] == pytest.approx(2 / 12)
    assert m["forced_commits"] == 1 and m["empty_hypotheses"] == 1
    assert m["cpu_s_per_audio_min"] == pytest.approx(10 / 0.25)
    assert m["infer_rtf"] == pytest.approx(0.4)
    assert m["decodes"] == 2 and m["mean_window_ms"] == 7000 and m["replay_overrun_ms"] == 5000


def test_finalization_latency_is_boundary_minus_speech_end_and_only_in_real_time():
    boundaries = [{"wallMs": 7_800.0, "audioMs": 7_700, "speechEndMs": 6_000}]
    trace = trace_of([commit(7_800, 7_700, "boundaryTail", [5_900])], boundaries=boundaries)
    m = ll.run_metrics(report_of(["a"], trace), CLIP_TEXT, ref_words=["a"], ref_spans=[[0, 6_000]])
    assert m["finalization_latency_ms"] == [1_800]
    awaited = ll.run_metrics(report_of(["a"], {**trace, "realtime": False}), CLIP_TEXT, ref_words=["a"],
                             ref_spans=[[0, 6_000]])
    assert awaited["finalization_latency_ms"] == [] and awaited["finalization"] is None


def test_a_report_without_the_trace_is_refused():
    with pytest.raises(ValueError):
        ll.run_metrics({"live": live_stats(), "durationMs": 1000}, CLIP_TEXT)


def test_errors_are_attributed_to_the_kind_of_commit_that_made_them():
    trace = trace_of([commit(4_000, 3_000, "agreed", [1_000, 1_500]),
                      commit(9_000, 8_000, "forced", [2_000, 2_500])])
    # ref: a b c d ; hyp: a X c d e? we have four tokens: a, x, c, d -> the substitution is in the forced... no, agreed
    words = ["a", "x", "c", "z"]
    m = ll.run_metrics(report_of(words, trace), CLIP_TEXT, ref_words=["a", "b", "c", "d"], ref_spans=[[0, 3_000]])
    assert m["subs"] == 2 and m["dels"] == 0 and m["ins"] == 0
    assert m["errors_by_reason"]["agreed"] == {"ok": 1, "sub": 1, "ins": 0}
    assert m["errors_by_reason"]["forced"] == {"ok": 1, "sub": 1, "ins": 0}


def test_nothing_of_the_transcript_is_kept_in_the_result():
    trace = trace_of([commit(4_000, 3_000, "agreed", [1_000, 1_500, 2_000])])
    secret = ["kumpidensyal", "ulat", "pangalan"]
    m = ll.run_metrics(report_of(secret, trace), CLIP_TEXT, ref_words=secret, ref_spans=[[0, 3_000]])
    blob = json.dumps(m)
    assert not any(word in blob for word in secret)


# ---- hallucinations, repeats, omissions ----------------------------------

def test_loops_need_four_repeats_and_count_a_run_once():
    assert ll.count_loops("hello hello hello hello".split()) == 1
    assert ll.count_loops("hello hello hello".split()) == 0
    assert ll.count_loops("ano ba ano ba ano ba ano ba sige".split()) == 1
    assert ll.count_loops(("x " * 9 + "y").split()) == 1
    assert ll.count_loops("a a a a b b b b".split()) == 2


def test_repeats_are_places_where_a_unit_is_said_again():
    assert ll.count_repeats("the the cat".split()) == 1
    assert ll.count_repeats("ano ba ano ba".split()) == 1
    assert ll.count_repeats("a b c d".split()) == 0


def test_filler_hits_count_only_what_the_reference_does_not_contain():
    hyp = "thank you for watching ang report thank you for watching".split()
    assert ll.filler_hits(["ang", "report"], hyp) == 2
    assert ll.filler_hits("thank you for watching".split(), hyp) == 1
    assert ll.filler_hits(None, hyp) == 2


def test_an_invented_span_is_six_inserted_words_in_a_row():
    ref = ["a", "b"]
    hyp = ["a"] + ["x"] * 6 + ["b"]
    assert ll.insertion_spans(ll.align(ref, hyp)) == 1
    assert ll.insertion_spans(ll.align(ref, ["a"] + ["x"] * 5 + ["b"])) == 0


def test_missing_speech_finds_a_stretch_with_no_word_near_it():
    words = [{"start": 0, "end": 900}, {"start": 1_000, "end": 1_900}]
    m = ll.missing_speech([[0, 2_000], [10_000, 12_000]], words)
    # the second span is 8 s from the last word: all 2 s of it are uncovered; the first is covered
    assert m["ref_ms"] == 4_000 and m["missing_ms"] == 2_000 and m["share"] == 0.5
    # a word within the 1 s pad covers the edge of a span
    near = ll.missing_speech([[2_500, 3_000]], words)
    assert near["missing_ms"] == 0


def test_ghost_words_lie_away_from_all_reference_speech():
    words = [{"start": 100, "end": 400}, {"start": 8_000, "end": 8_300}]
    assert ll.ghost_words([[0, 1_000]], words) == 1


def test_repeated_phrases_are_a_four_word_phrase_again_within_thirty_words():
    assert ll.repeated_phrases("a b c d x y a b c d z".split()) == 1
    assert ll.repeated_phrases("a b c d x y z".split()) == 0
    far = "a b c d " + " ".join(f"x{i}" for i in range(40)) + " a b c d"
    assert ll.repeated_phrases(far.split()) == 0
    assert ll.repeated_phrases("a b c d a b c d a b c d".split()) == 2


def test_an_omitted_segment_is_a_long_reference_turn_that_no_word_touches():
    words = [{"start": 100, "end": 500}, {"start": 6_200, "end": 6_500}]
    m = ll.omitted_segments([[0, 2_000], [3_000, 5_000], [6_000, 6_600], [8_000, 8_500]], words)
    # the third segment is under a second, the fourth too: two checked, one omitted
    assert m == {"checked": 2, "omitted": 1, "share": 0.5}
    # two speakers talking at once are two segments: dropping one is seen although speech continues
    assert ll.omitted_segments([[0, 3_000], [0, 3_000]], [{"start": 100, "end": 300}])["omitted"] == 0
    assert ll.omitted_segments([[0, 3_000], [10_000, 13_000]], [{"start": 100, "end": 300}])["omitted"] == 1


def test_segment_latency_is_anchored_on_the_end_of_the_reference_segment():
    words = [{"start": 100, "end": 900, "wall": 5_000}, {"start": 1_000, "end": 1_900, "wall": 6_000},
             {"start": 20_000, "end": 20_500, "wall": 21_000}]
    # the last word inside [0, 2000] was committed at 6000: 4000 after the segment ended
    assert ll.segment_latencies([[0, 2_000]], words) == [4_000]
    # a variant that shifts every word's timestamp 3 s later does not change it
    shifted = [{**w, "start": w["start"] + 3_000, "end": w["end"] + 3_000} for w in words[:2]]
    assert ll.segment_latencies([[0, 2_000]], shifted) == []   # the words left the segment: nothing is claimed
    assert ll.segment_latencies([[0, 500]], words) == []       # under a second


def test_an_empty_word_is_counted_and_a_run_with_no_words_still_scores():
    trace = trace_of([])
    m = ll.run_metrics(report_of([], trace), CLIP_TEXT, ref_words=["a", "b"], ref_spans=[[0, 3_000]])
    assert m["words_committed"] == 0 and m["wer"] == 1.0 and m["deletion_rate"] == 1.0
    assert m["latency_wall"] is None and m["missing_speech_share"] == 1.0
    assert m["segments_omitted"] == 1 and m["segment_latency_ms"] == []


def test_the_new_metrics_ride_along_with_every_run():
    trace = trace_of([commit(4_000, 3_000, "agreed", [1_000, 1_500, 2_000, 2_500, 9_000, 9_500, 10_000, 10_500])])
    words = ["a", "b", "c", "d", "x", "a", "b", "c"]
    rep = report_of(words, trace)
    rep["liveTrace"]["invariants"]["emptyWords"] = 2
    m = ll.run_metrics(rep, CLIP_SPEECH, ref_words=None, ref_spans=[[0, 3_000]])
    assert m["omitted_segment_share"] == 0.0 and m["segments_checked"] == 1
    assert m["segment_latency_ms"] == [1_000]
    assert m["invariant_words_match"] is True and m["empty_words"] == 2
    assert m["hallucination_repeated_phrases"] == 0 and m["hallucinations_critical"] == 0
    rep2 = report_of("a b c d x y a b c d".split(), trace_of([commit(4_000, 3_000, "agreed", [100 * i for i in range(1, 11)])]))
    assert ll.run_metrics(rep2, CLIP_SPEECH, ref_words=None, ref_spans=[[0, 3_000]])["hallucination_repeated_phrases"] == 1


# ---- statistics ------------------------------------------------------------

def test_log_ratio_and_reduction_known_answers():
    assert ll.reduction([math.log(0.7)] * 3) == pytest.approx(0.3)
    assert ll.reduction([math.log(0.5), math.log(2.0)]) == pytest.approx(0.0)   # a 2x gain and a 2x loss cancel
    assert ll.reduction([]) is None
    assert ll.log_ratio([100, 100, 70], 2) == pytest.approx(math.log(0.7))
    assert ll.log_ratio([100, 140, 60], 2) == pytest.approx(math.log(0.5))        # against the mean of the controls
    assert ll.log_ratio([None, 100, 50], 2) == pytest.approx(math.log(0.5))
    assert ll.log_ratio([100, 100, None], 2) is None


def test_a_bimodal_pool_does_not_move_the_headline():
    # Two clips, 3 s and 17 s, a 30% gain on each. The variant happens to commit more words on the
    # fast clip and the controls more on the slow one: pooled over words the "median" would claim
    # an 88% gain. Per block it is each clip's own median, and the reduction is the 30% built in.
    blocks = [[[3_000] * 100, [3_000] * 100, [2_100] * 300],
              [[17_000] * 300, [17_000] * 300, [11_900] * 100]]
    r = ll.randomization_test(blocks, 2, resamples=500, seed=1)[0.5]
    assert r["reduction"] == pytest.approx(0.3, abs=1e-9)
    pooled_c = [x for b in blocks for x in b[0] + b[1]]
    pooled_v = [x for b in blocks for x in b[2]]
    assert 1 - ll.quantile(pooled_v, 0.5) / ll.quantile(pooled_c, 0.5) == pytest.approx(0.876, abs=0.01)


def blocks_of(effect, *, clips=3, rounds=3, words=100, spread=0.15, run_shift=0.06, seed=1):
    """Blocks of [C0, C1, variant] latencies with the noise of real runs: each run shifts as a
    whole (the decoder is not deterministic) as well as each word differing from the next."""
    rng = random.Random(seed)
    out = []
    for c in range(clips):
        base = 3_000 + 1_000 * c
        for _ in range(rounds):
            runs = []
            for arm in ("C0", "C1", "V"):
                shift = 1 + rng.gauss(0, run_shift)
                scale = (1 - effect) if arm == "V" else 1.0
                runs.append([round(base * shift * scale * (1 + rng.gauss(0, spread))) for _ in range(words)])
            out.append(runs)
    return out


def test_the_randomization_test_finds_a_real_effect():
    r = ll.randomization_test(blocks_of(0.30), 2, quantiles=(0.5,), resamples=1000, seed=3)[0.5]
    assert r["reduction"] == pytest.approx(0.30, abs=0.04)
    assert r["p"] < 0.01
    i = ll.block_reduction_interval(blocks_of(0.30), 2)
    assert i["ci95"][0] < r["reduction"] < i["ci95"][1] and i["lower95_one_sided"] > 0.2


def test_the_randomization_test_of_no_effect_is_not_significant_and_the_interval_covers_zero():
    blocks = blocks_of(0.0, seed=21)
    r = ll.randomization_test(blocks, 2, quantiles=(0.5,), resamples=1000, seed=3)[0.5]
    assert r["p"] > 0.05
    i = ll.block_reduction_interval(blocks, 2)
    assert i["ci95"][0] <= 0 <= i["ci95"][1]


def test_the_randomization_test_has_about_the_stated_false_positive_rate():
    # Simulated before the first real run: at 3 clips x 3 rounds with run-to-run noise of 6%.
    trials, hits = 150, 0
    for seed in range(trials):
        r = ll.randomization_test(blocks_of(0.0, seed=seed), 2, quantiles=(0.5,), resamples=300, seed=1)[0.5]
        hits += r["p"] < 0.05
    assert hits / trials < 0.10


def test_the_two_sided_aa_test_sees_a_shift_between_the_controls():
    blocks = [[a, [round(x * 0.8) for x in b]] for a, b, _ in blocks_of(0.0, seed=5)]
    r = ll.randomization_test(blocks, 1, quantiles=(0.5,), resamples=500, seed=1, two_sided=True)[0.5]
    assert r["reduction"] == pytest.approx(0.2, abs=0.04) and r["p"] < 0.02


def test_the_randomization_test_is_reproducible_from_its_seed():
    b = blocks_of(0.1)
    one = ll.randomization_test(b, 2, resamples=200, seed=9)
    two = ll.randomization_test(b, 2, resamples=200, seed=9)
    assert one == two


def test_randomization_mean_delta_known_values():
    # the variant is worse in every one of three blocks: of the 27 arrangements (any of three runs
    # plays the variant in each block), only this one has a mean as high, so p = 1/27
    blocks = [[0.20, 0.20, 0.30], [0.10, 0.10, 0.25], [0.30, 0.30, 0.40]]
    r = ll.randomization_mean_delta(blocks, 2, alternative="greater", resamples=20_000, seed=1)
    assert r["mean_delta"] == pytest.approx((0.10 + 0.15 + 0.10) / 3)
    assert r["p"] == pytest.approx(1 / 27, abs=0.01)
    assert ll.randomization_mean_delta(blocks, 2, alternative="less", resamples=2000, seed=1)["p"] > 0.9
    assert ll.randomization_mean_delta([], 2) == {"mean_delta": None, "p": None, "blocks": 0}
    # a block with a missing value is left out, not counted as zero
    assert ll.randomization_mean_delta([[0.2, 0.2, None], [0.1, 0.1, 0.2]], 2, resamples=500)["blocks"] == 1


def test_randomization_mean_delta_has_about_the_stated_false_positive_rate():
    rng = random.Random(11)
    hits = 0
    trials = 300
    for _ in range(trials):
        blocks = [[rng.gauss(0.2, 0.02) + 0.05 * (b % 3) for _ in range(3)] for b in range(9)]
        if ll.randomization_mean_delta(blocks, 2, resamples=300, seed=rng.randrange(10**6))["p"] < 0.05:
            hits += 1
    assert hits / trials < 0.09


def test_a_statistic_that_cannot_be_computed_has_no_p_value():
    r = ll.randomization_test([], 2, quantiles=(0.5,), resamples=10)[0.5]
    assert r["reduction"] is None and r["p"] is None


def test_t_mean_ci():
    assert ll.t_mean_ci([]) is None
    one = ll.t_mean_ci([2.0])
    assert one["mean"] == 2.0 and one["n"] == 1
    ci = ll.t_mean_ci([1.0, 2.0, 3.0, 4.0, 5.0])
    assert ci["mean"] == 3.0
    # t(0.975, 4) = 2.776, se = sqrt(2.5/5)
    assert ci["ci95"][1] == pytest.approx(3.0 + 2.776 * math.sqrt(0.5), abs=1e-6)


def test_holm_adjustment():
    adjusted = ll.holm([0.01, 0.04, None, 0.03])
    assert adjusted == [pytest.approx(0.03), pytest.approx(0.06), None, pytest.approx(0.06)]


# ---- the plan --------------------------------------------------------------

def test_the_schedule_covers_every_block_and_arm_once_and_is_seeded():
    arms = ["C0", "C1", "HT", "VAD"]
    clips = ["a", "b", "c"]
    one = lat.make_schedule(1, clips, arms, 3)
    two = lat.make_schedule(1, clips, arms, 3)
    assert one == two
    assert len(one) == 3 * 3 * 4
    assert {(o["round"], o["clip"], o["arm"]) for o in one} == {(r, c, a) for r in (1, 2, 3) for c in clips for a in arms}
    # rounds are outermost: a round finishes before the next starts
    assert [o["round"] for o in one] == sorted(o["round"] for o in one)
    # arms inside a block are a permutation, positions 1..n
    block = [o for o in one if o["round"] == 1 and o["clip"] == "a"]
    assert sorted(o["position"] for o in block) == [1, 2, 3, 4]
    # a different session is a different order
    assert lat.make_schedule(2, clips, arms, 3) != one


def test_arm_order_is_not_always_the_same_across_blocks():
    arms = ["C0", "C1", "HT", "VAD", "PRE"]
    order = lat.make_schedule(1, ["a", "b", "c", "d"], arms, 4)
    firsts = {o["arm"] for o in order if o["position"] == 1}
    assert len(firsts) >= 3


def test_every_arm_is_the_production_configuration_plus_one_change():
    assert lat.ARMS["C0"]["flags"] == [] and lat.ARMS["C1"]["flags"] == []
    keys = lambda flags: [f for f in flags if f.startswith("--")]  # noqa: E731
    for name, arm in lat.ARMS.items():
        if name in lat.CONTROLS:
            continue
        # one variable: at most one setting flag, plus the companion value for head tolerance
        settings = set(keys(arm["flags"]))
        assert len(settings - {"--head-min-run"}) == 1, name


def test_the_gate_is_the_one_in_the_brief():
    g = lat.DEFAULT_GATE
    assert g["latency"]["minRelativeReduction"] == 0.20
    assert g["immutability"]["maxViolations"] == 0
    assert g["wer"]["supportedRegressionAlpha"] == 0.05
    assert "unchanged unless every gate passes" in g["default"]
    assert "session 1 AND in session 2" in g["reproducibility"]
    assert g["latency"]["tailGuard"]["minReduction"] < 0 and g["latency"]["perClipGuard"]["minReduction"] < 0


def test_the_variant_defaults_in_the_swift_app_are_the_control(tmp_path):
    # The control is "no flags": it can only be the production configuration if the CLI's
    # defaults are SessionConfig()'s. Pinned on the Swift side by SessionConfigDefaultsTests;
    # here, that the flags the experiment varies are all ones the CLI documents.
    cli = (EVAL.parent / "app/Sources/TranscriberCLI/main.swift").read_text()
    for arm in lat.ARMS.values():
        for flag in arm["flags"]:
            if flag.startswith("--"):
                assert f'"{flag}"' in cli, flag


# ---- one session, synthetic results ---------------------------------------

def synthetic_plan(arms, clips, rounds=3):
    return {"schema": 1, "session": 1, "name": "synthetic", "commit": "0" * 40, "seed": 1,
            "binary": {"sha256": "0" * 64}, "hardware": {"cores": 12}, "rounds": rounds,
            "arms": {a: {**lat.ARMS[a]} for a in arms}, "controls": ["C0", "C1"],
            "variants": [a for a in arms if a not in ("C0", "C1")],
            "clips": clips, "gate": json.loads(json.dumps(lat.DEFAULT_GATE))}


def synthetic_run(clip, round_, arm, *, latencies, wer=0.2, deletion=0.04, missing=0.02, violations=0,
                  hallucinations=0, dropped=2, attempts=60, forced=1, failed_hops=0, busy=(10.0,),
                  ghost=0, omitted=0.02, words_match=True):
    return {"id": f"r{round_}-{clip}-{arm}", "round": round_, "clip": clip, "arm": arm, "ok": True,
            "metrics": {"latency_wall_ms": latencies, "latency_audio_ms": [x - 800 for x in latencies],
                        "latency_wall": ll.latency_summary(latencies), "latency_audio": ll.latency_summary(latencies),
                        "reason": [0] * len(latencies), "wer": wer, "deletion_rate": deletion,
                        "missing_speech_share": missing, "invariant_violations": violations,
                        "tokens_match_commits": True, "hallucinations_critical": hallucinations,
                        "hallucination_fillers": hallucinations, "hallucination_loops": 0,
                        "hallucination_invented_spans": 0, "dropped_hops": dropped, "attempts": attempts,
                        "forced_commits": forced, "empty_hypotheses": 1, "failed_hops": failed_hops,
                        "head_skips": 0, "head_skipped_words": 0, "boundaries": 3, "finalizations": 2,
                        "omitted_segment_share": omitted, "segment_latency_ms": [x + 2_000 for x in latencies[:20]],
                        "segment_latency": ll.latency_summary([x + 2_000 for x in latencies[:20]]),
                        "invariant_words_match": words_match, "empty_words": 0, "hallucination_repeated_phrases": 0,
                        "finalizations_abandoned": 0, "unagreed_tail_words": 4, "repeats": 1,
                        "repeat_excess": 0, "ghost_words": ghost, "finalization_latency_ms": [1500, 1700],
                        "cpu_s_per_audio_min": 10.0, "infer_rtf": 0.4, "decodes_per_min": 30.0,
                        "mean_window_ms": 7000.0, "decode_wall_median_ms": 900.0, "replay_overrun_ms": 3000.0,
                        "errors_by_reason": {r: {"ok": 1, "sub": 0, "ins": 0} for r in ll.REASONS}},
            "machineBusyPercent": list(busy), "lockWaitSeconds": 1.0, "loadavgAtLaunch": 2.0}


def synthetic_results(plan, *, effect=0.3, wer_delta=0.0, variant_violations=0, aa_shift=0.0,
                      variant_dropped=2, variant_hall=0, variant_ghost=0, tail_scale=1.0, slow_clip=None,
                      anchor_effect=None, busy_blocks=None, omitted_delta=0.0, unmatched=False, seed=2):
    """`slow_clip`: the variant is 1.3x SLOWER there and faster elsewhere by enough to keep the
    overall effect. `tail_scale` multiplies the slowest tenth of the variant's latencies.
    `anchor_effect`: the gain of the segment-latency series (default: the same as `effect`).
    `busy_blocks`: {(clip, round): machine busy percent} for blocks shared with other jobs."""
    rng = random.Random(seed)
    runs = []
    anchor = effect if anchor_effect is None else anchor_effect
    for clip in plan["clips"]:
        base = 3_000 + (500 if clip["corpus"] == "liva" else 0)
        for r in range(1, plan["rounds"] + 1):
            for arm in plan["arms"]:
                is_variant = arm in plan["variants"]
                if arm == "C1":
                    scale = 1 - aa_shift
                elif is_variant:
                    scale = 1 - effect
                    if slow_clip is not None:
                        scale = 1.3 if clip["id"] == slow_clip else 1 - effect - 0.15
                else:
                    scale = 1.0
                lats = [round(base * scale * (1 + rng.gauss(0, 0.12))) for _ in range(150)]
                if is_variant and tail_scale != 1.0:
                    cut = sorted(lats)[int(len(lats) * 0.85)]
                    lats = [round(x * tail_scale) if x >= cut else x for x in lats]
                has_text = bool(clip["refWords"])
                run = synthetic_run(
                    clip["id"], r, arm, latencies=lats,
                    wer=(0.2 + (wer_delta if is_variant else 0) + rng.gauss(0, 0.004)) if has_text else None,
                    deletion=(0.04 + rng.gauss(0, 0.002)) if has_text else None,
                    violations=variant_violations if is_variant else 0,
                    dropped=variant_dropped if is_variant else 2,
                    hallucinations=variant_hall if is_variant else 0, ghost=variant_ghost if is_variant else 0,
                    omitted=0.02 + (omitted_delta if is_variant else 0.0),
                    busy=((busy_blocks or {}).get((clip["id"], r), 10.0),),
                    words_match=not (unmatched and is_variant))
                seg_scale = (1 - anchor) if is_variant else (1 - aa_shift if arm == "C1" else 1.0)
                run["metrics"]["segment_latency_ms"] = [round(base * 2 * seg_scale * (1 + rng.gauss(0, 0.1))) for _ in range(20)]
                run["metrics"]["segment_latency"] = ll.latency_summary(run["metrics"]["segment_latency_ms"])
                runs.append(run)
    return {"schema": 1, "session": 1, "planSha256": "x" * 64, "runs": runs}


CLIPS = [{"id": "f1", "corpus": "fleurs", "refWords": 250}, {"id": "l1", "corpus": "liva", "refWords": 480},
         {"id": "a1", "corpus": "ami", "refWords": None}]


def analysis_of(**kw):
    plan = synthetic_plan(["C0", "C1", "HT"], CLIPS)
    plan["gate"]["latency"]["randomizationResamples"] = 300
    return plan, lat.analyze_session(plan, synthetic_results(plan, **kw))


def test_a_variant_that_is_faster_and_no_worse_passes_every_gate():
    _, a = analysis_of(effect=0.30)
    g = a["variants"]["HT"]["gates"]
    assert g["latency"]["pass"] and g["latency"]["median_reduction"] == pytest.approx(0.30, abs=0.04) and g["latency"]["p"] < 0.05
    assert g["all_pass"], {k: v for k, v in g.items() if isinstance(v, dict) and not v.get("pass")}
    assert a["aa"]["valid"]


def test_a_gain_below_twenty_percent_fails_the_latency_gate():
    _, a = analysis_of(effect=0.12)
    g = a["variants"]["HT"]["gates"]
    assert not g["latency"]["pass"] and not g["all_pass"]


def test_a_wer_regression_fails_even_with_a_big_latency_gain():
    _, a = analysis_of(effect=0.35, wer_delta=0.02)
    g = a["variants"]["HT"]["gates"]
    assert g["latency"]["pass"] and not g["wer"]["pass"] and not g["all_pass"]


def test_one_broken_invariant_in_any_run_blocks_the_change():
    _, a = analysis_of(effect=0.35, variant_violations=1)
    g = a["variants"]["HT"]["gates"]
    assert not g["immutability"]["pass"] and not g["all_pass"]
    assert a["invariantViolationsByArm"]["HT"] > 0


def test_more_hallucinations_than_the_controls_block_the_change():
    _, a = analysis_of(effect=0.35, variant_hall=1)
    assert not a["variants"]["HT"]["gates"]["hallucinations"]["pass"]


def test_materially_more_dropped_hops_block_the_change():
    _, a = analysis_of(effect=0.35, variant_dropped=8)
    assert not a["variants"]["HT"]["gates"]["droppedHops"]["pass"]


def test_a_p95_that_gets_worse_blocks_the_change_even_when_the_median_is_much_better():
    _, a = analysis_of(effect=0.35, tail_scale=1.8)
    g = a["variants"]["HT"]["gates"]
    assert g["latency"]["median_reduction"] > 0.25 and g["latency"]["p95_reduction"] < -0.05
    assert not g["latency"]["pass"] and not g["all_pass"]


def test_one_clip_getting_slower_blocks_the_change_although_the_average_clears_the_bar():
    _, a = analysis_of(effect=0.35, slow_clip="a1")
    g = a["variants"]["HT"]["gates"]["latency"]
    assert g["median_reduction"] >= 0.20 and g["worst_clip_reduction"] < -0.10
    assert not g["pass"]


def test_a_gain_that_only_the_models_own_timestamps_show_is_not_a_gain():
    _, a = analysis_of(effect=0.35, anchor_effect=0.0)
    g = a["variants"]["HT"]["gates"]["latency"]
    assert g["median_reduction"] >= 0.20 and g["segment_anchor_reduction"] == pytest.approx(0.0, abs=0.05)
    assert not g["pass"]


def test_more_omitted_turns_block_the_change_even_when_wer_and_deletions_are_unchanged():
    _, a = analysis_of(effect=0.35, omitted_delta=0.03)
    g = a["variants"]["HT"]["gates"]
    assert g["wer"]["pass"] and not g["missingSpeech"]["pass"] and not g["all_pass"]


def test_more_ghost_words_block_the_change():
    _, a = analysis_of(effect=0.35, variant_ghost=1)
    assert not a["variants"]["HT"]["gates"]["hallucinations"]["pass"]


def test_a_run_whose_monitor_counted_other_words_than_were_committed_blocks_the_change():
    _, a = analysis_of(effect=0.35, unmatched=True)
    g = a["variants"]["HT"]["gates"]["immutability"]
    assert not g["pass"] and g["runs_with_unmatched_words"]


def test_blocks_shared_with_other_jobs_are_named_and_the_gates_are_also_run_without_them():
    # 12 cores; 60% busy is 7.2 cores, of which the replay used 0.17: "other" is far above 2.
    _, a = analysis_of(effect=0.35, busy_blocks={("f1", 2): 60.0, ("l1", 3): 60.0})
    assert a["load"]["contended_blocks"] == ["f1/r2", "l1/r3"]
    g = a["variants"]["HT"]["gates"]["uncontended"]
    assert g["evaluated"] and g["blocks_without"] == 7 and g["all_pass_without_contended_blocks"] is True


def test_a_verdict_that_flips_without_the_shared_blocks_does_not_pass():
    # the whole gain is in the blocks that were shared with other jobs
    plan = synthetic_plan(["C0", "C1", "HT"], CLIPS)
    plan["gate"]["latency"]["randomizationResamples"] = 300
    results = synthetic_results(plan, effect=0.0, busy_blocks={("f1", 1): 60.0, ("l1", 1): 60.0, ("a1", 1): 60.0})
    for run in results["runs"]:
        if run["arm"] == "HT" and run["round"] == 1:
            run["metrics"]["latency_wall_ms"] = [round(x * 0.5) for x in run["metrics"]["latency_wall_ms"]]
            run["metrics"]["latency_wall"] = ll.latency_summary(run["metrics"]["latency_wall_ms"])
            run["metrics"]["segment_latency_ms"] = [round(x * 0.5) for x in run["metrics"]["segment_latency_ms"]]
    a = lat.analyze_session(plan, results)
    g = a["variants"]["HT"]["gates"]
    assert g["uncontended"]["evaluated"] and g["uncontended"]["all_pass_without_contended_blocks"] is False
    assert not g["all_pass"]


def test_a_run_that_committed_nothing_does_not_break_the_analysis():
    plan = synthetic_plan(["C0", "C1", "HT"], CLIPS)
    plan["gate"]["latency"]["randomizationResamples"] = 100
    results = synthetic_results(plan)
    victim = next(r for r in results["runs"] if r["arm"] == "HT" and r["clip"] == "f1" and r["round"] == 2)
    for key in ("latency_wall_ms", "latency_audio_ms", "segment_latency_ms", "reason"):
        victim["metrics"][key] = []
    victim["metrics"]["latency_wall"] = None
    victim["metrics"]["segment_latency"] = None
    a = lat.analyze_session(plan, results)
    assert "HT" in a["variants"] and a["variants"]["HT"]["per_clip"]["f1"]["rounds"] == 3


def test_a_session_whose_controls_disagree_is_not_valid_for_timing():
    _, a = analysis_of(effect=0.35, aa_shift=0.25)
    assert not a["aa"]["valid"]
    assert not a["variants"]["HT"]["gates"]["session_valid"]["pass"]
    assert not a["variants"]["HT"]["gates"]["all_pass"]


def test_incomplete_blocks_are_left_out_and_named():
    plan = synthetic_plan(["C0", "C1", "HT"], CLIPS)
    plan["gate"]["latency"]["randomizationResamples"] = 100
    results = synthetic_results(plan)
    results["runs"] = [r for r in results["runs"] if not (r["clip"] == "f1" and r["round"] == 2 and r["arm"] == "HT")]
    a = lat.analyze_session(plan, results)
    assert a["blocks"] == 8 and a["blocksPlanned"] == 9
    assert a["excluded"] == [{"clip": "f1", "round": 2, "missing": ["HT"]}]


def test_the_report_renders_every_arm_and_variant():
    plan, a = analysis_of(effect=0.30)
    text = lat.render_session(plan, a)
    for needle in ("C0", "C1", "HT", "A/A", "Gates", "all pass", "reference-anchored"):
        assert needle in text


# ---- the decision across sessions -------------------------------------------

def decide_with(tmp_path, per_session, *, gate=None, plan_hashes=None, arm_flags=None, allow_unchecked=False):
    out = tmp_path / "out"
    out.mkdir()
    for number, (reduction, all_pass, failed) in per_session.items():
        plan = {"session": number, "gate": gate or lat.DEFAULT_GATE, "seed": 1, "tier": "balanced",
                "base": ["--live"], "arms": {"HT": {"flags": (arm_flags or {}).get(number, ["--head-tolerance", "3"])}},
                "clips": [{"id": "c", "wavSha256": "x"}]}
        analysis = {"planSha256": (plan_hashes or {}).get(number, f"hash{number}"),
                    "variants": {"HT": {"latency": {"median": {"reduction": reduction}},
                                        "gates": {"latency": {"pass": all_pass}, "all_pass": all_pass,
                                                  **{k: {"pass": False} for k in failed}}}}}
        (out / f"plan-session-{number}.json").write_text(json.dumps(plan))
        (out / f"analysis-session-{number}.json").write_text(json.dumps(analysis))

    class Args:
        pass
    args = Args()
    args.out = out
    args.sessions = list(per_session)
    args.allow_unchecked = allow_unchecked
    lat.cmd_decide(args)
    return json.loads((out / "decision.json").read_text())


def test_the_default_changes_only_when_both_sessions_pass(tmp_path):
    both = decide_with(tmp_path, {1: (0.3, True, []), 2: (0.28, True, [])})
    assert both["changeDefaultTo"] == ["HT"] and both["productionConfigurationChanged"] and not both["problems"]


def test_one_failing_session_keeps_the_default(tmp_path):
    (tmp_path / "x").mkdir()
    one = decide_with(tmp_path / "x", {1: (0.3, True, []), 2: (0.1, False, ["latency"])})
    assert one["changeDefaultTo"] == [] and not one["productionConfigurationChanged"]
    assert one["verdicts"]["HT"]["per_session"]["2"]["failed"] == ["latency"]


def test_one_session_is_not_a_reproduction(tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    only = decide_with(tmp_path / "a", {1: (0.4, True, [])})
    assert not only["productionConfigurationChanged"] and any("fewer than two" in p for p in only["problems"])


def test_the_same_session_twice_is_not_a_reproduction(tmp_path):
    out = tmp_path / "out"
    out.mkdir()
    plan = {"session": 1, "gate": lat.DEFAULT_GATE, "seed": 1, "tier": "balanced", "base": [], "arms": {}, "clips": []}
    analysis = {"planSha256": "h", "variants": {"HT": {"latency": {"median": {"reduction": 0.4}},
                                                       "gates": {"all_pass": True, "latency": {"pass": True}}}}}
    (out / "plan-session-1.json").write_text(json.dumps(plan))
    (out / "analysis-session-1.json").write_text(json.dumps(analysis))

    class Args:
        pass
    args = Args()
    args.out, args.sessions, args.allow_unchecked = out, [1, 1], False
    lat.cmd_decide(args)
    decision = json.loads((out / "decision.json").read_text())
    assert not decision["productionConfigurationChanged"]
    assert any("fewer than two" in p or "share a plan" in p for p in decision["problems"])


def test_sessions_with_another_gate_or_other_arm_flags_are_not_comparable(tmp_path):
    (tmp_path / "g").mkdir()
    (tmp_path / "f").mkdir()
    weaker = json.loads(json.dumps(lat.DEFAULT_GATE))
    weaker["latency"]["minRelativeReduction"] = 0.05
    d = decide_with(tmp_path / "g", {1: (0.3, True, []), 2: (0.3, True, [])}, gate=weaker)
    assert not d["productionConfigurationChanged"] and any("gate" in p for p in d["problems"])
    d = decide_with(tmp_path / "f", {1: (0.3, True, []), 2: (0.3, True, [])},
                    arm_flags={1: ["--head-tolerance", "3"], 2: ["--head-tolerance", "5"]})
    assert not d["productionConfigurationChanged"] and any("other flags" in p for p in d["problems"])


def test_only_one_variable_is_ever_changed_at_once(tmp_path):
    out = tmp_path / "out"
    out.mkdir()
    for number, reductions in ((1, {"HT": 0.3, "HOP": 0.25}), (2, {"HT": 0.32, "HOP": 0.22})):
        plan = {"session": number, "gate": lat.DEFAULT_GATE, "seed": 1, "tier": "balanced", "base": [],
                "arms": {"HT": {"flags": ["a"]}, "HOP": {"flags": ["b"]}}, "clips": []}
        analysis = {"planSha256": f"h{number}", "variants": {
            v: {"latency": {"median": {"reduction": r}}, "gates": {"all_pass": True, "latency": {"pass": True}}}
            for v, r in reductions.items()}}
        (out / f"plan-session-{number}.json").write_text(json.dumps(plan))
        (out / f"analysis-session-{number}.json").write_text(json.dumps(analysis))

    class Args:
        pass
    args = Args()
    args.out, args.sessions, args.allow_unchecked = out, [1, 2], False
    lat.cmd_decide(args)
    d = json.loads((out / "decision.json").read_text())
    assert set(d["meetEveryGate"]) == {"HT", "HOP"} and d["changeDefaultTo"] == ["HT"]


# ---- promotion --------------------------------------------------------------

def test_promotion_sends_on_what_cleared_the_session_one_bar():
    plan = {"gate": lat.DEFAULT_GATE}
    analysis = {"variants": {
        "HT": {"latency": {"median": {"reduction": 0.30}}, "gates": {"immutability": {"pass": True}}},
        "VAD": {"latency": {"median": {"reduction": 0.05}}, "gates": {"immutability": {"pass": True}}},
        "PRE": {"latency": {"median": {"reduction": 0.40}}, "gates": {"immutability": {"pass": False}}},
        "HOP": {"latency": {"median": {"reduction": 0.16}}, "gates": {"immutability": {"pass": True}}}}}
    assert lat.promote(plan, analysis) == ["HT", "HOP"]


# ---- the committed fixture --------------------------------------------------

def test_the_clip_fixture_in_git_holds_no_audio_text_or_paths():
    path = EVAL / "fixtures" / "live-latency-clips.json"
    if not path.exists():
        pytest.skip("run `eval/live_latency.py prepare` first")
    fixture = json.loads(path.read_text())
    blob = path.read_text()
    assert "refText" not in blob and "/tmp/" not in blob and '"text"' not in blob
    for clip in fixture["clips"]:
        assert set(clip) == {"id", "corpus", "kind", "language", "durationMs", "wavSha256", "refWords",
                             "refSpanCount", "refSpansSha256", "source"}
        assert len(clip["wavSha256"]) == 64
        assert clip["source"]["licence"] == "CC BY 4.0"


def test_densest_window_follows_the_reference_not_the_decode():
    spans = [(0, 10_000), (70_000, 160_000), (200_000, 205_000)]
    assert lat.densest_window(spans, 300_000, 90_000, earliest_ms=0, step_ms=10_000) == 70_000
    # nothing before earliest is considered
    assert lat.densest_window([(0, 90_000)], 300_000, 90_000, earliest_ms=60_000, step_ms=30_000) == 60_000


def test_rttm_segments_are_kept_apart_and_merged_only_when_asking_where_speech_is():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "x.rttm"
        p.write_text("SPEAKER m 1 1.00 2.00 <NA> <NA> A <NA> <NA>\nSPEAKER m 1 2.50 1.00 <NA> <NA> B <NA> <NA>\n"
                     "SPEAKER m 1 9.00 0.50 <NA> <NA> A <NA> <NA>\n")
        segments = lat.parse_rttm(p)
        assert segments == [(1000, 3000), (2500, 3500), (9000, 9500)]
        assert ll.merge_spans(segments) == [(1000, 3500), (9000, 9500)]
