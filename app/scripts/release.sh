#!/usr/bin/env bash
# Builds, signs and publishes a release the app's updater will accept.
#
# The updater installs nothing it cannot check against the Ed25519 public key
# compiled into it (`UpdateSource.publicKey`). This script is the other half of
# that: it signs the zip with the private half and refuses to publish if the
# two do not belong together. A release published any other way -- by hand, by
# CI, by dragging a zip into the GitHub page -- is a release no installed copy
# can accept.
#
#     scripts/release.sh              build, sign and publish VERSION
#     scripts/release.sh --dry-run    everything except the publish
#
# Once, before the first release:
#
#     scripts/release.sh --init-key   make the signing key
#
# See docs/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --init-key) INIT_KEY=1 ;;
    "") ;;
    *) echo "usage: scripts/release.sh [--dry-run|--init-key]" >&2; exit 2 ;;
esac

BUILD_DIR=".build/release-tools"
RELKEY="$BUILD_DIR/relkey"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }

# --- the signing tool ------------------------------------------------------
# Compiled from Update.swift, so the signature it writes and the signature the
# app parses can never drift apart.
say "building the signing tool…"
mkdir -p "$BUILD_DIR"
swiftc -O -o "$RELKEY" scripts/relkey.swift Sources/TranscriberCore/Update.swift

if [ "${INIT_KEY:-0}" = 1 ]; then
    "$RELKEY" generate
    exit 0
fi

# --- the two halves of the key must match ----------------------------------
EMBEDDED=$(sed -n 's/.*public static let publicKey = "\(.*\)".*/\1/p' \
    Sources/TranscriberCore/Update.swift)
[ -n "$EMBEDDED" ] || die "Update.swift has no update key. Run scripts/release.sh --init-key,
then paste the printed line into Sources/TranscriberCore/Update.swift."

PRIVATE_HALF=$("$RELKEY" public) || exit 1
[ "$EMBEDDED" = "$PRIVATE_HALF" ] || die "the key in Update.swift is not the public half of the
signing key on this machine. Publishing would make a release no installed copy accepts.
  in Update.swift: $EMBEDDED
  from the key:    $PRIVATE_HALF"

# --- what is being released ------------------------------------------------
VERSION=$(tr -d '[:space:]' < VERSION)
TAG="v$VERSION"
[ -n "$VERSION" ] || die "VERSION is empty."

if [ -n "$(git status --porcelain)" ]; then
    die "the working tree has changes. Commit them first: the build number comes
from the commit count, and a release must be reproducible from a commit."
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    die "$TAG already exists. Bump VERSION."
fi

# The release notes are the CHANGELOG section for this version: from its
# heading to the next one.
NOTES="$BUILD_DIR/notes.md"
awk -v v="$VERSION" '
    $0 ~ "^## " v "([^0-9.]|$)" { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' ../CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || die "CHANGELOG.md has no section for $VERSION."

# --- build and package -----------------------------------------------------
say "building Transcriber $VERSION…"
./build-app.sh release

DIST="dist"
ZIP="$DIST/Transcriber-$VERSION.zip"
rm -rf "$DIST"
mkdir -p "$DIST"

say "packaging…"
# ditto, not zip: the executable bit and the code signature have to survive.
ditto -c -k --sequesterRsrc --keepParent Transcriber.app "$ZIP"

say "signing…"
"$RELKEY" sign "$ZIP"
"$RELKEY" verify "$ZIP" "$EMBEDDED"

printf '\n%s\n' "$(ls -lh "$ZIP" | awk '{print $9, $5}')"

# --- publish ---------------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
    say "dry run: not tagging and not publishing. The signed zip is in $DIST/."
    exit 0
fi

command -v gh >/dev/null || die "gh is not installed. brew install gh"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. gh auth login"

say "publishing $TAG…"
git tag -a "$TAG" -m "Transcriber $VERSION"
git push origin "$TAG"
gh release create "$TAG" \
    --title "Transcriber $VERSION" \
    --notes-file "$NOTES" \
    "$ZIP" "$ZIP.sig"

say "published. Installed copies will see $TAG at their next check."
