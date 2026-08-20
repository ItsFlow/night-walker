#!/usr/bin/env bash
#
# Reverse install.sh: unregister the login item, quit and remove Night Walker,
# and leave Color Filters OFF. UserDefaults settings live in the app's own
# domain; pass --purge-settings to remove them too.
#
# Refuses if the historical Color Filter Scheduler.app is still present — that
# app shares this bundle id.
set -euo pipefail

BUNDLE_ID="com.flo.color-filter-scheduler"
APP_NAME="Night Walker"
EXECUTABLE="color-filter-scheduler"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE"
LEGACY_APP="$HOME/Applications/Color Filter Scheduler.app"

PURGE=0
[[ "${1:-}" == "--purge-settings" ]] && PURGE=1

if [[ -d "$LEGACY_APP" ]]; then
    echo "error: refusing to uninstall/purge: $LEGACY_APP exists (shared bundle id $BUNDLE_ID)." >&2
    echo "  That is the captain live app; this script would alter its login item" >&2
    echo "  and --purge-settings would delete its preferences." >&2
    exit 1
fi

if [[ -d "$INSTALLED_APP" ]]; then
    BID="$(defaults read "$INSTALLED_APP/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    if [[ "$BID" != "$BUNDLE_ID" ]]; then
        echo "error: $INSTALLED_APP is not $BUNDLE_ID (id='${BID:-<empty>}'); not deleting." >&2
        exit 1
    fi
fi

echo "==> Unregistering main app login item"
if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --unregister-login-item
    pkill -f "$APP_BINARY" 2>/dev/null || true
fi

echo "==> Turning Color Filters OFF"
if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --set-enabled 0 || true
fi

echo "==> Removing files"
rm -rf "$INSTALLED_APP"

if [[ "$PURGE" == "1" ]]; then
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    echo "    removed saved settings ($BUNDLE_ID)"
else
    echo "    left saved settings in place (use --purge-settings to remove)."
fi

echo
echo "Uninstalled. Color Filters left OFF."
