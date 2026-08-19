#!/usr/bin/env bash
#
# Build + bundle + install the menu-bar app to ~/Applications and register it to
# launch at login (via a per-user LaunchAgent). Idempotent: safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.flo.color-filter-scheduler"
APP_NAME="Color Filter Scheduler"
EXECUTABLE="color-filter-scheduler"

APPS_DIR="$HOME/Applications"
INSTALLED_APP="$APPS_DIR/$APP_NAME.app"
APP_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENTS_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"

echo "==> Building app bundle"
"$REPO_DIR/bundle.sh"
BUILT_APP="$REPO_DIR/dist/$APP_NAME.app"

echo "==> Installing -> $INSTALLED_APP"
mkdir -p "$APPS_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$BUILT_APP" "$INSTALLED_APP"

echo "==> Writing LaunchAgent -> $PLIST"
mkdir -p "$AGENTS_DIR" "$LOG_DIR"
sed -e "s#__APP_BINARY__#$APP_BINARY#g" \
    -e "s#__LOGDIR__#$LOG_DIR#g" \
    "$REPO_DIR/$LABEL.plist.template" > "$PLIST"

echo "==> Loading agent (launch at login + start now)"
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo
echo "Installed. A menu-bar icon should appear now and at every login."
echo "  App   : $INSTALLED_APP"
echo "  Plist : $PLIST"
echo "  Logs  : $LOG_DIR/color-filter-scheduler.log"
echo
echo "Open the menu-bar icon, then:"
echo "  1. Press 'Run' to try the filter live (or 'Pause' to turn it off)."
echo "  2. Open 'Settings' (the header pill) to set latitude/longitude,"
echo "     adjust 'Strength', and turn on 'Automatic (sunset → sunrise)'."
echo
echo "To change the reconcile cadence, edit reconcileInterval in the source"
echo "(Sources/color-filter-scheduler/AppDelegate.swift) and re-run this script."
