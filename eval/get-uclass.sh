#!/bin/sh
# Download the UCLASS benchmark fixture. The audio is not in this repository.
#
# Source: UCLASS, the UCL Archive of Stuttered Speech.
#   https://www.uclass.psychol.ucl.ac.uk/
# UCLASS is free for research and teaching. Two conditions apply to any use:
#   1. acknowledge the source of the data;
#   2. state that the data collection was supported by the Wellcome Trust.
# UCL redacts names and postcodes in the audio. Do not try to recover them.
set -e

BASE="https://www.uclass.psychol.ucl.ac.uk/Release2/Monologue"
ID="${1:-M_1017_11y8m_1}"
DIR="$(dirname "$0")"

mkdir -p "$DIR/audio" "$DIR/refs"
echo "fetching $ID …"
curl -fsS -o "$DIR/audio/$ID.wav" "$BASE/AudioOnly/wav/$ID.wav"

# Most files carry a word-level transcript; M_1017_11y8m_1 is syllable-level.
for kind in word syll; do
    if curl -fsS -o "$DIR/refs/$ID.cha" "$BASE/Annotation/chat/$ID.$kind.orth.cha"; then
        break
    fi
done
test -s "$DIR/refs/$ID.cha" || { echo "no transcript for $ID" >&2; exit 1; }
echo "audio      $DIR/audio/$ID.wav"
echo "reference  $DIR/refs/$ID.cha"
echo
echo "Only four monologues carry a transcript:"
echo "  M_1017_11y8m_1  M_1017_13y2m_1  M_0017_19y2m_1  M_0065_20y1m_1"
