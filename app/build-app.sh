#!/usr/bin/env bash
# Assembles Notero.app.
#
# The bundle is not cosmetic. macOS only grants microphone access to a signed
# app bundle carrying NSMicrophoneUsageDescription -- a bare SwiftPM executable
# is refused, and the refusal looks like silence rather than an error. SwiftData
# also derives paths from the bundle identifier, so it needs a real one.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="Notero.app"
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
cp "$BIN" "$APP/Contents/MacOS/Notero"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Notero</string>
    <key>CFBundleDisplayName</key>       <string>Notero</string>
    <key>CFBundleIdentifier</key>        <string>local.notero</string>
    <key>CFBundleVersion</key>           <string>$BUILD</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleExecutable</key>        <string>Notero</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Notero records audio from your microphone to transcribe it on this Mac. Audio never leaves the machine.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Notero records what this Mac plays, so the people on a call are transcribed as clearly as the people in the room. Audio never leaves the machine.</string>
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

# codesign needs a real file, not a process substitution. A directory keeps
# the file and its parent under one trap; appending a suffix to the variable
# would leave the path mktemp actually created behind on every build.
ENTITLEMENTS_DIR=$(mktemp -d -t transcriber)
trap 'rm -rf "$ENTITLEMENTS_DIR"' EXIT
ENTITLEMENTS="$ENTITLEMENTS_DIR/entitlements.plist"
cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
ENT

# A real signing identity when the machine has one, ad-hoc when it does not.
#
# This is not only about distribution. TCC keys its permissions to the code
# signature, and an ad-hoc signature has nothing stable in it but the hash of
# the binary -- so every rebuild is a different app as far as macOS is
# concerned, and the system audio permission has to be granted again. Measured:
# ad-hoc lost the grant on each rebuild, and signing with the Apple Development
# identity kept it, because the requirement becomes the bundle id plus the team
# rather than the hash.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
if [ -n "$IDENTITY" ]; then
    echo "signing as $IDENTITY"
else
    IDENTITY="-"
    echo "signing ad-hoc; system audio permission will be asked for again after every build"
fi
codesign --force --deep --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP" 2>&1 \
    | { grep -v "replacing existing signature" || true; }

echo "built $APP ($VERSION, build $BUILD)"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
