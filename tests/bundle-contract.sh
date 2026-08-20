#!/usr/bin/env bash
# bundle-contract: ./bundle.sh produces a signed .app with the historical
# identifier com.flo.color-filter-scheduler.
#
# The shipped executable must be universal (x86_64 + arm64).
#
# Does not install. Does not touch ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

if [ ! -x ./bundle.sh ]; then
    echo "bundle-contract: ./bundle.sh missing or not executable" >&2
    exit 1
fi

./bundle.sh

shopt -s nullglob
apps=(dist/*.app)
shopt -u nullglob
if [ ${#apps[@]} -eq 0 ]; then
    echo "FAIL: bundle.sh produced no dist/*.app"
    exit 1
fi
# Prefer the most recently modified bundle if several names coexist.
APP="$(ls -td dist/*.app | head -1)"
echo "bundle-contract: inspecting $APP"

if [ ! -d "$APP" ]; then
    fail "bundle path is not a directory: $APP"
    echo "bundle-contract: $failures failure(s)"
    exit 1
fi

if codesign --verify --verbose=1 "$APP"; then
    ok "codesign --verify"
else
    fail "codesign --verify"
fi

IDENT="$(codesign -d --verbose=2 "$APP" 2>&1 | awk -F= '/^Identifier=/{print $2; exit}')"
if [ "$IDENT" = "com.flo.color-filter-scheduler" ]; then
    ok "codesign identifier is com.flo.color-filter-scheduler"
else
    fail "codesign identifier is '${IDENT:-<empty>}' (want com.flo.color-filter-scheduler)"
fi

INFO="$APP/Contents/Info.plist"
if [ -f "$INFO" ]; then
    PLIST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null || true)"
    if [ "$PLIST_ID" = "com.flo.color-filter-scheduler" ]; then
        ok "Info.plist CFBundleIdentifier is com.flo.color-filter-scheduler"
    else
        fail "Info.plist CFBundleIdentifier is '${PLIST_ID:-<empty>}'"
    fi
    EXEC_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO" 2>/dev/null || echo color-filter-scheduler)"
else
    fail "Info.plist missing"
    EXEC_NAME="color-filter-scheduler"
fi

EXEC="$APP/Contents/MacOS/$EXEC_NAME"
if [ ! -x "$EXEC" ]; then
    fail "missing executable $EXEC"
    echo "bundle-contract: $failures failure(s)"
    exit 1
fi

LIPO_INFO="$(lipo -info "$EXEC" 2>/dev/null || echo "")"
echo "note: $LIPO_INFO"

has_x86=0
has_arm=0
case "$LIPO_INFO" in *x86_64*) has_x86=1 ;; esac
case "$LIPO_INFO" in *arm64*) has_arm=1 ;; esac

if [ "$has_x86" = "1" ] && [ "$has_arm" = "1" ]; then
    ok "universal binary (x86_64 + arm64)"
else
    fail "$EXEC is not universal x86_64+arm64"
fi

if otool -L "$EXEC" | awk '{print $1}' | grep -q '/ServiceManagement.framework/'; then
    ok "executable links ServiceManagement for launch at login"
else
    fail "executable does not link ServiceManagement"
fi

if [ "$failures" -ne 0 ]; then
    echo "bundle-contract: $failures failure(s)"
    exit 1
fi
echo "bundle-contract: all checks passed"
