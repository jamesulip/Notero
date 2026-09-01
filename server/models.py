"""Catalogue of selectable ASR models.

The names in WhisperKit's zoo are actively misleading, so every entry here
carries what the model actually is rather than what it is called. `_turbo` marks
a compute variant that adds a prefill stage; it does **not** mean OpenAI's
large-v3-turbo, which is published under its September 2024 date stamp. Picking
by name alone gets you the full 1.5B large-v3 with a decoder 5.3x heavier, in a
loop that re-decodes the whole window every hop.

`multilingual=False` entries are listed but must not be selected for Tagalog:
the distil-whisper models are English-only and will silently translate.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ModelInfo:
    id: str
    label: str
    detail: str
    approx_mb: int
    multilingual: bool
    recommended: bool = False


CATALOGUE: tuple[ModelInfo, ...] = (
    ModelInfo(
        id="openai_whisper-large-v3-v20240930_turbo",
        label="large-v3-turbo",
        detail="OpenAI's turbo model: large-v3 with the decoder pruned 32 -> 4 "
               "layers. Same encoder, ~809M params. The validated default.",
        approx_mb=1638, multilingual=True, recommended=True,
    ),
    ModelInfo(
        id="openai_whisper-large-v3-v20240930_626MB",
        label="large-v3-turbo (quantized, 626MB)",
        detail="Same turbo model, quantized. Faster and lighter; accuracy cost "
               "on Tagalog is unmeasured -- A/B it before trusting it.",
        approx_mb=626, multilingual=True,
    ),
    ModelInfo(
        id="openai_whisper-large-v3-v20240930_547MB",
        label="large-v3-turbo (quantized, 547MB)",
        detail="More aggressive quantization of the turbo model.",
        approx_mb=547, multilingual=True,
    ),
    ModelInfo(
        id="openai_whisper-large-v3_turbo",
        label="large-v3 (full, not turbo)",
        detail="Full 1.5B large-v3. The `_turbo` suffix is a WhisperKit compute "
               "variant, NOT the turbo model -- its decoder is 5.3x heavier. "
               "Most accurate, and far slower per hop.",
        approx_mb=3195, multilingual=True,
    ),
    ModelInfo(
        id="openai_whisper-large-v3_947MB",
        label="large-v3 (quantized, 947MB)",
        detail="Quantized full large-v3.",
        approx_mb=947, multilingual=True,
    ),
    ModelInfo(
        id="openai_whisper-medium",
        label="medium",
        detail="Multilingual, much lighter. A fallback if the machine is "
               "saturated; expect a real accuracy drop on Taglish.",
        approx_mb=1530, multilingual=True,
    ),
    ModelInfo(
        id="openai_whisper-small",
        label="small",
        detail="Fastest multilingual option. Useful for smoke-testing the "
               "pipeline, not for transcripts you intend to keep.",
        approx_mb=483, multilingual=True,
    ),
    ModelInfo(
        id="distil-whisper_distil-large-v3_turbo",
        label="distil-large-v3 (ENGLISH ONLY)",
        detail="English-only. Listed for completeness -- on Tagalog it will "
               "translate rather than transcribe. Do not select for `tl`.",
        approx_mb=600, multilingual=False,
    ),
)

BY_ID = {m.id: m for m in CATALOGUE}


def is_downloaded(model_id: str, models_dir: Path) -> bool:
    """WhisperKit lays models out under <base>/models/<repo>/<model-id>/."""
    candidate = (models_dir / "models" / "argmaxinc" / "whisperkit-coreml" / model_id)
    return (candidate / "TextDecoder.mlmodelc").exists()


def catalogue(models_dir: Path, current: str | None) -> list[dict]:
    return [
        {
            "id": m.id,
            "label": m.label,
            "detail": m.detail,
            "approx_mb": m.approx_mb,
            "multilingual": m.multilingual,
            "recommended": m.recommended,
            "downloaded": is_downloaded(m.id, models_dir),
            "current": m.id == current,
        }
        for m in CATALOGUE
    ]
