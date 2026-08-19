#!/bin/sh
set -eu

source_file="Sources/color-filter-scheduler/AppDelegate.swift"
failures=0

require_absent() {
    pattern="$1"
    description="$2"
    if rg -q --fixed-strings "$pattern" "$source_file"; then
        echo "FAIL: $description"
        failures=$((failures + 1))
    else
        echo "ok: $description"
    fi
}

require_present() {
    pattern="$1"
    description="$2"
    if rg -q --fixed-strings "$pattern" "$source_file"; then
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
