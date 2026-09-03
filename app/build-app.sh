#!/usr/bin/env bash
# Assembles Transcriber.app.
#
# The bundle is not cosmetic. macOS only grants microphone access to a signed
# app bundle carrying NSMicrophoneUsageDescription -- a bare SwiftPM executable
# is refused, and the refusal looks like silence rather than an error. SwiftData
# also derives paths from the bundle identifier, so it needs a real one.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="Transcriber.app"
BIN=".build/$CONFIG/Transcriber"

# Marketing version from VERSION; build number from the commit count, so two
# bundles from different commits never share one. Override either:
#     VERSION=1.2.0 BUILD=57 ./build-app.sh
VERSION=${VERSION:-$(tr -d '[:space:]' < VERSION)}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

echo "building $VERSION ($BUILD, $CONFIG)…"
swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Transcriber"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Transcriber</string>
    <key>CFBundleDisplayName</key>       <string>Transcriber</string>
    <key>CFBundleIdentifier</key>        <string>local.transcriber</string>
    <key>CFBundleVersion</key>           <string>$BUILD</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleExecutable</key>        <string>Transcriber</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Transcriber records audio from your microphone to transcribe it on this Mac. Audio never leaves the machine.</string>
    <!-- Declared so dropping media onto the Dock icon works, not only onto the window. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Audio or Video</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.movie</string>
                <string>public.mp3</string>
                <string>com.microsoft.waveform-audio</string>
                <string>public.mpeg-4-audio</string>
                <string>com.apple.quicktime-movie</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# codesign needs a real file, not a process substitution.
ENTITLEMENTS=$(mktemp -t transcriber).plist
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
ENT

# Ad-hoc signature. Enough for the microphone prompt on this machine; a real
# Developer ID would be needed to run it anywhere else.
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP" 2>&1 \
    | grep -v "replacing existing signature" || true

echo "built $APP ($VERSION, build $BUILD)"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
