#!/bin/sh
set -eu

source_file="Sources/color-filter-scheduler/AppDelegate.swift"
failures=0

# rg is nicer locally; grep -F is what GitHub Actions macos-latest has.
grep_fixed() {
    pattern="$1"
    file="$2"
    if command -v rg >/dev/null 2>&1; then
        rg -q --fixed-strings "$pattern" "$file"
    else
        grep -F -q "$pattern" "$file"
    fi
}

require_absent() {
    pattern="$1"
    description="$2"
    if grep_fixed "$pattern" "$source_file"; then
        echo "FAIL: $description"
        failures=$((failures + 1))
    else
        echo "ok: $description"
    fi
}

require_present() {
    pattern="$1"
    description="$2"
    if grep_fixed "$pattern" "$source_file"; then
        echo "ok: $description"
    else
        echo "FAIL: $description"
        failures=$((failures + 1))
    fi
}

require_absent 'NSPopover' 'popover presentation removed'
require_absent 'addGlobalMonitorForEvents' 'global mouse monitor removed'
require_absent 'clickShouldDismiss' 'raw frame hit-test removed'
require_absent '.leftMouseDown' 'inside mouse-down cannot call the close path'
require_absent '.rightMouseDown' 'inside right mouse-down cannot call the close path'
require_absent '.otherMouseDown' 'inside other mouse-down cannot call the close path'
require_present 'final class StatusPanel: NSPanel' 'presentation is an NSPanel'
require_present 'override var canBecomeKey: Bool { true }' 'borderless panel can become key'
require_present 'styleMask: [.borderless, .nonactivatingPanel]' 'panel is borderless and nonactivating'
require_present 'becomesKeyOnlyIfNeeded = false' 'text and slider interactions keep the panel key'
require_present 'func windowDidResignKey' 'outside click dismisses through key resignation'
require_present 'if event.keyCode == 53' 'Esc has an explicit dismissal path'

if [ "$failures" -ne 0 ]; then
    echo "panel-contract: $failures failure(s)"
    exit 1
fi

echo "panel-contract: all checks passed"
