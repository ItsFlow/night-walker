#!/bin/sh
set -eu

source_file="Sources/color-filter-scheduler/PanelView.swift"
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

require_absent 'Text("Strength")' 'no Strength heading'
require_absent 'Text("Location")' 'no Location heading'
require_absent 'Text("Settings")' 'no Settings text label'
require_absent 'Follow the sun' 'no Automatic explanation'
require_absent 'Precise override' 'no latitude/longitude explanation'
require_present 'TextField("Your location"' 'location label is an in-field placeholder'
require_present 'Image(systemName: "gearshape")' 'settings affordance is a gear icon'

if [ "$failures" -ne 0 ]; then
    echo "ui-contract: $failures failure(s)"
    exit 1
fi

echo "ui-contract: all checks passed"
