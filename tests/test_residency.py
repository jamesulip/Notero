"""The parsing in eval/residency.py, against output captured from this Mac."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import residency as rs  # noqa: E402

MB = 1024 * 1024

# Shape of `footprint -p PID -j FILE` for transcribe after the model loaded.
FOOTPRINT = {
    "processes": [{
        "name": "transcribe", "pid": 25150, "footprint": 77 * MB,
        "categories": {
            "MALLOC_LARGE": {"dirty": 36 * MB, "clean": 0, "swapped": 0, "reclaimable": 0},
            "Owned physical footprint (unmapped) (neural) (nofootprint)":
                {"dirty": 0, "clean": 1581 * MB, "swapped": 0, "reclaimable": 2736 * 1024},
            "mapped file": {"dirty": 0, "clean": 1664 * 1024, "swapped": 0, "reclaimable": 0},
        },
        "auxiliary": {"neural_peak": 1581 * MB, "phys_footprint": 77 * MB,
                      "phys_footprint_peak": 152 * MB},
    }],
}

VM_STAT = """Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                    12125.
Pages active:                                 304420.
Pages inactive:                               229081.
Pages wired down:                             119462.
Pages occupied by compressor:                 325380.
File-backed pages:                            251030.
Anonymous pages:                              306703.
"""


def test_footprint_neural_memory_is_counted_apart_from_the_footprint():
    parsed = rs.parse_footprint_json(FOOTPRINT)
    assert parsed["footprint_mb"] == pytest.approx(77)
    # The "mapped file" category is not neural; the neural row is clean, not dirty.
    assert parsed["neural_mb"] == pytest.approx(1581)
    assert parsed["neural_peak_mb"] == pytest.approx(1581)
    assert parsed["phys_footprint_peak_mb"] == pytest.approx(152)
    assert parsed["neural_mb"] > 10 * parsed["footprint_mb"]


def test_footprint_without_neural_categories_reports_zero_not_missing():
    document = {"processes": [{"footprint": 5 * MB, "categories":
                               {"MALLOC_SMALL": {"dirty": 5 * MB, "clean": 0, "swapped": 0}},
                               "auxiliary": {}}]}
    assert rs.parse_footprint_json(document) == {"footprint_mb": 5, "neural_mb": 0}
    assert rs.parse_footprint_json({}) == {}


def test_vm_stat_uses_the_page_size_in_the_header():
    parsed = rs.parse_vm_stat(VM_STAT)
    assert parsed["free_mb"] == pytest.approx(12125 * 16384 / MB)
    assert parsed["wired_mb"] == pytest.approx(119462 * 16384 / MB)
    assert parsed["compressor_mb"] == pytest.approx(325380 * 16384 / MB)
    assert rs.parse_vm_stat(VM_STAT.replace("16384", "4096"))["free_mb"] == \
        pytest.approx(12125 * 4096 / MB)


def test_stage_table_picks_the_samples_around_the_marks():
    samples = [
        {"t": 1.0, "footprint_mb": 12, "neural_mb": 0, "rss_mb": 40},
        {"t": 3.0, "footprint_mb": 14, "neural_mb": 0, "rss_mb": 50},
        {"t": 11.0, "footprint_mb": 77, "neural_mb": 1581, "rss_mb": 250},
        {"t": 14.0, "footprint_mb": 150, "neural_mb": 1581, "rss_mb": 300},
        {"t": 30.0, "footprint_mb": 90, "neural_mb": 1500, "rss_mb": 280},
    ]
    marks = {"load_start": 4.0, "load_end": 10.5, "decode_end": 20.0}
    table = rs.stage_table(samples, marks)
    assert table["before_model_load"]["footprint_mb"] == 14        # last sample before 4.0
    assert table["after_model_load"]["neural_mb"] == 1581          # first sample after 10.5
    assert table["peak_during_decode"] == {"footprint_mb": 150, "neural_mb": 1581, "rss_mb": 300}


def test_stage_table_leaves_out_a_stage_it_did_not_see():
    assert rs.stage_table([], {"load_start": 1.0}) == {}
    only_late = [{"t": 9.0, "footprint_mb": 50, "neural_mb": 0, "rss_mb": 1}]
    assert "before_model_load" not in rs.stage_table(only_late, {"load_start": 1.0})
