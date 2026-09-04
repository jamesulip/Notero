#!/usr/bin/env bash
# Builds and publishes a release.
#
# The app does not update itself: it downloads no code and checks no signature.
# A release is therefore a zip on the GitHub releases page that a user
# downloads and unpacks by hand. This script builds that zip from a clean
# commit, tags it, and publishes it with the CHANGELOG section as the notes.
#
#     scripts/release.sh              build and publish VERSION
#     scripts/release.sh --dry-run    everything except the publish
#
# See docs/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    "") ;;
    *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac

BUILD_DIR=".build/release-tools"
mkdir -p "$BUILD_DIR"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }

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
say "building Notero $VERSION…"
./build-app.sh release

DIST="dist"
ZIP="$DIST/Notero-$VERSION.zip"
rm -rf "$DIST"
mkdir -p "$DIST"

say "packaging…"
# ditto, not zip: the executable bit and the code signature have to survive.
ditto -c -k --sequesterRsrc --keepParent Notero.app "$ZIP"

printf '\n%s\n' "$(ls -lh "$ZIP" | awk '{print $9, $5}')"

# --- publish ---------------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
    say "dry run: not tagging and not publishing. The zip is in $DIST/."
    exit 0
fi

command -v gh >/dev/null || die "gh is not installed. brew install gh"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. gh auth login"

say "publishing $TAG…"
git tag -a "$TAG" -m "Notero $VERSION"
git push origin "$TAG"
gh release create "$TAG" \
    --title "Notero $VERSION" \
    --notes-file "$NOTES" \
    "$ZIP"

say "published. The zip is on the releases page."
