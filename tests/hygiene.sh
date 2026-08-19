#!/usr/bin/env bash
# hygiene: no committed secrets; no machine-local absolute paths in scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

# Collect source-like files, skipping build products and historical evidence dumps.
# Secret scan excludes EVIDENCE.md and docs/evidence/* (they can quote logs).
secret_files=()
while IFS= read -r f; do
    case "$f" in
        ./EVIDENCE.md|./docs/evidence/*) continue ;;
        ./.build/*|./dist/*|./.git/*) continue ;;
    esac
    secret_files+=("${f#./}")
done < <(find . \
    \( -path './.build' -o -path './dist' -o -path './.git' -o -path './docs/evidence' \) -prune -o \
    -type f \( \
        -name '*.swift' -o -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \
        -o -name '*.md' -o -name '*.template' -o -name '*.h' -o -name '*.c' \
        -o -name '*.plist' -o -name 'Package.swift' \
    \) -print | sort)

# AWS access key, PEM private keys, GitHub fine-grained PAT, Slack bot token.
# Split so this scanner file does not match itself.
secret_re="AKIA[0-9A-Z]{16}|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|github""_pat_|xox""b-"

secret_hits=0
if [ ${#secret_files[@]} -gt 0 ]; then
    for f in "${secret_files[@]}"; do
        [ -f "$f" ] || continue
        if grep -E -n -e "$secret_re" "$f" >/dev/null 2>&1; then
            grep -E -n -e "$secret_re" "$f" | while IFS= read -r line; do
                echo "FAIL: secret-like pattern in $f:$line"
            done
            secret_hits=$((secret_hits + 1))
        fi
    done
fi
if [ "$secret_hits" -eq 0 ]; then
    ok "no secret-like patterns in source files"
else
    fail "$secret_hits file(s) matched secret-like patterns"
fi

# Absolute machine-local paths: only scripts, Package.swift, LaunchAgent
# template, and .github — not docs/evidence historical logs.
# Split so this scanner file does not match itself.
user_path="$(printf '%s%s' '/Users/' 'flo')"
path_hits=0
scan_path() {
    local f="$1"
    [ -e "$f" ] || return 0
    if [ -d "$f" ]; then
        while IFS= read -r p; do
            if grep -n -e "$user_path" "$p" >/dev/null 2>&1; then
                grep -n -e "$user_path" "$p" | while IFS= read -r line; do
                    echo "FAIL: machine-local path in $p:$line"
                done
                path_hits=$((path_hits + 1))
            fi
        done < <(find "$f" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name '*.md' \) -print)
        return 0
    fi
    if grep -n -e "$user_path" "$f" >/dev/null 2>&1; then
        grep -n -e "$user_path" "$f" | while IFS= read -r line; do
            echo "FAIL: machine-local path in $f:$line"
        done
        path_hits=$((path_hits + 1))
    fi
}

while IFS= read -r shf; do
    scan_path "$shf"
done < <(find . \
    \( -path './.build' -o -path './dist' -o -path './.git' \) -prune -o \
    -type f -name '*.sh' -print | sort)

scan_path Package.swift
scan_path com.flo.color-filter-scheduler.plist.template
scan_path .github

if [ "$path_hits" -eq 0 ]; then
    ok "no machine-local /Users paths in scripts, Package.swift, LaunchAgent template, .github"
else
    fail "$path_hits file(s) contain a machine-local /Users path"
fi

if [ "$failures" -ne 0 ]; then
    echo "hygiene: $failures failure(s)"
    exit 1
fi
echo "hygiene: all checks passed"
