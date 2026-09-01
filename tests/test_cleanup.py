"""Cleanup guardrails.

Section 10's exit criterion is "obviously more readable and has invented
nothing". The second half is what these test: the model is not trusted, its
output is checked, and a rewrite that fails goes back to raw.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest  # noqa: E402

from server.cleanup import CleanupEngine, dropped_words, similarity  # noqa: E402

LEGITIMATE = [
    ("Kumusta kayong lah at, welcome", "Kumusta kayong lahat, welcome"),
    ("gusto kolang i confirm", "Gusto ko lang i-confirm."),
    ("ang problema kasih hindi pata pos", "Ang problema kasi, hindi pa tapos."),
    ("sa staging environment.", "Sa staging environment."),
]

# All four were observed passing the similarity check while changing meaning.
INVENTED = [
    ("tatlong bagailangan. Una, yung update", "Tatlong bagay ang karanasan. Una, yung update"),
    ("i priority zayun this week para hindi", "i priority, this week para hindi"),
    ("Nga nares last week tungkol", "Nga, last week tungkol"),
    ("Confirm kung kumple tona ang attendance.", "Confirm kung kumple ang attendance."),
]


@pytest.mark.parametrize("raw,cleaned", LEGITIMATE)
def test_legitimate_repairs_pass_both_guards(raw, cleaned):
    assert similarity(raw, cleaned) >= 0.85
    assert dropped_words(raw, cleaned) == []


@pytest.mark.parametrize("raw,cleaned", INVENTED)
def test_dropped_words_catch_what_similarity_misses(raw, cleaned):
    """These score 0.88-0.96 -- similarity alone would let every one through."""
    assert dropped_words(raw, cleaned), f"missed a dropped word in {cleaned!r}"


def test_translation_and_continuation_fail_on_similarity():
    assert similarity("kumusta kayong lahat", "How are you all?") < 0.85
    assert similarity("sige next topic na tayo",
                      "Sure, we can move on to the next topic now.") < 0.85


def test_rejected_rewrite_keeps_the_raw_text():
    engine = CleanupEngine()
    engine._model = object()          # pretend it is loaded
    engine._generate = lambda text, vocab: "How are you all doing today?"
    assert engine.clean_text("kumusta kayong lahat") == "kumusta kayong lahat"


def test_generation_failure_keeps_the_raw_text():
    """A broken model must degrade to raw, never to empty."""
    engine = CleanupEngine()
    engine._model = object()

    def boom(text, vocab):
        raise RuntimeError("model exploded")

    engine._generate = boom
    assert engine.clean_text("hindi pa tapos") == "hindi pa tapos"


def test_accepted_rewrite_is_returned():
    engine = CleanupEngine()
    engine._model = object()
    engine._generate = lambda text, vocab: "Gusto ko lang i-confirm."
    assert engine.clean_text("gusto kolang i confirm") == "Gusto ko lang i-confirm."


def test_rerun_clears_a_rewrite_that_no_longer_passes():
    """Tightening the guards must undo what the looser ones let through."""
    from dataclasses import dataclass

    @dataclass
    class Row:
        id: int
        text: str
        text_clean: str | None

    engine = CleanupEngine()
    engine._model = object()
    engine._generate = lambda text, vocab: "Nga, last week tungkol"   # drops "nares"

    rows = [Row(1, "Nga nares last week tungkol", "Nga, last week tungkol")]
    updates, stats = engine.clean_segments(rows)

    assert updates == {1: None}, "stale cleaned text must be cleared, not kept"
    assert stats.rejected_dropped == 1
