#!/usr/bin/env bash
# Generates a synthetic Taglish sample for RTF benchmarking.
#
# This is NOT an accuracy fixture. macOS has no Filipino voice, so this uses the
# Indonesian one -- close enough in phonology (both Austronesian, similar vowel
# inventory) to produce a realistic token density, which is what drives decode
# time. The acoustics are wrong for measuring WER. Use your own recordings for
# that; Phase 2's exit criterion depends on real audio.
set -euo pipefail
cd "$(dirname "$0")"
out=audio/synthetic-taglish.wav
tmp=$(mktemp -t taglish).aiff
# mktemp created "${tmp%.aiff}"; the .aiff was appended to the variable, so
# both paths need removing or one empty file leaks per run.
trap 'rm -f "$tmp" "${tmp%.aiff}"' EXIT
say -v Damayanti -r 175 -f synthetic-taglish.txt -o "$tmp"
afconvert -f WAVE -d LEI16@16000 -c 1 "$tmp" "$out"
echo "wrote $out"
