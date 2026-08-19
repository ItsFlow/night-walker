#!/usr/bin/env bash
# tests/run.sh — single entry for local / CI / no-mistakes
#
# Builds the debug binary once, then runs the contract suite. Never installs
# the app, never writes captain settings, never leaves Color Filters changed.
# Skips GUI-only --render-panel unless RUN_GUI=1.
#
# Env:
#   RUN_BUNDLE=1  (default) also run tests/bundle-contract.sh (release + codesign)
#   RUN_BUNDLE=0  skip packaging
#   RUN_GUI=1     also --render-panel (skipped by default)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RUN_BUNDLE="${RUN_BUNDLE:-1}"
RUN_GUI="${RUN_GUI:-0}"

nums_close() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        d = a - b
        if (d < 0) d = -d
        exit (d < 1e-9) ? 0 : 1
    }'
}

read_ma() {
    defaults read com.apple.mediaaccessibility "$1" 2>/dev/null || true
}

ORIG_ENABLED="$(read_ma "__Color__-MADisplayFilterCategoryEnabled")"
ORIG_INTENSITY="$(read_ma MADisplayFilterSingleColorIntensity)"
ORIG_TYPE="$(read_ma "__Color__-MADisplayFilterType")"
echo "run.sh: Color Filters snapshot enabled=${ORIG_ENABLED:-?} intensity=${ORIG_INTENSITY:-?} type=${ORIG_TYPE:-?}"

BIN=""
restore_color_filters() {
    if [ -z "${BIN:-}" ] || [ ! -x "${BIN:-}" ]; then
        return 0
    fi
    if [ -z "$ORIG_ENABLED" ] || [ -z "$ORIG_INTENSITY" ]; then
        return 0
    fi
    local en int
    en="$(read_ma "__Color__-MADisplayFilterCategoryEnabled")"
    int="$(read_ma MADisplayFilterSingleColorIntensity)"
    if [ "$en" = "$ORIG_ENABLED" ] && nums_close "${int:-0}" "$ORIG_INTENSITY"; then
        return 0
    fi
    echo "run.sh: restoring Color Filters (enabled=$ORIG_ENABLED intensity=$ORIG_INTENSITY)" >&2
    "$BIN" --set-enabled "$ORIG_ENABLED" >/dev/null || \
        echo "run.sh: ERROR restoring --set-enabled" >&2
    "$BIN" --set-intensity "$ORIG_INTENSITY" >/dev/null || \
        echo "run.sh: ERROR restoring --set-intensity" >&2
}

trap restore_color_filters EXIT INT TERM

echo "==> swift build (debug)"
swift build
BIN="$(swift build --show-bin-path)/color-filter-scheduler"
if [ ! -x "$BIN" ]; then
    echo "run.sh: debug binary missing at $BIN" >&2
    exit 1
fi
export BIN
echo "run.sh: BIN=$BIN"

passed=0
failed=0
failed_names=()

run_one() {
    local name="$1"
    shift
    echo
    echo "==> $name"
    if "$@"; then
        echo "PASS $name"
        passed=$((passed + 1))
    else
        echo "FAIL $name"
        failed=$((failed + 1))
        failed_names+=("$name")
    fi
}

run_one panel-contract sh tests/panel-contract.sh
run_one ui-contract sh tests/ui-contract.sh
run_one selftest "$BIN" --selftest
run_one cli-contract bash tests/cli-contract.sh
run_one hygiene bash tests/hygiene.sh

if [ "$RUN_BUNDLE" = "1" ]; then
    run_one bundle-contract bash tests/bundle-contract.sh
else
    echo
    echo "==> bundle-contract skipped (RUN_BUNDLE=$RUN_BUNDLE)"
fi

if [ "$RUN_GUI" = "1" ]; then
    run_one render-panel "$BIN" --render-panel .build/panel-render
else
    echo
    echo "==> --render-panel skipped (set RUN_GUI=1 to enable)"
fi

restore_color_filters

echo
echo "========================================"
echo "run.sh: $passed passed, $failed failed"
if [ "$failed" -ne 0 ]; then
    echo "failed: ${failed_names[*]}"
fi

en="$(read_ma "__Color__-MADisplayFilterCategoryEnabled")"
int="$(read_ma MADisplayFilterSingleColorIntensity)"
typ="$(read_ma "__Color__-MADisplayFilterType")"
echo "Color Filters after tests: enabled=$en intensity=$int type=$typ"
if [ -n "$ORIG_ENABLED" ] && [ "$en" != "$ORIG_ENABLED" ]; then
    echo "ERROR: Color Filters enabled drifted ($en != $ORIG_ENABLED)" >&2
    failed=$((failed + 1))
fi
if [ -n "$ORIG_INTENSITY" ] && ! nums_close "${int:-0}" "$ORIG_INTENSITY"; then
    echo "ERROR: Color Filters intensity drifted ($int != $ORIG_INTENSITY)" >&2
    failed=$((failed + 1))
fi
if [ -n "$ORIG_TYPE" ] && [ "$typ" != "$ORIG_TYPE" ]; then
    echo "ERROR: Color Filters type drifted ($typ != $ORIG_TYPE)" >&2
    failed=$((failed + 1))
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo "run.sh: all checks passed"
exit 0
