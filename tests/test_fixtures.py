"""The fixture manifest and its generator driver.

Generation needs macOS `say`; nothing here calls it. The driver is exercised with a
fake runner that records the commands and writes the files, and the macOS-only guard is
exercised by hiding the tools, so these tests run on Linux.
"""

import csv
import hashlib
import json
import struct
import sys
import wave
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import fixtures as fx  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
MANIFEST = fx.load_manifest()
FIXTURES = fx.by_id(MANIFEST)


# ---- the committed manifest is consistent -----------------------------------

def test_every_fixture_says_what_it_supports_and_cannot_support():
    for fixture in MANIFEST["fixtures"]:
        assert fixture["supports"] and fixture["cannot_support"], fixture["id"]
        assert isinstance(fixture["synthetic"], bool) and "deterministic" in fixture, fixture["id"]


def test_the_synthetic_flag_is_true_for_everything_but_the_public_subset():
    public = [f["id"] for f in MANIFEST["fixtures"] if not f["synthetic"]]
    assert public == ["fleurs-fil-ph-subset"]
    assert "CC-BY-4.0" in FIXTURES["fleurs-fil-ph-subset"]["external"]["license"]
    # ... and its limits are stated: read speech, not Taglish, not a meeting.
    text = " ".join(FIXTURES["fleurs-fil-ph-subset"]["cannot_support"])
    assert "Taglish" in text and "meeting" in text


def test_every_generator_a_fixture_names_exists_and_every_dependency_too():
    for fixture in MANIFEST["fixtures"]:
        name = fixture.get("generator")
        if name:
            assert name in MANIFEST["generators"], fixture["id"]
    for name, generator in MANIFEST["generators"].items():
        for dependency in generator.get("needs", []):
            assert dependency in FIXTURES, f"{name} needs {dependency}"
        assert generator["commands"], name


def test_deterministic_fixtures_record_a_sha256_for_every_generated_file():
    for fixture in MANIFEST["fixtures"]:
        if fixture.get("generator") and fixture["deterministic"]:
            hashes = fixture["sha256"]
            assert fixture["audio"] in hashes, fixture["id"]
            for name, sha in hashes.items():
                assert len(sha) == 64 and set(sha) <= set("0123456789abcdef"), (fixture["id"], name)


def test_the_committed_reference_hash_matches_the_reference_file():
    synthetic = FIXTURES["synthetic-taglish"]
    reference = REPO / synthetic["reference"]
    assert hashlib.sha256(reference.read_bytes()).hexdigest() == synthetic["reference_sha256"]
    assert (REPO / "eval" / "fixtures" / "synthetic-taglish.pause-points.json").is_file()


def test_the_pause_points_file_is_a_valid_input_for_make_paused():
    points = json.loads((REPO / "eval" / "fixtures" / "synthetic-taglish.pause-points.json").read_text())
    assert len(points["words"]) == 26                        # the 26 pauses of the paused fixture
    assert all(w["text"].endswith((".", "?", ",")) and isinstance(w["endMs"], int) for w in points["words"])
    assert [w["endMs"] for w in points["words"]] == sorted(w["endMs"] for w in points["words"])


def test_multispeaker_fixtures_match_the_generators_own_list_exactly():
    # If the speaker agent adds, renames or removes a fixture in make_multispeaker.py, the
    # manifest (and its hashes) must follow: this fails until it does.
    import make_multispeaker as mm
    declared = {f["generator_arg"] for f in MANIFEST["fixtures"] if f["generator"] == "multispeaker"}
    assert declared == {fixture.name for fixture in mm.FIXTURES}
    assert len(declared) == 7


# ---- generating (a fake runner stands in for say, afconvert and python) -------

class Recorder:
    def __init__(self, files):
        self.calls = []
        self.files = files            # relative path -> bytes, written under {out} by any command

    def __call__(self, argv, check=True, capture_output=True):
        self.calls.append(argv)
        for name, data in self.files.items():
            path = Path(self.out) / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)


@pytest.fixture
def tools_present(monkeypatch):
    monkeypatch.setattr(fx.shutil, "which", lambda name: f"/usr/bin/{name}")


def test_generate_runs_the_manifest_commands_and_checks_the_hash(tmp_path, tools_present):
    manifest = json.loads(json.dumps(MANIFEST))
    data = b"fake wav bytes"
    manifest["fixtures"][0]["sha256"] = {"synthetic-taglish.wav": hashlib.sha256(data).hexdigest()}
    run = Recorder({"synthetic-taglish.wav": data})
    run.out = tmp_path
    made = fx.generate(tmp_path, only=["synthetic-taglish"], manifest=manifest, run=run)
    assert made["synthetic-taglish"]["matches_manifest"] is True
    say, afconvert = run.calls
    assert say[0] == "say" and "Damayanti" in say and str(REPO / "eval" / "synthetic-taglish.txt") in say
    assert afconvert[0] == "afconvert" and afconvert[-1] == str(tmp_path / "synthetic-taglish.wav")
    assert all("{" not in arg for call in run.calls for arg in call)       # every placeholder expanded
    # A different hash is reported, not hidden:
    manifest["fixtures"][0]["sha256"] = {"synthetic-taglish.wav": "0" * 64}
    run2 = Recorder({"synthetic-taglish.wav": data})
    run2.out = tmp_path / "again"
    made = fx.generate(tmp_path / "again", only=["synthetic-taglish"], manifest=manifest, run=run2)
    assert made["synthetic-taglish"]["matches_manifest"] is False
    assert made["synthetic-taglish"]["mismatched"] == ["synthetic-taglish.wav"]


def test_generate_builds_a_dependency_first_and_feeds_its_path_to_the_next_command(tmp_path, tools_present):
    run = Recorder({"synthetic-taglish.wav": b"a", "synthetic-taglish-paused.wav": b"b"})
    run.out = tmp_path
    made = fx.generate(tmp_path, only=["synthetic-taglish-paused"], run=run)
    assert "synthetic-taglish" in made or "synthetic-taglish-paused" in made
    paused = [c for c in run.calls if c[1].endswith("make_paused.py")][0]
    assert paused[2] == str(tmp_path / "synthetic-taglish.wav")              # {fixture:synthetic-taglish}
    assert paused[3].endswith("synthetic-taglish.pause-points.json") and paused[-1] == "1200"
    assert run.calls.index(paused) > 1                                      # after say and afconvert


def test_generate_renders_only_the_requested_multispeaker_fixtures(tmp_path, tools_present):
    run = Recorder({"multispeaker/two-distinct.wav": b"1", "multispeaker/three-voices.wav": b"2"})
    run.out = tmp_path
    made = fx.generate(tmp_path, only=["ms-two-distinct", "ms-three-voices"], run=run)
    assert set(made) == {"ms-two-distinct", "ms-three-voices"}
    command = run.calls[0]
    assert command[1].endswith("make_multispeaker.py")
    assert command[command.index("--only") + 1:] == ["two-distinct", "--only", "three-voices"]
    assert len(run.calls) == 1                                              # one render for the group


def test_generate_rejects_unknown_ids_and_skips_the_external_fixture(tmp_path, tools_present):
    with pytest.raises(KeyError, match="no-such"):
        fx.generate(tmp_path, only=["no-such"])
    assert fx.generate(tmp_path, only=["fleurs-fil-ph-subset"], run=Recorder({})) == {}


def test_generation_needs_the_macos_tools_and_says_so_on_linux(tmp_path, monkeypatch):
    monkeypatch.setattr(fx.shutil, "which", lambda name: None)
    with pytest.raises(fx.FixtureUnavailable, match="needs `say`"):
        fx.generate(tmp_path, only=["synthetic-taglish"], run=Recorder({}))


def test_resolve_prefers_a_matching_file_found_on_the_search_path(tmp_path, tools_present):
    data = b"clip"
    manifest = json.loads(json.dumps(MANIFEST))
    manifest["fixtures"][0]["sha256"] = {"synthetic-taglish.wav": hashlib.sha256(data).hexdigest()}
    (tmp_path / "found").mkdir()
    (tmp_path / "found" / "synthetic-taglish.wav").write_bytes(data)
    path, info = fx.resolve("synthetic-taglish", search=[tmp_path / "found"], scratch=tmp_path / "s",
                            manifest=manifest)
    assert path == tmp_path / "found" / "synthetic-taglish.wav"
    assert info["source"] == "found" and info["matches_manifest"] is True


def test_resolve_ignores_a_file_whose_hash_differs_and_generates_instead(tmp_path, tools_present, monkeypatch):
    manifest = json.loads(json.dumps(MANIFEST))
    manifest["fixtures"][0]["sha256"] = {"synthetic-taglish.wav": hashlib.sha256(b"right").hexdigest()}
    (tmp_path / "found").mkdir()
    (tmp_path / "found" / "synthetic-taglish.wav").write_bytes(b"stale or different")
    run = Recorder({"synthetic-taglish.wav": b"right"})
    run.out = tmp_path / "s"
    path, info = fx.resolve("synthetic-taglish", search=[tmp_path / "found"], scratch=tmp_path / "s",
                            manifest=manifest, run=run)
    assert len(run.calls) == 2                      # say and afconvert were (fake-)run: the stale file was not used
    assert info["source"] == "generated" and path == tmp_path / "s" / "synthetic-taglish.wav"
    assert info["matches_manifest"] is True


def test_resolve_without_generation_raises_a_clear_error(tmp_path):
    with pytest.raises(fx.FixtureUnavailable, match="was not found"):
        fx.resolve("synthetic-taglish", search=[tmp_path], scratch=tmp_path / "s", allow_generate=False)
    with pytest.raises(KeyError):
        fx.resolve("no-such", search=[], scratch=tmp_path)


def test_verify_reports_ok_missing_and_mismatch(tmp_path):
    (tmp_path / "synthetic-taglish.wav").write_bytes(b"not the right bytes")
    rows = {r["id"]: r for r in fx.verify(tmp_path)}
    assert rows["synthetic-taglish"]["status"].startswith("MISMATCH")
    assert rows["ms-two-distinct"]["status"] == "missing"
    # a directory that matches the manifest verifies clean
    manifest = json.loads(json.dumps(MANIFEST))
    manifest["fixtures"][0]["sha256"] = {"synthetic-taglish.wav": hashlib.sha256(b"not the right bytes").hexdigest()}
    assert {r["id"]: r for r in fx.verify(tmp_path, manifest)}["synthetic-taglish"]["status"] == "ok"


# ---- the optional public subset ------------------------------------------------

def write_float32_wav(path: Path, samples, rate=16000):
    body = struct.pack(f"<{len(samples)}f", *samples)
    header = (b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVE" + b"fmt " +
              struct.pack("<IHHIIHH", 16, 3, 1, rate, rate * 4, 4, 32) + b"data" + struct.pack("<I", len(body)))
    path.write_bytes(header + body)


def make_fleurs(tmp_path, count=12):
    root = tmp_path / "fleurs"
    clips = root / "test" / "test"
    clips.mkdir(parents=True)
    with (root / "test.tsv").open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        for i in range(count):
            name = f"clip{i:03d}.wav"
            write_float32_wav(clips / name, [0.5 if i % 2 else -0.5] * (1600 + i * 160))
            writer.writerow([i, name, f"Raw sentence {i}.", f"normalized sentence {i}", "phon", 1600 + i * 160, "MALE"])
    return root


def test_read_pcm16_converts_float32_and_passes_int16_through(tmp_path):
    write_float32_wav(tmp_path / "f.wav", [0.0, 0.5, -0.5, 1.5, -2.0])
    assert fx.read_pcm16(tmp_path / "f.wav") == [0, 16384, -16384, 32767, -32768]    # clipped, not wrapped
    fx.write_pcm16(tmp_path / "p.wav", [1, -2, 3])
    assert fx.read_pcm16(tmp_path / "p.wav") == [1, -2, 3]
    with wave.open(str(tmp_path / "p.wav")) as handle:
        assert handle.getframerate() == 16000 and handle.getnchannels() == 1


def test_read_pcm16_rejects_other_formats_rather_than_misreading_them(tmp_path):
    (tmp_path / "bad.wav").write_bytes(b"not a wav file at all")
    with pytest.raises(ValueError, match="RIFF"):
        fx.read_pcm16(tmp_path / "bad.wav")
    write_float32_wav(tmp_path / "rate.wav", [0.0] * 10, rate=44100)
    with pytest.raises(ValueError, match="16000"):
        fx.read_pcm16(tmp_path / "rate.wav")


def test_fleurs_selection_is_fixed_by_a_hash_not_chosen(tmp_path):
    root = make_fleurs(tmp_path)
    first = [c["file"] for c in fx.fleurs_selection(root, 5)]
    assert first == [c["file"] for c in fx.fleurs_selection(root, 5)]       # same every time
    expected = sorted((f"clip{i:03d}.wav" for i in range(12)), key=lambda n: hashlib.sha1(n.encode()).hexdigest())[:5]
    assert first == expected
    assert [c["file"] for c in fx.fleurs_selection(root, 3)] == first[:3]   # a prefix: K only trims


def test_fleurs_subset_concatenates_with_a_half_second_gap_and_joins_the_references(tmp_path):
    root = make_fleurs(tmp_path)
    built = fx.build_fleurs_subset(root, 3, tmp_path / "out")
    chosen = fx.fleurs_selection(root, 3)
    expected_samples = sum(1600 + int(c["file"][4:7]) * 160 for c in chosen) + 2 * 8000
    assert round(built["duration_s"] * 16000) == expected_samples
    assert built["clips"] == [c["file"] for c in chosen]
    reference = built["reference"].read_text().split()
    assert reference[:2] == ["normalized", "sentence"] and len(reference) == 9      # 3 clips x 3 words
    assert built["sha256"] == fx.sha256_of(built["audio"])


def test_fleurs_absent_is_a_clean_skip_not_a_crash(tmp_path):
    with pytest.raises(fx.FixtureUnavailable, match="FLEURS not found"):
        fx.fleurs_selection(tmp_path / "nothing", 8)
    root = make_fleurs(tmp_path, count=2)
    with pytest.raises(fx.FixtureUnavailable, match="need 8"):
        fx.fleurs_selection(root, 8)


def test_default_scratch_is_outside_the_repository():
    assert not str(fx.default_scratch()).startswith(str(REPO))
