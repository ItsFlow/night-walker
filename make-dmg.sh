#!/usr/bin/env bash
#
# Build the downloadable disk image: dist/NightWalker-<version>.dmg with the
# app, an Applications shortcut and a short "how to open" note.
#
# Without a Developer ID the app is ad-hoc signed and NOT notarized, so macOS
# blocks the first open of a downloaded copy ("Apple could not verify…").
# The note in the DMG walks through Open Anyway. To ship a copy that opens with
# no warning, set both:
#   NW_SIGN_IDENTITY="Developer ID Application: <name> (<team>)"
#   NW_NOTARY_PROFILE=<profile saved with `xcrun notarytool store-credentials`>
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Night Walker"
cd "$REPO_DIR"

"$REPO_DIR/bundle.sh"
APP="$REPO_DIR/dist/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$REPO_DIR/dist/NightWalker-$VERSION.dmg"

STAGE="$(mktemp -d)"
cleanup_stage() {
    if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi
}
trap cleanup_stage EXIT

ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
# The Open Anyway note is only true for a build that is not notarized.
if [[ -z "${NW_SIGN_IDENTITY:-}" || -z "${NW_NOTARY_PROFILE:-}" ]]; then
cat > "$STAGE/If macOS blocks it.txt" <<'NOTE'
Night Walker is a free app that is not notarized by Apple, so the first time
you open it macOS says it "could not verify" it. That is expected.

1. Drag Night Walker into Applications.
2. Open it from Applications. When the warning appears, click Done.
3. Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to Night Walker. Enter your password, then Open.

You only do this once. Night Walker then lives in the menu bar (the eclipse
icon, no Dock icon) and starts again at every login.

Source: https://github.com/ItsFlow/night-walker
NOTE
fi

rm -f "$DMG"
echo "==> Creating $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${NW_SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$NW_SIGN_IDENTITY" "$DMG"
    if [[ -n "${NW_NOTARY_PROFILE:-}" ]]; then
        echo "==> Notarizing (this waits for Apple)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NW_NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

hdiutil verify "$DMG" >/dev/null
echo
echo "Built: $DMG"
shasum -a 256 "$DMG"
