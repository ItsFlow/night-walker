#!/usr/bin/env bash
#
# Reverse install.sh: unload the login-item agent, quit and remove Night Walker,
# and leave Color Filters OFF. UserDefaults settings live in the app's own
# domain; pass --purge-settings to remove them too.
#
# Refuses if the historical Color Filter Scheduler.app is still present — that
# app shares this bundle id / LaunchAgent label.
set -euo pipefail

LABEL="com.flo.color-filter-scheduler"
APP_NAME="Night Walker"
EXECUTABLE="color-filter-scheduler"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
UID_NUM="$(id -u)"
LEGACY_APP="$HOME/Applications/Color Filter Scheduler.app"

PURGE=0
[[ "${1:-}" == "--purge-settings" ]] && PURGE=1

if [[ -d "$LEGACY_APP" ]]; then
    echo "error: refusing to uninstall/purge: $LEGACY_APP exists (shared bundle id $LABEL)." >&2
    echo "  That is the captain live app; this script would steal its login item" >&2
    echo "  and --purge-settings would delete its preferences." >&2
    exit 1
fi

if [[ -d "$INSTALLED_APP" ]]; then
    BID="$(defaults read "$INSTALLED_APP/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [[ "$BID" != "$LABEL" ]]; then
        echo "error: $INSTALLED_APP is not $LABEL (id='${BID:-<empty>}'); not deleting." >&2
        exit 1
    fi
fi

echo "==> Unloading login-item agent"
if [[ -f "$PLIST" ]] && grep -F -q "$APP_BINARY" "$PLIST"; then
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
else
    echo "    skipped bootout (plist missing or not pointing at $APP_BINARY)"
fi

echo "==> Turning Color Filters OFF"
if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --set-enabled 0 || true
fi

echo "==> Removing files"
if [[ -f "$PLIST" ]] && grep -F -q "$APP_BINARY" "$PLIST"; then
    rm -f "$PLIST"
fi
rm -rf "$INSTALLED_APP"
rm -f "$LOG_DIR/color-filter-scheduler.log" "$LOG_DIR/color-filter-scheduler.err.log"

if [[ "$PURGE" == "1" ]]; then
    defaults delete "$LABEL" 2>/dev/null || true
    echo "    removed saved settings ($LABEL)"
else
    echo "    left saved settings in place (use --purge-settings to remove)."
fi

echo
echo "Uninstalled. Color Filters left OFF."
