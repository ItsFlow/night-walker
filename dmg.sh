#!/usr/bin/env bash
#
# Wrap the Night Walker .app in a friend-friendly compressed DMG: the app
# plus an /Applications symlink so they can drag-install. Relies on
# bundle.sh for the universal ad-hoc-signed app. Does not notarize and
# does not Developer-ID sign the disk image.
#
# Output: ./dist/NightWalker-<VERSION>.dmg
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Night Walker"
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$REPO_DIR/bundle.sh" | head -1)"
[[ -n "$VERSION" ]] || { echo "error: could not read VERSION from bundle.sh" >&2; exit 1; }

DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/NightWalker-$VERSION.dmg"

echo "==> Bundling app"
"$REPO_DIR/bundle.sh"
[[ -d "$APP" ]] || { echo "error: bundle.sh did not produce $APP" >&2; exit 1; }

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

echo "==> Staging DMG contents"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
mkdir -p "$DIST"
# UDZO = zlib-compressed read-only image. -ov overwrites an existing file.
hdiutil create \
    -volname "Night Walker" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

echo
echo "Built: $DMG"
ls -lh "$DMG"
