#!/usr/bin/env bash
#
# Assemble a proper LSUIElement (.app) menu-bar bundle from a universal
# (x86_64 + arm64) SwiftPM release build and ad-hoc sign it. This is the
# standard CLT-only, no-Xcode pattern: dual-arch release build -> lipo ->
# hand-assembled .app -> codesign -s -.
#
# Output: ./dist/Night Walker.app
# Public name is Night Walker; executable / package / bundle id stay
# color-filter-scheduler / com.flo.color-filter-scheduler.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Night Walker"
BUNDLE_ID="com.flo.color-filter-scheduler"
EXECUTABLE="color-filter-scheduler"
VERSION="1.0.0"

DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"

find_arch_bin() {
    local arch="$1"
    local candidates=(
        "$REPO_DIR/.build/${arch}-apple-macosx/release/$EXECUTABLE"
        "$REPO_DIR/.build/${arch}-apple-macos/release/$EXECUTABLE"
    )
    local p
    for p in "${candidates[@]}"; do
        if [[ -x "$p" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    echo "error: no $arch release binary after swift build --arch $arch" >&2
    echo "looked for:" >&2
    for p in "${candidates[@]}"; do
        echo "  $p" >&2
    done
    echo ".build layout:" >&2
    ls -la "$REPO_DIR/.build" >&2 || true
    return 1
}

echo "==> Building universal release (arm64 + x86_64)…"
cd "$REPO_DIR"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM_BIN="$(find_arch_bin arm64)"
X86_BIN="$(find_arch_bin x86_64)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> lipo $ARM_BIN + $X86_BIN"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"
lipo -info "$APP/Contents/MacOS/$EXECUTABLE"

echo "==> Rendering app icon (.icns)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
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

echo "==> Ad-hoc signing"
# Ad-hoc only (no paid cert). Do not add --options runtime / Hardened Runtime.
# --deep is unnecessary here (no nested code) and Apple-discouraged for shipping.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"

echo
echo "Built: $APP"
echo "Run it directly with:  open \"$APP\""
