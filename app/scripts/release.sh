#!/usr/bin/env bash
# Builds and publishes a release.
#
# The app does not update itself: it downloads no code and checks no signature.
# A release is therefore a zip on the GitHub releases page that a user
# downloads and unpacks by hand. This script builds that zip from a clean
# commit, tags it, and publishes it with the CHANGELOG section as the notes.
#
#     scripts/release.sh                 build and publish VERSION
#     scripts/release.sh --dry-run       everything except the publish
#     scripts/release.sh --notes FILE    a short summary for the release page
#                                        in place of the CHANGELOG section
#
# See docs/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
NOTES_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --notes)
            shift
            NOTES_FILE=${1:-}
            [ -n "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ] || die "--notes needs a file with text in it."
            ;;
        *) echo "usage: scripts/release.sh [--dry-run] [--notes FILE]" >&2; exit 2 ;;
    esac
    shift
done

BUILD_DIR=".build/release-tools"
mkdir -p "$BUILD_DIR"

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

# The release notes are the install steps, then what is new, then one line
# about updating. The install steps go on every release page because the
# right-click-Open step is the one thing a user has to know that the app
# cannot tell them itself.
#
# "What is new" is the file given with --notes, which should be a short
# grouped summary written for the page. Without --notes it is the CHANGELOG
# section for this version, which is the full record and reads long on a
# release page. The CHANGELOG must have the section either way.
SECTION="$BUILD_DIR/section.md"
awk -v v="$VERSION" '
    $0 ~ "^## " v "([^0-9.]|$)" { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' ../CHANGELOG.md > "$SECTION"
[ -s "$SECTION" ] || die "CHANGELOG.md has no section for $VERSION."

NOTES="$BUILD_DIR/notes.md"
{
cat <<INSTALL
## Install

1. Download \`Notero-$VERSION.zip\` and unpack it.
2. Move \`Notero.app\` to \`/Applications\`.
3. For the first launch, right-click Notero → Open. The app is not Developer ID signed, so macOS may block a normal double-click.
4. Notero requires macOS 15+ and Apple silicon.

On first launch, Notero downloads approximately 1.9 GB of AI model weights from Hugging Face. This is the app's only network request.

## What's New

INSTALL
if [ -n "$NOTES_FILE" ]; then cat "$NOTES_FILE"; else cat "$SECTION"; fi
printf '\n\nYour existing recordings and notes remain unchanged when updating.\n'
} > "$NOTES"

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
