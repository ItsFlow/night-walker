#!/usr/bin/env bash
#
# Assemble a proper LSUIElement (.app) menu-bar bundle from the SwiftPM release
# build and ad-hoc sign it. This is the standard CLT-only, no-Xcode pattern:
# release build -> hand-assembled .app -> codesign -s -.
#
# Output: ./dist/Color Filter Scheduler.app
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Color Filter Scheduler"
BUNDLE_ID="com.flo.color-filter-scheduler"
EXECUTABLE="color-filter-scheduler"
VERSION="1.0.0"

DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building (swift build -c release)…"
cd "$REPO_DIR"
swift build -c release
BUILT="$REPO_DIR/.build/release/$EXECUTABLE"
[[ -x "$BUILT" ]] || { echo "error: build did not produce $BUILT" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILT" "$APP/Contents/MacOS/$EXECUTABLE"

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
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"

echo
echo "Built: $APP"
echo "Run it directly with:  open \"$APP\""
