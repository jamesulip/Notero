"""Model catalogue and switching guards."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from server.models import BY_ID, CATALOGUE, catalogue, is_downloaded  # noqa: E402


def test_the_default_is_the_real_turbo_model():
    """The date-stamped id is OpenAI's large-v3-turbo; the `_turbo` suffix alone
    is a WhisperKit compute variant of full large-v3."""
    from server.adapters.whisperkit import DEFAULT_MODEL

    assert DEFAULT_MODEL == "openai_whisper-large-v3-v20240930_turbo"
    assert BY_ID[DEFAULT_MODEL].recommended
    assert BY_ID[DEFAULT_MODEL].multilingual


def test_the_lookalike_is_listed_as_the_heavier_model():
    lookalike = BY_ID["openai_whisper-large-v3_turbo"]
    real = BY_ID["openai_whisper-large-v3-v20240930_turbo"]
    assert lookalike.approx_mb > real.approx_mb * 1.8
    assert "NOT the turbo model" in lookalike.detail


def test_english_only_models_are_flagged():
    english_only = [m for m in CATALOGUE if not m.multilingual]
    assert english_only, "the distil models should be listed and flagged"
    for model in english_only:
        assert "ENGLISH ONLY" in model.label


def test_exactly_one_recommendation():
    assert sum(m.recommended for m in CATALOGUE) == 1


def test_downloaded_detection(tmp_path):
    model_id = "openai_whisper-large-v3-v20240930_turbo"
    assert not is_downloaded(model_id, tmp_path)

    target = tmp_path / "models" / "argmaxinc" / "whisperkit-coreml" / model_id
    (target / "TextDecoder.mlmodelc").mkdir(parents=True)
    assert is_downloaded(model_id, tmp_path)


def test_catalogue_marks_the_current_model(tmp_path):
    rows = catalogue(tmp_path, "openai_whisper-small")
    current = [r for r in rows if r["current"]]
    assert len(current) == 1
    assert current[0]["id"] == "openai_whisper-small"
