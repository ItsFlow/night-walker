#!/usr/bin/env bash
#
# Build + bundle + install Night Walker to ~/Applications and register the
# bundled main app to launch at login. Idempotent: safe to re-run on a machine
# that does NOT already have the historical Color Filter Scheduler.app.
#
# The bundle id stays com.flo.color-filter-scheduler. That is the same domain as
# the captain's live install, so this script REFUSES if
# ~/Applications/Color Filter Scheduler.app exists unless you pass
# --replace-login-item.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="com.flo.color-filter-scheduler"
APP_NAME="Night Walker"
EXECUTABLE="color-filter-scheduler"
LEGACY_APP="$HOME/Applications/Color Filter Scheduler.app"

REPLACE_LOGIN=0
if [[ "${1:-}" == "--replace-login-item" ]]; then
    REPLACE_LOGIN=1
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--replace-login-item]" >&2
    exit 2
fi

APPS_DIR="$HOME/Applications"
INSTALLED_APP="$APPS_DIR/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LEGACY_BINARY="$LEGACY_APP/Contents/MacOS/$EXECUTABLE"

if [[ -d "$LEGACY_APP" && "$REPLACE_LOGIN" -ne 1 ]]; then
    echo "error: refusing to install: $LEGACY_APP exists." >&2
    echo "  It shares bundle id $BUNDLE_ID." >&2
    echo "  Friends should install from the DMG (drag to Applications)." >&2
    echo "  Pass --replace-login-item only if you intend to migrate this Mac." >&2
    exit 1
fi

echo "==> Building app bundle"
"$REPO_DIR/bundle.sh"
BUILT_APP="$REPO_DIR/dist/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || { echo "error: bundle.sh did not produce $BUILT_APP" >&2; exit 1; }

if [[ -f "$PLIST" ]]; then
    PLIST_BINARY="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST" 2>/dev/null || true)"
    if [[ "$PLIST_BINARY" != "$APP_BINARY" && "$PLIST_BINARY" != "$LEGACY_BINARY" ]]; then
        echo "error: refusing to remove unrelated LaunchAgent $PLIST" >&2
        exit 1
    fi
    echo "==> Removing managed legacy LaunchAgent"
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
    rm -f "$PLIST"
fi

echo "==> Installing -> $INSTALLED_APP"
mkdir -p "$APPS_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

echo "==> Registering main app with SMAppService"
"$APP_BINARY" --register-login-item
open "$INSTALLED_APP"

echo
echo "Installed. A menu-bar icon should appear now and at every login."
echo "  App   : $INSTALLED_APP"
echo "  Login : System Settings > General > Login Items"
echo
echo "Open the menu-bar icon, then:"
echo "  1. Press 'Run' to try the filter live (or 'Pause' to turn it off)."
echo "  2. Open Settings (the header gear) to set your city, adjust Strength,"
echo "     and turn on Automatic."
echo
echo "To change the reconcile cadence, edit reconcileInterval in the source"
echo "(Sources/color-filter-scheduler/AppDelegate.swift) and re-run this script."
