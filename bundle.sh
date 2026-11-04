#!/usr/bin/env bash
#
# Assemble a proper LSUIElement (.app) menu-bar bundle from the SwiftPM release
# build and ad-hoc sign it. This is the standard CLT-only, no-Xcode pattern:
# release build -> hand-assembled .app -> codesign -s -.
#
# Output: ./dist/Night Walker.app
# Bundle id stays com.flo.color-filter-scheduler (historical).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Night Walker"
BUNDLE_ID="com.flo.color-filter-scheduler"
EXECUTABLE="color-filter-scheduler"
VERSION="1.0.2"

DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"

# Universal (Apple Silicon + Intel) so one download works on every Mac.
# `--arch a --arch b` needs Xcode's xcbuild, so build each triple and lipo.
cd "$REPO_DIR"
SLICES=()
for arch in arm64 x86_64; do
    triple="$arch-apple-macosx13.0"
    echo "==> Building $triple (swift build -c release)…"
    swift build -c release --triple "$triple"
    slice="$(swift build -c release --triple "$triple" --show-bin-path)/$EXECUTABLE"
    [[ -x "$slice" ]] || { echo "error: build did not produce $slice" >&2; exit 1; }
    SLICES+=("$slice")
done
BUILT="$REPO_DIR/.build/$EXECUTABLE-universal"
lipo -create "${SLICES[@]}" -output "$BUILT"
lipo -info "$BUILT"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILT" "$APP/Contents/MacOS/$EXECUTABLE"

echo "==> Rendering app icon (.icns)"
ICON_TMP="$(mktemp -d)"
cleanup_icon_tmp() {
    # Delete only the exact directory mktemp created for this run.
    if [[ -n "${ICON_TMP:-}" && -d "$ICON_TMP" ]]; then
        rm -rf -- "$ICON_TMP"
    fi
}
trap cleanup_icon_tmp EXIT
ICONSET="$ICON_TMP/AppIcon.iconset"
swift "$REPO_DIR/tools/make-appicon.swift" "$ICONSET"
if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
    ICON_KEY='    <key>CFBundleIconFile</key>        <string>AppIcon</string>'
else
    echo "warning: iconutil failed; bundling without .icns" >&2
    ICON_KEY=''
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$EXECUTABLE</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
$ICON_KEY
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Menu-bar-only agent: no Dock icon, no main window. -->
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

# Marker so bundled-app UserDefaults/domain is unambiguous.
printf 'APPL????' > "$APP/Contents/PkgInfo"

# NW_SIGN_IDENTITY="Developer ID Application: …" signs for notarization
# (hardened runtime + secure timestamp). Unset = ad-hoc, which runs locally but
# is blocked by Gatekeeper when downloaded (see make-dmg.sh).
if [[ -n "${NW_SIGN_IDENTITY:-}" ]]; then
    echo "==> Signing with Developer ID"
    codesign --force --options runtime --timestamp --sign "$NW_SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "==> Ad-hoc signing"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

echo
echo "Built: $APP"
echo "Run it directly with:  open \"$APP\""
