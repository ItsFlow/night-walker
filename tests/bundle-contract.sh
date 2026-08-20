#!/usr/bin/env bash
# Behavioral check for icon generation failures and bundle.sh temp cleanup.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

failures=0
pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# --- make-appicon: success writes 10 PNGs ---
icon_ok="$(mktemp -d)"
if swift "$REPO_DIR/tools/make-appicon.swift" "$icon_ok/AppIcon.iconset"; then
    pngs="$(find "$icon_ok/AppIcon.iconset" -name '*.png' | wc -l | tr -d ' ')"
    if [[ "$pngs" == "10" ]]; then
        pass "make-appicon writes 10 PNGs"
    else
        fail "make-appicon wrote $pngs PNGs, expected 10"
    fi
else
    fail "make-appicon success path exited nonzero"
fi
rm -rf "$icon_ok"

# --- make-appicon: unwritable output fails visibly ---
blocker="$(mktemp)"
if swift "$REPO_DIR/tools/make-appicon.swift" "$blocker/AppIcon.iconset" >/tmp/cfs-icon-fail.out 2>/tmp/cfs-icon-fail.err; then
    fail "make-appicon succeeded against a file path (expected failure)"
else
    if [[ -s /tmp/cfs-icon-fail.err ]]; then
        pass "make-appicon unwritable output fails with stderr"
    else
        fail "make-appicon failed but wrote no stderr"
    fi
fi
rm -f "$blocker" /tmp/cfs-icon-fail.out /tmp/cfs-icon-fail.err

# --- bundle.sh EXIT trap removes the exact mktemp icon dir ---
wrap="$(mktemp -d)"
recorded="$wrap/mktemp-path"
cat > "$wrap/mktemp" <<'EOF'
#!/bin/sh
if [ "$1" = "-d" ]; then
    d="$(/usr/bin/mktemp -d)"
    echo "$d" >> "${CFS_MKTEMP_LOG:?}"
    printf '%s\n' "$d"
    exit 0
fi
exec /usr/bin/mktemp "$@"
EOF
chmod +x "$wrap/mktemp"

export CFS_MKTEMP_LOG="$recorded"
PATH="$wrap:$PATH" "$REPO_DIR/bundle.sh"
if [[ ! -s "$recorded" ]]; then
    fail "bundle.sh did not call mktemp -d"
else
    leaked=0
    while IFS= read -r dir; do
        # swift build may also call mktemp -d; only the icon dir contains AppIcon.iconset.
        if [[ -d "$dir/AppIcon.iconset" ]]; then
            leaked=1
            echo "  leftover icon dir: $dir"
        fi
    done < "$recorded"
    if [[ "$leaked" -eq 0 ]]; then
        pass "bundle.sh EXIT trap removed the mktemp icon directory"
    else
        fail "bundle.sh left its mktemp icon directory behind"
    fi
fi
rm -rf "$wrap"

if [[ "$failures" -ne 0 ]]; then
    echo "bundle-contract: $failures failure(s)"
    exit 1
fi
echo "bundle-contract: all checks passed"
