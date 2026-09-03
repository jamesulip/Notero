#!/usr/bin/env bash
# Screenshots the running Transcriber window, optionally clicking first.
#
#     scripts/snap.sh out.png                       # capture the main window
#     scripts/snap.sh out.png 858 296               # click, wait, capture
#     scripts/snap.sh out.png 1535 564 right        # right-click, capture
#     WINDOW=2 scripts/snap.sh out.png              # another window (Settings)
#
# Writes out.png at full resolution and out.small.png scaled to 1000 px wide,
# which is the size a model or a quick look wants. Prints the window origin
# and the scale so image coordinates map back to screen points:
# screen = origin + image_xy * scale.
#
# Refuses to click unless Transcriber is frontmost: clicks go to whatever is
# in front, and a right-click meant for the app once opened another app's
# menu instead. If the app will not come to the front, someone is using the
# Mac -- stop rather than fight them for focus.
set -euo pipefail

OUT=${1:?output png}
X=${2:-}
Y=${3:-}
MODE=${4:-left}
WINDOW=${WINDOW:-1}
HERE=$(cd "$(dirname "$0")" && pwd)

if ! pgrep -x Transcriber >/dev/null; then
    echo "Transcriber is not running" >&2
    exit 1
fi

osascript -e 'tell application "Transcriber" to activate' >/dev/null
sleep 0.6
FRONT=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true')
if [[ "$FRONT" != "Transcriber" ]]; then
    echo "refusing: $FRONT is frontmost, not Transcriber" >&2
    exit 3
fi

if [[ -n "$X" && -n "$Y" ]]; then
    CLICK="$HERE/click"
    if [[ ! -x "$CLICK" || "$HERE/click.swift" -nt "$CLICK" ]]; then
        swiftc -O "$HERE/click.swift" -o "$CLICK"
    fi
    "$CLICK" "$X" "$Y" "$MODE"
    sleep 1.2
fi

BOUNDS=$(osascript -e "tell application \"System Events\" to tell process \"Transcriber\" to get {position, size} of window $WINDOW")
# "717, 39, 1083, 1065"
IFS=', ' read -r PX PY W H <<<"$(echo "$BOUNDS" | tr -d ' ' | tr ',' ' ')"

screencapture -x -R"$PX,$PY,$W,$H" "$OUT"
SMALL="${OUT%.png}.small.png"
sips -Z 1000 "$OUT" --out "$SMALL" >/dev/null
SCALE=$(python3 -c "print(round($W/1000, 4))")
echo "window origin ($PX, $PY) size ${W}x${H}; small image scale $SCALE"
echo "wrote $OUT and $SMALL"
