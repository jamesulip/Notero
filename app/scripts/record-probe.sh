#!/usr/bin/env bash
# Wraps the `transcribe` command line tool in an app bundle so that its capture
# diagnostics can actually run.
#
# macOS will not give system audio permission to a command line tool. The
# prompt needs a bundle identifier to attach the answer to and a foreground
# application to appear in front of, and a tool launched from a terminal has
# neither -- TCC decides the request belongs to the terminal and refuses it
# without asking anybody. Launched through LaunchServices from a signed bundle,
# the same binary is asked properly and the answer is remembered.
#
#   scripts/record-probe.sh --devices
#   scripts/record-probe.sh --record --source both --seconds 20 --out /tmp/x.m4a
#   scripts/record-probe.sh --channels --seconds 15
#
# Output goes to a log file, because LaunchServices discards stderr.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG=${CONFIG:-debug}
APP="$(mktemp -d -t notero-probe)/RecordProbe.app"
LOG="${PROBE_LOG:-/tmp/notero-record-probe.log}"

swift build -c "$CONFIG" --product transcribe >&2

mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/transcribe" "$APP/Contents/MacOS/RecordProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RecordProbe</string>
    <key>CFBundleIdentifier</key><string>local.notero.recordprobe</string>
    <key>CFBundleExecutable</key><string>RecordProbe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>RecordProbe records the microphone to check that capture works.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>RecordProbe records this Mac's audio to check that capture works.</string>
</dict>
</plist>
PLIST

ENTITLEMENTS="$APP/../entitlements.plist"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict><key>com.apple.security.device.audio-input</key><true/></dict>
</plist>
ENT

# The same identity rule as build-app.sh, and for the same reason: TCC keys the
# permission to the signature, and an ad-hoc one changes with every build.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
[ -n "$IDENTITY" ] || IDENTITY="-"
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP" 2>&1 \
    | { grep -v "replacing existing signature" || true; }

: > "$LOG"
open -a "$APP" --args "$@" --gui --log "$LOG"
echo "running; log: $LOG" >&2
sleep 2
tail -f "$LOG"
