#!/usr/bin/env bash
#
# Reverse install.sh: unload the login-item agent, quit and remove the app, and
# leave Color Filters OFF. UserDefaults settings live in the app's own domain;
# pass --purge-settings to remove them too.
set -euo pipefail

LABEL="com.flo.color-filter-scheduler"
APP_NAME="Color Filter Scheduler"
EXECUTABLE="color-filter-scheduler"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
UID_NUM="$(id -u)"

PURGE=0
[[ "${1:-}" == "--purge-settings" ]] && PURGE=1

echo "==> Unloading login-item agent"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "==> Turning Color Filters OFF"
if [[ -x "$APP_BINARY" ]]; then
    "$APP_BINARY" --set-enabled 0 || true
fi

echo "==> Removing files"
rm -f "$PLIST"
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
