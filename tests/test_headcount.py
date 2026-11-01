"""The head-count sweep's bookkeeping (eval/run_headcount.py), without running a build."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import run_headcount as hc  # noqa: E402


def row(fixture, arm, stated, ref, speakers, der):
    return {"fixture": fixture, "arm": arm, "stated": stated, "ref": ref,
            "speakers": speakers, "der": der}


def test_a_cell_counts_wrong_counts_merges_and_phantoms_separately():
    rows = [row("a", "ship-0.85", "true", 3, 3, 0.10), row("b", "ship-0.85", "true", 3, 2, 0.30),
            row("c", "ship-0.85", "true", 3, 4, 0.20)]
    cell = hc.summarize(rows)[0]
    assert (cell["wrong_count"], cell["merged"], cell["split"]) == (2, 1, 1)
    assert round(cell["mean_der"], 2) == 20.0


def test_arms_and_stated_counts_are_kept_apart_and_in_a_fixed_order():
    rows = [row("a", "cons-0.75", "one-too-few", 3, 3, 0.1), row("a", "ship-0.85", "any", 3, 3, 0.1),
            row("a", "ship-0.85", "true", 3, 3, 0.1)]
    out = hc.summarize(rows)
    assert [(s["arm"], s["stated"]) for s in out] == [
        ("cons-0.75", "one-too-few"), ("ship-0.85", "any"), ("ship-0.85", "true")]


def test_the_table_has_one_line_per_cell():
    text = hc.render(hc.summarize([row("a", "ship-0.85", "true", 2, 2, 0.05)]))
    assert text.count("\n") == 2 and "| ship-0.85 | true | 1 | 5.00 | 0 | 0 | 0 |" in text
