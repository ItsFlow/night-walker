#!/usr/bin/env bash
# CLI contract: read-only commands must not touch Color Filters; mutating
# commands restore via the unpackaged .build binary (SPI, not defaults write).
# Never invokes ~/Applications. Never writes com.flo.color-filter-scheduler.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "${BIN:-}" ]; then
    echo "cli-contract: BIN is unset (run via tests/run.sh, or export BIN=)" >&2
    exit 1
fi
if [ ! -x "$BIN" ]; then
    echo "cli-contract: BIN is not executable: $BIN" >&2
    exit 1
fi

# Refuse to talk to the installed app even if someone exports the wrong BIN.
case "$BIN" in
    "$HOME/Applications"/*)
        echo "cli-contract: refusing installed app at $BIN" >&2
        exit 1
        ;;
esac

failures=0
OUT="$(mktemp)"
ERR="$(mktemp)"
APP_SNAP="$(mktemp)"
MA_SNAP="$(mktemp)"
APP_DOMAIN="com.flo.color-filter-scheduler"

ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

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
defaults read com.apple.mediaaccessibility >"$MA_SNAP" 2>/dev/null || true

HAD_APP=0
if defaults read "$APP_DOMAIN" >"$APP_SNAP" 2>/dev/null; then
    HAD_APP=1
fi

RESTORED=0
restore_color_filters() {
    if [ "$RESTORED" = "1" ]; then
        return 0
    fi
    RESTORED=1
    if [ -z "$ORIG_ENABLED" ] || [ -z "$ORIG_INTENSITY" ]; then
        echo "cli-contract: no original Color Filters snapshot; skip restore" >&2
        return 0
    fi
    "$BIN" --set-enabled "$ORIG_ENABLED" >/dev/null || \
        echo "cli-contract: ERROR restoring --set-enabled $ORIG_ENABLED" >&2
    "$BIN" --set-intensity "$ORIG_INTENSITY" >/dev/null || \
        echo "cli-contract: ERROR restoring --set-intensity $ORIG_INTENSITY" >&2
}

verify_color_filters() {
    local en int typ
    en="$(read_ma "__Color__-MADisplayFilterCategoryEnabled")"
    int="$(read_ma MADisplayFilterSingleColorIntensity)"
    typ="$(read_ma "__Color__-MADisplayFilterType")"
    if [ "$en" != "$ORIG_ENABLED" ]; then
        fail "Color Filters enabled restored ($en != $ORIG_ENABLED)"
        return 1
    fi
    if [ -n "$ORIG_TYPE" ] && [ "$typ" != "$ORIG_TYPE" ]; then
        fail "Color Filters type restored ($typ != $ORIG_TYPE)"
        return 1
    fi
    if ! nums_close "$int" "$ORIG_INTENSITY"; then
        fail "Color Filters intensity restored ($int != $ORIG_INTENSITY)"
        return 1
    fi
    ok "Color Filters restored (enabled=$en intensity=$int type=$typ)"
    return 0
}

check_app_untouched() {
    local after
    after="$(mktemp)"
    if [ "$HAD_APP" = "1" ]; then
        if ! defaults read "$APP_DOMAIN" >"$after" 2>/dev/null; then
            fail "captain settings domain $APP_DOMAIN disappeared"
            rm -f "$after"
            return 1
        fi
        if ! cmp -s "$APP_SNAP" "$after"; then
            fail "captain settings $APP_DOMAIN changed (tests must not persist)"
            diff -u "$APP_SNAP" "$after" || true
            rm -f "$after"
            return 1
        fi
        ok "captain settings $APP_DOMAIN unchanged"
    else
        if defaults read "$APP_DOMAIN" >"$after" 2>/dev/null; then
            fail "captain settings $APP_DOMAIN was created"
            rm -f "$after"
            return 1
        fi
        ok "captain settings $APP_DOMAIN still absent"
    fi
    rm -f "$after"
    return 0
}

cleanup() {
    local rc=$?
    restore_color_filters
    verify_color_filters || rc=1
    check_app_untouched || rc=1
    rm -f "$OUT" "$ERR" "$APP_SNAP" "$MA_SNAP"
    trap - EXIT INT TERM
    exit "$rc"
}
trap cleanup EXIT INT TERM

expect_exit() {
    local want="$1"
    shift
    set +e
    "$@" >"$OUT" 2>"$ERR"
    local st=$?
    set -e
    if [ "$st" -eq "$want" ]; then
        ok "$* (exit $want)"
    else
        fail "$* (exit $st, want $want)"
        if [ -s "$ERR" ]; then sed 's/^/    stderr: /' "$ERR"; fi
        if [ -s "$OUT" ]; then sed 's/^/    stdout: /' "$OUT"; fi
    fi
}

contains() {
    local needle="$1"
    if grep -F -q -- "$needle" "$OUT"; then
        ok "output contains '$needle'"
    else
        fail "output missing '$needle'"
        sed 's/^/    stdout: /' "$OUT"
    fi
}

# --- read-only ---
expect_exit 0 "$BIN" --get
expect_exit 2 "$BIN" --decide
expect_exit 2 "$BIN" --decide --lat 91 --lon 0
expect_exit 2 "$BIN" --decide --lat 999 --lon 0
expect_exit 2 "$BIN" --decide --lat nan --lon 0
expect_exit 2 "$BIN" --decide --lat inf --lon 0
expect_exit 2 "$BIN" --decide --lat 48.137 --lon 11.575 --now not-a-date
expect_exit 0 "$BIN" --decide --lat 48.137 --lon 11.575
contains "decision:"

expect_exit 0 "$BIN" --help
contains "--now"

expect_exit 0 "$BIN" --decide --lat 48.137 --lon 11.575 --now 2026-08-18T12:00:00Z
contains "want OFF"

expect_exit 0 "$BIN" --decide --lat 48.137 --lon 11.575 --now 2026-08-18T22:15:00Z
contains "want ON"

expect_exit 2 "$BIN" --decide --lat 48.137 --lon 11.575 --sr-off nan
expect_exit 2 "$BIN" --set-intensity nan
expect_exit 2 "$BIN" --set-intensity inf
expect_exit 2 "$BIN" --set-intensity 1.5
expect_exit 2 "$BIN" --set-intensity -0.1
expect_exit 2 "$BIN" --render-panel /tmp/cfs-render-panel-test
mkdir -p .build
ESCAPE_LINK=".build/cfs-render-escape"
rm -f "$ESCAPE_LINK"
ln -s /tmp "$ESCAPE_LINK"
expect_exit 2 "$BIN" --render-panel "$ESCAPE_LINK"
rm -f "$ESCAPE_LINK"

expect_exit 0 "$BIN" --decide --lat 80 --lon 15 --now 2026-06-21T12:00:00Z
contains "polar day"
contains "want OFF"

expect_exit 0 "$BIN" --reconcile --lat 48.137 --lon 11.575 --now 2026-08-18T12:00:00Z
# no --apply: still read-only

MA_AFTER="$(mktemp)"
defaults read com.apple.mediaaccessibility >"$MA_AFTER" 2>/dev/null || true
if cmp -s "$MA_SNAP" "$MA_AFTER"; then
    ok "--get/--decide/--reconcile (no --apply) left com.apple.mediaaccessibility identical"
else
    fail "read-only commands mutated com.apple.mediaaccessibility"
    diff -u "$MA_SNAP" "$MA_AFTER" || true
fi
rm -f "$MA_AFTER"

# NSArgumentDomain on the unpackaged binary. Command must start with --engine-status
# so CLI.swift does not fall through to the GUI (--flag parsing vs -key value).
expect_exit 0 "$BIN" --engine-status -automationEnabled 0
contains "automationEnabled=false"
contains "fail-safe"

# --- live toggle (minimal): one flip + restore ---
# Skip on a clean machine (e.g. GitHub Actions) where Color Filters prefs
# were never created. Mutating then would leave a preference we cannot
# restore from an empty snapshot.
if [ -z "$ORIG_ENABLED" ] || [ -z "$ORIG_INTENSITY" ]; then
    echo "note: skipping live Color Filters mutation (no pre-existing preference)"
else
    if [ "$ORIG_ENABLED" = "1" ]; then
        FLIP_TO=0
    else
        FLIP_TO=1
    fi
    expect_exit 0 "$BIN" --set-enabled "$FLIP_TO"
    NOW_EN="$(read_ma "__Color__-MADisplayFilterCategoryEnabled")"
    if [ "$NOW_EN" = "$FLIP_TO" ]; then
        ok "--set-enabled $FLIP_TO applied live"
    else
        fail "--set-enabled $FLIP_TO did not apply (now $NOW_EN)"
    fi
    restore_color_filters
    RESTORED=0  # allow a second restore after reconcile
    verify_color_filters || true

    # --reconcile --apply with --now frozen so wantOn matches the restored
    # state. Restore is still mandatory in case the engine disagrees.
    if [ "$ORIG_ENABLED" = "1" ]; then
        APPLY_NOW="2026-08-18T22:15:00Z"  # Munich night → want ON
    else
        APPLY_NOW="2026-08-18T12:00:00Z"  # Munich day → want OFF
    fi
    expect_exit 0 "$BIN" --reconcile --lat 48.137 --lon 11.575 --now "$APPLY_NOW" --apply
    restore_color_filters
    verify_color_filters || true
fi

check_app_untouched || true

if [ "$failures" -ne 0 ]; then
    echo "cli-contract: $failures failure(s)"
    exit 1
fi
echo "cli-contract: all checks passed"
