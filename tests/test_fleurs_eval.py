"""The FLEURS evaluation harness: choosing a subset, reading and writing WAV, building
the constructed long-form files, the scoring arithmetic, the paired comparison, and one
end-to-end pass (prepare, decode, score, compare) against a fake `transcribe` that needs
no model and no audio tool. The real binary is exercised by the runs recorded in the
findings. Everything here runs on Linux."""

import array
import json
import random
import struct
import sys
import wave
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "eval"))

import fleurs_eval as fe  # noqa: E402
import langscore  # noqa: E402

TSV = (
    "1987\ta.wav\tNagganap ang pagbagsak, at \"hindi\" 800 ito.\tnagganap ang pagbagsak at hindi 800 ito\t55\t160000\tMALE\n"
    "1987\tb.wav\tNagganap ang pagbagsak, at \"hindi\" 800 ito.\tnagganap ang pagbagsak at hindi 800 ito\t55\t120000\tMALE\n"
    "1988\tc.wav\tIsa pa.\tisa pa\t6\t80000\tMALE\n"
    "1990\td.wav\tPangatlo.\tpangatlo\t9\t96000\tMALE\n"
    "1991\te.wav\t\"Hindi,\" sabi niya.\thindi sabi niya\t15\t64000\tMALE\n"
)


def utterances(count: int, per_sentence: int = 1) -> list[fe.Utterance]:
    out = []
    for sent in range(count):
        for rec in range(per_sentence):
            out.append(fe.Utterance(1000 + sent, f"s{sent}r{rec}.wav", f"Sentence {sent}.", f"sentence {sent}", 16000 * (3 + sent % 4)))
    return out


# ---- the TSV ------------------------------------------------------------

def test_parse_tsv_keeps_quotes_and_columns():
    utts = fe.parse_tsv(TSV)
    assert len(utts) == 5
    assert utts[4].raw == '"Hindi," sabi niya.'        # a field that STARTS with a quote: csv would strip it
    first = utts[0]
    assert first.sent_id == 1987 and first.filename == "a.wav" and first.uid == "a"
    assert '"hindi"' in first.raw          # the csv module would have eaten these
    assert first.fleurs_norm.endswith("800 ito")
    assert first.num_samples == 160000 and first.duration_s == 10.0


def test_parse_tsv_rejects_short_lines_and_bad_numbers():
    with pytest.raises(ValueError, match="line 1"):
        fe.parse_tsv("1987\ta.wav\ttext\n")
    with pytest.raises(ValueError, match="line 1"):
        fe.parse_tsv("x\ta.wav\tt\tn\t5\t100\tMALE\n")


# ---- subset selection ---------------------------------------------------

def test_one_per_sentence_keeps_one_recording_per_sentence_sorted():
    chosen = fe.one_per_sentence(fe.parse_tsv(TSV), seed=7)
    assert [u.sent_id for u in chosen] == [1987, 1988, 1990, 1991]
    assert chosen[0].filename in ("a.wav", "b.wav")


def test_selection_is_reproducible_and_seeded():
    utts = utterances(60, per_sentence=3)
    first = fe.select_subset(utts, 20, seed=7)
    assert [u.filename for u in first] == [u.filename for u in fe.select_subset(list(reversed(utts)), 20, seed=7)]
    assert len({u.sent_id for u in first}) == 20        # no sentence twice
    assert [u.filename for u in first] != [u.filename for u in fe.select_subset(utts, 20, seed=8)]
    # The seed picks WHICH sentences, in a scattered order: not the 20 lowest ids, and not the same 20 for another seed.
    assert {u.sent_id for u in first} != set(range(1000, 1020))
    assert {u.sent_id for u in first} != {u.sent_id for u in fe.select_subset(utts, 20, seed=8)}
    assert [u.sent_id for u in first] != sorted(u.sent_id for u in first)


def test_selection_is_prefix_stable_so_asking_for_more_adds_items():
    utts = utterances(60, per_sentence=2)
    small = [u.filename for u in fe.select_subset(utts, 10, seed=3)]
    large = [u.filename for u in fe.select_subset(utts, 25, seed=3)]
    assert large[:10] == small


def test_hash_is_pinned_so_a_python_upgrade_cannot_reshuffle_the_subset():
    # Computed from sha256, not from random.Random, which is not stable across versions.
    assert fe._digest(7, "sent", 1687) == 121144151410528026     # sha256(b'7:sent:1687')[:8]
    assert fe._unit(7, "gap", "lf1", 0) == pytest.approx(0.79894, abs=1e-5)


def test_subset_larger_than_the_pool_returns_what_exists():
    assert len(fe.select_subset(utterances(5), 100, seed=1)) == 5


# ---- WAV ----------------------------------------------------------------

def riff(payload: bytes, *, tag: int, bits: int, channels: int = 1, rate: int = 16000, declared: int | None = None,
         extensible: bool = False) -> bytes:
    if extensible:
        fmt = struct.pack("<HHIIHHHHI", 0xFFFE, channels, rate, rate * channels * bits // 8,
                          channels * bits // 8, bits, 22, bits, 0) + struct.pack("<H", tag) + bytes(14)
    else:
        fmt = struct.pack("<HHIIHH", tag, channels, rate, rate * channels * bits // 8, channels * bits // 8, bits)
    size = len(payload) if declared is None else declared
    return (b"RIFF" + struct.pack("<I", 4 + 8 + len(fmt) + 8 + len(payload)) + b"WAVE"
            + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", size) + payload)


def test_pcm16_roundtrip_is_readable_by_the_stdlib_wave_module(tmp_path):
    samples = array.array("h", [0, 1, -1, 32767, -32768, 1234])
    data = fe.wav_bytes(samples)
    path = tmp_path / "x.wav"
    path.write_bytes(data)
    with wave.open(str(path)) as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()) == (16000, 1, 2, 6)
    rate, back = fe.read_pcm16_mono(data)
    assert rate == 16000 and list(back) == list(samples)


def test_float32_wav_is_converted_with_clipping():
    floats = array.array("f", [0.0, 0.5, -0.5, 1.0, -1.0, 1.7, -2.0])
    rate, samples = fe.read_pcm16_mono(riff(floats.tobytes(), tag=3, bits=32))
    assert rate == 16000
    assert list(samples) == [0, 16384, -16384, 32767, -32767, 32767, -32768]


def test_extensible_header_is_read_by_its_real_format_tag():
    floats = array.array("f", [0.25, -0.25])
    _, samples = fe.read_pcm16_mono(riff(floats.tobytes(), tag=3, bits=32, extensible=True))
    assert list(samples) == [8192, -8192]


def test_truncated_data_chunk_reads_to_the_end():
    pcm = array.array("h", [5, 6, 7, 8]).tobytes()
    _, samples = fe.read_pcm16_mono(riff(pcm + b"\x01", tag=1, bits=16, declared=10_000))
    assert list(samples) == [5, 6, 7, 8]          # the stray odd byte is dropped


def test_stereo_and_unknown_formats_ask_for_a_converter():
    with pytest.raises(fe.NeedsConversion, match="2 channels"):
        fe.read_pcm16_mono(riff(bytes(8), tag=1, bits=16, channels=2))
    with pytest.raises(fe.NeedsConversion):
        fe.read_pcm16_mono(riff(bytes(6), tag=1, bits=24))
    with pytest.raises(ValueError):
        fe.read_pcm16_mono(b"not a wav file at all")
    with pytest.raises(ValueError):
        fe.read_pcm16_mono(b"RIFF\x00\x00\x00\x00WAVEjunk")


def test_load_16k_mono_reads_16k_files_without_a_tool(tmp_path):
    path = tmp_path / "ok.wav"
    path.write_bytes(riff(array.array("f", [0.5]).tobytes(), tag=3, bits=32))
    assert list(fe.load_16k_mono(path)) == [16384]


def test_converter_command_picks_the_available_tool():
    src, dst = Path("a.wav"), Path("b.wav")
    mac = fe.converter_command(src, dst, platform="darwin", have={"afconvert": True, "ffmpeg": True})
    assert mac[0] == "afconvert" and "LEI16@16000" in mac and mac[-2:] == ["a.wav", "b.wav"]
    linux = fe.converter_command(src, dst, platform="linux", have={"afconvert": True, "ffmpeg": True})
    assert linux[0] == "ffmpeg" and "16000" in linux and "pcm_s16le" in linux
    assert fe.converter_command(src, dst, platform="darwin", have={"ffmpeg": True})[0] == "ffmpeg"
    with pytest.raises(RuntimeError, match="no audio converter"):
        fe.converter_command(src, dst, platform="linux", have={})


# ---- the constructed long-form -----------------------------------------

def test_gaps_are_in_range_reproducible_and_not_constant():
    gaps = [fe.gap_seconds(7, "lf1", i) for i in range(200)]
    assert all(0.3 <= g <= 1.5 for g in gaps)
    assert gaps == [fe.gap_seconds(7, "lf1", i) for i in range(200)]
    assert max(gaps) - min(gaps) > 0.8                       # actually spread, not a constant
    assert gaps != [fe.gap_seconds(8, "lf1", i) for i in range(200)]


def test_plan_longform_is_consecutive_with_offsets_that_add_up():
    chosen = fe.one_per_sentence(utterances(30), seed=7)
    parts, gaps = fe.plan_longform(chosen, start_index=4, target_s=60, seed=7, label="lf1")
    assert [p.utt.sent_id for p in parts] == [c.sent_id for c in chosen[4:4 + len(parts)]]
    assert len(gaps) == len(parts) - 1
    assert parts[0].start_s == 0
    for k in range(1, len(parts)):
        assert parts[k].start_s == pytest.approx(parts[k - 1].end_s + gaps[k - 1])
    assert parts[-1].end_s >= 60 and parts[-2].end_s < 60     # stopped at the first part that reached it


def test_plan_longform_fails_loudly_when_the_pool_is_too_short():
    chosen = fe.one_per_sentence(utterances(3), seed=7)
    with pytest.raises(ValueError, match="ran out of sentences"):
        fe.plan_longform(chosen, start_index=0, target_s=600, seed=7, label="lf1")


def test_render_longform_places_clips_and_silence():
    a = array.array("h", [1] * 100)
    b = array.array("h", [2] * 50)
    samples, spans = fe.render_longform([a, b], [0.5])
    assert spans == [(0, 100), (100 + 8000, 100 + 8000 + 50)]
    assert len(samples) == 8150
    assert set(samples[100:8100]) == {0}                      # the gap is digital silence
    assert list(samples[:100]) == [1] * 100 and list(samples[-50:]) == [2] * 50
    with pytest.raises(ValueError):
        fe.render_longform([a, b], [])


# ---- edit distance and scoring -----------------------------------------

def full_distance(a, b):
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i]
        for j in range(1, len(b) + 1):
            cur.append(min(prev[j - 1] + (a[i - 1] != b[j - 1]), prev[j] + 1, cur[j - 1] + 1))
        prev = cur
    return prev[-1]


def test_edit_distance_is_exact_against_the_full_table():
    rng = random.Random(5)
    for _ in range(300):
        n, m = rng.randrange(0, 90), rng.randrange(0, 90)
        a = "".join(rng.choice("abc ") for _ in range(n))
        b = "".join(rng.choice("abc ") for _ in range(m))
        assert fe.edit_distance(a, b) == full_distance(a, b), (a, b)


def test_edit_distance_is_exact_when_the_strings_are_far_apart_and_long():
    rng = random.Random(9)
    a = "".join(rng.choice("abcdefgh") for _ in range(400))
    b = "".join(rng.choice("abcdefgh") for _ in range(380))   # unrelated: the band must widen to the end
    assert fe.edit_distance(a, b) == full_distance(a, b)
    assert fe.edit_distance("", "abc") == 3 and fe.edit_distance("abc", "") == 3
    assert fe.edit_distance(["a", "b"], ["a", "c"]) == 1       # works on word lists too


def test_the_band_must_widen_when_the_best_alignment_is_far_off_the_diagonal():
    rng = random.Random(4)
    core = "".join(rng.choice("abcdefgh") for _ in range(200))
    a = "x" * 60 + core
    b = core + "x" * 60            # equal length, but the best alignment is 60 off the diagonal
    assert full_distance(a, b) == 120
    assert fe._banded(a, b, 32) != 120                          # precondition: the first band is NOT enough
    assert fe.edit_distance(a, b) == 120


def test_cer_counts_on_normalized_text():
    errors, chars = fe.cer_counts("Ang  bata, ay MASAYA!", "ang bata ay masay")
    assert chars == len("ang bata ay masaya") and errors == 1
    assert fe.cer_counts("a b", "a b") == (0, 3)


@pytest.fixture
def english(monkeypatch):
    monkeypatch.setattr(langscore, "_LEXICON", {"meeting", "report", "send"})


def test_score_utterance_splits_errors_by_language_class(english):
    ref = "kailangan natin i-send ang report bago mag-meeting"
    hyp = "kailangan natin i-send ang repor bago mag-meeting"
    row = fe.score_utterance(ref, hyp)
    assert row["sub"] == 1 and row["del"] == 0 and row["ins"] == 0
    assert row["classes"]["en"]["ref"] == 1 and row["classes"]["en"]["err"] == 1     # "report"
    assert row["classes"]["tl"]["ref"] == row["langscore_ref_words"] - 1
    assert row["classes"]["tl"]["err"] == 0
    # score.py splits the hyphens (9 words), langscore keeps them (7): both are recorded.
    assert row["ref_words"] == 9 and row["langscore_ref_words"] == 7


def test_pooling_sums_errors_and_is_not_an_average_of_rates(english):
    short = fe.score_utterance("isa", "dalawa")                                    # 1 word, 100% WER
    long = fe.score_utterance(" ".join(["ang"] * 99), " ".join(["ang"] * 99))      # 99 words, 0% WER
    pool = fe.pooled([short, long])
    assert pool["ref_words"] == 100
    assert pool["wer"] == pytest.approx(0.01)            # an average of the two rates would say 0.5
    assert pool["utterances"] == 2 and pool["empty_transcripts"] == 0
    assert fe.pooled([fe.score_utterance("isa dalawa", "")])["empty_transcripts"] == 1


def test_pooled_class_error_rate_has_no_denominator_when_a_class_is_absent(english):
    pool = fe.pooled([fe.score_utterance("ang bata", "ang bata")])
    assert pool["classes"]["en"]["ref_words"] == 0 and pool["classes"]["en"]["error_rate"] is None


def test_bootstrap_is_seeded_and_brackets_the_pooled_value():
    rows = [fe.score_utterance(" ".join(["ang"] * 10), " ".join(["ang"] * (10 - (i % 3)))) for i in range(30)]
    lo, hi = fe.bootstrap_pooled(rows)
    assert (lo, hi) == fe.bootstrap_pooled(rows)
    assert lo <= fe.pooled(rows)["wer"] <= hi and lo < hi
    assert fe.bootstrap_pooled([]) is None


def test_sign_test():
    assert fe.sign_test_p(0, 0) == 1.0
    assert fe.sign_test_p(5, 5) == 1.0
    assert fe.sign_test_p(5, 0) == pytest.approx(0.0625)
    assert fe.sign_test_p(0, 5) == pytest.approx(0.0625)
    assert fe.sign_test_p(1, 9) == pytest.approx(2 * 11 / 1024)


def row(ref, hyp):
    return fe.score_utterance(ref, hyp)


def test_paired_compare_reports_direction_and_the_worst_regressions():
    ref = "isa dalawa tatlo apat lima"
    a = {"x": row(ref, ref), "y": row(ref, ref), "z": row(ref, "isa dalawa tatlo apat lima")}
    b = {"x": row(ref, "isa dalawa"), "y": row(ref, "isa dalawa tatlo apat"), "z": row(ref, ref)}
    result = fe.paired_compare(a, b)
    assert result["wer_a"] == 0 and result["wer_b"] == pytest.approx((3 + 1) / 15)
    assert result["wer_diff_b_minus_a"] > 0                   # positive: B is worse
    assert result["worst_regressions_of_b"] == [(3, "x"), (1, "y")]
    assert result["a_better"] == ["x", "y"] and result["b_better"] == []
    assert result["identical_error_counts"] == 1
    assert result["ci95"][0] <= result["wer_diff_b_minus_a"] <= result["ci95"][1]


def test_paired_compare_uses_only_shared_utterances():
    ref = "isa dalawa"
    result = fe.paired_compare({"x": row(ref, ref), "only-a": row(ref, "")}, {"x": row(ref, ref), "only-b": row(ref, "")})
    assert result["utterances"] == 1 and result["wer_diff_b_minus_a"] == 0
    with pytest.raises(ValueError):
        fe.paired_compare({"a": row(ref, ref)}, {"b": row(ref, ref)})


def test_english_tokens_lists_what_the_class_really_holds(english):
    counts = fe.english_tokens(["Mag-send ng report, report!", "ang bata"])
    assert counts == {"report": 2}


# ---- decode plumbing ----------------------------------------------------

def test_schedule_runs_every_arm_on_an_item_and_rotates_who_goes_first():
    plan = fe.schedule(["i0", "i1", "i2", "i3"], ["A", "B"], repeats=1)
    assert [arm for _, _, arm in plan] == ["A", "B", "B", "A", "A", "B", "B", "A"]
    assert [item for _, item, _ in plan] == ["i0", "i0", "i1", "i1", "i2", "i2", "i3", "i3"]
    three = fe.schedule(["i0", "i1", "i2"], ["A", "B", "C"], repeats=2)
    assert len(three) == 18
    assert sorted(arm for rep, item, arm in three if (rep, item) == (1, "i2")) == ["A", "B", "C"]
    assert fe.schedule(["i"], ["A"], repeats=3) == [(0, "i", "A"), (1, "i", "A"), (2, "i", "A")]


def test_parse_arm():
    name, binary, extra = fe.parse_arm("auto|/x/transcribe|--language auto --tier fast")
    assert (name, binary, extra) == ("auto", Path("/x/transcribe"), ["--language", "auto", "--tier", "fast"])
    assert fe.parse_arm("p6|/x/transcribe")[2] == []
    for bad in ("justname", "|/x", "name|"):
        with pytest.raises(Exception):
            fe.parse_arm(bad)


def test_decode_command_has_no_reference_and_takes_the_lock_first():
    cmd = fe.decode_command(Path("/b/transcribe"), Path("/a.wav"), Path("/o.json"), ["--tier", "best"], use_lock=True)
    assert cmd[0] == str(fe.LOCK_SCRIPT) and cmd[1] == "/b/transcribe"
    assert "--reference" not in cmd and "--no-diarize" in cmd and cmd[-2:] == ["--tier", "best"]
    assert fe.decode_command(Path("/b/t"), Path("/a.wav"), Path("/o.json"), [], use_lock=False)[0] == "/b/t"


def test_output_names_keep_the_repeat_suffix():
    assert fe.with_ext(Path("/d/item.r0"), ".json") == Path("/d/item.r0.json")
    assert fe.with_ext(Path("/d/item.r12"), ".report.json") == Path("/d/item.r12.report.json")


# ---- end to end, against a fake transcribe -----------------------------

FAKE = """#!{python}
import json, os, sys
args = sys.argv[1:]
audio = args[args.index("--audio") + 1]
out = args[args.index("--json") + 1]
language = args[args.index("--language") + 1] if "--language" in args else "tl"
stem = os.path.splitext(os.path.basename(audio))[0]
manifest = json.load(open(os.environ["FAKE_MANIFEST"]))
entry = next(e for group in manifest["sets"].values() for e in group if e["id"] == stem)
words = entry["ref"].replace(",", "").replace(".", "").split()
mode = {mode!r}
if mode == "drop-first":
    words = words[1:]
if mode == "auto" and language == "auto":
    words = words[:-2]
json.dump({{"transcript": " ".join(words), "rtf": 0.1, "decodeMs": 100, "durationMs": 1000, "loadMs": 5,
           "model": "fake", "language": language, "detectedLanguage": language, "windowLanguages": [language],
           "wordCount": len(words)}}, open(out, "w"))
sys.stderr.write("speech: 1 regions, 0:01 in 1 windows\\n")
if mode == "drop-first":
    sys.stderr.write("  1 window(s) needed a retry (a lead-in of silence, wider audio or half the window)\\n")
"""


def make_fake(path: Path, mode: str) -> Path:
    path.write_text(FAKE.format(python=sys.executable, mode=mode))
    path.chmod(0o755)
    return path


def write_source(src: Path, sentences: int) -> None:
    audio = src / "test" / "test"
    audio.mkdir(parents=True)
    rows = []
    for k in range(sentences):
        name = f"{k:03d}.wav"
        tone = array.array("f", [0.3 if (i // 40) % 2 else -0.3 for i in range(16000 * 2)])   # 2 s, float32 like FLEURS
        (audio / name).write_bytes(riff(tone.tobytes(), tag=3, bits=32))
        rows.append(f"{1000 + k}\t{name}\tAng bata ay masaya {k}, sa bahay.\tang bata ay masaya {k} sa bahay\t30\t32000\tMALE")
    (src / "test.tsv").write_text("\n".join(rows) + "\n")


@pytest.fixture
def prepared(tmp_path, monkeypatch):
    src, work = tmp_path / "src", tmp_path / "work"
    write_source(src, 60)
    assert fe.main(["prepare", "--src", str(src), "--work", str(work), "--subset", "5", "--seed", "7",
                    "--longform-seconds", "20", "30"]) == 0
    monkeypatch.setenv("FAKE_MANIFEST", str(work / "manifest.json"))
    return work


def test_prepare_writes_the_sets_and_the_audio(prepared):
    manifest = json.loads((prepared / "manifest.json").read_text())
    assert [len(manifest["sets"][k]) for k in ("subset", "longform")] == [5, 2]
    assert manifest["source"]["license"] == "CC-BY-4.0" and manifest["seed"] == 7
    lf1, lf2 = manifest["sets"]["longform"]
    assert lf1["duration_s"] >= 20 and lf2["duration_s"] >= 30
    assert set(lf1["parts"]).isdisjoint(lf2["parts"])           # the long-form files share no sentence
    for entry in manifest["sets"]["subset"]:
        with wave.open(entry["wav"]) as w:
            assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (16000, 1, 2)
    parts = [p for p in manifest["sets"]["parts"] if p["longform"] == "lf1"]
    assert [p["sent_id"] for p in parts] == lf1["parts"]
    # The long-form file really contains each part's samples at the recorded offset.
    with wave.open(lf1["wav"]) as whole:
        data = whole.readframes(whole.getnframes())
    part = parts[2]
    with wave.open(part["wav"]) as w:
        clip = w.readframes(w.getnframes())
    start = part["start_sample"] * 2
    assert part["end_sample"] - part["start_sample"] == len(clip) // 2
    assert data[start:start + len(clip)] == clip
    assert lf1["ref"] == " ".join(p["ref"] for p in parts)


def test_prepare_is_reproducible(tmp_path):
    src = tmp_path / "src"
    write_source(src, 60)
    hashes = []
    for name in ("one", "two"):
        work = tmp_path / name
        fe.main(["prepare", "--src", str(src), "--work", str(work), "--subset", "6", "--seed", "3",
                 "--longform-seconds", "20"])
        manifest = json.loads((work / "manifest.json").read_text())
        hashes.append([(e["id"], e["sha256"]) for k in ("subset", "longform") for e in manifest["sets"][k]])
    assert hashes[0] == hashes[1]


def test_decode_score_and_compare_end_to_end(prepared, tmp_path, capsys):
    good = make_fake(tmp_path / "good", "exact")
    bad = make_fake(tmp_path / "bad", "drop-first")
    assert fe.main(["decode", "--work", str(prepared), "--set", "subset", "--no-lock", "--repeats", "2",
                    "--arm", f"good|{good}", "--arm", f"bad|{bad}"]) == 0
    decoded = sorted(p.name for p in (prepared / "decode" / "subset" / "good").glob("*.json") if "report" not in p.name)
    assert len(decoded) == 10 and decoded[0].endswith(".r0.json")     # 5 items x 2 repeats
    capsys.readouterr()

    assert fe.main(["score", "--work", str(prepared), "--set", "subset", "--arm", "good", "--arm", "bad"]) == 0
    out = capsys.readouterr().out
    assert "| good | 5 |" in out and "| bad | 5 |" in out
    good_row = next(line for line in out.splitlines() if line.startswith("| good"))
    bad_row = next(line for line in out.splitlines() if line.startswith("| bad"))
    assert "| 0.0% |" in good_row                                   # an exact transcript scores 0
    assert "| 0 / 0 |" in good_row and "| 5 / 0 |" in bad_row                   # retried windows come from stderr
    assert any(line.startswith("| bad r1 | 5 |") for line in out.splitlines())    # the second repeat is its own row
    assert "run-to-run, good: 5 items decoded [2] times, 0 produced different text" in out

    assert fe.main(["compare", "--work", str(prepared), "--set", "subset", "--a", "good", "--b", "bad"]) == 0
    out = capsys.readouterr().out
    assert "difference +" in out and "good had fewer errors: 5" in out
    assert "transcripts byte-identical between the arms: 0 of 5" in out
    assert "worse than good" in out


def test_a_resumed_decode_does_not_run_finished_items_again(prepared, tmp_path):
    fake = make_fake(tmp_path / "fake", "exact")
    args = ["decode", "--work", str(prepared), "--set", "subset", "--no-lock", "--arm", f"x|{fake}"]
    fe.main(args)
    target = prepared / "decode" / "subset" / "x"
    stamp = {p.name: p.stat().st_mtime_ns for p in target.glob("*.r0.json")}
    fe.main(args)
    assert stamp == {p.name: p.stat().st_mtime_ns for p in target.glob("*.r0.json")}
    fe.main(args + ["--force"])
    assert stamp != {p.name: p.stat().st_mtime_ns for p in target.glob("*.r0.json")}


def test_forced_language_and_auto_are_separate_arms(prepared, tmp_path, capsys):
    fake = make_fake(tmp_path / "fake", "auto")
    fe.main(["decode", "--work", str(prepared), "--set", "subset", "--no-lock",
             "--arm", f"tl|{fake}|--language tl", "--arm", f"auto|{fake}|--language auto"])
    record = json.loads(next((prepared / "decode" / "subset" / "auto").glob("*.r0.json")).read_text())
    assert record["language"] == "auto" and "--language" in record["cmd"]
    capsys.readouterr()
    fe.main(["compare", "--work", str(prepared), "--set", "subset", "--a", "tl", "--b", "auto"])
    assert "good" not in capsys.readouterr().out
    fe.main(["score", "--work", str(prepared), "--set", "subset", "--arm", "tl", "--arm", "auto"])
    out = capsys.readouterr().out
    tl_row = next(line for line in out.splitlines() if line.startswith("| tl"))
    auto_row = next(line for line in out.splitlines() if line.startswith("| auto"))
    assert "| 0.0% |" in tl_row and "| 0.0% |" not in auto_row


def test_longform_report_pairs_each_file_with_its_parts(prepared, tmp_path, capsys):
    fake = make_fake(tmp_path / "fake", "exact")
    for name in ("longform", "parts"):
        fe.main(["decode", "--work", str(prepared), "--set", name, "--no-lock", "--repeats", "2" if name == "longform" else "1",
                 "--arm", f"x|{fake}"])
    capsys.readouterr()
    assert fe.main(["longform", "--work", str(prepared), "--arm", "x"]) == 0
    out = capsys.readouterr().out
    assert "| lf1 |" in out and "| lf2 |" in out
    assert "| 2 | 0.0% (0.0%-0.0%) |" in out


def test_a_failed_decode_is_recorded_and_excluded_from_scores(prepared, tmp_path, capsys):
    broken = tmp_path / "broken"
    broken.write_text(f"#!{sys.executable}\nimport sys\nsys.stderr.write('boom')\nsys.exit(3)\n")
    broken.chmod(0o755)
    fe.main(["decode", "--work", str(prepared), "--set", "subset", "--no-lock", "--limit", "2", "--arm", f"b|{broken}"])
    record = json.loads(next((prepared / "decode" / "subset" / "b").glob("*.r0.json")).read_text())
    assert record["ok"] is False and "exit code 3" in record["error"]
    capsys.readouterr()
    fe.main(["score", "--work", str(prepared), "--set", "subset", "--arm", "b"])
    assert "no decoded records for arm b" in capsys.readouterr().err


def test_lock_is_held_once_per_batch_and_never_nested(prepared, tmp_path, monkeypatch):
    log = tmp_path / "lock.log"
    lock = tmp_path / "lock.sh"
    lock.write_text('#!/bin/bash\necho acquired >> "$LOCK_LOG"\nexec "$@"\n')
    lock.chmod(0o755)
    monkeypatch.setattr(fe, "LOCK_SCRIPT", lock)
    monkeypatch.setenv("NOTERO_BENCH_LOCK", str(lock))        # the batch child must not reach the real queue
    monkeypatch.setenv("LOCK_LOG", str(log))
    good = make_fake(tmp_path / "good", "exact")
    bad = make_fake(tmp_path / "bad", "drop-first")
    args = ["decode", "--work", str(prepared), "--set", "subset", "--lock-batch", "4",
            "--arm", f"good|{good}", "--arm", f"bad|{bad}"]
    assert fe.main(args) == 0
    assert len(log.read_text().splitlines()) == 3          # 10 decodes in batches of 4: 4 + 4 + 2
    done = sorted(p.name for arm in ("good", "bad") for p in (prepared / "decode" / "subset" / arm).glob("*.r0.json"))
    assert len(done) == 10
    assert not list((prepared / "decode" / "_batches").glob("*.json"))     # batch plans are cleaned up
    assert fe.main(args) == 0
    assert len(log.read_text().splitlines()) == 3          # everything finished: no lock taken at all


def test_a_lock_per_decode_is_still_the_default(prepared, tmp_path, monkeypatch):
    log = tmp_path / "lock.log"
    lock = tmp_path / "lock.sh"
    lock.write_text('#!/bin/bash\necho acquired >> "$LOCK_LOG"\nexec "$@"\n')
    lock.chmod(0o755)
    monkeypatch.setattr(fe, "LOCK_SCRIPT", lock)
    monkeypatch.setenv("NOTERO_BENCH_LOCK", str(lock))        # the batch child must not reach the real queue
    monkeypatch.setenv("LOCK_LOG", str(log))
    fake = make_fake(tmp_path / "fake", "exact")
    fe.main(["decode", "--work", str(prepared), "--set", "subset", "--limit", "3", "--arm", f"x|{fake}"])
    assert len(log.read_text().splitlines()) == 3


# ---- code-switch counts, the CER guard, and the user's own reference set ----

def test_code_switch_points_are_counted_and_pooled(english):
    ref = "kailangan natin i-send ang report bago mag-meeting"
    perfect = fe.score_utterance(ref, ref)
    broken = fe.score_utterance(ref, "kailangan natin i-send ang bago mag-meeting")      # drops "report"
    assert perfect["switch_positions"] == 2 and perfect["switch_errors"] == 0
    assert broken["switch_errors"] >= 1
    pool = fe.pooled([perfect, broken])
    assert pool["code_switch"]["positions"] == 4
    assert pool["code_switch"]["error_rate"] == pytest.approx(pool["code_switch"]["errors"] / 4)
    assert fe.pooled([fe.score_utterance("ang bata", "ang bata")])["code_switch"]["error_rate"] is None


def test_cer_is_skipped_for_very_long_text_and_pooling_says_so(monkeypatch):
    monkeypatch.setattr(fe, "CER_MAX_CHARS", 30)
    short = fe.score_utterance("ang bata", "ang bata")
    long = fe.score_utterance(" ".join(["ang"] * 30), " ".join(["ang"] * 29))
    assert short["cer_skipped"] is False and long["cer_skipped"] is True
    assert long["char_ref"] == 0 and long["sub"] + long["del"] + long["ins"] == 1       # the WER is still scored
    pool = fe.pooled([short, long])
    assert pool["cer_skipped_rows"] == 1 and pool["cer"] == 0.0


def reference_folder(tmp_path: Path, entries: list[dict] | None = None) -> Path:
    folder = tmp_path / "notero-references-2026-11-01"
    (folder / "audio").mkdir(parents=True)
    (folder / "refs").mkdir()
    (folder / "audio" / "aaa-111.m4a").write_bytes(b"not really audio")
    (folder / "refs" / "aaa-111.txt").write_text("Kailangan natin i-send ang report.\nSige po.\n", encoding="utf8")
    manifest = entries if entries is not None else [
        {"id": "aaa-111", "audio": "audio/aaa-111.m4a", "ref": "refs/aaa-111.txt", "category": "own",
         "title": "Weekly", "durationMs": 61000}]
    (folder / "manifest.json").write_text(json.dumps(manifest))
    return folder


def test_import_references_builds_a_work_manifest_without_copying_audio(tmp_path, capsys):
    folder = reference_folder(tmp_path)
    work = tmp_path / "work"
    assert fe.main(["import-references", "--refs", str(folder), "--work", str(work)]) == 0
    manifest = json.loads((work / "manifest.json").read_text())
    entry = manifest["sets"]["subset"][0]
    assert entry["id"] == "aaa-111" and entry["wav"] == str((folder / "audio" / "aaa-111.m4a").resolve())
    assert entry["ref"].startswith("Kailangan natin") and entry["duration_s"] == 61.0
    assert manifest["source"]["dataset"] == "user-reference-set" and "private" in manifest["source"]["license"]
    assert not list(work.rglob("*.m4a"))                      # the audio stays where the app wrote it
    assert "1 recordings, 8 reference words" in capsys.readouterr().out


def test_import_references_refuses_paths_outside_the_folder_and_bad_ids(tmp_path):
    outside = tmp_path / "secret.txt"
    outside.write_text("private")
    folder = reference_folder(tmp_path, [{"id": "aaa-111", "audio": "audio/aaa-111.m4a", "ref": "../secret.txt"}])
    with pytest.raises(ValueError, match="leaves"):
        fe.references_to_manifest(folder, json.loads((folder / "manifest.json").read_text()))
    with pytest.raises(ValueError, match="unusable id"):
        fe.references_to_manifest(folder, [{"id": "../x", "audio": "audio/aaa-111.m4a", "ref": "refs/aaa-111.txt"}])
    with pytest.raises(FileNotFoundError):
        fe.references_to_manifest(folder, [{"id": "ok", "audio": "audio/missing.m4a", "ref": "refs/aaa-111.txt"}])
    with pytest.raises(ValueError, match="no recordings"):
        fe.references_to_manifest(folder, [])


def test_an_imported_reference_set_goes_through_decode_and_score(tmp_path, capsys, monkeypatch):
    folder = reference_folder(tmp_path)
    work = tmp_path / "work"
    fe.main(["import-references", "--refs", str(folder), "--work", str(work)])
    monkeypatch.setenv("FAKE_MANIFEST", str(work / "manifest.json"))
    fake = make_fake(tmp_path / "fake", "exact")
    assert fe.main(["decode", "--work", str(work), "--set", "subset", "--no-lock", "--arm", f"x|{fake}"]) == 0
    capsys.readouterr()
    assert fe.main(["score", "--work", str(work), "--set", "subset", "--arm", "x"]) == 0
    assert "| x | 1 | 8 |" in capsys.readouterr().out


# ---- the audited English count ----------------------------------------------

def test_audited_english_drops_tagalog_words_that_spell_like_english(english, monkeypatch):
    # "report" is English; "iba" is a Tagalog word that happens to be in an English word list.
    monkeypatch.setattr(langscore, "_LEXICON", {"meeting", "report", "send", "iba"})
    ref = "may iba pang report"
    assert fe.audited_english(ref, ref, frozenset()) == (2, 0)                 # langscore counts "iba" as English
    assert fe.audited_english(ref, ref, frozenset({"iba"})) == (1, 0)
    assert fe.audited_english(ref, "may pang", frozenset({"iba"})) == (1, 1)    # "report" lost: one audited error
    assert fe.audited_english(ref, "may pang report", frozenset({"iba"})) == (1, 0)   # "iba" lost: not an English error
    row = fe.score_utterance(ref, "may pang report", frozenset({"iba"}))
    assert (row["en_audited_ref"], row["en_audited_err"]) == (1, 0) and row["classes"]["en"]["ref"] == 2
    pool = fe.pooled([row])
    assert pool["en_audited"] == {"ref_words": 1, "errors": 0, "error_rate": 0.0}
    assert fe.pooled([fe.score_utterance("ang bata", "ang bata")])["en_audited"]["error_rate"] is None


def test_the_collision_file_loads_without_its_comments():
    tokens = fe.load_collisions(fe.COLLISIONS_FILE)
    assert {"pa", "iba", "tubig", "halos"} <= tokens
    assert not any(t.startswith("#") or t != t.lower() or " " in t for t in tokens)
    assert "greenland" not in tokens and "hydrogen" not in tokens     # foreign names and English terms stay English


def test_ids_selects_items_and_unknown_ids_are_refused(prepared, tmp_path, capsys):
    fake = make_fake(tmp_path / "fake", "exact")
    assert fe.main(["decode", "--work", str(prepared), "--set", "longform", "--no-lock", "--ids", "lf2",
                    "--arm", f"x|{fake}"]) == 0
    done = sorted(p.name for p in (prepared / "decode" / "longform" / "x").glob("*.r0.json"))
    assert done == ["lf2.r0.json"]
    assert fe.main(["decode", "--work", str(prepared), "--set", "longform", "--no-lock", "--ids", "lf9",
                    "--arm", f"x|{fake}"]) == 2
    assert "not in the longform set: lf9" in capsys.readouterr().err


# ---- abrupt starts -----------------------------------------------------------

def tone(seconds: float, amplitude: int, period: int = 40) -> array.array:
    return array.array("h", [amplitude if (i // (period // 2)) % 2 else -amplitude
                             for i in range(int(seconds * 16000))])


def quiet(seconds: float) -> array.array:
    return array.array("h", bytes(2 * int(seconds * 16000)))


def test_speech_onset_finds_the_first_loud_frame_on_a_frame_boundary():
    samples = quiet(0.5) + tone(1.0, 8000)
    assert fe.speech_onset(samples) == 8000                    # 0.5 s at 16 kHz
    assert fe.speech_onset(tone(1.0, 8000)) == 0                # already starts at speech
    assert fe.speech_onset(quiet(1.0)) == 0                     # nothing to find: leave it alone
    assert fe.speech_onset(array.array("h")) == 0 and fe.speech_onset(array.array("h", [5] * 50)) == 0


def test_speech_onset_tracks_the_recordings_own_level_and_ignores_a_noise_floor():
    noise = tone(0.4, 30)                                       # a steady hiss, 0.4% of the speech level
    samples = noise + tone(1.0, 8000)
    assert fe.speech_onset(samples) == 6400                     # 0.4 s: the hiss is not speech
    soft = noise + tone(1.0, 400)                               # a quiet speaker: the onset is relative
    assert fe.speech_onset(soft) == 6400
    loud_hiss = tone(0.4, 150) + tone(1.0, 8000)                # a noisier room: 150 is below 10% of 8000
    assert fe.speech_onset(loud_hiss) == 6400
    faint = tone(0.4, 3) + tone(1.0, 50)                        # a very quiet recording: 3 against 50
    assert fe.speech_onset(faint) == 6400


def test_trim_to_onset_keeps_every_sample_from_the_onset_on():
    samples = quiet(0.3) + tone(0.5, 5000)
    trimmed = fe.trim_to_onset(samples)
    assert len(trimmed) == len(samples) - 4800
    assert list(trimmed) == list(samples[4800:]) and trimmed[0] != 0


def test_add_abrupt_writes_trimmed_copies_with_the_same_references(prepared, capsys):
    manifest = json.loads((prepared / "manifest.json").read_text())
    # The fixtures start with speech at sample 0, so make one with a lead-in to check the trim.
    first = manifest["sets"]["subset"][0]
    lead = quiet(0.5) + fe.read_pcm16_mono(Path(first["wav"]).read_bytes())[1]
    Path(first["wav"]).write_bytes(fe.wav_bytes(lead))
    assert fe.main(["add-abrupt", "--work", str(prepared), "--n", "3"]) == 0
    out = capsys.readouterr().out
    assert "3 abrupt-start utterances" in out
    after = json.loads((prepared / "manifest.json").read_text())
    abrupt = after["sets"]["abrupt"]
    assert [a["id"] for a in abrupt] == [f"{s['id']}-abrupt" for s in after["sets"]["subset"][:3]]
    assert abrupt[0]["ref"] == first["ref"] and abrupt[0]["trimmed_s"] == pytest.approx(0.5, abs=0.02)
    assert abrupt[0]["wav"] != first["wav"]
    trimmed_samples = fe.read_pcm16_mono(Path(abrupt[0]["wav"]).read_bytes())[1]
    assert len(trimmed_samples) == len(lead) - 8000             # the file on disk has the lead-in cut off
    assert abrupt[0]["duration_s"] == pytest.approx(first["duration_s"], abs=0.02)   # the lead-in is gone, the speech is whole
    assert after["sets"]["subset"] == manifest["sets"]["subset"]          # the other sets are untouched
    assert not (prepared / "manifest.json.tmp").exists()


def test_abrupt_set_goes_through_decode_and_score(prepared, tmp_path, capsys):
    fe.main(["add-abrupt", "--work", str(prepared), "--n", "2"])
    fake = make_fake(tmp_path / "fake", "exact")
    capsys.readouterr()
    assert fe.main(["decode", "--work", str(prepared), "--set", "abrupt", "--no-lock", "--arm", f"x|{fake}"]) == 0
    assert fe.main(["score", "--work", str(prepared), "--set", "abrupt", "--arm", "x"]) == 0
    assert "| x | 2 |" in capsys.readouterr().out
